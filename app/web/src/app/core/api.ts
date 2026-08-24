import { HttpErrorResponse } from '@angular/common/http';

/**
 * As falhas que a interface precisa distinguir (§10).
 *
 * Estar offline **não é um erro**: o servidor é backup e ponto de encontro, e
 * uma tela que trata falta de rede como defeito assusta por algo cotidiano.
 * Por isso `Offline` é um tipo próprio, e não um `ApiError` com código 0.
 */
export class Offline extends Error {
  constructor(cause?: unknown) {
    super('sem conexão com o servidor');
    this.name = 'Offline';
    this.cause = cause;
  }
}

export class ApiError extends Error {
  constructor(
    readonly status: number,
    readonly code: string | null = null,
    readonly detail: string | null = null,
  ) {
    super(detail ?? `HTTP ${status}`);
    this.name = 'ApiError';
  }

  /** §7.7 — o paywall, não um erro. */
  get isQuotaExhausted(): boolean {
    return this.status === 402 || this.code === 'quota_exhausted';
  }

  /** Vale tentar de novo: o servidor tropeçou, o pedido não estava errado. */
  get isTransient(): boolean {
    return this.status >= 500 || this.status === 429 || this.status === 408;
  }

  get isUnauthorized(): boolean {
    return this.status === 401;
  }
}

/**
 * Traduz o erro do `HttpClient` para o vocabulário acima.
 *
 * `status === 0` é o navegador dizendo que a requisição não saiu — DNS, rede,
 * CORS. Nenhum deles é uma resposta do servidor, e chamar isso de "erro 0"
 * levaria a interface a mostrar um número que não existe.
 */
export function toFailure(error: unknown): Offline | ApiError {
  if (error instanceof Offline || error instanceof ApiError) return error;
  if (!(error instanceof HttpErrorResponse)) return new ApiError(0, null, String(error));
  if (error.status === 0) return new Offline(error);

  const body = error.error as { detail?: unknown; error_code?: unknown; code?: unknown } | null;
  const detail = typeof body?.detail === 'string' ? body.detail : null;
  const code =
    typeof body?.error_code === 'string'
      ? body.error_code
      : typeof body?.code === 'string'
        ? body.code
        : null;

  return new ApiError(error.status, code, detail);
}
