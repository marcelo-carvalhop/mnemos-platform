import 'package:flutter/services.dart';

class BleMnemosDevice {
  const BleMnemosDevice({required this.deviceId, required this.name, required this.rssi});

  final String deviceId;
  final String name;
  final int rssi;

  factory BleMnemosDevice.fromMap(Map<Object?, Object?> map) => BleMnemosDevice(
        deviceId: map['deviceId']?.toString() ?? '',
        name: map['name']?.toString() ?? 'Mnemos',
        rssi: (map['rssi'] as num?)?.toInt() ?? -100,
      );
}

class BleSyncReport {
  const BleSyncReport({
    required this.sentCards,
    required this.receivedReviews,
    required this.deviceId,
    required this.reviewsJson,
  });

  final int sentCards;
  final int receivedReviews;
  final String deviceId;
  final String reviewsJson;

  factory BleSyncReport.fromMap(Map<Object?, Object?> map) => BleSyncReport(
        sentCards: (map['sentCards'] as num?)?.toInt() ?? 0,
        receivedReviews: (map['receivedReviews'] as num?)?.toInt() ?? 0,
        deviceId: map['deviceId']?.toString() ?? '',
        reviewsJson: map['reviewsJson']?.toString() ?? '',
      );
}

/// Native Android BLE transport. BLE is only transport; it carries the same
/// canonical Mnemos snapshot/review schemas used elsewhere.
abstract final class DeviceBle {
  static const _channel = MethodChannel('br.com.mnemos/device_ble');

  static Future<List<BleMnemosDevice>> scan({Duration timeout = const Duration(seconds: 5)}) async {
    final rows = await _channel.invokeListMethod<Object?>('scan', {'timeoutMs': timeout.inMilliseconds}) ?? const [];
    return [
      for (final row in rows)
        if (row is Map) BleMnemosDevice.fromMap(Map<Object?, Object?>.from(row)),
    ].where((d) => d.deviceId.isNotEmpty).toList(growable: false);
  }

  static Future<BleSyncReport> sync({
    required String deviceId,
    required String snapshotJson,
  }) async {
    final raw = await _channel.invokeMapMethod<Object?, Object?>('sync', {
      'deviceId': deviceId,
      'snapshot': snapshotJson,
    });
    if (raw == null) throw StateError('O Android não retornou o resultado da sincronização Bluetooth.');
    return BleSyncReport.fromMap(raw);
  }
}
