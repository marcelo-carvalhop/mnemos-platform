# Mnemos — Requisitos Atômicos v0.5

Este documento refina `Mnemos_Requisitos_Tecnicos_Fonte_2026-08.md`. Cada linha descreve uma única obrigação observável ou verificável. A implementação pode agrupar tarefas internamente, mas um requisito só é considerado atendido quando seu critério de aceite é demonstrado.

| ID | Requisito atômico | Critério de aceite |
|---|---|---|
| HM-001 | A Home do terminal deve exibir apenas o estado resumido de estudo, uma ação primária contextual e acesso ao Menu. | Inspeção visual: no máximo dois botões interativos na Home. |
| HM-002 | A ação primária deve ser CONTINUAR quando existir sessão interrompida. | Com session.json válido, reiniciar e verificar CONTINUAR. |
| HM-003 | A ação primária deve ser ESTUDAR quando houver ao menos uma revisão devida. | Com dueCount>0, Home mostra ESTUDAR. |
| HM-004 | A ação primária deve ser PRATICAR quando não houver revisão devida e houver cards. | Com dueCount=0 e cardCount>0, Home mostra PRATICAR. |
| HM-005 | Sincronização e Conexão devem ser telas separadas. | Nenhuma ação de rede configurável aparece na tela Sincronizar e nenhum seletor de conteúdo aparece em Conexão. |
| HM-006 | Cada etapa de avaliação deve exibir somente controles necessários àquela decisão. | Pergunta, confiança, resultado e esforço são telas/estados distintos. |
| CARD-001 | Todo card aceito pelo CYD deve declarar schema mnemos.card/v2. | Snapshot com schema diferente é rejeitado. |
| CARD-002 | Todo card deve possuir id estável e não vazio. | Card sem id é rejeitado. |
| CARD-003 | Todo card deve possuir deckId correspondente a deck presente no snapshot. | deckId inexistente é rejeitado. |
| CARD-004 | CYD deve suportar open_recall. | Capability e execução funcional. |
| CARD-005 | CYD deve suportar cloze. | Capability e execução funcional. |
| CARD-006 | CYD deve suportar application. | Capability e execução funcional. |
| CARD-007 | CYD deve suportar multiple_choice com 2 a 4 opções. | Fora desse intervalo é rejeitado. |
| CARD-008 | multiple_choice deve declarar correctOptionIndex dentro do intervalo das opções. | Índice inválido é rejeitado. |
| CARD-009 | CYD deve suportar true_false com duas alternativas fixas. | Firmware materializa Verdadeiro/Falso. |
| CARD-010 | true_false deve possuir resposta correta determinística. | Índice correto 0 ou 1. |
| CARD-011 | Mudança editorial deve preservar cardId e incrementar revision. | Contrato app/web documentado; teste de snapshot preserva estado por id. |
| EVAL-001 | Confiança deve ser capturada antes de qualquer feedback sobre correção. | Nenhuma tela de resultado é alcançável sem Confidence. |
| EVAL-002 | Confiança deve ser persistida em escala numérica compatível com limiar 70. | ReviewEvent registra 25/60/90 no CYD. |
| EVAL-003 | Resposta aberta deve ser autoavaliada como correta ou incorreta. | Tela oferece ERREI/ACERTEI após referência. |
| EVAL-004 | Se resposta autoavaliada for correta, esforço deve ser coletado separadamente. | DIFÍCIL/NORMAL/FÁCIL somente após ACERTEI. |
| EVAL-005 | Se resposta autoavaliada for incorreta, esforço não deve ser solicitado. | ERREI gera Effort=None. |
| EVAL-006 | multiple_choice deve registrar automaticamente acerto/erro. | Comparação selectedOptionIndex vs correctOptionIndex. |
| EVAL-007 | true_false deve registrar automaticamente acerto/erro. | Mesma comparação objetiva. |
| EVAL-008 | Acerto+dificil deve mapear internamente para Rating::Hard. | Teste LearningModel.ratingFor. |
| EVAL-009 | Acerto+normal deve mapear internamente para Rating::Good. | Teste LearningModel.ratingFor. |
| EVAL-010 | Acerto+facil deve mapear internamente para Rating::Easy. | Teste LearningModel.ratingFor. |
| EVAL-011 | Qualquer erro deve mapear internamente para Rating::Again. | Teste LearningModel.ratingFor. |
| EVAL-012 | Latência deve ser medida da apresentação até a resposta estar pronta/alternativa ser escolhida. | ReviewEvent.responseTimeMs >0 em interação real. |
| SESS-001 | ReviewSession deve conter somente cards devidos e novos admitidos pela política de carga. | Fila validada por isDue/new quota. |
| SESS-002 | PracticeSession deve poder iniciar imediatamente quando dueCount=0. | Finalizar sessão e iniciar PRATICAR sem esperar dueAt. |
| SESS-003 | PracticeSession deve registrar ReviewEvent. | Histórico cresce após prática. |
| SESS-004 | PracticeSession deve definir affectsSchedule=false. | Evento persistido com false. |
| SESS-005 | PracticeSession não deve alterar D, S ou dueAt. | Snapshot de estado antes/depois idêntico. |
| SESS-006 | ReviewSession deve definir affectsSchedule=true. | Evento persistido com true. |
| SESS-007 | Fila deve evitar mais de K cards consecutivos do mesmo deck quando houver alternativa. | K padrão 2. |
| SESS-008 | Cards marcados illusionOfMastery devem receber prioridade sobre equivalentes. | Ordenação de candidatos. |
| SESS-009 | Introdução de novos cards deve diminuir quando carga prevista de 7 dias aumenta. | allowedNewCards retorna 1 no limiar. |
| SESS-010 | Sessão interrompida deve ser restaurada por cardId, não índice. | Reordenar biblioteca e restaurar. |
| SESS-011 | Card removido deve ser descartado silenciosamente de sessão restaurada. | Sessão restante continua sem referência inválida. |
| DSR-001 | Recuperabilidade deve usar R=1/(1+t/(9S)). | S=10,t=10 produz aproximadamente 0,9. |
| DSR-002 | Card novo deve ser considerado devido. | repetitions=0 -> isDue true. |
| DSR-003 | D deve permanecer no intervalo [1,10]. | Aplicar sequência extrema e verificar clamp. |
| DSR-004 | S deve permanecer positiva e limitada. | Aplicar sequência extrema e verificar clamp. |
| DSR-005 | Erro deve incrementar lapses. | Review Again incrementa lapses. |
| DSR-006 | Acerto deve incrementar repetitions. | Review correto incrementa repetitions. |
| DSR-007 | Intervalo deve ser derivado de S e retentionTarget em produção. | DEMO_INTERVALS=false e fórmula inversa. |
| DSR-008 | Meta de retenção deve permanecer configurável entre 0,80 e 0,95. | LearningModel aplica clamp. |
| DSR-009 | Modo cram deve usar ganho reduzido quando ativado futuramente. | CRAM_GAIN_FACTOR aplicado no LearningModel. |
| DATA-001 | Definições de card devem persistir separadamente do estado de aprendizagem. | library.json não é fonte de D/S. |
| DATA-002 | Estado de aprendizagem deve persistir em state.json. | Reboot preserva D/S/dueAt. |
| DATA-003 | Histórico bruto deve ser append-only no fluxo normal. | ACK não remove review_history.ndjson. |
| DATA-004 | Outbox deve conter eventos ainda não confirmados. | Novo review aparece em review_outbox.ndjson. |
| DATA-005 | ACK deve limpar somente outbox. | Histórico permanece após clearReviewOutbox. |
| DATA-006 | Todo ReviewEvent v2 deve conter cardId, deckId, timestamp, confiança, outcome e sessionMode. | Schema e serialização. |
| DATA-007 | Snapshot de conteúdo deve ser validado integralmente antes de substituir biblioteca ativa. | Card inválido mantém biblioteca anterior. |
| DATA-008 | Atualização de conteúdo deve preservar CardState local de ids existentes. | SyncCodec reaproveita state por id. |
| MET-001 | Retenção 30d deve usar somente revisões programadas. | Practice não altera numerador/denominador. |
| MET-002 | Sobreconfiança deve contar erro com confiança >=70. | Evento High+Incorrect incrementa índice. |
| MET-003 | Consistência deve fornecer contagem diária de 30 dias. | Array consistency30d tamanho 30. |
| MET-004 | Maturidade deve distinguir new, learning, young e mature. | Buckets por repetitions/S. |
| MET-005 | Carga futura deve fornecer 30 dias de vencimentos. | reviewForecast30d tamanho 30. |
| MET-006 | Retenção deve ser segmentável por deck. | retentionByDeck contém deckId. |
| MET-007 | Dificuldade deve ser fornecida em 10 bins. | difficultyHistogram tamanho 10. |
| MET-008 | Tempo médio de resposta deve ser calculável em 30 dias. | responseTime30d contém samples e meanMs. |
| MET-009 | Métricas devem ser recomputáveis do histórico bruto e estado atual. | Apagar cache não muda resultado. |
| MET-010 | Dashboard visual pertence ao app/web, não à Home do terminal. | Firmware expõe JSON e não gráficos. |
| NET-001 | Firmware v0.5 não deve depender de BLE. | Nenhum include/objeto BLE no firmware/cyd. |
| NET-002 | Provisionamento deve usar SoftAP dedicado em 2,4 GHz. | SSID MNEMOS-* e host 192.168.4.1. |
| NET-003 | DirectSync deve usar SoftAP dedicado quando solicitado. | mode=sync no QR. |
| NET-004 | Provisionamento e DirectSync devem possuir autorização funcional separada. | /v4/provision rejeitado em sync; /v4/sync/* rejeitado em provision. |
| NET-005 | Wi-Fi desligado pelo usuário não deve apagar perfis conhecidos. | disable persiste profiles. |
| NET-006 | Ao religar Wi-Fi, firmware deve procurar rede conhecida automaticamente. | enable chama reconnect. |
| NET-007 | Rede atual funcional não deve ser abandonada apenas por aparecer outra conhecida. | loop não escaneia enquanto connected. |
| NET-008 | Perfis devem suportar open e personal. | NetworkProfile valida ambos. |
| NET-009 | Enterprise password deve ser capability condicional ao core. | info reflete CONFIG_ESP_WIFI_ENTERPRISE_SUPPORT. |
| SYNC-001 | DirectSync deve aceitar mnemos.sync/v2. | POST /v4/sync/library. |
| SYNC-002 | DirectSync deve exportar mnemos.review-batch/v2. | GET /v4/sync/reviews. |
| SYNC-003 | DirectSync deve permitir ACK explícito de reviews. | POST /v4/sync/reviews/ack. |
| SYNC-004 | DirectSync deve expor métricas. | GET /v4/metrics. |
| SYNC-005 | Encerramento deve desligar SoftAP e restaurar política STA. | POST /v4/complete. |
| SYNC-006 | Backend e DirectSync devem usar o mesmo SyncCodec. | Análise de dependência. |
| EXT-001 | App/web devem consultar /v4/info antes de enviar conteúdo. | Cliente verifica protocol/capabilities. |
| EXT-002 | App deve respeitar maxCards e maxOptions. | UI impede snapshot incompatível antes do envio. |
| EXT-003 | App deve separar Conexão de Sincronização. | Fluxos não compartilham tela de conteúdo. |
| EXT-004 | App deve representar presença desejada por deck, não direção upload/download. | HMI usa No Mnemos/Somente no app. |
| EXT-005 | App/web devem renderizar dashboard fora da Home. | Superfície Estatísticas dedicada. |
| EXT-006 | App/backend não devem zerar CardState ao editar conteúdo com mesmo cardId. | Teste de reconciliação. |
| QA-001 | Firmware CYD deve compilar com PlatformIO esp32dev. | pio run termina SUCCESS. |
| QA-002 | Uso de flash deve ser registrado em cada release. | QA inclui bytes e percentual. |
| QA-003 | Ausência de símbolos BLE deve ser verificada por busca estática. | grep em include/src retorna zero. |
| QA-004 | Schemas públicos devem validar como JSON Schema Draft 2020-12. | Validador local sem erros. |
| QA-005 | Fixture Redes deve conter exatamente 1 deck e 10 cards. | Script de validação. |
| QA-006 | Sessão prática deve ser testada imediatamente após sessão normal completa. | Teste físico obrigatório. |
| QA-007 | DirectSync deve ser testado sem roteador disponível. | Celular conecta ao MNEMOS-* e sincroniza. |

Total: **95 requisitos atômicos**.

Os requisitos metodológicos originais continuam sendo a fonte de intenção. Este documento não altera a metodologia; decompõe-a para engenharia, teste e rastreabilidade.

## SCHED — Transparência do agendamento

| ID | Obrigação atômica | Critério de aceite |
|---|---|---|
| SCHED-001 | `dueAt` deve ser a fonte de verdade para determinar se um card já agendado está vencido. | Card com `dueAt > now` não entra em dueCount mesmo após primeira falha. |
| SCHED-002 | Card nunca agendado deve ser considerado disponível para introdução, mas não deve ser contado como revisão vencida na Agenda. | `dueAt=0` aparece como novo na Home e entra na fila sujeito à cota, sem incrementar `dueNow`. |
| SCHED-003 | A Home sem revisões pendentes deve informar a próxima revisão. | `dueNow=0` e `nextReviewAt>0` mostram rótulo humanizado sem novo botão. |
| SCHED-004 | A Home com revisões pendentes deve priorizar a quantidade devida. | `dueNow>0` mantém `N revisões` como mensagem principal. |
| SCHED-005 | O Menu deve fornecer uma Agenda informativa. | Agenda abre e fecha sem alterar CardState. |
| SCHED-006 | Agenda deve informar vencidas agora. | Valor corresponde ao mesmo cálculo usado pela Home. |
| SCHED-007 | Agenda deve informar revisões futuras ainda hoje. | Apenas `now < dueAt < início de amanhã` é contado. |
| SCHED-008 | Agenda deve informar revisões de amanhã. | Apenas dueAt dentro do próximo dia local é contado. |
| SCHED-009 | Agenda deve informar carga dos próximos sete dias. | Contagem é derivada exclusivamente dos dueAt persistidos. |
| SCHED-010 | Após uma revisão que afeta o scheduler, o terminal deve informar o novo dueAt. | Feedback aparece antes do próximo card/resumo. |
| SCHED-011 | Nenhuma sessão deve interromper o fluxo após cada card para expor o `dueAt` individual. | Após commit, a HMI avança diretamente para o próximo card ou resumo; somente a próxima revisão agregada é mostrada fora do fluxo do card. |
| SCHED-012 | A conclusão de uma sessão sem pendências deve informar a próxima revisão global. | Menor dueAt futuro é exibido. |
| SCHED-013 | Datas devem ser apresentadas em linguagem humana. | Segundos/minutos, hoje, amanhã, dia da semana ou DD/MM conforme distância. |
| SCHED-014 | Relógio não confiável deve ser sinalizado na apresentação de uma data futura. | Rótulo recebe indicação `aprox.` enquanto TimeService não estiver confiável. |
| SCHED-015 | Um primeiro erro deve respeitar o intervalo de reaprendizado. | Após Again inicial, card não vence novamente antes do dueAt calculado. |
| SCHED-016 | Card já tentado e errado não deve permanecer classificado como `new` nas métricas. | `lastReviewedAt>0` e S<1 dia entra em `learning`. |
