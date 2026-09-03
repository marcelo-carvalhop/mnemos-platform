import { ChangeDetectionStrategy, Component, computed, inject, signal } from '@angular/core';
import { GRADES_IN_ORDER, GRADE_LABELS, MATURE_INTERVAL_DAYS } from '../../core/contract.g';
import { Store, dayStart } from '../../core/store';

/**
 * Progresso (§5.11).
 *
 * Uma métrica só carrega a tela: memória acumulada. Tudo aqui vem do log de
 * revisões — §3 diz que ele é a verdade, e um número que não sai dele é um
 * número inventado.
 *
 * Nada de sequência de dias. Uma métrica que pune quem viajou uma semana
 * transforma o produto em obrigação, e o que o Mnemos promete é conhecimento
 * guardado, não presença.
 */
@Component({
  selector: 'app-progress',
  changeDetection: ChangeDetectionStrategy.OnPush,
  styleUrl: './progress.css',
  template: `
    <header class="head">
      <h1>Progresso</h1>
      <div class="chips" role="group" aria-label="Período">
        @for (option of windows; track option.days) {
          <button type="button" [class.on]="window() === option.days" (click)="window.set(option.days)">
            {{ option.label }}
          </button>
        }
      </div>
    </header>

    <section class="cards">
      <!-- O bloco-âncora: a métrica que o produto promete, antes das que só
           descrevem esforço. -->
      <article class="anchor">
        <p class="eyebrow mn-mono">Memória acumulada</p>
        <p class="figure">
          <span class="n">{{ store.accumulatedMemoryDays().toLocaleString('pt-BR') }}</span>
          <span class="unit">dias</span>
        </p>
        <p class="note">Soma do intervalo atual de cada card.</p>
      </article>
      <article>
        <p class="n">{{ store.liveCards().length.toLocaleString('pt-BR') }}</p>
        <p class="label">cards vivos</p>
      </article>
      <article>
        <p class="n">{{ store.matureCount().toLocaleString('pt-BR') }}</p>
        <!-- §4 — maduro é o corte de 21 dias, um predicado de consulta. -->
        <p class="label">maduros (≥ {{ matureDays }} dias)</p>
      </article>
      <article>
        <p class="n good">{{ retention() }}%</p>
        <p class="label">acertos em {{ window() }} dias</p>
      </article>
    </section>

    <div class="split">
      <section aria-label="Revisões por dia">
        <div class="section-head">
          <h2>Revisões por dia</h2>
          <span class="eyebrow mn-mono">Últimos {{ window() }} dias</span>
        </div>
      @if (byDay().every((d) => d.count === 0)) {
        <p class="empty">Sem revisões neste período.</p>
      } @else {
        <!-- Uma linha de grade rotulada com o pico: sem referência de altura,
             trinta barras e duas datas não dizem se o dia mais alto foram
             oito revisões ou oitenta. Os gráficos de Saúde e de Tempo de Uso
             sempre trazem linha de base e ao menos um valor. -->
        <div class="plot">
          <span class="grid" aria-hidden="true"></span>
          <span class="grid-label mn-mono" aria-hidden="true">{{ peak() }}</span>
          <ol class="chart">
            @for (day of byDay(); track day.iso) {
              <li>
                <span
                  class="bar"
                  [class.empty]="day.count === 0"
                  [style.height.%]="peak() ? (day.count / peak()) * 100 : 0"
                  [attr.title]="day.count + ' em ' + day.label"
                ></span>
              </li>
            }
          </ol>
        </div>
        <p class="axis mn-mono">
          <span>{{ byDay()[0].label }}</span>
          <span>hoje</span>
        </p>
      }
      </section>

      <section aria-label="Distribuição dos graus">
        <h2>Como você respondeu</h2>
      @if (store.reviews().length === 0) {
        <p class="empty">Ainda não há revisões para distribuir.</p>
      } @else {
        <ul class="grades">
          @for (grade of grades; track grade) {
            <li>
              <span class="name">{{ labels[grade] }}</span>
              <span class="track" aria-hidden="true">
                <span [class]="'fill g' + grade" [style.width.%]="share(grade)"></span>
              </span>
              <span class="pct mn-mono">{{ share(grade) }}%</span>
            </li>
          }
        </ul>
      }

        <h2 class="spaced">Maturidade por baralho</h2>
        @if (store.liveDecks().length === 0) {
          <p class="empty">Nenhum baralho ainda.</p>
        } @else {
          <ul class="maturity">
            @for (deck of store.liveDecks(); track deck.id) {
              <li>
                <span class="row">
                  <span>{{ deck.name }}</span>
                  <span class="mn-mono">{{ store.matureCount(deck.id) }}/{{ store.cardsOfDeck(deck.id).length }}</span>
                </span>
                <span class="track" aria-hidden="true">
                  <span class="fill" [style.width.%]="maturityOf(deck.id)"></span>
                </span>
              </li>
            }
          </ul>
        }
      </section>
    </div>
  `,
})
export class Progress {
  protected readonly store = inject(Store);
  protected readonly grades = GRADES_IN_ORDER;
  protected readonly labels = GRADE_LABELS;
  protected readonly matureDays = MATURE_INTERVAL_DAYS;

  /** A janela do gráfico e da retenção — o canvas oferece três. */
  protected readonly window = signal(30);
  protected readonly windows = [
    { days: 30, label: '30 dias' },
    { days: 90, label: '90 dias' },
    { days: 3650, label: 'Tudo' },
  ];

  protected maturityOf(deckId: string): number {
    const total = this.store.cardsOfDeck(deckId).length;
    return total === 0 ? 0 : (this.store.matureCount(deckId) / total) * 100;
  }

  private readonly recent = computed(() => {
    const since = new Date(this.store.now().getTime() - this.window() * 86_400_000);
    return this.store.reviews().filter((r) => new Date(r.reviewed_at) >= since);
  });

  /**
   * "Acertos" e não "retenção": retenção tem um significado técnico em FSRS —
   * a probabilidade-alvo de lembrar — e usar a mesma palavra para a taxa
   * observada faria dois números diferentes disputarem o mesmo nome.
   */
  protected readonly retention = computed(() => {
    const rows = this.recent();
    if (rows.length === 0) return 0;
    const right = rows.filter((r) => r.grade > 1).length;
    return Math.round((right / rows.length) * 100);
  });

  protected readonly byDay = computed(() => {
    const today = dayStart(this.store.now());
    const buckets: { iso: string; label: string; count: number }[] = [];

    for (let i = Math.min(this.window(), 60) - 1; i >= 0; i--) {
      const start = new Date(today.getTime() - i * 86_400_000);
      buckets.push({
        iso: start.toISOString(),
        label: start.toLocaleDateString('pt-BR', { day: '2-digit', month: 'short' }),
        count: 0,
      });
    }

    // Um índice por ISO em vez de varrer os trinta baldes por revisão: com
    // anos de histórico a varredura seria o dobro de trabalho por nada.
    const slot = new Map(buckets.map((b, i) => [b.iso, i]));
    for (const review of this.recent()) {
      // §5.7 — a revisão cai no dia de estudo em que aconteceu, e o dia vira
      // às 04:00. Uma revisão à 01:00 pertence ao dia anterior.
      const index = slot.get(dayStart(new Date(review.reviewed_at)).toISOString());
      if (index !== undefined) buckets[index].count += 1;
    }
    return buckets;
  });

  protected readonly peak = computed(() => Math.max(...this.byDay().map((d) => d.count), 0));

  protected share(grade: number): number {
    const rows = this.store.reviews();
    if (rows.length === 0) return 0;
    return Math.round((rows.filter((r) => r.grade === grade).length / rows.length) * 100);
  }
}
