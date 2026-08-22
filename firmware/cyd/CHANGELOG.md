# Firmware CYD changelog

## 0.5.0-preview.3

### Ajuste de transparência da HMI

O reagendamento individual de cada card deixa de gerar uma tela intermediária. A próxima revisão permanece visível de forma agregada na Home, Agenda e resumo da sessão. A tela de esforço também deixa de explicar detalhes internos do scheduler.


### Preview.2

Adiciona `ScheduleService`, próxima revisão na Home, `MENU > AGENDA`, feedback pós-review e próxima revisão no resumo. Corrige a semântica de primeiro erro: `dueAt` passa a ser a fonte de vencimento, cards já tentados deixam de ser tratados como novos e a carga futura inclui reaprendizado. Introduz `partitions/mnemos_ota.csv` com dois slots OTA de 1,5 MiB e LittleFS de 960 KiB.

Refatora o firmware em torno de `LearningModel`, `StudyEngine`, `Storage`, `MetricsService`, `SyncCodec`, `LocalLinkService`, `NetworkService` e `CydDisplay`. Remove BLE. DirectSync passa a usar SoftAP/HTTP. Adiciona Card v2, múltipla escolha, verdadeiro/falso, correção objetiva automática, confiança/resultado/esforço separados, PracticeSession sem alteração de D/S/dueAt, histórico de reviews imutável separado da outbox e Device Protocol v4.

## 0.4.x

Linha anterior com Device Protocol v3, provisionamento AP-only, redes conhecidas e BLE direct sync. Mantida apenas como histórico de migração.
