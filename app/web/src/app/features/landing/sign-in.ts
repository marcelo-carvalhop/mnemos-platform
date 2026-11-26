import { ChangeDetectionStrategy, Component, computed, inject, signal } from '@angular/core';
import { FormsModule } from '@angular/forms';
import { ActivatedRoute, Router, RouterLink } from '@angular/router';
import { ApiError, Offline } from '../../core/api';
import { Session } from '../../core/session';
import { Sync } from '../../core/sync';

/**
 * Entrar ou criar conta — a outra tela que o aplicativo não tem.
 *
 * Num servidor só para convidados, criar conta pede o código de convite e
 * termina num e-mail de confirmação: a sessão nasce quando a pessoa abre o
 * link (`/confirmar`), não aqui. Num servidor aberto, entra direto. Um formulário só, com um botão que muda de papel, porque
 * "entrar" e "criar conta" são a mesma intenção — usar o produto — e duas
 * páginas separadas obrigam a escolher antes de saber qual é o seu caso.
 */
@Component({
  selector: 'app-sign-in',
  changeDetection: ChangeDetectionStrategy.OnPush,
  imports: [FormsModule, RouterLink],
  styleUrl: './sign-in.css',
  template: `
    <aside class="pitch">
      <a class="brand" routerLink="/">
        <svg class="mark" aria-hidden="true" width="20" height="20" viewBox="0 0 24 24" fill="none">
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

      <div class="pitch-body">
        <p class="eyebrow">Repetição espaçada</p>
        <p class="claim">
          O que você aprendeu,<br /><span class="quiet">de volta na hora certa.</span>
        </p>

        <div class="sample" aria-hidden="true">
          <div class="sample-head">
            <span>Geografia</span>
            <span>2 / 12</span>
          </div>
          <p class="sample-front">Por que existem as estações do ano?</p>
          <div class="sample-grades">
            <span class="again">Errei</span><span class="hard">Difícil</span
            ><span class="good">Bom</span><span class="easy">Fácil</span>
          </div>
        </div>

        <ol>
          <li>
            <span class="n">01</span>
            <span
              ><strong>Cards curtos, uma ideia cada.</strong> Escritos por você ou propostos pela
              IA, sempre com a sua aprovação.</span
            >
          </li>
          <li>
            <span class="n">02</span>
            <span
              ><strong>Um histórico só.</strong> Navegador, celular e terminal de tinta eletrônica
              com o mesmo cronograma.</span
            >
          </li>
          <li>
            <span class="n">03</span>
            <span
              ><strong>Uma métrica: memória.</strong> Quanto tempo o que você sabe fica de pé sem
              precisar de revisão.</span
            >
          </li>
        </ol>
      </div>

      <p class="fine">
        {{
          inviteRequired()
            ? 'No beta, quem entra com convite usa o Mnemos com IA, sem pagar.'
            : 'O primeiro mês é grátis, para testar.'
        }}
      </p>
    </aside>

    <main class="panel">
      @if (sentTo(); as address) {
        <section class="sent" aria-live="polite">
          <p class="kicker">Quase lá</p>
          <h1>Confirme seu e-mail</h1>
          <p class="lede">
            Mandamos um link para <strong>{{ address }}</strong
            >. Abra o e-mail e toque em <em>Confirmar e-mail</em>. Você entra direto, neste ou em
            outro aparelho.
          </p>
          <p class="hint">Não chegou em um minuto? Olhe o spam ou peça outro link.</p>

          @if (notice(); as message) {
            <p class="notice" role="status">{{ message }}</p>
          }

          <button class="primary" type="button" (click)="resend()" [disabled]="busy()">
            {{ busy() ? 'Um momento…' : 'Mandar o link de novo' }}
          </button>

          <p class="switch">
            Já confirmou?
            <button type="button" (click)="backToSignIn()">Entrar</button>
          </p>
        </section>
      } @else {
        <form (submit)="submit($event)">
          <p class="kicker">{{ creating() ? 'Nova conta' : 'Sua conta' }}</p>
          <h1>{{ creating() ? 'Criar conta' : 'Entrar' }}</h1>
          <p class="lede">
            {{
              creating()
                ? inviteRequired()
                  ? 'Use o código de convite que você recebeu.'
                  : 'Estude no navegador com o mesmo histórico do celular e do terminal.'
                : 'Continue de onde parou, em qualquer superfície.'
            }}
          </p>

          @if (creating() && inviteRequired()) {
            <label>
              <span>Código de convite</span>
              <input
                type="text"
                name="invite"
                autocomplete="off"
                autocapitalize="none"
                spellcheck="false"
                required
                [(ngModel)]="invite"
                [disabled]="busy()"
              />
            </label>
          }

          <label>
            <span>E-mail</span>
            <input
              type="email"
              name="email"
              autocomplete="email"
              required
              [(ngModel)]="email"
              [disabled]="busy()"
            />
          </label>

          <label>
            <span>Senha</span>
            <input
              type="password"
              name="password"
              [attr.autocomplete]="creating() ? 'new-password' : 'current-password'"
              required
              minlength="8"
              [(ngModel)]="password"
              [disabled]="busy()"
            />
            @if (creating()) {
              <small>Ao menos 8 caracteres.</small>
            }
          </label>

          @if (problem(); as message) {
            <p class="problem" role="alert">
              {{ message }}
              @if (unconfirmed()) {
                <button type="button" class="inline" (click)="resend()" [disabled]="busy()">
                  Mandar o link de novo
                </button>
              }
            </p>
          }
          @if (notice(); as message) {
            <p class="notice" role="status">{{ message }}</p>
          }

          <button class="primary" type="submit" [disabled]="!valid() || busy()">
            {{ busy() ? 'Um momento…' : creating() ? 'Criar conta' : 'Entrar' }}
          </button>

          @if (creating()) {
            <p class="consent">
              Ao criar a conta você aceita os <a routerLink="/termos">termos de uso</a> e a
              <a routerLink="/privacidade">política de privacidade</a>.
            </p>
          }

          <p class="switch">
            {{
              creating()
                ? 'Já tem conta?'
                : inviteRequired()
                  ? 'Recebeu um convite?'
                  : 'Ainda não tem conta?'
            }}
            <button type="button" (click)="toggle()">
              {{ creating() ? 'Entrar' : 'Criar uma conta' }}
            </button>
          </p>
        </form>
      }
    </main>
  `,
})
export class SignIn {
  private readonly session = inject(Session);
  private readonly sync = inject(Sync);
  private readonly router = inject(Router);
  private readonly route = inject(ActivatedRoute);

  protected readonly email = signal('');
  protected readonly password = signal('');
  protected readonly invite = signal('');
  protected readonly creating = signal(false);
  protected readonly busy = signal(false);
  protected readonly problem = signal<string | null>(null);
  protected readonly notice = signal<string | null>(null);
  /** O login recusou por e-mail não confirmado: oferece mandar o link de novo. */
  protected readonly unconfirmed = signal(false);
  /** Depois de criar a conta num servidor com confirmação: para quem foi o link. */
  protected readonly sentTo = signal<string | null>(null);
  /**
   * Na dúvida, pede o convite: um campo a mais num servidor aberto custa menos
   * que um cadastro recusado sem explicação num fechado.
   */
  protected readonly inviteRequired = signal(true);

  protected readonly valid = computed(
    () =>
      this.email().includes('@') &&
      this.password().length >= 8 &&
      (!this.creating() || !this.inviteRequired() || this.invite().trim().length > 0),
  );

  constructor() {
    // "Tenho um convite" na landing abre direto em criar conta.
    if (this.route.snapshot.queryParamMap.has('convite')) this.creating.set(true);
    this.session
      .options()
      .then((o) => this.inviteRequired.set(o.invite_required))
      .catch(() => {
        /* offline ou servidor antigo: continua pedindo o convite */
      });
  }

  protected toggle(): void {
    this.creating.set(!this.creating());
    this.problem.set(null);
    this.notice.set(null);
    this.unconfirmed.set(false);
  }

  protected backToSignIn(): void {
    this.sentTo.set(null);
    this.creating.set(false);
    this.password.set('');
    this.notice.set(null);
    this.problem.set(null);
  }

  protected async submit(event: Event): Promise<void> {
    event.preventDefault();
    if (!this.valid() || this.busy()) return;

    this.busy.set(true);
    this.problem.set(null);
    this.notice.set(null);
    this.unconfirmed.set(false);
    const email = this.email().trim();

    try {
      if (this.creating()) {
        const outcome = await this.session.signUp(email, this.password(), this.invite());
        if (outcome === 'verification-sent') {
          this.busy.set(false);
          this.sentTo.set(email);
          return;
        }
      } else {
        await this.session.signIn(email, this.password());
      }

      // Puxar antes de mostrar Hoje: entrar e ver uma biblioteca vazia por dois
      // segundos parece perda de dados, ainda que nada tenha se perdido.
      await this.sync.syncNow();
      await this.router.navigate(['/hoje']);
    } catch (e) {
      this.busy.set(false);
      this.unconfirmed.set(e instanceof ApiError && e.detail === 'email_not_verified');
      this.problem.set(explain(e, this.creating()));
    }
  }

  protected async resend(): Promise<void> {
    const email = this.sentTo() ?? this.email().trim();
    if (!email.includes('@') || this.busy()) return;
    this.busy.set(true);
    this.notice.set(null);
    try {
      await this.session.resendVerification(email);
      this.problem.set(null);
      this.unconfirmed.set(false);
      this.notice.set(
        `Se houver uma confirmação pendente para ${email}, um link novo está a caminho.`,
      );
    } catch (e) {
      this.problem.set(
        e instanceof Offline
          ? 'Sem conexão com o servidor. Tente de novo.'
          : 'Não consegui mandar agora. Tente em um minuto.',
      );
    } finally {
      this.busy.set(false);
    }
  }
}

/**
 * §10 — a copy é do cliente, nunca a prosa do servidor.
 *
 * Um 401 aqui não diz se o e-mail existe: dizer "esta conta não existe"
 * transforma o formulário num verificador de e-mails cadastrados.
 */
function explain(error: unknown, creating: boolean): string {
  if (error instanceof Offline) return 'Sem conexão com o servidor. Tente de novo.';
  if (error instanceof ApiError) {
    if (error.detail === 'invite_invalid') return 'Esse código de convite não confere.';
    if (error.detail === 'email_not_verified')
      return 'Falta confirmar o e-mail. Abra o link que mandamos quando você criou a conta.';
    if (error.status === 409) return 'Já existe uma conta com este e-mail.';
    if (error.status === 401 || error.status === 403) return 'E-mail ou senha não conferem.';
    if (error.status === 422) return 'Confira o e-mail e use ao menos 8 caracteres na senha.';
    if (error.isTransient) return 'O servidor tropeçou. Tente de novo em instantes.';
  }
  return creating ? 'Não consegui criar a conta agora.' : 'Não consegui entrar agora.';
}
