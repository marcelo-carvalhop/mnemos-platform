import { HttpErrorResponse, type HttpInterceptorFn } from '@angular/common/http';
import { inject } from '@angular/core';
import { catchError, from, switchMap, throwError } from 'rxjs';
import { API_BASE_URL } from './config';
import { Session } from './session';

/**
 * Põe o bearer e renova uma vez quando o servidor recusa (§8.2).
 *
 * A rotação acontece aqui e não em cada chamada porque um 401 pode chegar em
 * qualquer requisição, inclusive numa que a pessoa não disparou — o polling de
 * uma geração, por exemplo. Repetir esse tratamento em cada serviço é como se
 * perde um deles.
 *
 * Só uma retentativa: se o pedido repetido também voltar 401, o problema não é
 * o token vencido, e insistir viraria laço.
 */
export const authInterceptor: HttpInterceptorFn = (req, next) => {
  const session = inject(Session);
  const baseUrl = inject(API_BASE_URL);

  // O token só sai para o nosso servidor. Um interceptor que carimba tudo
  // entrega credencial para qualquer host que a página venha a chamar.
  if (!req.url.startsWith(baseUrl)) return next(req);

  // Estas rotas estabelecem a sessão e não podem depender dela: mandar um
  // access vencido para `refresh` é o laço que estamos evitando.
  //
  // `signup` fica de fora da lista de propósito — ele **anexa** credenciais a
  // uma conta anônima existente (§8.1) e exige o bearer dela. Tratá-lo como
  // "rota de autenticação" e tirar o cabeçalho devolve 401, que foi o que
  // aconteceu na primeira tentativa contra o servidor real.
  const establishesSession =
    req.url.includes('/v1/auth/device') ||
    req.url.includes('/v1/auth/login') ||
    req.url.includes('/v1/auth/refresh') ||
    req.url.includes('/v1/auth/challenge');
  if (establishesSession) return next(req);

  const withToken = (token: string | null) =>
    token ? req.clone({ setHeaders: { Authorization: `Bearer ${token}` } }) : req;

  return next(withToken(session.token())).pipe(
    catchError((error: unknown) => {
      if (!(error instanceof HttpErrorResponse) || error.status !== 401) {
        return throwError(() => error);
      }
      return from(session.refreshOnce()).pipe(
        switchMap((renewed) =>
          renewed ? next(withToken(session.token())) : throwError(() => error),
        ),
      );
    }),
  );
};
