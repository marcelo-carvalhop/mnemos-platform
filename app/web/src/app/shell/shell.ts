import { ChangeDetectionStrategy, Component, computed, inject, signal } from '@angular/core';
import { Router, RouterLink, RouterLinkActive, RouterOutlet } from '@angular/router';
import { Session } from '../core/session';
import { Store } from '../core/store';
import { Sync } from '../core/sync';

/**
 * A moldura do aplicativo: navegação à esquerda, tela à direita.
 *
 * O telefone usa quatro abas na base porque o polegar chega lá. Na web a mesma
 * navegação vira uma coluna fixa — a largura existe, e esconder a estrutura
 * atrás de um menu hambúrguer num monitor é economizar espaço que sobra.
 *
 * As quatro seções e a ordem são as mesmas do aplicativo. Uma pessoa que usa os
 * dois não deveria ter de reaprender onde as coisas estão.
 */
@Component({
  selector: 'app-shell',
  changeDetection: ChangeDetectionStrategy.OnPush,
  imports: [RouterOutlet, RouterLink, RouterLinkActive],
  styleUrl: './shell.css',
  template: `
    <a class="skip" href="#conteudo">Pular para o conteúdo</a>

    <div class="frame">
      <nav class="rail" aria-label="Seções">
        <a class="brand" routerLink="/hoje">
          <span class="mark" aria-hidden="true"></span>
          <span class="name">Mnemos</span>
        </a>

        <ul class="sections">
          @for (item of sections; track item.path) {
            <li>
              <a
                [routerLink]="item.path"
                routerLinkActive="on"
                [routerLinkActiveOptions]="{ exact: false }"
              >
                <span>{{ item.label }}</span>
                @if (item.path === '/hoje' && dueCount() > 0) {
                  <span class="badge mn-mono">{{ dueCount() }}</span>
                }
              </a>
            </li>
          }
        </ul>

        <a class="write" routerLink="/criar">
          <span>Criar</span>
          <kbd class="mn-mono">N</kbd>
        </a>

        <div class="spacer"></div>

        @if (pending() > 0) {
          <p class="pending">
            <span class="dot" aria-hidden="true"></span>
            {{ pending() }} {{ pending() === 1 ? 'mudança' : 'mudanças' }} para enviar
          </p>
        } @else if (sync.phase() === 'offline') {
          <!-- §5.14 — offline não é erro. O texto é deliberadamente sem drama. -->
          <p class="pending">Sem conexão. Nada foi perdido.</p>
        }

        <a class="quiet" routerLink="/configuracoes" routerLinkActive="on">Configurações</a>
        <button class="quiet" type="button" (click)="leave()">Sair</button>
      </nav>

      <main id="conteudo" class="content">
        <router-outlet />
      </main>
    </div>
  `,
})
export class Shell {
  private readonly session = inject(Session);
  private readonly router = inject(Router);
  protected readonly store = inject(Store);
  protected readonly sync = inject(Sync);

  protected readonly sections = [
    { path: '/hoje', label: 'Hoje' },
    { path: '/biblioteca', label: 'Biblioteca' },
    { path: '/progresso', label: 'Progresso' },
    { path: '/dispositivo', label: 'Dispositivo' },
  ];

  protected readonly dueCount = computed(() => this.store.due().length);

  /** O número honesto de mostrar offline: "3 esperando" é verdade e não alarma. */
  protected readonly pending = computed(() => {
    const tables = [
      this.store.decks(),
      this.store.cards(),
      this.store.reviews(),
      this.store.settings(),
    ];
    return tables.reduce(
      (total, rows) => total + rows.filter((r) => r.server_seq === null).length,
      0,
    );
  });

  private readonly started = signal(false);

  constructor() {
    // Uma sincronia ao abrir. É o momento em que as mudanças de outro aparelho
    // são mais prováveis de estarem esperando (§6).
    if (!this.started()) {
      this.started.set(true);
      void this.sync.syncNow();
    }
  }

  protected async leave(): Promise<void> {
    // Empurrar antes de sair: o que a pessoa escreveu nesta aba não existe em
    // nenhum outro lugar, e sair sem enviar apagaria trabalho dela.
    await this.sync.syncNow();
    this.session.signOut();
    this.store.clear();
    await this.router.navigate(['/']);
  }
}
