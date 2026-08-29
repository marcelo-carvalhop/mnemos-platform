import { provideHttpClient, withInterceptors } from '@angular/common/http';
import {
  ApplicationConfig,
  provideBrowserGlobalErrorListeners,
  provideZonelessChangeDetection,
} from '@angular/core';
import { provideRouter, withComponentInputBinding, withInMemoryScrolling } from '@angular/router';
import { authInterceptor } from './core/auth.interceptor';
import { routes } from './app.routes';

/**
 * Zoneless e signals: sem `zone.js`, a detecção de mudanças roda quando um
 * signal muda, e não a cada callback do navegador. Numa tela de estudo isso é
 * a diferença entre o teclado responder na hora e responder depois de o
 * framework varrer a árvore.
 */
export const appConfig: ApplicationConfig = {
  providers: [
    provideBrowserGlobalErrorListeners(),
    provideZonelessChangeDetection(),
    provideHttpClient(withInterceptors([authInterceptor])),
    provideRouter(
      routes,
      // Parâmetros de rota entram como `input()` no componente, o que mantém a
      // tela ignorando de onde o valor veio.
      withComponentInputBinding(),
      withInMemoryScrolling({ scrollPositionRestoration: 'top' }),
    ),
  ],
};
