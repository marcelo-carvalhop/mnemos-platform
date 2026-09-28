# Integração externa e compatibilidade

O Mnemos separa contratos públicos em [`spec/`](../../spec/README.md), contrato interno gerado em `shared/contract.yaml` e modelos de persistência de cada componente. Implementações externas podem usar outra linguagem ou banco, mas precisam declarar a versão de cada documento transmitido, validar o produtor e o consumidor e respeitar a autorização do serviço. Este guia descreve o estado de `feature/t5-s3-touch`; os protocolos v1 e os perfis CYD preservados em `spec/protocol/` são históricos para o T5 Touch.

## Matriz de interfaces

| Fronteira | Transporte e versões observadas | Origem da implementação |
| --- | --- | --- |
| Móvel/web ↔ API | HTTP local ou HTTPS público, bearer da conta e `/v1/sync/*`; entidades do contrato gerado com sequência de servidor | `app/mobile/lib/`, `app/web/src/app/`, `backend/app/sync/` |
| Móvel ↔ T5 Touch | HTTP local, Device Protocol v4; `mnemos.provision/v2`, `mnemos.sync/v2` e `mnemos.review-batch/v2` | `app/mobile/lib/device/`, `firmware/t5-touch/src/local_link_service.cpp` |
| T5 Touch ↔ API | HTTP em laboratório ou HTTPS com CA, bearer próprio do terminal; `/v1/terminal/*` | `firmware/t5-touch/src/backend_sync_service.cpp`, `backend/app/terminal/` |
| Geração | API e worker, armazenamento temporário de objetos e fila no PostgreSQL | `backend/app/generation/`, `backend/app/worker.py` |

O número da rota HTTP não é o número do schema JSON. Por exemplo, `/v1/terminal/snapshot` entrega `mnemos.sync/v2`; o QR e `/v4/info` negociam o protocolo local v4. O modelo e as capacidades do terminal prevalecem sobre suposições de um cliente sobre o nome da placa. O T5 Touch anuncia cinco tipos, quatro opções no máximo, formato `plain` e 128 cartões ativos, mas os produtores atuais de snapshot emitem apenas `open_recall`. Veja [o diagnóstico de conteúdo](../integration/t5-touch.md#conteúdo-e-tipos-de-cartão).

## Registro, escopo e ciclo de vida

Um cliente autenticado registra ou rotaciona a credencial em `POST /v1/terminals/register`. O registro aceita uma lista de baralhos, vazia por padrão; a seleção posterior passa por `POST /v1/terminals/{device_id}/decks`. O token devolvido é exclusivo daquele terminal e só deve ser entregue localmente em `mnemos.provision/v2`. O servidor guarda o hash, a seleção desejada e o estado reportado separadamente. A listagem, o resumo e a revogação exigem token de conta; o terminal usa seu próprio bearer para snapshot, revisões, deltas e status. Não confiar em `user_id`, `deckId` ou `cardId` enviados pelo dispositivo como prova de posse.

O campo `protocol` da resposta atual de registro ainda vale **3** em `backend/app/terminal/router.py`, enquanto o T5 Touch usa Device Protocol **4**. O aplicativo móvel escolhe rotas locais pelo `v=4` no QR e por `/v4/info`, não por essa resposta; um novo cliente não deve tratar `protocol: 3` como negociação da sessão local. Este metadado deve ser reconciliado numa alteração de código e coberto por teste cruzado.

O snapshot de conteúdo é inteiro e limitado pela capacidade informada; excesso resulta em 409, sem truncamento. O terminal preserva estado local por ID de cartão quando aplica definições. Revisões são fatos append-only identificados por ID estável; o servidor deduplica retries e pode entregar deltas com cursor `server_seq`. O estado FSRS é derivado do histórico e das configurações, e não deve ser confundido com um registro central de estado autoritativo do cartão.

## Conformidade e erros conhecidos

O schema `review-v2.schema.json` descreve `reviewedAt` em segundos. A rota `POST /v1/terminal/reviews` exige hoje `reviewedAtMs` e uma origem do enum interno (`standard` ou `multiple_choice`); o firmware envia `reviewedAt` e `source=terminal`. Assim, o envio direto recebe 422 e não pode ser anunciado como integrado. Há também risco de perda no DirectSync móvel: `_importReviews` ignora eventos de cartão ausente e `synchronize` pode confirmar toda a outbox depois de transmitir a biblioteca. Consulte [a matriz de falhas e critérios de aceite](../integration/t5-touch.md) antes de implementar uma integração externa.

Para contribuir em qualquer contrato, alterar schema, texto do protocolo, serialização do emissor, parser/validação do receptor, exemplos e testes com payload produzido pela implementação real. Execute `python shared/generate.py --check` e `python tools/schema-validator/validate_mnemos_examples.py`; os testes de componentes não substituem o ensaio físico. A versão v1 antiga e o perfil CYD estão preservados em `spec/protocol/`, sem promessa de compatibilidade automática com v2/v4.
