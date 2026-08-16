import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'providers.dart';

/// Composition for §9's metrics.
///
/// One provider per question the progress screen asks, so a slow query does
/// not hold up the rest of the screen and a failing one does not blank it.

/// §9 — measured over the review log, not over what the user hoped for.
///
/// Null until there is something to measure.
final retentionProvider = FutureProvider<double?>((ref) async {
  final service = await ref.watch(progressServiceProvider.future);
  return service.retention(
    since: ref.watch(clockProvider)().subtract(const Duration(days: 90)),
  );
});

/// §5.11 — consecutive days, with the forgiveness §9 argues for: a streak that
/// breaks on one missed day teaches people to fear the app.
final streakProvider = FutureProvider<int>((ref) async {
  final service = await ref.watch(progressServiceProvider.future);
  return service.streak(ref.watch(clockProvider)());
});

/// What is coming, so nobody is ambushed by four hundred cards on a Monday.
final forecastProvider = FutureProvider<Map<String, int>>((ref) async {
  final service = await ref.watch(progressServiceProvider.future);
  return service.loadForecast(from: ref.watch(clockProvider)(), days: 14);
});

/// The last twelve weeks of answered days.
final heatmapProvider = FutureProvider<Map<String, int>>((ref) async {
  final service = await ref.watch(progressServiceProvider.future);
  final now = ref.watch(clockProvider)();
  return service.heatmap(from: now.subtract(const Duration(days: 83)), to: now);
});

/// §5.11's milestones: cards that crossed six months and a year.
///
/// Windowed to the last month, because the interesting question is what
/// happened recently — a card that graduated a year ago is not news.
final graduationsProvider =
    FutureProvider<List<({String cardId, int milestone})>>((ref) async {
  final service = await ref.watch(progressServiceProvider.future);
  final now = ref.watch(clockProvider)();
  return service.graduations(from: now.subtract(const Duration(days: 30)), to: now);
});
