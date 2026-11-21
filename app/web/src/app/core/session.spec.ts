import { HttpClient, provideHttpClient, withInterceptors } from '@angular/common/http';
import { HttpTestingController, provideHttpClientTesting } from '@angular/common/http/testing';
import { TestBed } from '@angular/core/testing';
import { firstValueFrom } from 'rxjs';
import { afterEach, beforeEach, describe, expect, it } from 'vitest';
import { authInterceptor } from './auth.interceptor';
import { API_BASE_URL } from './config';
import { Session } from './session';

/**
 * A sessão e o interceptor.
 *
 * Criar conta é um pedido só (`/v1/auth/register`), com o código de convite:
 * um servidor só para convidados recusa a conta anônima que o desenho antigo
 * (aparelho primeiro, credenciais depois) criava.
 */
describe('Session', () => {
  let session: Session;
  let http: HttpTestingController;

  /** Um turno da fila de tarefas: `flush` resolve promessas encadeadas, e uma
   * volta de microtask não basta para chegar à próxima requisição. */
  const tick = () => new Promise((resolve) => setTimeout(resolve, 0));

  const pair = (n: number) => ({
    access_token: `access-${n}`,
    refresh_token: `refresh-${n}`,
    user_id: 'u1',
  });

  beforeEach(() => {
    localStorage.clear();
    TestBed.configureTestingModule({
      providers: [
        provideHttpClient(withInterceptors([authInterceptor])),
        provideHttpClientTesting(),
        { provide: API_BASE_URL, useValue: '/api' },
      ],
    });
    session = TestBed.inject(Session);
    http = TestBed.inject(HttpTestingController);
  });

  afterEach(() => http.verify());

  it('criar conta manda convite e credenciais de uma vez, sem bearer', async () => {
    const done = session.signUp('a@b.com', 'senha-de-teste', ' ConVite123 ');

    const register = http.expectOne('/api/v1/auth/register');
    expect(register.request.headers.has('Authorization')).toBe(false);
    expect(register.request.body).toEqual({
      email: 'a@b.com',
      password: 'senha-de-teste',
      device_id: session.deviceId,
      invite_code: 'ConVite123',
    });
    register.flush({ status: 'verification_sent', email: 'a@b.com', tokens: null });

    // Com confirmação ligada, nada de sessão até o link ser aberto.
    expect(await done).toBe('verification-sent');
    expect(session.signedIn()).toBe(false);
  });

  it('num servidor aberto, criar conta já entra', async () => {
    const done = session.signUp('a@b.com', 'senha-de-teste');

    const register = http.expectOne('/api/v1/auth/register');
    expect(register.request.body.invite_code).toBeNull();
    register.flush({ status: 'signed_in', email: 'a@b.com', tokens: pair(1) });

    expect(await done).toBe('signed-in');
    expect(session.token()).toBe('access-1');
  });

  it('abrir o link de confirmação entra neste navegador', async () => {
    const done = session.confirmEmail('tok');

    const verify = http.expectOne('/api/v1/auth/verify-email');
    expect(verify.request.body).toEqual({ token: 'tok', device_id: session.deviceId });
    verify.flush({ email: 'a@b.com', tokens: pair(3) });

    await done;
    expect(session.token()).toBe('access-3');
  });

  it('uma conta que deixou de ser membro encerra a sessão', async () => {
    session['store'](pair(1));

    const client = TestBed.inject(HttpClient);
    const promise = firstValueFrom(client.get('/api/v1/quota/')).catch((e: unknown) => e);
    http
      .expectOne('/api/v1/quota/')
      .flush({ detail: 'account_required' }, { status: 403, statusText: 'Forbidden' });

    await promise;
    expect(session.signedIn()).toBe(false);
  });

  it('entrar não leva bearer: é a chamada que cria a sessão', async () => {
    const done = session.signIn('a@b.com', 'senha-de-teste');

    const login = http.expectOne('/api/v1/auth/login');
    expect(login.request.headers.has('Authorization')).toBe(false);
    login.flush(pair(1));

    await done;
    expect(session.signedIn()).toBe(true);
  });

  it('o id do aparelho é estável entre sessões', () => {
    // §6.2 desempata conflito pelo `device_id`. Um id novo a cada carregamento
    // faria este navegador nunca desempatar de forma previsível consigo mesmo,
    // e é por isso que ele é persistido em vez de sorteado.
    expect(localStorage.getItem('mnemos.device')).toBe(session.deviceId);
  });

  it('um 401 renova o token e repete o pedido uma vez', async () => {
    session['store'](pair(1));

    const client = TestBed.inject(HttpClient);
    const promise = firstValueFrom(client.get('/api/v1/quota/'));

    const first = http.expectOne('/api/v1/quota/');
    expect(first.request.headers.get('Authorization')).toBe('Bearer access-1');
    first.flush(null, { status: 401, statusText: 'Unauthorized' });

    await tick();
    http.expectOne('/api/v1/auth/refresh').flush(pair(2));

    await tick();
    const retry = http.expectOne('/api/v1/quota/');
    // O pedido repetido leva o token novo — sem isso a renovação não serve.
    expect(retry.request.headers.get('Authorization')).toBe('Bearer access-2');
    retry.flush({ remaining: 1 });

    await promise;
  });

  it('um refresh recusado encerra a sessão em vez de virar erro na tela', async () => {
    // Quem ficou meses fora simplesmente entra de novo; um alerta vermelho
    // trataria isso como defeito.
    session['store'](pair(1));
    const renewed = session.refreshOnce();

    http.expectOne('/api/v1/auth/refresh').flush(null, { status: 401, statusText: 'no' });

    expect(await renewed).toBe(false);
    expect(session.signedIn()).toBe(false);
    expect(localStorage.getItem('mnemos.access')).toBeNull();
  });

  it('duas renovações simultâneas compartilham uma tentativa', async () => {
    // O servidor invalida o refresh a cada uso: duas rotações em paralelo
    // fariam a segunda derrubar a sessão que a primeira acabou de renovar.
    session['store'](pair(1));
    const a = session.refreshOnce();
    const b = session.refreshOnce();

    http.expectOne('/api/v1/auth/refresh').flush(pair(2));

    expect(await a).toBe(true);
    expect(await b).toBe(true);
  });
});
