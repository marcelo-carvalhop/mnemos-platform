import { ChangeDetectionStrategy, Component, computed, inject } from '@angular/core';
import { RouterLink } from '@angular/router';
import { Store } from '../../core/store';
import { Sync } from '../../core/sync';
import { OpenGenerations } from '../create/open-generations';

/**
 * Hoje — a tela onde o estudo mora (§5.2).
 *
 * A manchete é a memória acumulada, não o número de cards. §2.3: quantos cards
 * alguém tem mede o quanto digitou; quanto tempo o conhecimento fica de pé mede
 * o que o produto promete.
 *
 * "Nada vencendo" é uma mensagem de conclusão, não uma tela vazia: a memória
 * segue trabalhando sozinha, e dizer isso é a diferença entre terminar o dia e
 * achar que o app quebrou.
 */
@Component({
  selector: 'app-today',
  changeDetection: ChangeDetectionStrategy.OnPush,
  imports: [RouterLink, OpenGenerations],
  styleUrl: './today.css',
  template: `
    <app-open-generations />

    <header class="head">
      <p class="label">Sua memória acumulada</p>
      <h1>{{ memory() }}</h1>
      <p class="label">de conhecimento guardado</p>
    </header>

    <section class="goal" aria-label="Meta de hoje">
      <div class="ring" [style.--p]="ratio()">
        <span class="mn-mono">{{ percent() }}%</span>
      </div>
      <div>
        <p class="count">{{ store.studiedToday() }} / {{ store.dailyGoal() }} cards</p>
        <p class="label">meta de hoje</p>
      </div>
    </section>

    @if (due().length > 0) {
      <a class="primary" routerLink="/estudar">
        Estudar agora · {{ due().length }}
        <kbd class="mn-mono">espaço</kbd>
      </a>
    } @else if (hasCards()) {
      <section class="done">
        <h2>Nada vencendo agora</h2>
        <p>Sua memória segue trabalhando sozinha.</p>
      </section>
    } @else {
      <section class="empty">
        <h2>Seu primeiro baralho</h2>
        <p>
          Diga o que você quer aprender e a IA escreve os cards. Você aprova um por um antes de
          qualquer coisa virar baralho.
        </p>
        <a class="primary inline" routerLink="/criar">Criar com IA</a>
      </section>
    }

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

  protected readonly ratio = computed(() => {
    const goal = this.store.dailyGoal();
    return goal === 0 ? 0 : Math.min(1, this.store.studiedToday() / goal);
  });

  protected readonly percent = computed(() => Math.round(this.ratio() * 100));

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
}
