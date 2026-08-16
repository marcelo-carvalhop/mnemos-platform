import 'dart:async';

import 'package:api_client/api_client.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sync_client/sync_client.dart';

/// What the interface is allowed to say about syncing (§2.2, §5.14).
///
/// Offline is not an error state. The app works entirely against local SQLite;
/// the server is a backup and a meeting point. So the states are deliberately
/// undramatic, and only [failed] is worth a colour.
enum SyncPhase { idle, syncing, offline, failed, resyncing }

class SyncState {
  const SyncState({
    this.phase = SyncPhase.idle,
    this.pending = 0,
    this.lastSuccess,
    this.message,
  });

  final SyncPhase phase;

  /// Rows still in the outbox. This is the honest number to show: "3 mudanças
  /// esperando" is true offline, and says nothing alarming.
  final int pending;
  final DateTime? lastSuccess;
  final String? message;

  SyncState copyWith({
    SyncPhase? phase,
    int? pending,
    DateTime? lastSuccess,
    String? message,
  }) =>
      SyncState(
        phase: phase ?? this.phase,
        pending: pending ?? this.pending,
        lastSuccess: lastSuccess ?? this.lastSuccess,
        message: message,
      );
}

/// Drives the sync loop and reports what happened.
///
/// The loop itself lives in `sync_client`, which knows the ordering rules and
/// is tested without a network. This owns the *when*: after a session, on
/// resume, and never twice at once.
class SyncController extends StateNotifier<SyncState> {
  SyncController(this._client, {required this.isSignedIn}) : super(const SyncState());

  final SyncClient _client;

  /// There is nothing to sync before an account exists, and trying would only
  /// produce 401s on a first launch that is working perfectly well offline.
  final Future<bool> Function() isSignedIn;

  Future<void>? _running;

  /// Bumped every time a sync writes the state. A pending count read before
  /// the bump is stale, whether or not the sync is still running when the
  /// read finishes — which is the part that made two earlier attempts at this
  /// wrong.
  int _epoch = 0;

  /// Coalesces callers: a session ending while a resume-triggered sync is
  /// still in flight joins it instead of starting a second one.
  Future<void> syncNow() => _running ??= _run().whenComplete(() => _running = null);

  Future<void> _run() async {
    if (!await isSignedIn()) {
      state = state.copyWith(pending: await _client.outboxDepth());
      return;
    }

    state = state.copyWith(phase: SyncPhase.syncing);
    try {
      await _client.syncNow();
      _publish(SyncState(
        phase: SyncPhase.idle,
        pending: await _client.outboxDepth(),
        lastSuccess: DateTime.now(),
      ));
    } on ResyncRequired {
      // §6.3 — the cursor predates the tombstone horizon, so an incremental
      // pull would silently miss deletions. `sync_client` starts over; this
      // only reports it, because a full resync can take a moment and a silent
      // pause looks like a hang.
      state = state.copyWith(phase: SyncPhase.resyncing);
      try {
        await _client.syncNow();
        _publish(SyncState(
          phase: SyncPhase.idle,
          pending: await _client.outboxDepth(),
          lastSuccess: DateTime.now(),
        ));
      } on Object catch (e) {
        _publish(state.copyWith(phase: SyncPhase.failed, message: '$e'));
      }
    } on Offline {
      // Ordinary. Nothing was lost — the outbox is exactly where it was.
      _publish(state.copyWith(
        phase: SyncPhase.offline,
        pending: await _client.outboxDepth(),
      ));
    } on ApiException catch (e) {
      _publish(state.copyWith(
        phase: e.isTransient ? SyncPhase.offline : SyncPhase.failed,
        pending: await _client.outboxDepth(),
        message: e.code ?? e.detail,
      ));
    } on Object catch (e) {
      // Everything else. Sync is started fire-and-forget, so an exception
      // that escapes here goes nowhere at all — that is how a pull that died
      // on an unknown column stayed invisible while the badge cheerfully
      // reported nothing pending.
      _publish(state.copyWith(phase: SyncPhase.failed, message: '$e'));
    }
  }

  /// Refreshes the pending count without touching the network — for showing
  /// "n mudanças esperando" right after a review.
  ///
  /// Reads the outbox depth, and discards the answer if a sync spoke while it
  /// was reading.
  ///
  /// Both run at the end of a session, this one first. Two earlier versions
  /// got it wrong. Checking `_running` on the way in is check-then-act. So is
  /// checking it again afterwards: by then the sync has usually *finished*, so
  /// there is nothing in flight to see — only the epoch records that it
  /// happened. On a device the symptom was "4 mudanças para enviar" with all
  /// four already on the server.
  Future<void> refreshPending() async {
    final at = _epoch;
    final depth = await _client.outboxDepth();
    if (_epoch != at || _running != null) return;
    state = state.copyWith(pending: depth);
  }

  void _publish(SyncState next) {
    _epoch++;
    state = next;
  }
}
