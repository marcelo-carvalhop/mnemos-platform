# Mnemos v0.4 — Guia de arquitetura, HMI e implementação

## 1. Propósito desta versão

A v0.4 transforma a conectividade e a sincronização do Mnemos em subsistemas explícitos e, ao mesmo tempo, reduz a interface. A regra central do produto é que simplicidade não é decoração: é uma restrição arquitetural. O aplicativo prepara e administra o estudo; o terminal é a superfície oficial de leitura, recordação e avaliação dos cards. A futura interface web segue a mesma divisão.

A release não tenta esconder a complexidade apagando estados importantes. Ela desloca a complexidade para o software. O usuário declara intenções simples — qual dispositivo está configurado, quais decks devem existir nele e quando deseja uma sincronização direta — enquanto o sistema decide transporte, comparação de estado, reenvio idempotente e reconciliação.

## 2. Responsabilidade das interfaces

### 2.1 Mobile

A Home é somente navegação. Ela contém Biblioteca, Dispositivo, Sincronização e Estatísticas, com Configurações disponível no AppBar. Home não contém streak, cards vencidos, retenção, forecast, notificações, lembretes, recomendações ou botões de estudo.

Biblioteca é autoria e organização. Ela lista decks e quantidade de cards, permite criar, editar, renomear, arquivar e excluir. Métricas de aprendizagem não aparecem nesta tela.

Dispositivo é identidade e configuração do terminal. Ele mostra modelo, identificador, firmware, protocolo e capacidade, além de levar para a configuração de conexão. Não escolhe decks.

Conexão existe apenas para provisionamento e configuração de transporte. Ela identifica o terminal, seleciona/grava um perfil de rede e, quando disponível, entrega uma credencial própria do dispositivo para o backend. O provisionamento não instala conteúdo.

Sincronização define o estado desejado do terminal. Para cada deck há somente duas opções semânticas: `No Mnemos` e `Somente no app`. O app compara esse desejo com o inventário físico reportado e calcula as operações necessárias. Reviews nunca dependem de seleção manual: saem automaticamente do terminal e entram no app/backend de forma idempotente.

Estatísticas é a única área destinada a métricas de aprendizagem. A separação evita que dados disponíveis sejam transformados em ruído em telas que possuem outra finalidade.

### 2.2 Terminal

O terminal é a superfície de estudo. Sua Home permanece reduzida à entrada para a sessão e aos acessos de Sincronização e Conexão. A tela de Sincronização oferece sincronização pelo backend quando Wi-Fi está disponível e sincronização direta por Bluetooth quando o usuário deseja. A tela de Conexão mostra estado do Wi-Fi, permite configurar rede e desligar/ligar o rádio.

O terminal não mantém BLE anunciando permanentemente. A sessão BLE é explícita, temporária e termina após confirmação, cancelamento ou timeout.

### 2.3 Web

`app/web/` permanece sem framework escolhido. Quando implementado, o web será um ambiente de autoria em escala, organização, administração de dispositivos e estatísticas. Não será uma segunda superfície de estudo e não deverá transformar todas as páginas em dashboards.

## 3. Autoridade dos dados

A arquitetura separa conteúdo de evidência de estudo.

```text
Conteúdo canônico
App / Backend  ───────────────────────►  Terminal
cards, decks, revisões de conteúdo

Evidência de estudo
App / Backend  ◄───────────────────────  Terminal
reviews, tempos, confiança, progresso observado
```

O terminal pode preservar estado local necessário ao estudo offline, mas a autoria do conteúdo permanece no app/backend. Essa regra reduz conflitos de sincronização e permite que a HMI apresente decisões de presença, não decisões de direção de arquivo.

## 4. Desired State Synchronization

A sincronização de decks é baseada em reconciliação.

```text
Desired Device State
          +
Actual Device State
          │
          ▼
      Sync Planner
          │
    ┌─────┼─────┐
    ▼     ▼     ▼
   ADD  UPDATE REMOVE
```

`desiredDeviceState` é a intenção do usuário. `actualDeviceState` é o último estado físico confirmado pelo terminal. Se a intenção for alterada sem conectividade, ela continua salva localmente como pendente. Quando backend ou BLE estiverem disponíveis, o sincronizador aplica a intenção.

A aplicação mantém o estado desejado explícito mesmo quando ele é vazio. Isso é importante: um conjunto vazio pode significar legitimamente “remover todos os decks do terminal” e não pode ser confundido com “estado ainda não carregado”.

Após uma sincronização BLE, o estado físico local recebe timestamp. Ao reabrir a tela, um relatório antigo do backend não pode sobrescrever uma observação BLE mais nova. O backend também recebe, em melhor esforço, o estado físico observado para convergir quando a Internet reaparecer.

## 5. Snapshots e consistência

A referência v0.4 usa snapshots completos e atômicos para conteúdo. Delta sync está reservado por `mnemos.sync-manifest/v1`, mas não é requisito desta release.

O terminal valida schema, capacidade, modalidade de card e formato de conteúdo antes de substituir sua biblioteca. A implementação do backend constrói uma biblioteca temporária, persiste estado/conteúdo e só então expõe a nova coleção em memória. O transporte BLE segue a mesma ideia: `begin → chunks → commit`.

Uma falha durante a transferência não deve produzir meia biblioteca. Esse requisito é mais importante que economizar alguns bytes no estágio atual do protótipo.

## 6. Review outbox e idempotência

Reviews são eventos append-only até confirmação externa. O terminal mantém o arquivo de revisões enquanto não receber ACK. Se uma conexão cair depois do envio, o mesmo review pode aparecer novamente; por isso `mnemos.review/v1` possui identidade estável e o backend/app devem ser idempotentes.

A remoção de um deck do estado desejado não autoriza descartar reviews ainda pendentes daquele deck. O backend aceita reviews de decks ainda reportados fisicamente mesmo quando eles acabaram de sair do conjunto desejado. Primeiro a evidência é preservada; depois o conteúdo pode desaparecer do terminal.

## 7. Perfis de rede conhecidos

O terminal deixa de persistir apenas um SSID/senha e passa a manter uma coleção de `mnemos.network-profile/v1`. O firmware de referência limita essa coleção a oito perfis, suficiente para prototipação e uso cotidiano.

Perfis podem ser `open`, `personal` ou `enterprise-password`. Cada um armazena flags `enabled`, `autoConnect` e uma prioridade humana. O rádio desligado não apaga perfis.

Quando existe uma conexão saudável, o terminal não troca de rede só porque outra conhecida apareceu. Quando está desconectado e Wi-Fi está habilitado, ele procura redes conhecidas e escolhe uma candidata por prioridade e, em seguida, qualidade do sinal. Falhas aumentam o backoff para evitar tentativas agressivas e desperdício de energia.

Redes Enterprise por certificado e automação genérica de captive portal não fazem parte da capacidade de referência da v0.4. O contrato foi desenhado para evolução por capability negotiation, sem transformar essas limitações em campos privados.

## 8. Redes dual-band

No Android, resultados de scan são agregados por SSID. Um roteador pode anunciar o mesmo SSID em múltiplos BSSIDs de 2,4/5/6 GHz. A compatibilidade do terminal é verdadeira quando pelo menos uma ocorrência de 2,4 GHz existe; não é correto classificar o SSID inteiro como incompatível apenas porque o BSSID mais forte observado pelo telefone é 5 GHz.

O terminal recebe SSID e credencial, não a banda escolhida pelo telefone. Ele faz sua própria associação à variante suportada.

## 9. Provisionamento Wi-Fi

Provisionamento Wi-Fi é uma transação de conexão e não de conteúdo.

```text
Usuário abre Conexão no terminal
        │
        ▼
Terminal suspende Station e abre SoftAP exclusivo
        │
        ▼
App lê QR e conecta temporariamente ao MNEMOS-...
        │
        ▼
App lê identidade/capabilities
        │
        ▼
App envia NetworkProfile + backend credential opcional
        │
        ▼
Terminal persiste, mas NÃO inicia Station ainda
        │
        ▼
/pairing/complete
        │
        ▼
SoftAP encerra
        │
        ▼
Terminal volta a Station e procura rede conhecida
```

A v0.4 elimina o uso concorrente `AP_STA` durante o provisionamento porque tentativas Station não podem disputar modo/canal com a rede temporária usada pelo telefone.

## 10. Bluetooth como transporte offline

BLE é fallback de sincronização direta e não um segundo protocolo de dados. O mesmo `mnemos.sync/v1` usado pelo restante do ecossistema viaja pelo serviço GATT Mnemos.

O Android atua como Central/GATT Client. O terminal atua como Peripheral/GATT Server. A sessão é iniciada pelo usuário no terminal, o telefone procura o `deviceId`, negocia MTU, envia snapshot fragmentado, aguarda commit, solicita reviews, importa-os e envia ACK. Em seguida a conexão é encerrada e o BLE é desligado.

```text
App                                  Terminal
 │                                      │
 │──────── begin(size) ────────────────►│
 │──────── chunks ─────────────────────►│
 │──────── commit ─────────────────────►│
 │◄─────── snapshot_committed ─────────│
 │──────── reviews ────────────────────►│
 │◄─────── review-batch bytes ─────────│
 │◄─────── reviews_end ────────────────│
 │──────── reviews_ack ────────────────►│
 │                                      │
 └──────────── disconnect ──────────────┘
```

A fragmentação pertence ao transporte BLE; o card continua sendo `mnemos.card/v1` e não ganha uma variante “card BLE”.

## 11. Retomada de sessão no terminal

A sessão de estudo é persistida por IDs estáveis de card. Se o terminal reiniciar ou entrar em suspensão no meio de uma sessão, a Home oferece **CONTINUAR SESSÃO**. O estado salvo contém a sequência da sessão ainda necessária, a posição e os contadores de avaliação; ao restaurar, os IDs são remapeados contra a biblioteca atual e cards removidos são descartados com segurança.

Essa persistência é deliberadamente local ao terminal e não transforma o aplicativo em superfície de estudo. O objetivo é apenas preservar continuidade de uso. Quando a sessão termina normalmente, o arquivo temporário de sessão é apagado.

## 12. Capability negotiation

Clientes não devem codificar lógica do tipo “se modelo = CYD”. O terminal expõe capacidades. A referência atual anuncia `basic/plain`, limite de cards e disponibilidade de BLE, backend, known networks e Enterprise password quando a build do core oferece esse suporte.

Isso permite que o T5 evolua para modalidades e capacidades maiores sem quebrar o app ou alterar o significado dos schemas existentes.

## 13. Backend de referência

A entidade TerminalCredential separa estado desejado e estado reportado. `deck_ids` representa a intenção que o backend deve servir no snapshot; `reported_deck_ids` representa o último inventário físico comunicado pelo terminal/app. Também são mantidos `card_count`, `max_cards`, `connectivity`, `wifi_ssid`, revisão e timestamps.

O backend registra terminais sem exigir qualquer deck. Isso preserva a separação entre Conexão e Sincronização. A credencial entregue ao terminal é restrita ao device e não é uma cópia do token completo da conta móvel.

Os endpoints de terminal aceitam estado vazio. Excesso de capacidade retorna erro em vez de truncar silenciosamente uma biblioteca. Reviews são ingeridos de forma idempotente e podem pertencer ao conjunto desejado ou ainda reportado, evitando perda no momento em que um deck é removido.

A documentação específica para implementadores de backend está em `docs/developers/backend-implementation-v0.4.md` e o contrato público em `spec/protocol/backend-api-v1.md`.

## 14. Energia e conectividade

O estado Wi-Fi OFF é persistente e voluntário. Nele o terminal não faz scans nem tenta reconectar. Religar o Wi-Fi preserva perfis e inicia reconexão. BLE só existe durante uma janela explícita de sincronização.

Perfis de energia mais sofisticados — “sempre conectado”, “balanceado” e “economia” — permanecem para a fase T5, quando medições reais de bateria/e-paper permitirem definir intervalos com evidência em vez de valores arbitrários.

## 15. Segurança

Credenciais Wi-Fi, credenciais Enterprise e tokens de backend são dados sensíveis. No protótipo CYD, persistência utiliza NVS/Preferences. Uma build de produto deve ativar mecanismos de proteção de flash/NVS e tratar provisionamento, OTA e BLE com requisitos de produção específicos.

A BLE v0.4 depende de ação física explícita e janela curta; ela ainda não implementa uma relação criptográfica permanente App↔Terminal. Antes de produto público, deve ser acrescentado pareamento confiável com segredo/challenge ou mecanismo equivalente. Esse item está documentado como hardening pendente, não escondido como se estivesse resolvido.

Captive portals não devem receber automação genérica de credenciais. Uma rede conectada sem acesso ao backend deve ser diagnosticada como conectividade limitada/portal provável e apresentada ao usuário como tal.

## 16. Mapa de implementação

| Responsabilidade | Implementação principal |
|---|---|
| Home mínima | `app/mobile/lib/features/home_screen.dart` |
| Biblioteca | `app/mobile/lib/features/decks_screen.dart` |
| Identidade do terminal | `app/mobile/lib/features/device_screen.dart` |
| Provisionamento | `app/mobile/lib/features/terminal_screen.dart` |
| Estado desejado | `app/mobile/lib/features/device_sync_screen.dart` |
| Estado local terminal | `app/mobile/lib/device/terminal_local_store.dart` |
| BLE mobile | `app/mobile/lib/device/device_ble.dart` + `MnemosBleBridge.kt` |
| Wi-Fi Android | `MainActivity.kt` + `device_wifi.dart` |
| HTTP Device Protocol | `terminal_protocol.dart` + `pairing_service.cpp` |
| Perfis de rede | `network_service.h/.cpp` |
| BLE firmware | `ble_sync_service.h/.cpp` |
| Sync backend firmware | `backend_sync_service.h/.cpp` |
| API de terminais | `backend/app/terminal/router.py` + `service.py` |
| Persistência backend | `backend/app/models.py` + migration `0011` |
| Contratos públicos | `spec/schemas/` e `spec/protocol/` |

## 17. Testes de conformidade

Antes de release devem ser executados, quando as toolchains estão disponíveis:

```bash
# schemas/fixtures
python tools/schema-validator/validate_mnemos_examples.py

# backend
python -m compileall backend/app backend/tests

# mobile
cd app/mobile
flutter pub get
flutter analyze
flutter test

# firmware
cd firmware/cyd
pio run
```

No teste físico, validar separadamente SoftAP, associação a rede pessoal 2,4 GHz, SSID dual-band compartilhado, Wi-Fi OFF/ON, perfil conhecido, falha de senha/backoff, BLE snapshot vazio, BLE snapshot com 10 cards, envio/ACK de reviews e queda de conexão antes do commit.

## 18. Limitações conscientemente mantidas em v0.4

O CYD continua sendo hardware provisório e anuncia apenas cards `basic/plain`. O transporte de conteúdo usa snapshot completo em vez de delta. EAP-TLS/certificados, automação genérica de captive portal, OTA assinado, criptografia de confiança BLE permanente e perfis avançados de energia não são apresentados como funcionalidades prontas.

Esses itens foram mantidos fora do escopo porque implementá-los sem hardware final, infraestrutura de produção ou política de segurança definida aumentaria complexidade sem validar o produto. Os contratos e a separação de responsabilidades da v0.4 permitem adicioná-los posteriormente sem devolver complexidade à HMI.

## 18. Princípio de manutenção

Ao acrescentar uma funcionalidade, primeiro determine a qual tela/subsistema ela pertence. Se não houver uma responsabilidade clara, ela não deve aparecer na Home por conveniência. Se uma decisão puder ser derivada pelo sistema com segurança, ela não deve ser pedida ao usuário. Se uma informação for técnica mas necessária para suporte, ela deve existir em diagnóstico, não no fluxo principal.

A regra de produto pode ser resumida assim:

```text
O usuário decide o resultado desejado.
O Mnemos decide como alcançá-lo.
```

## 19. Registro de QA desta entrega

O registro exato do que foi validado no ambiente de empacotamento e do que ainda exige Flutter/PlatformIO/PostgreSQL está em `docs/releases/v0.4.0-QA.md`. Esse arquivo deve acompanhar a release para evitar confundir validação estrutural com compilação real em hardware/toolchain.
