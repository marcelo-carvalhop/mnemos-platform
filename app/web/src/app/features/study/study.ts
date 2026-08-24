import {
  ChangeDetectionStrategy,
  Component,
  computed,
  inject,
  signal,
  type OnDestroy,
} from '@angular/core';
import { Router, RouterLink } from '@angular/router';
import { GRADES_IN_ORDER, GRADE_LABELS, type Grade } from '../../core/contract.g';
import { Store } from '../../core/store';
import { Sync } from '../../core/sync';
import { preview } from '../../core/scheduler';
import { IntervalPipe } from '../../shared/interval-pipe';

/**
 * A sessão de estudo (§5.8).
 *
 * É aqui que a web ganha do telefone: no celular a resposta é um toque, e cada
 * toque exige mirar. Com teclado a decisão é uma tecla — **espaço** vira o
 * card, **1 a 4** graduam — e a mão nem sai do lugar. Por isso a tela é
 * centralizada e estreita mesmo num monitor largo: ler a pergunta é a tarefa,
 * e nada mais deve competir por atenção.
 *
 * §5.8.3 — cada grau mostra o intervalo que produz **antes** de ser escolhido.
 * A prévia vem de `preview`, que é derivada de `apply`: ela não pode mentir
 * porque é literalmente o mesmo cálculo.
 */
@Component({
  selector: 'app-study',
  changeDetection: ChangeDetectionStrategy.OnPush,
  imports: [RouterLink, IntervalPipe],
  styleUrl: './study.css',
  host: { '(document:keydown)': 'onKey($event)' },
  template: `
    @if (card(); as current) {
      <header class="bar">
        <a class="leave" routerLink="/hoje">Sair</a>
        <p class="mn-mono progress">{{ done() }} de {{ total() }}</p>
        <div class="track" aria-hidden="true">
          <span [style.width.%]="total() ? (done() / total()) * 100 : 0"></span>
        </div>
      </header>

      <article class="card" [attr.aria-live]="'polite'">
        <p class="front">{{ current.front }}</p>

        @if (revealed()) {
          <hr />
          <p class="back">{{ current.back }}</p>
          @if (current.tags.length > 0) {
            <ul class="tags">
              @for (tag of current.tags; track tag) {
                <li class="mn-mono">{{ tag }}</li>
              }
            </ul>
          }
        }
      </article>

      @if (!revealed()) {
        <button class="reveal" type="button" (click)="reveal()">
          Ver a resposta
          <kbd class="mn-mono">espaço</kbd>
        </button>
      } @else {
        <div class="grades" role="group" aria-label="Como foi">
          @for (grade of grades; track grade) {
            <button
              type="button"
              [class]="'grade g' + grade"
              (click)="answer(grade)"
              [attr.aria-label]="labels[grade] + ', volta em ' + (intervals()[grade] | interval)"
            >
              <kbd class="mn-mono">{{ grade }}</kbd>
              <span class="name">{{ labels[grade] }}</span>
              <!-- §5.8.3: o intervalo aparece antes da escolha, não depois. -->
              <span class="when mn-mono">{{ intervals()[grade] | interval }}</span>
            </button>
          }
        </div>
      }
    } @else {
      <section class="finished">
        <h1>{{ answered() > 0 ? 'Sessão concluída' : 'Nada vencendo agora' }}</h1>
        @if (answered() > 0) {
          <p>
            {{ answered() }} {{ answered() === 1 ? 'card revisto' : 'cards revistos' }}. O próximo
            volta quando estiver perto de ser esquecido.
          </p>
        } @else {
          <p>Sua memória segue trabalhando sozinha.</p>
        }
        <a class="leave-primary" routerLink="/hoje">Voltar para Hoje</a>
      </section>
    }
  `,
})
export class Study implements OnDestroy {
  private readonly store = inject(Store);
  private readonly sync = inject(Sync);
  private readonly router = inject(Router);

  protected readonly grades = GRADES_IN_ORDER;
  protected readonly labels = GRADE_LABELS;

  protected readonly revealed = signal(false);
  protected readonly answered = signal(0);

  /**
   * A fila é congelada ao abrir a tela.
   *
   * `store.due()` é reativo: gradar um card o tira da lista na hora, e a fila
   * encolheria embaixo da pessoa enquanto ela estuda — o contador iria de "12"
   * para "11 de 11" a cada resposta. Congelar dá uma sessão com começo e fim.
   */
  private readonly queue = signal<string[]>(this.store.due().map((c) => c.id));
  private readonly index = signal(0);

  /** Quando a resposta apareceu, para medir o tempo até a decisão (§5.2). */
  private revealedAt: number | null = null;

  protected readonly total = computed(() => this.queue().length);
  protected readonly done = computed(() => this.index());

  protected readonly card = computed(() => {
    const id = this.queue()[this.index()];
    return id ? (this.store.liveCards().find((c) => c.id === id) ?? null) : null;
  });

  protected readonly intervals = computed(() => {
    const current = this.card();
    if (!current) return {} as Record<Grade, number>;
    const state = this.store.states().get(current.id);
    if (!state) return {} as Record<Grade, number>;
    return preview(state, this.store.now(), this.store.fsrsParams());
  });

  protected reveal(): void {
    if (this.revealed()) return;
    this.revealed.set(true);
    this.revealedAt = Date.now();
  }

  protected answer(grade: Grade): void {
    const current = this.card();
    if (!current || !this.revealed()) return;

    const elapsed = this.revealedAt === null ? null : Date.now() - this.revealedAt;
    this.store.recordReview(current.id, grade, elapsed);

    this.revealed.set(false);
    this.revealedAt = null;
    this.answered.update((n) => n + 1);
    this.index.update((i) => i + 1);

    // Enviar ao fim, não a cada card: uma requisição por resposta transformaria
    // vinte decisões em vinte esperas, e o outbox já garante que nada se perde
    // se a aba fechar antes.
    if (this.index() >= this.queue().length) void this.sync.syncNow();
  }

  /**
   * O teclado é a interface principal desta tela.
   *
   * `Escape` sai, espaço revela, 1–4 graduam. Teclas só valem quando o foco não
   * está num campo de texto — caso contrário digitar "3" numa busca graduaria
   * um card sem ninguém pedir.
   */
  protected onKey(event: KeyboardEvent): void {
    if (isTyping(event.target)) return;

    if (event.key === 'Escape') {
      event.preventDefault();
      void this.router.navigate(['/hoje']);
      return;
    }

    if (event.key === ' ' || event.key === 'Enter') {
      event.preventDefault();
      if (!this.revealed()) this.reveal();
      return;
    }

    const grade = Number(event.key);
    if (this.revealed() && GRADES_IN_ORDER.includes(grade as Grade)) {
      event.preventDefault();
      this.answer(grade as Grade);
    }
  }

  ngOnDestroy(): void {
    // Sair no meio não perde o que já foi respondido: as revisões estão no
    // outbox, e §3 diz que elas são a verdade.
    if (this.answered() > 0) void this.sync.syncNow();
  }
}

function isTyping(target: EventTarget | null): boolean {
  if (!(target instanceof HTMLElement)) return false;
  return (
    target.isContentEditable ||
    target instanceof HTMLInputElement ||
    target instanceof HTMLTextAreaElement
  );
}
