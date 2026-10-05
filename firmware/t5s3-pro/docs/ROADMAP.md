# Roadmap — firmware/t5s3-pro

Pendências conhecidas, em ordem de prioridade. Itens que exigem o hardware
estão marcados com **(bancada)**.

## Validação

- [ ] **(bancada)** Validar a sincronização terminal → backend ponta a ponta.
  `sync_codec.cpp` já converte as revisões para `reviewedAtMs` e mapeia
  `source` para `standard`/`multiple_choice`, mas isso nunca foi testado
  contra o servidor.
- [ ] **(bancada)** Executar e registrar as checklists
  ([TEST_CHECKLIST.md](TEST_CHECKLIST.md) e
  [HMI_TEST_CHECKLIST.md](HMI_TEST_CHECKLIST.md)) com data, versão do
  firmware e resultado.
- [ ] **(bancada)** Validar o build de produto (`t5s3-pro`): light sleep,
  auto-off e hard-off por bateria crítica.
- [ ] **(bancada)** Testar o rollback do OTA: o bootloader tem
  `CONFIG_BOOTLOADER_APP_ROLLBACK_ENABLE=1`; falta provar que uma imagem que
  trava antes de `confirmRunningImage()` volta para a anterior.
- [ ] **(bancada)** Teste de várias horas monitorando o heap livre: há mais de
  300 usos de `String` do Arduino.

## Robustez

- [ ] Assinar a tarefa do `loop()` no task watchdog, depois de medir as
  operações longas (refresh do EPD, HTTP de sincronização, gravação no SD) e
  alimentar o watchdog dentro delas.
- [ ] Retorno na tela quando o desligamento é recusado com USB conectado
  (hoje só há log serial) e quando o corte do BATFET falha.
- [ ] Documentar como extrair o coredump: o framework grava em flash e a
  partição `coredump` existe.

## Energia e bateria

- [ ] Formalizar a máquina de estados de energia, incluindo o comportamento da
  bancada com bateria crítica.
- [ ] **(bancada)** Calibrar a estimativa por tensão com uma descarga completa
  da célula de 1500 mAh: resistência interna (0,12 Ω), limite crítico (3,45 V)
  e curva tensão × carga.
- [ ] **(bancada)** Medir o consumo em cada estado (ativo, light sleep,
  desligado) e documentar a autonomia.
- [ ] Pedir à LilyGO a golden image ou o procedimento de provisionamento do
  BQ27220 para o H752-01 (Device Number `0x0220`, Design/FullChargeCapacity
  3000 mAh, `SEC=3`, firmware factory reporta `BQ27220 NOK`).

## Código

- [ ] Extrair um núcleo compartilhado entre as variantes de firmware:
  `fsrs_engine`, `storage`, `schedule_service`, `fsrs_replay_service`,
  `backend_sync_service` e `cards` são idênticos aos do t5-touch, e o
  `sync_codec` já divergiu.
- [ ] Dividir `main.cpp` (telas, toque, energia e rede) e `t5_display.cpp`.
- [ ] Logging com níveis e tags no lugar dos `Serial.print*` espalhados.
- [ ] `.clang-format` para o código do projeto e `pio check` no CI.
- [ ] Ampliar os testes no host: `sync_codec` contra os schemas de `spec/` e
  `schedule_service`.

## Segurança

- [ ] Assinar os pacotes OTA (hoje: modelo, geração e SHA-256).
- [ ] Recusar backend em `http://` no build de produto.
- [ ] Decidir sobre secure boot, criptografia de flash e NVS cifrada. Os
  eFuses são irreversíveis: testar numa placa descartável.
- [ ] LocalLink: token de curta duração e limite de tentativas.

## Licenciamento e release

- [ ] Definir a licença do projeto (`LICENSE` na raiz).
- [ ] Resolver a origem GPL-3.0 provável de `lib/BQ27220`
  ([THIRD_PARTY_NOTICES.md](../THIRD_PARTY_NOTICES.md)).
- [ ] Registrar a família e a licença das fontes de `src/mnemos_fonts.cpp`.
- [ ] Processo de release: tag por versão e artefatos (binário, manifesto
  OTA, SHA-256) anexados à release a partir do CI.

## Integração com a plataforma (fora do firmware)

- [ ] App móvel: o ACK do DirectSync pode apagar toda a outbox do terminal.
- [ ] Backend: o registro da API anuncia `protocol=3`, enquanto o terminal
  negocia v4.
- [ ] Backend e app reduzem todos os cartões a `open_recall` nos snapshots.
