# Migração Mnemos v0.2 → v0.3

A v0.3 substitui o formato privado de transferência por uma família pública de JSON Schemas. O app produz `mnemos.sync/v1`; o firmware recebe em `/v2/library`. Rotas v1 permanecem temporariamente para bancada, mas novas integrações devem implementar apenas v2.

O pareamento deixa de significar "telefone conectado ao terminal" durante toda a operação. O SoftAP passa a ser um canal de provisionamento. O app entrega Wi-Fi de infraestrutura; o terminal mantém AP+STA durante a transição; ao final encerra o AP e permanece STA. A tela inicial passa a oferecer `DESLIGAR WI-FI`/`LIGAR WI-FI`, preservando credenciais.

O backend adiciona `terminal_credentials` pela migration `0010_terminal_credentials`. Execute a migration antes dos endpoints de terminal. Registro/reprovisionamento rotaciona segredo e armazena o conjunto de decks autorizado. Foram adicionados listagem e revogação de terminais.

O banco local do app não é reformatado para copiar JSON. A conversão fica em `TerminalSyncService`, preservando compatibilidade com dados existentes. `createdAt` de card ainda usa `updatedAt` como valor de compatibilidade na exportação atual.

O terminal CYD v0.3 negocia capacidades e aceita somente `basic/plain`, máximo 48 cards. Snapshots vindos do backend são aplicados atomicamente; excesso de capacidade gera conflito em vez de truncamento. Backend updates de conteúdo chegam ao terminal no boot online, após provisionamento, ao reativar Wi-Fi e na sincronização periódica.

Os dados demonstrativos foram consolidados em um único deck `Redes de Computadores` com 10 cards. O fixture público está em `docs/v0.3/examples/redes-10-cards.sync.json`.

A toolchain Android do pacote permanece na combinação JDK 21, Gradle 8.14.5, AGP 8.11.1 e Kotlin Gradle Plugin 2.2.20 para esta versão. Uma migração futura para Gradle/AGP 9 deve ser tratada separadamente porque altera a DSL Android e a integração Kotlin.
