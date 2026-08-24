// GENERATED FROM shared/contract.yaml — DO NOT EDIT.
// Regenerate with: python shared/generate.py

/// Contract version; bumped when this file's shape changes.
const int kContractVersion = 1;

/// §7.6 — counted in grapheme clusters over NFC-normalised text.
const int kFrontMaxGraphemes = 120;
const int kBackMaxGraphemes = 240;

/// §4 — maturity is a query predicate, never a stored column.
const int kMatureIntervalDays = 21;
const double kDesiredRetention = 0.9;
const List<int> kGraduationMilestoneDays = [180, 365];

/// §4.1 — o vetor FSRS padrão. Declarado no contrato porque cada plataforma
/// usa um pacote diferente e os padrões deles não coincidem.
const List<double> kFsrsWeights = [0.2172, 1.1771, 3.2602, 16.1507, 7.0114, 0.57, 2.0966, 0.0069, 1.5261, 0.112, 1.0178, 1.849, 0.1133, 0.3127, 2.2934, 0.2191, 3.0004, 0.7536, 0.3332, 0.1437, 0.2];

/// §5.7 — the day rolls over at 04:00 local, not midnight.
const int kDefaultDayCutoffHour = 4;

/// §7.7 — one generation for the lifetime of the account, not per month.
const int kFreeGenerationsLifetime = 1;
const int kMaxJobsInFlight = 2;

/// §7.3 — teto do assunto ou do texto colado. Sem ele o corpo da requisição
/// vira o prompt, e o custo de uma geração é medido em tokens.
const int kTopicMaxChars = 20000;

/// §5.9 — alternative modes. The grade mapping is a scheduling decision, so
/// its numbers live in the contract rather than in a widget.
const int kMultipleChoiceOptions = 4;
const int kMultipleChoiceFastAnswerMs = 10000;
const int kLeechMinLapses = 4;
const int kSimuladoDefaultQuestions = 20;
const int kSimuladoDefaultMinutes = 20;
const int kTtsAnswerPauseMs = 3000;

/// §5.2 — the wire value is the contract. Never renumber.
enum Grade {
  /// Errei (wire value 1)
  again(1),
  /// Difícil (wire value 2)
  hard(2),
  /// Bom (wire value 3)
  good(3),
  /// Fácil (wire value 4)
  easy(4),
  ;

  const Grade(this.value);

  /// Persisted and transmitted as this smallint.
  final int value;

  static Grade fromValue(int value) => Grade.values.firstWhere(
        (g) => g.value == value,
        orElse: () => throw ArgumentError('unknown grade value: $value'),
      );
}

/// §5.2 — a review row exists only for modes that feed the scheduler.
enum ReviewSource {
  standard('standard'),
  multipleChoice('multiple_choice'),
  ;

  const ReviewSource(this.wire);

  /// The string on the wire and in the database.
  final String wire;

  static ReviewSource fromWire(String wire) => values.firstWhere(
        (v) => v.wire == wire,
        orElse: () => throw ArgumentError('unknown review source: $wire'),
      );
}

/// §5.1
enum CardStatus {
  active('active'),
  suspended('suspended'),
  buried('buried'),
  ;

  const CardStatus(this.wire);

  final String wire;

  static CardStatus fromWire(String wire) => values.firstWhere(
        (v) => v.wire == wire,
        orElse: () => throw ArgumentError('unknown card status: $wire'),
      );
}

/// §10 — the client maps codes to copy; it never matches on server prose.
enum ErrorCode {
  quotaExhausted('quota_exhausted'),
  topicTooVague('topic_too_vague'),
  materialInsufficient('material_insufficient'),
  fileTooLarge('file_too_large'),
  pageLimitExceeded('page_limit_exceeded'),
  photoUnreadable('photo_unreadable'),
  modelRefused('model_refused'),
  networkUnavailable('network_unavailable'),
  resyncRequired('resync_required'),
  ;

  const ErrorCode(this.wire);

  final String wire;

  /// Null for a code this build has never heard of. §5.3 makes that the
  /// normal case, not a corruption — so it is a lookup that can miss, never
  /// a throw.
  static ErrorCode? fromWire(String? wire) {
    for (final value in values) {
      if (value.wire == wire) return value;
    }
    return null;
  }
}
