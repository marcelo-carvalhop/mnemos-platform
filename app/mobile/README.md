# Mnemos Android v0.3.0

Aplicativo Flutter do ecossistema Mnemos. A versão v0.3 mantém o banco local Drift/SQLite e acrescenta uma camada pública de interoperabilidade baseada em JSON Schema. O app exporta `mnemos.sync/v1` para o terminal e importa `mnemos.review/v1` sem acoplar o formato externo às tabelas internas.

A tela `Terminal Mnemos` lê o QR Code v2, registra o hardware no backend quando possível, solicita ao Android uma conexão temporária ao SoftAP, transfere relógio, credenciais da rede Wi-Fi de infraestrutura, biblioteca inicial e token restrito de dispositivo. O app então encerra sua ligação ao SoftAP; o terminal permanece conectado à infraestrutura e pode sincronizar diretamente com o backend.

No Android 13+ o projeto declara `NEARBY_WIFI_DEVICES`; versões anteriores mantêm compatibilidade com a permissão de localização necessária às APIs Wi-Fi antigas. A senha da infraestrutura é informada pelo usuário e não é recuperada automaticamente do sistema.

Para desenvolvimento, execute `flutter pub get`, `flutter analyze` e `flutter run`. A documentação para integrações externas está em `../../docs/developers`; os schemas ficam em `../../spec/schemas`. O único seed demonstrativo contém um deck `Redes de Computadores` com 10 cards.
