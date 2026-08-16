# Mnemos v0.3.0 — Changelog

A v0.3.0 introduz a primeira camada pública de interoperabilidade do Mnemos. Foram adicionados JSON Schemas versionados para deck, card, estado, review, snapshot, lote de reviews e provisionamento. O app passa a exportar a biblioteca inicial no formato `mnemos.sync/v1`, enquanto o firmware CYD interpreta `mnemos.card/v1` e mantém suporte temporário às rotas legadas v1.

O fluxo de conexão foi remodelado. O QR Code inicia uma sessão de provisionamento em SoftAP. O aplicativo coleta a rede de infraestrutura, envia SSID e senha ao terminal, transfere a biblioteca e, quando existe backend alcançável, envia uma credencial exclusiva do terminal. O ESP32 mantém AP+STA durante a configuração, encerra o SoftAP no final e permanece como estação na rede configurada.

O terminal recebeu persistência de rede em NVS, reconexão controlada, sincronização direta periódica com backend e um botão na tela inicial para desligar ou ligar o Wi-Fi sem apagar credenciais. O firmware anuncia capacidades (`basic/plain`, 48 cards no CYD), valida snapshots integralmente antes de aplicá-los e preserva a biblioteca anterior quando o backend envia um documento incompatível. Reviews continuam funcionando offline e são apagados do log local somente após confirmação 2xx do backend ou do aplicativo.

O backend ganhou credenciais de terminal rotacionáveis, listagem e revogação por dispositivo, filtragem do snapshot pelos decks selecionados, endpoint de snapshot canônico e endpoint de ingestão de reviews. O token da conta do usuário não é transferido ao hardware. Snapshots que excedem a capacidade do terminal retornam conflito em vez de serem truncados silenciosamente, e reviews são autorizados também contra o conjunto de decks atribuído ao terminal.

Os dados demonstrativos foram reduzidos a um único baralho `Redes de Computadores` com 10 cards. Referências de demonstração a OAB, concursos e Revolução Gloriosa foram removidas da interface do aplicativo.

A configuração Android foi atualizada para versão 0.3.0 do aplicativo, Gradle 8.14.5, Android Gradle Plugin 8.11.1 e Kotlin 2.2.20, além das permissões Wi-Fi necessárias ao provisionamento moderno.
