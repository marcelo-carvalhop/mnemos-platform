import {
  ChangeDetectionStrategy,
  Component,
  computed,
  inject,
  input,
  signal,
  type OnInit,
} from '@angular/core';
import { Router } from '@angular/router';
import { failureForError, type GenerationFailure } from '../../core/error-copy';
import { Generation, type PendingCard } from '../../core/generation';
import { Sync } from '../../core/sync';

/**
 * A fila de aprovação (§7.8).
 *
 * Nada gerado vira card sem alguém dizer sim, um por vez. No aplicativo isso é
 * uma pilha arrastável, porque o polegar decide melhor por gesto. Aqui a
 * decisão é uma tecla — **A** aprova, **D** descarta, **Z** desfaz — e o card
 * fica grande e centralizado pela mesma razão da tela de estudo: julgar a
 * qualidade de um card exige lê-lo.
 *
 * "Aprovar restantes" existe e fica longe do caminho: é útil quando a geração
 * saiu boa, e é exatamente o botão que se aperta sem ler quando ele fica perto
 * demais.
 */
@Component({
  selector: 'app-approval',
  changeDetection: ChangeDetectionStrategy.OnPush,
  styleUrl: './approval.css',
  host: { '(document:keydown)': 'onKey($event)' },
  template: `
    @if (failure(); as problem) {
      <section class="failed">
        <h1>{{ problem.title }}</h1>
        <p>{{ problem.detail }}</p>
      </section>
    } @else if (loading()) {
      <p class="loading">Carregando a fila…</p>
    } @else {
      <header class="bar">
        <p class="mn-mono">{{ decided().length }} de {{ total() }}</p>
        @if (decided().length > 0) {
          <button class="undo" type="button" [disabled]="busy()" (click)="undo()">
            Desfazer <kbd class="mn-mono">Z</kbd>
          </button>
        }
      </header>

      @if (current(); as card) {
        <article class="card">
          <p class="front">{{ card.front }}</p>
          <hr />
          <p class="back">{{ card.back }}</p>
          @if (card.tags.length > 0) {
            <ul class="tags">
              @for (tag of card.tags; track tag) {
                <li class="mn-mono">{{ tag }}</li>
              }
            </ul>
          }
        </article>

        <div class="actions">
          <button class="discard" type="button" [disabled]="busy()" (click)="decide('discarded')">
            Descartar <kbd class="mn-mono">D</kbd>
          </button>
          <button class="approve" type="button" [disabled]="busy()" (click)="decide('approved')">
            Aprovar <kbd class="mn-mono">A</kbd>
          </button>
        </div>

        <button class="rest" type="button" [disabled]="busy()" (click)="finish(true)">
          Aprovar os {{ pending().length }} restantes
        </button>
      } @else {
        <section class="judged">
          @if (total() === 0) {
            <!-- Uma fila que chegou vazia não é uma fila terminada: aprovados
                 igual a total é verdadeiro com zero e zero. -->
            <h1>Nenhum card chegou</h1>
            <p>Esta geração não produziu nada para aprovar. Sua geração não foi gasta.</p>
          } @else {
            <h1>
              {{
                approved() === total()
                  ? 'Você aprovou todos'
                  : approved() + ' de ' + total() + ' aprovados'
              }}
            </h1>
            <p>Eles entram no baralho quando você criar.</p>
          }

          @if (approved() > 0) {
            <button class="primary" type="button" [disabled]="busy()" (click)="finish(false)">
              Criar {{ approved() }} {{ approved() === 1 ? 'card' : 'cards' }}
            </button>
          } @else {
            <!-- Sem nada aprovado não há o que criar. Um botão morto deixaria a
                 tela sem saída nenhuma. -->
            <button class="secondary" type="button" (click)="leave()">Voltar</button>
          }
        </section>
      }
    }
  `,
})
export class Approval implements OnInit {
  private readonly generation = inject(Generation);
  private readonly sync = inject(Sync);
  private readonly router = inject(Router);

  readonly jobId = input.required<string>();

  protected readonly pending = signal<PendingCard[]>([]);
  protected readonly decided = signal<{ card: PendingCard; decision: string }[]>([]);
  protected readonly loading = signal(true);
  protected readonly busy = signal(false);
  protected readonly failure = signal<GenerationFailure | null>(null);

  protected readonly current = computed(() => this.pending()[0] ?? null);
  protected readonly total = computed(() => this.pending().length + this.decided().length);
  protected readonly approved = computed(
    () => this.decided().filter((d) => d.decision === 'approved').length,
  );

  /**
   * `ngOnInit` e não o construtor: um `input.required` só existe depois de o
   * roteador (ou o teste) preencher os inputs, e lê-lo antes disso lança — o
   * que a tela mostrava como "algo deu errado", sem nada a ver com o servidor.
   */
  ngOnInit(): void {
    void this.load();
  }

  private async load(): Promise<void> {
    try {
      const queue = await this.generation.queue(this.jobId());
      // Já decididos ficam fora da fila mas contam no total: sair no meio e
      // voltar tem de retomar de onde parou (§7.8).
      this.pending.set(queue.cards.filter((c) => c.decision === null));
      this.decided.set(
        queue.cards
          .filter((c) => c.decision !== null)
          .map((c) => ({ card: c, decision: c.decision as string })),
      );
    } catch (e) {
      this.failure.set(failureForError(e));
    } finally {
      this.loading.set(false);
    }
  }

  protected async decide(decision: 'approved' | 'discarded'): Promise<void> {
    const card = this.current();
    if (!card || this.busy()) return;

    // Otimista: o julgamento é da pessoa, e esperar a rede entre um card e o
    // seguinte transformaria vinte decisões em vinte esperas.
    this.pending.update((rows) => rows.slice(1));
    this.decided.update((rows) => [...rows, { card, decision }]);

    try {
      await this.generation.decide(card.id, decision);
    } catch {
      this.pending.update((rows) => [card, ...rows]);
      this.decided.update((rows) => rows.slice(0, -1));
    }
  }

  protected async undo(): Promise<void> {
    const last = this.decided().at(-1);
    if (!last || this.busy()) return;

    this.decided.update((rows) => rows.slice(0, -1));
    this.pending.update((rows) => [last.card, ...rows]);

    try {
      // §5.7 — nulo é a decisão de "des-decidir", que o servidor modela de
      // propósito, e não um campo ausente.
      await this.generation.decide(last.card.id, null);
    } catch {
      this.pending.update((rows) => rows.slice(1));
      this.decided.update((rows) => [...rows, last]);
    }
  }

  protected async finish(approveRest: boolean): Promise<void> {
    this.busy.set(true);
    try {
      if (approveRest) await this.generation.approveRemaining(this.jobId());
      await this.generation.close(this.jobId());
      // Os cards nascem no servidor; puxar é como eles chegam aqui.
      await this.sync.syncNow();
      await this.router.navigate(['/biblioteca']);
    } catch (e) {
      this.busy.set(false);
      this.failure.set(failureForError(e));
    }
  }

  protected async leave(): Promise<void> {
    await this.router.navigate(['/hoje']);
  }

  protected onKey(event: KeyboardEvent): void {
    if (event.target instanceof HTMLInputElement || event.target instanceof HTMLTextAreaElement) {
      return;
    }
    const key = event.key.toLowerCase();
    if (key === 'a') {
      event.preventDefault();
      void this.decide('approved');
    } else if (key === 'd') {
      event.preventDefault();
      void this.decide('discarded');
    } else if (key === 'z') {
      event.preventDefault();
      void this.undo();
    }
  }
}
