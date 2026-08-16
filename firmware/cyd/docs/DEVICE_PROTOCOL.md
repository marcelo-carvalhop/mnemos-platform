# Device Protocol — firmware CYD v0.4

A definição normativa corrente é `spec/protocol/device-protocol-v3.md`. Este arquivo existe apenas como ponte para quem abre diretamente a pasta do firmware.

O v3 separa provisionamento de conteúdo: `/v3/provision` recebe `mnemos.provision/v2` e apenas persiste um perfil de rede/backend; `/v3/pairing/complete` encerra o SoftAP e libera a reconexão Station. Bibliotecas não são instaladas pela tela de Conexão.

Sincronização de conteúdo ocorre pelo backend ou pelo BLE Sync Transport v1. Endpoints v2/v1 são mantidos apenas durante a janela de migração e novas integrações devem usar v3.

Consulte também `spec/protocol/provisioning-v2.md`, `spec/protocol/ble-sync-v1.md` e `docs/MNEMOS_V0.4_IMPLEMENTATION_GUIDE.md`.
