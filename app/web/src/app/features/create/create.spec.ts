import { provideHttpClient } from '@angular/common/http';
import { provideZonelessChangeDetection } from '@angular/core';
import { TestBed, type ComponentFixture } from '@angular/core/testing';
import { provideRouter } from '@angular/router';
import { beforeEach, describe, expect, it, vi } from 'vitest';
import { ApiError } from '../../core/api';
import { Generation } from '../../core/generation';
import { Store } from '../../core/store';
import { Sync } from '../../core/sync';
import { Create, deckNameFrom } from './create';

/**
 * A criação AI-first, e o paywall tratado com honestidade.
 *
 * O que vale testar: que a cota é dita **antes** de ser gasta, que o caminho
 * grátis nunca some, e que um 402 não destrói o baralho que já foi criado.
 */
describe('Create', () => {
  let fixture: ComponentFixture<Create>;
  let store: Store;
  const api = {
    quota: vi.fn(),
    create: vi.fn(),
  };

  const text = () => fixture.nativeElement.textContent as string;

  const build = async () => {
    fixture = TestBed.createComponent(Create);
    await fixture.whenStable();
    fixture.detectChanges();
  };

  beforeEach(() => {
    api.quota.mockReset();
    api.create.mockReset();
    api.quota.mockResolvedValue({ remaining: 1, limit: 1, plan: 'free' });

    TestBed.configureTestingModule({
      providers: [
        provideZonelessChangeDetection(),
        provideHttpClient(),
        provideRouter([]),
        { provide: Generation, useValue: api },
        { provide: Sync, useValue: { syncNow: vi.fn().mockResolvedValue(undefined) } },
      ],
    });
    store = TestBed.inject(Store);
  });

  it('diz a cota antes de qualquer campo', async () => {
    // §7.7.1 — uma geração para a vida da conta. Contar isso só depois de gasta
    // é tirar algo que a pessoa não sabia que tinha.
    await build();
    expect(text()).toContain('1 geração grátis disponível');
  });

  it('sem cota, o botão vira assinatura e não uma tentativa fadada', async () => {
    api.quota.mockResolvedValue({ remaining: 0, limit: 1, plan: 'free' });
    await build();

    expect(text()).toContain('já foi usada');
    expect(text()).toContain('Assinar para gerar');
    expect(text()).not.toContain('Criar com IA');
  });

  it('o caminho grátis nunca some', async () => {
    // Mesmo sem cota: escrever cards à mão é livre, sempre, e uma tela que
    // esconde isso quando o dinheiro entra em jogo está mentindo.
    api.quota.mockResolvedValue({ remaining: 0, limit: 1, plan: 'free' });
    await build();
    expect(text()).toContain('Escrever eu mesmo');
  });

  it('offline, a cota diz que não sabe em vez de chutar', async () => {
    api.quota.mockRejectedValue(new ApiError(0));
    await build();

    expect(text()).not.toContain('já foi usada');
    expect(text()).not.toContain('-1');
  });

  it('gerar exige um assunto', async () => {
    await build();
    const button = fixture.nativeElement.querySelector('button.primary') as HTMLButtonElement;
    expect(button.disabled).toBe(true);
  });

  it('o baralho e os cards nascem da mesma ação', async () => {
    api.create.mockResolvedValue({ id: 'job', status: 'queued', stage: 'na fila' });
    await build();

    fixture.componentInstance['subject'].set('Ciclo de Krebs');
    await fixture.componentInstance['generate']();

    // O nome do baralho sai do que a pessoa escreveu: ninguém é perguntado
    // duas vezes sobre o mesmo assunto.
    expect(store.decks().map((d) => d.name)).toEqual(['Ciclo de Krebs']);
    expect(api.create).toHaveBeenCalledTimes(1);
  });

  it('o baralho chega ao servidor antes de a geração ser pedida', async () => {
    // O servidor recusa gerar dentro de um baralho que não conhece (§7.3), e
    // este acabou de nascer neste navegador.
    const order: string[] = [];
    const sync = { syncNow: vi.fn().mockImplementation(async () => void order.push('sync')) };
    TestBed.resetTestingModule();
    TestBed.configureTestingModule({
      providers: [
        provideZonelessChangeDetection(),
        provideHttpClient(),
        provideRouter([]),
        { provide: Generation, useValue: api },
        { provide: Sync, useValue: sync },
      ],
    });
    api.create.mockImplementation(async () => {
      order.push('create');
      return { id: 'job', status: 'queued', stage: 'na fila' };
    });
    await build();

    fixture.componentInstance['subject'].set('Ciclo de Krebs');
    await fixture.componentInstance['generate']();

    expect(order).toEqual(['sync', 'create']);
  });

  it('um 402 não apaga o baralho que já foi criado', async () => {
    // Punir a pessoa por uma decisão comercial nossa seria destruir trabalho
    // dela. O baralho fica, e escrever à mão nele continua livre.
    api.create.mockRejectedValue(new ApiError(402, 'quota_exhausted'));
    await build();

    fixture.componentInstance['subject'].set('Ciclo de Krebs');
    await fixture.componentInstance['generate']();
    fixture.detectChanges();

    expect(store.decks().map((d) => d.name)).toEqual(['Ciclo de Krebs']);
    expect(text()).toContain('escrever os cards à mão');
  });
});

describe('deckNameFrom', () => {
  it('usa o assunto como está quando ele cabe', () => {
    expect(deckNameFrom('Ciclo de Krebs')).toBe('Ciclo de Krebs');
  });

  it('corta em palavra, nunca no meio de uma', () => {
    const name = deckNameFrom(
      'Revolução Gloriosa de 1688 e a consolidação do parlamentarismo inglês',
    );
    expect(name.length).toBeLessThanOrEqual(44);
    expect(name.startsWith('Revolução Gloriosa de 1688')).toBe(true);
  });

  it('uma palavra única e enorme ainda vira um nome utilizável', () => {
    expect(deckNameFrom('A'.repeat(200)).length).toBeLessThanOrEqual(44);
  });

  it('quebra de linha não vai para o nome do baralho', () => {
    // O campo aceita várias linhas, e a lista da biblioteca reserva uma linha
    // por baralho.
    expect(deckNameFrom('Ciclo de Krebs\ne a cadeia respiratória')).not.toContain('\n');
  });
});
