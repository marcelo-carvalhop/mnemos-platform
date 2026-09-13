import { ApiError, Offline } from './api';
import { errorCodeFromWire, type ErrorCode } from './contract.g';

/**
 * §10 — o cliente mapeia um código para a copy, e nunca mostra prosa do
 * servidor.
 *
 * Toda frase que uma pessoa lê sobre uma falha está escrita aqui. É a razão de
 * os códigos existirem: prosa escrita para log não é prosa escrita para gente,
 * e traduzir no ponto da falha faz cada tela escrever a sua, diferente.
 *
 * Este arquivo é o irmão de `app/mobile/lib/features/generation/error_copy.dart`
 * e as frases são as mesmas de propósito — quem usa os dois não deveria ler
 * duas explicações diferentes do mesmo problema.
 */
export interface GenerationFailure {
  readonly title: string;
  readonly detail: string;
  readonly canRetry: boolean;
  readonly showsPaywall: boolean;
}

const COPY: Record<ErrorCode, GenerationFailure> = {
  quota_exhausted: {
    title: 'Você usou sua geração grátis',
    detail: 'Criar cards à mão e estudar continuam livres, sempre.',
    canRetry: false,
    showsPaywall: true,
  },
  topic_too_vague: {
    title: 'Preciso de um recorte mais estreito',
    detail: 'Diga o período, a disciplina ou o capítulo. Sua geração não foi gasta.',
    canRetry: true,
    showsPaywall: false,
  },
  material_insufficient: {
    title: 'Não deu para tirar cards daqui',
    detail: 'O material é curto ou tem pouco conteúdo verificável. Sua geração não foi gasta.',
    canRetry: true,
    showsPaywall: false,
  },
  file_too_large: {
    title: 'Arquivo grande demais',
    detail: 'Tente um trecho menor, ou só os capítulos que interessam.',
    canRetry: true,
    showsPaywall: false,
  },
  page_limit_exceeded: {
    title: 'PDF com páginas demais',
    detail: 'Selecione o intervalo de páginas que você vai estudar.',
    canRetry: true,
    showsPaywall: false,
  },
  photo_unreadable: {
    title: 'Não consegui ler a foto',
    detail: 'Aproxime, evite sombra sobre o texto e mantenha a página plana.',
    canRetry: true,
    showsPaywall: false,
  },
  model_refused: {
    title: 'Não posso gerar cards sobre isso',
    detail: 'Sua geração não foi gasta.',
    canRetry: false,
    showsPaywall: false,
  },
  network_unavailable: {
    title: 'Sem conexão com o servidor',
    detail: 'Nada foi perdido e sua geração não foi gasta. Tente de novo.',
    canRetry: true,
    showsPaywall: false,
  },
  resync_required: {
    title: 'Preciso recarregar seus dados',
    detail: 'Este navegador ficou muito tempo sem sincronizar.',
    canRetry: true,
    showsPaywall: false,
  },
};

/**
 * Um código que esta versão não conhece ainda é uma falha, e §5.3 diz que um
 * cliente algumas versões atrás é normal — então existe uma frase para isso, e
 * não uma tela em branco.
 */
const UNKNOWN: GenerationFailure = {
  title: 'Algo deu errado',
  detail: 'Não consegui gerar os cards. Sua geração não foi gasta.',
  canRetry: true,
  showsPaywall: false,
};

export function failureForCode(wire: string | null | undefined): GenerationFailure {
  const code = errorCodeFromWire(wire);
  return code ? COPY[code] : UNKNOWN;
}

export function failureForError(error: unknown): GenerationFailure {
  if (error instanceof Offline) return COPY.network_unavailable;
  if (error instanceof ApiError) {
    if (error.isQuotaExhausted) return COPY.quota_exhausted;
    if (error.isTransient) return COPY.network_unavailable;
    return failureForCode(error.code);
  }
  return UNKNOWN;
}
