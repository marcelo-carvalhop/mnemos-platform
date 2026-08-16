import 'package:domain/domain.dart';
import 'package:drift/drift.dart';
import 'package:store/store.dart';

/// Every metric of §9, derived from `reviews` + `card_states`, with
/// `goal_history` as the only additional input. No counters, no ledger,
/// nothing to reconcile.

/// "Memória acumulada" — the headline (§9).
class AccumulatedMemory {
  const AccumulatedMemory(this.days);

  /// Sum of stability over active cards, in days.
  final double days;

  /// Rounded to whole months first, so the carry works out on its own: 11.9
  /// months becomes one year rather than "0 anos e 12 meses".
  ///
  /// Rounded rather than truncated, because this is the headline on the user's
  /// profile — 3 years and 1.97 months truncates to "1 mês" and throws away
  /// four weeks of real memory.
  int get _totalMonths => (days / 30.44).round();

  int get years => _totalMonths ~/ 12;
  int get months => _totalMonths % 12;

  /// "3 anos e 2 meses".
  String get label {
    if (days < 30) return '${days.round()} dias';
    if (years == 0) return _plural(months, 'mês', 'meses');
    if (months == 0) return _plural(years, 'ano', 'anos');
    return '${_plural(years, "ano", "anos")} e ${_plural(months, "mês", "meses")}';
  }

  static String _plural(int n, String one, String many) =>
      '$n ${n == 1 ? one : many}';
}

class DeckMaturity {
  const DeckMaturity({required this.deckId, required this.total, required this.mature});
  final String deckId;
  final int total;
  final int mature;

  /// §5.2 asks for the proportion **mature**, never "concluído" — nothing is
  /// ever concluded in spaced repetition.
  double get ratio => total == 0 ? 0 : mature / total;
}

class Leech {
  const Leech({required this.cardId, required this.lapses, required this.reps});
  final String cardId;
  final int lapses;
  final int reps;
  double get lapseRate => reps == 0 ? 0 : lapses / reps;
}

class ProgressService {
  ProgressService(this.db, {required this.day});

  final AppDatabase db;
  final DayBucket day;

  int _ms(DateTime t) => t.toUtc().millisecondsSinceEpoch;

  // -------------------------------------------------------------------------
  // The headline (§9)
  // -------------------------------------------------------------------------

  /// Sum of stability across active cards.
  ///
  /// FSRS stability *is* a duration: days until retrievability decays to 90%,
  /// by the algorithm's definition and **independent of the configured
  /// retention target**. The interval derives from the target; the stability
  /// does not. If the target ever becomes user-facing, lowering it would
  /// lengthen every interval without moving this number — and had the metric
  /// been defined as "days until the target", the headline on the user's
  /// profile would silently change meaning.
  ///
  /// This is also why §2.3 holds: a new card contributes ≈0, so creating a
  /// thousand cards moves nothing, and a lapse cuts stability and lowers it.
  Future<AccumulatedMemory> accumulatedMemory() async {
    final row = await db.customSelect(
      '''
      SELECT COALESCE(SUM(s.stability), 0) AS total
      FROM card_states s
      JOIN cards c ON c.id = s.card_id
      LEFT JOIN card_flags f ON f.card_id = s.card_id
      WHERE c.deleted_at IS NULL
        AND COALESCE(f.status, 'active') != 'suspended'
      ''',
      readsFrom: {db.cardStates, db.cards, db.cardFlags},
    ).getSingle();
    return AccumulatedMemory(row.read<double>('total'));
  }

  /// Share of reviews the user actually remembered.
  ///
  /// An accuracy rate, which is what a user understands. Calibration —
  /// comparing predicted retrievability against what happened — is a separate,
  /// internal signal and is not shown (§9).
  /// Null when there is nothing to measure.
  ///
  /// Returning 0.0 for an account with no reviews is not a small inaccuracy:
  /// rendered, it tells someone who has never answered a card that they get
  /// everything wrong. "No data" and "zero" are different facts and the type
  /// says so, so no caller can render one as the other by accident.
  Future<double?> retention({DateTime? since}) async {
    final row = await db.customSelect(
      '''
      SELECT
        COUNT(*) AS total,
        SUM(CASE WHEN grade > 1 THEN 1 ELSE 0 END) AS remembered
      FROM reviews
      WHERE source = 'standard' AND (?1 IS NULL OR reviewed_at >= ?1)
      ''',
      variables: [Variable<int>(since == null ? null : _ms(since))],
      readsFrom: {db.reviews},
    ).getSingle();

    final total = row.read<int>('total');
    if (total == 0) return null;
    return (row.read<int?>('remembered') ?? 0) / total;
  }

  /// §4 — maturity is a query predicate, never a stored column.
  Future<List<DeckMaturity>> maturityByDeck() async {
    final rows = await db.customSelect(
      '''
      SELECT c.deck_id AS deck_id,
             COUNT(*) AS total,
             SUM(CASE
                   WHEN s.due_at IS NOT NULL AND s.last_review_at IS NOT NULL
                    AND (s.due_at - s.last_review_at) > ?1
                   THEN 1 ELSE 0 END) AS mature
      FROM cards c
      LEFT JOIN card_states s ON s.card_id = c.id
      WHERE c.deleted_at IS NULL
      GROUP BY c.deck_id
      ''',
      variables: [Variable<int>(kMatureIntervalDays * 86400000)],
      readsFrom: {db.cards, db.cardStates},
    ).get();

    return rows
        .map((r) => DeckMaturity(
              deckId: r.read<String>('deck_id'),
              total: r.read<int>('total'),
              mature: r.read<int?>('mature') ?? 0,
            ))
        .toList();
  }

  /// Reviews per local day (§5.7) — the heatmap.
  Future<Map<String, int>> heatmap({required DateTime from, required DateTime to}) async {
    final rows = await db.customSelect(
      'SELECT reviewed_at FROM reviews WHERE reviewed_at >= ?1 AND reviewed_at < ?2',
      variables: [Variable<int>(_ms(from)), Variable<int>(_ms(to))],
      readsFrom: {db.reviews},
    ).get();

    final counts = <String, int>{};
    for (final row in rows) {
      final key = day.keyFor(
        DateTime.fromMillisecondsSinceEpoch(row.read<int>('reviewed_at'), isUtc: true),
      );
      counts[key] = (counts[key] ?? 0) + 1;
    }
    return counts;
  }

  /// How many cards fall due on each of the coming days.
  ///
  /// §5.11 uses this as a warning when someone is creating material faster
  /// than they can sustain.
  Future<Map<String, int>> loadForecast({required DateTime from, int days = 14}) async {
    final until = from.add(Duration(days: days));
    final rows = await db.customSelect(
      '''
      SELECT s.due_at FROM card_states s
      JOIN cards c ON c.id = s.card_id
      LEFT JOIN card_flags f ON f.card_id = s.card_id
      WHERE c.deleted_at IS NULL
        AND COALESCE(f.status, 'active') = 'active'
        AND s.due_at IS NOT NULL AND s.due_at >= ?1 AND s.due_at < ?2
      ''',
      variables: [Variable<int>(_ms(from)), Variable<int>(_ms(until))],
      readsFrom: {db.cardStates, db.cards, db.cardFlags},
    ).get();

    final counts = <String, int>{};
    for (final row in rows) {
      final key = day.keyFor(
        DateTime.fromMillisecondsSinceEpoch(row.read<int>('due_at'), isUtc: true),
      );
      counts[key] = (counts[key] ?? 0) + 1;
    }
    return counts;
  }

  /// "Cards com vazamento" (§5.11) — forgotten again and again despite review.
  Future<List<Leech>> leeches({int minLapses = 4}) async {
    final rows = await db.customSelect(
      '''
      SELECT s.card_id, s.lapses, s.reps FROM card_states s
      JOIN cards c ON c.id = s.card_id
      WHERE c.deleted_at IS NULL AND s.lapses >= ?1
      ORDER BY s.lapses DESC, s.card_id
      ''',
      variables: [Variable<int>(minLapses)],
      readsFrom: {db.cardStates, db.cards},
    ).get();

    return rows
        .map((r) => Leech(
              cardId: r.read<String>('card_id'),
              lapses: r.read<int>('lapses'),
              reps: r.read<int>('reps'),
            ))
        .toList();
  }

  // -------------------------------------------------------------------------
  // Engagement (§5.11)
  // -------------------------------------------------------------------------

  /// The daily goal in force on [dayKey].
  ///
  /// Reads `goal_history` rather than the current setting: comparing history
  /// against today's goal makes the streak rewrite itself — dropping the goal
  /// from 50 to 10 would retroactively turn every past day into a success, and
  /// raising it would erase a streak the user actually earned.
  ///
  /// The row in force is the greatest `(effective_from, created_at, id)` at or
  /// before the day, which stays identical on every device even when two of
  /// them change the goal on the same day.
  Future<int?> goalOn(String dayKey) async {
    final row = await db.customSelect(
      '''
      SELECT daily_goal FROM goal_history
      WHERE effective_from_local_date <= ?1
      ORDER BY effective_from_local_date DESC, created_at DESC, id DESC
      LIMIT 1
      ''',
      variables: [Variable<String>(dayKey)],
      readsFrom: {db.goalHistory},
    ).getSingleOrNull();
    return row?.read<int>('daily_goal');
  }

  Future<bool> goalMetOn(String dayKey) async {
    final goal = await goalOn(dayKey);
    if (goal == null) return false;

    final (start, end) = day.rangeOf(dayKey);
    final row = await db.customSelect(
      'SELECT COUNT(*) AS n FROM reviews WHERE reviewed_at >= ?1 AND reviewed_at < ?2',
      variables: [Variable<int>(_ms(start)), Variable<int>(_ms(end))],
      readsFrom: {db.reviews},
    ).getSingle();

    return row.read<int>('n') >= goal;
  }

  /// Consecutive days the **goal was met** — not days the app was opened
  /// (§5.11).
  ///
  /// Up to [forgivenessPerMonth] missed days are forgiven within each local
  /// month, so one bad week does not erase a year. The allowance is derived
  /// from the days themselves, not stored, so there is no balance to keep in
  /// sync across devices.
  Future<int> streak(DateTime now, {int forgivenessPerMonth = 2, int lookback = 400}) async {
    var streak = 0;
    final forgiven = <String, int>{};
    var cursor = now;

    for (var i = 0; i < lookback; i++) {
      final key = day.keyFor(cursor);
      final month = key.substring(0, 7);

      if (await goalMetOn(key)) {
        streak++;
      } else if (i == 0) {
        // Today does not break a streak that has not had its chance yet.
      } else {
        final used = forgiven[month] ?? 0;
        if (used < forgivenessPerMonth) {
          forgiven[month] = used + 1;
        } else {
          break;
        }
      }
      cursor = cursor.subtract(const Duration(days: 1));
    }
    return streak;
  }

  /// Cards that crossed a milestone in the given window (§5.11).
  ///
  /// Queried from `reviews.interval_days_after` rather than replayed: the
  /// snapshot is advisory (§5.2), and being wrong about a celebration is
  /// cheap, where replaying every card to find one would not be.
  Future<List<({String cardId, int milestone})>> graduations({
    required DateTime from,
    required DateTime to,
  }) async {
    final results = <({String cardId, int milestone})>[];

    for (final milestone in kGraduationMilestoneDays) {
      final rows = await db.customSelect(
        '''
        SELECT r.card_id, MIN(r.reviewed_at) AS first_at
        FROM reviews r
        WHERE r.interval_days_after >= ?1
          AND r.reviewed_at >= ?2 AND r.reviewed_at < ?3
          AND NOT EXISTS (
            SELECT 1 FROM reviews e
            WHERE e.card_id = r.card_id
              AND e.interval_days_after >= ?1
              AND e.reviewed_at < ?2
          )
        GROUP BY r.card_id
        ''',
        variables: [
          Variable<int>(milestone),
          Variable<int>(_ms(from)),
          Variable<int>(_ms(to)),
        ],
        readsFrom: {db.reviews},
      ).get();

      for (final row in rows) {
        results.add((cardId: row.read<String>('card_id'), milestone: milestone));
      }
    }
    return results;
  }

  /// "Card teimoso do mês" (§5.11) — the one missed most in the window.
  Future<String?> mostStubborn({required DateTime from, required DateTime to}) async {
    final row = await db.customSelect(
      '''
      SELECT card_id, COUNT(*) AS misses FROM reviews
      WHERE grade = 1 AND reviewed_at >= ?1 AND reviewed_at < ?2
      GROUP BY card_id
      ORDER BY misses DESC, card_id
      LIMIT 1
      ''',
      variables: [Variable<int>(_ms(from)), Variable<int>(_ms(to))],
      readsFrom: {db.reviews},
    ).getSingleOrNull();
    return row?.read<String>('card_id');
  }
}
