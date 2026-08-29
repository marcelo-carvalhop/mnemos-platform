import 'package:domain/domain.dart';
import 'package:store/store.dart';

/// One thing to do: say something, or wait.
sealed class AudioStep {
  const AudioStep();
}

/// Text to speak, tagged with the card it belongs to so the interface can
/// show what is being read without deciding the order itself.
class Speak extends AudioStep {
  const Speak({required this.cardId, required this.text, required this.isFront});

  final String cardId;
  final String text;
  final bool isFront;

  @override
  String toString() => 'Speak(${isFront ? "front" : "back"}: $text)';
}

/// The gap between the question and the answer — the whole point of the mode.
class Pause extends AudioStep {
  const Pause(this.duration);

  final Duration duration;

  @override
  String toString() => 'Pause(${duration.inMilliseconds}ms)';
}

/// Audio (TTS) — §5.9, §11.6.
///
/// "Lê frente, faz pausa, lê verso." For commuting and the gym, so there is no
/// grade button: the user has headphones in and their hands elsewhere. The
/// session is passive and **generates no review**.
///
/// This class is the whole mode except for the speaking. It produces a
/// playlist, which makes the ordering and the pauses testable in plain Dart;
/// `flutter_tts` is on-device (§11.6) and lives in the app, given the list to
/// read. Nothing is sent anywhere.
class AudioSessionBuilder {
  const AudioSessionBuilder(this.db);

  final AppDatabase db;

  Future<List<AudioStep>> build(
    List<String> cardIds, {
    Duration answerPause = const Duration(milliseconds: kTtsAnswerPauseMs),
    Duration betweenCards = const Duration(milliseconds: 1200),
  }) async {
    if (cardIds.isEmpty) return const [];

    final cards = await (db.select(db.cards)
          ..where((t) => t.id.isIn(cardIds))
          ..where((t) => t.deletedAt.isNull()))
        .get();
    final byId = {for (final c in cards) c.id: c};

    final steps = <AudioStep>[];
    for (final id in cardIds) {
      final card = byId[id];
      if (card == null) continue;

      if (steps.isNotEmpty) steps.add(Pause(betweenCards));
      steps.add(Speak(cardId: id, text: card.front, isFront: true));
      steps.add(Pause(answerPause));
      steps.add(Speak(cardId: id, text: card.back, isFront: false));
    }
    return steps;
  }
}
