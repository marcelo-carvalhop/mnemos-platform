# Revisão técnica — arquitetura v1

**Documento revisado:** [`2026-08-08-arquitetura-tecnica-design.md`](2026-08-08-arquitetura-tecnica-design.md)
**Spec funcional:** [`spec-funcional-app-flashcards.md`](../../../spec-funcional-app-flashcards.md)
**Data:** 2026-08-08
**Status:** revisão — nenhuma alteração aplicada ao documento original

> Escrito em português para acompanhar a spec funcional. Identificadores, nomes de coluna e termos de API ficam em inglês.

---

## Veredito

O princípio organizador do §3 — revisão como evento imutável, `card_state` como cache reconstruível — está correto e é o que dá coerência ao resto. As decisões de FSRS client-side, offline-first com SQLite como fonte de verdade, e `pending_cards.decision` em vez de delete no triage são todas boas e bem justificadas.

Os problemas se concentram em três lugares:

1. **Sincronização** — o protocolo do §6, como escrito, quebra em dois dispositivos e em reinstalação. Não é um detalhe: é o caminho pelo qual o produto perde o histórico do usuário.
2. **Determinismo do scheduler** — três coisas fora do log de revisões alimentam o FSRS (parâmetros, meta de retenção, fuzz) e nenhuma está no documento. Sem elas, "replay é determinístico" é falso.
3. **Subsistemas ausentes** — notificações, busca, TTS, export, conta anônima e billing por loja não aparecem em lugar nenhum, e pelo menos dois deles têm consequência de schema.

O §7 (geração) está tecnicamente preciso nos números que verifiquei contra a API atual, com uma contradição interna e algumas alavancas de custo não exploradas.

Severidade: **[P0]** quebra v1 · **[P1]** dívida cara de corrigir depois · **[P2]** melhoria.

---

## 1. Sincronização

### 1.1 [P0] `reviews` push-only impede o segundo dispositivo de reconstruir o estado

§6 diz *"Reviews — push-only. Append locally, push, never modify."* e o §5.5 confirma que o servidor espelha o tier 2. Mas não existe caminho de **pull** para revisões.

Consequência direta: o tablet nunca vê as revisões feitas no celular. Como `card_state` é derivado exclusivamente do log local, os dois dispositivos calculam `due_at` diferentes a partir de históricos diferentes. O card revisado hoje no celular aparece vencido amanhã no tablet, é revisado de novo, e o FSRS de ambos passa a ver um histórico que não existiu. Reinstalar o app tem o mesmo efeito: o histórico está no servidor, mas nada o traz de volta.

O próprio documento se contradiz: §10.2 pede o teste *"concurrent offline reviews merge to the union"* — união só existe com pull.

**Correção:** revisões sincronizam nos dois sentidos, mas como **união append-only**, não como LWW. Continua sem resolução de conflito — é `INSERT ... ON CONFLICT (id) DO NOTHING` dos dois lados. Isso preserva integralmente a propriedade do §3.2; só o nome "push-only" estava errado. Vale para `progress_resets` pelo mesmo motivo (§5.10 no tablet precisa respeitar o reset feito no celular).

O documento também deve nomear o **bootstrap**: dispositivo novo faz um pull completo de tiers 1 e 2 antes de calcular qualquer `card_state`, e a UI precisa de um estado "restaurando histórico" — para um usuário de dois anos isso não é instantâneo.

### 1.2 [P0] Watermark de pull baseado em `updated_at` do cliente perde linhas em silêncio

§6 define pull como *"a delta by `updated_at` watermark"*, e `updated_at` é gravado pelo dispositivo (é o mesmo campo usado como critério de LWW). Dois modos de falha, ambos silenciosos:

- **Relógio adiantado/atrasado.** Dispositivo B com relógio 10 minutos atrás grava `updated_at` no passado. O dispositivo A, que já puxou até `T`, nunca mais verá essa linha — ela nasceu abaixo da marca d'água. Um relógio adiantado é pior: a linha vence todo LWW futuro para sempre.
- **Ordem de commit.** Mesmo com relógios perfeitos, uma transação longa que começa em `T1` e commita depois de outra que começou em `T2 > T1` fica invisível para quem já puxou até `T2`.

**Correção:** separar as duas responsabilidades do timestamp.

| Campo | Quem escreve | Para quê |
|---|---|---|
| `updated_at` (ms UTC) | cliente | critério de LWW, desempate por `device_id` |
| `server_seq` (bigint) | servidor | cursor de pull, monotônico por usuário |

O pull vira keyset sobre `(server_seq, id)`, nunca sobre tempo. `server_seq` sai de uma sequência por usuário atribuída dentro da mesma transação do upsert (`SELECT ... FOR UPDATE` na linha do usuário, ou uma sequence dedicada). Paginação por keyset também elimina o bug clássico de linhas com timestamp idêntico caindo na fronteira da página.

Vale explicitar o comportamento sob relógio errado no cliente também: rejeitar `updated_at` mais que N minutos no futuro em relação ao relógio do servidor, e clampar.

### 1.3 [P0] Tombstones sem política de retenção

O §6 introduz `deleted_at` como tombstone mas não diz por quanto tempo eles vivem. Sem GC, o payload de pull cresce para sempre. Com GC, um dispositivo offline por mais tempo que a janela de retenção ressuscita linhas apagadas.

**Correção:** retenção explícita (90 dias é razoável) e uma regra dura: se `last_pulled_server_seq` do dispositivo é anterior ao horizonte de GC, o servidor responde `410 resync_required` e o cliente faz full resync. Isso é uma linha de código quando decidido agora e uma migração dolorosa quando descoberto em produção.

### 1.4 [P1] `card_tags` não tem história de sincronização

```sql
card_tags(card_id, tag)
```

É tier 1 (conteúdo, LWW bidirecional) mas não tem `updated_at`, `deleted_at` nem `device_id`. Remover uma tag offline em um dispositivo e sincronizar faz a tag reaparecer — não há tombstone para dizer que ela sumiu.

**Correção recomendada:** tags viram **valor do card**, não entidade própria. `cards.tags` como `text[]` no Postgres e JSON no SQLite; a unidade de LWW passa a ser a linha do card, que é o que o §5.4/§5.7 já faz na prática (tags são sempre editadas junto com o card). Uma tabela `card_tags` local, derivada por trigger, continua servindo o filtro do §5.10 sem participar do sync.

### 1.5 [P1] LWW em linha larga perde edições concorrentes de campos diferentes

`cards` mistura conteúdo (`front`, `back`) com estado efêmero (`buried_until`) e intenção do usuário (`status`). Com LWW por linha: enterrar o card no celular e corrigir uma vírgula no tablet → uma das duas ações some.

Pior: `buried_until` é estado que expira em 24h. Sincronizá-lo como conteúdo significa que uma escrita trivial e diária compete com edições reais de texto.

**Correção:** separar as unidades de LWW. `cards` mantém conteúdo; uma tabela pequena `card_flags(card_id, status, buried_until, updated_at, device_id)` carrega o estado volátil com seu próprio relógio. Alternativa mais barata: timestamps por campo apenas para os dois campos voláteis.

### 1.6 [P1] Outbox: ordem de dependência e coalescing não estão definidos

§4 cita `sync/ outbox push + delta pull` e §6 diz que o push é *"chunked and resumable"*. Faltam três regras que o implementador vai ter que inventar:

- **Ordem.** Um `card` que referencia um `deck` criado offline não pode ser enviado antes do deck, ou a FK do servidor rejeita. Push em ordem de dependência (decks → cards → reviews → decisions) ou FKs `DEFERRABLE`.
- **Coalescing.** Para entidades LWW, o outbox empurra o **estado atual** da linha, não cada edição. Dez correções de vírgula offline = um push.
- **Idempotência.** Cada chunk com `Idempotency-Key`; aplicação transacional por chunk; retry nunca duplica.

### 1.7 [P1] `pending_cards` é uma terceira forma de sync não especificada

§5.4 diz que `pending_cards` é *"server-sourced mirror; `decision` is written locally"* e que a decisão *"pushes back like any other mutation"* — mas §6 só define duas formas (append-only e LWW bidirecional). Esta é uma terceira: pull unidirecional do servidor + push de uma única coluna.

Além disso, o §7.7 tem uma corrida: quem cria a linha em `cards` quando a decisão sincroniza — o cliente que aprovou, ou o servidor ao receber a decisão? Se ambos, o card duplica.

**Correção elegante:** o `pending_card.id` **vira** o `cards.id` na aprovação. O cliente cria a linha localmente com esse id e a empurra; o servidor, ao receber a decisão, faz upsert idempotente. Reenvio do mesmo push não produz um segundo card, por construção — mesma lógica do §3.2 aplicada à aprovação.

---

## 2. Determinismo do scheduler

O §3 afirma que cada dispositivo recomputa o estado a partir do log. Isso só vale se **tudo** que entra no cálculo estiver no log ou sincronizado. Três coisas não estão.

### 2.1 [P0] `settings` não sincroniza, mas a meta de retenção alimenta o FSRS

§5.4: *"`settings` and `sync_state` never leave the device."* E §13 fixa a meta de retenção em 90% "armazenada como setting".

`desired_retention` é **entrada do cálculo de intervalo** no FSRS — o intervalo é `S · f(R_desejado)`. Se o valor vive só no dispositivo, dois dispositivos com o mesmo histórico calculam `due_at` diferentes. E se um dia a meta virar configurável (§5.12 pede isso), a divergência vira visível.

**Correção:** partir `settings` em dois.

| Sincronizado (LWW) | Local |
|---|---|
| `desired_retention`, `fsrs_params`, `fsrs_params_version`, `new_per_day`, `daily_goal`, `timezone`, `day_cutoff_hour` | voz de TTS, tema, horário de notificação, `sync_state` |

### 2.2 [P0] Parâmetros do FSRS não existem no modelo de dados

Não há coluna, tabela ou campo para o vetor de pesos do FSRS. Se v1 usa os pesos default e nunca otimiza, tudo bem — mas isso precisa estar escrito como decisão, porque:

- Uma atualização do app que mude a versão do algoritmo (FSRS-5 → 6) invalida **todos** os `card_state`. Precisa de `fsrs_params_version` em `card_state` e rebuild total quando divergir.
- Se algum dia houver otimização por usuário, os pesos passam a ser dado sincronizado e o item 2.1 já cobre o caminho.

### 2.3 [P0] Fuzz do FSRS quebra o property test do §10 e diverge entre dispositivos

O FSRS aplica, por padrão em várias portas, um *fuzz* aleatório aos intervalos ≥ ~2,5 dias, para espalhar a carga. Isso é aleatoriedade não semeada.

Consequências: o teste *"replaying a log twice yields identical state"* (§10.1) falha de forma intermitente, e — pior — dois dispositivos que reproduzem o mesmo log chegam a `due_at` diferentes, destruindo a premissa do §3.

**Correção:** desligar o fuzz explicitamente, ou semeá-lo de forma determinística a partir de `(card_id, review_id)`. Verificar o default da porta `dart-fsrs` e fixá-lo no wrapper `Scheduler` — é exatamente o tipo de coisa que o §4.1 diz que o wrapper existe para controlar.

### 2.4 [P1] A interface do `scheduler` está incompleta

```dart
CardState replay(List<Review> history);
Map<Grade, Duration> preview(CardState state);
```

Faltam duas entradas obrigatórias:

- **`preview` precisa do agora.** O intervalo resultante depende da retrievabilidade no momento da revisão, que depende de quanto tempo passou desde a última. Um card vencido há 3 dias não produz os mesmos quatro intervalos de um revisado no dia.
- **Ambas precisam dos parâmetros.** Ver 2.1/2.2.

Além disso, `preview` e a aplicação real da nota precisam compartilhar **um único caminho de código**, senão o §5.8.3 volta a poder mentir:

```dart
CardState apply(CardState s, Grade g, DateTime at, FsrsParams p);
CardState replay(List<Review> h, List<ProgressReset> r, FsrsParams p);
Map<Grade, Duration> preview(CardState s, DateTime now, FsrsParams p)
  => {for (final g in Grade.values) g: apply(s, g, now, p).dueAt.difference(now)};
```

Com `preview` derivado de `apply`, a propriedade *"preview always agrees with what the next review actually writes"* é verdadeira por construção, não por teste.

### 2.5 [P1] `computed_from_review_id` assume ordem de chegada

O watermark incremental funciona quando revisões chegam em ordem. Com sync bidirecional (item 1.1), uma revisão do dispositivo B com `reviewed_at` **anterior** ao watermark pode chegar depois. O replay incremental a ignora e o estado fica errado.

**Correção:** o watermark é `(computed_through_reviewed_at, computed_through_review_id)`, e todo insert com `reviewed_at` abaixo dele marca o card como `dirty`, forçando replay completo daquele card. Replay de um card é barato; é o rebuild da conta inteira que não é. Uma flag `dirty` + job de reconciliação em background resolve.

---

## 3. Modelagem e banco

### 3.1 [P1] Nenhuma estratégia de índices

O documento não menciona um índice. Os que a carga exige:

```sql
-- fila do dia (o hot path)
CREATE INDEX ON card_state(due_at) WHERE due_at IS NOT NULL;
-- replay por card
CREATE INDEX ON reviews(card_id, reviewed_at, id);
-- listagem e contagem por baralho
CREATE INDEX ON cards(deck_id) WHERE deleted_at IS NULL;
-- pull (servidor)
CREATE INDEX ON cards(user_id, server_seq);
CREATE INDEX ON decks(user_id, server_seq);
-- heatmap e estatísticas (servidor)
CREATE INDEX ON reviews(user_id, reviewed_at);
```

A query da fila também precisa considerar `status` e `buried_until` — se esses saírem para `card_flags` (item 1.5), é um join, e o índice tem que refletir isso.

### 3.2 [P1] Imutabilidade: `RULE` do Postgres é a ferramenta errada

§5.2 diz *"enforced by a SQLite trigger and a Postgres rule"*. `RULE` é um mecanismo legado do Postgres com semântica surpreendente em vários casos. Duas defesas melhores, e vale ter as duas:

```sql
-- 1. privilégio: a role da aplicação simplesmente não pode
REVOKE UPDATE, DELETE ON reviews FROM app_role;
GRANT INSERT, SELECT ON reviews TO app_role;

-- 2. trigger: erro explícito se alguém tentar via role privilegiada
CREATE TRIGGER reviews_immutable BEFORE UPDATE OR DELETE ON reviews
  FOR EACH ROW EXECUTE FUNCTION raise_immutable();
```

A revogação de privilégio é mais forte e mais barata que o trigger. Deixar um caminho administrativo separado, documentado, para exclusão de conta (item 4.6).

### 3.3 [P1] IDs gerados pelo cliente exigem verificação de posse no servidor

§5.6 escolhe UUIDv7 client-generated — decisão certa. Mas ela move a atribuição de identidade para fora do perímetro de confiança. O servidor precisa, em todo upsert:

- nunca aceitar `user_id` vindo do payload — sempre derivar do token;
- verificar que o `deck_id` de um card pertence ao usuário que empurra (senão é IDOR de escrita entre contas);
- verificar que o `card_id` de uma revisão pertence ao usuário.

Row-Level Security no Postgres é a resposta estrutural: uma policy `user_id = current_setting('app.user_id')::uuid` em cada tabela torna o vazamento entre contas impossível por construção, em vez de depender de um `WHERE` que alguém pode esquecer.

### 3.4 [P2] Guardar o resultado na linha de revisão vale muito e não fere a imutabilidade

Sugestão de adicionar a `reviews`:

```sql
interval_days_after, stability_after, difficulty_after,  -- escritos uma vez, no insert
scheduler_version, app_version
```

O que isso compra:

- **Graduação (§5.11)** vira `WHERE interval_days_after >= 180 AND ...` em vez de exigir replay.
- **Gráficos históricos** (retenção ao longo do tempo, evolução de memória) viram query direta.
- **Auditoria** de mudança de algoritmo: dá para comparar o que o app calculou na época com o que o replay calcula hoje.

Não viola o §3: são valores escritos no insert, nunca atualizados. Ressalva importante para documentar: são **advisórios**, não autoritativos — uma revisão criada no dispositivo A com parâmetros diferentes pode discordar do replay no dispositivo B. O `card_state` continua sendo derivado do replay, não dessas colunas. (É exatamente o que o Anki faz no `revlog`, e pela mesma razão.)

### 3.5 [P2] Detalhes de tipo e semântica

- **`grade`** como `smallint` 1–4 com mapeamento documentado (1=errei … 4=fácil), nunca string, nunca renumerado.
- **`decks.parent_id`** precisa de: prevenção de ciclo na escrita (cliente e servidor), limite de profundidade, e semântica definida de delete (soft-delete da subárvore?) e de `archived_at` vs `deleted_at` — baralho arquivado entra na sessão de estudo?
- **`decks.version`** não tem semântica definida. Ou define agora (inteiro monotônico incrementado a cada mudança de conteúdo, para o §7 da spec funcional) ou marca explicitamente como *reservado, não usado em v1*. O risco desses campos não é a migração de schema (adicionar coluna nullable é trivial nos dois bancos) — é acumular semântica implícita divergente entre cliente e servidor.
- **Revisões de cards apagados** precisam de regra: o histórico sobrevive (as estatísticas dependem dele), mas `SUM(stability)` do §8 filtra por cards ativos. Já está implícito; vale escrever.

---

## 4. Backend e operação

### 4.1 [P1] Trocar Redis/`arq` por fila no próprio Postgres

§4.2 escolhe `arq` sobre Redis. Três argumentos contra, todos alinhados ao próprio princípio declarado do documento (*"one FastAPI service owns everything"*, §6):

1. **A reserva de cota e o enfileiramento precisam ser atômicos.** §7.6 diz que a cota é reservada no enqueue. Com a cota no Postgres e a fila no Redis, isso é um commit distribuído — e o modo de falha é cobrar cota de um job que nunca rodou.
2. **`generation_jobs` já vive no Postgres.** A fila no Redis duplica o estado do job em dois lugares que podem divergir.
3. **Redis como fila é at-least-once com perda em restart sem persistência.** Para um job que consome cota paga, isso é ruim.

`SELECT ... FOR UPDATE SKIP LOCKED` sobre `generation_jobs` dá uma fila transacional, durável e sem infraestrutura nova, no volume que esse produto terá por anos. Reservar cota e enfileirar viram um único `INSERT` + `UPDATE` na mesma transação.

Se Redis ficar (é legítimo, `arq` é ergonômico), então documentar a compensação: reaper de reservas órfãs quando o worker morre entre o enqueue e o start.

### 4.2 [P1] Cota: aritmética sob concorrência e reservas órfãs

§7.6 descreve o ciclo reserve/commit/release mas não a mecânica. Duas armadilhas:

- **Read-then-write.** `SELECT used FROM quota` seguido de `UPDATE` é uma corrida clássica: duas gerações simultâneas passam pelo limite. Fazer em um comando:
  ```sql
  UPDATE quota_usage
     SET reserved = reserved + :n
   WHERE user_id = :u AND period = :p
     AND used + reserved + :n <= limit
  RETURNING reserved;
  ```
  Zero linhas retornadas = cota esgotada. É a mesma correção do §10.3 (*"quota accounting under concurrent requests"*) — o teste está previsto, o mecanismo não.
- **Reserva vaza.** Worker morre depois do enqueue: a reserva fica para sempre e o usuário perde cota que nunca usou. Reserva precisa de `expires_at` e um job que libera as vencidas.

Falta também definir o **limite de jobs concorrentes por usuário** (senão 20 gerações entram na fila de uma vez) e o **fuso do período** — "20 gerações por mês" em UTC ou no fuso do usuário? Escolher e escrever.

### 4.3 [P1] Cota deve ser contada em créditos, não em gerações

§7.3 identifica corretamente que imagens dominam o custo e que *"quota must account for images"*. Mas §7.6 e §13 definem a cota como "20 gerações/mês". As duas afirmações não fecham.

Sugestão: armazenar as duas coisas desde já — `generations_count` e `credits_consumed` (ou tokens de entrada/saída, que é o dado bruto). Enforcement em v1 pode ser por contagem simples (é o que a tela precisa mostrar), mas com o dado de custo real gravado desde o primeiro dia dá para calibrar o preço sem migração e sem adivinhação. Uma foto de quadro de aula pode custar 10× uma geração por tópico.

### 4.4 [P1] Upload de PDF e fotos não está no documento

§7.1 fala em `document` (base64) e `image`, mas não em como o arquivo chega ao servidor. Mandar base64 dentro de um JSON pelo FastAPI significa carregar o arquivo inteiro na memória do processo web — um PDF de 32MB vira ~43MB de base64 mais o parse.

Opções, em ordem de preferência:
1. Upload direto para object storage (S3/R2) com URL pré-assinada; o worker busca de lá. Retry não reenvia o arquivo.
2. Multipart streaming com limite de tamanho aplicado **antes** de bufferizar.

Vale considerar a **Files API** da Anthropic para o mesmo fim: sobe o documento uma vez (limite de 500MB por arquivo, header beta `files-api-2025-04-14`) e referencia por `file_id` nas chamadas — útil se um job precisar de mais de uma passagem sobre o mesmo material.

### 4.5 [P1] Billing pela loja é obrigatório e não aparece no documento

§5.13 da spec funcional pede assinatura, e o §12 tem "Quota & billing" como sub-projeto. Mas assinatura digital consumida dentro do app **precisa** passar pela App Store (diretriz 3.1.1) e pelo Google Play — Stripe in-app é rejeição na revisão. Isso tem consequências concretas:

- validação de recibo no servidor (App Store Server Notifications v2, Google Play RTDN via Pub/Sub);
- `subscriptions` guarda o *entitlement* derivado, não o recibo cru como fonte de verdade;
- a "assinatura inclusa na compra do aparelho" (§5.13) é um caminho de entitlement **fora** das lojas — código promocional ou concessão pelo servidor —, que precisa coexistir com o estado vindo da loja;
- estados chatos que precisam existir no modelo: em período de graça, expirado, reembolsado, em pausa.

Nada disso muda a arquitetura, mas muda o schema e vale um parágrafo antes de o sub-projeto 8 começar.

### 4.6 [P1] LGPD, export e exclusão de conta

Produto brasileiro, dado pessoal (fotos de caderno podem conter qualquer coisa). Três lacunas:

- **Export (§5.12)** está na spec funcional e ausente da arquitetura. Endpoint que devolve JSON/zip com decks, cards, revisões — barato de fazer com o modelo atual.
- **Exclusão de conta** colide com `reviews` append-only. Precisa de caminho administrativo explícito (item 3.2) e de decisão sobre o que fica: apagar tudo ou anonimizar.
- **Retenção do material de origem.** PDFs e fotos enviados: apagar quando o job termina, ou reter N dias para permitir retry? Escolher e escrever — é a diferença entre um parágrafo na política de privacidade e um incidente.

### 4.7 [P2] Observabilidade e detecção de divergência de sync

§9 diz *"Sync failures are silent and retried; a user who never opens Ajustes should never learn that sync exists."* Silencioso para o usuário: certo. Silencioso para você: perigoso — significa que perda de dado não gera sinal.

- **Silencioso no app, barulhento na telemetria.** Métricas de sucesso/latência de push e pull, contagem de conflitos LWW resolvidos, tamanho do outbox.
- **Checksum de divergência.** Periodicamente o cliente manda um hash de `(id, updated_at)` por tabela; o servidor compara. Divergência é o único jeito de descobrir que a marca d'água comeu uma linha (item 1.2) antes do usuário reclamar.
- **Escape hatch em Ajustes:** "sincronizar agora" + "última sincronização em X" + "reenviar tudo". Não contradiz o §9 — só dá um lugar para o suporte apontar.
- **Custo por usuário.** Tokens gastos por geração, por usuário, por dia. Sem isso a cota é adivinhação e um bug vira fatura.

### 4.8 [P2] Migrações e versionamento de protocolo

Offline-first significa dispositivos vários meses atrás. Não está no documento:

- migrações do `drift` testadas **a partir de cada versão anterior**, não só da última;
- schema aditivo por padrão (adicionar coluna nullable, nunca renomear);
- `protocol_version` no handshake de sync e `min_supported_app_version` no servidor, para que um cliente muito antigo receba "atualize o app" em vez de corromper dados.

### 4.9 [P2] Autenticação e a conta anônima

§13 decide *"account creation after the first generation"*. Isso implica um período anônimo com consequências não tratadas:

- **Abuso de cota grátis.** Sem conta, a cota é atrelada a quê? Se for ao dispositivo, reinstalar zera. Sugestão: token de dispositivo anônimo emitido no primeiro boot, cota atrelada a ele, migrada para a conta no signup; App Attest / Play Integrity só se o abuso virar real.
- **Merge no login.** Usuário instala, gera cards anonimamente, depois entra numa conta **existente** que já tem dados. Precisa de decisão: mesclar, descartar local, ou perguntar.
- **Nunca deslogar offline.** Falha de refresh sem rede não pode limpar a sessão — o app inteiro funciona offline; expulsar o usuário por causa de sync é o pior bug possível aqui.
- Refresh tokens: rotação com detecção de reuso, armazenados com hash.

### 4.10 [P2] Rate limiting e teto de custo

Cota controla o custo por usuário legítimo. Falta o resto: rate limit por usuário e por IP, teto diário absoluto por conta, e um kill switch global com alarme de orçamento. Um bug de retry em loop numa API de $5/$25 por MTok é caro rápido.

---

## 5. Pipeline de geração (§7)

Verifiquei os números do §7 contra a API atual. **A maior parte está correta:** Opus 5 a $5/$25 por MTok, 1M de contexto, visão de alta resolução com 2576px no lado maior e até ~4784 tokens por imagem, mínimo de cache de 512 tokens, limites de PDF de 32MB e 600 páginas (600 vale porque Opus 5 é modelo de 1M — modelos de 200k ficam em 100 páginas), e `output_config.format` sem suporte a `maxLength`. Os pontos abaixo são o que falta ou está inconsistente.

### 5.1 [P0] Contradição no prompt caching: `level` não pode estar no prefixo

§7.3 diz que o system prompt é *"byte-identical across every generation"* e no mesmo parêntese lista o conteúdo dele: *"(Portuguese, character limits, **level**, pedagogy rules)"*.

`level` é justamente o que varia por requisição (§5.5: introdutório/intermediário/avançado). Caching é **prefix match** — um byte diferente invalida tudo dali para frente. Com `level` no prefixo, o cache nunca é lido: só se paga o prêmio de escrita (1,25×) e nunca o desconto de leitura (0,1×).

**Correção:** `level` vai **depois** do breakpoint, junto com o tópico e o documento. Ou três variantes estáticas do prefixo, se a instrução de nível for longa o bastante para justificar.

### 5.2 [P1] TTL do cache torna o ganho hipotético no padrão de uso deste produto

O TTL default é **5 minutos** (há opção de 1 hora, ao custo de 2× na escrita em vez de 1,25×). O cache é compartilhado na organização, então o que importa é a taxa agregada de gerações, não a de um usuário.

O ponto de equilíbrio com TTL de 5 min são **duas** requisições dentro da janela; com 1 hora, três. Enquanto o volume for baixo, o cache custa mais do que economiza. Recomendações:

- instrumentar `usage.cache_read_input_tokens` desde o primeiro dia — se for zero, algo invalida o prefixo (e o item 5.1 é o suspeito número um);
- decidir 5m vs 1h por medição, não por default;
- não tratar o caching como economia garantida no modelo de custo.

### 5.3 [P1] `effort` e thinking: a maior alavanca de custo, ausente do documento

Duas coisas não mencionadas no §7:

- **No Opus 5, thinking está ligado por padrão.** Omitir o parâmetro `thinking` faz o modelo pensar (diferente do Opus 4.8/4.7). Isso consome tokens de saída — os caros — e conta contra `max_tokens`.
- **`output_config.effort`** (`low`/`medium`/`high`/`xhigh`/`max`, default `high`) controla profundidade e gasto.

Escrever 15 flashcards a partir de texto fornecido não é tarefa de raciocínio profundo. `effort: "low"` ou `"medium"` provavelmente entrega qualidade equivalente por uma fração do custo e da latência — e latência importa aqui, porque o §5.5 promete "alguns segundos".

Isso é uma alavanca comparável ou maior que trocar Opus 5 por Sonnet 5, e ortogonal a ela. Ordem sugerida de experimentação: varrer `effort` no modelo atual, depois avaliar o modelo. Vale um parâmetro de configuração e uma linha no §7.3.

*(Nota lateral sobre a comparação de custo do §7.3: Sonnet 5 está a $3/$15, mas com preço introdutório de $2/$10 por MTok até 31/08/2026 — hoje é 08/08. Se houver benchmark a fazer, a janela é agora.)*

### 5.4 [P1] Falta o estado de erro "o modelo recusou"

§9 lista os erros de geração: rede, cota, tópico vago, PDF grande demais, foto ilegível, material insuficiente. Falta um: o Opus 5 tem salvaguardas de segurança reforçadas e pode **recusar** a requisição — HTTP 200 com `stop_reason: "refusal"` e uma categoria em `stop_details`, não um erro HTTP.

Material de estudo real cai nisso ocasionalmente: uma questão de bioquímica, um capítulo de segurança da informação num curso de TI, uma prova de toxicologia. Código que lê `response.content[0]` sem checar `stop_reason` quebra.

**Correção:** checar `stop_reason` antes de ler o conteúdo; adicionar `error_code` correspondente ao job; **não cobrar cota** (uma recusa antes de qualquer saída não é cobrada pela API); e considerar o parâmetro `fallbacks: "default"` (beta `server-side-fallback-2026-07-01`), que reexecuta a requisição recusada em outro modelo dentro da mesma chamada, roteando por categoria de recusa. Para um app de estudo, recuperar a geração em vez de mostrar um erro incompreensível é a diferença entre um bug e um não-evento.

### 5.5 [P1] Contagem de caracteres: o "mesmo constante" não garante a mesma contagem

§7.5 promete que *"the client editor, the preview, and this server-side stage all read the same constants"*. Constante compartilhada não basta — o que falta é a **mesma função de contagem**.

`String.length` em Dart conta unidades UTF-16. `len()` em Python conta code points. Para "ção" os dois dão 3. Para um caractere com acento combinante decomposto (NFD), Dart e Python dão 2 e o usuário vê 1. Resultado: o editor aceita, o servidor derruba, ou vice-versa.

**Correção:**
- normalizar tudo em **NFC** na entrada, dos dois lados;
- contar **grapheme clusters** (`characters` package no Dart; `regex`/`grapheme` no Python), não unidades de código;
- definir a regra em um lugar e testá-la com um conjunto de casos compartilhado (acentos compostos, emoji, hífen).

E sobre "mesmas constantes" entre Dart e Python: uma constante duplicada em dois idiomas diverge. Vale gerar os dois arquivos de um único YAML (limites, enum de `grade`, `source`, códigos de erro) — pequeno investimento que fecha uma classe inteira de bug de contrato.

### 5.6 [P2] Pedir cards a mais em vez de aceitar entregar menos

§7.5 decide, corretamente, derrubar cards que estouram o limite em vez de truncar, e não fazer retry (não gastar cota que o usuário não pediu). Mas há uma terceira opção mais barata que ambas: **pedir `ceil(n * 1.2)` cards ao modelo** e cortar os excedentes depois do `constrain`. O custo marginal são tokens de saída de alguns cards, muito abaixo de uma segunda chamada, e a fila de aprovação passa a raramente ficar curta.

### 5.7 [P2] Estimar custo antes de cobrar cota

O endpoint `count_tokens` permite calcular o custo real de um PDF ou de um lote de fotos **antes** da chamada ao modelo. Isso viabiliza:

- mostrar "esta captura vai consumir ~3 créditos" antes de confirmar (§5.6 tem a tela intermediária certa para isso);
- rejeitar cedo o que é caro demais, sem gastar;
- tornar obrigatório o recorte de páginas acima de N páginas, em vez de oferecê-lo.

Nunca estimar tokens com `tiktoken` ou heurística de caracteres — é o tokenizador errado e erra feio em português e em imagem.

### 5.8 [P2] Limitações completas de structured outputs

§7.5 acerta ao dizer que `maxLength` não é suportado. A lista completa do que **não** é suportado, para não haver outra surpresa: `minLength`, restrições numéricas (`minimum`, `maximum`, `multipleOf`), restrições complexas de array, schemas recursivos, e `additionalProperties` com qualquer valor que não seja `false`.

Dois detalhes operacionais que valem uma linha:

- **Primeira requisição com um schema novo paga latência de compilação**; depois disso há cache de 24h. Schema estável = latência estável.
- Os SDKs Python e TypeScript **removem** as keywords não suportadas antes de enviar e validam no cliente. Isso é útil de saber para não achar que "funcionou" quando na verdade o SDK silenciosamente tirou a restrição — o estágio `constrain` do servidor continua sendo obrigatório.

### 5.9 [P2] Polling vs. duração real do job

§7.2 escolhe polling a cada ~1,5s sobre SSE, argumentando que jobs duram segundos. O argumento é bom para tópico e texto colado. Para um PDF de 200 páginas ou 5 fotos com `effort` alto, o job pode passar de um minuto — e aí 40 requisições de polling por job, por usuário, começam a ser um custo real de infraestrutura.

Sugestão barata: backoff no polling (1s nos primeiros 10s, depois 3s, depois 5s) em vez de intervalo fixo. Mantém a decisão de não usar SSE, que continua correta.

---

## 6. Métricas (§8)

### 6.1 [P1] A definição de "memória acumulada" está imprecisa

§8 define a estabilidade do FSRS como *"days until retrievability decays to the retention target"*. Não é. **Estabilidade é o número de dias até a retrievabilidade cair para 90%** — por definição do algoritmo, independente da meta configurada. O intervalo é que deriva da meta: `I = S · f(R_desejado)`.

Na v1 isso não muda nada, porque §13 fixa a meta em 90% e os dois números coincidem. Mas se a meta virar configurável (§5.12 pede), a métrica de destaque do produto muda de definição em silêncio: baixar a meta para 85% aumentaria os intervalos sem mexer em `SUM(stability)`, e subir para 95% faria o oposto. Escrever a definição correta agora evita descobrir isso quando o número na tela do usuário se comportar de forma inexplicável.

### 6.2 [P1] Streak se reescreve quando a meta diária muda

§8 diz que o streak conta *"days the goal was met"* e que os perdões são derivados, não armazenados. Derivar é a decisão certa — mas derivado **de qual meta**?

Se a comparação usa a meta atual, baixar a meta de 50 para 10 cards faz o histórico inteiro virar "meta batida" e o streak salta retroativamente. Subir a meta apaga o streak.

**Correção:** gravar a meta vigente por dia. Uma tabela mínima `day_summary(local_date, goal_at_the_time, reviews_count)` preenchida no fim do dia (ou derivada de um log de mudanças de setting) resolve, e de quebra torna o heatmap e o streak baratos de renderizar sem varrer o log inteiro. Isso não fere o §3 — continua derivado, só que materializado com a entrada correta.

### 6.3 [P2] "Precisão" mede acerto, não calibração

§8 define precisão como *"share of reviews graded above errei, against the configured retention target"*. Isso é taxa de acerto, e é uma métrica legítima e legível. Mas a métrica nativa do FSRS é a **calibração**: comparar a retrievabilidade prevista no momento da revisão com o resultado real. É ela que responde "o algoritmo está acertando as previsões para você?" e que justifica ajustar parâmetros.

Sugestão: manter a taxa de acerto como número visível (é o que o usuário entende) e calcular calibração internamente — é o sinal que diz quando otimizar os pesos passa a valer a pena.

### 6.4 [P2] Múltipla escolha precisa de regra de inferência de nota documentada

§5.9 da spec funcional diz que múltipla escolha conta para o FSRS *"com o grau inferido do acerto e do tempo"*. Isso é uma decisão de agendamento, não de UI, e pertence à arquitetura.

Múltipla escolha com 4 alternativas tem ~25% de acerto por chute. Mapear "acertou" para *bom* ou *fácil* infla a estabilidade com sinal ruidoso e degrada o cronograma do usuário ao longo de meses. Mapeamento conservador sugerido:

| Resultado | Nota |
|---|---|
| errou | errei |
| acertou lento | difícil |
| acertou rápido | bom |
| — | *fácil* nunca é inferido |

### 6.5 [P2] Fuso e virada do dia

§5.6 acerta ao dizer que os limites de dia são calculados no fuso do usuário. Faltam duas definições:

- **Qual fuso?** O do dispositivo no momento da query (muda quando a pessoa viaja e reescreve o heatmap) ou um `timezone` IANA armazenado e sincronizado? Recomendo o segundo, editável em Ajustes.
- **Hora de virada.** Apps sérios de SRS usam corte às 4h da manhã, não à meia-noite. Sem isso, estudar à 1h da manhã conta como o dia seguinte, quebra o streak de quem estuda tarde e é uma reclamação garantida. `day_cutoff_hour` default 4, no bloco sincronizado do item 2.1.

Uma única função de bucketização de dia, compartilhada, usada por heatmap, streak, meta diária e "enterrado até amanhã". Cuidado com `AT TIME ZONE` no Postgres em torno de horário de verão.

---

## 7. Subsistemas ausentes

Cada um destes está na spec funcional e não aparece na arquitetura. Os dois primeiros têm consequência de schema.

### 7.1 [P1] Busca e filtro (§5.10)

*"Lista de cards com busca e filtro por tag e por estado"* precisa de índice de texto. SQLite FTS5 resolve, com um detalhe que importa muito em português:

```sql
CREATE VIRTUAL TABLE cards_fts USING fts5(
  front, back, content='cards', content_rowid='rowid',
  tokenize="unicode61 remove_diacritics 2"
);
```

`remove_diacritics 2` é o que faz "funcao" encontrar "função". Sem isso, a busca parece quebrada. É uma tabela do `drift` que precisa existir no sub-projeto 1, com triggers de sincronização com `cards`.

### 7.2 [P1] Notificações (§2.4, §5.12)

*"Notificação só para fila vencida, com horário escolhido, desligável"*. A consequência arquitetural é boa e vale escrever explicitamente: como a fila é calculada localmente, isso é **notificação local agendada no dispositivo** — sem push tokens, sem infraestrutura de push, sem enviar dado de estudo ao servidor para decidir quando notificar. Um subsistema inteiro que o offline-first elimina.

Detalhe de implementação: reagendar a notificação ao fim de cada sessão e na virada do dia, e cancelá-la quando a fila zera.

### 7.3 [P2] TTS (§5.9)

Modo áudio: TTS on-device (`flutter_tts`) — funciona offline, custo zero, sem enviar conteúdo ao servidor. Registrar como decisão, junto com o fato (já bem tratado no §5.2) de que a sessão de áudio não grava linha em `reviews`.

### 7.4 [P2] Export de dados (§5.12)

Coberto no item 4.6.

---

## 8. Decomposição (§12)

Duas observações sobre a ordem.

**O menor produto reconhecível é 1 + 3 + 2, não 1 + 2.** §12 afirma que Foundation + Study loop *"together are the smallest thing that is recognisably the product"* — mas sem Authoring não existe um card para estudar. A fatia vertical mínima precisa de criação manual.

**Falta um sub-projeto 0.** Um walking skeleton antes de tudo: repo, CI, migração inicial do `drift`, contrato OpenAPI gerando o cliente Dart, e um caminho ponta a ponta (criar card → estudar → push → pull em outro device) mesmo que trivial. Em projeto offline-first, descobrir problemas de contrato e de migração no sub-projeto 4 é caro; descobri-los no dia 3 é barato.

Sobre o cliente gerado (§4): definir `operation_id` explícito em cada rota do FastAPI, senão os nomes de método no Dart saem ilegíveis. E versionar o cliente gerado no repo, com teste de contrato que falha quando o schema muda.

---

## 9. Cliente Flutter (§4)

Pontos não decididos que vão aparecer na primeira semana:

- **Gerência de estado** não está escolhida. Riverpod combina bem com streams do `drift` e com a direção de dependência declarada.
- **Replay pesado fora da UI isolate.** Rebuild completo de milhares de cards trava a interface. `drift` oferece `NativeDatabase.createInBackground`; usar desde o começo.
- **WAL mode** no SQLite, e decisão explícita sobre criptografia em repouso (SQLCipher). Provavelmente desnecessária, mas é uma pergunta de revisão de loja que vale ter respondida.
- **`preview` não pode chamar o banco.** Já está garantido pelo desenho do pacote puro, mas vale um teste que falhe se alguém adicionar I/O ao `scheduler`.

---

## 10. Testes (§10)

O §10 está bem direcionado. Três adições:

1. **Vetores de referência do FSRS.** Comparar a saída do wrapper contra a implementação de referência (`py-fsrs`) em um conjunto fixo de históricos. Isso pega regressão de porta e mudança de versão do algoritmo — que os property tests internos não pegam, porque um scheduler consistentemente errado passa em todos eles.
2. **Teste model-based de sync.** Simular interleavings aleatórios de operações em dois dispositivos e afirmar convergência. Os três cenários do §10.2 são bons, mas escritos à mão; a classe de bug de sync que dói é a que ninguém pensou em escrever.
3. **Testes de migração a partir de cada versão anterior** do schema `drift` (item 4.8).

---

## 11. Sobre o §11 (mudanças no design)

A lista está correta e bem fundamentada. Quatro acréscimos:

- **`06 Fila de aprovação` — "aprovar todos os restantes" tem tensão com o §2.2.** A spec funcional exige aprovação humana de tudo que a IA gera; um botão que aprova 17 cards não lidos é carimbo, não aprovação. Não é motivo para remover (§5.7 pede explicitamente), mas merece confirmação e talvez um limite (por exemplo, disponível só depois de N cards revisados individualmente).
- **Indicador de cota no ponto de criação.** §5.13 exige cota visível na tela de geração; o botão flutuante ausente do nav (já apontado no §11) é onde ela precisa aparecer, junto com o estado offline (geração indisponível).
- **`10 Configurações`** — além do que o §11 lista, faltam: fuso horário, hora de virada do dia (item 6.5), exportar dados, e o escape hatch de sync (item 4.7).
- **Estado de restauração.** Reinstalar o app com dois anos de histórico não é instantâneo (item 1.1) — precisa de tela.

---

## 12. Prioridades

Se for para corrigir em ordem:

| # | Item | Onde | Por que primeiro |
|---|---|---|---|
| 1 | Revisões e `progress_resets` sincronizam nos dois sentidos (união) | 1.1 | Sem isso, multi-dispositivo e reinstalação perdem o produto |
| 2 | Cursor de pull por `server_seq`, não por `updated_at` | 1.2 | Perda silenciosa de dados, impossível de detectar depois |
| 3 | Meta de retenção e parâmetros do FSRS no bloco sincronizado | 2.1, 2.2 | Sem isso, "replay determinístico" é falso |
| 4 | Fuzz do FSRS desligado ou semeado | 2.3 | Quebra o property test e diverge entre dispositivos |
| 5 | `level` fora do prefixo de cache | 5.1 | Contradição interna; o cache nunca é lido como está |
| 6 | Retenção de tombstone + `410 resync_required` | 1.3 | Barato agora, migração dolorosa depois |
| 7 | Tratar `stop_reason: "refusal"` + `fallbacks` | 5.4 | Classe de erro inteira ausente do §9 |
| 8 | Contagem por grapheme cluster + NFC, constantes geradas | 5.5 | A garantia do §7.5 não se sustenta sem isso |
| 9 | Aritmética de cota em um comando + expiração de reserva | 4.2 | Cobrança errada é o pior tipo de bug |
| 10 | Fila no Postgres com `SKIP LOCKED` (ou reaper documentado) | 4.1 | Torna cota + enqueue atômicos |

O resto pode entrar conforme os sub-projetos avançam. Os itens de billing por loja (4.5) e LGPD (4.6) não bloqueiam o sub-projeto 1, mas precisam estar resolvidos antes do 8 e antes da submissão à loja, respectivamente.
