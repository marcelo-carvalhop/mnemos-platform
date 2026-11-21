#!/usr/bin/env python3
r"""Kit de demonstração do terminal Mnemos T5S3 Pro com a plataforma.

Fala com o backend pela mesma API pública que o app e a web usam e com a placa
pelo console serial do firmware (USB). Serve para:

  doctor    conferir backend, IPs da máquina e a URL que o terminal deve usar
  link-app  dar e-mail e senha à conta anônima do app (app, web e terminal
            passam a usar a mesma conta; só em dev/staging, sem attestation)
  seed      criar uma conta de demonstração com baralhos e cartões
  pair      parear a placa pela USB (registra o terminal na conta e grava
            Wi-Fi + URL + credencial na placa), sem depender do app
  decks     escolher os baralhos que vão para o terminal
  status    ver o que o backend sabe do terminal (desejado x reportado)
  sync      pedir uma sincronização agora e mostrar o resultado
  info      estado da placa (Wi-Fi, backend, biblioteca, última sync)
  unpair    desvincular a placa (com --new-identity, troca o id do terminal)
  monitor   log serial filtrado ([backend], [platform], respostas)

Só usa a biblioteca padrão do Python, mais pyserial para a USB:
    pip install pyserial

Exemplos (demo local, backend no notebook):
    python3 tools/mnemos_demo.py doctor --api http://192.168.0.10:8000
    python3 tools/mnemos_demo.py link-app --api http://192.168.0.10:8000 \
        --email demo@mnemos.dev --password mnemos-demo
    python3 tools/mnemos_demo.py seed --api http://192.168.0.10:8000 \
        --email demo@mnemos.dev --password mnemos-demo
    python3 tools/mnemos_demo.py pair --api http://192.168.0.10:8000 \
        --email demo@mnemos.dev --password mnemos-demo \
        --ssid MinhaRede --wifi-password segredo123 --decks all

Variáveis de ambiente aceitas no lugar das opções: MNEMOS_API, MNEMOS_EMAIL,
MNEMOS_PASSWORD, MNEMOS_PORT, MNEMOS_SSID, MNEMOS_WIFI_PASSWORD.
"""

from __future__ import annotations

import argparse
import json
import os
import socket
import subprocess
import sys
import time
import urllib.error
import urllib.request
import uuid
from pathlib import Path

STATE_FILE = Path.home() / ".mnemos-demo.json"
REPLY_PREFIX = "@mnemos "


# --------------------------------------------------------------------------
# utilidades
# --------------------------------------------------------------------------

def die(message: str, code: int = 1) -> None:
    print(f"[erro] {message}", file=sys.stderr)
    sys.exit(code)


def uuid7() -> str:
    ms = int(time.time() * 1000)
    rnd = uuid.uuid4().int
    value = (ms << 80) | (0x7 << 76) | (((rnd >> 64) & 0x0FFF) << 64) | (0b10 << 62) | (rnd & ((1 << 62) - 1))
    return str(uuid.UUID(int=value))


def load_state() -> dict:
    try:
        return json.loads(STATE_FILE.read_text())
    except (OSError, ValueError):
        return {}


def save_state(state: dict) -> None:
    try:
        STATE_FILE.write_text(json.dumps(state, indent=1))
    except OSError:
        pass


class Api:
    def __init__(self, base: str):
        if not base:
            die("informe --api (ex.: http://192.168.0.10:8000) ou MNEMOS_API")
        self.base = base.rstrip("/")
        self.token: str | None = None

    def call(self, method: str, path: str, body=None, token: str | None = None, timeout: float = 15):
        data = json.dumps(body).encode() if body is not None else None
        req = urllib.request.Request(self.base + path, data=data, method=method)
        req.add_header("Content-Type", "application/json")
        tok = token or self.token
        if tok:
            req.add_header("Authorization", "Bearer " + tok)
        try:
            with urllib.request.urlopen(req, timeout=timeout) as resp:
                raw = resp.read()
                return resp.status, (json.loads(raw) if raw else {})
        except urllib.error.HTTPError as exc:
            text = exc.read().decode(errors="replace")
            try:
                return exc.code, json.loads(text)
            except ValueError:
                return exc.code, {"detail": text[:300]}
        except (urllib.error.URLError, OSError) as exc:
            return 0, {"detail": str(exc)}

    def login(self, email: str, password: str, create: bool = False) -> str:
        state = load_state()
        device_id = state.get("device_id") or uuid7()
        state["device_id"] = device_id
        save_state(state)

        status, pair = self.call("POST", "/v1/auth/login",
                                 {"email": email, "password": password, "device_id": device_id})
        if status == 200:
            self.token = pair["access_token"]
            return pair["user_id"]
        if not create:
            die(f"login recusado ({status}): {pair.get('detail')}. Use 'seed' para criar a conta.")

        status, anon = self.call("POST", "/v1/auth/device", {"device_id": device_id, "platform": "web"})
        if status != 200:
            die(f"não consegui criar a conta anônima ({status}): {anon.get('detail')}")
        status, pair = self.call("POST", "/v1/auth/signup",
                                 {"email": email, "password": password, "device_id": device_id},
                                 token=anon["access_token"])
        if status != 200:
            die(f"cadastro recusado ({status}): {pair.get('detail')}")
        self.token = pair["access_token"]
        print(f"[conta] criada: {email}")
        return pair["user_id"]

    def pull_all(self, table: str) -> list[dict]:
        rows, cursor = [], 0
        while True:
            status, page = self.call("GET", f"/v1/sync/pull?table={table}&since={cursor}&limit=1000")
            if status != 200:
                die(f"pull {table} falhou ({status}): {page.get('detail')}")
            rows.extend(page["rows"])
            cursor = page["cursor"]
            if not page.get("has_more"):
                return rows

    def live_decks(self) -> list[dict]:
        decks = {}
        for row in self.pull_all("decks"):
            decks[row["id"]] = row
        return [d for d in decks.values() if not d.get("deleted_at") and not d.get("archived_at")]

    def live_cards(self) -> list[dict]:
        cards = {}
        for row in self.pull_all("cards"):
            cards[row["id"]] = row
        return [c for c in cards.values() if not c.get("deleted_at")]


# --------------------------------------------------------------------------
# serial
# --------------------------------------------------------------------------

def find_port(explicit: str | None) -> str:
    if explicit:
        return explicit
    try:
        from serial.tools import list_ports
    except ImportError:
        die("instale o pyserial: pip install pyserial")
    candidates = []
    for port in list_ports.comports():
        hwid = (port.hwid or "").upper()
        desc = (port.description or "").upper()
        if "303A" in hwid or "ESPRESSIF" in desc or "USB JTAG" in desc:
            candidates.append(port.device)
    if len(candidates) == 1:
        return candidates[0]
    if not candidates:
        die("nenhuma placa Espressif encontrada na USB. Use --port (ex.: /dev/ttyACM0 ou COM5).")
    die("mais de uma placa encontrada: " + ", ".join(candidates) + ". Use --port.")
    return ""


class Board:
    def __init__(self, port: str, verbose: bool = False):
        try:
            import serial
        except ImportError:
            die("instale o pyserial: pip install pyserial")
        self.verbose = verbose
        self.ser = serial.Serial()
        self.ser.port = port
        self.ser.baudrate = 115200
        self.ser.timeout = 0.2
        # Sem DTR/RTS: abrir a porta não deve reiniciar a placa.
        self.ser.dtr = False
        self.ser.rts = False
        try:
            self.ser.open()
        except Exception as exc:  # noqa: BLE001
            die(f"não abriu {port}: {exc}. Feche o monitor serial (pio device monitor) e tente de novo.")
        self._buffer = b""

    def _lines(self, deadline: float):
        while time.time() < deadline:
            chunk = self.ser.read(4096)
            if chunk:
                self._buffer += chunk
                while b"\n" in self._buffer:
                    line, self._buffer = self._buffer.split(b"\n", 1)
                    yield line.decode(errors="replace").rstrip("\r")
            else:
                yield None

    def command(self, payload: dict, timeout: float = 20) -> dict:
        self.ser.reset_input_buffer()
        self._buffer = b""
        self.ser.write((json.dumps(payload, ensure_ascii=False) + "\n").encode())
        self.ser.flush()
        deadline = time.time() + timeout
        for line in self._lines(deadline):
            if line is None:
                continue
            if self.verbose and not line.startswith(REPLY_PREFIX):
                print("   │ " + line)
            if line.startswith(REPLY_PREFIX):
                try:
                    reply = json.loads(line[len(REPLY_PREFIX):])
                except ValueError:
                    continue
                if reply.get("cmd") in (payload.get("cmd"), "?"):
                    return reply
        die(f"a placa não respondeu a '{payload.get('cmd')}' em {timeout:.0f}s. "
            "O firmware 0.8.2+ está gravado? A placa está acordada (toque na tela)?")
        return {}

    def close(self):
        self.ser.close()


# --------------------------------------------------------------------------
# comandos
# --------------------------------------------------------------------------

DEMO_DECKS = [
    ("Biologia celular", "Organelas e funções", [
        ("O que é a mitocôndria?", "Organela da respiração celular, onde se produz a maior parte do ATP."),
        ("Função do ribossomo", "Síntese de proteínas a partir do RNA mensageiro."),
        ("O que faz o complexo de Golgi?", "Modifica, empacota e endereça proteínas — os “correios” da célula."),
        ("Retículo endoplasmático rugoso", "Possui ribossomos aderidos e produz proteínas para exportação."),
        ("Lisossomo", "Vesícula com enzimas digestivas que degradam material celular."),
        ("Membrana plasmática", "Bicamada lipídica com permeabilidade seletiva."),
    ]),
    ("Física — Óptica", "Refração e espelhos", [
        ("Lei de Snell", "n₁·sen θ₁ = n₂·sen θ₂ → a luz desvia ao mudar de meio."),
        ("Índice de refração (n)", "n = c / v. Água ≈ 1,33; vidro ≈ 1,5."),
        ("Espelho côncavo: foco", "f = R/2. Raios paralelos ao eixo convergem no foco."),
        ("Reflexão total", "Ocorre quando o ângulo de incidência supera o ângulo limite (n₁ > n₂)."),
        ("Lente convergente", "Bordas finas no ar; forma imagem real além do foco."),
    ]),
    ("Português — Crase", "Regras rápidas", [
        ("Crase antes de palavra masculina?", "Não ocorre, salvo se houver “à moda de” subentendido."),
        ("Vou ___ Bahia / Vou ___ Recife", "Vou à Bahia (volto da Bahia); vou a Recife (volto de Recife)."),
        ("Crase em horas", "Ocorre: “às 14h”, “à uma hora”."),
        ("Antes de verbo", "Nunca há crase antes de verbo: “a partir de”."),
    ]),
]


def cmd_doctor(args):
    print("== máquina ==")
    host = socket.gethostname()
    ips = set()
    try:
        probe = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        probe.connect(("10.255.255.255", 1))
        ips.add(probe.getsockname()[0])
        probe.close()
    except OSError:
        pass
    try:
        for info in socket.getaddrinfo(host, None, socket.AF_INET):
            ips.add(info[4][0])
    except OSError:
        pass
    ips = sorted(ip for ip in ips if not ip.startswith("127."))
    print(f"  hostname: {host}  (mDNS: http://{host}.local:8000, se o Bonjour/Avahi estiver ativo)")
    print(f"  IPs na rede: {', '.join(ips) or 'nenhum encontrado'}")

    if args.api:
        print("== backend ==")
        api = Api(args.api)
        status, body = api.call("GET", "/healthz", timeout=5)
        print(f"  {args.api}/healthz -> {status} {body}")
        if status != 200:
            print("  [!] backend inacessível. Suba com: docker compose up -d && docker compose run --rm migrate")
        host_part = args.api.split("://", 1)[-1].split("/", 1)[0].split(":", 1)[0]
        if host_part in ("localhost", "127.0.0.1", "10.0.2.2"):
            print("  [!] terminal e celular não alcançam 'localhost'. Use o IP do notebook na rede: "
                  + (f"http://{ips[0]}:8000" if ips else "http://<ip>:8000"))
    print("== rede para a demo ==")
    print("  - terminal, celular e notebook na MESMA rede 2,4 GHz WPA2 (roteador portátil ou hotspot)")
    print("  - evite Wi-Fi da universidade: isolamento entre clientes bloqueia terminal -> notebook")
    print("  - libere a porta 8000 no firewall do notebook")


def find_compose_root() -> Path | None:
    here = Path(__file__).resolve()
    for parent in here.parents:
        if (parent / "compose.yaml").exists():
            return parent
    return None


def latest_app_device() -> tuple[str, str]:
    root = find_compose_root()
    if root is None:
        die("não achei o compose.yaml do repositório; informe --device-id")
    query = ("select id, platform from devices where platform in ('android','ios') "
             "order by created_at desc limit 1")
    cmd = ["docker", "compose", "exec", "-T", "postgres", "psql", "-U",
           os.environ.get("POSTGRES_USER", "flashcards"), "-d", os.environ.get("POSTGRES_DB", "flashcards"),
           "-At", "-F", "|", "-c", query]
    try:
        out = subprocess.run(cmd, cwd=root, capture_output=True, text=True, timeout=30)
    except (OSError, subprocess.TimeoutExpired) as exc:
        die(f"não consegui consultar o banco pelo docker compose: {exc}. Informe --device-id")
    line = out.stdout.strip().splitlines()[0] if out.stdout.strip() else ""
    if out.returncode != 0 or "|" not in line:
        die("nenhum aparelho Android/iOS registrado ainda. Abra o app uma vez com o backend no ar. "
            + (out.stderr.strip()[:200] if out.stderr else ""))
    device_id, platform = line.split("|", 1)
    return device_id, platform


def cmd_link_app(args):
    """O app usa uma conta anônima presa ao aparelho e não tem tela de login.
    Em dev/staging (REQUIRE_ATTESTATION desligado), registrar de novo o mesmo
    id de aparelho devolve um token dessa conta; o signup só acrescenta e-mail
    e senha, sem mover dados. A web passa a entrar nessa conta e o terminal
    pareado pelo app aparece nela."""
    api = Api(args.api)
    if args.device_id:
        device_id, platform = args.device_id, args.platform
    else:
        device_id, platform = latest_app_device()
        print(f"[app] aparelho mais recente: {device_id} ({platform})")

    status, pair = api.call("POST", "/v1/auth/device", {"device_id": device_id, "platform": platform})
    if status != 200:
        die(f"não consegui entrar na conta do app ({status}): {pair.get('detail')}. "
            "Com REQUIRE_ATTESTATION ligado isto não é possível.")

    tool_device = load_state().get("device_id") or uuid7()
    state = load_state()
    state["device_id"] = tool_device
    save_state(state)

    status, body = api.call("POST", "/v1/auth/signup",
                            {"email": args.email, "password": args.password, "device_id": tool_device},
                            token=pair["access_token"])
    if status == 200:
        print(f"[conta] a conta do app agora entra com {args.email} / {args.password}")
    elif "already has credentials" in str(body.get("detail", "")):
        print("[conta] a conta do app já tem e-mail e senha: entre na web com eles "
              "(este comando não troca credenciais existentes)")
        return
    elif "already registered" in str(body.get("detail", "")):
        die(f"{args.email} já pertence a outra conta (criada na web?). Use outro e-mail aqui.")
    else:
        die(f"signup falhou ({status}): {body.get('detail')}")

    api.login(args.email, args.password)
    decks = api.live_decks()
    print(f"[conta] login conferido: {len(decks)} baralhos na conta. Entre na web com esse e-mail.")


def cmd_seed(args):
    api = Api(args.api)
    api.login(args.email, args.password, create=True)
    existing = {d["name"] for d in api.live_decks()}
    state = load_state()
    device_id = state["device_id"]
    now = int(time.time() * 1000)
    created = 0
    for name, description, cards in DEMO_DECKS:
        if name in existing and not args.force:
            print(f"[seed] baralho já existe: {name}")
            continue
        deck_id = uuid7()
        status, body = api.call("POST", "/v1/sync/push", {"table": "decks", "rows": [{
            "id": deck_id, "name": name, "description": description, "updated_at": now,
            "device_id": device_id, "version": 1, "origin": "own"}]})
        if status != 200:
            die(f"criar baralho falhou ({status}): {body.get('detail')}")
        rows = [{"id": uuid7(), "deck_id": deck_id, "front": front, "back": back, "tags": ["demo"],
                 "updated_at": now, "device_id": device_id} for front, back in cards]
        status, body = api.call("POST", "/v1/sync/push", {"table": "cards", "rows": rows})
        if status != 200:
            die(f"criar cartões falhou ({status}): {body.get('detail')}")
        created += 1
        print(f"[seed] {name}: {len(rows)} cartões")
    print(f"[seed] pronto ({created} baralhos novos). Entre na web/app com {args.email} / {args.password}.")


def resolve_decks(api: Api, selection: str | None) -> list[str]:
    if not selection:
        return []
    decks = api.live_decks()
    if selection == "all":
        return [d["id"] for d in decks]
    chosen, missing = [], []
    for token in (s.strip() for s in selection.split(",")):
        if not token:
            continue
        match = next((d for d in decks if token.lower() in (d["id"].lower(), d["name"].lower())), None)
        if match is None:
            missing.append(token)
        elif match["id"] not in chosen:
            chosen.append(match["id"])
    if missing:
        names = ", ".join(sorted(d["name"] for d in decks))
        die(f"baralhos não encontrados: {', '.join(missing)}. Disponíveis: {names}")
    return chosen


def print_report(reply: dict):
    print(f"  {reply.get('title', reply.get('outcome'))}")
    for line in str(reply.get("message", "")).splitlines():
        print("    " + line)


def wait_wifi(board: Board, seconds: int) -> dict:
    deadline = time.time() + seconds
    info = {}
    while time.time() < deadline:
        info = board.command({"cmd": "info"}, timeout=10)
        if info.get("wifi", {}).get("connected"):
            return info
        time.sleep(2)
    return info


def cmd_pair(args):
    api = Api(args.api)
    api.login(args.email, args.password, create=args.create_account)
    host_part = args.api.split("://", 1)[-1].split("/", 1)[0].split(":", 1)[0]
    if host_part in ("localhost", "127.0.0.1"):
        die("o terminal não alcança localhost: use o IP ou nome .local do notebook em --api")

    board = Board(find_port(args.port), verbose=args.verbose)
    try:
        info = board.command({"cmd": "info"})
        device_id = info["deviceId"]
        print(f"[placa] {device_id} firmware {info.get('firmware')} cartões={info.get('cards')}")

        deck_ids = resolve_decks(api, args.decks)
        body = {"device_id": device_id, "model": info.get("model", "Mnemos T5S3 Pro"),
                "firmware": info.get("firmware", "unknown"), "deck_ids": deck_ids}
        status, reg = api.call("POST", "/v1/terminals/register", body)

        if status == 409 and "another user" in str(reg.get("detail", "")):
            if not args.new_identity:
                die("este terminal já pertence a outra conta. Rode de novo com --new-identity "
                    "(a placa ganha um id novo) ou entre com a conta original.")
            reply = board.command({"cmd": "unpair", "newIdentity": True})
            device_id = reply["deviceId"]
            print(f"[placa] nova identidade: {device_id}")
            body["device_id"] = device_id
            status, reg = api.call("POST", "/v1/terminals/register", body)

        if status != 200:
            die(f"registro do terminal falhou ({status}): {reg.get('detail')}")
        print(f"[backend] terminal registrado; baralhos escolhidos: {len(deck_ids)}")

        provision = {"cmd": "provision", "backendUrl": args.api.rstrip("/"),
                     "deviceToken": reg["device_token"], "epoch": int(time.time())}
        if args.ssid:
            provision.update({"ssid": args.ssid, "password": args.wifi_password or ""})
            if args.security:
                provision["security"] = args.security
            if args.username:
                provision["username"] = args.username
            reply = board.command(provision)
        else:
            if not info.get("wifi", {}).get("profiles"):
                die("a placa não conhece nenhuma rede: informe --ssid e --wifi-password")
            reply = board.command({"cmd": "backend", "url": provision["backendUrl"],
                                   "token": provision["deviceToken"]})
            board.command({"cmd": "time", "epoch": int(time.time())})
        if not reply.get("ok"):
            die(f"a placa recusou a configuração: {reply.get('error')}")
        print("[placa] Wi-Fi e conta gravados")

        print("[placa] aguardando o Wi-Fi conectar...")
        info = wait_wifi(board, args.wifi_timeout)
        if not info.get("wifi", {}).get("connected"):
            print(f"[!] o Wi-Fi não conectou em {args.wifi_timeout}s (último erro: "
                  f"{info.get('wifi', {}).get('lastError')}). A placa continua tentando sozinha.")
            return
        print(f"[placa] conectada em {info['wifi'].get('ssid')} ({info['wifi'].get('ip')})")
        reply = board.command({"cmd": "sync"}, timeout=90)
        print("[sync]")
        print_report(reply)
    finally:
        board.close()


def cmd_decks(args):
    api = Api(args.api)
    api.login(args.email, args.password)
    device_id = args.device
    if not device_id:
        board = Board(find_port(args.port))
        try:
            device_id = board.command({"cmd": "info"})["deviceId"]
        finally:
            board.close()
    deck_ids = resolve_decks(api, args.decks or "all")
    status, summary = api.call("POST", f"/v1/terminals/{device_id}/decks", {"deck_ids": deck_ids})
    if status != 200:
        die(f"não consegui escolher os baralhos ({status}): {summary.get('detail')}")
    print(f"[backend] {device_id}: {len(deck_ids)} baralhos desejados. "
          "O terminal aplica na próxima sincronização (ou rode: sync).")


def cmd_status(args):
    api = Api(args.api)
    api.login(args.email, args.password)
    decks = {d["id"]: d["name"] for d in api.live_decks()}
    status, rows = api.call("GET", "/v1/terminals")
    if status != 200:
        die(f"falhou ({status}): {rows}")
    if not rows:
        print("nenhum terminal nesta conta")
    for t in rows:
        print(f"{t['device_id']}  {'REVOGADO ' if t['revoked'] else ''}firmware {t['firmware']}")
        print(f"   cartões no aparelho: {t['card_count']}/{t['max_cards']}  conexão: {t.get('connectivity')} "
              f"rede: {t.get('wifi_ssid')}")
        print(f"   visto: {t.get('last_seen_at')}  última sync completa: {t.get('last_sync_at')}")
        print("   desejados: " + (", ".join(decks.get(i, i) for i in t["desired_deck_ids"]) or "-"))
        print("   no aparelho: " + (", ".join(decks.get(i, i) for i in t["reported_deck_ids"]) or "-"))


def cmd_sync(args):
    board = Board(find_port(args.port), verbose=args.verbose)
    try:
        reply = board.command({"cmd": "sync"}, timeout=90)
        print_report(reply)
        if not reply.get("ok") and reply.get("error"):
            print(f"  erro: {reply['error']}")
    finally:
        board.close()


def cmd_info(args):
    board = Board(find_port(args.port))
    try:
        print(json.dumps(board.command({"cmd": "info"}), indent=2, ensure_ascii=False))
    finally:
        board.close()


def cmd_unpair(args):
    board = Board(find_port(args.port))
    try:
        reply = board.command({"cmd": "unpair", "newIdentity": bool(args.new_identity)})
        print(f"[placa] desvinculada. id atual: {reply.get('deviceId')}")
    finally:
        board.close()


def cmd_monitor(args):
    board = Board(find_port(args.port))
    print("[monitor] Ctrl+C para sair")
    keys = ("[backend]", "[platform]", "[local-link]", "[wifi]", "[app]", REPLY_PREFIX)
    try:
        for line in board._lines(time.time() + 10 ** 9):
            if line is None:
                continue
            if args.all or any(k in line for k in keys):
                print(line)
    except KeyboardInterrupt:
        pass
    finally:
        board.close()


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = parser.add_subparsers(dest="command", required=True)

    def common(p, account=True, serial_port=True):
        p.add_argument("--api", default=os.environ.get("MNEMOS_API"), help="URL do backend (ex.: http://192.168.0.10:8000)")
        if account:
            p.add_argument("--email", default=os.environ.get("MNEMOS_EMAIL"), required=os.environ.get("MNEMOS_EMAIL") is None)
            p.add_argument("--password", default=os.environ.get("MNEMOS_PASSWORD"), required=os.environ.get("MNEMOS_PASSWORD") is None)
        if serial_port:
            p.add_argument("--port", default=os.environ.get("MNEMOS_PORT"), help="porta serial (padrão: detecta)")
            p.add_argument("--verbose", action="store_true", help="mostra o log da placa durante os comandos")

    p = sub.add_parser("doctor"); common(p, account=False, serial_port=False); p.set_defaults(fn=cmd_doctor)
    p = sub.add_parser("link-app"); common(p, serial_port=False)
    p.add_argument("--device-id", help="id do aparelho do app (padrão: o Android/iOS mais recente no banco local)")
    p.add_argument("--platform", default="android")
    p.set_defaults(fn=cmd_link_app)

    p = sub.add_parser("seed"); common(p, serial_port=False)
    p.add_argument("--force", action="store_true", help="cria os baralhos mesmo que já existam"); p.set_defaults(fn=cmd_seed)

    p = sub.add_parser("pair"); common(p)
    p.add_argument("--ssid", default=os.environ.get("MNEMOS_SSID"))
    p.add_argument("--wifi-password", default=os.environ.get("MNEMOS_WIFI_PASSWORD"))
    p.add_argument("--security", choices=["personal", "open", "enterprise-password"])
    p.add_argument("--username", help="usuário de rede Enterprise (PEAP)")
    p.add_argument("--decks", help="'all' ou nomes/ids separados por vírgula")
    p.add_argument("--new-identity", action="store_true", help="troca o id do terminal se ele pertencer a outra conta")
    p.add_argument("--create-account", action="store_true", help="cria a conta se o login falhar")
    p.add_argument("--wifi-timeout", type=int, default=45)
    p.set_defaults(fn=cmd_pair)

    p = sub.add_parser("decks"); common(p)
    p.add_argument("--device", help="id do terminal (padrão: lê da placa)")
    p.add_argument("--decks", default="all"); p.set_defaults(fn=cmd_decks)

    p = sub.add_parser("status"); common(p, serial_port=False); p.set_defaults(fn=cmd_status)
    p = sub.add_parser("sync"); common(p, account=False); p.set_defaults(fn=cmd_sync)
    p = sub.add_parser("info"); common(p, account=False); p.set_defaults(fn=cmd_info)
    p = sub.add_parser("unpair"); common(p, account=False)
    p.add_argument("--new-identity", action="store_true"); p.set_defaults(fn=cmd_unpair)
    p = sub.add_parser("monitor"); common(p, account=False)
    p.add_argument("--all", action="store_true", help="todo o log, sem filtro"); p.set_defaults(fn=cmd_monitor)

    args = parser.parse_args()
    if args.command in ("seed", "pair", "decks", "status", "link-app") and not args.api:
        die("informe --api (ex.: http://192.168.0.10:8000) ou MNEMOS_API")
    args.fn(args)


if __name__ == "__main__":
    main()
