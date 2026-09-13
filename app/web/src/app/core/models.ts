import type { CardStatus, Grade, ReviewSource } from './contract.g';

/**
 * As linhas como elas viajam (§6).
 *
 * Os nomes são os do servidor — `snake_case`, datas em ISO — de propósito: o
 * cliente de sync empurra de volta exatamente o que recebeu, e traduzir para
 * `camelCase` na entrada obrigaria a traduzir de volta na saída, com uma
 * chance de errar em cada direção. A tradução acontece uma vez só, nas visões.
 */

/**
 * O que toda linha sincronizável carrega.
 *
 * `updated_at` fica de fora de propósito: só as **entidades** têm, porque é o
 * critério de último-a-escrever (§6.2). O histórico é imutável — uma revisão
 * não tem "última atualização", e as tabelas de histórico nem têm a coluna.
 * Mandá-la mesmo assim faz o servidor devolver 500 com "unconsumed column
 * names", que foi o que aconteceu na primeira tentativa de enviar uma revisão.
 */
export interface SyncRow {
  device_id: string;
  /** Nulo enquanto a linha ainda não foi aceita pelo servidor: é o outbox. */
  server_seq: number | null;
}

/** Uma entidade: muda com o tempo, e por isso desempata por `updated_at`. */
export interface EntityRow extends SyncRow {
  updated_at: string;
}

export interface DeckRow extends EntityRow {
  id: string;
  parent_id: string | null;
  name: string;
  description: string | null;
  version: number;
  origin: string;
  archived_at: string | null;
  deleted_at: string | null;
}

export interface CardRow extends EntityRow {
  id: string;
  deck_id: string;
  front: string;
  back: string;
  tags: string[];
  deleted_at: string | null;
}

export interface CardFlagRow extends EntityRow {
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

export interface UserSettingRow extends EntityRow {
  key: string;
  value: string;
}

export interface GoalHistoryRow extends SyncRow {
  id: string;
  daily_goal: number;
  effective_from_local_date: string;
  created_at: string;
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
