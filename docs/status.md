# Estado técnico da plataforma

**Base de auditoria:** `feature/t5-s3-touch` em `2acab5d` (28/09/2026). Este registro distingue código presente, testes automatizados e integração física verificada. Não representa homologação de produção. O histórico de trabalho de agosto permanece em `docs/releases/legacy/STATUS-2026-08-09.md` e não deve ser interpretado como estado atual.

| Área | Implementação observada | Limite ou verificação pendente |
| --- | --- | --- |
| Móvel | Flutter com biblioteca, estudo, criação, progresso, banco Drift/SQLite, sincronização e fluxo de dispositivo. | Validar no hardware atual o pareamento e o retorno de revisões após interrupções de rede. |
| Web | Angular 22 com estudo, biblioteca, criação, progresso e conta sobre a API comum. | O espelho de estudo fica em memória; recarregar sem rede não preserva uma sessão offline. |
| Backend | FastAPI, 17 modelos persistentes, API de conta/sync/terminal, geração assíncrona, PostgreSQL e armazenamento de objetos local no Compose. | Não declarar implantação de produção nem integração física ponta a ponta apenas pela existência das rotas. |
| T5 Touch | HMI touch-first, FSRS, RTC, microSD como fonte de definições quando presente, LittleFS para estado/histórico, rede cooperativa, sleep e atualização local A/B. | A build padrão é de bancada; checklists de hardware ainda têm itens abertos. Rollback automático depende da configuração real do bootloader. |
| Interoperabilidade | `shared/contract.yaml` gera código para os clientes oficiais; `spec/` contém schemas públicos versionados; Device Protocol v4 e sync v2 estão em uso no terminal. | O corpo de revisão publicado pelo firmware não satisfaz a validação atual de `POST /v1/terminal/reviews`. O tipo de cartão é reduzido a `open_recall` nos snapshots construídos pelo backend e pelo móvel. |

## Bloqueadores de integração

O bloqueador imediato do fluxo terminal → servidor está descrito com campos, unidades, código envolvido e critérios de aceite em [integration/t5-touch.md](integration/t5-touch.md). A incompatibilidade é um defeito de contrato entre implementações: `firmware/t5-touch/src/storage.cpp` grava `reviewedAt` em segundos e `source=terminal`, enquanto `backend/app/terminal/service.py` exige `reviewedAtMs` e restringe `source` aos valores de `ReviewSource`. O servidor retorna 422 antes de confirmar os eventos. O firmware mantém a outbox após resposta não-2xx, portanto a perda do evento direto não foi demonstrada, mas a fila não converge.

Há risco distinto no DirectSync móvel. O aplicativo ignora revisões de cartões que não existem na sua base local, mas pode chamar o ACK que apaga toda a outbox do terminal depois do envio da biblioteca. Esse caso precisa de confirmação seletiva ou retenção dos eventos não incorporados antes de declarar integridade do histórico. O registro da API também anuncia `protocol=3` enquanto o QR do T5 Touch negocia v4; o móvel atual usa o QR, mas o metadado do backend deve ser corrigido para integradores futuros.

Há uma segunda perda semântica: `backend/app/terminal/service.py::snapshot` e `app/mobile/lib/device/terminal_sync_service.dart::buildLibraryBundle` constroem cartões como `open_recall` independentemente do tipo original. O terminal anuncia outros tipos em `/v4/info`, mas o caminho de conteúdo sincronizado atualmente não preserva alternativas e regras de avaliação. A correção exige persistência e projeção compatíveis nos produtores do snapshot, além de fixtures para cada tipo.

## Evidência e manutenção

Os checklists em `firmware/t5-touch/docs/` são roteiros de bancada; caixas não marcadas não são testes executados. Os workflows em `.github/workflows/` cobrem backend, móvel, web, schemas e **firmware CYD**; não há job de build do T5 Touch nesta ramificação. Esta revisão documental não executou hardware nem confirmou o estado remoto dos workflows. Um item só deve mudar para **integrado** depois de um teste ponta a ponta com revisão criada no terminal, confirmação, pull nos demais clientes, retry idempotente e reinicialização do dispositivo. Atualize esta página e o guia de integração no mesmo PR que corrigir o contrato.
