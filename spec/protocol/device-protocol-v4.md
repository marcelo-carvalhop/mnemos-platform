# Device Protocol v4 — T5 Touch

**Implementação de referência:** `firmware/t5-touch/src/local_link_service.cpp`, `app/mobile/lib/device/terminal_protocol.dart`. Este protocolo trata a sessão HTTP **local** entre telefone e terminal. A API remota em `/v1/terminal/*` usa outra credencial e outro endereço. Os schemas JSON de conteúdo são identificados por `mnemos.*` e evoluem separadamente da versão v4.

## Descoberta, endereço e autorização

O terminal exibe `mnemos://local?v=4&mode=...&transport=...` com `id`, `ssid`, `pwd`, `host`, `token`, `model` e `fw`. `transport=lan` usa o IP atual da infraestrutura, sem criar SoftAP; `transport=ap` anuncia SoftAP temporário com host obtido da interface AP. O cliente monta `http://<host>/v4/...?...` e inclui o token efêmero em **toda** requisição como `?token=<valor>`. Sem token válido, a resposta é 401. A sessão expira após 300 segundos ou ao ser concluída. O QR contém credenciais temporárias e precisa ser tratado como segredo de sessão.

O cliente deve ler `GET /v4/info` antes de transferir dados. A resposta contém `protocol=4`, identidade, versão, `localMode`, `cardCount`, `maxCards`, `pendingReviews`, estado de relógio/rede e `features`/`capabilities`. Na variante T5 Touch: `maxCards=128`, `cardTypes=[open_recall, cloze, multiple_choice, true_false, application]`, `contentFormats=[plain]`, `maxOptions=4`, `maxPayloadBytes=120000`, tela e-paper 960×540, toque primário, `typedRecall=false`, `bleSync=false` e `sdStorage=true`. O consumidor deve usar capacidades anunciadas, nunca apenas o nome do modelo. O catálogo suportar cinco tipos não implica que os produtores atuais de snapshot preservem os cinco tipos.

## Modos e operações

| Rota | Modo | Corpo ou resposta | Efeito e erros relevantes |
| --- | --- | --- | --- |
| `GET /v4/info` | Ambos | Identidade e capacidades | Consultar antes da transferência. |
| `POST /v4/time` | Ambos | `{ "epochSeconds": 1780000000 }` | Rejeita epoch anterior ao mínimo aceito com 422. |
| `GET /v4/network/status` | Ambos | `enabled`, `connected`, SSID, IP, perfis e `lastError` | Estado de conectividade, não confirmação de sync. |
| `POST /v4/provision` | `provision` | `mnemos.provision/v2` com `networkProfile`, intervalo e backend opcional | Persiste configuração de rede/terminal; modo errado recebe 409. |
| `POST /v4/sync/library` | `sync` | `mnemos.sync/v2` | Valida capacidade e cartões e troca a biblioteca; falha de parse/compatibilidade recebe 422. |
| `GET /v4/sync/reviews` | `sync` | `mnemos.review-batch/v2` | Lê eventos pendentes da outbox. |
| `POST /v4/sync/reviews/ack` | `sync` | Resposta `{ "ok": true }` | **Limpa toda a outbox**; o corpo atual não seleciona IDs. |
| `GET /v4/metrics` | `sync` | `mnemos.metrics/v1` | Métricas locais. |
| `POST /v4/complete` | Ambos | Resposta `{ "ok": true }` | Encerra a sessão temporária. |

O modo vem do QR e pode ser confirmado por `localMode`; o servidor retorna 409 para operação incompatível. `POST /v4/provision` não seleciona baralhos. `POST /v4/sync/library` não configura Wi-Fi. Um snapshot vazio é uma seleção vazia válida; os limites de payload e cartão precisam ser observados antes do envio. O aplicativo deve incorporar cada revisão de modo durável antes do ACK. **A implementação móvel atual pode ignorar eventos de cartões ausentes e ainda assim emitir ACK**; até a correção, não tratar o fluxo como livre de perdas. Consulte [a análise da integração](../../docs/integration/t5-touch.md#directsync-e-confirmação).

## Versões, integração e segurança

O formato de provisão v2 está descrito em [`provisioning-v2.md`](provisioning-v2.md). Os schemas v2 de cartão/snapshot e revisão/lote estão em [`../schemas/`](../schemas/). O envio remoto de revisões T5 Touch → backend ainda recebe 422 por divergência de campos e origem: o protocolo local v4 funcionar não prova que a API remota aceite o mesmo lote. Testar as duas fronteiras independentemente, com os bytes emitidos pelo firmware.

O HTTP local não fornece TLS; isolar a sessão com senha efêmera do SoftAP quando usado, token temporário e encerramento. O bearer de conta não trafega nesse canal. Em LAN compartilhada, o token em query string e o QR completo não devem ser registrados em logs ou telemetria. Uma integração externa não deve inferir segurança criptográfica do simples fato de o terminal aceitar um token local.
