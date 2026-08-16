import 'package:api_client/api_client.dart';
import 'package:domain/domain.dart';

/// §10 — the client maps a code to copy, and never shows server prose.
///
/// The server sends a machine-readable `ErrorCode`; every string a user reads
/// about a failure is written here. That is the whole reason the codes exist:
/// prose written for a log is not prose written for a person, and translating
/// it at the point of failure means it gets written twice, differently.
class GenerationFailure {
  const GenerationFailure({
    required this.title,
    required this.detail,
    this.canRetry = false,
    this.showsPaywall = false,
  });

  final String title;
  final String detail;

  /// Whether trying the same thing again could plausibly work.
  final bool canRetry;
  final bool showsPaywall;

  /// Switches on the enum, not on a string.
  ///
  /// The wire value lives on the contract enum, so a code added to
  /// `contract.yaml` and regenerated turns up here as a missing case rather
  /// than as a generic message nobody notices in production.
  static GenerationFailure forCode(String? code) => forError(ErrorCode.fromWire(code));

  static GenerationFailure forError(ErrorCode? code) {
    return switch (code) {
      ErrorCode.quotaExhausted => const GenerationFailure(
          title: 'Você usou sua geração grátis',
          detail: 'Criar cards à mão e estudar continuam livres, sempre.',
          showsPaywall: true,
        ),
      ErrorCode.topicTooVague => const GenerationFailure(
          title: 'Preciso de um recorte mais estreito',
          detail: 'Diga o período, a disciplina ou o capítulo. '
              'Sua geração não foi gasta.',
          canRetry: true,
        ),
      ErrorCode.materialInsufficient => const GenerationFailure(
          title: 'Não deu para tirar cards daqui',
          detail: 'O material é curto ou tem pouco conteúdo verificável. '
              'Sua geração não foi gasta.',
          canRetry: true,
        ),
      ErrorCode.fileTooLarge => const GenerationFailure(
          title: 'Arquivo grande demais',
          detail: 'Tente um trecho menor, ou só os capítulos que interessam.',
          canRetry: true,
        ),
      ErrorCode.pageLimitExceeded => const GenerationFailure(
          title: 'PDF com páginas demais',
          detail: 'Selecione o intervalo de páginas que você vai estudar.',
          canRetry: true,
        ),
      ErrorCode.photoUnreadable => const GenerationFailure(
          title: 'Não consegui ler a foto',
          detail: 'Aproxime, evite sombra sobre o texto e mantenha a página plana.',
          canRetry: true,
        ),
      ErrorCode.modelRefused => const GenerationFailure(
          title: 'Não posso gerar cards sobre isso',
          detail: 'Sua geração não foi gasta.',
        ),
      ErrorCode.networkUnavailable => const GenerationFailure(
          title: 'Sem conexão com o servidor',
          detail: 'Nada foi perdido e sua geração não foi gasta. Tente de novo.',
          canRetry: true,
        ),
      ErrorCode.resyncRequired => const GenerationFailure(
          title: 'Preciso recarregar seus dados',
          detail: 'Este aparelho ficou muito tempo sem sincronizar.',
          canRetry: true,
        ),
      // A code this build does not know is still a failure, and §5.3 says a
      // client several versions behind is normal — so there is a sentence for
      // it rather than a blank screen.
      null => const GenerationFailure(
          title: 'Algo deu errado',
          detail: 'Não consegui gerar os cards. Sua geração não foi gasta.',
          canRetry: true,
        ),
    };
  }

  /// For a failure that never reached the server.
  static GenerationFailure forException(Object error) {
    if (error is Offline) return forError(ErrorCode.networkUnavailable);
    if (error is ApiException) {
      if (error.isQuotaExhausted) return forError(ErrorCode.quotaExhausted);
      if (error.isTransient) return forError(ErrorCode.networkUnavailable);
      return forCode(error.code);
    }
    return forError(null);
  }
}
