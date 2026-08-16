# Mnemos BLE Sync Transport v1

BLE is a transport for existing Mnemos data contracts. It does not define a second card format.

The terminal acts as BLE Peripheral/GATT Server and only advertises after the user explicitly opens **Sincronização → Celular / Bluetooth**. The mobile application acts as Central/GATT Client. Advertising and the BLE radio session end after successful acknowledgement or cancellation.

## GATT service

Service UUID: `6d6e656d-6f73-4001-8000-000000000001`

Control characteristic: `...0002`, write/read. It carries small UTF-8 JSON control messages.

Data characteristic: `...0003`, write + notify. It carries fragmented UTF-8 bytes of canonical snapshots or review batches.

Status characteristic: `...0004`, notify/read. It carries small JSON events.

## Snapshot transaction

The app writes `{"op":"begin","size":N}` to Control, fragments one `mnemos.sync/v1` document over Data, and writes `{"op":"commit"}`. The terminal MUST validate the complete snapshot before replacing its live library. Invalid or incomplete snapshots MUST leave the previous library untouched.

On success the terminal notifies `{"event":"snapshot_committed","cards":N}`.

## Review return

The app writes `{"op":"reviews"}`. The terminal sends `reviews_begin`, fragments one `mnemos.review-batch/v1` document over Data, then notifies `reviews_end`. The app imports reviews idempotently and only then writes `{"op":"reviews_ack"}`. The terminal clears its review outbox only after that acknowledgement.

## Reliability

Every review has a stable id. Re-sending an unacknowledged review is valid and MUST be idempotent. BLE disconnection before snapshot commit or review acknowledgement is not success. The reference implementation uses acknowledged characteristic writes for snapshot chunks and notifications for terminal-to-phone review chunks.

## Privacy and power

BLE scanning/advertising is user initiated. The terminal does not continuously advertise for proximity tracking. No account bearer token is transferred through BLE; terminal/backend credentials remain device scoped.

## Prototype trust boundary

The v0.4 CYD reference requires an explicit user action on the terminal and limits the advertising window, but it does not yet establish a long-lived cryptographic trust relationship between phone and terminal. A production implementation SHOULD add a device-specific pairing secret/challenge (or equivalent authenticated mechanism) without changing the canonical card/review schemas.
