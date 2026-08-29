#!/usr/bin/env python3
"""Generate the shared contract into Dart, Python, TypeScript and C++.

Spec §4: character limits, enums and error codes are declared once in
contract.yaml and consumed by both sides. The generated files are committed,
and CI regenerates and diffs them, so a stale generated file fails the build
rather than silently disagreeing with its source.

    python shared/generate.py           # write the generated files
    python shared/generate.py --check   # exit 1 if they are out of date
"""

from __future__ import annotations

import argparse
import pathlib
import sys

import yaml

ROOT = pathlib.Path(__file__).resolve().parent.parent
CONTRACT = ROOT / "shared" / "contract.yaml"
DART_OUT = ROOT / "app" / "mobile" / "packages" / "domain" / "lib" / "src" / "contract.g.dart"
PY_OUT = ROOT / "backend" / "app" / "contract.py"
TS_OUT = ROOT / "app" / "web" / "src" / "app" / "core" / "contract.g.ts"
CPP_OUT = ROOT / "firmware" / "t5" / "include" / "mnemos_contract_generated.h"

BANNER_LINES = [
    "GENERATED FROM shared/contract.yaml — DO NOT EDIT.",
    "Regenerate with: python shared/generate.py",
]


def _dart(c: dict) -> str:
    limits = c["card_limits"]
    sched = c["scheduling"]
    quota = c["quota"]
    modes = c["modes"]
    generation = c["generation"]

    grades ="\n".join(
        f"  /// {g['label_pt']} (wire value {g['value']})\n"
        f"  {g['dart']}({g['value']}),"
        for g in c["grades"]
    )
    # The Dart member is camelCase and the wire value is not, so each member
    # carries its wire value. Without it every client-side mapping hardcodes a
    # snake_case string — which is the thing §10 exists to stop.
    sources = "\n".join(f"  {_camel(s)}('{s}')," for s in c["review_sources"])
    statuses = "\n".join(f"  {_camel(s)}('{s}')," for s in c["card_statuses"])
    errors = "\n".join(f"  {_camel(e)}('{e}')," for e in c["error_codes"])
    milestones = ", ".join(str(d) for d in sched["graduation_milestone_days"])
    weights = ", ".join(repr(w) for w in sched["fsrs_weights"])
    learning_steps = ", ".join(
        f"{seconds}U" for seconds in sched["learning_steps_seconds"]
    )
    relearning_steps = ", ".join(
        f"{seconds}U" for seconds in sched["relearning_steps_seconds"]
    )

    banner = "\n".join(f"// {line}" for line in BANNER_LINES)
    return f"""{banner}

/// Contract version; bumped when this file's shape changes.
const int kContractVersion = {c['version']};

/// §7.6 — counted in grapheme clusters over NFC-normalised text.
const int kFrontMaxGraphemes = {limits['front_max_graphemes']};
const int kBackMaxGraphemes = {limits['back_max_graphemes']};

/// §4 — maturity is a query predicate, never a stored column.
const int kMatureIntervalDays = {sched['mature_interval_days']};
const double kDesiredRetention = {sched['desired_retention']};
const List<int> kGraduationMilestoneDays = [{milestones}];

/// §4.1 — o vetor FSRS padrão. Declarado no contrato porque cada plataforma
/// usa um pacote diferente e os padrões deles não coincidem.
const List<double> kFsrsWeights = [{weights}];

/// §5.7 — the day rolls over at 04:00 local, not midnight.
const int kDefaultDayCutoffHour = {sched['default_day_cutoff_hour']};
const List<int> kLearningStepsSeconds = {sched['learning_steps_seconds']};
const List<int> kRelearningStepsSeconds = {sched['relearning_steps_seconds']};
const int kMaximumIntervalDays = {sched['maximum_interval_days']};
const bool kEnableFsrsFuzz = {str(sched['enable_fuzz']).lower()};

/// §7.7 — one generation for the lifetime of the account, not per month.
const int kFreeGenerationsLifetime = {quota['free_generations_lifetime']};
const int kMaxJobsInFlight = {quota['max_jobs_in_flight']};

/// §7.3 — teto do assunto ou do texto colado. Sem ele o corpo da requisição
/// vira o prompt, e o custo de uma geração é medido em tokens.
const int kTopicMaxChars = {generation['topic_max_chars']};

/// §5.9 — alternative modes. The grade mapping is a scheduling decision, so
/// its numbers live in the contract rather than in a widget.
const int kMultipleChoiceOptions = {modes['multiple_choice_options']};
const int kMultipleChoiceFastAnswerMs = {modes['multiple_choice_fast_answer_ms']};
const int kLeechMinLapses = {modes['leech_min_lapses']};
const int kSimuladoDefaultQuestions = {modes['simulado_default_questions']};
const int kSimuladoDefaultMinutes = {modes['simulado_default_minutes']};
const int kTtsAnswerPauseMs = {modes['tts_answer_pause_ms']};

/// §5.2 — the wire value is the contract. Never renumber.
enum Grade {{
{grades}
  ;

  const Grade(this.value);

  /// Persisted and transmitted as this smallint.
  final int value;

  static Grade fromValue(int value) => Grade.values.firstWhere(
        (g) => g.value == value,
        orElse: () => throw ArgumentError('unknown grade value: $value'),
      );
}}

/// §5.2 — a review row exists only for modes that feed the scheduler.
enum ReviewSource {{
{sources}
  ;

  const ReviewSource(this.wire);

  /// The string on the wire and in the database.
  final String wire;

  static ReviewSource fromWire(String wire) => values.firstWhere(
        (v) => v.wire == wire,
        orElse: () => throw ArgumentError('unknown review source: $wire'),
      );
}}

/// §5.1
enum CardStatus {{
{statuses}
  ;

  const CardStatus(this.wire);

  final String wire;

  static CardStatus fromWire(String wire) => values.firstWhere(
        (v) => v.wire == wire,
        orElse: () => throw ArgumentError('unknown card status: $wire'),
      );
}}

/// §10 — the client maps codes to copy; it never matches on server prose.
enum ErrorCode {{
{errors}
  ;

  const ErrorCode(this.wire);

  final String wire;

  /// Null for a code this build has never heard of. §5.3 makes that the
  /// normal case, not a corruption — so it is a lookup that can miss, never
  /// a throw.
  static ErrorCode? fromWire(String? wire) {{
    for (final value in values) {{
      if (value.wire == wire) return value;
    }}
    return null;
  }}
}}
"""


def _python(c: dict) -> str:
    limits = c["card_limits"]
    sched = c["scheduling"]
    quota = c["quota"]
    modes = c["modes"]
    generation = c["generation"]

    grades ="\n".join(f"    {g['name'].upper()} = {g['value']}" for g in c["grades"])
    sources = "\n".join(f'    {s.upper()} = "{s}"' for s in c["review_sources"])
    statuses = "\n".join(f'    {s.upper()} = "{s}"' for s in c["card_statuses"])
    errors = "\n".join(f'    {e.upper()} = "{e}"' for e in c["error_codes"])
    milestones = ", ".join(str(d) for d in sched["graduation_milestone_days"])
    weights = ", ".join(repr(w) for w in sched["fsrs_weights"])

    banner = "\n".join(f"# {line}" for line in BANNER_LINES)
    return f'''{banner}

from __future__ import annotations

from enum import IntEnum, StrEnum

CONTRACT_VERSION = {c['version']}

# §7.6 — counted in grapheme clusters over NFC-normalised text.
FRONT_MAX_GRAPHEMES = {limits['front_max_graphemes']}
BACK_MAX_GRAPHEMES = {limits['back_max_graphemes']}

# §4 — maturity is a query predicate, never a stored column.
MATURE_INTERVAL_DAYS = {sched['mature_interval_days']}
DESIRED_RETENTION = {sched['desired_retention']}
GRADUATION_MILESTONE_DAYS = ({milestones},)

# §4.1 — the default FSRS vector, declared here because each platform's
# package ships a DIFFERENT default and two clients must not disagree.
FSRS_WEIGHTS = ({weights},)

# §5.7 — the day rolls over at 04:00 local, not midnight.
DEFAULT_DAY_CUTOFF_HOUR = {sched['default_day_cutoff_hour']}
LEARNING_STEPS_SECONDS = tuple({sched['learning_steps_seconds']})
RELEARNING_STEPS_SECONDS = tuple({sched['relearning_steps_seconds']})
MAXIMUM_INTERVAL_DAYS = {sched['maximum_interval_days']}
ENABLE_FSRS_FUZZ = {sched['enable_fuzz']}

# §7.7 — one generation for the lifetime of the account, not per month.
FREE_GENERATIONS_LIFETIME = {quota['free_generations_lifetime']}
MAX_JOBS_IN_FLIGHT = {quota['max_jobs_in_flight']}

# §7.3 — cap on the subject, or on pasted material. Without it the request body
# becomes the prompt, and a generation is billed by token.
TOPIC_MAX_CHARS = {generation['topic_max_chars']}

# §5.9 — alternative modes. Present on the server only so that a future
# server-side check has the same numbers; the modes themselves are on-device.
MULTIPLE_CHOICE_OPTIONS = {modes['multiple_choice_options']}
MULTIPLE_CHOICE_FAST_ANSWER_MS = {modes['multiple_choice_fast_answer_ms']}
LEECH_MIN_LAPSES = {modes['leech_min_lapses']}
SIMULADO_DEFAULT_QUESTIONS = {modes['simulado_default_questions']}
SIMULADO_DEFAULT_MINUTES = {modes['simulado_default_minutes']}
TTS_ANSWER_PAUSE_MS = {modes['tts_answer_pause_ms']}


class Grade(IntEnum):
    """§5.2 — the wire value is the contract. Never renumber."""

{grades}


class ReviewSource(StrEnum):
    """§5.2 — a review row exists only for modes that feed the scheduler."""

{sources}


class CardStatus(StrEnum):
    """§5.1"""

{statuses}


class ErrorCode(StrEnum):
    """§10 — machine-readable; the client maps these to copy.

    StrEnum, not `(str, Enum)`: the latter stringifies as "ErrorCode.MEMBER" on
    Python 3.11+, and that string reached the database. A code the client
    cannot map is the same as no code at all.
    """

{errors}
'''


def _typescript(c: dict) -> str:
    limits = c["card_limits"]
    sched = c["scheduling"]
    quota = c["quota"]
    modes = c["modes"]
    generation = c["generation"]

    # Uniões de literais em vez de enums do TypeScript: o valor na rede é o
    # contrato, e uma união faz o compilador recusar uma string que não existe
    # sem introduzir um objeto em tempo de execução para traduzir de volta.
    grades = "\n".join(
        f"  /** {g['label_pt']} */\n  {_camel(g['dart'])}: {g['value']}," for g in c["grades"]
    )
    grade_labels = "\n".join(f"  {g['value']}: '{g['label_pt']}'," for g in c["grades"])
    sources = " | ".join(f"'{s}'" for s in c["review_sources"])
    statuses = " | ".join(f"'{s}'" for s in c["card_statuses"])
    errors = " | ".join(f"'{e}'" for e in c["error_codes"])
    error_list = "\n".join(f"  '{e}'," for e in c["error_codes"])
    milestones = ", ".join(str(d) for d in sched["graduation_milestone_days"])
    weights = ", ".join(repr(w) for w in sched["fsrs_weights"])

    banner = "\n".join(f"// {line}" for line in BANNER_LINES)
    return f"""{banner}

/** Contract version; bumped when this file's shape changes. */
export const CONTRACT_VERSION = {c['version']};

/** §7.6 — counted in grapheme clusters over NFC-normalised text. */
export const FRONT_MAX_GRAPHEMES = {limits['front_max_graphemes']};
export const BACK_MAX_GRAPHEMES = {limits['back_max_graphemes']};

/** §4 — maturity is a query predicate, never a stored column. */
export const MATURE_INTERVAL_DAYS = {sched['mature_interval_days']};
export const DESIRED_RETENTION = {sched['desired_retention']};
export const GRADUATION_MILESTONE_DAYS = [{milestones}] as const;

/**
 * §4.1 — o vetor FSRS padrão. Vem do contrato e não do pacote: `ts-fsrs` traz
 * o vetor do FSRS-6 e o `fsrs` do Dart traz outro, e herdar cada padrão faria
 * a web e o aplicativo agendarem o mesmo histórico de formas diferentes.
 */
export const FSRS_WEIGHTS: readonly number[] = [{weights}];

/** §5.7 — the day rolls over at 04:00 local, not midnight. */
export const DEFAULT_DAY_CUTOFF_HOUR = {sched['default_day_cutoff_hour']};

/** §7.7 — one generation for the lifetime of the account, not per month. */
export const FREE_GENERATIONS_LIFETIME = {quota['free_generations_lifetime']};
export const MAX_JOBS_IN_FLIGHT = {quota['max_jobs_in_flight']};

/** §7.3 — cap on the subject, or on pasted material. */
export const TOPIC_MAX_CHARS = {generation['topic_max_chars']};

/** §5.9 — alternative modes. Scheduling decisions, not interface ones. */
export const MULTIPLE_CHOICE_OPTIONS = {modes['multiple_choice_options']};
export const MULTIPLE_CHOICE_FAST_ANSWER_MS = {modes['multiple_choice_fast_answer_ms']};
export const LEECH_MIN_LAPSES = {modes['leech_min_lapses']};
export const SIMULADO_DEFAULT_QUESTIONS = {modes['simulado_default_questions']};
export const SIMULADO_DEFAULT_MINUTES = {modes['simulado_default_minutes']};
export const TTS_ANSWER_PAUSE_MS = {modes['tts_answer_pause_ms']};

/** §5.2 — the wire value is the contract. Never renumber. */
export const Grade = {{
{grades}
}} as const;

export type Grade = (typeof Grade)[keyof typeof Grade];

/** The four grades in the order they are always shown: errei → fácil. */
export const GRADES_IN_ORDER: readonly Grade[] = [
  {", ".join(f"Grade.{_camel(g['dart'])}" for g in c["grades"])},
];

export const GRADE_LABELS: Record<Grade, string> = {{
{grade_labels}
}};

/** §5.2 — a review row exists only for modes that feed the scheduler. */
export type ReviewSource = {sources};

/** §5.1 */
export type CardStatus = {statuses};

/** §10 — the client maps codes to copy; it never shows server prose. */
export type ErrorCode = {errors};

const ERROR_CODES: readonly string[] = [
{error_list}
];

/**
 * Null for a code this build has never heard of. §5.3 makes that the normal
 * case, not a corruption — so it is a lookup that can miss, never a throw.
 */
export function errorCodeFromWire(wire: string | null | undefined): ErrorCode | null {{
  return wire != null && ERROR_CODES.includes(wire) ? (wire as ErrorCode) : null;
}}
"""



def _cpp(c: dict) -> str:
    limits = c["card_limits"]
    sched = c["scheduling"]
    quota = c["quota"]
    modes = c["modes"]
    generation = c["generation"]

    learning_steps = ", ".join(
        f"{seconds}U"
        for seconds in sched["learning_steps_seconds"]
    )

    relearning_steps = ", ".join(
        f"{seconds}U"
        for seconds in sched["relearning_steps_seconds"]
    )

    milestones = ", ".join(str(d) for d in sched["graduation_milestone_days"])
    weights = ", ".join(repr(w) for w in sched["fsrs_weights"])

    grade_values = "\n".join(
        f"constexpr uint8_t GRADE_{g['dart'].upper()} = {g['value']}U;"
        for g in c["grades"]
    )

    review_sources = "\n".join(
        f'constexpr const char REVIEW_SOURCE_{s.upper()}[] = "{s}";'
        for s in c["review_sources"]
    )

    card_statuses = "\n".join(
        f'constexpr const char CARD_STATUS_{s.upper()}[] = "{s}";'
        for s in c["card_statuses"]
    )

    errors = "\n".join(
        f'constexpr const char ERROR_{e.upper()}[] = "{e}";'
        for e in c["error_codes"]
    )

    banner = "\n".join(f"// {line}" for line in BANNER_LINES)

    return f"""{banner}
#pragma once

#include <stddef.h>
#include <stdint.h>

namespace MnemosContract {{

constexpr uint32_t CONTRACT_VERSION = {c['version']}U;

constexpr size_t FRONT_MAX_GRAPHEMES = {limits['front_max_graphemes']}U;
constexpr size_t BACK_MAX_GRAPHEMES = {limits['back_max_graphemes']}U;

constexpr uint32_t MATURE_INTERVAL_DAYS = {sched['mature_interval_days']}U;
constexpr double DESIRED_RETENTION = {sched['desired_retention']};
constexpr uint8_t DEFAULT_DAY_CUTOFF_HOUR = {sched['default_day_cutoff_hour']}U;

constexpr uint32_t LEARNING_STEPS_SECONDS[] = {{{learning_steps}}};
constexpr size_t LEARNING_STEP_COUNT =
    sizeof(LEARNING_STEPS_SECONDS) / sizeof(LEARNING_STEPS_SECONDS[0]);

constexpr uint32_t RELEARNING_STEPS_SECONDS[] = {{{relearning_steps}}};
constexpr size_t RELEARNING_STEP_COUNT =
    sizeof(RELEARNING_STEPS_SECONDS) / sizeof(RELEARNING_STEPS_SECONDS[0]);

constexpr uint32_t MAXIMUM_INTERVAL_DAYS =
    {sched['maximum_interval_days']}U;

constexpr bool ENABLE_FSRS_FUZZ =
    {str(sched['enable_fuzz']).lower()};

constexpr uint32_t GRADUATION_MILESTONE_DAYS[] = {{{milestones}}};
constexpr size_t GRADUATION_MILESTONE_COUNT =
    sizeof(GRADUATION_MILESTONE_DAYS) /
    sizeof(GRADUATION_MILESTONE_DAYS[0]);

constexpr double FSRS_WEIGHTS[] = {{{weights}}};
constexpr size_t FSRS_WEIGHT_COUNT =
    sizeof(FSRS_WEIGHTS) / sizeof(FSRS_WEIGHTS[0]);

static_assert(FSRS_WEIGHT_COUNT == 21U,
              "Mnemos currently requires the 21-weight FSRS contract");

{grade_values}

{review_sources}

{card_statuses}

constexpr uint8_t MULTIPLE_CHOICE_OPTIONS =
    {modes['multiple_choice_options']}U;
constexpr uint32_t MULTIPLE_CHOICE_FAST_ANSWER_MS =
    {modes['multiple_choice_fast_answer_ms']}U;
constexpr uint16_t LEECH_MIN_LAPSES =
    {modes['leech_min_lapses']}U;
constexpr uint16_t SIMULADO_DEFAULT_QUESTIONS =
    {modes['simulado_default_questions']}U;
constexpr uint16_t SIMULADO_DEFAULT_MINUTES =
    {modes['simulado_default_minutes']}U;
constexpr uint32_t TTS_ANSWER_PAUSE_MS =
    {modes['tts_answer_pause_ms']}U;

constexpr uint32_t FREE_GENERATIONS_LIFETIME =
    {quota['free_generations_lifetime']}U;
constexpr uint32_t MAX_JOBS_IN_FLIGHT =
    {quota['max_jobs_in_flight']}U;
constexpr uint32_t TOPIC_MAX_CHARS =
    {generation['topic_max_chars']}U;

{errors}

}}  // namespace MnemosContract
"""

def _camel(snake: str) -> str:
    head, *tail = snake.split("_")
    return head + "".join(p.capitalize() for p in tail)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--check", action="store_true", help="fail if out of date")
    args = parser.parse_args()

    contract = yaml.safe_load(CONTRACT.read_text(encoding="utf-8"))
    outputs = {
        DART_OUT: _dart(contract),
        PY_OUT: _python(contract),
        TS_OUT: _typescript(contract),
        CPP_OUT: _cpp(contract),
    }

    stale = []
    for path, content in outputs.items():
        current = path.read_text(encoding="utf-8") if path.exists() else None
        if current == content:
            continue
        if args.check:
            stale.append(path)
        else:
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(content, encoding="utf-8")
            print(f"wrote {path.relative_to(ROOT)}")

    if stale:
        for path in stale:
            print(f"STALE: {path.relative_to(ROOT)}", file=sys.stderr)
        print("\nRun: python shared/generate.py", file=sys.stderr)
        return 1

    if args.check:
        print("contract: generated files are up to date")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
