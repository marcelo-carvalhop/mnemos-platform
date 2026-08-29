import { HttpClient } from '@angular/common/http';
import { Injectable, inject, signal } from '@angular/core';
import { firstValueFrom } from 'rxjs';
import { Offline, toFailure } from './api';
import { API_BASE_URL } from './config';
import { KEY_OF, PUSH_ORDER, type SyncTable } from './models';
import { Session } from './session';
import { Store } from './store';

interface PullResponse {
  table: string;
  rows: Record<string, unknown>[];
  cursor: number;
  has_more: boolean;
}

interface PushResponse {
  applied: number;
  skipped_stale: number;
  high_water: number;
  assigned: Record<string, number>;
}

export type SyncPhase = 'idle' | 'syncing' | 'offline' | 'failed';

/**
 * A metade cliente de §6, na web.
 *
 * O servidor não expõe REST de baralhos e cards: a API pública de conteúdo
 * **é** o protocolo de sync. Então a web fala o mesmo protocolo que o
 * aplicativo, o que também é o que faz as duas superfícies concordarem sobre
 * conflito — mesma ordem de envio, mesma regra de último-a-escrever.
 *
 * A diferença em relação ao telefone é deliberada: lá o SQLite local é a
 * verdade e o servidor é backup. Aqui não há banco local, e o `Store` é um
 * espelho em memória do que o servidor mandou. §5.14 vale igual — ficar
 * offline não é erro; o que muda é que a web, sem persistência, perde o
 * espelho ao recarregar e simplesmente puxa de novo.
 */
@Injectable({ providedIn: 'root' })
export class Sync {
  private readonly http = inject(HttpClient);
  private readonly baseUrl = inject(API_BASE_URL);
  private readonly session = inject(Session);
  private readonly store = inject(Store);

  readonly phase = signal<SyncPhase>('idle');
  readonly lastSuccess = signal<Date | null>(null);
  readonly message = signal<string | null>(null);

  private running: Promise<void> | null = null;

  /**
   * Junta chamadas simultâneas numa só.
   *
   * Duas sincronias ao mesmo tempo enviariam o mesmo outbox duas vezes; a
   * segunda não corrompe nada (§6.4 é idempotente), mas gasta rede e embaralha
   * o estado que a interface mostra.
   */
  syncNow(): Promise<void> {
    return (this.running ??= this.run().finally(() => {
      this.running = null;
    }));
  }

  private async run(): Promise<void> {
    if (!this.session.signedIn()) return;

    this.phase.set('syncing');
    try {
      // Enviar antes de puxar, para um aparelho que ficou fora não receber as
      // próprias edições de volta como se fossem de outro (§6.4).
      await this.pushAll();
      await this.pullAll();
      this.phase.set('idle');
      this.lastSuccess.set(new Date());
      this.message.set(null);
    } catch (e) {
      const failure = toFailure(e);
      if (failure instanceof Offline) {
        // Corriqueiro num trem. Nada se perdeu: o outbox está onde estava.
        this.phase.set('offline');
        this.message.set(null);
        return;
      }
      this.phase.set(failure.isTransient ? 'offline' : 'failed');
      this.message.set(failure.code ?? failure.detail);
    }
  }

  private async pushAll(): Promise<void> {
    for (const table of PUSH_ORDER) {
      const pending = this.store.outbox(table);
      if (pending.length === 0) continue;

      const response = await firstValueFrom(
        this.http.post<PushResponse>(`${this.baseUrl}/v1/sync/push`, {
          table,
          rows: pending,
          // Derivada do conteúdo: uma retentativa depois de timeout carrega a
          // mesma chave e o servidor pode reconhecê-la (§6.4).
          idempotency_key: `${table}:${pending.map((r) => r[KEY_OF[table]]).join(',')}`,
        }),
      );
      this.store.acknowledge(table, response.assigned);
    }
  }

  private async pullAll(): Promise<void> {
    for (const table of PUSH_ORDER) {
      // Uma página grande e um laço: um baralho de milhares de cards não cabe
      // numa resposta, e parar na primeira página deixaria a biblioteca
      // silenciosamente incompleta.
      for (;;) {
        const since = this.store.cursor(table);
        const page = await firstValueFrom(
          this.http.get<PullResponse>(`${this.baseUrl}/v1/sync/pull`, {
            params: { table, since, limit: 500 },
          }),
        );
        if (page.rows.length === 0) break;
        this.store.apply(table as SyncTable, page.rows, page.cursor);
        if (!page.has_more) break;
      }
    }
  }
}
