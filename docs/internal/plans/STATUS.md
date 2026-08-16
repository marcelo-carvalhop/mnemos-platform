# Status — 2026-08-09

Where the build stands, what is verified, and what to pick up next.

**Everything below is committed and pushed.**

CI had never been green — not once since the commit that added it. Every suite
below really does pass, and I ran them, but I ran them *locally* and reported
that as though it were the pipeline. Two jobs were failing the whole time for
reasons that only exist on a fresh checkout, which is exactly the class of
failure a pipeline is for. Both are fixed; the lesson is that "I ran the tests"
and "CI is green" are different sentences.

```
420 tests   9 Dart packages (209) · app (44) · server (157) · 1 live
1 emulator  generation walked end to end on a device, real model included
0 red       contract --check, flutter analyze, dart analyze, import contracts
20 routes   auth, sync, quota, generation, ops — every one typed
25 screens  design/telas-faltantes.dc.html — nothing left undesigned
2 real      generations end to end through the queue, against the live model
```

Bring the stack up: `docker compose up -d` then `docker compose run --rm migrate`.

---

## Done and verified

| Wave | Piece | Verification |
|---|---|---|
| 0 | `shared/contract.yaml` + codegen → Dart and Python | `--check` fails on drift; CI runs it |
| 0 | `domain` package — Uuid7, grapheme text, entities | 24 tests |
| 0 | Container stack: postgres, minio, server, worker | four services healthy; `/healthz`, `/readyz` |
| 0 | alembic as a one-shot step, three migrations | applied; idempotence asserted in CI |
| 0 | CI: contract, dart matrix, server-in-image, import contracts | `.github/workflows/ci.yml` |
| 0 | Generation spike | 9 probes, US$ 0.27, §7 updated with measurements |
| 1a | `scheduler` — FSRS, apply/replay/preview, no fuzz | 20 tests |
| 2c | Sync service — §6 protocol | 18 tests against real Postgres |
| 4 | Quota — one generation per lifetime | 11 tests |
| 2c/4 | **Auth** — anonymous device, signup, login, rotation | 18 tests, end to end |
| 2c/4 | Sync and quota routers | reachable over HTTP |
| 3a | Generation — queue, constrain, approval queue | 26 tests |
| 1b | Client store — drift schema, FTS5, day bucketing | 24 tests |
| 2b | Study loop — record, replay, limits, outbox | 22 tests |
| 2a | Authoring — deck tree, character limit, bulk ops | 20 tests |
| 3b | Progress — every §9 metric, streak, milestones | 22 tests |
| 2c | Sync client — outbox drain, delta apply, resync | 15 tests |
| 3c | `modes` — multiple choice, leech drill, simulado, audio | 21 tests |
| — | **Flutter app** — theme, Riverpod composition, 11 screens | 10 tests, `flutter analyze` clean |
| 3a | **The real model call** — worker drains the queue | 17 tests + live generations |
| 3a | **Generation router** — the whole §7 flow over HTTP | 12 tests + walked end to end |
| 4 | **Attestation** — challenge, Play Integrity, App Attest | 23 tests |
| 3a | **Generation in the app** — request, progress, approval, paywall | 7 tests + walked on a device |
| 5.1 | **Onboarding** — four steps, the free generation announced | 6 tests + walked on a device |
| 5.11 | **Progress** — memory, retention, forecast, heatmap, maturity | on §9's tested metrics |
| 5.12 | **Settings** — limits, retention target, day cutoff, account | 5 tests |
| 5.10 | **Search** — FTS5, accent-insensitive | 9 tests |
| 5.6 | **Capture** — camera, gallery, PDF, pre-signed upload | 4 tests + a PDF read on a device |
| 8.4 | **Export and deletion** — LGPD, past an append-only table | 10 tests |
| 11.5 | **Local reminders** — one notification, no backend | 5 tests |
| 5.10 | **Deck management** — rename, archive, delete | on tested authoring ops |
| 5.13 | **Subscription** — status, restore, what stays free | store is a human gate |
| 2c | **`api_client`** — transport, token rotation, error shapes | 19 tests |
| 2c | **Sync wired into the app** — badge, lifecycle, triggers | 8 tests + a live round trip |

### What the spike changed in the spec

- **Scanned PDF needs no OCR stage** — confirmed with a PDF containing no `/Font` at all. This was §7.1's riskiest claim and it was taken from documentation, not a test.
- **The 20% overgeneration was removed** — zero violations in 108 cards.
- **`effort: high` rejected** — +94% cost, 68% slower, no better output.
- **§5.5's "alguns segundos" is wrong** — 10 to 24 seconds measured. The functional spec needs amending.
- Cost per generation: **US$ 0.0289** (Opus 5, medium) / **US$ 0.0124** (Sonnet 5).

---

## Next, in order

**1. The screens that exist in the canvas but not in the app.** Onboarding, generate-by-topic, capture, the paywall and restore are designed and specified; the app currently seeds a deck on first run instead. None of them is blocked.

**2. The generation flow in the app.** The server side is done and proven; the app has no screen that enqueues a job yet.

**2. Deck management (§5.10) and subscription management (§5.13)** — still undesigned, and the only two left.

---

## Blocked

**Nothing is blocked on design any more.** The canvas now carries 21 screens; §5.9's seven closed the last gate that a wave depended on. Deck management (§5.10) and subscription management (§5.13) remain undesigned but neither blocks the build order.

**Two human gates remain**, in the sense that I cannot verify them from here: the store billing sandbox and an iOS build (needs macOS).

The third — card quality — is now answerable. Two real generations ran through the queue against the live model; their output is in `pending_cards` and reads well (short, one idea per card, no preamble). Worth your eyes before wave 3a is called done, but it is no longer unmeasured.

**The handwriting photo** was dropped by decision. The scanned-PDF probe covers the "no OCR" claim; what stays unmeasured is a real photograph — angle, lighting, cursive. Worth revisiting before wave 3a ships.

---

## Decisions taken autonomously

All are reversible and each lives in one place.

**Device attestation moved from "held in reserve" to required in v1.** Direct consequence of the free tier becoming one generation per lifetime: with a monthly allowance a reinstall leaked a fraction and cost three cents; now it doubles everything a user was ever given, and the anonymous device token is the only thing in the way. Recorded in §8.1.

**`server_seq` comes from a per-user counter under `FOR UPDATE`, not a Postgres sequence.** A sequence is monotonic but not commit-ordered — a transaction drawing a low value and committing late is invisible to a device that already pulled past it, which is the same hole §6.2 describes for timestamps.

**The quota period is `lifetime` for free and `YYYY-MM` for paid**, so one code path serves both instead of forking the reservation logic.

**No router without auth.** I stopped rather than ship endpoints with a placeholder identity.

**The three non-scheduling modes were given no way to write.** §5.9 says the leech drill, the simulado and the audio session must not feed FSRS. Rather than a flag someone has to remember to check, only `MultipleChoiceMode` receives a `StudyService` — the other three are constructed with the database alone, so the guarantee is structural. The interface carries the same distinction as a badge, green against amber, because §5.9 requires it to be visible too.

**Multiple choice never infers *fácil*.** One option in four is a 25% chance of guessing right; letting that buy the longest interval feeds noise into stability and degrades the schedule over months. Wrong → *errei*, correct-and-slow → *difícil*, correct-and-fast → *bom*, with the threshold in `contract.yaml` rather than in a widget.

**A question the deck cannot furnish with distinct distractors is skipped, not padded.** A two-option question is a coin toss, and multiple choice writes to the review log — a coin toss would be recorded as if it meant something.

**The app's tests are deliberately few**, and spent where behaviour is not reachable from the packages: the Riverpod composition, and the grapheme limit in the editor, which lives in the interface because it exists for a device screen that does not ship yet.

---

## Bugs found by verifying, not by reading

Recorded because each would have been silent:

**`rowcount` is `-1` in psycopg3 for `INSERT ... ON CONFLICT`** — and `-1` is truthy. Every push looked applied, including the replays and stale writes the function exists to reject. Two tests failed on it; now decided by `RETURNING`.

**`python -m importlinter.cli` exits 0 and prints nothing.** The architecture check had been verifying nothing at all. The real console script reports a config error instead. Fixed, and proven by adding a deliberate `from fastapi import APIRouter` to a forbidden module.

**The worker inherited the image's HTTP healthcheck** and reported unhealthy with a failing streak of 7 while running correctly. It now writes a heartbeat file the check reads, which proves the loop is turning rather than that the process exists.

**The spike billed cached tokens at full price**, which would have made prompt caching look useless on exactly the calls it makes cheap.

**Two of my tests were wrong, not the code.** The tombstone-horizon test pushed a row LWW correctly rejected, so the cursor never advanced; the free-tier rollover test never committed its reservation, so the expiry sweeper correctly released it. Both now assert the real scenario.

**The leech drill had to read past `progress_resets`.** Counting lapses straight from the log meant a card the user had deliberately restarted (§5.10) stayed labelled a leech forever, because §3 forbids deleting its history. The query now counts only reviews after the last reset marker — the history survives, the label does not.

**`DropdownButtonFormField.initialValue` does not exist on Flutter 3.32.** It is `value` until 3.35. Caught by `flutter analyze`, which is why CI now pins the same version the machine runs.

**The structured output is JSON inside a text block, not a `.parsed` attribute** — and the refusal category is on `stop_details`, not on the response. I wrote the parser from memory instead of from the spike that had already recorded both, and the worker's first live call returned 200 OK and then failed to read it. The spike existed precisely to settle this; not reading it back was the mistake.

**Cache tokens are not part of `input_tokens`.** The first real generation reported 54 input tokens against a system prompt of several hundred; the second recorded 873 cache reads against 48 input. §7.4's prefix caching works, and storing only `tokens_in` was understating every job by whatever the cache served. A cache read bills at 0.1x and a write at 1.25x, so the three figures are not interchangeable — migration `0006_cache_metering` records them apart, which is what §7 requires for repricing not to be guesswork.

**A test that would have passed in CI and failed on your machine.** `run_one` claims whatever job is oldest, by design, so the runner tests were sensitive to jobs already sitting in the development database. Fixed with a fixture that hides pre-existing queued rows inside the test transaction.

**The two halves of §6 disagreed about two things, and neither suite could see it.** `sync_client` was tested against a fake server that echoed whatever it was given; the server was tested with Python objects no client ever sends. Wiring them found both in the first live round trip.

The server never told the client which `server_seq` each row got — only a high-water mark. `server_seq IS NULL` is what "not yet synced" means locally, so nothing could ever leave the outbox and every row would be pushed again forever. Push now returns an `assigned` map, including for rows rejected as stale: those get the winning row's sequence, so they stop being pending and the next pull replaces their contents.

And nobody had decided the wire format for time. SQLite has no timestamp, so the client stores epoch milliseconds; Postgres has `timestamptz` and should keep it. The first real push failed with `cannot cast type bigint to timestamp with time zone`. Milliseconds is now the wire format in both directions, converted once at the edge — chosen over ISO-8601 because `updated_at` decides last-writer-wins and integers compare exactly.

### Deleting an account was going to be a free-generation faucet

§8.4 says an account can be deleted; §8.1 exists because a reinstall must not
mint a second free generation. Delete-and-register-again is the same attack
with one extra step, and the first version of the deletion did exactly that —
it removed the device row along with everything else.

The device now outlives the account, carrying one fact: that its free
allowance was spent. A random client-generated id and a boolean, with no name,
no email and no study data attached. Retaining an identifier for anti-abuse is
defensible; retaining a person is not, so what survives is asserted in a test
rather than assumed.

The first attempt at that was still wrong, and a test caught it: the "was it
spent" read ran *after* `quota_usage` had been deleted, so it always answered
"never" — which is precisely the answer that reopens the hole.

### The pre-signed URL pointed at a hostname no phone can resolve

§7.2 said the client uploads straight to storage and never said **which
address**. The server signed against `http://minio:9000`, which is a container
name — and a pre-signed URL is signed against its host, so it cannot simply be
rewritten by the client. There are two endpoints now: the internal one the
server and worker use, and the public one the signature is made for. In a
single-host deployment they are the same string; anywhere else, getting it
wrong fails with a DNS error naming the container, which is at least a
legible way to be wrong.

### Two of a kind: "no data" rendered as a number

**Retention read 0% on an account that had never answered a card.** The
service returned 0.0 for an empty log, and rendered that says "you get
everything wrong" to someone who has not started. It returns null now — the
type is what stops a caller showing one as the other — and the screen says the
number appears after the first answers. Exactly the same mistake as the empty
state below, in a different place, which is what makes it worth naming as a
kind rather than as an incident.

**Search had an index, triggers and no function.** `remove_diacritics 2` was
chosen months ago for Portuguese and nothing had ever searched through it.
There are nine tests now, including the one that justifies the setting: typing
"funcao" finds "função". Also that FTS5 syntax typed by a user is text — an
unbalanced quote is a SQL error, and a search box must never throw because of
what was typed into it.

### One from onboarding, which only appeared once seeding stopped

**A brand-new account was told its memory was working away on its own.** With
no cards at all, Hoje showed §5.2's completion state — "nada vencendo agora" —
because "nothing due" and "nothing exists" were the same condition. They are
different sentences and the second one is an invitation, not a reassurance.
Invisible until onboarding replaced `seedIfEmpty`, because there had always
been four cards.

### Two more, from driving the generation flow

**A button that looked enabled and did nothing.** `_deckId` stayed null until
someone touched the dropdown, while the dropdown itself *displayed* the first
deck — so submit bailed silently on a screen that looked ready. One resolved
value now feeds both, and with no decks at all the screen says so.

**`ReviewSource.multipleChoice.name` is `multipleChoice`; the contract says
`multiple_choice`.** The client had been writing the Dart member name into a
text column the server reads by wire value — a divergence that would have sat
there silently, since nothing constrains that column. The generated Dart enums
now carry their wire value, `fromWire` round-trips, and the error copy switches
on the enum rather than on strings, so a code added to `contract.yaml` shows up
as a missing case instead of a generic message nobody notices.

### Four defects the emulator found that no suite could

The app builds and runs on Android now. Everything below was green in CI at
the time, and every one of these was real.

**Pulling `reviews` from another device threw and the throw went nowhere.**
The server sends `scheduler_version` and `app_version`; the client's table did
not have them, so the INSERT failed — inside a fire-and-forget sync, where the
only trace was one line in logcat while the badge cheerfully reported nothing
pending. §5.3 already said devices run several versions behind and schema
changes are additive, so the client now drops columns it does not know rather
than dying on them, the two schemas were brought back into line (schema v2,
migrated in place), and the controller reports an unexpected failure instead of
swallowing it.

**"Estudar agora · 4" after answering all four.** The queue was not invalidated
when a session ended, so §5.2's completion state never appeared and the button
offered cards that were no longer due.

**The sync badge claimed four changes were waiting after the server had them.**
Check-then-act, twice: guarding on "is a sync running" before the read is not
enough, and neither is checking again afterwards — by then the sync has
usually finished, so there is nothing in flight to see. It takes an epoch
counter. Worth recording that the first two fixes were both shipped and both
wrong, and that the test only caught it once the interleaving was forced with a
gate instead of hoped for with timing.

**The Android build did not exist.** `flutter_local_notifications` needs core
library desugaring, `flutter_tts` needs compileSdk 36, and
`flutter_secure_storage` wants API 23 for a keystore-backed store — below which
it quietly falls back to plain preferences, which is not where a refresh token
belongs. minSdk is 24 now, set by what the plugins require.

**Windows-specific:** `.gitattributes` forces LF on shell scripts — `entrypoint.sh` with CRLF fails inside a Linux container with an error naming the script rather than the interpreter.
