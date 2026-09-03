import { ChangeDetectionStrategy, Component, computed, inject } from '@angular/core';
import { RouterLink } from '@angular/router';
import { Store } from '../../core/store';
import { Sync } from '../../core/sync';
import { OpenGenerations } from '../create/open-generations';

/**
 * Hoje — a tela onde o estudo mora (§5.2).
 *
 * §design — "cada tela abre com um bloco-âncora em vez de um vazio
 * centralizado; e a largura do conteúdo passa a ser usada em duas colunas". O
 * bloco-âncora responde a única pergunta que faz alguém abrir o Mnemos: o que
 * vence agora. O resto da tela é contexto para essa resposta, não competição
 * com ela.
 *
 * A manchete secundária é a memória acumulada, não o número de cards. §2.3:
 * quantos cards alguém tem mede o quanto digitou; quanto tempo o conhecimento
 * fica de pé mede o que o produto promete.
 */
@Component({
  selector: 'app-today',
  changeDetection: ChangeDetectionStrategy.OnPush,
  imports: [RouterLink, OpenGenerations],
  styleUrl: './today.css',
  template: `
    <app-open-generations />

    <header class="head">
      <div>
        <p class="eyebrow mn-mono">{{ today() }}</p>
        <h1>Hoje</h1>
      </div>
      @if (due().length > 0) {
        <a class="primary" routerLink="/estudar">
          Estudar agora
          <kbd class="mn-mono">espaço</kbd>
        </a>
      }
    </header>

    <div class="split">
      <!-- O bloco-âncora. Existe em todos os três estados: com fila, sem fila
           e sem cards. Um vazio centralizado no lugar dele deixaria a tela sem
           dizer nada no dia em que não há o que fazer. -->
      <section class="anchor" aria-label="O que vence agora">
        @if (due().length > 0) {
          <p class="eyebrow mn-mono">Vencendo agora</p>
          <p class="figure">
            <span class="n">{{ due().length }}</span>
            <span class="unit">cards em {{ plural(byDeck().length, 'baralho', 'baralhos') }}</span>
          </p>
          <div class="split-bar" aria-hidden="true">
            @for (row of byDeck(); track row.deck.id) {
              <span [style.flex]="row.count" [class.second]="!$first"></span>
            }
          </div>
          <p class="legend">
            @for (row of byDeck(); track row.deck.id) {
              <span>{{ row.deck.name }} {{ row.count }}</span>
            }
          </p>
        } @else if (hasCards()) {
          <p class="eyebrow mn-mono">Nada vencendo</p>
          <p class="figure"><span class="n">0</span><span class="unit">cards para hoje</span></p>
          <p class="prose">
            Sua memória segue trabalhando sozinha. Voltamos a te chamar quando algo estiver
            prestes a escapar.
          </p>
        } @else {
          <p class="eyebrow mn-mono">Comece por aqui</p>
          <p class="figure"><span class="n">0</span><span class="unit">cards ainda</span></p>
          <p class="prose">
            Diga o que você quer aprender e a IA escreve os cards. Você aprova um por um antes de
            qualquer coisa virar baralho.
          </p>
          <a class="onDark" routerLink="/criar">Criar com IA</a>
        }
      </section>

      <div class="stack">
        <section class="tile pair" aria-label="Memória e retenção">
          <!-- A cor do numeral segue a métrica, não a tela: memória acumulada
               é lavanda e retenção é menta **em toda superfície**. Antes eram
               quatro telas com quatro critérios — o mesmo "98%" saía lavanda
               aqui e menta em Progresso. Saúde e Fitness pintam o número com a
               cor da categoria, sempre a mesma para a mesma medida. -->
          <div>
            <p class="eyebrow mn-mono">Memória acumulada</p>
            <p class="figure small accent"><span class="n">{{ memory() }}</span></p>
          </div>
          <div class="right">
            <p class="eyebrow mn-mono">Retenção 90 d</p>
            <p class="figure small settled"><span class="n">{{ retention() }}</span></p>
          </div>
        </section>

        <section class="tile" aria-label="Sequência">
          <p class="eyebrow mn-mono">Meta de hoje · {{ store.studiedToday() }} de {{ store.dailyGoal() }}</p>
          <div class="week">
            @for (day of week(); track day.label) {
              <div>
                <span class="bar" [class.met]="day.met" [class.today]="day.today"></span>
                <span class="mn-mono">{{ day.label }}</span>
              </div>
            }
          </div>
        </section>
      </div>
    </div>

    <div class="split">
      <section aria-label="A fila de hoje">
        <div class="section-head">
          <h2>A fila de hoje</h2>
          <a routerLink="/biblioteca">Ver todos os baralhos</a>
        </div>
        @if (byDeck().length > 0) {
          <ul class="decks">
            @for (row of byDeck(); track row.deck.id) {
              <li>
                <span class="rule" aria-hidden="true"></span>
                <span class="who">
                  <span class="name">{{ row.deck.name }}</span>
                  <span class="meta">
                    {{ plural(store.cardsOfDeck(row.deck.id).length, 'card', 'cards') }} ·
                    {{ plural(store.matureCount(row.deck.id), 'maduro', 'maduros') }}
                  </span>
                </span>
                <span class="badge">{{ row.count }} hoje</span>
                <a class="ghost" routerLink="/estudar">Estudar</a>
              </li>
            }
          </ul>
        } @else {
          <p class="prose muted">Nenhum baralho com cards vencendo hoje.</p>
        }
      </section>

      <section aria-label="Próximos 14 dias">
        <div class="section-head"><h2>Próximos 14 dias</h2></div>
        @if (forecast().length > 0) {
          <div class="forecast">
            @for (day of forecast(); track day.label) {
              <div>
                <span
                  class="bar"
                  [style.height.px]="day.height"
                  [class.peak]="day.peak"
                  [class.empty]="day.empty"
                ></span>
                <span class="mn-mono">{{ day.label }}</span>
              </div>
            }
          </div>
        } @else {
          <p class="prose muted">Nada vencendo nas próximas duas semanas.</p>
        }
      </section>
    </div>

    @if (sync.phase() === 'failed' && sync.message()) {
      <p class="problem" role="status">Não consegui sincronizar: {{ sync.message() }}</p>
    }
  `,
})
export class Today {
  protected readonly store = inject(Store);
  protected readonly sync = inject(Sync);

  protected readonly due = computed(() => this.store.due());
  protected readonly hasCards = computed(() => this.store.liveCards().length > 0);

  protected plural(n: number, one: string, many: string): string {
    return `${n} ${n === 1 ? one : many}`;
  }

  /**
   * "terça, 31 de agosto" — a sobrancelha do cabeçalho.
   *
   * O `-feira` cai fora, como no aplicativo (`longDate` em `format.dart`).
   * Antes o app dizia "SEGUNDA, 31 DE AGOSTO" e o web "QUARTA-FEIRA, 2 DE
   * SETEMBRO": o primeiro texto de duas telas equivalentes, escrito de dois
   * jeitos.
   */
  protected readonly today = computed(() =>
    new Date()
      .toLocaleDateString('pt-BR', { weekday: 'long', day: 'numeric', month: 'long' })
      .replace('-feira', ''),
  );

  /**
   * A fila de hoje repartida por baralho.
   *
   * Deriva de `due()` e não de uma contagem própria: o número do bloco-âncora
   * e os das linhas têm de somar, e só somam se vierem da mesma fonte.
   */
  protected readonly byDeck = computed(() => {
    const decks = new Map(this.store.liveDecks().map((d) => [d.id, d]));
    const counts = new Map<string, number>();
    for (const card of this.due()) {
      counts.set(card.deck_id, (counts.get(card.deck_id) ?? 0) + 1);
    }
    return [...counts.entries()]
      .flatMap(([id, count]) => {
        const deck = decks.get(id);
        return deck ? [{ deck, count }] : [];
      })
      .sort((a, b) => b.count - a.count);
  });

  /**
   * §2.3 — a manchete. Em dias enquanto couber em dias: "410 dias" é uma
   * conquista legível, "1,1 anos" é um arredondamento que esconde o progresso
   * da semana.
   */
  protected readonly memory = computed(() => {
    const days = this.store.accumulatedMemoryDays();
    if (days === 0) return '—';
    if (days === 1) return '1 dia';
    return `${days.toLocaleString('pt-BR')} dias`;
  });

  /** §9 — medida sobre o log de revisões, nunca sobre o que se esperava. */
  protected readonly retention = computed(() => {
    const since = Date.now() - 90 * 86_400_000;
    const graded = this.store
      .reviews()
      .filter((r) => new Date(r.reviewed_at).getTime() >= since);
    if (graded.length === 0) return '—';
    const right = graded.filter((r) => r.grade > 1).length;
    return `${Math.round((right / graded.length) * 100)}%`;
  });

  /**
   * Os sete dias da semana e se a meta foi batida em cada um.
   *
   * Não é enfeite do número: mostra **quais** dias contaram, que é o que
   * deixa a sequência verificável em vez de afirmada.
   */
  protected readonly week = computed(() => {
    const goal = this.store.dailyGoal();
    const perDay = new Map<string, number>();
    for (const review of this.store.reviews()) {
      const key = new Date(review.reviewed_at).toLocaleDateString('en-CA');
      perDay.set(key, (perDay.get(key) ?? 0) + 1);
    }

    const labels = ['DOM', 'SEG', 'TER', 'QUA', 'QUI', 'SEX', 'SÁB'];
    const days = [];
    for (let back = 6; back >= 0; back--) {
      const date = new Date();
      date.setDate(date.getDate() - back);
      const key = date.toLocaleDateString('en-CA');
      days.push({
        label: labels[date.getDay()],
        met: goal > 0 && (perDay.get(key) ?? 0) >= goal,
        today: back === 0,
      });
    }
    return days;
  });

  /**
   * Quantos cards vencem em cada um dos próximos catorze dias.
   *
   * **Os catorze slots, sempre** — inclusive os vazios. Antes só os dias com
   * vencimento eram desenhados, e três barras vizinhas rotuladas 02, 03 e 08
   * se liam como três dias consecutivos: o gráfico mentia sobre o intervalo.
   * Saúde e Tempo de Uso renderizam o período inteiro; ausência de dado é um
   * espaço, não uma barra que não existe. O app já fazia assim.
   */
  protected readonly forecast = computed(() => {
    const states = this.store.states();
    const perDay = new Map<string, number>();

    for (const card of this.store.liveCards()) {
      const dueAt = states.get(card.id)?.dueAt;
      if (!dueAt) continue;
      const ahead = Math.floor((dueAt.getTime() - Date.now()) / 86_400_000);
      if (ahead < 0 || ahead > 13) continue;
      const key = dueAt.toLocaleDateString('en-CA');
      perDay.set(key, (perDay.get(key) ?? 0) + 1);
    }

    const days = [];
    for (let ahead = 0; ahead < 14; ahead++) {
      const date = new Date();
      date.setDate(date.getDate() + ahead);
      const key = date.toLocaleDateString('en-CA');
      days.push({ label: key.slice(8), count: perDay.get(key) ?? 0 });
    }

    const peak = Math.max(...days.map((d) => d.count));
    if (peak === 0) return [];

    return days.map((d) => ({
      label: d.label,
      // Piso de 3 px, na cor do trilho: um dia zerado desenhado com a altura
      // mínima **da barra** parece um dia com um card.
      height: d.count === 0 ? 3 : Math.max(6, Math.round((d.count / peak) * 64)),
      peak: d.count > 0 && d.count === peak,
      empty: d.count === 0,
    }));
  });
}
