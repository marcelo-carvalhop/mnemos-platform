/// Every metric of §9, derived from `reviews` + `card_states`, with
/// `goal_history` as the only additional input.
///
/// No counters and no ledger: nothing here can drift out of step with the log,
/// because nothing here is stored.
library;

export 'src/progress_service.dart';
