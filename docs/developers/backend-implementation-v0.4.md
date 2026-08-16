# Backend Implementation Guide — v0.4

A compatible backend is not required to use the Mnemos reference Python implementation. Compatibility is defined by public schemas and API semantics.

## Separate account and terminal credentials

Never copy the mobile/account bearer token into a terminal. Register each physical device and issue a revocable terminal-scoped opaque token. Store only a cryptographic hash server-side. Rotation and revocation of one terminal must not sign out the user elsewhere.

## Persist desired and actual state independently

For every terminal keep at least: device id, owner, model/firmware, desired deck ids, last reported deck ids, card count/capacity, last seen/sync time and connectivity metadata. Desired state is written by authenticated user clients. Reported state is written by the terminal token or, after direct BLE sync, by an authenticated app explicitly reporting what it observed.

Do not treat registration as deck assignment. An empty desired deck list is valid.

## Snapshot generation

`GET /v1/terminal/snapshot` returns an atomic `mnemos.sync/v1` built only from desired decks owned by the user. Never silently truncate to device capacity. Return a conflict/error so the device can preserve its previous snapshot and the HMI can explain the capacity mismatch.

## Reviews

`POST /v1/terminal/reviews` ingests `mnemos.review-batch/v1`. Review ids are idempotency keys. A duplicate is success/skipped, not corruption. During deck removal, accept pending reviews for cards that are either in desired scope or still in the terminal's last validated reported scope.

## Status

`POST /v1/terminal/status` is terminal-authenticated telemetry. Validate any reported deck ids against resources owned by that account before storing them. Do not allow reported scope to grant access to foreign content.

## Direct BLE observation

An authenticated app may report the state it observed after a successful direct BLE commit. This is not a replacement for terminal authentication; it is eventual-state telemetry so web/mobile clients do not display stale device contents when the terminal had no Internet.

## Security and secrets

Use TLS in production. Device tokens must be high-entropy, individually revocable and omitted from logs. Wi-Fi credentials never belong in the backend unless a product feature explicitly requires cloud network-profile backup; the v0.4 reference design stores them only on the phone during entry and on the terminal after provisioning.

## Idempotency and transactions

Review ingestion must be idempotent. Snapshot generation should use a consistent database view. Desired-state updates should be atomic. If future delta sync is implemented, keep a monotonic/library revision or content manifest and retain full-snapshot recovery as a fallback.

## External implementation checklist

A backend can claim Mnemos v0.4 compatibility when it validates public schemas, separates device/account credentials, preserves desired versus reported state, never truncates snapshots silently, accepts idempotent review batches, supports terminal revocation and documents any capability deviations.
