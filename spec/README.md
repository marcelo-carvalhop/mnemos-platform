# Contratos e protocolos Mnemos

`spec/` reúne schemas JSON e descrições de interfaces públicas. Cada documento usa seu próprio identificador de versão; `/v1` na URL da API, v4 no protocolo HTTP local e v2 em um objeto JSON não representam uma mesma release de produto. A implementação efetiva precisa ser verificada em ambos os lados de uma interface. [A matriz de integração](../docs/integration/t5-touch.md) registra divergências atualmente conhecidas.

| Interface | Arquivo de referência | Uso nesta ramificação |
| --- | --- | --- |
| Cartão e snapshot | [`schemas/card-v2.schema.json`](schemas/card-v2.schema.json), [`schemas/sync-v2.schema.json`](schemas/sync-v2.schema.json) | T5 Touch e produtores móvel/backend; apenas `open_recall` é projetado pelos produtores atuais. |
| Revisão e lote | [`schemas/review-v2.schema.json`](schemas/review-v2.schema.json), [`schemas/review-batch-v2.schema.json`](schemas/review-batch-v2.schema.json) | Saída local do T5 Touch; o validador da API diverge desse formato. |
| Métricas | [`schemas/metrics-v1.schema.json`](schemas/metrics-v1.schema.json) | Consulta local v4. |
| HTTP local | [`protocol/device-protocol-v4.md`](protocol/device-protocol-v4.md) | T5 Touch e app móvel, com negociação por QR e `/v4/info`. |
| Wi-Fi | [`schemas/provisioning/v2.json`](schemas/provisioning/v2.json), [`schemas/network-profile/v1.json`](schemas/network-profile/v1.json) e [`protocol/provisioning-v2.md`](protocol/provisioning-v2.md) | Perfil de rede e credencial restrita no provisionamento local v4. |
| API de conta/terminal | [`../docs/developers/backend-implementation.md`](../docs/developers/backend-implementation.md) e código em `backend/app/terminal/` | Rotas `/v1/*`; `protocol/backend-api-v1.md` descreve a família anterior e não é suficiente para o T5 Touch. |

Os arquivos `protocol/device-protocol-v2.md`, `device-protocol-v3.md`, `ble-sync-v1.md`, `backend-api-v1.md` e os documentos de Wi-Fi v1 servem como histórico e contratos de outros perfis. Sua presença não significa que o T5 Touch ofereça BLE ou rotas v2/v3. `shared/contract.yaml` é a origem do código gerado para as aplicações oficiais; não está substituído automaticamente pelos schemas públicos. Ao alterar uma interface, atualizar as duas fontes quando pertinente, produtor, receptor e fixture cruzado, e executar os validadores indicados em [`docs/developers/getting-started.md`](../docs/developers/getting-started.md).
