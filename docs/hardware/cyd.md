# Mnemos Terminal CYD v0.3.0

Firmware provisório para ESP32-2432S028. Esta versão implementa sessão de estudo local, persistência em LittleFS, reviews append-only, Device Protocol v2, provisionamento Wi-Fi e sincronização direta com backend. O conteúdo demonstrativo é um único deck `Redes de Computadores` com 10 cards.

`CONFIGURAR / SINCRONIZAR` cria um SoftAP temporário e mostra um QR `mnemos://pair?v=2`. O app entrega a rede de infraestrutura e opcionalmente uma credencial de backend. O terminal trabalha em AP+STA durante a transição, encerra o SoftAP ao final e permanece em STA. `DESLIGAR WI-FI` desativa o rádio sem apagar SSID, senha, backend ou token; `LIGAR WI-FI` reconecta e dispara sincronização.

O perfil de capacidade desta placa é deliberadamente restrito: até 48 cards, `type=basic`, `format=plain` e payload local máximo de 90000 bytes. Esses valores são anunciados por `/v2/info`. Snapshots são validados antes de substituir a biblioteca; capacidade excedida ou conteúdo não suportado mantém o estado anterior.

A sincronização direta envia reviews pendentes para `POST /v1/terminal/reviews` e obtém conteúdo em `GET /v1/terminal/snapshot`. Para HTTPS de produção, preencha `Config::BACKEND_ROOT_CA`; o firmware não usa conexão TLS insegura. HTTP permanece disponível apenas para laboratório/LAN.

Abra esta pasta no PlatformIO e compile o ambiente `esp32-2432s028`. As dependências são TFT_eSPI, XPT2046_Touchscreen, ArduinoJson 7 e QRCode. A documentação de integração está em `docs/`.
