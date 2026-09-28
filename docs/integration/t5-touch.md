# Integração T5 Touch ↔ plataforma

**Referência auditada:** `feature/t5-s3-touch` em `2acab5d`. Este guia descreve as interfaces realmente presentes e separa contrato público, representação local e formato aceito pelo backend. Consulte também [o estado técnico](../status.md), o [Device Protocol v4](../../spec/protocol/device-protocol-v4.md), os schemas em `spec/schemas/` e as rotas em `backend/app/terminal/router.py`.

## Topologia e fronteiras

| Origem | Destino | Interface | Credencial / responsabilidade |
| --- | --- | --- | --- |
| App móvel | Terminal | HTTP local Device Protocol v4 por LAN ou SoftAP temporário | Token efêmero de sessão local; consulta `/v4/info`, provisiona, envia biblioteca e coleta revisões. |
| App móvel ou web | API | HTTP local ou HTTPS público em `/v1/auth`, `/v1/sync`, `/v1/terminals`, `/v1/generation` | Token da conta. A web não conversa diretamente com o SoftAP. |
| Terminal | API | HTTP de laboratório ou HTTPS com CA validada em `/v1/terminal/*` | Token exclusivo do terminal, com escopo de baralhos. O token da conta não deve ser copiado para o hardware. |
| API / worker | Banco e armazenamento de objetos | Serviços internos | Dados compartilhados, fila de geração e uploads temporários. |

O Terminal T5 Touch declara `protocol=4`, `maxCards=128`, `cardTypes` para cinco tipos, `typedRecall=false`, `bleSync=false` e armazenamento microSD no `/v4/info`. Essas capacidades descrevem o firmware; não comprovam que os produtores de snapshots persistem todos os tipos. O caminho local usa `mnemos.sync/v2` e `mnemos.review-batch/v2`. O dispositivo verifica limite e integridade antes de trocar a biblioteca; a API responde 409 quando a seleção excede a capacidade solicitada.

## Sequência prevista

O aplicativo autenticado registra o terminal, recebe uma credencial restrita e a entrega durante o provisionamento local. O servidor armazena a seleção desejada de baralhos. Em sincronização direta pela infraestrutura, o terminal tenta enviar primeiro sua outbox, obtém o snapshot de conteúdo, puxa revisões/remarcações/preferências pertinentes e reporta o estado físico. Em DirectSync, o móvel tenta incorporar revisões, transfere a biblioteca selecionada e confirma a outbox depois da transferência; há uma lacuna na confirmação de eventos ignorados, descrita abaixo. O usuário pode estudar sem rede; a sincronização deve tolerar repetição de IDs.

No código desta ramificação, a etapa **terminal → backend** não completa quando existe ao menos uma revisão local. `BackendSyncService::pushReviews` envia o lote produzido por `SyncCodec::buildReviewBatchV2`, que empacota sem transformação as linhas da outbox persistidas por `Storage::appendReviewToPath`. O endpoint valida todos os itens antes de gravar qualquer um. A resposta de validação é HTTP 422; `pushReviews` só limpa a outbox após 2xx.

O registro do terminal devolve `protocol=3` em `backend/app/terminal/router.py`, apesar de `/v4/info` anunciar 4. O aplicativo móvel usa o valor do QR para selecionar as rotas v4, portanto esse campo não quebra seu caminho atual, mas é metadado incorreto para um novo integrador. A versão da API `/v1` não deve ser confundida com a versão do protocolo local.

## Incompatibilidade de payload (bloqueador)

| Campo | Linha local e schema `review-v2` | Validador do servidor | Consequência |
| --- | --- | --- | --- |
| Momento | `reviewedAt` em segundos desde Unix epoch; `ReviewEvent` já calcula também milissegundos. | Exige `reviewedAtMs` inteiro, em milissegundos. | Campo obrigatório ausente; 422. |
| Origem | `source="terminal"` na linha gravada. | Aceita apenas `standard` e `multiple_choice` (`ReviewSource` gerado de `shared/contract.yaml`). | Valor rejeitado mesmo após corrigir o momento. |
| Vencimento | `dueAfter` em segundos é gravado; `ReviewEvent` dispõe de `dueAfterMs`. | Lê `dueAfterMs` para derivar intervalo; na ausência assume o instante da revisão. | O intervalo persistido pode virar zero, apesar de o evento local conter o vencimento correto. |
| Escopo | `cardId`, `deckId`, ID estável e rating são enviados. | Confere `cardId` nos baralhos desejados ou reportados da credencial. | Deve ser mantido; jamais usar `deckId` do corpo como prova de autorização. |

O schema público `spec/schemas/review-v2.schema.json` exige `reviewedAt` e não define `reviewedAtMs` ou `source` como obrigatórios, enquanto o serviço aceita outro dialeto sob o mesmo rótulo `mnemos.review/v2`. A correção deve escolher um contrato canônico ou declarar explicitamente uma projeção de transporte. Simplesmente trocar o número do schema ou converter `reviewedAt` sem tratar `source` e `dueAfterMs` deixa a integração incompleta.

**Direção de correção proposta, ainda não implementada:** preservar o evento histórico local e projetar no envio ao backend `reviewedAtMs`, `dueAfterMs` e um `source` admitido pelo contrato compartilhado, mantendo a proveniência física pelo `device_id` autenticado. Alternativamente, o backend pode aceitar o formato público de terminal e realizar essa projeção no limite da API. Em ambos os casos, definir no schema o formato aceito, compatibilizar exemplos e testar bytes reais produzidos pelo firmware contra o endpoint. O parser móvel hoje aceita `reviewedAt` como fallback e importa a origem como `standard` com ID de dispositivo, de modo que a alteração não deve quebrar o caminho direto.

## Conteúdo e tipos de cartão

O terminal aceita cinco tipos por capacidade e interpreta alternativas em `SyncCodec::parseCard`. Todavia, `backend/app/terminal/service.py::snapshot` e `app/mobile/lib/device/terminal_sync_service.dart::buildLibraryBundle` emitem `type=open_recall` para cada card. O banco central, na forma atual, armazena frente, verso e etiquetas, sem atributos suficientes para reconstruir opções e avaliação de múltipla escolha. Até existir migração de dados, autoria compatível e serialização nos dois produtores, a integração de conteúdo da plataforma deve ser descrita como **open recall**. Não converter silenciosamente um tipo objetivo existente em outro sem decisão editorial do estudante.

## DirectSync e confirmação

O móvel lê primeiro o lote da outbox local do terminal. Em `TerminalSyncService._importReviews`, um evento cujo `cardId` não existe no SQLite ou está excluído é contabilizado como ignorado. `synchronize` ainda envia a biblioteca e, se esse envio for bem-sucedido, chama `TerminalClient.acknowledgeReviews()`. O endpoint `/v4/sync/reviews/ack` apaga **toda** a outbox, sem identificar quais eventos foram de fato incorporados. Assim, um card ausente no móvel durante a troca pode levar à perda da única cópia pendente daquele review. O mesmo procedimento precisa tratar IDs já presentes como duplicatas seguras, distinguindo-os de eventos não importados.

**Correção necessária em código, ainda não implementada:** evitar o ACK enquanto houver evento sem destino durável ou introduzir confirmação por IDs/limite confirmado, preservando os eventos restantes no dispositivo. A estratégia deve contemplar cartão ausente, card excluído, erro parcial de importação e novo evento criado entre leitura e ACK. O teste precisa demonstrar que um evento ignorado sobrevive ao próximo ciclo e que duplicatas já persistidas podem ser confirmadas sem produzir outra revisão.

## Critérios de aceite para integração

1. Um fixture de review produzido pelo firmware é aceito pelo endpoint sem renomeações manuais; o horário e o intervalo persistidos conservam suas unidades. Um fixture inválido retorna 422 com campo identificável.
2. Dois envios do mesmo ID produzem uma única revisão e confirmação idempotente. Timeout seguido de retry não perde nem duplica eventos.
3. A outbox direta é removida somente depois da confirmação remota; revisão fora do escopo do terminal é rejeitada. Revogação da credencial produz 401.
4. A revisão criada no terminal aparece no histórico móvel e web após pull, com o mesmo ID, nota, instante e dispositivo de origem; reinício do terminal não perde o cursor nem a sessão local.
5. Conteúdo com mais de 128 cartões resulta em 409, sem truncamento. Card de tipo não representável recebe erro explícito ou permanece fora da seleção, jamais é reinterpretado silenciosamente.
6. No DirectSync móvel, um card ausente ou excluído não causa ACK do evento não incorporado; retry após recomposição da biblioteca preserva o ID e não duplica o histórico.
7. Ensaios são repetidos na build de bancada e na build de produto para rede, sleep e retomada. Teste A/B com reboot e integridade do microSD fica separado da confirmação do bootloader para rollback automático.

Os testes automatizados do backend em `backend/tests/test_terminal_sync_v2.py` usam `reviewedAtMs` e `source=standard`; eles não exercitam o NDJSON realmente produzido por `Storage`. Esse fixture cruzado deve existir antes de declarar o fluxo ponta a ponta concluído.
