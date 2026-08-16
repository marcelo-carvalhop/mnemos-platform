# Sincronização

A v0.4 usa desired-state reconciliation. O usuário declara se cada deck deve ficar `No Mnemos` ou `Somente no app`; o sistema compara essa intenção com o último estado físico reportado e calcula as mudanças. O usuário não escolhe upload/download.

Conteúdo flui App/Backend → Terminal. Reviews e evidência de estudo fluem Terminal → App/Backend e são idempotentes. Snapshots são validados antes de substituir a biblioteca. BLE e HTTPS transportam os mesmos contratos públicos. Veja `docs/architecture/synchronization-v0.4.md`.
