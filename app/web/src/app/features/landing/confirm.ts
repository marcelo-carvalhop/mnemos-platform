import { ChangeDetectionStrategy, Component, inject, signal } from '@angular/core';
import { ActivatedRoute, Router, RouterLink } from '@angular/router';
import { Offline } from '../../core/api';
import { Session } from '../../core/session';
import { Sync } from '../../core/sync';

/**
 * O link do e-mail de confirmação cai aqui (`/confirmar?token=…`).
 *
 * Abrir o link prova a caixa de entrada, então o navegador sai com sessão e vai
 * direto para Hoje. Quem criou a conta no celular e abriu o e-mail no
 * computador ganha a web de brinde; no celular, basta entrar com a senha.
 */
@Component({
  selector: 'app-confirm',
  changeDetection: ChangeDetectionStrategy.OnPush,
  imports: [RouterLink],
  styles: `
    :host {
      display: grid;
      place-items: center;
      min-height: 100dvh;
      padding: 40px 20px;
      background:
        linear-gradient(var(--mn-surface-soft) 1px, transparent 1px) 0 0 / 56px 56px,
        linear-gradient(90deg, var(--mn-surface-soft) 1px, transparent 1px) 0 0 / 56px 56px,
        var(--mn-surface);
    }
    .wrap {
      width: 100%;
      max-width: 440px;
    }
    .brand {
      display: inline-flex;
      align-items: center;
      gap: 10px;
      margin-bottom: 28px;
      font-family: var(--mn-font-display);
      font-size: 20px;
      font-weight: 600;
      letter-spacing: -0.02em;
      color: var(--mn-text);
      text-decoration: none;
    }
    .mark {
      flex: none;
    }
    .card {
      padding: 36px 32px 32px;
      border: 1px solid var(--mn-line);
      border-radius: var(--mn-radius-lg);
      background: var(--mn-surface-raised);
      box-shadow: var(--mn-shadow-float);
    }
    .status {
      display: grid;
      place-items: center;
      width: 44px;
      height: 44px;
      margin-bottom: 24px;
      border-radius: var(--mn-radius-pill);
      background: var(--mn-highlight-soft);
      color: var(--mn-highlight);
    }
    .status.ok {
      background: var(--mn-good-bg);
      color: var(--mn-good);
    }
    .status.bad {
      background: var(--mn-again-bg);
      color: var(--mn-again);
    }
    .status.working svg {
      animation: spin 1s linear infinite;
    }
    @keyframes spin {
      to {
        transform: rotate(360deg);
      }
    }
    .kicker {
      margin: 0 0 10px;
      font-family: var(--mn-font-mono);
      font-size: 12px;
      letter-spacing: 0.12em;
      text-transform: uppercase;
      color: var(--mn-text-faint);
    }
    h1 {
      font-size: 30px;
      line-height: 1.1;
      margin-bottom: 10px;
    }
    p {
      margin: 0;
      font-size: 15px;
      line-height: 1.6;
      color: var(--mn-text-muted);
    }
    .cta {
      display: inline-flex;
      margin-top: 24px;
      padding: 13px 24px;
      background: var(--mn-accent);
      color: var(--mn-text-on-accent);
      border-radius: var(--mn-radius-pill);
      font-weight: 500;
      text-decoration: none;
    }
    .cta:hover {
      background: var(--mn-accent-hover);
    }
  `,
  template: `
    <div class="wrap">
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
      <div class="card">
        @switch (state()) {
          @case ('working') {
            <span class="status working" aria-hidden="true">
              <svg
                width="20"
                height="20"
                viewBox="0 0 24 24"
                fill="none"
                stroke="currentColor"
                stroke-width="2.2"
                stroke-linecap="round"
              >
                <path d="M21 12a9 9 0 1 1-6.2-8.56" />
              </svg>
            </span>
            <p class="kicker">Confirmação</p>
            <h1>Confirmando…</h1>
            <p>Só um instante.</p>
          }
          @case ('done') {
            <span class="status ok" aria-hidden="true">
              <svg
                width="20"
                height="20"
                viewBox="0 0 24 24"
                fill="none"
                stroke="currentColor"
                stroke-width="2.4"
                stroke-linecap="round"
                stroke-linejoin="round"
              >
                <path d="M20 6 9 17l-5-5" />
              </svg>
            </span>
            <p class="kicker">Tudo certo</p>
            <h1>E-mail confirmado</h1>
            <p>Sua conta está ativa. Levando você para os seus cards…</p>
          }
          @case ('offline') {
            <span class="status bad" aria-hidden="true">
              <svg
                width="20"
                height="20"
                viewBox="0 0 24 24"
                fill="none"
                stroke="currentColor"
                stroke-width="2.2"
                stroke-linecap="round"
              >
                <path d="M12 8v5" />
                <path d="M12 16.5v.01" />
              </svg>
            </span>
            <p class="kicker">Sem conexão</p>
            <h1>Não consegui falar com o servidor</h1>
            <p>Abra o link de novo quando a internet voltar.</p>
          }
          @default {
            <span class="status bad" aria-hidden="true">
              <svg
                width="20"
                height="20"
                viewBox="0 0 24 24"
                fill="none"
                stroke="currentColor"
                stroke-width="2.2"
                stroke-linecap="round"
              >
                <path d="M18 6 6 18" />
                <path d="m6 6 12 12" />
              </svg>
            </span>
            <p class="kicker">Link expirado</p>
            <h1>Este link não vale mais</h1>
            <p>
              Ele já foi usado ou passou dos 7 dias. Se a conta já está confirmada, é só entrar; se
              não, entre com seu e-mail e peça um link novo.
            </p>
            <a class="cta" routerLink="/entrar">Ir para entrar</a>
          }
        }
      </div>
    </div>
  `,
})
export class Confirm {
  private readonly session = inject(Session);
  private readonly sync = inject(Sync);
  private readonly router = inject(Router);

  protected readonly state = signal<'working' | 'done' | 'invalid' | 'offline'>('working');

  constructor() {
    const token = inject(ActivatedRoute).snapshot.queryParamMap.get('token');
    if (!token) {
      this.state.set('invalid');
      return;
    }
    void this.confirm(token);
  }

  private async confirm(token: string): Promise<void> {
    try {
      await this.session.confirmEmail(token);
      this.state.set('done');
      if (this.session.signedIn()) {
        await this.sync.syncNow().catch(() => undefined);
        await this.router.navigate(['/hoje']);
      }
    } catch (e) {
      this.state.set(e instanceof Offline ? 'offline' : 'invalid');
    }
  }
}
