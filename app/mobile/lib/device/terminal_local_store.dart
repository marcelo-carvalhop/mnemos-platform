import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:store/store.dart';

class StoredTerminal {
  const StoredTerminal({
    required this.deviceId,
    required this.model,
    required this.firmware,
    required this.protocol,
    required this.maxCards,
    required this.bleSync,
    required this.lastSeenAt,
  });

  final String deviceId;
  final String model;
  final String firmware;
  final int protocol;
  final int maxCards;
  final bool bleSync;
  final DateTime lastSeenAt;

  Map<String, Object?> toJson() => {
        'deviceId': deviceId,
        'model': model,
        'firmware': firmware,
        'protocol': protocol,
        'maxCards': maxCards,
        'bleSync': bleSync,
        'lastSeenAt': lastSeenAt.toUtc().toIso8601String(),
      };

  factory StoredTerminal.fromJson(Map<String, Object?> json) => StoredTerminal(
        deviceId: json['deviceId'] as String,
        model: (json['model'] as String?) ?? 'Mnemos Terminal',
        firmware: (json['firmware'] as String?) ?? 'desconhecido',
        protocol: (json['protocol'] as num?)?.toInt() ?? 0,
        maxCards: (json['maxCards'] as num?)?.toInt() ?? 0,
        bleSync: json['bleSync'] as bool? ?? ((json['protocol'] as num?)?.toInt() ?? 0) >= 3,
        lastSeenAt: DateTime.tryParse(json['lastSeenAt']?.toString() ?? '') ?? DateTime.fromMillisecondsSinceEpoch(0),
      );
}

/// Small local registry for terminal intent/state.
///
/// It deliberately reuses LocalSettings instead of introducing new Drift
/// tables in v0.4. That keeps the migration additive and avoids coupling the
/// public Mnemos protocol to the app's database layout.
class TerminalLocalStore {
  const TerminalLocalStore(this.db);

  final AppDatabase db;

  static const _activeDeviceKey = 'terminal.active_device';

  String _identityKey(String id) => 'terminal.$id.identity';
  String _desiredDecksKey(String id) => 'terminal.$id.desired_decks';
  String _actualDecksKey(String id) => 'terminal.$id.actual_decks';
  String _desiredUpdatedKey(String id) => 'terminal.$id.desired_updated_at';
  String _lastSyncKey(String id) => 'terminal.$id.last_sync';

  Future<String?> _read(String key) async {
    final row = await (db.select(db.localSettings)..where((t) => t.key.equals(key))).getSingleOrNull();
    return row?.value;
  }

  Future<void> _write(String key, String value) async {
    await db.into(db.localSettings).insert(
          LocalSettingsCompanion.insert(key: key, value: value),
          mode: InsertMode.insertOrReplace,
        );
  }

  Future<String?> activeDeviceId() => _read(_activeDeviceKey);

  Future<void> setActiveDevice(String deviceId) => _write(_activeDeviceKey, deviceId);

  Future<void> saveTerminal(StoredTerminal terminal) async {
    await _write(_identityKey(terminal.deviceId), jsonEncode(terminal.toJson()));
    await setActiveDevice(terminal.deviceId);
  }

  Future<StoredTerminal?> terminal(String deviceId) async {
    final raw = await _read(_identityKey(deviceId));
    if (raw == null) return null;
    try {
      final decoded = jsonDecode(raw);
      return decoded is Map ? StoredTerminal.fromJson(Map<String, Object?>.from(decoded)) : null;
    } catch (_) {
      return null;
    }
  }

  Future<StoredTerminal?> activeTerminal() async {
    final id = await activeDeviceId();
    return id == null ? null : terminal(id);
  }

  Future<Set<String>> desiredDeckIds(String deviceId) => _readSet(_desiredDecksKey(deviceId));
  Future<Set<String>> actualDeckIds(String deviceId) => _readSet(_actualDecksKey(deviceId));

  Future<bool> hasDesiredDeckIntent(String deviceId) async =>
      (await _read(_desiredDecksKey(deviceId))) != null;

  Future<DateTime?> desiredUpdatedAt(String deviceId) async {
    final raw = await _read(_desiredUpdatedKey(deviceId));
    return raw == null ? null : DateTime.tryParse(raw);
  }

  Future<void> setDesiredDeckIds(String deviceId, Set<String> ids) async {
    await _write(_desiredDecksKey(deviceId), jsonEncode(ids.toList()..sort()));
    await _write(_desiredUpdatedKey(deviceId), DateTime.now().toUtc().toIso8601String());
  }

  Future<void> setActualDeckIds(String deviceId, Set<String> ids) =>
      _write(_actualDecksKey(deviceId), jsonEncode(ids.toList()..sort()));

  Future<Set<String>> _readSet(String key) async {
    final raw = await _read(key);
    if (raw == null || raw.isEmpty) return <String>{};
    try {
      final value = jsonDecode(raw);
      if (value is! List) return <String>{};
      return value.map((e) => e.toString()).toSet();
    } catch (_) {
      return <String>{};
    }
  }

  Future<void> markSync(String deviceId, {required int sentCards, required int receivedReviews}) =>
      _write(
        _lastSyncKey(deviceId),
        jsonEncode({
          'at': DateTime.now().toUtc().toIso8601String(),
          'sentCards': sentCards,
          'receivedReviews': receivedReviews,
        }),
      );

  Future<Map<String, Object?>?> lastSync(String deviceId) async {
    final raw = await _read(_lastSyncKey(deviceId));
    if (raw == null) return null;
    try {
      final value = jsonDecode(raw);
      return value is Map ? Map<String, Object?>.from(value) : null;
    } catch (_) {
      return null;
    }
  }
}
