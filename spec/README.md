# Mnemos Specifications

This directory is normative. Documentation under `/docs` explains the system; files under `/spec` define interoperable contracts.

Current data contracts: `mnemos.card/v1`, `mnemos.deck/v1`, `mnemos.card-state/v1`, `mnemos.review/v1`, `mnemos.review-batch/v1`, `mnemos.sync/v1`, `mnemos.network-profile/v1` and `mnemos.sync-manifest/v1`.

Current transport/API specifications: Device Protocol v3, Provisioning v2, BLE Sync Transport v1 and Backend API v1. Product release versions and protocol/schema versions evolve independently.

Third-party implementations may use any language, database or internal data model. Compatibility requires preserving the semantics and validation constraints of these public contracts at integration boundaries.
