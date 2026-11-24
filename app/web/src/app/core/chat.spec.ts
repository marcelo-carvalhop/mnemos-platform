import { HttpErrorResponse, provideHttpClient } from '@angular/common/http';
import { HttpTestingController, provideHttpClientTesting } from '@angular/common/http/testing';
import { provideZonelessChangeDetection } from '@angular/core';
import { TestBed } from '@angular/core/testing';
import { beforeEach, describe, expect, it } from 'vitest';
import { ApiError, Offline, toFailure } from './api';
import { Chat, chatFailure, threadKey, toWire, windowed, type ChatMessage } from './chat';

/**
 * O chat de estudo do lado do cliente: o que vai no pedido, o que fica de fora
 * — a resposta de um card antes de revelada — e a frase de cada falha.
 */
describe('Chat', () => {
  let chat: Chat;
  let http: HttpTestingController;

  beforeEach(() => {
    TestBed.configureTestingModule({
      providers: [
        provideZonelessChangeDetection(),
        provideHttpClient(),
        provideHttpClientTesting(),
      ],
    });
    chat = TestBed.inject(Chat);
    http = TestBed.inject(HttpTestingController);
  });

  it('manda a conversa e o contexto para /v1/chat', async () => {
    const pending = chat.ask([{ role: 'user', content: 'O que é mitose?' }], {
      kind: 'home',
      decks: ['Biologia'],
    });
    const req = http.expectOne('/api/v1/chat');
    expect(req.request.method).toBe('POST');
    expect(req.request.body).toEqual({
      messages: [{ role: 'user', content: 'O que é mitose?' }],
      context: { kind: 'home', decks: ['Biologia'] },
    });
    req.flush({ reply: 'É a divisão celular.', truncated: false, refused: false });
    await expect(pending).resolves.toEqual({
      reply: 'É a divisão celular.',
      truncated: false,
      refused: false,
    });
  });

  it('não envia a resposta do card antes de revelada', () => {
    const card = {
      kind: 'card' as const,
      cardId: 'c1',
      deck: 'História',
      question: 'Quando caiu o Muro?',
      answer: '1989',
    };
    const hidden = toWire({ ...card, revealed: false });
    expect(hidden).not.toHaveProperty('answer');
    expect(hidden).not.toHaveProperty('cardId');
    expect(hidden['question']).toBe('Quando caiu o Muro?');

    expect(toWire({ ...card, revealed: true })['answer']).toBe('1989');
  });

  it('corta a conversa nas últimas vinte, começando por uma pergunta', () => {
    const many: ChatMessage[] = Array.from({ length: 25 }, (_, i) => ({
      role: i % 2 === 0 ? 'user' : 'assistant',
      content: `m${i}`,
    }));
    const sent = windowed(many);
    expect(sent.length).toBeLessThanOrEqual(20);
    expect(sent[0].role).toBe('user');
    expect(sent.at(-1)?.content).toBe('m24');
  });

  it('guarda uma conversa por contexto, e só a do card atual', () => {
    const home = chat.thread('home');
    home.set([{ role: 'user', content: 'oi' }]);
    chat.thread('card:a').set([{ role: 'user', content: 'dica?' }]);

    // Outro card: conversa nova; a de Hoje continua.
    expect(chat.thread('card:b')()).toEqual([]);
    expect(chat.thread('card:a')()).toEqual([]);
    expect(chat.thread('home')()).toEqual([{ role: 'user', content: 'oi' }]);
    expect(threadKey({ kind: 'card', cardId: 'x' })).toBe('card:x');
    expect(threadKey({ kind: 'home' })).toBe('home');
  });

  it('tem uma frase para cada falha', () => {
    const fail = (status: number, detail: string) =>
      toFailure(new HttpErrorResponse({ status, error: { detail } }));

    expect(chatFailure(new Offline()).canRetry).toBe(true);
    expect(chatFailure(fail(429, 'chat_rate_limited')).message).toContain('Espere um minuto');
    expect(chatFailure(fail(429, 'chat_daily_limit'))).toEqual({
      message: 'Você chegou ao limite de perguntas de hoje. Volte amanhã.',
      canRetry: false,
    });
    expect(chatFailure(fail(503, 'chat_not_configured')).canRetry).toBe(false);
    expect(chatFailure(fail(403, 'chat_account_required')).message).toContain('e-mail');
    expect(chatFailure(new ApiError(502, null, 'chat_model_unavailable')).canRetry).toBe(true);
  });
});
