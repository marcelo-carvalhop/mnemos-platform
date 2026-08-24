import { describe, expect, it } from 'vitest';
import { Grade } from './contract.g';
import {
  DEFAULT_FSRS_PARAMS,
  PACKAGE_DEFAULT_WEIGHTS,
  apply,
  freshState,
  preview,
  replay,
  type ReviewEntry,
} from './scheduler';
import fixtures from './fsrs-fixtures.json';

/**
 * O acordo entre o aplicativo e a web.
 *
 * §3 diz que o log de revisões é a verdade e `card_state` é um cache
 * reconstruído identicamente em qualquer lugar. O app usa o pacote `fsrs` do
 * pub e a web usa `ts-fsrs` do npm: duas implementações independentes, e nada
 * além deste arquivo impede que divirjam. Se divergirem, as duas superfícies
 * discordam sobre o que vence hoje e a pessoa não tem como saber qual está
 * certa.
 *
 * Os fixtures são gerados por
 * `app/mobile/packages/scheduler/tool/dump_fixtures.dart`. Quando este teste
 * falhar, a pergunta não é "qual valor eu ajusto" — é qual das duas
 * implementações mudou e por quê.
 */

interface Fixture {
  name: string;
  grades: number[];
  startUtc: string;
  expected: {
    stability: number;
    difficulty: number;
    dueAt: string | null;
    reps: number;
    lapses: number;
    phase: string;
    step: number | null;
  };
}

const DAY_MS = 24 * 60 * 60 * 1000;

const relativeError = (a: number, b: number) =>
  b === 0 ? Math.abs(a) : Math.abs(a - b) / Math.abs(b);
const cases = fixtures.cases as Fixture[];
const params = {
  weights: fixtures.weights as number[],
  desiredRetention: fixtures.desiredRetention as number,
};

describe('acordo com o escalonador do aplicativo', () => {
  it('usa o mesmo vetor de pesos', () => {
    // Pesos diferentes produzem agendamentos diferentes mesmo com algoritmos
    // idênticos, e isso não apareceria em nenhum outro teste.
    expect([...DEFAULT_FSRS_PARAMS.weights]).toEqual(fixtures.weights);
    expect(DEFAULT_FSRS_PARAMS.desiredRetention).toBe(fixtures.desiredRetention);
  });

  it('não herda o vetor padrão do pacote', () => {
    // Não é hipótese: `ts-fsrs` traz o vetor do FSRS-6 e o `fsrs` do Dart traz
    // outro. Herdar o padrão de cada pacote fazia a web agendar tudo diferente
    // do telefone, e só o teste cruzado apanhou. Se um dia os dois padrões
    // coincidirem, este teste falha e a resposta é apagá-lo — não é uma
    // afirmação sobre o pacote, é sobre de onde os pesos vêm.
    expect([...PACKAGE_DEFAULT_WEIGHTS]).not.toEqual(fixtures.weights);
  });

  for (const c of cases) {
    it(`reproduz "${c.name}"`, () => {
      const start = new Date(c.startUtc);
      const history: ReviewEntry[] = c.grades.map((g, i) => ({
        id: `r${String(i).padStart(3, '0')}`,
        cardId: 'c1',
        reviewedAt: new Date(start.getTime() + i * DAY_MS),
        grade: g as Grade,
      }));

      const state = replay(history, [], params, 'c1');

      // **A data de vencimento é exata.** É o que a pessoa vê, é o que decide
      // se um card entra na fila de hoje, e é onde uma divergência entre as
      // duas implementações apareceria como o telefone e o navegador
      // discordando. Aqui não há tolerância.
      expect(state.dueAt?.toISOString() ?? null).toBe(c.expected.dueAt);
      expect(state.reps).toBe(c.expected.reps);
      expect(state.lapses).toBe(c.expected.lapses);
      expect(state.phase).toBe(c.expected.phase);

      // Estabilidade e dificuldade toleram erro *relativo*: `ts-fsrs`
      // arredonda para oito casas e o pacote do Dart não, então os dois
      // divergem na quinta casa de um número na casa das dezenas. Isso não
      // move nenhum vencimento — a asserção acima é a prova — e exigir
      // igualdade faria o teste falhar por ruído em vez de por divergência.
      expect(relativeError(state.stability, c.expected.stability)).toBeLessThan(1e-6);
      expect(relativeError(state.difficulty, c.expected.difficulty)).toBeLessThan(1e-6);
    });
  }
});

describe('replay', () => {
  const at = (day: number) => new Date(Date.UTC(2026, 0, 1 + day, 9));

  it('não depende da ordem em que as revisões chegaram', () => {
    // §5.3 — sincronia bidirecional entrega histórico fora de ordem, e o
    // replay não pode depender de quem chegou primeiro.
    const inOrder: ReviewEntry[] = [
      { id: 'a', cardId: 'c', reviewedAt: at(0), grade: Grade.good },
      { id: 'b', cardId: 'c', reviewedAt: at(1), grade: Grade.hard },
      { id: 'c', cardId: 'c', reviewedAt: at(2), grade: Grade.easy },
    ];
    const shuffled = [inOrder[2], inOrder[0], inOrder[1]];

    expect(replay(shuffled, [], DEFAULT_FSRS_PARAMS, 'c')).toEqual(
      replay(inOrder, [], DEFAULT_FSRS_PARAMS, 'c'),
    );
  });

  it('ignora o histórico de outros cards', () => {
    const history: ReviewEntry[] = [
      { id: 'a', cardId: 'outro', reviewedAt: at(0), grade: Grade.good },
      { id: 'b', cardId: 'c', reviewedAt: at(1), grade: Grade.good },
    ];
    expect(replay(history, [], DEFAULT_FSRS_PARAMS, 'c').reps).toBe(1);
  });

  it('reiniciar progresso descarta o agendamento e preserva o histórico', () => {
    // §5.10 — reiniciar não apaga revisão nenhuma (§3 proíbe): o replay é que
    // passa a ignorar o que veio antes do marco.
    const history: ReviewEntry[] = [
      { id: 'a', cardId: 'c', reviewedAt: at(0), grade: Grade.easy },
      { id: 'b', cardId: 'c', reviewedAt: at(1), grade: Grade.easy },
      { id: 'c', cardId: 'c', reviewedAt: at(5), grade: Grade.good },
    ];
    const after = replay(history, [{ cardId: 'c', resetAt: at(3) }], DEFAULT_FSRS_PARAMS, 'c');

    expect(after.reps).toBe(1);
    expect(history).toHaveLength(3);
  });

  it('um card sem histórico é novo, não vencido', () => {
    const state = replay([], [], DEFAULT_FSRS_PARAMS, 'c');
    expect(state).toEqual(freshState('c'));
    expect(state.dueAt).toBeNull();
  });

  it('errar depois de graduar conta como recaída', () => {
    const history: ReviewEntry[] = [
      { id: 'a', cardId: 'c', reviewedAt: at(0), grade: Grade.easy },
      { id: 'b', cardId: 'c', reviewedAt: at(1), grade: Grade.easy },
      { id: 'c', cardId: 'c', reviewedAt: at(20), grade: Grade.again },
    ];
    expect(replay(history, [], DEFAULT_FSRS_PARAMS, 'c').lapses).toBe(1);
  });

  it('errar antes de graduar não conta como recaída', () => {
    // Um card ainda em aprendizado não "recaiu" de lugar nenhum, e contar isso
    // como lapso infla a estatística de dificuldade da pessoa.
    const history: ReviewEntry[] = [
      { id: 'a', cardId: 'c', reviewedAt: at(0), grade: Grade.again },
      { id: 'b', cardId: 'c', reviewedAt: at(0), grade: Grade.again },
    ];
    expect(replay(history, [], DEFAULT_FSRS_PARAMS, 'c').lapses).toBe(0);
  });
});

describe('prévia dos intervalos', () => {
  it('mostra os quatro graus em ordem crescente de intervalo', () => {
    // §5.8.3 — errei ≤ difícil ≤ bom ≤ fácil. Se a ordem quebrar, os botões
    // mentem sobre o que fazem.
    const now = new Date(Date.UTC(2026, 0, 10, 9));
    const state = apply(
      freshState('c'),
      Grade.good,
      new Date(Date.UTC(2026, 0, 1, 9)),
      DEFAULT_FSRS_PARAMS,
    );
    const p = preview(state, now, DEFAULT_FSRS_PARAMS);

    expect(p[Grade.again]).toBeLessThanOrEqual(p[Grade.hard]);
    expect(p[Grade.hard]).toBeLessThanOrEqual(p[Grade.good]);
    expect(p[Grade.good]).toBeLessThanOrEqual(p[Grade.easy]);
  });

  it('a prévia é o que realmente acontece ao gradar', () => {
    // Derivada de `apply`, não calculada ao lado dele. Este teste é o que
    // impede alguém de "otimizar" a prévia para uma fórmula própria.
    const now = new Date(Date.UTC(2026, 0, 10, 9));
    const state = apply(
      freshState('c'),
      Grade.good,
      new Date(Date.UTC(2026, 0, 1, 9)),
      DEFAULT_FSRS_PARAMS,
    );
    const p = preview(state, now, DEFAULT_FSRS_PARAMS);

    const actual = apply(state, Grade.good, now, DEFAULT_FSRS_PARAMS);
    expect(actual.dueAt!.getTime() - now.getTime()).toBe(p[Grade.good]);
  });
});
