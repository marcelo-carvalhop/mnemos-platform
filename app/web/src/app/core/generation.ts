import { HttpClient } from '@angular/common/http';
import { Injectable, inject } from '@angular/core';
import { firstValueFrom } from 'rxjs';
import { toFailure } from './api';
import { API_BASE_URL } from './config';

export interface GenerationJob {
  id: string;
  status: string;
  stage: string;
  error_code: string | null;
  error_detail: string | null;
  card_count: number;
}

export interface OpenGeneration {
  id: string;
  status: string;
  stage: string;
  target_deck_id: string;
  topic: string | null;
  pending: number;
}

/** Uma geração que falhou sem ninguém olhando, até a pessoa ver o motivo. */
export interface FailedGeneration {
  id: string;
  error_code: string | null;
  topic: string | null;
  source_type: string;
  target_deck_id: string;
}

export interface PendingCard {
  id: string;
  front: string;
  back: string;
  tags: string[];
  position: number;
  decision: string | null;
}

/** Uma parte do PDF que vale escolher: capítulo, unidade, aula. */
export interface BriefingSection {
  title: string;
  from_page: number;
  to_page: number;
}

/** Uma pergunta curta com opções de tocar. */
export interface BriefingQuestion {
  id: string;
  text: string;
  options: string[];
  multiple: boolean;
}

/**
 * O que a IA entendeu do material antes de gerar: o que ele é, as partes, até
 * três perguntas e a instrução que vai guiar os cards (`focus`), que a pessoa
 * pode editar. Ver `backend/app/generation/briefing.py`.
 */
export interface Briefing {
  summary: string;
  focus: string;
  suggested_count: number;
  sections: BriefingSection[];
  questions: BriefingQuestion[];
  page_count: number | null;
  refused: boolean;
}

export interface Quota {
  remaining: number;
  limit: number;
  plan: string;
}

/** §7 sobre HTTP. Mesmos endpoints que o aplicativo usa, mesma semântica. */
@Injectable({ providedIn: 'root' })
export class Generation {
  private readonly http = inject(HttpClient);
  private readonly baseUrl = inject(API_BASE_URL);

  async quota(): Promise<Quota> {
    return this.call<Quota>(this.http.get<Quota>(`${this.baseUrl}/v1/quota/`));
  }

  /** §7.8 — o que o servidor ainda deve: gerações rodando ou esperando resposta. */
  async open(): Promise<{ jobs: OpenGeneration[]; failed: FailedGeneration[] }> {
    type Body = { jobs?: OpenGeneration[]; failed?: FailedGeneration[] };
    const body = await this.call<Body>(this.http.get<Body>(`${this.baseUrl}/v1/generation/jobs`));
    return { jobs: body.jobs ?? [], failed: body.failed ?? [] };
  }

  /** A pessoa viu que a geração falhou: o aviso de Hoje some. */
  async markFailureSeen(jobId: string): Promise<void> {
    await this.call(this.http.post(`${this.baseUrl}/v1/generation/jobs/${jobId}/seen`, {}));
  }

  /**
   * §7.2 — uma URL pré-assinada. O arquivo vai direto para o armazenamento.
   *
   * Só `application/pdf`, `image/jpeg`, `image/png` e `image/webp` são aceitos;
   * qualquer outro tipo volta 415 daqui, antes de o navegador subir um byte.
   */
  async createUpload(contentType: string): Promise<{ upload_key: string; url: string }> {
    return this.call<{ upload_key: string; url: string }>(
      this.http.post<{ upload_key: string; url: string }>(`${this.baseUrl}/v1/generation/uploads`, {
        content_type: contentType,
      }),
    );
  }

  /**
   * O PUT vai para o armazenamento, não para a nossa API (§7.2).
   *
   * O `content-type` tem de ser exatamente o mesmo que assinou a URL, senão a
   * assinatura não confere. E o interceptor de autenticação não carimba este
   * pedido — ele só assina o nosso host —, o que é o certo: um `Authorization`
   * a mais aqui invalidaria a assinatura.
   */
  async upload(url: string, file: Blob, contentType: string): Promise<void> {
    await this.call<unknown>(
      this.http.put(url, file, { headers: { 'content-type': contentType } }),
    );
  }

  /**
   * A conversa antes de gerar: lê o começo do material e pergunta o que importa.
   * `round` 2 manda as respostas da primeira; não há terceira.
   */
  async briefing(input: {
    sourceType: 'pdf' | 'photo';
    uploadKey: string;
    round?: number;
    answers?: { question: string; answer: string }[];
    note?: string;
  }): Promise<Briefing> {
    return this.call<Briefing>(
      this.http.post<Briefing>(`${this.baseUrl}/v1/generation/briefing`, {
        source_type: input.sourceType,
        upload_key: input.uploadKey,
        round: input.round ?? 1,
        answers: input.answers ?? [],
        note: input.note ?? '',
      }),
    );
  }

  async create(input: {
    sourceType: 'topic' | 'text' | 'pdf' | 'photo';
    targetDeckId: string;
    topic?: string;
    uploadKey?: string;
    requestedCount?: number;
    level?: string;
    /** PDF e foto: o que a pessoa quer do material, saído do briefing. */
    focus?: string;
    /** PDF: as páginas a ler, 1 a N, inclusivas. Vazio é o arquivo inteiro. */
    pageRanges?: [number, number][];
  }): Promise<GenerationJob> {
    return this.call<GenerationJob>(
      this.http.post<GenerationJob>(`${this.baseUrl}/v1/generation/jobs`, {
        source_type: input.sourceType,
        target_deck_id: input.targetDeckId,
        topic: input.topic,
        upload_key: input.uploadKey,
        requested_count: input.requestedCount ?? 10,
        level: input.level ?? 'intermediario',
        focus: input.focus || undefined,
        page_ranges: input.pageRanges?.length ? input.pageRanges : undefined,
      }),
    );
  }

  async get(jobId: string): Promise<GenerationJob> {
    return this.call<GenerationJob>(
      this.http.get<GenerationJob>(`${this.baseUrl}/v1/generation/jobs/${jobId}`),
    );
  }

  async queue(jobId: string): Promise<{ cards: PendingCard[]; decided: number; total: number }> {
    return this.call(
      this.http.get<{ cards: PendingCard[]; decided: number; total: number }>(
        `${this.baseUrl}/v1/generation/jobs/${jobId}/queue`,
      ),
    );
  }

  /** `null` é desfazer: §5.7 modela isso como decisão, não como campo ausente. */
  async decide(pendingId: string, decision: 'approved' | 'discarded' | null): Promise<PendingCard> {
    return this.call<PendingCard>(
      this.http.post<PendingCard>(`${this.baseUrl}/v1/generation/pending/${pendingId}`, {
        decision,
      }),
    );
  }

  async approveRemaining(jobId: string): Promise<number> {
    const body = await this.call<{ created: number }>(
      this.http.post<{ created: number }>(
        `${this.baseUrl}/v1/generation/jobs/${jobId}/approve-all`,
        {},
      ),
    );
    return body.created;
  }

  async close(jobId: string): Promise<number> {
    const body = await this.call<{ created: number }>(
      this.http.post<{ created: number }>(`${this.baseUrl}/v1/generation/jobs/${jobId}/close`, {}),
    );
    return body.created;
  }

  private async call<T>(request: import('rxjs').Observable<T>): Promise<T> {
    try {
      return await firstValueFrom(request);
    } catch (e) {
      throw toFailure(e);
    }
  }
}
