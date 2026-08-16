/// The transport (§4.3, §6, §8.2).
///
/// `sync_client` deliberately declares `SyncApi` and no HTTP: the interesting
/// failures in the sync loop are ordering and idempotency, not sockets. This
/// package is the other half — the part that knows about bearer tokens,
/// refresh rotation and status codes, and nothing about what a review is.
library;

export 'src/account_api.dart';
export 'src/api.dart';
export 'src/api_exception.dart';
export 'src/auth_api.dart';
export 'src/generation_api.dart';
export 'src/http_sync_api.dart';
export 'src/token_store.dart';
export 'src/terminal_api.dart';
