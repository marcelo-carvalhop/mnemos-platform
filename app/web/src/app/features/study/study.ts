import {
  ChangeDetectionStrategy,
  Component,
  computed,
  effect,
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
        <div class="left">
          <a class="leave" routerLink="/hoje" aria-label="Sair da sessão">✕</a>
          <span class="deck">{{ deckName(current.deck_id) }}</span>
        </div>

        <div class="middle">
          <!-- Um segmento por card da sessão, não uma barra contínua: a
               pessoa vê quantos faltam e como foram os que já passaram. -->
          <div class="ruler" aria-hidden="true">
            @for (i of segments(); track i) {
              <span
                [class.right]="i < correct()"
                [class.wrong]="i >= correct() && i < done()"
                [class.now]="i === done()"
              ></span>
            }
          </div>
          <!-- Sans e caixa mista: eram quatro tratamentos de tipo numa faixa
               de 40 px — o nome do baralho em sans, a régua, o contador e os
               acertos em mono caixa alta, e o atalho em mono mais claro. Só o
               número fica em mono, que é onde o avanço fixo serve para
               alguma coisa. -->
          <p class="counts">
            <span class="mn-mono">{{ done() + 1 }}</span> de
            <span class="mn-mono">{{ total() }}</span>
            <span class="split">·</span>
            {{ correct() }} certos, {{ done() - correct() }} errados
          </p>
        </div>

        <!-- O atalho sai da faixa: ele já aparece dentro do próprio botão. -->
      </header>

      <article class="card" [attr.aria-live]="'polite'">
        <p class="eyebrow mn-mono">Pergunta</p>
        <p class="front">{{ current.front }}</p>

        @if (revealed()) {
          <hr />
          <p class="eyebrow mn-mono">Resposta</p>
          <p class="back">{{ current.back }}</p>
          <div class="foot">
            @if (current.tags.length > 0) {
              <ul class="tags">
                @for (tag of current.tags; track tag) {
                  <li class="mn-mono">{{ tag }}</li>
                }
              </ul>
            } @else {
              <span></span>
            }
            <span class="seen">{{ seen(current.id) }}</span>
          </div>
        }
      </article>

      @if (!revealed()) {
        <button class="reveal" type="button" (click)="reveal()">
          Ver a resposta
          <kbd class="mn-mono">espaço</kbd>
        </button>
      } @else {
        <p class="eyebrow mn-mono centred">Como foi?</p>
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
    } @else if (loading()) {
      <p class="loading">Carregando sua fila…</p>
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

  /** Quantos a pessoa acertou nesta sessão — "errei" é o único erro. */
  protected readonly correct = signal(0);

  /** Um índice por card da sessão, para desenhar a régua. */
  protected readonly segments = computed(() => Array.from({ length: this.total() }, (_, i) => i));

  protected deckName(deckId: string): string {
    return this.store.liveDecks().find((d) => d.id === deckId)?.name ?? 'Sessão';
  }

  /** "Visto há 6 dias · intervalo 6 d" — o contexto da pergunta. */
  protected seen(cardId: string): string {
    const state = this.store.states().get(cardId);
    if (!state?.lastReviewAt) return 'Primeira vez que você vê este card';
    const days = Math.round((Date.now() - state.lastReviewAt.getTime()) / 86_400_000);
    const gap =
      state.dueAt && state.lastReviewAt
        ? Math.round((state.dueAt.getTime() - state.lastReviewAt.getTime()) / 86_400_000)
        : null;
    const when = days <= 0 ? 'hoje' : days === 1 ? 'ontem' : `há ${days} dias`;
    return gap === null ? `Visto ${when}` : `Visto ${when} · intervalo ${gap} d`;
  }

  /**
   * A fila é congelada — mas só quando existe algo para congelar.
   *
   * `store.due()` é reativo: gradar um card o tira da lista na hora, e a fila
   * encolheria embaixo da pessoa enquanto ela estuda — o contador iria de "12"
   * para "11 de 11" a cada resposta. Congelar dá uma sessão com começo e fim.
   *
   * Congelar **no construtor** era errado e apareceu na primeira vez que abri
   * `/estudar` direto pela URL: nesse caminho o componente nasce antes de a
   * primeira sincronia terminar, a fila congela vazia, e a tela diz "nada
   * vencendo" enquanto Hoje mostra oito. Um link salvo, um F5 no meio da
   * sessão — qualquer entrada que não venha de Hoje caía nisso.
   *
   * O congelamento espera a sincronia **terminar**, e não apenas aparecer o
   * primeiro card. `reviews` é a última tabela do pull (§6.4: o histórico
   * aponta para cards), então existe uma janela em que os cards já chegaram e o
   * histórico não — nela todo card parece novo e todo card parece vencido.
   * Congelar aí deu uma sessão de 12 cards enquanto a barra lateral dizia 8, e
   * os quatro que sobravam já tinham sido respondidos.
   */
  private readonly queue = signal<string[] | null>(null);
  private readonly index = signal(0);

  /** Quando a resposta apareceu, para medir o tempo até a decisão (§5.2). */
  private revealedAt: number | null = null;

  constructor() {
    effect(() => {
      if (this.queue() !== null) return;
      if (this.sync.phase() === 'syncing') return;
      this.queue.set(this.store.due().map((c) => c.id));
    });
  }

  /** Nulo enquanto a fila ainda não foi congelada: ainda estamos carregando. */
  protected readonly loading = computed(() => this.queue() === null);

  protected readonly total = computed(() => this.queue()?.length ?? 0);
  protected readonly done = computed(() => this.index());

  protected readonly card = computed(() => {
    const id = this.queue()?.[this.index()];
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
    if (grade > 1) this.correct.update((n) => n + 1);
    this.index.update((i) => i + 1);

    // Enviar ao fim, não a cada card: uma requisição por resposta transformaria
    // vinte decisões em vinte esperas, e o outbox já garante que nada se perde
    // se a aba fechar antes.
    if (this.index() >= this.total()) void this.sync.syncNow();
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
