import { ChangeDetectionStrategy, Component, computed, inject, signal } from '@angular/core';
import { toSignal } from '@angular/core/rxjs-interop';
import { NavigationEnd, Router, RouterLink, RouterLinkActive, RouterOutlet } from '@angular/router';
import { filter, map, startWith } from 'rxjs';
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

    <div class="frame" [class.focus]="focus()">
      <!-- A revisão esconde a navegação: durante o estudo a barra completa
           continuava na tela, com badge de vencimento e bloco de sincronização
           disputando atenção com a pergunta. Toda superfície de foco da Apple
           tira o cromo — Fotos em tela cheia, o leitor de Books, o player da
           TV. Aqui o "X" e a régua de progresso da própria tela bastam. -->
      @if (!focus()) {
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
                    <span class="badge">{{ dueCount() }}</span>
                  }
                  @if (item.path === '/biblioteca' && cardCount() > 0) {
                    <span class="count mn-mono">{{ cardCount() }}</span>
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

          <!-- O canvas põe aqui o estado do T5. A web não tem cliente de
             terminal — só as rotas de autenticação existem no bundle — então o
             bloco mostra o que ela de fato sabe: o estado da sincronização.
             Inventar uma barra de bateria seria desenho bonito e mentira. -->
          <div class="status">
            <p class="eyebrow mn-mono">Sincronização</p>
            @if (pending() > 0) {
              <p class="line">
                <span class="dot pending" aria-hidden="true"></span>
                {{ pending() }} {{ pending() === 1 ? 'mudança' : 'mudanças' }} para enviar
              </p>
            } @else if (sync.phase() === 'offline') {
              <!-- §5.14 — offline não é erro. O texto é deliberadamente sem drama. -->
              <p class="line">
                <span class="dot offline" aria-hidden="true"></span>
                Sem conexão. Nada foi perdido.
              </p>
            } @else {
              <p class="line">
                <span class="dot ok" aria-hidden="true"></span>
                Tudo enviado
              </p>
            }
          </div>

          <!-- "exact: false" como nos demais: sem isto, a rota
             "/configuracoes" deixava a barra inteira sem nenhum item marcado,
             porque o único item do rodapé não recebia a pílula. -->
          <a
            class="quiet"
            routerLink="/configuracoes"
            routerLinkActive="on"
            [routerLinkActiveOptions]="{ exact: false }"
            >Configurações</a
          >
          <button class="quiet" type="button" (click)="leave()">Sair</button>
        </nav>
      }

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

  /** A rota atual, como sinal. */
  private readonly route = toSignal(
    this.router.events.pipe(
      filter((e): e is NavigationEnd => e instanceof NavigationEnd),
      map((e) => e.urlAfterRedirects),
      startWith(this.router.url),
    ),
    { initialValue: this.router.url },
  );

  /** A revisão é modo de foco: a moldura sai de cena enquanto ela dura. */
  protected readonly focus = computed(() => this.route().startsWith('/estudar'));

  protected readonly dueCount = computed(() => this.store.due().length);

  /** Quantos cards a biblioteca tem, ao lado do seu nome na navegação. */
  protected readonly cardCount = computed(() => this.store.liveCards().length);

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
