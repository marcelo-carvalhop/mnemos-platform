import { provideHttpClient } from '@angular/common/http';
import { provideZonelessChangeDetection } from '@angular/core';
import { TestBed, type ComponentFixture } from '@angular/core/testing';
import { provideRouter } from '@angular/router';
import { beforeEach, describe, expect, it } from 'vitest';
import { Grade } from '../../core/contract.g';
import { Store } from '../../core/store';
import { Sync } from '../../core/sync';
import { Study } from './study';

/**
 * A sessão de estudo, pelo teclado.
 *
 * O que vale testar aqui não é que um botão existe: é que espaço revela, que
 * 1–4 só graduam **depois** de revelar, que a fila não encolhe embaixo da
 * pessoa, e que digitar num campo de texto não gradua nada por acidente.
 */
describe('Study', () => {
  let fixture: ComponentFixture<Study>;
  let store: Store;

  const press = (key: string, target?: EventTarget) => {
    const event = new KeyboardEvent('keydown', { key, bubbles: true, cancelable: true });
    if (target) Object.defineProperty(event, 'target', { value: target });
    document.dispatchEvent(event);
    fixture.detectChanges();
  };

  const text = () => fixture.nativeElement.textContent as string;

  beforeEach(async () => {
    TestBed.configureTestingModule({
      providers: [provideZonelessChangeDetection(), provideHttpClient(), provideRouter([])],
    });
    store = TestBed.inject(Store);

    const deckId = store.createDeck('História');
    store.createCard(deckId, 'Quem foi deposto em 1688?', 'Jaime II.');
    store.createCard(deckId, 'O que é o Bill of Rights?', 'A carta de 1689.');

    fixture = TestBed.createComponent(Study);
    await fixture.whenStable();
    fixture.detectChanges();
  });

  it('abrir direto pela URL espera a sincronia antes de congelar a fila', async () => {
    // Duas falhas de uma vez, as duas vistas no navegador. Congelar no
    // construtor congelava a fila **vazia** — "nada vencendo" enquanto Hoje
    // mostrava oito. E congelar assim que aparecia o primeiro card congelava
    // uma fila **grande demais**: `reviews` é a última tabela do pull, e antes
    // dela todo card parece novo.
    TestBed.resetTestingModule();
    TestBed.configureTestingModule({
      providers: [provideZonelessChangeDetection(), provideHttpClient(), provideRouter([])],
    });
    const store = TestBed.inject(Store);
    const sync = TestBed.inject(Sync);
    sync.phase.set('syncing');

    const f = TestBed.createComponent(Study);
    await f.whenStable();
    f.detectChanges();
    expect(f.nativeElement.textContent).not.toContain('Nada vencendo');

    // A sincronia chega com os cards.
    const deckId = store.createDeck('História');
    const respondido = store.createCard(deckId, 'Já respondido', 'Resposta');
    store.createCard(deckId, 'Chegou depois', 'Resposta');
    // O histórico chega por último, e é ele que tira um card da fila.
    store.recordReview(respondido, Grade.easy, null);
    sync.phase.set('idle');
    await f.whenStable();
    f.detectChanges();

    expect(f.nativeElement.textContent).toContain('Chegou depois');
    // Um só na fila: o respondido não conta, e o total não pode inflar.
    // O contador é a posição na sessão ("1 de 1"), não o número de feitos.
    expect(f.nativeElement.textContent).toContain('1 de 1');
  });

  it('sem nada vencendo e com a sincronia pronta, diz que não há nada', async () => {
    TestBed.resetTestingModule();
    TestBed.configureTestingModule({
      providers: [provideZonelessChangeDetection(), provideHttpClient(), provideRouter([])],
    });
    TestBed.inject(Sync).phase.set('idle');

    const f = TestBed.createComponent(Study);
    await f.whenStable();
    f.detectChanges();

    expect(f.nativeElement.textContent).toContain('Nada vencendo agora');
  });

  it('mostra a pergunta e esconde a resposta', () => {
    expect(text()).toContain('Quem foi deposto em 1688?');
    expect(text()).not.toContain('Jaime II.');
  });

  it('espaço revela a resposta', () => {
    press(' ');
    expect(text()).toContain('Jaime II.');
  });

  it('um grau antes de revelar não faz nada', () => {
    // Graduar sem ler é a única coisa que a tela existe para impedir.
    press('3');
    expect(store.reviews()).toHaveLength(0);
    expect(text()).toContain('Quem foi deposto em 1688?');
  });

  it('depois de revelar, a tecla gradua e passa para o próximo', () => {
    press(' ');
    press('3');

    expect(store.reviews()).toHaveLength(1);
    expect(store.reviews()[0].grade).toBe(Grade.good);
    expect(text()).toContain('O que é o Bill of Rights?');
  });

  it('o próximo card volta escondido', () => {
    press(' ');
    press('3');
    expect(text()).not.toContain('A carta de 1689.');
  });

  it('a fila não encolhe embaixo de quem está estudando', () => {
    // `store.due()` é reativo: sem congelar, o total iria de "2" para "1 de 1"
    // a cada resposta, e a sessão nunca pareceria ter fim.
    expect(text()).toContain('1 de 2');
    press(' ');
    press('4');
    // O que importa aqui é o denominador: a segunda resposta continua sendo
    // "de 2", e não vira "de 1" porque a fila encolheu embaixo da pessoa.
    expect(text()).toContain('2 de 2');
    expect(text()).not.toContain('de 1');
  });

  it('digitar num campo de texto não gradua', () => {
    press(' ');
    const input = document.createElement('input');
    press('1', input);

    expect(store.reviews()).toHaveLength(0);
  });

  it('cada grau mostra o intervalo que produz, antes da escolha', () => {
    // §5.8.3 — a prévia vem de `preview`, derivada de `apply`. Ela não pode
    // mentir porque é o mesmo cálculo.
    press(' ');
    const labels = [...fixture.nativeElement.querySelectorAll('.grade .when')].map(
      (el: Element) => el.textContent?.trim() ?? '',
    );

    expect(labels).toHaveLength(4);
    expect(labels.every((l: string) => l.length > 0 && l !== '—')).toBe(true);
  });

  it('ao fim, diz quantos cards foram revistos', async () => {
    press(' ');
    press('3');
    press(' ');
    press('3');
    await fixture.whenStable();
    fixture.detectChanges();

    expect(text()).toContain('Sessão concluída');
    expect(text()).toContain('2 cards revistos');
  });
});
