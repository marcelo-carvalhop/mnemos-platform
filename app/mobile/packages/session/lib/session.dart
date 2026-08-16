/// The study loop: records reviews, replays them into `card_state`, and queues
/// rows for push.
///
/// The seam between `scheduler` (pure, no IO) and `store` (persistence, no
/// FSRS). Nothing here is a source of truth — everything it writes derives
/// from the review log (§3).
library;

export 'src/study_service.dart';
