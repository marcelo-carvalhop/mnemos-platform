# Connectivity Architecture — v0.4

Connectivity is managed independently from study and content selection.

## Modes

The terminal can operate offline, as a Wi-Fi station connected to known infrastructure, as a temporary SoftAP during provisioning, or as an on-demand BLE peripheral during direct synchronization. Provisioning and BLE are explicit user actions and are time limited.

## Known networks

The reference CYD firmware persists up to eight network profiles. Profiles contain SSID, security material, enabled/autoconnect flags and a human-oriented priority. The Wi-Fi radio may be disabled without deleting profiles.

When Wi-Fi is enabled and the current connection is healthy, no roaming occurs. When disconnected, the terminal scans and selects a visible known profile by priority and then RSSI. Connection failures increase a backoff window to reduce radio use and repeated authentication attempts.

## Security classes

`mnemos.network-profile/v1` currently defines open, personal passphrase and Enterprise password profiles. Enterprise certificate authentication is reserved for future capability negotiation. Captive portals are not modeled as Enterprise credentials and are not automatically scripted.

## Provisioning

SoftAP provisioning is AP-only. Station reconnect attempts are suspended for the entire provisioning transaction, eliminating AP/STA mode and channel races. `/v3/pairing/complete` closes the AP before infrastructure association begins.

## Dual-band discovery

Mobile Wi-Fi scan results are grouped by SSID. A shared SSID advertised by 2.4 and 5 GHz is one logical network. Compatibility with the CYD/T5 2.4 GHz radio is true when at least one 2.4 GHz BSSID exists.

## Power

Wi-Fi OFF is a persistent user state and suppresses scans/reconnect. BLE advertises only during an explicit sync window and shuts down after ACK/cancel/timeout. These behaviors are designed to carry forward to the e-paper terminal where radio use dominates controllable active power.
