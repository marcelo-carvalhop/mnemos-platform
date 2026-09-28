# Sincronização e convergência

A plataforma sincroniza conteúdo mutável e histórico de aprendizagem por mecanismos distintos. No móvel, Drift/SQLite mantém outbox e cursores; a web mantém seu espelho em memória; o terminal mantém uma outbox local e cursores próprios. O servidor atribui `server_seq` por usuário para que os pulls não dependam do relógio de cada aparelho. Conteúdo pode usar exclusão lógica e resolução determinística; IDs de revisões permitem união idempotente do histórico. O estado calculado de agendamento é derivado, não uma tabela de verdade sincronizada.

## Clientes móvel e web

Os clientes completos usam `/v1/sync/push` e `/v1/sync/pull`. O servidor confirma IDs com uma sequência atribuída e devolve deltas por tabela. Revisões e marcadores de reinício são eventos; entidades editáveis carregam momento de atualização e tombstones. Configurações que entram no FSRS, como retenção desejada, acompanham o histórico para evitar agendas divergentes após reinstalação ou uso em outro acesso. A web reconstrói seu espelho após recarga; não mantém um banco durável offline.

## Terminal

O backend mantém `deck_ids` desejados e `reported_deck_ids` observados para cada credencial física. A seleção pode estar vazia; pareamento não deve instalar conteúdo implicitamente. A API de snapshot entrega `mnemos.sync/v2` e recusa uma biblioteca maior que o limite informado. O terminal valida o documento, preserva o estado por ID de cartão e só troca a biblioteca após persistência. A outbox de revisões é reenviável e só é limpa após confirmação. Um DirectSync pelo móvel usa Device Protocol v4 e também deve incorporar eventos antes do ACK.

A implementação de envio remoto na ramificação ainda não converge: o terminal remete `reviewedAt` em segundos e `source=terminal`, mas o servidor exige `reviewedAtMs` e `source` do contrato interno. O corpo recebe 422 e a outbox permanece. No caminho móvel, um evento ignorado por falta de cartão pode ser removido pelo ACK geral após a transferência. O backend também projeta cartões sincronizados como `open_recall`, independentemente do tipo, devido ao modelo de conteúdo atual. O diagnóstico, a proposta de adaptação e os critérios ponta a ponta estão em [../integration/t5-touch.md](../integration/t5-touch.md).

## Invariantes de falha

Uma interrupção de rede não apaga revisão não confirmada. Retry do mesmo ID não cria segundo evento. Revisão de cartão fora dos baralhos autorizados não é aceita. Cursor só avança depois de uma página de delta ter sido gravada com sucesso. Remover um baralho desejado não deve impedir a saída das revisões pendentes ainda produzidas quando ele estava no terminal. Esses invariantes exigem teste cruzado entre o produtor real, API, banco e demais clientes; teste isolado com fixture produzido à mão não basta.
