# Mnemos Interoperability Specification v1

## 1. Status e escopo

Esta especificação define os contratos públicos de dados do ecossistema Mnemos. Ela foi criada para que aplicativo móvel, backend, terminal físico, ferramentas de importação e serviços de terceiros possam trocar conteúdo e eventos sem depender do banco Drift/SQLite do aplicativo, das classes SQLAlchemy do backend ou das estruturas C++ do firmware.

A família v1 é composta por `mnemos.deck/v1`, `mnemos.card/v1`, `mnemos.card-state/v1`, `mnemos.review/v1`, `mnemos.sync/v1`, `mnemos.review-batch/v1` e `mnemos.provision/v1`. Os arquivos normativos ficam em `schemas/`. Um implementador deve tratar esses arquivos JSON Schema como fonte de verdade estrutural e este documento como fonte de verdade semântica.

## 2. Princípios normativos

O protocolo separa conteúdo, estado de aprendizagem e histórico. `card` descreve aquilo que será estudado; `card-state` descreve o estado de agendamento de uma cópia do card; `review` é um fato histórico imutável. Uma edição textual não deve apagar histórico, e um novo algoritmo de repetição não deve exigir mudança do formato do conteúdo.

Identificadores devem ser estáveis. Um card editado mantém `id`; sua `metadata.revision` avança. Campos centrais desconhecidos são rejeitados por `additionalProperties: false`; extensões privadas devem ficar em `extensions`. Metadados temporais usam `date-time` UTC. Eventos de revisão usam segundos Unix UTC para simplificar interoperabilidade com firmware.

## 3. `mnemos.deck/v1`

Um deck é a unidade de organização de cards. `schema`, `id`, `name` e `metadata` são obrigatórios. `description` pode ser nulo. `metadata.revision` é inteiro maior ou igual a 1 e deve avançar quando o deck muda. A posse de um `deckId` nunca prova autorização; isso pertence ao backend.

```json
{
  "schema": "mnemos.deck/v1",
  "id": "demo-redes",
  "name": "Redes de Computadores",
  "description": "Fundamentos de redes e protocolos TCP/IP.",
  "metadata": {
    "language": "pt-BR",
    "updatedAt": "2026-08-16T14:00:00Z",
    "revision": 1
  }
}
```

## 4. `mnemos.card/v1`

Um card possui `schema`, `id`, `deckId`, `type`, `content` e `metadata`. `tags` e `extensions` são opcionais. `content.prompt` e `content.answer` são `contentBlock`; cada bloco declara `format` (`plain` ou `markdown`) e `text`.

Os tipos previstos no contrato público são `basic`, `typed`, `multiple_choice`, `cloze` e `true_false`. O schema exige `options` quando o tipo é `multiple_choice`. O schema público é mais amplo que a capacidade de um terminal específico: todo consumidor deve consultar capacidades antes de transferir conteúdo para hardware.

O perfil do protótipo CYD v0.3 aceita somente `type=basic` e `format=plain`. Ele rejeita Markdown e tipos que não declara em `/v2/info`; não deve haver conversão silenciosa. Um cliente externo que quiser enviar tipos mais ricos deve selecionar um dispositivo que anuncie suporte correspondente.

```json
{
  "schema": "mnemos.card/v1",
  "id": "demo-redes-04",
  "deckId": "demo-redes",
  "type": "basic",
  "content": {
    "prompt": {
      "format": "plain",
      "text": "O que ocorre no three-way handshake do TCP?"
    },
    "answer": {
      "format": "plain",
      "text": "Cliente e servidor trocam SYN, SYN-ACK e ACK para sincronizar números de sequência e estabelecer a conexão."
    }
  },
  "tags": ["redes-de-computadores"],
  "metadata": {
    "language": "pt-BR",
    "createdAt": "2026-08-16T14:00:00Z",
    "updatedAt": "2026-08-16T14:00:00Z",
    "revision": 1
  }
}
```

## 5. `mnemos.card-state/v1`

O estado é separado do conteúdo. `dueAt` e `lastReviewedAt` usam segundos Unix UTC. `intervalSeconds`, `repetitions`, `lapses` e `lastRating` descrevem o scheduling. `scheduler` é um recipiente opcional para parâmetros adicionais de algoritmo.

No provisionamento app → terminal, o app envia `states` no snapshot inicial. Na sincronização backend → terminal da v0.3, o backend de referência envia o conteúdo canônico e o terminal preserva seu estado local por `cardId`. O backend ainda não é a autoridade única de scheduling entre todos os clientes; uma implementação externa não deve inferir que `states` sempre estará presente em `mnemos.sync/v1`.

## 6. `mnemos.review/v1`

Um review é append-only. `id` precisa ser único e estável para que retries sejam idempotentes. `rating` é 1=Again/Errei, 2=Hard/Difícil, 3=Good/Acertei, 4=Easy/Fácil. `confidence` usa 0..3. `responseTimeMs` mede o tempo observado na sessão. `intervalBeforeSeconds` e `intervalAfterSeconds` são valores do scheduler no instante do evento; são históricos, não comandos para reescrever o passado.

```json
{
  "schema": "mnemos.review/v1",
  "id": "018f55a0-a111-7e11-9000-000000000001",
  "cardId": "demo-redes-04",
  "reviewedAt": 1786888800,
  "rating": 3,
  "responseTimeMs": 6200,
  "confidence": 2,
  "intervalBeforeSeconds": 120,
  "intervalAfterSeconds": 300,
  "source": "terminal"
}
```

## 7. `mnemos.sync/v1`

`mnemos.sync/v1` é um snapshot de biblioteca. Ele contém `decks`, `cards` e opcionalmente `states`. `exportedAt` identifica quando o documento foi montado; `cursor` é reservado para evolução incremental.

Aplicação de snapshot deve ser atômica: primeiro valide schema, relações deck/card, capacidades e limites; somente depois substitua o estado persistente. Um snapshot vazio é válido e significa biblioteca vazia dentro do escopo atribuído. Não se deve interpretar ausência de cards como falha automática.

Limites de hardware são capacidades, não regras do schema. O CYD v0.3 declara `maxCards=48`. Se o conjunto autorizado tiver mais cards que a capacidade solicitada, o backend de referência responde conflito de capacidade; ele nunca trunca silenciosamente.

## 8. `mnemos.review-batch/v1`

O lote transporta até 500 reviews. Cada item continua obrigado a satisfazer `mnemos.review/v1`. O servidor deve deduplicar por `review.id`. Se a confirmação da requisição se perder e o terminal repetir o mesmo lote, não deve existir uma segunda revisão.

## 9. `mnemos.provision/v1`

O documento de provisionamento é usado apenas na ligação local temporária entre app e terminal. `wifi.ssid` tem até 32 caracteres. `wifi.password` deve ser vazia para uma rede aberta ou possuir 8..63 caracteres no perfil pessoal atualmente suportado. Redes Enterprise/captive portal não fazem parte do perfil CYD v0.3.

`backend` é opcional e, quando presente, contém URL base e token restrito ao terminal. O token de conta do app nunca deve ir para o hardware. A senha Wi-Fi não deve aparecer em QR, logs, respostas diagnósticas ou backend.

## 10. Extensões

Extensões privadas devem ser agrupadas sob `extensions` com namespace estável, por exemplo `com.exemplo.importer` ou `mnemos.ai`. Um produtor não deve criar novos campos no nível raiz e continuar anunciando `mnemos.card/v1`, porque isso tornaria a validação ambígua.

## 11. Versionamento

O consumidor seleciona parser pelo valor `schema`. Uma mudança incompatível — remoção de campo obrigatório, alteração de unidade, nova semântica para campo existente — exige um novo identificador principal, por exemplo `mnemos.card/v2`. Um artefato publicado como `card/v1.json` deve permanecer semanticamente estável.

Adicionar documentação ou esclarecer semântica sem alterar validade é compatível. Adicionar campo opcional pode ser compatível somente se a política `additionalProperties` e os consumidores existentes forem considerados. Na dúvida, publique nova versão.

## 12. Validação e regras de negócio

JSON Schema valida estrutura, não autorização. Após validar estrutura, o backend precisa verificar propriedade do deck, pertencimento do card, capacidade, escopo do terminal, revogação e demais regras. Um documento pode ser estruturalmente válido e ainda assim ser proibido para aquela credencial.

O arquivo `docs/v0.3/examples/redes-10-cards.sync.json` é o exemplo canônico desta versão. Ele contém exatamente um deck `Redes de Computadores`, dez cards `basic/plain` e seus estados iniciais.

## 13. Perfil de conformidade do CYD v0.3

O endpoint `/v2/info` anuncia capacidades. O perfil de referência possui `cardTypes=["basic"]`, `contentFormats=["plain"]`, `maxCards=48` e `maxPayloadBytes=90000`. Implementadores devem negociar com esses valores e não assumir que todo hardware Mnemos terá as mesmas limitações.

## 14. Limitações conhecidas da v0.3

O banco local atual do app não possui `createdAt` independente para cards; durante a exportação, `updatedAt` é usado também como valor de compatibilidade para `createdAt`. O snapshot de backend não distribui estado de scheduling autoritativo entre todos os clientes. O terminal CYD oferece apenas cards `basic/plain`. Essas limitações são de implementação, não devem ser reproduzidas como requisitos permanentes por integrações externas.
