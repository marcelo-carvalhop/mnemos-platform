# Contrato App/Web <-> Firmware v0.5

O app e a web não devem reproduzir a lógica interna do terminal. Devem produzir/consumir os contratos públicos em `spec/schemas` e respeitar as capabilities retornadas por `/v4/info`.

A criação de conteúdo pertence ao app/web. O estudo pertence ao terminal. Para sincronização de conteúdo, app/backend enviam um snapshot `mnemos.sync/v2`. Para um card já existente, o firmware preserva o `CardState` local pelo `cardId`; atualização de conteúdo não deve zerar o histórico de aprendizagem. Remover um card remove o conteúdo na próxima reconciliação, mas reviews já produzidos continuam na outbox/histórico até ACK.

O app deve suportar `open_recall`, `cloze`, `multiple_choice`, `true_false` e `application`. Para `multiple_choice`, deve enviar de 2 a 4 opções no CYD e `evaluation.correctOptionIndex`. Para `true_false`, deve enviar `correctOptionIndex` 0=Verdadeiro ou 1=Falso. Para tipos autoavaliados, deve fornecer `content.answer.text`.

A tela de Sincronização do app deve representar estado desejado (`No Mnemos` / `Somente no app`) e não expor upload/download como decisão de usuário. A tela de Conexão não envia decks. Provisionamento e DirectSync usam o mesmo SoftAP, porém rotas distintas por modo.

Para DirectSync, o app escaneia o QR, conecta temporariamente ao SSID `MNEMOS-XXXXXX`, acessa `http://192.168.4.1`, passa `token` como query parameter e executa: GET `/v4/info`; POST `/v4/time`; POST `/v4/sync/library`; GET `/v4/sync/reviews`; POST `/v4/sync/reviews/ack`; GET `/v4/metrics`; POST `/v4/complete`. O app deve permanecer funcional sem backend e nunca apagar reviews locais antes de confirmar que os persistiu.

O dashboard é app/web. O terminal não precisa renderizar gráficos. O cliente deve aceitar `mnemos.metrics/v1` e, quando possível, também recomputar os mesmos indicadores a partir de `mnemos.review/v2` para testes de consistência.

## Agenda e autoridade de agendamento

Na preview.2 o terminal passa a tornar `dueAt` visível localmente. Isso não muda a autoridade do contrato: app/web não devem enviar datas de revisão arbitrárias dentro do snapshot de conteúdo. `mnemos.sync/v2` continua transportando biblioteca; o `CardState` existente é preservado no firmware pelo `cardId`. O próximo horário mostrado na Home/Agenda é derivado do menor `dueAt` futuro mantido pelo terminal.

Para dashboards externos, a aplicação pode exibir projeções de carga a partir de `mnemos.metrics/v1`. Se o app/web mantiver uma cópia de estado para uso offline, deve tratar timestamps de agendamento recebidos/sincronizados como estado do motor e nunca recalculá-los apenas a partir do texto do card. Mudanças de meta de retenção afetam cálculos futuros; não devem reescrever retroativamente `dueAt` já persistido sem um evento de revisão ou operação de agendamento explicitamente definida pelo protocolo.
