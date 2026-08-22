# Arquitetura do firmware Mnemos v0.5

A v0.5 reorganiza o firmware em camadas com responsabilidades exclusivas. `main.cpp` é apenas o coordenador da máquina de estados da HMI. `CydDisplay` desenha e transforma toque em `UiAction`; não calcula aprendizagem nem persiste dados. `StudyEngine` monta e conduz sessões; não implementa fórmulas de memória. `LearningModel` é a única camada autorizada a calcular Recuperabilidade, Dificuldade, Estabilidade e `dueAt`. `Storage` é a fronteira de persistência. `ScheduleService` agrega `dueAt` diretamente dos estados e produz a visão curta da agenda. `MetricsService` reconstrói indicadores a partir de `review_history.ndjson` e dos estados atuais. `SyncCodec` é a fronteira de serialização do snapshot e dos lotes de review. `LocalLinkService` implementa o protocolo local HTTP sobre SoftAP. `NetworkService` administra perfis conhecidos e associação à infraestrutura. `BackendSyncService` usa o mesmo contrato de conteúdo/reviews através do backend.

O fluxo de dependências é deliberadamente unidirecional: HMI -> StudyEngine -> LearningModel/Storage; HMI -> ScheduleService -> CardState/TimeService; conectividade -> SyncCodec/Storage; métricas -> histórico/estado. Nenhum módulo de transporte decide como um card é agendado.

## Fonte de verdade

`library.json` contém definições de cards. `state.json` contém D/S, datas e estado de aprendizagem. `review_history.ndjson` é histórico auditável e não é apagado após sincronização. `review_outbox.ndjson` contém os mesmos eventos ainda não confirmados e pode ser limpo após ACK. `session.json` preserva apenas a fila ainda não concluída e o modo da sessão.

## Transportes

A v0.5 não contém BLE. Wi-Fi em modo STA é usado para backend. Wi-Fi SoftAP é ativado somente sob solicitação do usuário para provisionamento ou sincronização direta. O QR informa `mode=provision` ou `mode=sync`; o servidor rejeita operações que não pertencem ao modo ativo.

## Contratos

Device Protocol v4 usa `mnemos.card/v2`, `mnemos.review/v2`, `mnemos.review-batch/v2`, `mnemos.sync/v2` e `mnemos.metrics/v1`. App e web devem tratar esses contratos como fonte de compatibilidade, não os layouts internos do firmware.


## Agendamento visível

`LearningModel` continua sendo a única camada que cria ou altera `dueAt`. `ScheduleService` nunca agenda cards: ele apenas agrega os estados atuais e produz `dueNow`, `laterToday`, `tomorrow`, `next7Days` e `nextReviewAt`, além de converter epoch para linguagem humana. `dueAt` é a fonte de verdade para decidir vencimento; a meta de retenção participa do cálculo quando o evento é aplicado, mas uma alteração posterior da meta não modifica retroativamente cards já agendados.

A Home exibe `nextReviewAt` apenas quando `dueNow=0`. A tela Agenda é informativa e não oferece edição de datas. Durante uma sessão, o `dueAt` individual produzido para cada card não é mostrado. O terminal expõe somente a próxima revisão agregada na Home, na Agenda e no resumo; PracticeSession continua sem criar novo agendamento.

## Particionamento CYD

A preview.2 substitui `huge_app.csv` por `partitions/mnemos_ota.csv`. O layout mantém NVS em `0x9000`, `otadata` em `0xE000`, dois slots OTA de `0x180000` bytes (`app0` e `app1`) e LittleFS de `0x0F0000` bytes em `0x310000`. O objetivo é recuperar OTA A/B sem reduzir o espaço de filesystem já usado na preview.1.
