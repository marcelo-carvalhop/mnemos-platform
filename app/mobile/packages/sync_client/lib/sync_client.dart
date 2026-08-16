/// The client half of §6: drains the outbox into the server and applies
/// deltas back.
///
/// The server is a backup and a meeting point; local SQLite is the source of
/// truth. This is the only place that knows the order those two things must
/// happen in.
library;

export 'src/sync_client.dart';
