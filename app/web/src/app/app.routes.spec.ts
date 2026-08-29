import { provideHttpClient } from '@angular/common/http';
import { provideHttpClientTesting } from '@angular/common/http/testing';
import { Component, provideZonelessChangeDetection } from '@angular/core';
import { TestBed } from '@angular/core/testing';
import { Router, RouterOutlet, provideRouter } from '@angular/router';
import { beforeEach, describe, expect, it } from 'vitest';
import { API_BASE_URL } from './core/config';
import { Session } from './core/session';
import { routes } from './app.routes';

/**
 * A configuração de rotas, montada de verdade.
 *
 * Este arquivo existe por causa de um erro que passou por tudo: a rota `**`
 * tinha `redirectTo` e `canMatch` juntos, que o Angular recusa (NG04014). O
 * build passou, os 68 testes passaram — todos usavam `provideRouter([])`, sem
 * nunca instanciar a configuração real — e a página abria **em branco**, porque
 * uma configuração inválida derruba o roteador inteiro, não só a rota errada.
 *
 * A lição é o teste: um objeto de configuração que nenhum teste instancia não
 * está testado, por mais tipado que seja.
 */
@Component({ selector: 'app-host', template: '<router-outlet />', imports: [RouterOutlet] })
class Host {}

describe('rotas', () => {
  let router: Router;
  let session: Session;

  beforeEach(() => {
    localStorage.clear();
    TestBed.configureTestingModule({
      providers: [
        provideZonelessChangeDetection(),
        provideHttpClient(),
        provideHttpClientTesting(),
        provideRouter(routes),
        { provide: API_BASE_URL, useValue: '/api' },
      ],
    });
    router = TestBed.inject(Router);
    session = TestBed.inject(Session);
    TestBed.createComponent(Host);
  });

  it('a configuração é válida', () => {
    // `resetConfig` revalida. NG04014 e parentes aparecem aqui, não em produção.
    expect(() => router.resetConfig(routes)).not.toThrow();
  });

  it('sem sessão, a raiz é a landing', async () => {
    await router.navigateByUrl('/');
    expect(router.url).toBe('/');
  });

  it('sem sessão, uma tela do aplicativo manda de volta para a landing', async () => {
    // As telas internas só casam com sessão; sem ela a raiz assume, e a raiz
    // sem sessão é a landing.
    await router.navigateByUrl('/hoje');
    expect(router.url).toBe('/');
  });

  it('com sessão, a raiz abre o aplicativo em Hoje', async () => {
    session['store']({ access_token: 'a', refresh_token: 'r', user_id: 'u' });
    await router.navigateByUrl('/');
    expect(router.url).toBe('/hoje');
  });

  it('uma URL desconhecida não deixa a tela vazia', async () => {
    // O caractere-curinga é o que impede um link velho de virar tela branca.
    await router.navigateByUrl('/rota-que-nao-existe');
    expect(router.url).toBe('/');
  });

  it('entrar é alcançável com ou sem sessão', async () => {
    await router.navigateByUrl('/entrar');
    expect(router.url).toBe('/entrar');
  });

  it('toda tela do aplicativo carrega', async () => {
    // Um `loadComponent` com caminho errado só falha quando alguém navega até
    // lá. Aqui todos falham de uma vez, no CI.
    session['store']({ access_token: 'a', refresh_token: 'r', user_id: 'u' });
    for (const path of [
      '/hoje',
      '/estudar',
      '/biblioteca',
      '/biblioteca/algum-id',
      '/criar',
      '/gerar/algum-job',
      '/aprovar/algum-job',
      '/progresso',
      '/dispositivo',
      '/configuracoes',
    ]) {
      await router.navigateByUrl(path);
      expect(router.url, `${path} não abriu`).toBe(path);
    }
  });
});
