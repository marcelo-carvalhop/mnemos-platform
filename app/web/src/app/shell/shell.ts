import {
  ChangeDetectionStrategy,
  Component,
  computed,
  effect,
  inject,
  signal,
  untracked,
} from '@angular/core';
import { toSignal } from '@angular/core/rxjs-interop';
import { NavigationEnd, Router, RouterLink, RouterLinkActive, RouterOutlet } from '@angular/router';
import { filter, map, startWith } from 'rxjs';
import { PendingGenerations } from '../core/open-generations';
import { Session } from '../core/session';
import { Store } from '../core/store';
import { Sync } from '../core/sync';

/**
 * A moldura do aplicativo: navegação à esquerda, tela à direita — e, no
 * celular, o menu do aplicativo: abas na base e "Mais" numa folha.
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
            <svg
              class="mark"
              aria-hidden="true"
              width="20"
              height="20"
              viewBox="0 0 24 24"
              fill="none"
            >
              <rect
                x="3"
                y="6"
                width="14"
                height="14"
                rx="3"
                stroke="currentColor"
                stroke-width="1.8"
              />
              <rect x="7" y="2" width="14" height="14" rx="3" fill="var(--mn-highlight)" />
            </svg>
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

          <!-- O caminho de volta para uma geração, em qualquer tela. -->
          @if (gens.target(); as target) {
            <a class="gen" [class.waiting]="gens.pending() > 0" [routerLink]="target">
              @if (gens.pending() > 0) {
                <strong>{{ gens.pending() }} para aprovar</strong>
                <span>Cards da IA esperando você</span>
              } @else {
                <strong>Gerando cards…</strong>
                <span>Pode continuar; avisamos aqui.</span>
              }
            </a>
          }

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

        <!-- Celular: o mesmo menu do aplicativo. Cabeçalho curto em cima,
             abas na base, onde o polegar alcança. A coluna acima some. -->
        <header class="topbar">
          <a class="brand-sm" routerLink="/hoje" aria-label="Mnemos, ir para Hoje">
            <svg
              class="mark"
              aria-hidden="true"
              width="22"
              height="22"
              viewBox="0 0 24 24"
              fill="none"
            >
              <rect
                x="3"
                y="6"
                width="14"
                height="14"
                rx="3"
                stroke="currentColor"
                stroke-width="1.8"
              />
              <rect x="7" y="2" width="14" height="14" rx="3" fill="var(--mn-highlight)" />
            </svg>
            Mnemos
          </a>
          @if (gens.target(); as target) {
            <a class="gen-pill" [class.waiting]="gens.pending() > 0" [routerLink]="target">
              {{ gens.pending() > 0 ? gens.pending() + ' para aprovar' : 'Gerando…' }}
            </a>
          }
          <button class="sync-chip" type="button" (click)="more.showModal()">
            <span class="dot" [class]="'dot ' + syncTone()" aria-hidden="true"></span>
            {{ syncShort() }}
          </button>
        </header>

        <nav class="tabbar" aria-label="Seções">
          <a routerLink="/hoje" routerLinkActive="on" class="tab">
            <span class="icon">
              <svg
                aria-hidden="true"
                width="22"
                height="22"
                viewBox="0 0 24 24"
                fill="none"
                stroke="currentColor"
                stroke-width="1.8"
                stroke-linecap="round"
                stroke-linejoin="round"
              >
                <rect x="3.5" y="5" width="17" height="15.5" rx="2.5" />
                <path d="M3.5 10h17M8 3v4M16 3v4" />
              </svg>
              @if (dueCount() > 0) {
                <span class="tab-badge">{{ dueCount() > 99 ? '99+' : dueCount() }}</span>
              }
            </span>
            Hoje
          </a>
          <a routerLink="/biblioteca" routerLinkActive="on" class="tab">
            <span class="icon">
              <svg
                aria-hidden="true"
                width="22"
                height="22"
                viewBox="0 0 24 24"
                fill="none"
                stroke="currentColor"
                stroke-width="1.8"
                stroke-linecap="round"
                stroke-linejoin="round"
              >
                <rect x="7" y="3.5" width="13.5" height="17" rx="2.5" />
                <path d="M4 7v11.5A2.5 2.5 0 0 0 6.5 21H16M11 9h6M11 13h6" />
              </svg>
            </span>
            Biblioteca
          </a>
          <a routerLink="/criar" routerLinkActive="on" class="tab create" aria-label="Criar cards">
            <span class="icon plus">
              <svg
                aria-hidden="true"
                width="22"
                height="22"
                viewBox="0 0 24 24"
                fill="none"
                stroke="currentColor"
                stroke-width="2.2"
                stroke-linecap="round"
              >
                <path d="M12 5v14M5 12h14" />
              </svg>
            </span>
            Criar
          </a>
          <a routerLink="/progresso" routerLinkActive="on" class="tab">
            <span class="icon">
              <svg
                aria-hidden="true"
                width="22"
                height="22"
                viewBox="0 0 24 24"
                fill="none"
                stroke="currentColor"
                stroke-width="1.8"
                stroke-linecap="round"
                stroke-linejoin="round"
              >
                <path d="M4 20V10M10 20V4M16 20v-7M22 20H2" />
              </svg>
            </span>
            Progresso
          </a>
          <button type="button" class="tab" [class.on]="inMore()" (click)="more.showModal()">
            <span class="icon">
              <svg
                aria-hidden="true"
                width="22"
                height="22"
                viewBox="0 0 24 24"
                fill="currentColor"
              >
                <circle cx="5" cy="12" r="1.8" />
                <circle cx="12" cy="12" r="1.8" />
                <circle cx="19" cy="12" r="1.8" />
              </svg>
            </span>
            Mais
          </button>
        </nav>

        <dialog
          #more
          class="sheet"
          aria-label="Mais opções"
          (click)="closeOnBackdrop($event, more)"
        >
          <div class="sheet-body" tabindex="-1" autofocus>
            <span class="grabber" aria-hidden="true"></span>
            <div class="sheet-status">
              <p class="eyebrow mn-mono">Sincronização</p>
              <p class="line">
                <span [class]="'dot ' + syncTone()" aria-hidden="true"></span>
                {{ syncLong() }}
              </p>
            </div>
            <ul class="sheet-list">
              <li>
                <a routerLink="/dispositivo" (click)="more.close()">
                  <svg
                    aria-hidden="true"
                    width="20"
                    height="20"
                    viewBox="0 0 24 24"
                    fill="none"
                    stroke="currentColor"
                    stroke-width="1.8"
                    stroke-linecap="round"
                    stroke-linejoin="round"
                  >
                    <rect x="3" y="5" width="18" height="12" rx="2" />
                    <path d="M8 21h8M12 17v4" />
                  </svg>
                  Dispositivo
                  <span class="chev" aria-hidden="true">›</span>
                </a>
              </li>
              <li>
                <a routerLink="/configuracoes" (click)="more.close()">
                  <svg
                    aria-hidden="true"
                    width="20"
                    height="20"
                    viewBox="0 0 24 24"
                    fill="none"
                    stroke="currentColor"
                    stroke-width="1.8"
                    stroke-linecap="round"
                    stroke-linejoin="round"
                  >
                    <circle cx="12" cy="12" r="3" />
                    <path
                      d="M19.4 15a1.7 1.7 0 0 0 .3 1.8l.1.1a2 2 0 1 1-2.8 2.8l-.1-.1a1.7 1.7 0 0 0-1.8-.3 1.7 1.7 0 0 0-1 1.5V21a2 2 0 1 1-4 0v-.1a1.7 1.7 0 0 0-1.1-1.5 1.7 1.7 0 0 0-1.8.3l-.1.1a2 2 0 1 1-2.8-2.8l.1-.1a1.7 1.7 0 0 0 .3-1.8 1.7 1.7 0 0 0-1.5-1H3a2 2 0 1 1 0-4h.1a1.7 1.7 0 0 0 1.5-1.1 1.7 1.7 0 0 0-.3-1.8l-.1-.1a2 2 0 1 1 2.8-2.8l.1.1a1.7 1.7 0 0 0 1.8.3h0a1.7 1.7 0 0 0 1-1.5V3a2 2 0 1 1 4 0v.1a1.7 1.7 0 0 0 1 1.5 1.7 1.7 0 0 0 1.8-.3l.1-.1a2 2 0 1 1 2.8 2.8l-.1.1a1.7 1.7 0 0 0-.3 1.8v0a1.7 1.7 0 0 0 1.5 1H21a2 2 0 1 1 0 4h-.1a1.7 1.7 0 0 0-1.5 1z"
                    />
                  </svg>
                  Configurações
                  <span class="chev" aria-hidden="true">›</span>
                </a>
              </li>
              <li>
                <button type="button" class="out" (click)="more.close(); leave()">
                  <svg
                    aria-hidden="true"
                    width="20"
                    height="20"
                    viewBox="0 0 24 24"
                    fill="none"
                    stroke="currentColor"
                    stroke-width="1.8"
                    stroke-linecap="round"
                    stroke-linejoin="round"
                  >
                    <path d="M9 21H5a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h4M16 17l5-5-5-5M21 12H9" />
                  </svg>
                  Sair
                </button>
              </li>
            </ul>
            <button type="button" class="sheet-close" (click)="more.close()">Fechar</button>
          </div>
        </dialog>
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
  protected readonly gens = inject(PendingGenerations);

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

  /** "Mais" fica marcado quando a tela aberta mora dentro dele. */
  protected readonly inMore = computed(() =>
    ['/dispositivo', '/configuracoes'].some((p) => this.route().startsWith(p)),
  );

  /** O estado da sincronização, nas três formas que as duas barras usam. */
  protected readonly syncTone = computed(() =>
    this.pending() > 0 ? 'pending' : this.sync.phase() === 'offline' ? 'offline' : 'ok',
  );
  protected readonly syncShort = computed(() => {
    const n = this.pending();
    if (n > 0) return `${n} para enviar`;
    return this.sync.phase() === 'offline' ? 'Sem conexão' : 'Sincronizado';
  });
  protected readonly syncLong = computed(() => {
    const n = this.pending();
    if (n > 0) return `${n} ${n === 1 ? 'mudança' : 'mudanças'} para enviar`;
    return this.sync.phase() === 'offline' ? 'Sem conexão. Nada foi perdido.' : 'Tudo enviado';
  });

  /** Um toque fora da folha fecha a folha: o `<dialog>` recebe o clique no fundo. */
  protected closeOnBackdrop(event: MouseEvent, dialog: HTMLDialogElement): void {
    if (event.target === dialog) dialog.close();
  }

  private readonly started = signal(false);

  /** A cada troca de tela, pergunta de novo o que o servidor ainda deve. */
  private readonly refreshGenerations = effect(() => {
    this.route();
    untracked(() => void this.gens.refresh());
  });

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
