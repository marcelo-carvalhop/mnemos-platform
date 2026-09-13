import {
  FSRS,
  Rating,
  State,
  createEmptyCard,
  default_w,
  type Card as FsrsCard,
  type Grade as FsrsGrade,
} from 'ts-fsrs';
import { DESIRED_RETENTION, FSRS_WEIGHTS, Grade } from './contract.g';

/**
 * FSRS na web (§4.1).
 *
 * Puro: sem IO, sem banco, sem relógio ambiente — toda entrada recebe o
 * instante que deve usar. É o mesmo desenho do `Scheduler` do aplicativo, e
 * pela mesma razão: erros de agendamento aparecem semanas depois como "por que
 * este card venceu hoje", e só um teste rápido contra centenas de históricos
 * sintéticos os pega antes.
 *
 * **O app e a web usam implementações diferentes do mesmo algoritmo** — o
 * pacote `fsrs` do pub e `ts-fsrs` do npm. §3 diz que o log de revisões é a
 * verdade e `card_state` é um cache reconstruído identicamente em qualquer
 * lugar; duas implementações que divirjam quebram exatamente isso, e a pessoa
 * veria um número no telefone e outro no navegador sem pista de qual está
 * certo. `scheduler.spec.ts` cruza esta implementação com fixtures gerados
 * pelo Dart, e é o que sustenta essa afirmação.
 */

export type CardPhase = 'newCard' | 'learning' | 'review' | 'relearning';

export interface CardState {
  readonly cardId: string;
  readonly stability: number;
  readonly difficulty: number;
  readonly dueAt: Date | null;
  readonly lastReviewAt: Date | null;
  readonly reps: number;
  readonly lapses: number;
  readonly phase: CardPhase;
  readonly step: number | null;
}

export interface ReviewEntry {
  readonly id: string;
  readonly cardId: string;
  readonly reviewedAt: Date;
  readonly grade: Grade;
}

export interface ProgressReset {
  readonly cardId: string;
  readonly resetAt: Date;
}

export interface FsrsParams {
  readonly weights: readonly number[];
  readonly desiredRetention: number;
}

/**
 * O vetor vem do contrato, **não** de `default_w` do pacote.
 *
 * `ts-fsrs` traz o vetor do FSRS-6 e o pacote `fsrs` do Dart traz outro; herdar
 * cada padrão faria o navegador e o telefone agendarem o mesmo histórico de
 * formas diferentes, sem nada avisando. Foi o que o teste cruzado apanhou.
 */
export const DEFAULT_FSRS_PARAMS: FsrsParams = {
  weights: FSRS_WEIGHTS,
  desiredRetention: DESIRED_RETENTION,
};

/** O padrão do pacote, exposto só para o teste que prova que não o usamos. */
export const PACKAGE_DEFAULT_WEIGHTS: readonly number[] = default_w;

export function freshState(cardId: string): CardState {
  return {
    cardId,
    stability: 0,
    difficulty: 0,
    dueAt: null,
    lastReviewAt: null,
    reps: 0,
    lapses: 0,
    phase: 'newCard',
    step: 0,
  };
}

/** O único lugar onde um grau vira um novo estado. Todo o resto deriva daqui. */
export function apply(state: CardState, grade: Grade, at: Date, params: FsrsParams): CardState {
  const engine = buildEngine(params);
  const { card } = engine.next(toFsrs(state, at), at, toRating(grade));

  const lapsed = grade === Grade.again && state.phase === 'review';

  return {
    cardId: state.cardId,
    stability: card.stability ?? 0,
    difficulty: card.difficulty ?? 0,
    dueAt: card.due,
    lastReviewAt: card.last_review ?? null,
    reps: state.reps + 1,
    lapses: state.lapses + (lapsed ? 1 : 0),
    phase: toPhase(card.state),
    step: typeof card.learning_steps === 'number' ? card.learning_steps : null,
  };
}

/**
 * Reconstrói o estado de um card a partir do histórico (§3, §5.3).
 *
 * `resets` implementa o *reiniciar progresso* de §5.10: revisões até o último
 * reset do card são ignoradas, de modo que o agendamento recomeça enquanto o
 * histórico sobrevive — §3 proíbe apagá-lo.
 *
 * A ordenação é por `(reviewedAt, id)` e não pela ordem recebida: sincronia
 * bidirecional entrega revisões fora de ordem (§5.3), e o replay não pode
 * depender de quem chegou primeiro.
 */
export function replay(
  history: readonly ReviewEntry[],
  resets: readonly ProgressReset[],
  params: FsrsParams,
  cardId: string,
): CardState {
  let cutoff: Date | null = null;
  for (const reset of resets) {
    if (reset.cardId !== cardId) continue;
    if (cutoff === null || reset.resetAt > cutoff) cutoff = reset.resetAt;
  }

  const relevant = history
    .filter((r) => r.cardId === cardId)
    .filter((r) => cutoff === null || r.reviewedAt > cutoff)
    .sort((a, b) => {
      const byTime = a.reviewedAt.getTime() - b.reviewedAt.getTime();
      return byTime !== 0 ? byTime : a.id.localeCompare(b.id);
    });

  let state = freshState(cardId);
  for (const review of relevant) {
    state = apply(state, review.grade, review.reviewedAt, params);
  }
  return state;
}

/**
 * O intervalo que cada um dos quatro graus produziria agora.
 *
 * §5.8.3 exige que cada botão mostre seu intervalo antes de a pessoa
 * confirmar. Isto é **derivado de [apply]**, não calculado ao lado dele, o que
 * torna "a prévia nunca mente" verdadeiro por construção e não por teste.
 *
 * `now` é parâmetro porque a resposta depende dele: um card três dias atrasado
 * não produz os mesmos quatro intervalos de um revisado em dia. Omiti-lo é o
 * jeito silencioso de entregar uma prévia errada justamente nos cards que a
 * pessoa mais nota.
 */
export function preview(state: CardState, now: Date, params: FsrsParams): Record<Grade, number> {
  const ms = (g: Grade) => {
    const due = apply(state, g, now, params).dueAt;
    return due ? due.getTime() - now.getTime() : 0;
  };
  return {
    [Grade.again]: ms(Grade.again),
    [Grade.hard]: ms(Grade.hard),
    [Grade.good]: ms(Grade.good),
    [Grade.easy]: ms(Grade.easy),
  } as Record<Grade, number>;
}

// ---------------------------------------------------------------------------

function buildEngine(params: FsrsParams): FSRS {
  return new FSRS({
    w: [...params.weights],
    request_retention: params.desiredRetention,
    // §4.1 — nunca aleatório.
    //
    // O pacote liga isto por padrão: espalha a carga jitterando intervalos de
    // ~2,5 dias para cima. Razoável num app de um aparelho só, fatal aqui —
    // faria o mesmo log produzir estados diferentes a cada replay, e dois
    // aparelhos calcularem vencimentos diferentes de históricos idênticos, que
    // é exatamente a falha que esta arquitetura existe para impedir.
    enable_fuzz: false,
  });
}

function toFsrs(state: CardState, at: Date): FsrsCard {
  if (state.phase === 'newCard') {
    return { ...createEmptyCard(at), state: State.Learning, learning_steps: 0, due: at };
  }
  return {
    ...createEmptyCard(at),
    state: toFsrsState(state.phase),
    learning_steps: state.step ?? 0,
    stability: state.stability,
    difficulty: state.difficulty,
    due: state.dueAt ?? at,
    last_review: state.lastReviewAt ?? undefined,
    reps: state.reps,
    lapses: state.lapses,
  };
}

function toRating(grade: Grade): FsrsGrade {
  switch (grade) {
    case Grade.again:
      return Rating.Again;
    case Grade.hard:
      return Rating.Hard;
    case Grade.good:
      return Rating.Good;
    default:
      return Rating.Easy;
  }
}

function toFsrsState(phase: CardPhase): State {
  switch (phase) {
    case 'newCard':
    case 'learning':
      return State.Learning;
    case 'review':
      return State.Review;
    default:
      return State.Relearning;
  }
}

function toPhase(state: State): CardPhase {
  switch (state) {
    case State.Learning:
      return 'learning';
    case State.Review:
      return 'review';
    case State.Relearning:
      return 'relearning';
    default:
      return 'newCard';
  }
}
