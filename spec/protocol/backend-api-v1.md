# Mnemos Backend Implementation Guide v1

## 1. Objetivo e independência tecnológica

Um backend compatível com Mnemos deve oferecer identidade, autorização, conteúdo canônico, histórico append-only e sincronização para dispositivos. A implementação de referência usa FastAPI, SQLAlchemy e PostgreSQL, mas isso não é requisito de compatibilidade. Qualquer stack é válida se respeitar schemas, autenticação, escopo e semântica descritos aqui.

O terminal nunca recebe o bearer token completo da conta. O app autenticado registra o terminal; o servidor cria uma credencial aleatória exclusiva daquele dispositivo, limitada aos decks atribuídos e revogável sem encerrar as sessões móveis/web.

## 2. Modelo mínimo de persistência

Recomenda-se persistir usuários, decks, cards, reviews append-only e credenciais de terminal. Para a credencial do terminal, mantenha pelo menos `device_id`, `user_id`, `token_hash`, `model`, `firmware`, `deck_ids`, `revoked`, `created_at` e `last_seen_at`.

Tokens de terminal devem ser aleatórios, de alta entropia e armazenados no servidor apenas em forma derivada (hash ou mecanismo equivalente apropriado). A implementação de referência usa SHA-256 porque o segredo é gerado aleatoriamente pelo servidor; não se trata de uma senha humana de baixa entropia.

Reviews são eventos append-only identificados por `id`. Repetir o mesmo evento é retry, não nova revisão. Cards e decks são mutáveis e precisam de revisão monotônica, ETag/controle otimista ou regra determinística de conflito. Exclusões em sistemas offline devem usar tombstones por uma janela suficiente para impedir ressurreição de dados.

## 3. Separação de credenciais

Há duas classes de bearer token. O token de conta autoriza operações humanas, inclusive registrar/listar/revogar terminais. O token de terminal autoriza somente endpoints de hardware e deve derivar o usuário/escopo no servidor. Nunca aceite `userId` do corpo como substituto da identidade autenticada.

Um reprovisionamento rotaciona o token. A perda de um terminal deve ser tratada com revogação específica daquele `device_id`.

## 4. API de conta para terminais

### `POST /v1/terminals/register`

Autenticação: bearer da conta. Corpo:

```json
{
  "device_id": "CYD-A1B2C3",
  "model": "ESP32-2432S028",
  "firmware": "0.3.0",
  "deck_ids": ["demo-redes"]
}
```

O servidor verifica que todos os decks estão ativos e pertencem à conta, cria ou rotaciona a credencial e devolve:

```json
{
  "device_id": "CYD-A1B2C3",
  "device_token": "segredo-opaco-gerado-pelo-servidor",
  "protocol": 2
}
```

### `GET /v1/terminals`

Lista terminais da conta com modelo, firmware, decks atribuídos, revogação e `last_seen_at`. Não devolve token em claro.

### `POST /v1/terminals/{device_id}/revoke`

Revoga a credencial. A próxima sincronização do hardware deve receber 401. Reativação exige novo registro/provisionamento e token novo.

## 5. API autenticada pelo terminal

### `GET /v1/terminal/snapshot?limit=<capacidade>`

Autenticação: `Authorization: Bearer <deviceToken>`. O servidor deriva `user_id` e `deck_ids` da credencial, filtra decks/cards ativos e monta `mnemos.sync/v1`.

O parâmetro `limit` é capacidade declarada pelo consumidor, não permissão para truncar. Consulte `limit+1` ou conte previamente. Se a biblioteca atribuída ultrapassar o limite, responda `409 Conflict`. Nunca escolha silenciosamente os primeiros N cards, porque isso produziria bibliotecas diferentes conforme ordenação e esconderia perda de conteúdo.

O snapshot pode ser vazio. No perfil v0.3, o backend de referência não envia estado de scheduling autoritativo; o terminal conserva `CardState` local por `cardId` ao atualizar conteúdo. Isso deve ser documentado por qualquer backend alternativo que siga a mesma estratégia.

### `POST /v1/terminal/reviews`

Recebe `mnemos.review-batch/v1`. Valide cada review, confirme `source=terminal`, confirme que o `cardId` pertence a um deck autorizado para aquela credencial e faça inserção idempotente por `review.id`.

Exemplo de resposta:

```json
{
  "accepted": 3,
  "duplicates": 1,
  "highWater": 1842
}
```

O terminal só apaga sua fila local depois de uma resposta 2xx. Em caso de timeout, deve reenviar os mesmos ids.

## 6. Validação JSON Schema

Valide na fronteira antes de regras de negócio. Compile/carregue validadores na inicialização, não em cada request. O registry precisa resolver as referências entre `sync`, `review-batch`, `deck`, `card` e `card-state`.

Exemplo Python:

```python
import json
from pathlib import Path
from jsonschema import Draft202012Validator
from referencing import Registry, Resource

schema_dir = Path("schemas")
resources = []
for path in schema_dir.glob("*.json"):
    document = json.loads(path.read_text(encoding="utf-8"))
    Draft202012Validator.check_schema(document)
    resources.append((document["$id"], Resource.from_contents(document)))

registry = Registry().with_resources(resources)
card_schema = json.loads((schema_dir / "card-v1.json").read_text(encoding="utf-8"))
card_validator = Draft202012Validator(card_schema, registry=registry)
```

Erros devem incluir caminho e mensagem. Evite devolver apenas `invalid payload`; implementadores externos precisam diagnosticar rapidamente incompatibilidades.

## 7. Autorização e escopo

Validação estrutural não prova propriedade. Para cada request de terminal, derive a credencial pelo token; aplique `user_id`; restrinja leitura aos `deck_ids`; e, na ingestão de reviews, confira se todos os `cardId` pertencem aos mesmos decks. Um terminal atribuído a um deck não deve conseguir revisar ou ler cards de outro deck por conhecer o identificador.

## 8. Snapshot atômico e capacidade

O backend deve fornecer um snapshot coerente. O terminal de referência valida tudo antes de substituir a biblioteca. Esse contrato fica mais forte se o servidor também impedir snapshots impossíveis: conteúdo incompatível com um perfil conhecido, mais cards que a capacidade ou ids inválidos devem gerar erro explícito.

Em sistemas maiores, uma negociação de capacidade pode ser registrada no cadastro do dispositivo. Mesmo assim, o valor enviado na requisição precisa ser limitado pelo servidor para evitar abuso.

## 9. Consistência e idempotência

Reviews convergem por união de ids; não use timestamp como identidade. Conteúdo mutável precisa de conflito determinístico. O backend de referência usa `server_seq` por usuário para sincronização incremental dos clientes completos, evitando depender do relógio do dispositivo.

Para hardware v0.3, snapshot completo é deliberado: simplifica recuperação e é adequado ao limite de 48 cards. Se uma futura geração comportar milhares de cards, introduza cursor/delta sem mudar silenciosamente a semântica de `mnemos.sync/v1`.

## 10. Scheduling e histórico

O histórico de review é a evidência durável. Estados de scheduling devem ser derivados por algoritmo/versionamento conhecido, não tratados como fatos históricos imutáveis. A v0.3 mantém scheduling local no terminal em sincronizações vindas do backend. Uma futura autoridade central deve definir replay determinístico, versão do scheduler e regras para reviews concorrentes antes de distribuir `card-state` como estado global.

## 11. Operação offline e retries

Backend indisponível não pode impedir estudo. O terminal enfileira reviews e tenta novamente quando o rádio está ligado. O intervalo de referência é 1800 s e pode ser configurado entre 300 e 86400 s. Polling agressivo é inadequado para bateria. Para terminais permanentemente alimentados, WebSocket/SSE/MQTT podem ser uma evolução opcional, não requisito do protocolo atual.

## 12. Segurança de transporte

Backend público deve usar HTTPS com validação de hostname/cadeia. Não aceite certificado sem validação. O firmware v0.3 exige CA em `BACKEND_ROOT_CA` para `https://` e rejeita HTTPS quando a CA está vazia; `http://` deve ser limitado a laboratório/LAN controlada.

Credenciais Wi-Fi não passam pelo backend. Elas existem somente no fluxo local app→terminal. Logs do backend nunca devem conter bearer token ou conteúdo privado integral por padrão.

## 13. Rate limiting, tamanhos e abuso

Aplique rate limiting por terminal/conta/IP conforme o modelo de ameaça. Limite batch de reviews, tamanho do body, tamanho de prompt/answer e quantidade de decks. O schema já impõe vários limites, mas o servidor deve também impor limites de transporte antes de parsear documentos excessivos.

Métricas úteis: `last_seen_at`, taxa de 401/403/409/422, idade do último sync, backlog de reviews, latência de snapshot, quantidade de cards atribuídos, falhas TLS e versão de firmware.

## 14. Observabilidade e privacidade

Logs recomendados: request-id, `device_id`, endpoint, status, latência, versão de firmware e contagens. Não registre senha Wi-Fi, token bearer, QR token ou bodies completos de cards/reviews por padrão. Em suporte técnico, use logs estruturados com redaction.

## 15. Desenvolvimento local

O emulador Android alcança a máquina host em `10.0.2.2`, mas um ESP32 físico não. Para testar sincronização direta do hardware, exponha o backend em um endereço da LAN alcançável pelo terminal ou em hostname HTTPS. O app evita provisionar `localhost`, `127.0.0.1` e `10.0.2.2` como URL de backend do hardware.

## 16. Testes de conformidade de backend

Um backend compatível deve provar pelo menos: registro com decks válidos; rejeição de deck de outro usuário; rotação de token; revogação; 401 para token inválido; snapshot restrito a decks atribuídos; 409 quando capacidade é excedida; snapshot vazio válido; review idempotente; rejeição de review fora do escopo; validação dos schemas; e persistência de histórico durante retries.

Use `docs/v0.3/examples/redes-10-cards.sync.json` como fixture pública de snapshot.

## 17. Respostas e erros

Prefira erros estruturados e estáveis. `401` para autenticação inválida, `403` para referência fora do escopo, `409` para capacidade/conflito de estado, `422` para documento semanticamente inválido e `5xx` somente para falha de servidor. Não transforme erros de autorização em 200 com campo `ok=false`.

## 18. Evolução

Mantenha parsers antigos durante janela de migração. Nunca reinterprete `mnemos.card/v1` como se fosse v2. Publique schemas antigos permanentemente se já houver dados persistidos que os referenciem. Migrações de banco devem preservar o histórico append-only e permitir rotação/revogação de credenciais sem perda de conteúdo.

## v0.4 terminal desired-state additions

Connection and content assignment are independent. `POST /v1/terminals/register` accepts an empty `deck_ids` list and returns a terminal-scoped credential. A freshly paired terminal therefore has no implicit content assignment.

`GET /v1/terminals/{device_id}/summary` returns both `desired_deck_ids` and `reported_deck_ids`, plus capacity, connectivity and last synchronization metadata.

`POST /v1/terminals/{device_id}/decks` changes only desired deck presence. It does not claim that the physical terminal has already applied the decision.

`POST /v1/terminals/{device_id}/observed` is account-authenticated and records the actual state observed by the official/compatible app immediately after a direct BLE synchronization. It exists so cloud state can converge even when the terminal had no Internet.

`POST /v1/terminal/status` is terminal-token authenticated and reports the terminal's own physical state after infrastructure synchronization.

Review authorization during reconciliation considers the union of desired scope and last validated reported scope. This allows pending reviews to leave a deck safely before that deck is removed from the terminal, while reported deck ids are still validated as belonging to the same account.
