# Synchronization Architecture — v0.4

Mnemos is offline-capable and eventually synchronized. Content, learning events and transport are separate layers.

## Authority model

Canonical card/deck content is authored in mobile/web/backend and flows toward terminals. Review events originate in terminals and flow outward. This asymmetry removes most bidirectional edit conflicts while preserving offline study.

## Desired state

For each registered terminal the account stores a set of desired deck ids. The physical terminal reports its actual deck ids. The difference is a reconciliation plan:

`desired - actual` → add/update content.

`actual - desired` → remove content after pending review events have been safely exported.

A terminal with an empty desired set is valid. Connection never implicitly changes desired content.

## Atomic snapshot

The current reference implementation uses an atomic full snapshot (`mnemos.sync/v1`) as the content commit unit. The receiver validates schema, capacity and supported capabilities before replacing its live library. An interrupted transfer preserves the old library.

This is intentionally simpler than a card-level distributed transaction for the current prototype. `mnemos.sync-manifest/v1` reserves a transport-independent manifest for future delta synchronization. Delta transfer can be added without changing `mnemos.card/v1` or HMI semantics.

## Review outbox

Reviews are append-only events with stable ids. The terminal keeps them until an authenticated backend or direct mobile client acknowledges successful ingestion. Duplicate delivery is allowed; consumers must be idempotent.

## Direct BLE sync

BLE sends the same canonical snapshot and returns the same canonical review batch used elsewhere. Mobile records the physical state observed after a direct sync so backend state eventually converges even though the terminal itself was offline.

## Failure ordering

Pending terminal reviews remain authorized during content removal by considering both desired and last-reported device scope. This prevents a user decision to remove a deck from causing loss of reviews produced immediately before reconciliation.
