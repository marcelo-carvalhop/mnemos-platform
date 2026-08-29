import { ChangeDetectionStrategy, Component, computed, inject, input, signal } from '@angular/core';
import { FormsModule } from '@angular/forms';
import { Router, RouterLink } from '@angular/router';
import { BACK_MAX_GRAPHEMES, FRONT_MAX_GRAPHEMES } from '../../core/contract.g';
import { Store } from '../../core/store';
import { Sync } from '../../core/sync';

/**
 * Um baralho e seus cards, com o editor ao lado.
 *
 * É aqui que a web ganha do telefone pela segunda vez: escrever em série. No
 * celular cada card é abrir uma tela, escrever, salvar e voltar. Com um monitor
 * a lista fica à esquerda e o editor à direita — salvar não fecha nada, e o
 * campo volta vazio pronto para o próximo. Dez cards viram dez minutos em vez
 * de dez navegações.
 *
 * Os limites de tamanho vêm do contrato (§7.6) porque o terminal de tinta
 * eletrônica tem uma tela finita: um card que não cabe nele não é um card.
 */
@Component({
  selector: 'app-deck',
  changeDetection: ChangeDetectionStrategy.OnPush,
  imports: [FormsModule, RouterLink],
  styleUrl: './deck.css',
  template: `
    @if (deck(); as current) {
      <header class="head">
        <div>
          <a class="back" routerLink="/biblioteca">Biblioteca</a>
          <h1>{{ current.name }}</h1>
          <p class="meta">
            {{ cards().length }} {{ cards().length === 1 ? 'card' : 'cards' }} · {{ mature() }}
            {{ mature() === 1 ? 'maduro' : 'maduros' }}
          </p>
        </div>
        <button class="danger" type="button" (click)="removeDeck()">Apagar baralho</button>
      </header>

      <div class="split">
        <section class="list" aria-label="Cards do baralho">
          @if (cards().length === 0) {
            <p class="empty">Nenhum card ainda. Escreva o primeiro ao lado.</p>
          } @else {
            <ul>
              @for (card of cards(); track card.id) {
                <li [class.on]="editingId() === card.id">
                  <button type="button" (click)="edit(card.id)">
                    <strong>{{ card.front }}</strong>
                    <span>{{ card.back }}</span>
                  </button>
                </li>
              }
            </ul>
          }
        </section>

        <section class="editor" aria-label="Escrever card">
          <h2>{{ editingId() ? 'Editar card' : 'Escrever card' }}</h2>

          <label>
            <span>Frente</span>
            <textarea [(ngModel)]="front" rows="3" [maxLength]="frontMax"></textarea>
            <small [class.over]="front().length > frontMax">
              {{ front().length }}/{{ frontMax }}
            </small>
          </label>

          <label>
            <span>Verso</span>
            <textarea [(ngModel)]="back" rows="5" [maxLength]="backMax"></textarea>
            <small [class.over]="back().length > backMax">{{ back().length }}/{{ backMax }}</small>
          </label>

          <!-- §7.6 — a prévia usa serifada porque imita o terminal de tinta
               eletrônica. Ver onde o texto quebra antes de salvar é o que
               impede um card que não cabe no aparelho. -->
          <div class="preview" aria-label="Como fica no aparelho">
            <p class="pf">{{ front() || 'A pergunta aparece aqui' }}</p>
            <hr />
            <p class="pb">{{ back() || 'E a resposta aqui' }}</p>
          </div>

          <div class="editor-actions">
            <button class="primary" type="button" [disabled]="!writable()" (click)="save()">
              {{ editingId() ? 'Salvar' : 'Adicionar card' }}
            </button>
            @if (editingId()) {
              <button type="button" (click)="reset()">Novo</button>
              <button class="danger" type="button" (click)="removeCard()">Apagar card</button>
            }
          </div>
        </section>
      </div>
    } @else {
      <p class="empty">Este baralho não existe mais.</p>
    }
  `,
})
export class Deck {
  private readonly store = inject(Store);
  private readonly sync = inject(Sync);
  private readonly router = inject(Router);

  readonly deckId = input.required<string>();

  protected readonly frontMax = FRONT_MAX_GRAPHEMES;
  protected readonly backMax = BACK_MAX_GRAPHEMES;

  protected readonly front = signal('');
  protected readonly back = signal('');
  protected readonly editingId = signal<string | null>(null);

  protected readonly deck = computed(() =>
    this.store.liveDecks().find((d) => d.id === this.deckId()),
  );
  protected readonly cards = computed(() => this.store.cardsOfDeck(this.deckId()));
  protected readonly mature = computed(() => this.store.matureCount(this.deckId()));

  protected readonly writable = computed(
    () => this.front().trim().length > 0 && this.back().trim().length > 0,
  );

  protected edit(id: string): void {
    const card = this.cards().find((c) => c.id === id);
    if (!card) return;
    this.editingId.set(id);
    this.front.set(card.front);
    this.back.set(card.back);
  }

  protected reset(): void {
    this.editingId.set(null);
    this.front.set('');
    this.back.set('');
  }

  protected save(): void {
    if (!this.writable()) return;
    const front = this.front().trim();
    const back = this.back().trim();
    const editing = this.editingId();

    if (editing) this.store.updateCard(editing, { front, back });
    else this.store.createCard(this.deckId(), front, back);

    // O campo volta vazio: escrever em série é o motivo de esta tela existir.
    this.reset();
    void this.sync.syncNow();
  }

  protected removeCard(): void {
    const editing = this.editingId();
    if (!editing) return;
    this.store.deleteCard(editing);
    this.reset();
    void this.sync.syncNow();
  }

  protected async removeDeck(): Promise<void> {
    // §3 — apagar escreve uma lápide, e a confirmação existe porque isso leva
    // os cards junto.
    const name = this.deck()?.name ?? '';
    if (!confirm(`Apagar "${name}" e todos os seus cards? O histórico de revisões é preservado.`)) {
      return;
    }
    this.store.deleteDeck(this.deckId());
    await this.sync.syncNow();
    await this.router.navigate(['/biblioteca']);
  }
}
