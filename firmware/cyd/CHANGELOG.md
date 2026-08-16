# Registro de versões — Mnemos

## 0.3.0 — 16 de agosto de 2026

A v0.3.0 introduz a primeira especificação pública de interoperabilidade do Mnemos. Cards, decks, estados, reviews, snapshots, lotes de reviews e provisionamento passam a possuir JSON Schemas versionados. O aplicativo converte sua persistência interna para `mnemos.sync/v1`; o firmware CYD implementa o Device Protocol v2 e mantém compatibilidade temporária com rotas v1.

A operação de conexão foi transformada em provisionamento: o terminal abre SoftAP temporário, o aplicativo transfere SSID e senha da rede de infraestrutura e, quando existe backend alcançável, uma credencial exclusiva do terminal. Ao fim o SoftAP é encerrado e o hardware permanece como estação. O terminal pode desligar o rádio Wi-Fi sem apagar credenciais e sincroniza diretamente com o backend no boot online, após provisionamento, ao reativar Wi-Fi e periodicamente.

O backend passa a registrar, listar e revogar terminais, restringir cada credencial aos decks atribuídos, servir snapshots canônicos e ingerir reviews idempotentes. Excesso de capacidade retorna conflito e não causa truncamento. O protótipo CYD anuncia `basic/plain`, máximo 48 cards e aplica snapshots somente depois de validação completa.

O conteúdo demonstrativo foi consolidado em um único baralho `Redes de Computadores` com 10 cards. A documentação pública, schemas e fixture canônico estão em `docs/v0.3` e `schemas`.


## 0.2.1 — 13 de agosto de 2026

Correção de compatibilidade com a implementação `WebServer` fornecida pelo Arduino-ESP32 2.0.17 usado pelo ambiente PlatformIO Espressif32 7.0.1. O método interno `PairingService::authorized()` deixou de ser declarado `const`, pois `WebServer::hasArg()` e `WebServer::arg()` nessa versão da biblioteca não possuem qualificadores `const`. A alteração não modifica o protocolo de pareamento, os endpoints HTTP nem o comportamento funcional da sincronização; apenas corrige a falha de compilação observada no firmware 0.2.0.

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
