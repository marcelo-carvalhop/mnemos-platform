import 'package:flutter/services.dart';

/// Android bridge used only during terminal provisioning.
///
/// The phone temporarily joins the Mnemos SoftAP, sends configuration, then
/// releases the network binding. Normal terminal operation happens on the
/// user's infrastructure Wi-Fi, not on this temporary link.
abstract final class DeviceWifi {
  static const _channel = MethodChannel('br.com.mnemos/device_wifi');

  static Future<bool> connect({required String ssid, required String password}) async {
    return await _channel.invokeMethod<bool>('connect', {
          'ssid': ssid,
          'password': password,
        }) ??
        false;
  }

  /// Best-effort SSID discovery. Android can redact this value depending on
  /// OS version and permissions, so callers must allow manual entry.
  static Future<String?> currentSsid() => _channel.invokeMethod<String>('currentSsid');

  static Future<void> disconnect() => _channel.invokeMethod<void>('disconnect');
}
