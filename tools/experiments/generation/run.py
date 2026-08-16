#!/usr/bin/env python3
"""Generation spike — replaces invented numbers in spec §7 with measurements.

Plan wave 0. This is not production code; it is deleted or archived once §7
carries real figures. It deliberately does NOT enable refusal fallbacks, so a
refusal is observed rather than silently rescued.

    python spikes/generation/run.py --report
    python spikes/generation/run.py --only topic-medium scanned-pdf
"""

from __future__ import annotations

import argparse
import base64
import json
import os
import pathlib
import sys
import time
from dataclasses import dataclass, field, asdict

import anthropic
import regex
import yaml

# The Windows console defaults to cp1252, which cannot encode "→" — let alone
# the Portuguese card samples this script exists to print. Without this the
# spike dies on its first status line.
for stream in (sys.stdout, sys.stderr):
    if hasattr(stream, "reconfigure"):
        stream.reconfigure(encoding="utf-8", errors="replace")

HERE = pathlib.Path(__file__).resolve().parent
ROOT = HERE.parent.parent
FIXTURES = HERE / "fixtures"
OUT = HERE / "out"

CONTRACT = yaml.safe_load((ROOT / "shared" / "contract.yaml").read_text(encoding="utf-8"))
FRONT_MAX = CONTRACT["card_limits"]["front_max_graphemes"]
BACK_MAX = CONTRACT["card_limits"]["back_max_graphemes"]

OPUS = "claude-opus-5"
SONNET = "claude-sonnet-5"

# USD per million tokens. Sonnet 5 is at its introductory rate through
# 2026-08-31; recompute after that.
PRICES = {
    OPUS: (5.00, 25.00),
    SONNET: (2.00, 10.00),
}

REQUESTED_CARDS = 10
# §7.6 asks for 20% more than requested, so the constrain stage can drop
# oversized cards without shortchanging the user. The spike measures whether
# 20% is the right margin.
OVERGENERATION = 1.2


def compute_cost(
    model: str, tokens_in: int, cache_read: int, cache_write: int, tokens_out: int
) -> float:
    """USD for one request.

    Cached tokens are not billed at the input rate: a read costs ~0.1× and a
    write ~1.25×. Summing all three at full price — as the first version of
    this script did — overstates the cost of exactly the requests caching is
    supposed to make cheap, which would have made the cache look useless.
    """
    price_in, price_out = PRICES[model]
    dollars = (
        tokens_in * price_in
        + cache_read * price_in * 0.10
        + cache_write * price_in * 1.25
        + tokens_out * price_out
    ) / 1e6
    return round(dollars, 5)


def graphemes(text: str) -> int:
    """Grapheme-cluster count — the Python side of §7.6.

    Matches Dart's `characters` package, verified on composed/decomposed
    accents and emoji.
    """
    return len(regex.findall(r"\X", text))


# The cacheable prefix (§7.4). `level` is deliberately NOT here: it varies per
# request, and caching is a prefix match, so a varying value inside the prefix
# means the cache is written every time and never read.
SYSTEM_PROMPT = f"""Você cria flashcards de estudo em português do Brasil para \
um app de repetição espaçada.

REGRAS ABSOLUTAS DE TAMANHO
- A frente deve ter no máximo {FRONT_MAX} caracteres.
- O verso deve ter no máximo {BACK_MAX} caracteres.
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


@dataclass
class Probe:
    name: str
    question: str
    model: str = OPUS
    effort: str = "medium"
    topic: str | None = None
    text: str | None = None
    pdf: str | None = None


@dataclass
class Result:
    name: str
    question: str
    model: str
    effort: str
    ok: bool
    status: str = ""
    stop_reason: str = ""
    refusal_category: str = ""
    latency_s: float = 0.0
    tokens_in: int = 0
    tokens_out: int = 0
    cache_read: int = 0
    cache_write: int = 0
    cost_usd: float = 0.0
    cards_total: int = 0
    cards_within_limit: int = 0
    front_max_seen: int = 0
    back_max_seen: int = 0
    error: str = ""
    samples: list[dict] = field(default_factory=list)

    @property
    def within_limit_pct(self) -> float:
        if not self.cards_total:
            return 0.0
        return 100.0 * self.cards_within_limit / self.cards_total


PROBES = [
    Probe("topic-low", "Custo e qualidade em effort baixo", effort="low",
          topic="A Revolução Gloriosa de 1688 na Inglaterra"),
    Probe("topic-medium", "Linha de base", effort="medium",
          topic="A Revolução Gloriosa de 1688 na Inglaterra"),
    Probe("topic-high", "Effort alto compensa?", effort="high",
          topic="A Revolução Gloriosa de 1688 na Inglaterra"),
    Probe("topic-sonnet", "Sonnet 5 basta?", model=SONNET, effort="medium",
          topic="A Revolução Gloriosa de 1688 na Inglaterra"),
    Probe("vague-topic", "needs_specification dispara? (§7.5)",
          topic="história"),
    Probe("pasted-text", "Texto colado (§5.6)",
          text=(FIXTURES / "texto.pdf").with_suffix(".txt").name),
    Probe("text-pdf", "PDF com camada de texto", pdf="texto.pdf"),
    Probe("scanned-pdf", "PDF escaneado, sem camada de texto (§7.1)",
          pdf="escaneado.pdf"),
    Probe("sensitive-topic", "Recusa em material legítimo de estudo (§10)",
          topic="Mecanismos de toxicidade de organofosforados para a prova de "
                "roteamento IP em redes de computadores"),
]


def build_content(probe: Probe) -> list[dict]:
    n = int(REQUESTED_CARDS * OVERGENERATION)
    instruction = (
        f"Nível: intermediário.\n"
        f"Gere {n} flashcards."
    )

    content: list[dict] = []

    if probe.pdf:
        data = (FIXTURES / probe.pdf).read_bytes()
        content.append({
            "type": "document",
            "source": {
                "type": "base64",
                "media_type": "application/pdf",
                "data": base64.standard_b64encode(data).decode(),
            },
        })
        content.append({"type": "text", "text": f"{instruction}\nBaseie-se no documento acima."})
    elif probe.text:
        material = (HERE / "material.txt").read_text(encoding="utf-8")
        content.append({"type": "text", "text": f"Material:\n\n{material}\n\n{instruction}"})
    else:
        content.append({"type": "text", "text": f"Tópico: {probe.topic}\n\n{instruction}"})

    return content


def run_probe(client: anthropic.Anthropic, probe: Probe) -> Result:
    result = Result(name=probe.name, question=probe.question,
                    model=probe.model, effort=probe.effort, ok=False)

    try:
        started = time.monotonic()
        response = client.messages.create(
            model=probe.model,
            max_tokens=8000,
            system=[{
                "type": "text",
                "text": SYSTEM_PROMPT,
                "cache_control": {"type": "ephemeral"},
            }],
            output_config={
                "effort": probe.effort,
                "format": {"type": "json_schema", "schema": SCHEMA},
            },
            messages=[{"role": "user", "content": build_content(probe)}],
        )
        result.latency_s = round(time.monotonic() - started, 2)
    except Exception as exc:  # noqa: BLE001 — the spike reports, never crashes
        result.error = f"{type(exc).__name__}: {exc}"
        return result

    usage = response.usage
    result.tokens_in = usage.input_tokens
    result.tokens_out = usage.output_tokens
    result.cache_read = getattr(usage, "cache_read_input_tokens", 0) or 0
    result.cache_write = getattr(usage, "cache_creation_input_tokens", 0) or 0

    result.cost_usd = compute_cost(
        probe.model, result.tokens_in, result.cache_read,
        result.cache_write, result.tokens_out,
    )

    result.stop_reason = response.stop_reason or ""

    # §10 — a refusal is HTTP 200 with stop_reason "refusal". Code that reads
    # content[0] without checking this crashes on it.
    if response.stop_reason == "refusal":
        details = getattr(response, "stop_details", None)
        result.refusal_category = getattr(details, "category", "") or "unknown"
        result.status = "refused"
        return result

    text = next((b.text for b in response.content if b.type == "text"), "")
    if not text:
        result.error = "no text block in response"
        return result

    try:
        payload = json.loads(text)
    except json.JSONDecodeError as exc:
        result.error = f"invalid JSON: {exc}"
        return result

    result.status = payload.get("status", "")
    cards = payload.get("cards") or []
    result.cards_total = len(cards)

    for card in cards:
        front_len = graphemes(card.get("front", ""))
        back_len = graphemes(card.get("back", ""))
        result.front_max_seen = max(result.front_max_seen, front_len)
        result.back_max_seen = max(result.back_max_seen, back_len)
        if front_len <= FRONT_MAX and back_len <= BACK_MAX:
            result.cards_within_limit += 1

    result.samples = [
        {"front": c.get("front"), "back": c.get("back"), "tags": c.get("tags"),
         "front_graphemes": graphemes(c.get("front", "")),
         "back_graphemes": graphemes(c.get("back", ""))}
        for c in cards[:3]
    ]
    if result.status == "needs_specification":
        result.samples = [{"reason": payload.get("reason", "")}]

    result.ok = True
    return result


def render_report(results: list[Result]) -> str:
    lines = [
        "# Generation spike — results",
        "",
        f"Requested {REQUESTED_CARDS} cards, asked for "
        f"{int(REQUESTED_CARDS * OVERGENERATION)} (§7.6 overgeneration).",
        f"Limits under test: front {FRONT_MAX}, back {BACK_MAX} graphemes.",
        "",
        "| probe | model | effort | status | cards | dentro do limite | maior frente | maior verso | latência | in | out | US$ |",
        "|---|---|---|---|---|---|---|---|---|---|---|---|",
    ]
    for r in results:
        status = r.status or ("ERRO" if r.error else "—")
        lines.append(
            f"| {r.name} | {r.model.replace('claude-', '')} | {r.effort} | {status} | "
            f"{r.cards_total} | {r.within_limit_pct:.0f}% | "
            f"{r.front_max_seen}/{FRONT_MAX} | {r.back_max_seen}/{BACK_MAX} | "
            f"{r.latency_s}s | {r.tokens_in} | {r.tokens_out} | {r.cost_usd:.4f} |"
        )

    total = sum(r.cost_usd for r in results)
    lines += ["", f"**Custo total da execução: US$ {total:.4f}**", ""]

    errors = [r for r in results if r.error]
    if errors:
        lines += ["## Erros", ""]
        lines += [f"- `{r.name}`: {r.error}" for r in errors]
        lines.append("")

    lines += ["## Amostras", ""]
    for r in results:
        if not r.samples:
            continue
        lines.append(f"### {r.name}")
        for s in r.samples:
            if "reason" in s:
                lines.append(f"- needs_specification: {s['reason']}")
            else:
                lines.append(
                    f"- **{s['front']}** ({s['front_graphemes']}) → "
                    f"{s['back']} ({s['back_graphemes']})"
                )
        lines.append("")
    return "\n".join(lines)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--only", nargs="*", help="run a subset by name")
    parser.add_argument("--report", action="store_true", help="write out/report.md")
    args = parser.parse_args()

    if not os.getenv("ANTHROPIC_API_KEY"):
        print("ANTHROPIC_API_KEY is not set", file=sys.stderr)
        return 2

    probes = PROBES
    if args.only:
        probes = [p for p in PROBES if p.name in args.only]
        if not probes:
            print(f"no probe matches {args.only}", file=sys.stderr)
            return 2

    client = anthropic.Anthropic()
    results: list[Result] = []
    for probe in probes:
        print(f"→ {probe.name} ({probe.model}, effort={probe.effort}) …", flush=True)
        result = run_probe(client, probe)
        results.append(result)
        if result.error:
            print(f"  ERRO: {result.error}", flush=True)
        else:
            print(
                f"  {result.status} · {result.cards_total} cards · "
                f"{result.within_limit_pct:.0f}% no limite · {result.latency_s}s · "
                f"US$ {result.cost_usd:.4f}",
                flush=True,
            )

    OUT.mkdir(parents=True, exist_ok=True)
    (OUT / "results.json").write_text(
        json.dumps([asdict(r) for r in results], ensure_ascii=False, indent=2),
        encoding="utf-8",
    )
    report = render_report(results)
    if args.report:
        (OUT / "report.md").write_text(report, encoding="utf-8")
    print("\n" + report)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
