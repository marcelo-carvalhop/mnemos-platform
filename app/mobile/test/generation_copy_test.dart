import 'package:api_client/api_client.dart';
import 'package:domain/domain.dart';
import 'package:flashcards/features/generation/error_copy.dart';
import 'package:flutter_test/flutter_test.dart';

/// §10 — the client maps a code to copy and never shows server prose.
///
/// Worth pinning rather than eyeballing: with one generation for the lifetime
/// of the account, whether a failure spent it is the first thing a user wants
/// to know, and getting that sentence wrong is worse than no sentence.
void main() {
  test('every contract error code has copy of its own', () {
    // A code that falls through to the generic message is a code nobody wrote
    // a sentence for.
    final generic = GenerationFailure.forCode('nao-existe').title;

    for (final code in ErrorCode.values) {
      final failure = GenerationFailure.forError(code);
      expect(failure.title, isNot(generic), reason: 'sem copy para ${code.wire}');
      expect(failure.detail, isNotEmpty);
    }
  });

  test('an unknown code still says something', () {
    // §5.3 — a client several versions behind is normal, so it will meet
    // codes it has never heard of.
    final failure = GenerationFailure.forCode('inventado_no_futuro');
    expect(failure.title, isNotEmpty);
    expect(failure.canRetry, isTrue);
  });

  test('only quota exhaustion opens the paywall', () {
    for (final code in ErrorCode.values) {
      expect(
        GenerationFailure.forError(code).showsPaywall,
        code == ErrorCode.quotaExhausted,
        reason: code.wire,
      );
    }
  });

  test('the failures that did not spend the generation say so', () {
    // §7.7 refunds anything that is not the user spending it. Silence here
    // reads as "you lost it".
    for (final code in [
      ErrorCode.topicTooVague,
      ErrorCode.materialInsufficient,
      ErrorCode.modelRefused,
      ErrorCode.networkUnavailable,
    ]) {
      expect(
        GenerationFailure.forError(code).detail,
        contains('não foi gasta'),
        reason: code.wire,
      );
    }
  });

  test('being offline is a network failure, not a mystery', () {
    final failure = GenerationFailure.forException(const Offline('sem rota'));
    expect(failure.canRetry, isTrue);
    expect(failure.detail, contains('Nada foi perdido'));
  });

  test('402 is the paywall however it arrives', () {
    expect(
      GenerationFailure.forException(const ApiException(402)).showsPaywall,
      isTrue,
    );
  });

  test('a 503 is worth retrying and does not accuse the user', () {
    final failure = GenerationFailure.forException(const ApiException(503));
    expect(failure.canRetry, isTrue);
    expect(failure.showsPaywall, isFalse);
  });
}
