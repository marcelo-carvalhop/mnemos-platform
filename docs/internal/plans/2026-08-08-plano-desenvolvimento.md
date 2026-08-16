# Development plan — parallel agent execution

**Status:** ready to execute
**Date:** 2026-08-08
**Source:** [technical architecture spec](../specs/2026-08-08-arquitetura-tecnica-design.md) · [functional spec](../../../spec-funcional-app-flashcards.md)

> English, for consistency with the specs it references.

---

## 1. What this document is

The spec says *what* to build and *why*. This says *in what order*, *who may touch which files*, and — the part that makes autonomous execution possible at all — **how each piece proves it works**.

Every task below carries a verification command. An agent implements, runs it, and iterates until it passes. A task without a runnable check is not a task in this plan; it is a human gate, and §8 lists those separately.

---

## 2. Execution model

```
one command
   └─ wave runner
        ├─ reads the wave manifest
        ├─ spawns N agents in parallel, one per track
        ├─ each agent: implement → verify → fix → verify … → report
        └─ gate: next wave starts only when every track in this wave
                 verifies green on a clean checkout
```

**Three rules the runner enforces**, because they are what separate parallel execution from parallel corruption:

1. **A track may only write files it owns** (§5). A write outside its ownership set fails the track, regardless of whether the code works.
2. **A wave gate re-runs the full verification from a clean checkout**, not from the agent's working tree. An agent that passes only in its own environment has not passed.
3. **Green is earned, never granted.** Deleting, skipping or weakening a test to reach green fails the track. The gate checks that the test count never decreases and that no test acquires a skip annotation.

### 2.1 The per-track loop

```
implement the task
run the verification command
├─ green → run it once more on a clean checkout → report done
└─ red   → diagnose, fix, repeat
           after N attempts without progress → STOP and report red
```

**Stopping red is a valid outcome and must be reported as such.** An agent that cannot make a task pass has found something the plan got wrong — a missing dependency, an interface that does not fit, an assumption from the spec that does not hold. That is information. Silently reducing scope to reach green destroys it.

"Without progress" means the same failure twice with no new diagnosis. A different failure each iteration is progress.

---

## 3. Dependency graph and waves

From §14 of the spec, with the parallelism made explicit:

```
wave 0   ┌─ skeleton ────────────────┐   serial, blocks everything
         └─ generation spike ────────┘   independent, informs wave 3

wave 1   ┌─ scheduler (pure Dart) ───┐   parallel
         └─ store + schema ──────────┘

wave 2   ┌─ authoring ───────────────┐
         ├─ study loop ──────────────┤   parallel, 3 tracks
         └─ accounts + sync ─────────┘

wave 3   ┌─ generation ──────────────┐   needs authoring + sync
         ├─ progress ────────────────┤   needs study loop
         └─ alternative modes ───────┘   needs study loop

wave 4   └─ quota + billing ─────────┘   needs generation
```

Wave 0 cannot be parallelised with anything that follows: it produces the contract every other track compiles against. The spike is the exception — it is a standalone Python script that touches no shared file, so it runs alongside wave 0 and its numbers land before wave 3 needs them.

---

## 4. What makes parallelism safe

Three mechanisms, in order of how much they matter.

**The contract exists before the tracks do.** `shared/contract.yaml` (character limits, `grade` and `source` enums, error codes) and the OpenAPI schema are wave 0 outputs. Two agents that generate their own idea of a `Grade` enum produce code that compiles separately and fails together.

**Migrations are append-only, never edited.** §11.4 already requires additive schema changes for offline-first reasons; the same rule removes the worst merge conflict in parallel work. Each track adds **its own numbered migration file** and never touches an existing one. Two tracks adding tables in the same wave produce two files, not one conflict.

**No barrel files.** A single `routers.py` or `providers.dart` that every track must append to is a guaranteed collision. Registration is by convention — a router module per feature discovered at startup, one provider file per feature — so adding a feature adds a file rather than editing a shared one.

**All dependencies are declared in wave 0.** `pubspec.yaml` and `pyproject.toml` are written once, with every package the plan is known to need. A track that discovers it needs a new dependency reports it rather than editing the manifest, and the runner applies it between waves. Concurrent edits to a lockfile are not resolvable automatically.

---

## 5. File ownership

Ownership is per wave. A track owns a path prefix exclusively for the duration of its wave.

| Track | Owns | May read | Must not touch |
|---|---|---|---|
| 0 skeleton | everything (nothing else runs) | — | — |
| 0 spike | `spikes/generation/**` | specs | anything under `app/`, `server/` |
| 1 scheduler | `app/packages/scheduler/**` | `app/packages/domain/**` | `app/lib/**`, `server/**` |
| 1 store | `app/lib/store/**`, `app/lib/migrations/**` | `app/packages/domain/**` | `app/packages/scheduler/**` |
| 2 authoring | `app/lib/features/decks/**`, `app/lib/features/editor/**` | store, domain, scheduler | `app/lib/sync/**` |
| 2 study | `app/lib/features/study/**`, `app/lib/notifications/**` | store, domain, scheduler | `app/lib/sync/**` |
| 2 sync | `app/lib/sync/**`, `server/auth/**`, `server/sync/**` | store, domain | `app/lib/features/**` |
| 3 generation | `server/generation/**`, `server/ingest/**`, `server/worker/**`, `app/lib/features/generate/**` | contract, sync | `server/auth/**` |
| 3 progress | `app/lib/features/progress/**` | store, domain, scheduler | everything else |
| 3 modes | `app/lib/features/modes/**` | store, domain, scheduler | everything else |
| 4 billing | `server/billing/**`, `server/quota/**`, `app/lib/features/billing/**` | all | — |

`shared/contract.yaml` is owned by wave 0. Later waves that need a new constant **report it**; the runner applies the change between waves and regenerates. This is deliberately rigid: a shared constant edited by two tracks at once is the exact failure the file exists to prevent.

---

## 6. The tracks

Each entry: goal, done criteria, verification command.

### Wave 0 — Skeleton

**Goal.** The repository compiles, containerises, tests and generates code end to end, with one trivial route proving the whole chain.

Deliverables:

- `.gitignore` (Flutter, Python, `.env`, Docker artefacts)
- `shared/contract.yaml` + generators producing a Dart file and a Python module
- `app/packages/domain/**` — entities and value types (`Grade`, `CardId`, `ReviewSource`, …), no dependencies
- `docker/server.Dockerfile` (multi-stage, non-root), `compose.yaml` (postgres, minio, server, worker), `.dockerignore` excluding `app/`, `.env.example`
- alembic wired to run as a one-shot command, **not** in the entrypoint (§11.7)
- drift wired with migration v1
- one route with explicit `operation_id` and a declared response model → generated Dart client, committed
- `/healthz` (no external checks) and `/readyz` (checks the database)
- CI: build the image, run every suite inside it, against a pinned Postgres service container
- `import-linter` and the Dart import lint configured, with the contracts from §12.1 already declared even though most layers are still empty

**Done when:** a clean clone runs one command and reaches green.

```
docker compose up -d
alembic upgrade head          # separate command, by design
curl -f localhost:8000/healthz
curl -f localhost:8000/readyz
pytest && dart test
dart run build_runner build   # generated client matches committed client
lint-imports                  # architecture contracts pass
```

### Wave 0 — Generation spike (parallel, standalone)

**Goal.** Replace four invented numbers in §7 with measurements. Not production code; it is deleted or archived afterwards.

Feeds: a topic, a pasted text, a real PDF, a scanned PDF, a photo of handwritten notes in Portuguese, a photo of a whiteboard.

Measures, per input type:

| Question | §7 claim under test |
|---|---|
| Share of generated cards within 120/240 graphemes | the "+20% and drop" rule (§7.6) |
| `tokens_in` / `tokens_out` | the 20 generations/month quota (§7.7) |
| Latency at `effort` low / medium / high | "alguns segundos" (§5.5) |
| Does a scanned PDF actually work without an extraction stage? | "no OCR service" (§7.1) |
| Does `needs_specification` fire on a vague topic? | the union schema (§7.5) |
| Refusal rate on biochemistry, infosec, toxicology | §10 |
| Opus 5 vs Sonnet 5 at equal effort | the model choice (§7.4) |

**Done when:** a results table exists and §7.4, §7.6 and §7.7 have been updated with real figures — or explicitly confirmed.

```
python spikes/generation/run.py --all --report
```

### Wave 1a — `scheduler`

**Goal.** The pure package of §4.1: `apply`, `replay`, `preview`. No I/O, no ambient clock, no randomness.

**Verification:**

```
dart test app/packages/scheduler
```

Must include: reference vectors against the FSRS implementation on a fixed corpus; property tests (replay twice is identical; `preview` agrees with what `apply` writes; a `progress_reset` makes replay match a fresh card); and the fuzz-disabled assertion of §12.1.

### Wave 1b — Store and schema

**Goal.** Every table of §5, the indexes of §5.6, FTS5 with `remove_diacritics 2`, the immutability triggers of §5.2, and the day-bucketing function of §5.7.

**Verification:**

```
dart test app/lib/store
pytest server/tests/schema
```

Must include: `UPDATE`/`DELETE` on `reviews` fail as the application role (§12.1); a migration test from v1; accent-insensitive search finds "função" when given "funcao"; the day boundary at 04:00 local behaves across a DST transition.

### Wave 2a — Authoring

Deck CRUD with the cycle, depth and subtree rules of §5.1; the manual editor with the hard character limit; the device preview; bulk operations of §5.10.

```
dart test app/lib/features/decks app/lib/features/editor
```

Must include the shared grapheme fixture of §7.6 — composed and decomposed accents, emoji — and a cycle-rejection test.

### Wave 2b — Study loop

The session of §5.8: front, reveal, four grades **each showing its resulting interval**, daily limits separated for new and review, suspend and bury, every answer written on the spot. Plus the local notification of §11.5.

```
dart test app/lib/features/study app/lib/notifications
```

Must include: leaving mid-session preserves what was reviewed; the displayed interval equals what the review writes; the new-card limit is independent of the review limit.

### Wave 2c — Accounts and sync

Auth with the anonymous device token of §8.1; outbox with dependency order, coalescing and idempotency (§6.4); pull by `server_seq` keyset (§6.2); LWW with tombstones; `410 resync_required` (§6.3); bootstrap (§6.5).

```
pytest server/tests/sync server/tests/auth
dart test app/lib/sync
```

Must include: two simulated devices converge; concurrent offline reviews merge as a union; a device past the tombstone horizon receives 410 and recovers; a client cannot write into another account by supplying a foreign id; **and a model-based test running randomised operation interleavings across two devices, asserting convergence**. A failed refresh while offline must not clear the session (§8.2).

### Wave 3a — Generation

The pipeline of §7 with the numbers the spike produced. Job queue on Postgres with `SKIP LOCKED`; pre-signed upload; the four inputs; structured output; the `constrain` stage; quota reservation as a single statement; the approval queue with `cards.id := pending_cards.id`; refusal handling (§10).

```
pytest server/tests/generation
dart test app/lib/features/generate
```

The model API is **mocked** here — recorded responses, including a refusal and a `needs_specification`. Live-model behaviour was the spike's job; this track tests our code, deterministically.

Must include: two concurrent reservations cannot exceed the limit; an expired reservation is swept; a replayed decision push produces no second card; `stop_reason: "refusal"` charges no quota.

### Wave 3b — Progress

Every metric of §9, including the streak against `goal_history` and the derived monthly forgivenesses.

```
dart test app/lib/features/progress
```

Must include: lowering the daily goal does **not** retroactively convert past days into successes.

### Wave 3c — Alternative modes

Multiple choice with the conservative grade mapping of §5.2 (`fácil` is never inferred); leech drill; timed simulado; TTS.

```
dart test app/lib/features/modes
```

Must include: the drill, the simulado and the TTS session write **no** review row.

### Wave 4 — Quota and billing

Store entitlement of §8.3 with the real subscription states; export and deletion of §8.4.

```
pytest server/tests/billing server/tests/quota
```

Store webhooks are mocked. Real store validation is a human gate (§8).

---

## 7. Cross-wave verification

Between waves the runner executes the full suite plus:

```
lint-imports                       # §12.1 architecture contracts
dart analyze --fatal-infos
docker compose up -d && pytest     # integration against the real stack
```

And a **test-count check**: total tests must be greater than or equal to the previous wave's. A wave that adds features and loses tests has hidden something.

---

## 8. What agents cannot validate — human gates

Listed so the plan does not pretend otherwise. Each blocks release, not development.

| Gate | Why an agent cannot close it | When |
|---|---|---|
| **iOS build and device testing** | Requires macOS and Xcode; not runnable in a Linux container | before any release |
| **Card generation quality** | "Are these good flashcards in Portuguese?" has no executable oracle. The spike measures cost, latency and limits — not pedagogy | after the spike, before wave 3a |
| **The eight missing flows of §13** | Onboarding, editor, generation, capture, alternative modes, deck management, quota, restore have no screen in the design. Agents cannot implement screens that were never designed | before waves 2 and 3 |
| **The design corrections of §13** | Removing XP, fixing "68% concluído", adding intervals to the grade buttons — product decisions already agreed, but they must land in the canvas | before wave 2b |
| **Store subscriptions** | Requires real App Store / Play sandbox accounts and app review | before wave 4 ships |
| **LGPD wording** | Export and deletion are implementable; the privacy policy is not an engineering artefact | before release |

**The design gate is the real schedule risk.** Wave 2 needs screens that do not exist yet — this is not a coding problem and no amount of parallelism shortens it.

---

## 9. What each agent receives

A task file per track:

```yaml
track: 2b-study
wave: 2
goal: <one paragraph>
spec_sections: [5.8, 11.5, 12]
owns: [app/lib/features/study/**, app/lib/notifications/**]
may_read: [app/lib/store/**, app/packages/**]
must_not_touch: [app/lib/sync/**, shared/contract.yaml]
verify: dart test app/lib/features/study app/lib/notifications
required_tests:
  - leaving mid-session preserves reviewed cards
  - displayed interval equals the interval written
  - new-card limit independent of review limit
max_iterations: 6
on_stuck: report red with the failing output and the diagnosis
```

`spec_sections` matters: the agent reads the spec, not a paraphrase. Every decision it needs is already written down, with its reasoning — that is what the spec is for.

---

## 10. Order of execution

| Step | Runs | Blocked by |
|---|---|---|
| 1 | wave 0 skeleton **+** spike, parallel | — |
| 2 | update §7 with the spike's numbers | spike |
| 3 | design gate: missing flows and §13 corrections | — (start immediately, in parallel with everything) |
| 4 | wave 1: scheduler ∥ store | skeleton |
| 5 | wave 2: authoring ∥ study ∥ sync | wave 1, design gate |
| 6 | wave 3: generation ∥ progress ∥ modes | wave 2, §7 update |
| 7 | wave 4: quota + billing | wave 3 |

**The design gate starts now**, not at step 5. It is the only item on this list that parallelism cannot compress, and it is a prerequisite for the largest wave.

---

## 11. Honest limits of this plan

**Parallelism buys less than the wave diagram suggests.** Waves 0 and 1 are nearly serial and produce the contract everything else depends on; the width is in waves 2 and 3. Expect three tracks at once at best.

**Agents converge fastest where the oracle is strongest.** `scheduler` is close to ideal — pure functions, property tests, reference vectors. Sync is good, via simulated devices. UI is weak: tests prove wiring, not that the screen is usable.

**A red track is a finding, not a failure.** The most valuable output of a stuck agent is the specification defect it found. The spec has already been through one review that fixed four real defects; the second review is execution.
