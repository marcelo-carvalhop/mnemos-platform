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

export interface PendingCard {
  id: string;
  front: string;
  back: string;
  tags: string[];
  position: number;
  decision: string | null;
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
  async open(): Promise<OpenGeneration[]> {
    const body = await this.call<{ jobs: OpenGeneration[] }>(
      this.http.get<{ jobs: OpenGeneration[] }>(`${this.baseUrl}/v1/generation/jobs`),
    );
    return body.jobs ?? [];
  }

  async create(input: {
    sourceType: 'topic' | 'text' | 'pdf' | 'photo';
    targetDeckId: string;
    topic?: string;
    uploadKey?: string;
    requestedCount?: number;
    level?: string;
  }): Promise<GenerationJob> {
    return this.call<GenerationJob>(
      this.http.post<GenerationJob>(`${this.baseUrl}/v1/generation/jobs`, {
        source_type: input.sourceType,
        target_deck_id: input.targetDeckId,
        topic: input.topic,
        upload_key: input.uploadKey,
        requested_count: input.requestedCount ?? 10,
        level: input.level ?? 'intermediario',
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
