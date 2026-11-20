"""Terminal Mnemos simulado: faz pela rede o mesmo que o firmware t5s3-pro.

Espelha BackendSyncService::syncNow() (firmware/t5s3-pro/src/backend_sync_service.cpp):
push de revisões -> snapshot -> pull reviews -> pull resets -> pull settings -> status.
O estado (token, cursores, biblioteca, outbox) fica num JSON, como a flash da placa.

Só biblioteca padrão do Python. Veja tools/terminal-sim/README.md.

  register <app_device_id> <deck_id>[,<deck_id>...]
  sync
  study <n>          # revisa n cards da biblioteca local -> outbox
  show

Variáveis: MNEMOS_API (padrão http://localhost:8000), MNEMOS_SIM_STATE,
MNEMOS_SIM_TERMINAL_ID.
"""

import json
import os
import sys
import time
import urllib.error
import urllib.request
import uuid

BASE = os.environ.get("MNEMOS_API", "http://localhost:8000").rstrip("/")
STATE = os.environ.get("MNEMOS_SIM_STATE", "/tmp/terminal_sim_state.json")
TERMINAL_ID = os.environ.get("MNEMOS_SIM_TERMINAL_ID", "T5S3-SIM-0001")
MAX_CARDS = 48  # limite padrão do snapshot


def load():
    try:
        with open(STATE) as f:
            return json.load(f)
    except FileNotFoundError:
        return {}


def save(s):
    with open(STATE, "w") as f:
        json.dump(s, f, ensure_ascii=False, indent=1)


def call(method, path, token=None, body=None):
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(BASE + path, data=data, method=method)
    req.add_header("Content-Type", "application/json")
    if token:
        req.add_header("Authorization", "Bearer " + token)
    try:
        with urllib.request.urlopen(req, timeout=10) as r:
            return r.status, json.loads(r.read() or b"{}")
    except urllib.error.HTTPError as e:
        return e.code, e.read().decode()[:300]


def register(app_device_id, deck_csv):
    st, auth = call("POST", "/v1/auth/device", body={"device_id": app_device_id, "platform": "android"})
    assert st == 200, (st, auth)
    decks = deck_csv.split(",")
    st, reg = call("POST", "/v1/terminals/register", auth["access_token"], {
        "device_id": TERMINAL_ID, "model": "Mnemos T5S3 Pro (simulado)",
        "firmware": "sim-0.7.0", "deck_ids": decks,
    })
    assert st == 200, (st, reg)
    save({"token": reg["device_token"], "cursors": {"reviews": 0, "resets": 0, "settings": 0},
          "library": {}, "revision": 0, "outbox": [], "seen_reviews": 0})
    print(f"[register] terminal {TERMINAL_ID} registrado, protocolo {reg.get('protocol')}, baralhos={len(decks)}")


def sync():
    s = load()
    tok = s["token"]
    ok = {}

    # 1. pushReviews
    if s["outbox"]:
        st, r = call("POST", "/v1/terminal/reviews", tok, {"schema": "mnemos.review-batch/v2", "reviews": s["outbox"]})
        ok["push"] = 200 <= st < 300
        print(f"[push] {len(s['outbox'])} revisões -> HTTP {st} {r if not ok['push'] else ''}")
        if ok["push"]:
            s["outbox"] = []
    else:
        ok["push"] = True
        print("[push] outbox vazia")

    # 2. pullSnapshot
    st, snap = call("GET", f"/v1/terminal/snapshot?limit={MAX_CARDS}&schema=mnemos.sync%2Fv2", tok)
    ok["snapshot"] = st == 200 and snap.get("schema") == "mnemos.sync/v2"
    if not ok["snapshot"]:
        print(f"[snapshot] HTTP {st} {snap}")
    else:
        old = s["library"]
        new = {}
        for c in snap["cards"]:
            assert c.get("schema") == "mnemos.card/v2", c.get("schema")
            new[c["id"]] = {
                "deck": c["deckId"], "type": c["type"],
                "q": c["content"]["prompt"]["text"], "a": c["content"]["answer"]["text"],
                "rev": c.get("metadata", {}).get("revision", 1),
            }
        added = [k for k in new if k not in old]
        removed = [k for k in old if k not in new]
        changed = [k for k in new if k in old and (new[k]["q"], new[k]["a"], new[k]["rev"]) != (old[k]["q"], old[k]["a"], old[k]["rev"])]
        types = sorted({c["type"] for c in new.values()})
        print(f"[snapshot] {len(new)} cards em {len(snap.get('decks', []))} baralhos, tipos={types}, "
              f"novos={len(added)} alterados={len(changed)} removidos={len(removed)}")
        for k in changed:
            print(f"   ~ alterado: {old[k]['q']!r}\n           -> {new[k]['q']!r} (rev {old[k]['rev']}->{new[k]['rev']})")
        s["library"] = new
        s["revision"] += 1

    # 3-5. pulls incrementais (só se o snapshot passou, como no firmware)
    for name, path, key in (("reviews", "/v1/terminal/reviews", "reviews"),
                            ("resets", "/v1/terminal/progress-resets", "resets"),
                            ("settings", "/v1/terminal/settings", "settings")):
        if not ok["snapshot"]:
            ok[name] = False
            continue
        total = 0
        while True:
            st, r = call("GET", f"{path}?since={s['cursors'][name]}", tok)
            if st != 200:
                print(f"[{name}] HTTP {st} {r}")
                ok[name] = False
                break
            total += len(r.get(key, []))
            s["cursors"][name] = r["cursor"]
            if not r.get("hasMore"):
                ok[name] = True
                break
        if ok.get(name):
            print(f"[{name}] +{total} (cursor={s['cursors'][name]})")

    synced = all(ok.values())
    st, _ = call("POST", "/v1/terminal/status", tok, {
        "reported_deck_ids": sorted({c["deck"] for c in s["library"].values()}),
        "card_count": len(s["library"]), "max_cards": MAX_CARDS,
        "connectivity": "wifi", "wifi_ssid": "bancada-sim",
        "library_revision": s["revision"], "synced": synced,
    })
    print(f"[backend] sync push={ok['push']:d} snapshot={ok['snapshot']:d} reviews={ok['reviews']:d} "
          f"resets={ok['resets']:d} settings={ok['settings']:d} status={int(200 <= st < 300)}")
    save(s)


def study(n):
    s = load()
    now = int(time.time() * 1000)
    ids = list(s["library"])[: int(n)]
    for i, cid in enumerate(ids):
        at = now - (len(ids) - i) * 20_000
        s["outbox"].append({
            "schema": "mnemos.review/v2", "id": str(uuid.uuid4()), "cardId": cid,
            "reviewedAtMs": at, "dueAfterMs": at + 3 * 86_400_000,
            "schedulerRating": 3, "responseTimeMs": 4200, "source": "standard",
        })
        print(f"[study] Bom em {s['library'][cid]['q'][:60]!r}")
    save(s)
    print(f"[study] outbox={len(s['outbox'])}; ids={[r['id'] for r in s['outbox']]}")


def show():
    s = load()
    for cid, c in s["library"].items():
        print(f"{cid}  [{c['type']}] rev{c['rev']}  {c['q'][:70]}")


cmd, *args = sys.argv[1:]
{"register": register, "sync": sync, "study": study, "show": show}[cmd](*args)
