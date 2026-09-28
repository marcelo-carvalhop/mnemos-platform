# Implementação do backend e contratos de serviço

O backend de referência combina FastAPI, SQLAlchemy/Alembic, PostgreSQL e um worker que consome `generation_jobs`. `compose.yaml` reúne serviços de desenvolvimento, incluindo MinIO para objetos temporários. Os modelos em [`backend/app/models.py`](../../backend/app/models.py) e o [modelo de dados](../architecture/data-model.md) descrevem persistência; o contrato interoperável fica em [`spec/`](../../spec/README.md). A API é versionada em `/v1`, independentemente da versão de cada schema no corpo.

## Identidade e sincronização dos clientes

`backend/app/main.py` monta rotas de autenticação, conta, quota, geração, sync e terminal. A sessão humana usa bearer da conta, com refresh tokens armazenados apenas por hash. Móvel e web usam `/v1/sync/push` e `/v1/sync/pull`; o servidor atribui `server_seq` por usuário, aplica autorização e devolve deltas a partir do cursor. Conteúdo mutável carrega timestamps e tombstones; revisões, resets de progresso e mudanças de meta preservam seu caráter histórico. A atualização/exclusão de reviews é proibida no banco por trigger. Ao implementar outro cliente, não construir o próximo cursor por relógio local nem inferir posse a partir de identificadores recebidos.

A geração assistida passa por upload temporário, reserva de cota, job em banco e aprovação de sugestões. A API e o worker são processos distintos; criar um job não executa o modelo dentro do request. O Compose fornece dependências locais, não evidência de uma implantação pública. Segredos, backup, TLS e retenção precisam de configuração operacional própria.

## Credencial física e rotas

| Identidade | Operações relevantes | Regra |
| --- | --- | --- |
| Conta | `POST /v1/terminals/register`, `GET /v1/terminals`, seleção em `/{device_id}/decks`, resumo, observação e revogação | O usuário é derivado do bearer. Registro rotaciona o token exclusivo do terminal. |
| Terminal | `GET /v1/terminal/snapshot`, `POST/GET /v1/terminal/reviews`, deltas de resets/configurações e `POST /v1/terminal/status` | O servidor deriva conta, baralhos desejados e reportados do token físico. |

`snapshot` recebe `limit` entre 1 e 256 e `schema=mnemos.sync/v2`; o código responde 409 caso a biblioteca ativa exceda o limite, inclusive quando o hardware informa 128. Seleção desejada e conteúdo observado não são a mesma coisa. Reviews de cartões fora da união de baralhos desejados e reportados recebem 403. Token ausente, inválido ou revogado recebe 401. Um envio idempotente usa o mesmo ID de evento no retry, e a resposta inclui `accepted`, `duplicates` e `highWater`.

O validador de `POST /v1/terminal/reviews` requer `schema=mnemos.review/v2`, `id`, `cardId`, `reviewedAtMs`, `schedulerRating` e `source` do enum `ReviewSource`; aceita até 500 eventos por lote. O endpoint retorna 422 para item inválido. Esse dialeto não coincide com o schema público v2 nem com as linhas escritas pelo T5 Touch, que usam `reviewedAt` em segundos e `source=terminal`. A incompatibilidade e a recomendação de adaptação estão em [integração T5 Touch](../integration/t5-touch.md). A projeção atual do snapshot também converte todo card em `open_recall` por limitação de autoria/persistência central; não declarar outros tipos integrados só porque o firmware os interpreta.

## Verificação e operação

Suba os serviços e aplique as migrações pelo procedimento em [`backend/README.md`](../../backend/README.md). `/healthz` atesta o processo; `/readyz` consulta o banco. Execute a suíte com banco de testes isolado, verifique o contrato gerado e use fixtures reais do firmware para testar o terminal. Um teste que monta à mão `reviewedAtMs` comprova o endpoint isolado, mas não o envio da outbox física. Em produção, registrar métricas de status, latência, backlog, respostas 401/403/409/422 e versão de firmware, sem registrar tokens, senha Wi-Fi ou corpos completos de estudo.
