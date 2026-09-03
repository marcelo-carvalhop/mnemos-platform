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
 * O teste que importa aqui é o do desenho de duas etapas: `signup` **anexa**
 * credenciais a uma conta anônima existente (§8.1) e exige o bearer dela. Um
 * `signup` solto devolve 401, e contra um mock ingênuo isso passa despercebido
 * — foi o que aconteceu antes de eu chamar o servidor de verdade.
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

  it('criar conta registra o aparelho antes de anexar as credenciais', async () => {
    const done = session.signUp('a@b.com', 'senha-de-teste');

    const device = http.expectOne('/api/v1/auth/device');
    expect(device.request.body.platform).toBe('web');
    expect(device.request.body.device_id).toBe(session.deviceId);
    device.flush(pair(1));

    await tick();

    const signup = http.expectOne('/api/v1/auth/signup');
    // O bearer da conta anônima: sem ele o servidor devolve 401.
    expect(signup.request.headers.get('Authorization')).toBe('Bearer access-1');
    signup.flush(pair(2));

    await done;
    expect(session.token()).toBe('access-2');
    expect(session.signedIn()).toBe(true);
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
