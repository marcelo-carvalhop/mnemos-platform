import { HttpClient } from '@angular/common/http';
import { Injectable, computed, inject, signal } from '@angular/core';
import { firstValueFrom } from 'rxjs';
import { toFailure } from './api';
import { API_BASE_URL } from './config';

interface TokenPair {
  access_token: string;
  refresh_token: string;
  user_id: string;
}

/** O que criar conta pede neste servidor (`GET /v1/auth/options`). */
export interface AuthOptions {
  invite_required: boolean;
  email_verification_required: boolean;
}

/** Criar conta termina de um destes dois jeitos. */
export type SignUpOutcome = 'signed-in' | 'verification-sent';

interface RegisterResponse {
  status: 'verification_sent' | 'signed_in';
  email: string;
  tokens: TokenPair | null;
}

const ACCESS = 'mnemos.access';
const REFRESH = 'mnemos.refresh';
const DEVICE = 'mnemos.device';

/**
 * Quem está usando, e como o navegador prova isso (§8).
 *
 * **Criar conta são dois passos, não um.** `POST /v1/auth/signup` não cria
 * conta: ele *anexa* e-mail e senha a uma conta anônima que já existe, e por
 * isso exige um bearer. É o desenho de §8.1 — no telefone a conta nasce sozinha
 * quando o aparelho se registra, e as credenciais só entram se e quando a
 * pessoa quiser um segundo aparelho. Na web o mesmo caminho vale: registrar o
 * navegador como aparelho, depois anexar as credenciais. Descobri isso ao
 * chamar o servidor de verdade; contra um mock, um `signup` solto parece
 * funcionar.
 *
 * No telefone os tokens ficam no keychain da plataforma. O navegador não tem
 * equivalente: `localStorage` é o que existe, e é legível por qualquer script
 * desta origem. A consequência prática é que a web **não** guarda nada além dos
 * tokens — nenhum conteúdo de card, nenhum histórico — e o refresh é rotacionado
 * a cada uso, então um token vazado tem validade curta e um único uso.
 */
@Injectable({ providedIn: 'root' })
export class Session {
  private readonly http = inject(HttpClient);
  private readonly baseUrl = inject(API_BASE_URL);

  private readonly access = signal<string | null>(read(ACCESS));
  private readonly refresh = signal<string | null>(read(REFRESH));

  readonly signedIn = computed(() => this.access() !== null);

  /**
   * O id deste navegador, para as linhas que ele escrever.
   *
   * §6.2 resolve conflito por último-a-escrever com desempate pelo `device_id`,
   * então ele precisa ser estável entre sessões e diferente do id do telefone —
   * dois aparelhos com o mesmo id nunca desempatam.
   */
  readonly deviceId = ensureDeviceId();

  token(): string | null {
    return this.access();
  }

  /**
   * Cria a conta com e-mail e senha de uma vez (`POST /v1/auth/register`).
   *
   * O caminho antigo — registrar o navegador como aparelho anônimo e depois
   * anexar credenciais — não existe num servidor só para convidados: ele
   * recusa contas anônimas. Com confirmação de e-mail ligada, nada entra
   * aqui: a sessão nasce quando a pessoa abre o link (`confirmEmail`).
   */
  async signUp(email: string, password: string, inviteCode = ''): Promise<SignUpOutcome> {
    const result = await this.post<RegisterResponse>('/v1/auth/register', {
      email,
      password,
      device_id: this.deviceId,
      invite_code: inviteCode.trim() || null,
    });
    if (result.status === 'signed_in' && result.tokens) {
      this.store(result.tokens);
      return 'signed-in';
    }
    return 'verification-sent';
  }

  /**
   * Abre o link do e-mail. O link prova a caixa de entrada, então o navegador
   * que o abriu já sai com sessão — sem pedir a senha de novo.
   */
  async confirmEmail(token: string): Promise<void> {
    const result = await this.post<{ email: string; tokens: TokenPair | null }>(
      '/v1/auth/verify-email',
      { token, device_id: this.deviceId },
    );
    if (result.tokens) this.store(result.tokens);
  }

  /** A mesma resposta para qualquer e-mail: não revela quem tem conta. */
  async resendVerification(email: string): Promise<void> {
    await this.post('/v1/auth/resend-verification', { email });
  }

  /** O "Avise-me" do plano com IA. A mesma resposta para um e-mail repetido. */
  async joinWaitlist(email: string): Promise<void> {
    await this.post('/v1/waitlist', { email, plan: 'ai' });
  }

  async options(): Promise<AuthOptions> {
    try {
      return await firstValueFrom(this.http.get<AuthOptions>(`${this.baseUrl}/v1/auth/options`));
    } catch (e) {
      throw toFailure(e);
    }
  }

  async signIn(email: string, password: string): Promise<void> {
    const pair = await this.post<TokenPair>('/v1/auth/login', {
      email,
      password,
      device_id: this.deviceId,
    });
    this.store(pair);
  }

  /**
   * Rotaciona o par. Chamadas concorrentes compartilham uma tentativa: o
   * servidor invalida o refresh a cada uso, então duas rotações em paralelo
   * fariam a segunda derrubar a sessão que a primeira acabou de renovar.
   */
  private rotating: Promise<boolean> | null = null;

  refreshOnce(): Promise<boolean> {
    return (this.rotating ??= this.rotate().finally(() => {
      this.rotating = null;
    }));
  }

  private async rotate(): Promise<boolean> {
    const token = this.refresh();
    if (!token) {
      this.signOut();
      return false;
    }
    try {
      const pair = await firstValueFrom(
        this.http.post<TokenPair>(`${this.baseUrl}/v1/auth/refresh`, { refresh_token: token }),
      );
      this.store(pair);
      return true;
    } catch {
      // Um refresh recusado é sessão encerrada, não um erro para mostrar: quem
      // ficou meses fora simplesmente entra de novo.
      this.signOut();
      return false;
    }
  }

  signOut(): void {
    this.access.set(null);
    this.refresh.set(null);
    remove(ACCESS);
    remove(REFRESH);
  }

  private async post<T>(path: string, body: unknown): Promise<T> {
    try {
      return await firstValueFrom(this.http.post<T>(`${this.baseUrl}${path}`, body));
    } catch (e) {
      throw toFailure(e);
    }
  }

  private store(pair: TokenPair): void {
    this.access.set(pair.access_token);
    this.refresh.set(pair.refresh_token);
    write(ACCESS, pair.access_token);
    write(REFRESH, pair.refresh_token);
  }
}

// `localStorage` lança em contextos onde o navegador bloqueia armazenamento
// (janela privada com site data desligado, iframe de terceiros). Falhar aqui
// derrubaria o app inteiro por uma preferência de privacidade.
function read(key: string): string | null {
  try {
    return localStorage.getItem(key);
  } catch {
    return null;
  }
}

function write(key: string, value: string): void {
  try {
    localStorage.setItem(key, value);
  } catch {
    /* sessão só desta aba */
  }
}

function remove(key: string): void {
  try {
    localStorage.removeItem(key);
  } catch {
    /* nada a limpar */
  }
}

function ensureDeviceId(): string {
  const existing = read(DEVICE);
  if (existing) return existing;
  const fresh = crypto.randomUUID();
  write(DEVICE, fresh);
  return fresh;
}
