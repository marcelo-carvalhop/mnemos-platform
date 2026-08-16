# Mnemos Device Protocol v3

Device Protocol v3 separates **connection** from **content synchronization**. Pairing is a short-lived configuration transaction; it does not install or remove decks.

## Pairing transport

The CYD reference implementation creates a temporary 2.4 GHz SoftAP named `MNEMOS-<suffix>`, with a random WPA2 passphrase, address `192.168.4.1`, a fixed channel and a single associated client. While this AP is active the station interface does not reconnect to infrastructure. This prevents the provisioning AP from disappearing because the station interface changes mode or channel.

The QR payload remains `mnemos://pair?...` and includes protocol version, device id, temporary SSID/password, host, session token, model and firmware.

## v3 local endpoints

`GET /v3/info` returns identity, capabilities, current library deck ids and non-secret metadata about known network profiles.

`POST /v3/time` updates the terminal clock.

`POST /v3/provision` accepts `mnemos.provision/v2`. The terminal validates and persists the `mnemos.network-profile/v1` profile and optional backend device credential. It MUST NOT start station association while the provisioning AP is active.

`GET /v3/network/status` reports radio state; during provisioning it is expected to report no infrastructure association.

`POST /v3/pairing/complete` is the transaction boundary. Only after returning success does the terminal close the SoftAP and, if Wi-Fi is enabled, attempt association with known infrastructure profiles.

## Capabilities

Clients MUST use capability negotiation rather than model-name conditionals. The CYD prototype currently advertises `basic` cards, `plain` content and its card capacity. `bleSync`, `knownNetworks`, `wifiProvisioning` and `backendSync` are independent feature flags.

## Compatibility

v1 and v2 routes can remain present during migration. New applications MUST prefer v3 when the QR payload advertises protocol 3. Content transfer over the pairing HTTP channel is legacy behavior and is not part of v3.
