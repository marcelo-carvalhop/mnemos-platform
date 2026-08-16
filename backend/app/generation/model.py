"""The model call (§7.4, §7.5, §10).

Everything the spike measured lives here: the cacheable system prefix, the
structured-output schema, `effort: medium`, and refusal handling. The spike is
in `spikes/generation/` and is not imported — it answered its questions and
stays as the record of how these choices were made.

The call itself is isolated from `service.py` on purpose. `service.py` owns the
database and the quota, and is tested without a network; this module owns the
network and returns a `GeneratedCards`, which is the only thing that crosses
between them.
"""

from __future__ import annotations

import base64
import json
import logging

import anthropic

from app.contract import BACK_MAX_GRAPHEMES, FRONT_MAX_GRAPHEMES

from .service import GeneratedCards

logger = logging.getLogger(__name__)

MODEL = "claude-opus-5"

# Measured in the spike: `effort: high` cost 94% more, ran 68% slower, and
# produced no better cards.
EFFORT = "medium"

MAX_TOKENS = 8000

# The cacheable prefix (§7.4). `level` and the requested count are deliberately
# NOT here — caching is a prefix match, so a value that varies per request
# inside the prefix means the cache is written every time and never read.
SYSTEM_PROMPT = f"""Você cria flashcards de estudo em português do Brasil para \
um app de repetição espaçada.

REGRAS ABSOLUTAS DE TAMANHO
- A frente deve ter no máximo {FRONT_MAX_GRAPHEMES} caracteres.
- O verso deve ter no máximo {BACK_MAX_GRAPHEMES} caracteres.
- Conte caracteres como o usuário os vê. Cards que excedem são descartados.

QUALIDADE PEDAGÓGICA
- Um card testa exatamente UMA ideia. Nunca agrupe fatos independentes.
- A frente é uma pergunta direta ou um termo a definir, nunca um enunciado vago.
- O verso é a resposta mínima suficiente: sem preâmbulo, sem repetir a pergunta,
  sem "trata-se de" ou "refere-se a".
- Prefira perguntas que exijam recuperação ativa a perguntas de sim/não.
- Não crie cards sobre metadados do material (título, autor, número de página).

QUANDO NÃO GERAR
- Se o tópico for vago demais para produzir cards específicos e verificáveis,
  responda com status "needs_specification" e explique em uma frase o que
  precisa ser especificado. Não invente escopo.

TAGS
- Uma a três tags curtas em minúsculas por card, sem acentos, sem espaços.
"""

SCHEMA = {
    "type": "object",
    "properties": {
        "status": {"type": "string", "enum": ["ok", "needs_specification"]},
        "reason": {
            "type": "string",
            "description": "Preenchido apenas quando status é needs_specification.",
        },
        "cards": {
            "type": "array",
            "items": {
                "type": "object",
                "properties": {
                    "front": {"type": "string"},
                    "back": {"type": "string"},
                    "tags": {"type": "array", "items": {"type": "string"}},
                },
                "required": ["front", "back", "tags"],
                "additionalProperties": False,
            },
        },
    },
    "required": ["status", "reason", "cards"],
    "additionalProperties": False,
}


class ModelUnavailable(Exception):
    """The call could not be made or completed. Distinct from a refusal.

    §7.7: infrastructure failure returns the allowance; the user spending it is
    what consumes it. With one generation per lifetime, confusing the two takes
    away the only one they had.
    """


def build_content(
    *,
    level: str,
    requested_count: int,
    topic: str | None = None,
    material: str | None = None,
    pdf: bytes | None = None,
    images: list[tuple[str, bytes]] | None = None,
) -> list[dict]:
    """Assembles the user turn.

    Documents and images come first, then the instruction — the model reads
    the material before being told what to do with it.
    """
    instruction = f"Nível: {level}.\nGere {requested_count} flashcards."
    content: list[dict] = []

    if pdf is not None:
        # §7.1: native PDF, no OCR stage. The spike confirmed this on a scanned
        # file containing no /Font object at all.
        content.append(
            {
                "type": "document",
                "source": {
                    "type": "base64",
                    "media_type": "application/pdf",
                    "data": base64.standard_b64encode(pdf).decode(),
                },
            }
        )
        content.append({"type": "text", "text": f"{instruction}\nBaseie-se no documento acima."})
    elif images:
        for media_type, data in images:
            content.append(
                {
                    "type": "image",
                    "source": {
                        "type": "base64",
                        "media_type": media_type,
                        "data": base64.standard_b64encode(data).decode(),
                    },
                }
            )
        content.append({"type": "text", "text": f"{instruction}\nBaseie-se nas imagens acima."})
    elif material:
        content.append({"type": "text", "text": f"Material:\n\n{material}\n\n{instruction}"})
    else:
        content.append({"type": "text", "text": f"Tópico: {topic}\n\n{instruction}"})

    return content


def generate(client: anthropic.Anthropic, content: list[dict]) -> GeneratedCards:
    """One call, one `GeneratedCards`.

    Raises [ModelUnavailable] for anything that is not an answer. A refusal is
    an answer — HTTP 200 with `stop_reason: "refusal"` — and comes back as a
    populated result, because §10 requires the user to be told which of the two
    happened.
    """
    try:
        response = client.messages.create(
            model=MODEL,
            max_tokens=MAX_TOKENS,
            system=[
                {
                    "type": "text",
                    "text": SYSTEM_PROMPT,
                    "cache_control": {"type": "ephemeral"},
                }
            ],
            output_config={
                "effort": EFFORT,
                "format": {"type": "json_schema", "schema": SCHEMA},
            },
            messages=[{"role": "user", "content": content}],
        )
    except anthropic.APIError as exc:
        raise ModelUnavailable(f"{type(exc).__name__}: {exc}") from exc

    return parse(response)


def parse(response: object) -> GeneratedCards:
    """Turns a Messages response into a `GeneratedCards`.

    Split out from [generate] so the mapping — including the refusal path,
    which is awkward to provoke on purpose — is testable without a network.

    Structured output arrives as JSON **inside a text block**, and the refusal
    category lives on `stop_details`. Both are as the wave 0 spike recorded
    them against the live API; neither is guessed.
    """
    usage = getattr(response, "usage", None)
    tokens_in = getattr(usage, "input_tokens", 0) or 0
    tokens_out = getattr(usage, "output_tokens", 0) or 0
    # Not part of input_tokens, and not the same price (§7.4).
    cache_read = getattr(usage, "cache_read_input_tokens", 0) or 0
    cache_write = getattr(usage, "cache_creation_input_tokens", 0) or 0

    stop_reason = getattr(response, "stop_reason", None)
    if stop_reason == "refusal":
        # §10 — a refusal is HTTP 200, not an exception. Code that reads
        # content[0] without checking this crashes on it. Nothing is billed
        # before output, so the caller refunds.
        details = getattr(response, "stop_details", None)
        return GeneratedCards(
            status="refused",
            cards=[],
            tokens_in=tokens_in,
            tokens_out=tokens_out,
            cache_read=cache_read,
            cache_write=cache_write,
            refused=True,
            refusal_category=str(getattr(details, "category", "") or "unknown"),
        )

    if stop_reason == "max_tokens":
        # Structured output truncated mid-object is not partially usable, and
        # billing the user for an unparseable answer would be wrong.
        raise ModelUnavailable("response hit max_tokens before completing")

    text = next(
        (
            block.text
            for block in getattr(response, "content", []) or []
            if getattr(block, "type", None) == "text"
        ),
        "",
    )
    if not text:
        raise ModelUnavailable("no text block in response")

    try:
        payload = json.loads(text)
    except json.JSONDecodeError as exc:
        raise ModelUnavailable(f"invalid JSON in response: {exc}") from exc

    return GeneratedCards(
        status=str(payload.get("status") or "ok"),
        cards=list(payload.get("cards") or []),
        reason=str(payload.get("reason") or ""),
        tokens_in=tokens_in,
        tokens_out=tokens_out,
        cache_read=cache_read,
        cache_write=cache_write,
    )
