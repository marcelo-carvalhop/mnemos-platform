import { DestroyRef, Injectable, computed, inject, signal } from '@angular/core';
import { Generation, type OpenGeneration } from './generation';

/**
 * As gerações que o servidor ainda deve (§7.8), num lugar só.
 *
 * A barra lateral, o cabeçalho do celular e o aviso de Hoje leem daqui, e
 * por isso dizem a mesma coisa ao mesmo tempo. A lista é pedida de novo a
 * cada troca de tela e, enquanto alguma geração ainda roda, a cada 15 s —
 * é o que faz o atalho virar de "Gerando…" para "12 para aprovar" sem
 * recarregar a página.
 */
@Injectable({ providedIn: 'root' })
export class PendingGenerations {
  private readonly generation = inject(Generation);

  readonly jobs = signal<OpenGeneration[]>([]);

  /** Cards esperando um sim ou não, somados entre as gerações. */
  readonly pending = computed(() => this.jobs().reduce((sum, j) => sum + j.pending, 0));
  readonly running = computed(() => this.jobs().some((j) => j.pending === 0));

  /** Para onde o atalho leva: a aprovação, se houver; senão o progresso. */
  readonly target = computed(() => {
    const jobs = this.jobs();
    const waiting = jobs.find((j) => j.pending > 0);
    if (waiting) return ['/aprovar', waiting.id];
    return jobs[0] ? ['/gerar', jobs[0].id] : null;
  });

  private timer: ReturnType<typeof setInterval> | null = null;

  constructor() {
    inject(DestroyRef).onDestroy(() => this.stop());
  }

  async refresh(): Promise<void> {
    try {
      this.jobs.set(await this.generation.open());
    } catch {
      // Offline não é erro; o atalho simplesmente não aparece.
      this.jobs.set([]);
    }
    if (this.running()) this.start();
    else this.stop();
  }

  private start(): void {
    if (this.timer !== null) return;
    this.timer = setInterval(() => void this.refresh(), 15_000);
  }

  private stop(): void {
    if (this.timer === null) return;
    clearInterval(this.timer);
    this.timer = null;
  }
}
