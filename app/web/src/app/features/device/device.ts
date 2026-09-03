import { HttpClient } from '@angular/common/http';
import { ChangeDetectionStrategy, Component, computed, inject, signal } from '@angular/core';
import { firstValueFrom } from 'rxjs';
import { API_BASE_URL } from '../../core/config';
import { Store } from '../../core/store';

interface Terminal {
  device_id: string;
  model: string;
  firmware: string;
  desired_deck_ids: string[];
  reported_deck_ids: string[];
  card_count: number;
  max_cards: number;
  connectivity: string | null;
  revoked: boolean;
  last_seen_at: string | null;
  last_sync_at: string | null;
}

/**
 * Dispositivo (§9).
 *
 * O terminal é da metade do hardware do projeto, e esta tela é o que o
 * aplicativo precisa oferecer para ele funcionar: dizer quais baralhos devem
 * estar nele e mostrar o que ele reporta ter.
 *
 * A distinção entre **desejado** e **reportado** é o desenho, não um detalhe:
 * o terminal sincroniza quando encontra rede, então os dois divergem por horas
 * e isso é normal. Uma tela que mostrasse só o desejado mentiria sobre o que
 * está no aparelho agora; uma que mostrasse só o reportado esconderia o que a
 * pessoa acabou de pedir.
 */
@Component({
  selector: 'app-device',
  changeDetection: ChangeDetectionStrategy.OnPush,
  styleUrl: './device.css',
  template: `
    @if (loading()) {
      <h1>Dispositivo</h1>
      <p class="quiet">Procurando terminais…</p>
    } @else if (terminals().length === 0) {
      <h1>Dispositivo</h1>
      <section class="empty">
        <h2>Nenhum terminal emparelhado</h2>
        <p>
          O emparelhamento acontece no aplicativo, por Bluetooth. Depois disso o terminal aparece
          aqui e você escolhe daqui o que vai nele.
        </p>
      </section>
    } @else {
      @for (terminal of terminals(); track terminal.device_id) {
        <section class="terminal">
          <header class="head">
            <div>
              <h1>{{ terminal.model || 'Terminal Mnemos' }}</h1>
              <p class="status">
                <span class="dot" [class.off]="!terminal.last_seen_at" aria-hidden="true"></span>
                <span>{{ lastSeen(terminal) }}</span>
                <span class="mn-mono id">{{ terminal.device_id }}</span>
              </p>
            </div>
          </header>

          <div class="split">
            <!-- A moldura do aparelho. O canvas mostra aqui o card que está na
                 tela do terminal e o nível de bateria; nenhum dos dois existe
                 no protocolo, então o bloco diz o que o terminal reporta de
                 fato — memória — e nomeia a lacuna em vez de desenhá-la. -->
            <div class="frame">
              <div class="screen">
                <p class="eyebrow mn-mono">Memória do aparelho</p>
                <p class="figure">
                  <span class="n">{{ terminal.card_count }}</span>
                  <span class="unit">de {{ terminal.max_cards }} cards</span>
                </p>
                <p class="track" aria-hidden="true">
                  <span [style.width.%]="fill(terminal)"></span>
                </p>
              </div>
              <p class="gap mn-mono">
                Firmware {{ terminal.firmware || 'desconhecido' }}
              </p>
            </div>

            <div>
              <div class="sync">
                <div>
                  <p class="when">{{ lastSync(terminal) }}</p>
                  <p class="detail">{{ waiting(terminal) }}</p>
                </div>
              </div>

              <p class="eyebrow mn-mono spaced">Conteúdo no aparelho</p>
              <ul class="decks">
                @for (deck of decks(); track deck.id) {
                  <li>
                    <!-- Interruptor, como o aplicativo: a mesma lista usava
                         switch lá e um quadradinho de 13 px aqui. O estado
                         ("aguardando" / "no aparelho") desce para baixo do
                         nome em vez de virar uma terceira coluna mono, que
                         empurrava o rótulo e deixava a caixa fora do eixo do
                         texto quando o nome quebrava em duas linhas. -->
                    <label class="pick">
                      <span class="who">
                        <span class="name">{{ deck.name }}</span>
                        <span class="meta">
                          {{ cardsLabel(deck.id) }}
                          @if (
                            terminal.desired_deck_ids.includes(deck.id) &&
                            !terminal.reported_deck_ids.includes(deck.id)
                          ) {
                            <span class="pending"> · aguardando o terminal</span>
                          } @else if (terminal.reported_deck_ids.includes(deck.id)) {
                            <span class="onboard"> · no aparelho</span>
                          }
                        </span>
                      </span>
                      <input
                        class="switch"
                        type="checkbox"
                        role="switch"
                        [checked]="terminal.desired_deck_ids.includes(deck.id)"
                        (change)="toggle(terminal, deck.id)"
                      />
                    </label>
                  </li>
                }
              </ul>

              @if (problem(); as message) {
                <p class="problem" role="status">{{ message }}</p>
              }
            </div>
          </div>
        </section>
      }
    }
  `,
})
export class Device {
  private readonly http = inject(HttpClient);
  private readonly baseUrl = inject(API_BASE_URL);
  protected readonly store = inject(Store);

  protected readonly terminals = signal<Terminal[]>([]);
  protected readonly loading = signal(true);
  protected readonly problem = signal<string | null>(null);

  protected readonly decks = computed(() => this.store.liveDecks());

  constructor() {
    void this.load();
  }

  private async load(): Promise<void> {
    try {
      // O endpoint devolve um array puro, não um envelope.
      const rows = await firstValueFrom(this.http.get<Terminal[]>(`${this.baseUrl}/v1/terminals`));
      // Um terminal revogado não é mais desta conta: mostrá-lo ofereceria
      // controle sobre um aparelho que não responde mais.
      this.terminals.set((rows ?? []).filter((t) => !t.revoked));
    } catch {
      this.terminals.set([]);
    } finally {
      this.loading.set(false);
    }
  }

  protected lastSeen(terminal: Terminal): string {
    if (!terminal.last_seen_at) return 'nunca visto';
    const hours = (Date.now() - new Date(terminal.last_seen_at).getTime()) / 3_600_000;
    if (hours < 1) return 'visto agora há pouco';
    if (hours < 24) return `visto há ${Math.round(hours)} h`;
    const days = Math.round(hours / 24);
    return days === 1 ? 'visto ontem' : `visto há ${days} dias`;
  }

  /** "1 card" e não "1 cards". */
  protected cardsLabel(deckId: string): string {
    const n = this.store.cardsOfDeck(deckId).length;
    return `${n} ${n === 1 ? 'card' : 'cards'}`;
  }

  /** Quanto da memória do terminal está ocupada. */
  protected fill(terminal: Terminal): number {
    return terminal.max_cards === 0 ? 0 : (terminal.card_count / terminal.max_cards) * 100;
  }

  protected lastSync(terminal: Terminal): string {
    if (!terminal.last_sync_at) return 'Ainda não sincronizou';
    const hours = (Date.now() - new Date(terminal.last_sync_at).getTime()) / 3_600_000;
    if (hours < 1) return 'Sincronizado agora há pouco';
    if (hours < 24) return `Sincronizado há ${Math.round(hours)} h`;
    const days = Math.round(hours / 24);
    return days === 1 ? 'Sincronizado ontem' : `Sincronizado há ${days} dias`;
  }

  /** Quantos cards a pessoa pediu que ainda não estão no aparelho. */
  protected waiting(terminal: Terminal): string {
    const pending = terminal.desired_deck_ids
      .filter((id) => !terminal.reported_deck_ids.includes(id))
      .reduce((total, id) => total + this.store.cardsOfDeck(id).length, 0);
    if (pending === 0) return 'O aparelho está com o conteúdo escolhido.';
    return `${pending} ${pending === 1 ? 'card novo esperando' : 'cards novos esperando'} envio`;
  }

  protected async toggle(terminal: Terminal, deckId: string): Promise<void> {
    const wanted = terminal.desired_deck_ids.includes(deckId)
      ? terminal.desired_deck_ids.filter((id) => id !== deckId)
      : [...terminal.desired_deck_ids, deckId];

    // Otimista, com desfazer em caso de falha: marcar uma caixa não deveria
    // esperar a rede, e uma caixa que volta sozinha diz mais que um alerta.
    this.patch(terminal.device_id, { desired_deck_ids: wanted });
    try {
      await firstValueFrom(
        this.http.post(`${this.baseUrl}/v1/terminals/${terminal.device_id}/decks`, {
          deck_ids: wanted,
        }),
      );
      this.problem.set(null);
    } catch {
      this.patch(terminal.device_id, { desired_deck_ids: terminal.desired_deck_ids });
      this.problem.set('Não consegui avisar o terminal. Tente de novo.');
    }
  }

  private patch(deviceId: string, patch: Partial<Terminal>): void {
    this.terminals.update((rows) =>
      rows.map((t) => (t.device_id === deviceId ? { ...t, ...patch } : t)),
    );
  }
}
