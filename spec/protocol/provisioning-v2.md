# Mnemos Provisioning v2

Provisioning v2 stores a network profile and optional terminal-scoped backend credential. It never selects decks.

A `mnemos.network-profile/v1` can describe an open network, a personal passphrase network, or an Enterprise username/password profile. The CYD Arduino reference implementation supports PEAP/MSCHAPv2 only when enterprise support is available in the underlying build. Certificate-based EAP and captive-portal automation are not claimed by this profile version.

Multiple profiles are persisted. When disconnected and Wi-Fi is enabled, the terminal scans for known profiles and chooses the highest configured priority, using signal strength as a tie breaker. It does not abandon a working connection merely because another known network becomes visible. Failed reconnect attempts use backoff. Turning Wi-Fi off preserves profiles and backend credentials while disabling scans and reconnection.

Dual-band SSIDs must be grouped by SSID in client HMIs. A network is compatible with a 2.4 GHz-only terminal when at least one BSSID for that SSID is visible in 2.4 GHz, even if the phone itself is currently using a stronger 5 GHz BSSID.
