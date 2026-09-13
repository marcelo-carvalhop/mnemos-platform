import { ChangeDetectionStrategy, Component, computed, inject, signal } from '@angular/core';
import { FormsModule } from '@angular/forms';
import { Router, RouterLink } from '@angular/router';
import { ApiError, Offline } from '../../core/api';
import { Session } from '../../core/session';
import { Sync } from '../../core/sync';

/**
 * Entrar ou criar conta — a outra tela que o aplicativo não tem.
 *
 * No celular a conta nasce sozinha, anônima e presa ao aparelho (§8.1). No
 * navegador não há aparelho para atestar, então a identidade tem de ser dita:
 * e-mail e senha. Um formulário só, com um botão que muda de papel, porque
 * "entrar" e "criar conta" são a mesma intenção — usar o produto — e duas
 * páginas separadas obrigam a escolher antes de saber qual é o seu caso.
 */
@Component({
  selector: 'app-sign-in',
  changeDetection: ChangeDetectionStrategy.OnPush,
  imports: [FormsModule, RouterLink],
  styleUrl: './sign-in.css',
  template: `
    <a class="brand" routerLink="/">
      <span class="mark" aria-hidden="true"></span>
      Mnemos
    </a>

    <form (submit)="submit($event)">
      <h1>{{ creating() ? 'Criar conta' : 'Entrar' }}</h1>

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
        <p class="problem" role="alert">{{ message }}</p>
      }

      <button class="primary" type="submit" [disabled]="!valid() || busy()">
        {{ busy() ? 'Um momento…' : creating() ? 'Criar conta' : 'Entrar' }}
      </button>

      <button class="switch" type="button" (click)="creating.set(!creating())">
        {{ creating() ? 'Já tenho conta' : 'Criar uma conta' }}
      </button>
    </form>
  `,
})
export class SignIn {
  private readonly session = inject(Session);
  private readonly sync = inject(Sync);
  private readonly router = inject(Router);

  protected readonly email = signal('');
  protected readonly password = signal('');
  protected readonly creating = signal(false);
  protected readonly busy = signal(false);
  protected readonly problem = signal<string | null>(null);

  protected readonly valid = computed(
    () => this.email().includes('@') && this.password().length >= 8,
  );

  protected async submit(event: Event): Promise<void> {
    event.preventDefault();
    if (!this.valid() || this.busy()) return;

    this.busy.set(true);
    this.problem.set(null);

    try {
      if (this.creating()) await this.session.signUp(this.email().trim(), this.password());
      else await this.session.signIn(this.email().trim(), this.password());

      // Puxar antes de mostrar Hoje: entrar e ver uma biblioteca vazia por dois
      // segundos parece perda de dados, ainda que nada tenha se perdido.
      await this.sync.syncNow();
      await this.router.navigate(['/hoje']);
    } catch (e) {
      this.busy.set(false);
      this.problem.set(explain(e, this.creating()));
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
    if (error.status === 409) return 'Já existe uma conta com este e-mail.';
    if (error.status === 401 || error.status === 403) return 'E-mail ou senha não conferem.';
    if (error.status === 422) return 'Confira o e-mail e use ao menos 8 caracteres na senha.';
    if (error.isTransient) return 'O servidor tropeçou. Tente de novo em instantes.';
  }
  return creating ? 'Não consegui criar a conta agora.' : 'Não consegui entrar agora.';
}
