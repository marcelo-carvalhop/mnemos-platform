import 'package:modes/modes.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'providers.dart';

/// Composition for §5.9.
///
/// Note what each provider is given. [multipleChoiceProvider] receives the
/// [StudyService]; the other three receive only the database. The guarantee
/// that extra practice cannot touch the schedule is enforced by what these
/// objects are handed, not by remembering not to call something.
final multipleChoiceProvider = FutureProvider<MultipleChoiceMode>((ref) async {
  return MultipleChoiceMode(
    ref.watch(databaseProvider),
    study: await ref.watch(studyServiceProvider.future),
  );
});

final leechDrillProvider = Provider<LeechDrill>((ref) {
  return LeechDrill(ref.watch(databaseProvider));
});

final simuladoProvider = Provider<SimuladoMode>((ref) {
  return SimuladoMode(ref.watch(databaseProvider));
});

final audioSessionProvider = Provider<AudioSessionBuilder>((ref) {
  return AudioSessionBuilder(ref.watch(databaseProvider));
});

/// The cards the drill would offer, worst first.
final leechesProvider = FutureProvider<List<LeechCard>>((ref) async {
  return ref.watch(leechDrillProvider).select();
});
