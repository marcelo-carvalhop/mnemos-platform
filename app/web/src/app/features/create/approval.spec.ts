import { provideHttpClient } from '@angular/common/http';
import { provideZonelessChangeDetection } from '@angular/core';
import { TestBed, type ComponentFixture } from '@angular/core/testing';
import { provideRouter } from '@angular/router';
import { beforeEach, describe, expect, it, vi } from 'vitest';
import { Generation, type PendingCard } from '../../core/generation';
import { Sync } from '../../core/sync';
import { Approval } from './approval';

/**
 * A fila de aprovação, pelo teclado — e os estados que já morderam o
 * aplicativo: uma fila que chega vazia, e uma tela sem saída.
 */
describe('Approval', () => {
  let fixture: ComponentFixture<Approval>;
  const api = { queue: vi.fn(), decide: vi.fn(), approveRemaining: vi.fn(), close: vi.fn() };

  const card = (i: number): PendingCard => ({
    id: `p${i}`,
    front: `Pergunta ${i}`,
    back: `Resposta ${i}`,
    tags: [],
    position: i,
    decision: null,
  });

  const press = (key: string) => {
    document.dispatchEvent(new KeyboardEvent('keydown', { key, bubbles: true, cancelable: true }));
    fixture.detectChanges();
  };

  const text = () => fixture.nativeElement.textContent as string;

  const build = async (cards: PendingCard[]) => {
    api.queue.mockResolvedValue({ cards, decided: 0, total: cards.length });
    fixture = TestBed.createComponent(Approval);
    fixture.componentRef.setInput('jobId', 'job');
    await fixture.whenStable();
    fixture.detectChanges();
  };

  beforeEach(() => {
    for (const fn of Object.values(api)) fn.mockReset();
    api.decide.mockImplementation(async (id: string) => ({ ...card(1), id }));
    api.close.mockResolvedValue(2);
    api.approveRemaining.mockResolvedValue(2);

    TestBed.configureTestingModule({
      providers: [
        provideZonelessChangeDetection(),
        provideHttpClient(),
        provideRouter([]),
        { provide: Generation, useValue: api },
        { provide: Sync, useValue: { syncNow: vi.fn().mockResolvedValue(undefined) } },
      ],
    });
  });

  it('mostra um card por vez, com a resposta junto', async () => {
    // Julgar a qualidade de um card exige ver os dois lados: a pergunta sem a
    // resposta não dá para aprovar nem descartar com honestidade.
    await build([card(1), card(2)]);
    expect(text()).toContain('Pergunta 1');
    expect(text()).toContain('Resposta 1');
    expect(text()).not.toContain('Pergunta 2');
  });

  it('A aprova e passa para o próximo', async () => {
    await build([card(1), card(2)]);
    press('a');
    await fixture.whenStable();
    fixture.detectChanges();

    expect(api.decide).toHaveBeenCalledWith('p1', 'approved');
    expect(text()).toContain('Pergunta 2');
  });

  it('D descarta', async () => {
    await build([card(1), card(2)]);
    press('d');
    await fixture.whenStable();

    expect(api.decide).toHaveBeenCalledWith('p1', 'discarded');
  });

  it('Z devolve o card ao topo da fila', async () => {
    // §5.7 — nulo é a decisão de "des-decidir", que o servidor modela de
    // propósito, e não um campo ausente.
    await build([card(1), card(2)]);
    press('d');
    await fixture.whenStable();
    press('z');
    await fixture.whenStable();
    fixture.detectChanges();

    expect(api.decide).toHaveBeenLastCalledWith('p1', null);
    expect(text()).toContain('Pergunta 1');
  });

  it('uma fila vazia não diz que você aprovou tudo', async () => {
    // "Você aprovou todos" com zero cards é 0 === 0 virando elogio. Ninguém
    // aprovou nada: a geração não produziu card algum.
    await build([]);
    expect(text()).not.toContain('Você aprovou todos');
    expect(text()).toContain('Nenhum card chegou');
    expect(text()).toContain('não foi gasta');
  });

  it('uma fila vazia oferece uma saída', async () => {
    // Sem nada aprovado, aprovar, descartar e criar ficam todos desabilitados.
    // Uma tela onde nenhum botão funciona é um beco sem saída.
    await build([]);
    const live = [...fixture.nativeElement.querySelectorAll('button')].filter(
      (b: HTMLButtonElement) => !b.disabled,
    );
    expect(live.length).toBeGreaterThan(0);
  });

  it('descartar tudo também termina com uma saída, não com um botão morto', async () => {
    await build([card(1)]);
    press('d');
    await fixture.whenStable();
    fixture.detectChanges();

    expect(text()).toContain('0 de 1 aprovados');
    expect(text()).toContain('Voltar');
  });

  it('falhar ao salvar devolve o card em vez de perdê-lo', async () => {
    // A decisão é otimista para não transformar vinte julgamentos em vinte
    // esperas — mas um card que some numa falha de rede é trabalho perdido.
    api.decide.mockRejectedValue(new Error('sem rede'));
    await build([card(1), card(2)]);
    press('a');
    await fixture.whenStable();
    fixture.detectChanges();

    expect(text()).toContain('Pergunta 1');
  });
});
