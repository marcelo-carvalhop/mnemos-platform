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
    <h1>Dispositivo</h1>

    @if (loading()) {
      <p class="quiet">Procurando terminais…</p>
    } @else if (terminals().length === 0) {
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
          <header>
            <h2>{{ terminal.model || 'Terminal Mnemos' }}</h2>
            <p class="quiet mn-mono">
              {{ terminal.firmware || 'firmware desconhecido' }} · {{ lastSeen(terminal) }} ·
              {{ terminal.card_count }}/{{ terminal.max_cards }} cards
            </p>
          </header>

          <h3>Baralhos no terminal</h3>
          <ul class="decks">
            @for (deck of decks(); track deck.id) {
              <li>
                <label>
                  <input
                    type="checkbox"
                    [checked]="terminal.desired_deck_ids.includes(deck.id)"
                    (change)="toggle(terminal, deck.id)"
                  />
                  <span>{{ deck.name }}</span>
                </label>
                <!-- O estado real, ao lado do pedido. Sem isso a pessoa não
                     sabe se o terminal já recebeu. -->
                @if (
                  terminal.desired_deck_ids.includes(deck.id) &&
                  !terminal.reported_deck_ids.includes(deck.id)
                ) {
                  <span class="pending mn-mono">aguardando o terminal</span>
                } @else if (terminal.reported_deck_ids.includes(deck.id)) {
                  <span class="onboard mn-mono">no aparelho</span>
                }
              </li>
            }
          </ul>

          @if (problem(); as message) {
            <p class="problem" role="status">{{ message }}</p>
          }
        </section>
      }
    }
  `,
})
export class Device {
  private readonly http = inject(HttpClient);
  private readonly baseUrl = inject(API_BASE_URL);
  private readonly store = inject(Store);

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
    return `visto há ${Math.round(hours / 24)} dias`;
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
