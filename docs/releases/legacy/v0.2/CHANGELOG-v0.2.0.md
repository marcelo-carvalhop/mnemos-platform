# Registro de versões — Mnemos

## 0.2.0 — 13 de agosto de 2026

Esta versão estabelece a primeira integração funcional entre o aplicativo Android/Flutter e o terminal provisório ESP32-2432S028. O firmware passa a oferecer um modo de pareamento direto: cria uma rede Wi-Fi local temporária protegida, produz um QR Code com identificador, SSID, credenciais efêmeras, endereço local e token de sessão, e expõe uma API HTTP limitada ao período de pareamento. O aplicativo passa a ler esse QR Code, solicitar ao Android a conexão local com o terminal e transferir baralhos sem depender de roteador ou acesso à internet.

A sincronização tornou-se bidirecional. Revisões realizadas no terminal são importadas para o histórico local do aplicativo antes que novos estados de cartões sejam enviados ao dispositivo. O aplicativo utiliza os identificadores originais dos cartões, preserva a deduplicação de eventos e reaplica o agendador já existente do projeto móvel. Depois de uma sincronização bem-sucedida, o aplicativo confirma o recebimento e o terminal limpa o log de revisões já transferido, impedindo crescimento indefinido do arquivo.

A hora do terminal também passa a ser sincronizada pelo telefone durante o pareamento. Essa mudança elimina a dependência de NTP para o protótipo, cuja rede temporária não possui acesso à internet e cujo hardware não possui RTC dedicado. O firmware continua capaz de operar offline entre sincronizações.

No aplicativo, a identidade visual foi migrada para a paleta Mnemos: Marfim Calmo `#F4F1E8`, Grafite Profundo `#1F1F1F`, Sálvia Analógica `#7A8B72`, Azul Petróleo `#365462`, Terracota Contida `#B56E52`, Cinza Névoa `#D9D5CC` e Latão Fosco `#B8A27A`. O splash nativo do Android também foi ajustado para Marfim Calmo, evitando uma ruptura visual antes do primeiro frame do Flutter.

A versão móvel passa de 0.1.0 para 0.2.0. O firmware integrado passa de 0.1.1 para 0.2.0. O nome interno do pacote Flutter/Android e o nome do banco local foram mantidos para preservar compatibilidade com o projeto existente; a marca apresentada ao usuário passa a ser Mnemos.

## 0.1.1 — firmware provisório

A versão 0.1.1 consolidou o pré-protótipo no ESP32-2432S028, incluindo calibração do touchscreen, sessão local de estudo, avaliação de confiança, quatro graus de resposta, persistência em LittleFS e correções de compatibilidade com a biblioteca XPT2046 e com a inicialização da estrutura de botões.

## 0.1.0 — aplicação móvel

A versão 0.1.0 corresponde à base original do aplicativo móvel fornecido para integração. Ela já continha armazenamento local com Drift/SQLite, domínio de cartões e baralhos, histórico de revisões, agendamento, backend e recursos de autoria. A versão 0.2.0 preserva essa estrutura e acrescenta o terminal físico como novo dispositivo de estudo.
