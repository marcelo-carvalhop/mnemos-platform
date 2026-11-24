import { HttpClient } from '@angular/common/http';
import { Injectable, inject, signal, type WritableSignal } from '@angular/core';
import { firstValueFrom } from 'rxjs';
import { ApiError, Offline, toFailure } from './api';
import { API_BASE_URL } from './config';

export type ChatRole = 'user' | 'assistant';

export interface ChatMessage {
  readonly role: ChatRole;
  readonly content: string;
}

/**
 * O que a IA sabe sobre a tela de onde a pergunta saiu.
 *
 * `cardId` fica no cliente: serve para separar a conversa de cada card e não
 * vai para o servidor. A resposta do card só sai daqui com `revealed` — o
 * servidor também a ignora antes disso, mas não mandar é a primeira defesa.
 */
export interface ChatContext {
  readonly kind: 'home' | 'card';
  readonly cardId?: string;
  readonly deck?: string;
  readonly question?: string;
  readonly answer?: string;
  readonly revealed?: boolean;
  readonly decks?: readonly string[];
}

export interface ChatReply {
  reply: string;
  truncated: boolean;
  refused: boolean;
}

/** Os mesmos tetos do servidor (`backend/app/chat/router.py`). */
export const CHAT_MAX_MESSAGES = 20;
export const CHAT_MAX_CHARS = 2000;
const MAX_DECKS = 30;
const MAX_DECK_NAME = 200;

/**
 * A conversa que cabe num pedido: as últimas mensagens, começando por uma
 * pergunta. O começo de uma conversa longa sai antes do fim — o que a pessoa
 * acabou de perguntar é o que precisa de contexto.
 */
export function windowed(messages: readonly ChatMessage[]): ChatMessage[] {
  const tail = messages.slice(-CHAT_MAX_MESSAGES);
  const first = tail.findIndex((m) => m.role === 'user');
  return first < 0 ? [] : tail.slice(first);
}

export function toWire(context: ChatContext): Record<string, unknown> {
  if (context.kind === 'home') {
    return {
      kind: 'home',
      decks: (context.decks ?? []).slice(0, MAX_DECKS).map((d) => d.slice(0, MAX_DECK_NAME)),
    };
  }
  const revealed = context.revealed === true;
  return {
    kind: 'card',
    deck: context.deck?.slice(0, MAX_DECK_NAME),
    question: context.question?.slice(0, CHAT_MAX_CHARS),
    revealed,
    ...(revealed ? { answer: context.answer?.slice(0, CHAT_MAX_CHARS) } : {}),
  };
}

/** A chave da conversa: uma para Hoje, uma por card. */
export function threadKey(context: ChatContext): string {
  return context.kind === 'card' ? `card:${context.cardId ?? ''}` : 'home';
}

export interface ChatFailure {
  readonly message: string;
  readonly canRetry: boolean;
}

/** §10 — o código vira frase aqui, e só aqui. */
export function chatFailure(error: unknown): ChatFailure {
  if (error instanceof Offline) {
    return { message: 'Sem conexão com o servidor. Tente de novo.', canRetry: true };
  }
  if (error instanceof ApiError) {
    const code = error.code ?? error.detail;
    if (code === 'chat_daily_limit') {
      return {
        message: 'Você chegou ao limite de perguntas de hoje. Volte amanhã.',
        canRetry: false,
      };
    }
    if (error.status === 429) {
      return {
        message: 'Muitas perguntas em pouco tempo. Espere um minuto e tente de novo.',
        canRetry: true,
      };
    }
    if (code === 'chat_not_configured' || error.status === 503) {
      return {
        message: 'O chat com IA ainda não está disponível neste servidor.',
        canRetry: false,
      };
    }
    if (code === 'chat_account_required') {
      return { message: 'O chat com IA é para contas com e-mail.', canRetry: false };
    }
    if (error.status === 422) {
      return {
        message: 'Não consegui enviar essa pergunta. Tente uma mais curta.',
        canRetry: false,
      };
    }
  }
  return { message: 'A IA não respondeu agora. Tente de novo em instantes.', canRetry: true };
}

/**
 * O chat de estudo sobre HTTP, e as conversas em memória.
 *
 * Nada é salvo: a conversa vive aqui enquanto a aba existe e vai inteira em
 * cada pedido. Só uma conversa de card por vez — passar ao próximo card começa
 * uma conversa nova, porque a anterior falava de outra pergunta.
 */
@Injectable({ providedIn: 'root' })
export class Chat {
  private readonly http = inject(HttpClient);
  private readonly baseUrl = inject(API_BASE_URL);
  private readonly threads = new Map<string, WritableSignal<ChatMessage[]>>();

  thread(key: string): WritableSignal<ChatMessage[]> {
    let thread = this.threads.get(key);
    if (!thread) {
      if (key.startsWith('card:')) {
        for (const old of [...this.threads.keys()]) {
          if (old.startsWith('card:')) this.threads.delete(old);
        }
      }
      thread = signal<ChatMessage[]>([]);
      this.threads.set(key, thread);
    }
    return thread;
  }

  async ask(messages: readonly ChatMessage[], context: ChatContext): Promise<ChatReply> {
    try {
      return await firstValueFrom(
        this.http.post<ChatReply>(`${this.baseUrl}/v1/chat`, {
          messages: windowed(messages),
          context: toWire(context),
        }),
      );
    } catch (error) {
      throw toFailure(error);
    }
  }
}
