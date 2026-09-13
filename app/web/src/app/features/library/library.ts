import { ChangeDetectionStrategy, Component, computed, inject, signal } from '@angular/core';
import { FormsModule } from '@angular/forms';
import { RouterLink } from '@angular/router';
import { Store } from '../../core/store';

/**
 * A biblioteca (§5.12).
 *
 * Existe para criar, abrir e organizar conteúdo. Métricas de retenção e
 * sequência pertencem a Progresso — a proporção de maduros aparece aqui como
 * barra porque é a única coisa que diz se um baralho está sendo estudado ou
 * apenas guardado.
 *
 * A busca é local e imediata: os cards já estão em memória, então filtrar não
 * precisa de rede, e um resultado que aparece enquanto se digita é a diferença
 * entre procurar e lembrar.
 */
@Component({
  selector: 'app-library',
  changeDetection: ChangeDetectionStrategy.OnPush,
  imports: [RouterLink, FormsModule],
  styleUrl: './library.css',
  template: `
    <header class="head">
      <h1>Biblioteca</h1>
      <a class="create" routerLink="/criar">Criar com IA</a>
    </header>

    <div class="tools">
      <input
        class="search"
        type="search"
        [(ngModel)]="query"
        placeholder="Buscar em baralhos e cards"
        aria-label="Buscar"
      />
      <div class="chips" role="group" aria-label="Filtro">
        @for (option of filters; track option.id) {
          <button type="button" [class.on]="filter() === option.id" (click)="filter.set(option.id)">
            {{ option.label }}
          </button>
        }
      </div>
    </div>

    @if (query().trim().length > 1) {
      <section aria-label="Resultados">
        @if (matches().length === 0) {
          <p class="empty-line">Nada encontrado para “{{ query() }}”.</p>
        } @else {
          <ul class="results">
            @for (card of matches(); track card.id) {
              <li>
                <a [routerLink]="['/biblioteca', card.deck_id]">
                  <strong>{{ card.front }}</strong>
                  <span>{{ card.back }}</span>
                </a>
              </li>
            }
          </ul>
        }
      </section>
    } @else if (decks().length === 0) {
      <section class="empty">
        <h2>Comece por um assunto</h2>
        <p>
          Diga o que você quer aprender e a IA escreve os cards. Você aprova um por um antes de
          qualquer coisa virar baralho.
        </p>
        <a class="create" routerLink="/criar">Criar com IA</a>
      </section>
    } @else if (visible().length === 0) {
      <p class="empty-line">Nenhum baralho neste filtro.</p>
    } @else {
      <ul class="decks">
        @for (deck of visible(); track deck.id) {
          <li>
            <div class="row">
              <h2>{{ deck.name }}</h2>
            </div>
            <p class="updated">Atualizado {{ updatedOf(deck.updated_at) }}</p>
            @if (countOf(deck.id) === 0) {
              <p class="meta">Sem cards ainda</p>
            } @else {
              <!-- Três segmentos em vez de três números: a proporção entre o
                   que vence, o que já está firme e o resto se lê antes de
                   qualquer legenda. -->
              <div class="bar" aria-hidden="true">
                @if (dueOf(deck.id) > 0) {
                  <span class="due" [style.flex]="dueOf(deck.id)"></span>
                }
                @if (matureOf(deck.id) > 0) {
                  <span class="mature" [style.flex]="matureOf(deck.id)"></span>
                }
                <span class="rest" [style.flex]="restOf(deck.id)"></span>
              </div>
              <!-- §5.2 — "maduros", nunca "concluído": nada é concluído em
                   repetição espaçada. -->
              <!-- Cada rótulo com o seu ponto, como o aplicativo já faz: sem
                   marcador, a barra de três segmentos acima ficava sem chave e
                   só "vencendo" tinha cor, o que não diz qual segmento é qual. -->
              <p class="meta">
                @if (dueOf(deck.id) > 0) {
                  <span class="due"
                    ><i class="dot" aria-hidden="true"></i>{{ dueOf(deck.id) }} vencendo</span
                  >
                }
                <span class="mature-label"
                  ><i class="dot" aria-hidden="true"></i>{{ matureOf(deck.id) }}
                  {{ matureOf(deck.id) === 1 ? 'maduro' : 'maduros' }}</span
                >
                <span class="total"
                  ><i class="dot" aria-hidden="true"></i>{{ countOf(deck.id) }} total</span
                >
              </p>
            }
            <div class="actions">
              @if (dueOf(deck.id) > 0) {
                <a class="study" routerLink="/estudar">Estudar {{ dueOf(deck.id) }}</a>
              }
              <a class="open" [routerLink]="['/biblioteca', deck.id]">Abrir</a>
            </div>
          </li>
        }
      </ul>
    }
  `,
})
export class Library {
  private readonly store = inject(Store);

  protected readonly query = signal('');
  protected readonly filter = signal<'all' | 'due' | 'mature'>('all');
  protected readonly decks = computed(() => this.store.liveDecks());

  protected readonly filters = [
    { id: 'all' as const, label: 'Todos' },
    { id: 'due' as const, label: 'Vencendo' },
    { id: 'mature' as const, label: 'Maduros' },
  ];

  /** Quantos cards de cada baralho estão na fila de hoje. */
  private readonly dueByDeck = computed(() => {
    const counts = new Map<string, number>();
    for (const card of this.store.due()) {
      counts.set(card.deck_id, (counts.get(card.deck_id) ?? 0) + 1);
    }
    return counts;
  });

  protected readonly visible = computed(() => {
    const decks = this.decks();
    switch (this.filter()) {
      case 'due':
        return decks.filter((d) => this.dueOf(d.id) > 0);
      case 'mature':
        return decks.filter((d) => this.matureOf(d.id) > 0);
      default:
        return decks;
    }
  });

  protected readonly matches = computed(() => {
    const needle = this.query().trim().toLocaleLowerCase('pt-BR');
    if (needle.length < 2) return [];
    return this.store
      .liveCards()
      .filter(
        (c) =>
          c.front.toLocaleLowerCase('pt-BR').includes(needle) ||
          c.back.toLocaleLowerCase('pt-BR').includes(needle),
      )
      .slice(0, 40);
  });

  protected countOf(deckId: string): number {
    return this.store.cardsOfDeck(deckId).length;
  }

  protected matureOf(deckId: string): number {
    return this.store.matureCount(deckId);
  }

  /** "ontem", "há 4 dias" — quando o baralho mudou pela última vez. */
  protected updatedOf(iso: string): string {
    const days = Math.floor((Date.now() - new Date(iso).getTime()) / 86_400_000);
    if (days <= 0) return 'hoje';
    if (days === 1) return 'ontem';
    if (days < 30) return `há ${days} dias`;
    return new Date(iso).toLocaleDateString('pt-BR', { day: 'numeric', month: 'long' });
  }

  protected dueOf(deckId: string): number {
    return this.dueByDeck().get(deckId) ?? 0;
  }

  /** O que não vence hoje nem está maduro — o meio da tabela. */
  protected restOf(deckId: string): number {
    return Math.max(0, this.countOf(deckId) - this.dueOf(deckId) - this.matureOf(deckId));
  }
}
