import { TestBed } from '@angular/core/testing';
import { provideHttpClient } from '@angular/common/http';
import { beforeEach, describe, expect, it } from 'vitest';
import { Grade } from './contract.g';
import { Store, dayStart } from './store';

/**
 * O espelho local e as regras que ele carrega.
 *
 * Duas coisas são testadas aqui porque nada mais as protege: que o estado de um
 * card **nunca** é armazenado (§3 — é replay do log, sempre) e que apagar
 * escreve uma lápide em vez de remover a linha, porque um DELETE não tem como
 * sincronizar.
 */
describe('Store', () => {
  let store: Store;

  beforeEach(() => {
    TestBed.configureTestingModule({ providers: [provideHttpClient()] });
    store = TestBed.inject(Store);
  });

  describe('escrita local', () => {
    it('toda escrita entra no outbox', () => {
      // `server_seq` nulo é o outbox (§6.2). Uma linha que nasce sem isso nunca
      // sobe, e o trabalho da pessoa fica só nesta aba.
      const deckId = store.createDeck('História');
      store.createCard(deckId, 'Frente', 'Verso');

      expect(store.outbox('decks')).toHaveLength(1);
      expect(store.outbox('cards')).toHaveLength(1);
    });

    it('carimba updated_at e device_id, que são o critério de conflito', () => {
      store.createDeck('História');
      const deck = store.decks()[0];

      expect(deck.updated_at).toBeTruthy();
      expect(deck.device_id).toBeTruthy();
      expect(deck.server_seq).toBeNull();
    });

    it('apagar um baralho escreve uma lápide e leva os cards junto', () => {
      // §3 — nada é removido. Um DELETE não teria como sincronizar: o outro
      // aparelho nunca saberia que a linha existiu.
      const deckId = store.createDeck('História');
      store.createCard(deckId, 'a', 'b');
      store.deleteDeck(deckId);

      expect(store.decks()).toHaveLength(1);
      expect(store.decks()[0].deleted_at).not.toBeNull();
      expect(store.liveDecks()).toHaveLength(0);
      expect(store.cardsOfDeck(deckId)).toHaveLength(0);
    });

    it('confirmar a linha tira ela do outbox', () => {
      const deckId = store.createDeck('História');
      store.acknowledge('decks', { [deckId]: 42 });

      expect(store.outbox('decks')).toHaveLength(0);
      expect(store.decks()[0].server_seq).toBe(42);
    });
  });

  describe('estado dos cards', () => {
    it('é sempre reconstruído do histórico, nunca armazenado', () => {
      // §3 — `card_state` é cache. Se fosse escrito, existiriam dois fatos
      // capazes de discordar, e é assim que dois aparelhos passam a dizer
      // coisas diferentes sobre o que vence hoje.
      const deckId = store.createDeck('História');
      const cardId = store.createCard(deckId, 'a', 'b');

      expect(store.states().get(cardId)!.reps).toBe(0);

      store.recordReview(cardId, Grade.good, 1200);
      expect(store.states().get(cardId)!.reps).toBe(1);
      expect(store.states().get(cardId)!.dueAt).not.toBeNull();
    });

    it('um card novo está vencido: nunca revisto é para revisar', () => {
      const deckId = store.createDeck('História');
      store.createCard(deckId, 'a', 'b');

      expect(store.due()).toHaveLength(1);
    });

    it('responder tira o card da fila de hoje', () => {
      const deckId = store.createDeck('História');
      const cardId = store.createCard(deckId, 'a', 'b');
      store.recordReview(cardId, Grade.easy, null);

      expect(store.due()).toHaveLength(0);
    });

    it('um card suspenso não entra na fila', () => {
      // §5.1 — suspender é o que se faz com um card ruim que ainda não se quer
      // apagar; ele não pode continuar aparecendo.
      const deckId = store.createDeck('História');
      const cardId = store.createCard(deckId, 'a', 'b');
      store.apply(
        'card_flags',
        [
          {
            card_id: cardId,
            status: 'suspended',
            buried_until: null,
            updated_at: new Date().toISOString(),
            device_id: 'x',
            server_seq: 1,
          },
        ],
        1,
      );

      expect(store.due()).toHaveLength(0);
    });

    it('um card apagado não aparece em lugar nenhum', () => {
      const deckId = store.createDeck('História');
      const cardId = store.createCard(deckId, 'a', 'b');
      store.deleteCard(cardId);

      expect(store.due()).toHaveLength(0);
      expect(store.liveCards()).toHaveLength(0);
      expect(store.states().has(cardId)).toBe(false);
    });
  });

  describe('conflito (§6.2)', () => {
    const row = (name: string, at: string, device: string) => ({
      id: 'd1',
      parent_id: null,
      name,
      description: null,
      version: 1,
      origin: 'own',
      archived_at: null,
      deleted_at: null,
      updated_at: at,
      device_id: device,
      server_seq: 1,
    });

    it('o mais recente vence', () => {
      store.apply('decks', [row('antigo', '2026-01-01T00:00:00Z', 'a')], 1);
      store.apply('decks', [row('novo', '2026-02-01T00:00:00Z', 'b')], 2);

      expect(store.decks()[0].name).toBe('novo');
    });

    it('uma linha mais velha não sobrescreve a local', () => {
      store.apply('decks', [row('novo', '2026-02-01T00:00:00Z', 'b')], 1);
      store.apply('decks', [row('antigo', '2026-01-01T00:00:00Z', 'a')], 2);

      expect(store.decks()[0].name).toBe('novo');
    });

    it('empate desempata pelo device_id, e não por quem falou por último', () => {
      // Avaliar localmente com a mesma regra do servidor é o que faz os dois
      // lados convergirem para a mesma resposta.
      const same = '2026-01-01T00:00:00Z';
      store.apply('decks', [row('do-b', same, 'b')], 1);
      store.apply('decks', [row('do-a', same, 'a')], 2);

      expect(store.decks()[0].name).toBe('do-b');
    });

    it('histórico entra por união e nunca é sobrescrito', () => {
      // §6.1 — uma revisão é um fato que aconteceu. Reescrevê-la seria reescrever
      // o passado, e §3 proíbe.
      const review = (grade: number) => ({
        id: 'r1',
        card_id: 'c1',
        reviewed_at: '2026-01-01T00:00:00Z',
        grade,
        source: 'standard',
        elapsed_ms: null,
        updated_at: '2026-01-01T00:00:00Z',
        device_id: 'a',
        server_seq: 1,
      });

      store.apply('reviews', [review(3)], 1);
      store.apply('reviews', [review(1)], 2);

      expect(store.reviews()).toHaveLength(1);
      expect(store.reviews()[0].grade).toBe(3);
    });
  });
});

describe('o dia de estudo (§5.7)', () => {
  it('vira às 04:00, não à meia-noite', () => {
    // Quem estuda de madrugada está terminando o dia anterior, não começando o
    // próximo — e a meta de hoje tem de concordar com isso.
    const oneAm = new Date(2026, 5, 10, 1, 0);
    expect(dayStart(oneAm).getDate()).toBe(9);

    const nineAm = new Date(2026, 5, 10, 9, 0);
    expect(dayStart(nineAm).getDate()).toBe(10);
  });

  it('exatamente às 04:00 já é o dia novo', () => {
    const fourAm = new Date(2026, 5, 10, 4, 0);
    expect(dayStart(fourAm).getDate()).toBe(10);
  });
});
