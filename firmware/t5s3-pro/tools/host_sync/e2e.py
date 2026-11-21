"""Teste ponta a ponta: firmware (código real, compilado no host) <-> backend real.

Roda o BackendSyncService, o SyncCodec e o Storage do firmware t5s3-pro contra
um backend de verdade (docker compose), passando pelos mesmos endpoints que o
app e a web usam para criar conteúdo. Veja README.md nesta pasta.
"""
import json, os, shutil, subprocess, sys, time, urllib.request, uuid

HERE = os.path.dirname(os.path.abspath(__file__))
API = os.environ.get("MNEMOS_API", "http://localhost:8000").rstrip("/")
LFS = os.environ.get("FW_LFS_DIR", os.path.join(HERE, ".lfs-e2e"))
FWSIM = os.environ.get("FWSIM", os.path.join(HERE, "fwsim"))
results = []

def call(method, path, token=None, body=None):
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(API + path, data=data, method=method)
    req.add_header("Content-Type", "application/json")
    if token: req.add_header("Authorization", "Bearer " + token)
    try:
        with urllib.request.urlopen(req, timeout=10) as r:
            return r.status, json.loads(r.read() or b"{}")
    except urllib.error.HTTPError as e:
        return e.code, e.read().decode()[:400]

def uuid7(ms=None):
    ms = ms or int(time.time() * 1000)
    rnd = uuid.uuid4().int
    v = (ms << 80) | (0x7 << 76) | (((rnd >> 64) & 0x0FFF) << 64) | (0b10 << 62) | (rnd & ((1 << 62) - 1))
    return str(uuid.UUID(int=v))

def fw(*args, **envs):
    env = dict(os.environ, FW_LFS=LFS, FW_API=STATE.get("api", API), FW_TOKEN=STATE.get("terminal_token", ""), FW_QUIET="1")
    env.update({k: str(v) for k, v in envs.items()})
    out = subprocess.run([FWSIM, *args], env=env, capture_output=True, text=True, timeout=120)
    for line in out.stdout.splitlines():
        if line.startswith("@result "):
            return json.loads(line[8:])
    raise RuntimeError(out.stdout[-2000:] + out.stderr[-2000:])

def check(name, cond, info=""):
    results.append((name, bool(cond)))
    print(("  ok   " if cond else "  FAIL ") + name + ("" if cond else f"  -> {info}"))

STATE = {}
shutil.rmtree(LFS, ignore_errors=True); os.makedirs(LFS)

print("== conta (como app/web) ==")
dev = uuid7()
st, anon = call("POST", "/v1/auth/device", body={"device_id": dev, "platform": "web"})
email = f"e2e{int(time.time())}@mnemos.dev"
st, pair = call("POST", "/v1/auth/signup", anon["access_token"], {"email": email, "password": "mnemos-demo", "device_id": dev})
tok = pair["access_token"]
now = int(time.time() * 1000)
decks = [{"id": uuid7(), "name": "Biologia celular"}, {"id": uuid7(), "name": "Física — Óptica"}]
call("POST", "/v1/sync/push", tok, {"table": "decks", "rows": [{**d, "description": None, "updated_at": now, "device_id": dev, "version": 1, "origin": "own"} for d in decks]})
cards = [
    (0, "O que é a mitocôndria?", "Organela da respiração celular e produção de ATP."),
    (0, "Qual a função do ribossomo?", "Síntese de proteínas."),
    (0, "O que faz o complexo de Golgi?", "Empacota proteínas — os “correios” da célula…"),
    (1, "Lei de Snell", "n₁·sen θ₁ = n₂·sen θ₂ → a luz desvia."),
    (1, "Índice de refração", "n = c / v; vidro n ≈ 1,5."),
    (1, "Espelho côncavo", "f = R/2 (α ≤ 90°) 🔭"),
]
crows = [{"id": uuid7(), "deck_id": decks[i]["id"], "front": f, "back": b, "tags": [], "updated_at": now, "device_id": dev} for i, f, b in cards]
st, r = call("POST", "/v1/sync/push", tok, {"table": "cards", "rows": crows})
check("conteúdo criado no backend", st == 200 and r["applied"] == 6, r)

print("== pareamento (como o app faz: register sem baralhos) ==")
TERMINAL = "T5S3-E2E" + str(int(time.time()) % 100000)
st, reg = call("POST", "/v1/terminals/register", tok, {"device_id": TERMINAL, "model": "LILYGO-T5S3-PRO-H752-01", "firmware": "0.8.2-preview.1-t5s3-pro", "deck_ids": []})
check("terminal registrado", st == 200, reg)
STATE["terminal_token"] = reg["device_token"]

print("== 1. terminal com biblioteca local (microSD) e outbox sujo ==")
fw("seedlocal")
fw("study", "2")  # 2 revisões de cartões locais -> 403 -> quarentena
fw("study", "1", "practice")  # prática -> não sobe
fw("addline", json.dumps({"schema": "mnemos.review/v2", "id": "relogio-errado-1", "cardId": crows[0]["id"], "reviewedAt": 1000, "schedulerRating": 3, "affectsSchedule": True}))
fw("addline", "isto nao e json")
r = fw("sync")
check("sync 1 termina ok", r["outcome"] == "ok", r)
check("prática descartada do envio (não estava no outbox)", r["dropped"] == 0 and r["pending"] == 0, r)
check("relógio inválido + linha corrompida + cartões locais em quarentena", r["quarantined"] == 4, r)
check("snapshot vazio preserva biblioteca local", r["kept"] and r["cardCount"] == 2 and not r["fromBackend"], r)
st, summ = call("GET", f"/v1/terminals/{TERMINAL}/summary", tok)
check("status aceito sem baralhos locais (evita 500)", st == 200 and summ["reported_deck_ids"] == [] and summ["card_count"] == 2 and summ["last_sync_at"], summ)

print("== 2. escolher baralhos no app/web ==")
st, _ = call("POST", f"/v1/terminals/{TERMINAL}/decks", tok, {"deck_ids": [d["id"] for d in decks]})
r = fw("sync")
check("sync 2 ok e biblioteca substituída", r["outcome"] == "ok" and r["changed"] and r["cardCount"] == 6 and r["fromBackend"], r)
texts = {c["q"]: c for c in r["cards"]}
check("texto normalizado para o e-paper", texts["Lei de Snell"]["a"] == "n1·sen teta1 = n2·sen teta2 -> a luz desvia." and "\"correios\"" in texts["O que faz o complexo de Golgi?"]["a"] and texts["Espelho côncavo"]["a"] == "f = R/2 (alfa <= 90°)", [c["a"] for c in r["cards"]])
check("nome do baralho normalizado", any(c["deck"] == "Física - Óptica" for c in r["cards"]), set(c["deck"] for c in r["cards"]))
st, summ = call("GET", f"/v1/terminals/{TERMINAL}/summary", tok)
check("web/app veem baralhos no aparelho", sorted(summ["reported_deck_ids"]) == sorted(d["id"] for d in decks) and summ["card_count"] == 6, summ)

print("== 3. sync sem mudanças não regrava nada ==")
r = fw("sync")
check("sync 3 sem mudança", r["outcome"] == "ok" and not r["changed"] and not r["libraryUpdatedFlag"], r)

print("== 4. estudar no terminal -> revisões aparecem para app/web ==")
s = fw("study", "3")
ids = s["ids"]
check("ids UUIDv7", all(len(i) == 36 and i[14] == "7" for i in ids), ids)
r = fw("sync")
check("3 revisões enviadas", r["pushed"] == 3 and r["pendingAfter"] == 0, r)
st, pull = call("GET", "/v1/sync/pull?table=reviews&since=0", tok)
mine = [x for x in pull["rows"] if x["id"] in ids]
check("revisões do terminal no histórico da conta", len(mine) == 3 and all(x["device_id"] == TERMINAL for x in mine), mine)

print("== 5. estudar no app -> terminal recebe ==")
app_reviews = [{"id": uuid7(now - 60000 * i), "card_id": crows[3 + (i % 3)]["id"], "reviewed_at": now - 60000 * i, "grade": 1 + (i % 4), "source": "standard", "elapsed_ms": 2000, "device_id": dev} for i in range(5)]
st, r0 = call("POST", "/v1/sync/push", tok, {"table": "reviews", "rows": app_reviews})
r = fw("sync")
check("5 revisões do app recebidas", r["remoteReviews"] == 5 and r["libraryUpdatedFlag"], r)
r = fw("sync")
check("sem duplicar na sincronização seguinte", r["remoteReviews"] == 0, r)

print("== 6. editar cartão na web ==")
edit = dict(crows[0]); edit["front"] = "O que é a mitocôndria? (editado na web)"; edit["updated_at"] = now + 1000
call("POST", "/v1/sync/push", tok, {"table": "cards", "rows": [edit]})
r = fw("sync")
check("texto atualizado no terminal", r["changed"] and any(c["q"].endswith("(editado na web)") for c in r["cards"]), r)

print("== 7. cartão apagado no app com revisão pendente no terminal ==")
fw("study", "6")
dele = dict(crows[1]); dele["deleted_at"] = now + 2000; dele["updated_at"] = now + 2000
call("POST", "/v1/sync/push", tok, {"table": "cards", "rows": [dele]})
r = fw("sync")
check("revisão do cartão apagado em quarentena, demais enviadas", r["quarantined"] == 1 and r["pushed"] == 5 and r["pendingAfter"] == 0, r)
check("cartão apagado sai do terminal", r["cardCount"] == 5, r["cardCount"])

print("== 8. retenção desejada alterada no app ==")
call("POST", "/v1/sync/push", tok, {"table": "user_settings", "rows": [{"key": "desired_retention", "value": "0.85", "updated_at": now + 3000, "device_id": dev}]})
r = fw("sync")
check("retenção aplicada", r["settings"] == 1 and abs(r["retention"] - 0.85) < 1e-6, r)
r = fw("sync")
check("retenção não reaplicada à toa", r["settings"] == 0, r)

print("== 9. capacidade estourada (limite 3) ==")
r = fw("sync", FW_MAXCARDS=3)
check("409 vira CapacityExceeded sem perder biblioteca", r["outcome"] == "capacity_exceeded" and r["cardCount"] == 5, r)

print("== 10. relógio sem referência ajustado pelo servidor ==")
r = fw("sync", FW_TRUSTED=0, FW_NOW=1500000000)
check("relógio ajustado pelo Date do backend", r["clockAdjusted"] and abs(r["clockNow"] - time.time()) < 120, r)

print("== 11. servidor fora do ar ==")
fw("study", "2")
STATE["api"] = "http://127.0.0.1:8099"
r = fw("sync")
check("Unreachable e outbox preservado", r["outcome"] == "unreachable" and r["pendingAfter"] == 2, r)
STATE["api"] = API
r = fw("sync")
check("ao voltar, fila esvazia", r["outcome"] == "ok" and r["pushed"] == 2, r)

print("== 12. troca de credencial reinicia cursores sem duplicar ==")
st, reg2 = call("POST", "/v1/terminals/register", tok, {"device_id": TERMINAL, "model": "x", "firmware": "y", "deck_ids": [d["id"] for d in decks]})
STATE["terminal_token"] = reg2["device_token"]
before = fw("show")["history"]
r = fw("sync")
check("cursores reiniciados e histórico sem duplicatas", r["outcome"] == "ok" and r["remoteReviews"] == 0 and r["history"] == before, (before, r["history"], r))

print("== 13. terminal revogado na web ==")
call("POST", f"/v1/terminals/{TERMINAL}/revoke", tok)
r = fw("sync")
check("AuthRejected", r["outcome"] == "auth_rejected" and r["authRejected"], r)
l = fw("loop", "4000", "authrejected")
check("sem tentativas periódicas com credencial recusada", l["requests"] == 0, l)

print("== 14. pedido pendente sem rede não faz requisição ==")
p = fw("pending", FW_CONNECTED=0)
check("aguarda Wi-Fi", p["requestsAfterLoop"] == 0 and p["stillPending"], p)

print("== 15. não pareado ==")
STATE["terminal_token"] = ""
r = fw("sync")
check("NotPaired", r["outcome"] == "not_paired" and r["requests"] == 0, r)

ok = sum(1 for _, v in results if v)
print(f"\n{ok}/{len(results)} verificações passaram")
sys.exit(0 if ok == len(results) else 1)
