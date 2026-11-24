import { provideHttpClient } from '@angular/common/http';
import { provideZonelessChangeDetection } from '@angular/core';
import { TestBed, type ComponentFixture } from '@angular/core/testing';
import { beforeEach, describe, expect, it, vi } from 'vitest';
import { ApiError } from '../../core/api';
import { Chat, type ChatContext } from '../../core/chat';
import { ChatPanel } from './chat-panel';

/**
 * O painel do chat: abre pelo próprio botão, conversa, mostra a falha com a
 * frase certa e fecha com Esc — sem que o Esc chegue a quem escuta o
 * documento por trás.
 */
describe('ChatPanel', () => {
  let fixture: ComponentFixture<ChatPanel>;
  let chat: Chat;
  let ask: ReturnType<typeof vi.fn>;

  const el = () => fixture.nativeElement as HTMLElement;
  const text = () => el().textContent ?? '';
  const dialog = () => el().querySelector('dialog') as HTMLDialogElement;
  const textarea = () => el().querySelector('textarea') as HTMLTextAreaElement;

  const build = async (context: ChatContext) => {
    fixture = TestBed.createComponent(ChatPanel);
    fixture.componentRef.setInput('context', context);
    await fixture.whenStable();
    fixture.detectChanges();
  };

  const open = async () => {
    (el().querySelector('.trigger') as HTMLButtonElement).click();
    await fixture.whenStable();
    fixture.detectChanges();
  };

  const type = async (value: string) => {
    textarea().value = value;
    textarea().dispatchEvent(new Event('input'));
    fixture.detectChanges();
    textarea().dispatchEvent(
      new KeyboardEvent('keydown', { key: 'Enter', bubbles: true, cancelable: true }),
    );
    await fixture.whenStable();
    fixture.detectChanges();
  };

  beforeEach(() => {
    TestBed.configureTestingModule({
      providers: [provideZonelessChangeDetection(), provideHttpClient()],
    });
    chat = TestBed.inject(Chat);
    ask = vi.fn();
    chat.ask = ask as unknown as Chat['ask'];
    // Cada teste começa com conversas vazias.
    chat.thread('home').set([]);
  });

  it('abre pelo botão com a apresentação e as sugestões de Hoje', async () => {
    await build({ kind: 'home' });
    expect(dialog().open).toBe(false);

    await open();
    expect(dialog().open).toBe(true);
    expect(text()).toContain('Pergunte à IA');
    expect(text()).toContain('A IA pode errar');
    expect(text()).toContain('Como memorizar melhor?');
  });

  it('envia com Enter e mostra a resposta', async () => {
    ask.mockResolvedValue({ reply: 'Use repetição espaçada.', truncated: false, refused: false });
    await build({ kind: 'home', decks: ['Biologia'] });
    await open();

    await type('Como estudo melhor?');

    expect(ask).toHaveBeenCalledWith([{ role: 'user', content: 'Como estudo melhor?' }], {
      kind: 'home',
      decks: ['Biologia'],
    });
    expect(text()).toContain('Como estudo melhor?');
    expect(text()).toContain('Use repetição espaçada.');
    expect(textarea().value).toBe('');
    // As sugestões de Hoje servem para começar a conversa.
    expect(el().querySelectorAll('.chips button').length).toBe(0);
  });

  it('a sugestão é uma pergunta pronta', async () => {
    ask.mockResolvedValue({ reply: 'Pense na Guerra Fria.', truncated: false, refused: false });
    await build({ kind: 'card', cardId: 'c1', question: 'Quando caiu o Muro?', revealed: false });
    await open();

    const chips = [...el().querySelectorAll('.chips button')].map((b) => b.textContent?.trim());
    expect(chips).toEqual(['Me dê uma dica', 'Explique a pergunta']);

    (el().querySelector('.chips button') as HTMLButtonElement).click();
    await fixture.whenStable();
    fixture.detectChanges();
    expect(ask.mock.calls[0][0]).toEqual([{ role: 'user', content: 'Me dê uma dica' }]);
    expect(text()).toContain('Pense na Guerra Fria.');
  });

  it('depois de revelar, as sugestões explicam', async () => {
    await build({ kind: 'card', cardId: 'c2', question: 'P', answer: 'R', revealed: true });
    const chips = [...el().querySelectorAll('.chips button')].map((b) => b.textContent?.trim());
    expect(chips).toEqual([
      'Por que essa é a resposta?',
      'Explique de outro jeito',
      'Dê um exemplo',
    ]);
  });

  it('mostra a falha com a frase do código e deixa tentar de novo', async () => {
    ask.mockRejectedValueOnce(new ApiError(429, null, 'chat_rate_limited'));
    await build({ kind: 'home' });
    await open();
    await type('Oi?');

    expect(text()).toContain('Muitas perguntas em pouco tempo');
    // A pergunta não se perde.
    expect(text()).toContain('Oi?');

    ask.mockResolvedValueOnce({ reply: 'Olá!', truncated: false, refused: false });
    const retry = [...el().querySelectorAll('.problem button')][0] as HTMLButtonElement;
    retry.click();
    await fixture.whenStable();
    fixture.detectChanges();
    expect(text()).toContain('Olá!');
    expect(text()).not.toContain('Muitas perguntas');
  });

  it('sem chave no servidor, diz isso e não oferece repetir', async () => {
    ask.mockRejectedValueOnce(new ApiError(503, null, 'chat_not_configured'));
    await build({ kind: 'home' });
    await open();
    await type('Oi?');
    expect(text()).toContain('não está disponível');
    expect(el().querySelector('.problem button')).toBeNull();
  });

  it('Esc fecha o chat e avisa o documento que a tecla foi usada', async () => {
    await build({ kind: 'home' });
    await open();

    const escape = new KeyboardEvent('keydown', { key: 'Escape', bubbles: true, cancelable: true });
    textarea().dispatchEvent(escape);
    await fixture.whenStable();
    fixture.detectChanges();

    expect(escape.defaultPrevented).toBe(true);
    expect(dialog().open).toBe(false);
  });
});
