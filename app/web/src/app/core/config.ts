import { InjectionToken } from '@angular/core';

/**
 * Onde o servidor mora.
 *
 * Um token e não uma constante porque muda por ambiente e porque os testes
 * precisam trocá-lo sem tocar em nada mais. `/api` no desenvolvimento: o proxy
 * do `ng serve` encaminha para o compose local, o que mantém tudo na mesma
 * origem e tira CORS do caminho.
 */
export const API_BASE_URL = new InjectionToken<string>('API_BASE_URL', {
  providedIn: 'root',
  factory: () => '/api',
});
