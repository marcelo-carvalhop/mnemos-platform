/// Alternative study modes (§5.9).
///
/// They all start from the same cards, and the line that matters runs through
/// the middle of them: **multiple choice feeds the scheduler, the other three
/// do not**. That is not a flag anyone has to remember to check — it is
/// whether a `reviews` row exists at all (§5.2). Only [MultipleChoiceMode]
/// takes a [StudyService]; the drill, the simulado and the audio session are
/// given no way to write one.
library;

export 'src/audio_session.dart';
export 'src/leech_drill.dart';
export 'src/multiple_choice.dart';
export 'src/simulado.dart';
