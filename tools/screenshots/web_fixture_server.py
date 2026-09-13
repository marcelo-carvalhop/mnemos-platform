"""Serves the Angular build with a stubbed Mnemos backend behind it.

The published web bundle talks to its own origin (`/v1/...`) and keeps its
session in localStorage, so a static server plus a fake API is enough to render
the signed-in screens without Postgres, Docker or a real account.

Every request is logged to requests.log so missing endpoints are visible.
"""

import base64
import json
import os
import random
import sys
import tempfile
from datetime import date, datetime, timedelta, timezone
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import parse_qs, urlparse

ROOT = os.path.abspath(sys.argv[1])
PORT = int(sys.argv[2])
# In the temp dir, not next to the script: a debug aid should not dirty the repo.
LOG = os.path.join(tempfile.gettempdir(), "mnemos-screenshot-requests.log")

NOW = datetime(2026, 8, 31, 15, 0, tzinfo=timezone.utc)
USER_ID = "01927f00-0000-7000-8000-0000000000aa"
DEVICE_ID = "01927f00-0000-7000-8000-0000000000bb"


def b64(data: dict) -> str:
    raw = json.dumps(data, separators=(",", ":")).encode()
    return base64.urlsafe_b64encode(raw).decode().rstrip("=")


def token() -> str:
    head = b64({"alg": "HS256", "typ": "JWT"})
    body = b64(
        {
            "sub": USER_ID,
            "iat": int(NOW.timestamp()),
            "exp": int((NOW + timedelta(days=3650)).timestamp()),
            "typ": "access",
        }
    )
    return f"{head}.{body}.c2NyZWVuc2hvdA"


def iso(dt: datetime) -> str:
    return dt.astimezone(timezone.utc).isoformat().replace("+00:00", "Z")


# ---------------------------------------------------------------------------
# Fixture data — the same shape the sync endpoints return
# ---------------------------------------------------------------------------

DECKS = [
    ("01927f01-0000-7000-8000-000000000001", "Redes de Computadores", 21),
    ("01927f01-0000-7000-8000-000000000002", "Direito Constitucional", 12),
]

REDES = [
    ("Qual é a função principal da camada de enlace?",
     "Entregar quadros entre nós diretamente conectados ao mesmo enlace e tratar o acesso ao meio físico."),
    ("Qual é a função principal do protocolo IP?",
     "Endereçar e encaminhar datagramas entre redes, oferecendo entrega por melhor esforço."),
    ("Qual é a diferença fundamental entre TCP e UDP?",
     "TCP oferece fluxo orientado a conexão, confiável e ordenado; UDP oferece datagramas sem conexão e sem garantias de entrega ou ordem."),
    ("O que ocorre no three-way handshake do TCP?",
     "Cliente e servidor trocam SYN, SYN-ACK e ACK para sincronizar números de sequência e estabelecer a conexão."),
    ("Para que serve o DNS?",
     "Resolver nomes de domínio em dados como endereços IP por meio de uma hierarquia distribuída de servidores."),
    ("Qual é a função de uma máscara de sub-rede?",
     "Separar os bits de rede e de host de um endereço IP, permitindo determinar quais endereços pertencem à mesma sub-rede."),
    ("O que faz um roteador?",
     "Encaminha pacotes entre redes distintas com base em sua tabela de roteamento e no endereço IP de destino."),
    ("O que é ARP em redes IPv4?",
     "É o protocolo usado em uma rede local para descobrir o endereço MAC associado a um endereço IPv4 conhecido."),
    ("Qual é a finalidade do DHCP?",
     "Fornecer automaticamente parâmetros de configuração de rede, como endereço IP, máscara, gateway e servidores DNS."),
    ("O que significa NAT?",
     "Network Address Translation: tradução de endereços entre domínios de rede, frequentemente usada para compartilhar um endereço público entre hosts privados."),
]

DIREITO = [
    ("O que são cláusulas pétreas?",
     "Núcleos da Constituição que não podem ser abolidos por emenda: a forma federativa de Estado, o voto direto secreto universal e periódico, a separação dos Poderes e os direitos e garantias individuais."),
    ("Qual a diferença entre controle difuso e concentrado de constitucionalidade?",
     "No difuso, qualquer juiz aprecia a constitucionalidade no caso concreto, com efeitos entre as partes; no concentrado, o STF julga a lei em tese, com efeito erga omnes."),
    ("O que é o princípio da reserva legal?",
     "A exigência de que determinadas matérias só possam ser disciplinadas por lei em sentido formal, editada pelo Poder Legislativo."),
    ("Quem pode propor ação direta de inconstitucionalidade?",
     "Os legitimados do art. 103 da Constituição, entre eles o Presidente da República, as Mesas do Senado e da Câmara, o Procurador-Geral da República, o Conselho Federal da OAB e os partidos políticos com representação no Congresso."),
    ("O que significa o princípio da anterioridade tributária?",
     "A vedação de cobrar tributo no mesmo exercício financeiro em que foi publicada a lei que o instituiu ou aumentou."),
    ("O que é habeas data?",
     "Remédio constitucional para assegurar o conhecimento ou a retificação de informações relativas à pessoa do impetrante constantes de registros de entidades governamentais ou de caráter público."),
]


def build_rows():
    seq = 0

    def nxt():
        nonlocal seq
        seq += 1
        return seq

    decks, cards = [], []
    for deck_id, name, age in DECKS:
        created = NOW - timedelta(days=age)
        decks.append(
            {
                "id": deck_id,
                "user_id": USER_ID,
                "parent_id": None,
                "name": name,
                "description": None,
                "version": 1,
                "author": None,
                "license": None,
                "origin": "own",
                "source_deck_id": None,
                "archived_at": None,
                "created_at": iso(created),
                "updated_at": iso(created),
                "deleted_at": None,
                "device_id": DEVICE_ID,
                "server_seq": nxt(),
            }
        )

    n = 0
    for (deck_id, _, age), seeds in ((DECKS[0], REDES), (DECKS[1], DIREITO)):
        created = NOW - timedelta(days=age)
        for front, back in seeds:
            n += 1
            cards.append(
                {
                    "id": f"01927f02-0000-7000-8000-{n:012d}",
                    "user_id": USER_ID,
                    "deck_id": deck_id,
                    "front": front,
                    "back": back,
                    "tags": [],
                    "created_at": iso(created),
                    "updated_at": iso(created),
                    "deleted_at": None,
                    "device_id": DEVICE_ID,
                    "server_seq": nxt(),
                }
            )

    rng = random.Random(20260831)
    reviews = []
    r = 0

    # As revisões são deliberadamente desiguais entre os dois baralhos, para
    # que a captura mostre os dois estados que importam: um baralho com fila
    # vencida e outro em dia. Uma fixture em que nada vence fotografa só a
    # tela de "parabéns, acabou".
    redes = [c for c in cards if c["deck_id"] == DECKS[0][0]]
    direito = [c for c in cards if c["deck_id"] == DECKS[1][0]]

    def review(card, at, grade):
        nonlocal r
        r += 1
        reviews.append(
            {
                "id": f"01927f03-0000-7000-8000-{r:012d}",
                "user_id": USER_ID,
                "card_id": card["id"],
                "reviewed_at": iso(at),
                "grade": grade,
                "source": "app",
                "elapsed_ms": rng.randint(2200, 9000),
                "device_id": DEVICE_ID,
                "server_seq": nxt(),
                "interval_days_after": None,
                "stability_after": None,
                "difficulty_after": None,
                "scheduler_version": 1,
                "app_version": "0.5.0",
            }
        )

    # Redes: revisado até duas semanas atrás, com notas baixas. Intervalos
    # curtos + duas semanas parado = fila vencida hoje.
    for card in redes:
        for days_ago in (21, 18, 15):
            review(card, NOW - timedelta(days=days_ago, hours=-2), rng.choice([1, 2, 3]))

    # Direito: em dia, com notas altas — nada vence.
    for card in direito:
        for days_ago in (12, 6, 1):
            review(card, NOW - timedelta(days=days_ago, hours=-2), rng.choice([3, 4]))

    # Volume diário suficiente para a meta ser batida e a sequência existir.
    # Duas faltas propositais: um mapa sem falhas não é um registro, é enfeite.
    for days_ago in range(20, -1, -1):
        if days_ago in (8, 13):
            continue
        at = NOW - timedelta(days=days_ago) + timedelta(hours=3)
        pool = direito if days_ago < 14 else cards
        for i in range(rng.randint(21, 28)):
            review(pool[i % len(pool)], at + timedelta(minutes=i * 3), 3)

    settings = [
        {
            "user_id": USER_ID,
            "key": key,
            "value": value,
            "updated_at": iso(NOW - timedelta(days=21)),
            "device_id": DEVICE_ID,
            "server_seq": nxt(),
        }
        for key, value in (
            ("timezone", "America/Sao_Paulo"),
            ("day_cutoff_hour", "4"),
            ("new_per_day", "10"),
            ("review_per_day", "200"),
            ("desired_retention", "0.9"),
        )
    ]

    goals = [
        {
            "id": "01927f04-0000-7000-8000-000000000001",
            "user_id": USER_ID,
            "effective_from_local_date": str(date(2026, 8, 10)),
            "daily_goal": 20,
            "created_at": iso(NOW - timedelta(days=21)),
            "device_id": DEVICE_ID,
            "server_seq": nxt(),
        }
    ]

    return {
        "decks": decks,
        "cards": cards,
        "card_flags": [],
        "reviews": reviews,
        "progress_resets": [],
        "goal_history": goals,
        "user_settings": settings,
    }


TABLES = build_rows()
HIGH_WATER = max(
    (row["server_seq"] for rows in TABLES.values() for row in rows), default=0
)

TERMINAL = {
    "device_id": "mnemos-t5-0a3f",
    "model": "Mnemos T5",
    "firmware": "0.5.0",
    "desired_deck_ids": [DECKS[0][0], DECKS[1][0]],
    "reported_deck_ids": [DECKS[0][0]],
    "card_count": 10,
    "max_cards": 400,
    "revoked": False,
    "connectivity": "wifi",
    "last_seen_at": iso(NOW - timedelta(hours=2)),
    "last_sync_at": iso(NOW - timedelta(hours=2)),
}

BOOT = (
    "<script>try{"
    f"localStorage.setItem('mnemos.access','{token()}');"
    f"localStorage.setItem('mnemos.refresh','{token()}');"
    f"localStorage.setItem('mnemos.device','{DEVICE_ID}');"
    "}catch(e){}</script>"
)


def click_after_load(label):
    """Aperta um botão pelo rótulo assim que ele aparece.

    O Chrome em `--screenshot` não clica em nada, e as origens de Criar são
    estado do componente e não rota — sem isto não há como fotografar a tela de
    PDF ou a de texto colado. Fica **aqui**, no servidor de fixture, e não numa
    rota `?origem=` no cliente: uma porta de entrada que só o fotógrafo usa não
    devia existir no produto.
    """
    escaped = json.dumps(label)
    return (
        "<script>(function(){var t=setInterval(function(){"
        "var b=[].slice.call(document.querySelectorAll('.sources button'))"
        f".filter(function(x){{return x.textContent.trim()==={escaped};}})[0];"
        "if(b){clearInterval(t);b.click();}},80);"
        "setTimeout(function(){clearInterval(t);},8000);})()</script>"
    )


class Handler(SimpleHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    # -- helpers ------------------------------------------------------------
    def _log(self, note):
        with open(LOG, "a", encoding="utf-8") as fh:
            fh.write(f"{self.command} {self.path} -> {note}\n")

    def _json(self, payload, status=200):
        body = json.dumps(payload).encode("utf-8")
        self.send_response(status)
        self.send_header("content-type", "application/json; charset=utf-8")
        self.send_header("content-length", str(len(body)))
        self.send_header("cache-control", "no-store")
        self.end_headers()
        self.wfile.write(body)

    def _read_body(self):
        length = int(self.headers.get("content-length") or 0)
        if not length:
            return {}
        try:
            return json.loads(self.rfile.read(length) or b"{}")
        except Exception:
            return {}

    # -- API ----------------------------------------------------------------
    def _api(self, method, path, query):
        if path.startswith("/v1/auth/"):
            self._log("auth")
            return self._json(
                {
                    "access_token": token(),
                    "refresh_token": token(),
                    "token_type": "bearer",
                    "expires_in": 3600,
                    "user_id": USER_ID,
                    "device_id": DEVICE_ID,
                }
            )

        if path == "/v1/sync/tables":
            self._log("tables")
            return self._json(sorted(TABLES))

        if path == "/v1/sync/pull":
            table = (query.get("table") or [""])[0]
            raw = (query.get("cursor") or query.get("since") or ["0"])[0]
            cursor = int(raw or 0)
            rows = [r for r in TABLES.get(table, []) if r["server_seq"] > cursor]
            self._log(f"pull {table} cursor={cursor} rows={len(rows)}")
            return self._json(
                {
                    "table": table,
                    "rows": rows,
                    "cursor": rows[-1]["server_seq"] if rows else cursor,
                    "has_more": False,
                }
            )

        if path == "/v1/sync/push":
            self._read_body()
            self._log("push")
            return self._json(
                {"applied": 0, "skipped_stale": 0, "high_water": HIGH_WATER, "assigned": {}}
            )

        if path.startswith("/v1/quota"):
            self._log("quota")
            return self._json({"remaining": 1, "limit": 1, "plan": "free"})

        if path.startswith("/v1/terminals"):
            # A lista, para o cliente web; o resumo, para o aplicativo.
            if path.rstrip("/") == "/v1/terminals" and method == "GET":
                self._log("terminal list")
                return self._json([TERMINAL])
            self._log("terminal")
            if path.endswith("/summary"):
                return self._json(
                    {
                        "device_id": "mnemos-t5-0a3f",
                        "model": "Mnemos T5",
                        "firmware": "0.5.0",
                        "desired_deck_ids": [DECKS[0][0]],
                        "reported_deck_ids": [DECKS[0][0]],
                        "card_count": 10,
                        "max_cards": 400,
                        "revoked": False,
                        "last_seen_at": iso(NOW - timedelta(hours=4)),
                        "last_sync_at": iso(NOW - timedelta(hours=4)),
                        "connectivity": "wifi",
                        "wifi_ssid": "casa-2g",
                    }
                )
            return self._json([])

        if path.startswith("/v1/account/export"):
            self._log("export")
            return self._json({"decks": TABLES["decks"], "cards": TABLES["cards"]})

        self._log("UNHANDLED")
        return self._json({"detail": "not stubbed"}, status=404)

    # -- static -------------------------------------------------------------
    @staticmethod
    def _api_path(path):
        """O cliente Angular usa a base `/api`; o app Flutter fala com a raiz.

        Servir os dois é uma linha e evita um servidor por cliente."""
        if path.startswith("/api/v1/"):
            return path[len("/api"):]
        return path if path.startswith("/v1/") else None

    def do_GET(self):
        parsed = urlparse(self.path)
        api = self._api_path(parsed.path)
        if api:
            return self._api("GET", api, parse_qs(parsed.query))

        local = os.path.join(ROOT, parsed.path.lstrip("/"))
        if parsed.path == "/" or not os.path.isfile(local):
            html = open(os.path.join(ROOT, "index.html"), encoding="utf-8").read()
            # ?anon=1 renders the signed-out screens (landing, sign-in).
            query = parse_qs(parsed.query)
            if "anon" not in query:
                html = html.replace("<body>", "<body>" + BOOT, 1)
            if "clique" in query:
                html = html.replace(
                    "</body>", click_after_load(query["clique"][0]) + "</body>", 1
                )
            body = html.encode("utf-8")
            self.send_response(200)
            self.send_header("content-type", "text/html; charset=utf-8")
            self.send_header("content-length", str(len(body)))
            self.send_header("cache-control", "no-store")
            self.end_headers()
            self.wfile.write(body)
            return
        return super().do_GET()

    def do_POST(self):
        parsed = urlparse(self.path)
        api = self._api_path(parsed.path)
        if api:
            self._read_body()
            return self._api("POST", api, parse_qs(parsed.query))
        self.send_error(404)

    def do_PUT(self):
        self.do_POST()

    def log_message(self, *args):
        pass


if not os.path.isfile(os.path.join(ROOT, "index.html")):
    raise SystemExit(f"no index.html under {ROOT} — is the web build there?")

os.chdir(ROOT)
open(LOG, "w", encoding="utf-8").close()
print(f"serving {ROOT} on {PORT}; high_water={HIGH_WATER}", flush=True)
ThreadingHTTPServer(("127.0.0.1", PORT), Handler).serve_forever()
