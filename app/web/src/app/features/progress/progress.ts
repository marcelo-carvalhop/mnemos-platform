import { ChangeDetectionStrategy, Component, computed, inject } from '@angular/core';
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
    <h1>Progresso</h1>

    <section class="headline">
      <p class="label">Memória acumulada</p>
      <p class="big">{{ store.accumulatedMemoryDays().toLocaleString('pt-BR') }} dias</p>
      <p class="label">somando o intervalo atual de cada card</p>
    </section>

    <section class="cards">
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
        <p class="n">{{ store.reviews().length.toLocaleString('pt-BR') }}</p>
        <p class="label">revisões no histórico</p>
      </article>
      <article>
        <p class="n">{{ retention() }}%</p>
        <p class="label">acertos nos últimos 30 dias</p>
      </article>
    </section>

    <section aria-label="Revisões por dia">
      <h2>Últimos 30 dias</h2>
      @if (byDay().every((d) => d.count === 0)) {
        <p class="empty">Sem revisões neste período.</p>
      } @else {
        <ol class="chart">
          @for (day of byDay(); track day.iso) {
            <li>
              <span
                class="bar"
                [style.height.%]="peak() ? (day.count / peak()) * 100 : 0"
                [attr.title]="day.count + ' em ' + day.label"
              ></span>
            </li>
          }
        </ol>
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
    </section>
  `,
})
export class Progress {
  protected readonly store = inject(Store);
  protected readonly grades = GRADES_IN_ORDER;
  protected readonly labels = GRADE_LABELS;
  protected readonly matureDays = MATURE_INTERVAL_DAYS;

  private readonly recent = computed(() => {
    const since = new Date(this.store.now().getTime() - 30 * 86_400_000);
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

    for (let i = 29; i >= 0; i--) {
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
