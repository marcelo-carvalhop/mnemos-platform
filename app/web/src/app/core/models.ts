import type { CardStatus, Grade, ReviewSource } from './contract.g';

/**
 * As linhas como elas viajam (§6).
 *
 * Os nomes são os do servidor — `snake_case`, datas em ISO — de propósito: o
 * cliente de sync empurra de volta exatamente o que recebeu, e traduzir para
 * `camelCase` na entrada obrigaria a traduzir de volta na saída, com uma
 * chance de errar em cada direção. A tradução acontece uma vez só, nas visões.
 */

export interface SyncRow {
  updated_at: string;
  device_id: string;
  /** Nulo enquanto a linha ainda não foi aceita pelo servidor: é o outbox. */
  server_seq: number | null;
}

export interface DeckRow extends SyncRow {
  id: string;
  parent_id: string | null;
  name: string;
  description: string | null;
  version: number;
  origin: string;
  archived_at: string | null;
  deleted_at: string | null;
}

export interface CardRow extends SyncRow {
  id: string;
  deck_id: string;
  front: string;
  back: string;
  tags: string[];
  deleted_at: string | null;
}

export interface CardFlagRow extends SyncRow {
  card_id: string;
  status: CardStatus;
  buried_until: string | null;
}

export interface ReviewRow extends SyncRow {
  id: string;
  card_id: string;
  reviewed_at: string;
  grade: Grade;
  source: ReviewSource;
  elapsed_ms: number | null;
}

export interface ProgressResetRow extends SyncRow {
  id: string;
  card_id: string | null;
  reset_at: string;
}

export interface UserSettingRow extends SyncRow {
  key: string;
  value: string;
}

export interface GoalHistoryRow extends SyncRow {
  id: string;
  goal: number;
  effective_from: string;
}

/**
 * A ordem de dependência (§6.4).
 *
 * Um card enviado antes do seu baralho referencia uma linha que o servidor
 * nunca viu e a chave estrangeira recusa. O histórico vai por último porque
 * aponta para cards.
 */
export const PUSH_ORDER = [
  'decks',
  'cards',
  'card_flags',
  'user_settings',
  'reviews',
  'progress_resets',
  'goal_history',
] as const;

export type SyncTable = (typeof PUSH_ORDER)[number];

/** A chave primária de cada tabela, para casar o `server_seq` devolvido. */
export const KEY_OF: Record<SyncTable, string> = {
  decks: 'id',
  cards: 'id',
  card_flags: 'card_id',
  user_settings: 'key',
  reviews: 'id',
  progress_resets: 'id',
  goal_history: 'id',
};
