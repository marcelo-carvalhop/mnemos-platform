# Device Protocol

A definição normativa corrente está em `../../../spec/protocol/device-protocol-v4.md`.

O v4 usa Wi-Fi para todos os transportes do CYD. Provisionamento e DirectSync reutilizam SoftAP, mas possuem modos distintos. O firmware anuncia `directWifiSync=true` e `bleSync=false`.
