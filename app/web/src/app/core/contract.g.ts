// GENERATED FROM shared/contract.yaml — DO NOT EDIT.
// Regenerate with: python shared/generate.py

/** Contract version; bumped when this file's shape changes. */
export const CONTRACT_VERSION = 2;

/** §7.6 — counted in grapheme clusters over NFC-normalised text. */
export const FRONT_MAX_GRAPHEMES = 120;
export const BACK_MAX_GRAPHEMES = 240;

/** §4 — maturity is a query predicate, never a stored column. */
export const MATURE_INTERVAL_DAYS = 21;
export const DESIRED_RETENTION = 0.9;
export const GRADUATION_MILESTONE_DAYS = [180, 365] as const;

/**
 * §4.1 — o vetor FSRS padrão. Vem do contrato e não do pacote: `ts-fsrs` traz
 * o vetor do FSRS-6 e o `fsrs` do Dart traz outro, e herdar cada padrão faria
 * a web e o aplicativo agendarem o mesmo histórico de formas diferentes.
 */
export const FSRS_WEIGHTS: readonly number[] = [0.2172, 1.1771, 3.2602, 16.1507, 7.0114, 0.57, 2.0966, 0.0069, 1.5261, 0.112, 1.0178, 1.849, 0.1133, 0.3127, 2.2934, 0.2191, 3.0004, 0.7536, 0.3332, 0.1437, 0.2];

/** §5.7 — the day rolls over at 04:00 local, not midnight. */
export const DEFAULT_DAY_CUTOFF_HOUR = 4;

/** §7.7 — one generation for the lifetime of the account, not per month. */
export const FREE_GENERATIONS_LIFETIME = 1;
export const MAX_JOBS_IN_FLIGHT = 2;

/** §7.3 — cap on the subject, or on pasted material. */
export const TOPIC_MAX_CHARS = 20000;

/** §5.9 — alternative modes. Scheduling decisions, not interface ones. */
export const MULTIPLE_CHOICE_OPTIONS = 4;
export const MULTIPLE_CHOICE_FAST_ANSWER_MS = 10000;
export const LEECH_MIN_LAPSES = 4;
export const SIMULADO_DEFAULT_QUESTIONS = 20;
export const SIMULADO_DEFAULT_MINUTES = 20;
export const TTS_ANSWER_PAUSE_MS = 3000;

/** §5.2 — the wire value is the contract. Never renumber. */
export const Grade = {
  /** Errei */
  again: 1,
  /** Difícil */
  hard: 2,
  /** Bom */
  good: 3,
  /** Fácil */
  easy: 4,
} as const;

export type Grade = (typeof Grade)[keyof typeof Grade];

/** The four grades in the order they are always shown: errei → fácil. */
export const GRADES_IN_ORDER: readonly Grade[] = [
  Grade.again, Grade.hard, Grade.good, Grade.easy,
];

export const GRADE_LABELS: Record<Grade, string> = {
  1: 'Errei',
  2: 'Difícil',
  3: 'Bom',
  4: 'Fácil',
};

/** §5.2 — a review row exists only for modes that feed the scheduler. */
export type ReviewSource = 'standard' | 'multiple_choice';

/** §5.1 */
export type CardStatus = 'active' | 'suspended' | 'buried';

/** §10 — the client maps codes to copy; it never shows server prose. */
export type ErrorCode = 'quota_exhausted' | 'topic_too_vague' | 'material_insufficient' | 'file_too_large' | 'page_limit_exceeded' | 'photo_unreadable' | 'model_refused' | 'network_unavailable' | 'resync_required';

const ERROR_CODES: readonly string[] = [
  'quota_exhausted',
  'topic_too_vague',
  'material_insufficient',
  'file_too_large',
  'page_limit_exceeded',
  'photo_unreadable',
  'model_refused',
  'network_unavailable',
  'resync_required',
];

/**
 * Null for a code this build has never heard of. §5.3 makes that the normal
 * case, not a corruption — so it is a lookup that can miss, never a throw.
 */
export function errorCodeFromWire(wire: string | null | undefined): ErrorCode | null {
  return wire != null && ERROR_CODES.includes(wire) ? (wire as ErrorCode) : null;
}
