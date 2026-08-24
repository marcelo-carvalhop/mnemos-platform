import { Injectable, computed, inject, signal } from '@angular/core';
import { DEFAULT_DAY_CUTOFF_HOUR, Grade, MATURE_INTERVAL_DAYS } from './contract.g';
import {
  KEY_OF,
  type CardFlagRow,
  type CardRow,
  type DeckRow,
  type GoalHistoryRow,
  type ProgressResetRow,
  type ReviewRow,
  type SyncTable,
  type UserSettingRow,
} from './models';
import { DEFAULT_FSRS_PARAMS, replay, type CardState, type FsrsParams } from './scheduler';
import { Session } from './session';

/**
 * O espelho local do que o servidor mandou, e a origem de tudo que a interface
 * mostra.
 *
 * Duas regras da arquitetura moram aqui:
 *
 * * **O log de revisões é a verdade** (§3). `card_state` não é armazenado: é
 *   recalculado por replay a partir do histórico. Guardar o estado seria criar
 *   um segundo fato capaz de discordar do primeiro, e é justamente o que faz
 *   dois aparelhos discordarem sobre o que vence hoje.
 * * **Nada é apagado** (§3). Remover um card escreve `deleted_at`; as visões
 *   filtram. Um DELETE de verdade não teria como sincronizar.
 *
 * Tudo é `signal`, então uma tela que mostra a fila de hoje se atualiza sozinha
 * quando uma revisão entra — sem evento, sem recarregar, sem o componente saber
 * quem escreveu.
 */
@Injectable({ providedIn: 'root' })
export class Store {
  private readonly session = inject(Session);

  readonly decks = signal<DeckRow[]>([]);
  readonly cards = signal<CardRow[]>([]);
  readonly flags = signal<CardFlagRow[]>([]);
  readonly reviews = signal<ReviewRow[]>([]);
  readonly resets = signal<ProgressResetRow[]>([]);
  readonly settings = signal<UserSettingRow[]>([]);
  readonly goals = signal<GoalHistoryRow[]>([]);

  /** Onde cada tabela parou. Zero significa "puxar do começo" (§6.2). */
  private readonly cursors = new Map<string, number>();

  /** Reavaliado a cada minuto para que "vence agora" não congele na tela. */
  private readonly clock = signal(new Date());

  constructor() {
    if (typeof window !== 'undefined') {
      setInterval(() => this.clock.set(new Date()), 60_000);
    }
  }

  now(): Date {
    return this.clock();
  }

  // ---------------------------------------------------------------------------
  // Sync
  // ---------------------------------------------------------------------------

  cursor(table: string): number {
    return this.cursors.get(table) ?? 0;
  }

  /** As linhas que o servidor ainda não confirmou (§6.2). */
  outbox(table: SyncTable): Record<string, unknown>[] {
    return (this.rowsOf(table) as Record<string, unknown>[]).filter((r) => r['server_seq'] == null);
  }

  acknowledge(table: SyncTable, assigned: Record<string, number>): void {
    if (Object.keys(assigned).length === 0) return;
    const key = KEY_OF[table];
    this.signalOf(table).update((rows) =>
      rows.map((row) => {
        const seq = assigned[(row as Record<string, unknown>)[key] as string];
        return seq == null ? row : { ...row, server_seq: seq };
      }),
    );
  }

  /**
   * Aplica o que veio do servidor.
   *
   * Histórico entra por união — inserido ou ignorado, nunca sobrescrito (§6.1).
   * Entidades resolvem por último-a-escrever, avaliado **localmente com a mesma
   * regra do servidor**, para que os dois lados cheguem à mesma resposta em vez
   * de confiar em quem falou por último.
   */
  apply(table: SyncTable, incoming: Record<string, unknown>[], cursor: number): void {
    const key = KEY_OF[table];
    const isHistory =
      table === 'reviews' || table === 'progress_resets' || table === 'goal_history';

    this.signalOf(table).update((rows) => {
      const byKey = new Map(rows.map((r) => [(r as Record<string, unknown>)[key] as string, r]));

      for (const row of incoming) {
        const id = row[key] as string;
        const local = byKey.get(id) as Record<string, unknown> | undefined;

        if (local && isHistory) continue;
        if (local && !remoteWins(row, local)) continue;

        byKey.set(id, row as never);
      }
      return [...byKey.values()];
    });

    this.cursors.set(table, cursor);
  }

  /** Um recomeço: outra conta entrou, e nada da anterior pode sobrar na tela. */
  clear(): void {
    this.decks.set([]);
    this.cards.set([]);
    this.flags.set([]);
    this.reviews.set([]);
    this.resets.set([]);
    this.settings.set([]);
    this.goals.set([]);
    this.cursors.clear();
  }

  // ---------------------------------------------------------------------------
  // Escrita local
  // ---------------------------------------------------------------------------

  /**
   * Toda escrita entra no outbox: `server_seq` nulo, `updated_at` e `device_id`
   * preenchidos aqui. São os três campos de que §6.2 depende, e esquecer um
   * deles faz a linha nunca subir ou nunca ganhar desempate.
   */
  private stamp<T extends object>(
    row: T,
  ): T & { updated_at: string; device_id: string; server_seq: null } {
    return {
      ...row,
      updated_at: new Date().toISOString(),
      device_id: this.session.deviceId,
      server_seq: null,
    };
  }

  createDeck(name: string): string {
    const id = crypto.randomUUID();
    this.decks.update((rows) => [
      ...rows,
      this.stamp({
        id,
        parent_id: null,
        name,
        description: null,
        version: 1,
        origin: 'own',
        archived_at: null,
        deleted_at: null,
      }) as DeckRow,
    ]);
    return id;
  }

  renameDeck(id: string, name: string): void {
    this.decks.update((rows) => rows.map((d) => (d.id === id ? this.stamp({ ...d, name }) : d)));
  }

  /** §3 — apagar é escrever uma lápide. Um DELETE não teria como sincronizar. */
  deleteDeck(id: string): void {
    const at = new Date().toISOString();
    this.decks.update((rows) =>
      rows.map((d) => (d.id === id ? this.stamp({ ...d, deleted_at: at }) : d)),
    );
    this.cards.update((rows) =>
      rows.map((c) => (c.deck_id === id ? this.stamp({ ...c, deleted_at: at }) : c)),
    );
  }

  createCard(deckId: string, front: string, back: string, tags: string[] = []): string {
    const id = crypto.randomUUID();
    this.cards.update((rows) => [
      ...rows,
      this.stamp({ id, deck_id: deckId, front, back, tags, deleted_at: null }) as CardRow,
    ]);
    return id;
  }

  updateCard(id: string, patch: Partial<Pick<CardRow, 'front' | 'back' | 'tags'>>): void {
    this.cards.update((rows) =>
      rows.map((c) => (c.id === id ? this.stamp({ ...c, ...patch }) : c)),
    );
  }

  deleteCard(id: string): void {
    const at = new Date().toISOString();
    this.cards.update((rows) =>
      rows.map((c) => (c.id === id ? this.stamp({ ...c, deleted_at: at }) : c)),
    );
  }

  /**
   * §5.2 — a revisão é append-only e é o único fato que o estudo produz. O
   * agendamento não é escrito: sai do replay, aqui e no telefone.
   */
  recordReview(cardId: string, grade: Grade, elapsedMs: number | null): void {
    this.reviews.update((rows) => [
      ...rows,
      this.stamp({
        id: crypto.randomUUID(),
        card_id: cardId,
        reviewed_at: new Date().toISOString(),
        grade,
        source: 'standard',
        elapsed_ms: elapsedMs,
      }) as ReviewRow,
    ]);
  }

  setSetting(key: string, value: string): void {
    this.settings.update((rows) => {
      const existing = rows.find((s) => s.key === key);
      const next = this.stamp({ key, value }) as UserSettingRow;
      return existing ? rows.map((s) => (s.key === key ? next : s)) : [...rows, next];
    });
  }

  // ---------------------------------------------------------------------------
  // Visões
  // ---------------------------------------------------------------------------

  readonly liveDecks = computed(() =>
    this.decks()
      .filter((d) => d.deleted_at === null && d.archived_at === null)
      .sort((a, b) => a.name.localeCompare(b.name, 'pt-BR')),
  );

  readonly liveCards = computed(() => this.cards().filter((c) => c.deleted_at === null));

  cardsOfDeck(deckId: string): CardRow[] {
    return this.liveCards().filter((c) => c.deck_id === deckId);
  }

  /** Os parâmetros vêm de `user_settings` porque são entrada da fórmula (§3.1). */
  readonly fsrsParams = computed<FsrsParams>(() => {
    const retention = this.settings().find((s) => s.key === 'desired_retention');
    const parsed = retention ? Number(retention.value) : NaN;
    return Number.isFinite(parsed) && parsed > 0 && parsed < 1
      ? { ...DEFAULT_FSRS_PARAMS, desiredRetention: parsed }
      : DEFAULT_FSRS_PARAMS;
  });

  /** Estado de cada card, sempre reconstruído — nunca lido de uma coluna. */
  readonly states = computed<Map<string, CardState>>(() => {
    const history = this.reviews().map((r) => ({
      id: r.id,
      cardId: r.card_id,
      reviewedAt: new Date(r.reviewed_at),
      grade: r.grade,
    }));
    const resets = this.resets()
      .filter((r) => r.card_id !== null)
      .map((r) => ({ cardId: r.card_id as string, resetAt: new Date(r.reset_at) }));
    const params = this.fsrsParams();

    // Agrupar antes de replayar: sem isso cada card varreria o histórico
    // inteiro, e uma conta com anos de uso ficaria quadrática.
    const byCard = new Map<string, typeof history>();
    for (const entry of history) {
      const bucket = byCard.get(entry.cardId);
      if (bucket) bucket.push(entry);
      else byCard.set(entry.cardId, [entry]);
    }

    const out = new Map<string, CardState>();
    for (const card of this.liveCards()) {
      out.set(card.id, replay(byCard.get(card.id) ?? [], resets, params, card.id));
    }
    return out;
  });

  /** §5.1 — suspenso sai da fila; enterrado sai até a hora marcada. */
  private readonly blocked = computed(() => {
    const now = this.now();
    const out = new Set<string>();
    for (const flag of this.flags()) {
      if (flag.status === 'suspended') out.add(flag.card_id);
      if (flag.buried_until && new Date(flag.buried_until) > now) out.add(flag.card_id);
    }
    return out;
  });

  /** O que vence agora: novos primeiro, depois os mais atrasados. */
  readonly due = computed(() => {
    const now = this.now();
    const states = this.states();
    const blocked = this.blocked();

    return this.liveCards()
      .filter((c) => !blocked.has(c.id))
      .filter((c) => {
        const due = states.get(c.id)?.dueAt;
        return due === null || due === undefined || due <= now;
      })
      .sort((a, b) => {
        const da = states.get(a.id)?.dueAt;
        const db = states.get(b.id)?.dueAt;
        if (da === null || da === undefined) return db === null || db === undefined ? 0 : -1;
        if (db === null || db === undefined) return 1;
        return da.getTime() - db.getTime();
      });
  });

  /** §4 — maduro é um predicado de consulta, nunca uma coluna. */
  matureCount(deckId?: string): number {
    const states = this.states();
    const cards = deckId ? this.cardsOfDeck(deckId) : this.liveCards();
    return cards.filter((c) => {
      const s = states.get(c.id);
      if (!s || !s.dueAt || !s.lastReviewAt) return false;
      const days = (s.dueAt.getTime() - s.lastReviewAt.getTime()) / 86_400_000;
      return days >= MATURE_INTERVAL_DAYS;
    }).length;
  }

  /**
   * §2.3 — a manchete é o que a pessoa guardou, nunca quantos cards ela tem.
   * A soma dos intervalos atuais é a leitura mais honesta disso: é o tempo que
   * o conhecimento fica de pé sem precisar ser revisto de novo.
   */
  readonly accumulatedMemoryDays = computed(() => {
    let total = 0;
    for (const state of this.states().values()) {
      if (!state.dueAt || !state.lastReviewAt) continue;
      total += (state.dueAt.getTime() - state.lastReviewAt.getTime()) / 86_400_000;
    }
    return Math.round(total);
  });

  /** §5.7 — o dia vira às 04:00 locais, não à meia-noite. */
  readonly studiedToday = computed(() => {
    const start = dayStart(this.now());
    return this.reviews().filter((r) => new Date(r.reviewed_at) >= start).length;
  });

  readonly dailyGoal = computed(() => {
    const latest = [...this.goals()].sort((a, b) =>
      b.effective_from.localeCompare(a.effective_from),
    )[0];
    return latest?.goal ?? 25;
  });

  // ---------------------------------------------------------------------------

  private rowsOf(table: SyncTable): unknown[] {
    return this.signalOf(table)();
  }

  private signalOf(table: SyncTable) {
    switch (table) {
      case 'decks':
        return this.decks as unknown as ReturnType<typeof signal<Record<string, unknown>[]>>;
      case 'cards':
        return this.cards as unknown as ReturnType<typeof signal<Record<string, unknown>[]>>;
      case 'card_flags':
        return this.flags as unknown as ReturnType<typeof signal<Record<string, unknown>[]>>;
      case 'reviews':
        return this.reviews as unknown as ReturnType<typeof signal<Record<string, unknown>[]>>;
      case 'progress_resets':
        return this.resets as unknown as ReturnType<typeof signal<Record<string, unknown>[]>>;
      case 'user_settings':
        return this.settings as unknown as ReturnType<typeof signal<Record<string, unknown>[]>>;
      case 'goal_history':
        return this.goals as unknown as ReturnType<typeof signal<Record<string, unknown>[]>>;
    }
  }
}

/**
 * A mesma regra que o servidor usa (§6.2): mais recente vence, e empate
 * desempata pelo `device_id`. Avaliar localmente é o que faz os dois lados
 * convergirem em vez de o último a falar ganhar.
 */
function remoteWins(remote: Record<string, unknown>, local: Record<string, unknown>): boolean {
  const ra = String(remote['updated_at'] ?? '');
  const la = String(local['updated_at'] ?? '');
  if (ra !== la) return ra > la;
  return String(remote['device_id'] ?? '') > String(local['device_id'] ?? '');
}

/** O começo do dia de estudo, às 04:00 locais (§5.7). */
export function dayStart(now: Date, cutoffHour = DEFAULT_DAY_CUTOFF_HOUR): Date {
  const start = new Date(now);
  start.setHours(cutoffHour, 0, 0, 0);
  if (now < start) start.setDate(start.getDate() - 1);
  return start;
}
