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

    <input
      class="search"
      type="search"
      [(ngModel)]="query"
      placeholder="Buscar em baralhos e cards"
      aria-label="Buscar"
    />

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
    } @else {
      <ul class="decks">
        @for (deck of decks(); track deck.id) {
          <li>
            <a [routerLink]="['/biblioteca', deck.id]">
              <div class="row">
                <h2>{{ deck.name }}</h2>
                <span aria-hidden="true">→</span>
              </div>
              @if (countOf(deck.id) === 0) {
                <p class="meta">Sem cards ainda</p>
              } @else {
                <div class="bar" aria-hidden="true">
                  <span [style.width.%]="(matureOf(deck.id) / countOf(deck.id)) * 100"></span>
                </div>
                <!-- §5.2 — "maduros", nunca "concluído": nada é concluído em
                     repetição espaçada. -->
                <p class="meta">
                  {{ countOf(deck.id) }} {{ countOf(deck.id) === 1 ? 'card' : 'cards' }} ·
                  {{ matureOf(deck.id) }} {{ matureOf(deck.id) === 1 ? 'maduro' : 'maduros' }}
                </p>
              }
            </a>
          </li>
        }
      </ul>
    }
  `,
})
export class Library {
  private readonly store = inject(Store);

  protected readonly query = signal('');
  protected readonly decks = computed(() => this.store.liveDecks());

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
}
