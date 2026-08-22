# Referência profunda do firmware CYD v0.5

Este documento descreve a implementação `firmware/cyd` da v0.5.0-preview.3. Ele deve ser atualizado junto do código. A intenção é permitir reconstruir mentalmente o firmware sem depender apenas de leitura exploratória do C++.

## 1. Inicialização e objetos globais (`src/main.cpp`)

`Storage storage` monta LittleFS e é a única interface usada pelas demais camadas para biblioteca, estado, sessões e reviews. `NetworkService networkService` mantém perfis Wi-Fi e estado STA/AP. `TimeService clockService` fornece epoch confiável por NTP/celular ou fallback persistido. `LearningModel learningModel` contém as fórmulas D/S/R. `ScheduleService scheduleService` agrega `dueAt` diretamente dos estados sem alterar o scheduler. `CydDisplay display` encapsula TFT e touch. `cards[]` e `states[]` são arrays fixos com capacidade `MAX_DEVICE_CARDS`; o índice de um card e seu estado correspondente deve permanecer igual enquanto a biblioteca está carregada. `cardCount` indica quantas posições desses arrays são válidas. `StudyEngine* engine` é recriado quando a biblioteca muda. `MetricsService metrics` lê `storage`, `cards` e `states`. `LocalLinkService localLink` hospeda o Device Protocol v4 via SoftAP. `BackendSyncService backendSync` sincroniza pela infraestrutura. `screen` guarda o estado atual da HMI. `pendingOutcome` preserva o resultado automático entre a tela de feedback objetivo e a tela de esforço.

`rebuildEngine()` destrói e recria `StudyEngine`, depois chama `initializeStates()`. Deve ser chamado sempre que um snapshot substitui a biblioteca. `renderHome/Menu/Agenda/Sync/Connection/Question/Confidence/SelfAssessment/ObjectiveFeedback/Effort/Summary()` alteram `screen` e delegam desenho a `CydDisplay`; não modificam aprendizagem. `startStudyFromCurrentState()` aplica prioridade CONTINUAR > REVIEW > PRACTICE. `advanceAfterCommit()` segue diretamente para o próximo card ou para o resumo; o `dueAt` individual permanece interno ao motor. `startLocalLink(mode)` inicia SoftAP e desenha QR.

`setup()` inicializa serial, display, armazenamento, rede e relógio; carrega biblioteca persistida ou fixture de dez cards; tenta backend quando já há conectividade; constrói o engine e mostra Home. `loop()` atende HTTP local, reconexão Wi-Fi e sincronização backend apenas fora de uma sessão; depois lê uma única `UiAction` e avança a máquina de estados.

## 2. Domínio (`include/models.h`)

`CardDefinition.id` é a identidade estável do conhecimento. `deckId` identifica agrupamento lógico e `deck` guarda nome para HMI. `type` define comportamento; `format` é atualmente `plain`. `question` e `answer` são textos de referência. `options[4]`, `optionCount` e `correctOptionIndex` existem somente para tipos objetivos. `revision` é versão editorial. `isObjective()` retorna verdadeiro para `multiple_choice` e `true_false`; `isSelfAssessed()` é o complemento.

`CardState.id` deve ser igual ao card correspondente. `difficulty` é D em 1..10. `stabilityDays` é S em dias. `dueAt` é epoch da próxima revisão. `lastReviewedAt` é epoch do último evento que afetou scheduler. `repetitions` conta acertos agendados; `lapses` conta falhas. `lastRating` guarda Again/Hard/Good/Easy interno. `illusionOfMastery` indica evidência recente de alta confiança seguida de erro e influencia prioridade, não a fórmula D/S/R.

`Confidence` usa `Low=25`, `Medium=60`, `High=90`; a escolha numérica permite aplicar limiar metodológico 70. `Outcome` separa correto/incorreto. `Effort` só existe para resposta correta. `Rating` é entrada interna do scheduler. `SessionMode` diferencia Review, Practice e Cram.

`ReviewEvent` é o evento auditável. `affectsSchedule` é falso em prática. `automaticEvaluation` é verdadeiro em tipos objetivos. Campos Before/After permitem auditar o scheduler. `SessionStats` é resumo transitório da sessão; não é fonte das métricas históricas.

## 3. Modelo de aprendizagem (`learning_model.*`)

`retrievability(state, now)` calcula `R = 1/(1+t/(9S))`; estado sem revisão anterior retorna 0. `isDue()` usa `dueAt` como fonte de verdade: `dueAt=0` significa card ainda não agendado; caso contrário o card vence somente quando `dueAt<=now`. Isso impede que um primeiro erro, que já recebeu um intervalo curto de reaprendizado, seja tratado como imediatamente vencido. A meta de retenção é aplicada ao produzir o intervalo e não recalcula datas antigas retroativamente. `ratingFor()` converte as duas dimensões de HMI para Rating interno: erro->Again; correto+difficult->Hard; correto+normal->Good; correto+easy->Easy.

`initialDifficulty()` e `initialStability()` fornecem estados determinísticos somente quando `lastReviewedAt=0`/S ainda não existe; uma primeira falha já registrada deixa de ser confundida com card nunca estudado. `updatedDifficulty()` move D em pequenos passos e aplica clamp. `successfulStability()` implementa a estrutura de atualização de S após acerto usando `DSR_W1..W3`. `failedStability()` implementa a estrutura de falha com `DSR_W4..W7`. `intervalSeconds()` resolve a curva de retenção para a meta configurada; quando `DEMO_INTERVALS=true`, usa 30/120/300/600 s apenas para bancada. `apply()` é a única função que altera D/S/dueAt; Practice retorna sem mutação. Cram reduz o ganho por `CRAM_GAIN_FACTOR` e limita reconsolidação.

Os coeficientes em `config.h` são provisórios. Alterá-los muda comportamento pedagógico e deve gerar registro de versão e testes numéricos.

## 4. Sessões (`study_engine.*`)

`cards_`, `states_` e `count_` apontam para a biblioteca ativa. `storage_`, `clock_` e `model_` são dependências. `queue_[48]` contém índices dos cards; `sessionCount_` limita a parte válida; `currentPosition_` aponta o item atual. `mode_` controla se o evento afeta scheduler. `confidence_`, `outcome_`, `selectedOptionIndex_`, `questionShownAtMs_` e `responseTimeMs_` são estado transitório do card. `stats_` agrega a sessão e `resumableSession_` indica se `session.json` é válido. O agendamento individual fica persistido em `CardState::dueAt` e não exige estado transitório específico na HMI.

`initializeStates()` completa ids, carrega `state.json` e tenta restaurar `session.json`. `dueCount()` conta cards que `LearningModel::isDue()` considera devidos. `allowedNewCards()` observa a carga prevista de sete dias e reduz a cota de novos; um card é novo somente enquanto `lastReviewedAt=0`, portanto uma primeira falha não volta para a cota de introdução. `buildReviewQueue()` cria candidatos, prioriza `illusionOfMastery`, coloca revisões antes de novos e intercala decks. `appendCandidateWithInterleaving()` tenta não exceder dois cards consecutivos do mesmo deck quando existe alternativa.

`startReviewSession()` usa a fila metodológica. `startPracticeSession()` seleciona até `PRACTICE_CARD_LIMIT`, marca modo Practice e não depende de dueAt. `resumeSession()` volta ao primeiro card ainda não concluído. `resetCardInteraction()` limpa apenas estado transitório. `persistSession()` grava a parte ainda não concluída.

`selectOption()` valida alternativa e registra latência. `markResponseReady()` congela a primeira latência. `evaluateAutomatic()` compara opção selecionada com a correta sem ainda persistir. `commitCurrent()` cria ReviewEvent, calcula R antes da revisão, chama `LearningModel::apply()` apenas se `affectsSchedule`, atualiza `illusionOfMastery`, grava history+outbox+state e avança a sessão.

## 5. Agenda (`schedule_service.*`)

`ScheduleService` recebe `TimeService`, `states[]` e `cardCount` por referência; ele não depende de `LearningModel`. `snapshot()` percorre os estados sem mutá-los. `newCards` conta `dueAt=0`; `dueNow` conta apenas revisões já agendadas com `dueAt<=now`. Entre cards futuros, `laterToday`, `tomorrow` e `next7Days` são agregados por limites de dia local e `nextReviewAt` recebe o menor `dueAt`.

`humanize(epoch)` converte o epoch para `em 30 s`, `em N min`, `hoje as HH:MM`, `amanha as HH:MM`, nome do dia da semana ou `DD/MM as HH:MM`. `localDayStartUtc()` converte a fronteira de calendário local para epoch UTC usando o offset configurado. `localClock()` e `weekdayName()` são auxiliares de apresentação. Esse módulo não grava estado e não contém fórmula D/S/R.

## 6. Persistência (`storage.*`)

Arquivos: `/library.json` contém cards; `/state.json` contém CardState; `/session.json` contém fila incompleta; `/review_history.ndjson` é histórico durável; `/review_outbox.ndjson` é fila de sincronização; `/reviews.ndjson` é somente caminho legado migrado.

`begin()` monta LittleFS e executa migração do review legado. `loadLibrary()` desserializa cards e migra `basic` para `open_recall`. `saveLibrary()` escreve primeiro `/library.tmp` e renomeia, evitando arquivo parcialmente gravado. `loadStates()` lê D/S e também aproxima S pelo antigo `intervalSeconds` quando necessário. `saveStates()` usa a mesma estratégia temporária.

`saveSession()` persiste ids, posição, modo e resumo. `loadSession()` remapeia ids para índices atuais; cards removidos desaparecem com segurança. `clearSession()` apaga sessão e temporário.

`appendReviewToPath()` serializa um `mnemos.review/v2`; `appendReview()` grava o mesmo evento em history e outbox. `reviewOutboxNdjson()` e `reviewHistoryNdjson()` leem cada arquivo. `clearReviewOutbox()` nunca toca no histórico. `pendingReviewCount()` conta linhas da outbox. `resetAll()` apaga somente dados Mnemos em LittleFS.

## 7. Métricas (`metrics_service.*`)

`buildJson()` é recomputável. Ele percorre `review_history.ndjson`, ignora linhas que não sejam `mnemos.review/v2` para cálculos v0.5 e usa apenas `sessionMode=review && affectsSchedule=true` para retenção/calibração. Calcula retenção 30d, sobreconfiança, latência média, consistência 30d, retenção semanal, maturidade, forecast 30d, retenção por deck, histograma D e readinessIndex. Maturidade e forecast usam `states_`; segmentação por deck usa `cards_`.

## 8. Codec de sincronização (`sync_codec.*`)

`applySnapshotV2()` valida `mnemos.sync/v2`, capacidade e todos os cards antes de tocar na biblioteca ativa. `parseCard()` traduz `mnemos.card/v2` para `CardDefinition`. Somente `plain` e cinco tipos anunciados são aceitos. Para cards existentes, o CardState local é preservado pelo id. A biblioteca temporária é persistida antes de substituir arrays em RAM.

`buildReviewBatchV2()` lê a outbox e constrói `mnemos.review-batch/v2`. ACK é responsabilidade do transporte e chama `Storage::clearReviewOutbox()`.

## 9. Wi-Fi (`network_service.*`)

`profiles_[8]` contém redes conhecidas. `enabled_` é decisão persistente do usuário; `provisioning_` também é usado como trava durante qualquer SoftAP local. `backendUrl_`, `deviceToken_` e `syncIntervalSeconds_` configuram backend. `connectedSsid_` é estado atual. `reconnectBackoffMs_` impede loop agressivo.

`load()/save()` serializam perfis em Preferences. `validProfile()` valida open/personal/enterprise-password. `prepareProvisioning()` força AP-only; apesar do nome histórico, é usado também por DirectSync. `finishProvisioning()` desliga AP e retorna à política STA. `chooseVisibleProfile()` prefere prioridade e depois RSSI, com fallback para hidden. `connectProfile()` executa autenticação. `reconnect()` só opera se Wi-Fi estiver habilitado e não houver SoftAP local. `disable()` desliga rádio sem apagar perfis. `loop()` só tenta reconectar quando desconectado e após backoff.

## 10. Link local (`local_link_service.*`)

`mode_` é Provisioning ou DirectSync. `deviceId_`, `ssid_`, `password_` e `token_` são gerados a cada sessão. `start()` interrompe STA, cria AP em 192.168.4.1 canal 6 e monta QR. `authorized()` exige token. `requireMode()` impede vazamento de responsabilidade entre conexão e sincronização. `loop()` atende HTTP e expira em cinco minutos. `stop()` derruba AP e restaura rede conhecida.

Rotas v4: `/v4/info`, `/v4/time`, `/v4/network/status`, `/v4/provision`, `/v4/sync/library`, `/v4/sync/reviews`, `/v4/sync/reviews/ack`, `/v4/metrics`, `/v4/complete`. `sendInfo()` é a fonte de capabilities. `provision()` grava `NetworkProfile` sem iniciar STA antes do `complete`. `importLibrary()` usa SyncCodec. `exportReviews()` nunca apaga a outbox. `acknowledgeReviews()` é a única rota local que a limpa. `exportMetrics()` retorna o JSON determinístico.

## 11. Backend (`backend_sync_service.*`)

`loop()` executa somente com STA conectado e intervalo vencido. `request()` seleciona HTTP ou HTTPS e exige CA para HTTPS. `pushReviews()` envia batch v2 e limpa outbox somente após 2xx. `pullSnapshot()` solicita Sync v2 e delega aplicação ao SyncCodec. `reportStatus()` informa decks, capacidade, protocolo, pendências e capabilities. `syncNow()` ordena push de reviews, pull de snapshot e status.

## 12. Display (`cyd_display.*`)

`UiAction` é o único resultado lógico do touch. `Button buttons_[8]` contém regiões clicáveis da tela atual. `Calibration` persiste limites e troca de eixos. `drawHeader`, `drawButton`, `drawWrappedText` e `drawCentered` são primitivas gráficas.

As funções `show*` não alteram o domínio: `showHome` tem no máximo dois botões e mostra a próxima revisão quando não há pendências; `showMainMenu` separa Sync/Agenda/Conexão; `showAgenda` resume a carga sem permitir edição; `showSyncMenu` oferece rede ou celular; `showLocalLink` mostra QR; `showQuestion` mostra uma ação para autoavaliação ou até quatro alternativas objetivas; `showConfidence` tem três níveis; `showSelfAssessment` tem dois resultados; `showObjectiveFeedback` é informativa; `showEffort` tem três opções; `showSummary` mostra a próxima revisão quando a fila está limpa e oferece continuar/praticar ou concluir.

`pollAction()` faz hit-test em botões. `readMappedTouch()` aplica calibração e debounce. `calibrateTouch()` mede quatro cantos e persiste parâmetros.

## 13. Limitações e riscos conhecidos

O CYD não possui CardKB integrado; respostas abertas são formuladas fora do firmware e autoavaliadas. A outbox/histórico ainda são lidos integralmente em `String` em alguns fluxos; isso precisa virar streaming quando o volume crescer. O histórico precisa de política de arquivamento antes de consumir o LittleFS; SD é candidato para hardware que o ofereça. `partitions/mnemos_ota.csv` recupera dois slots OTA de 1,5 MiB; a margem deve ser revalidada a cada release. O suporte Enterprise depende do core compilado. Captive portal não é automatizado. `image_occlusion` não é capability do CYD. Modo Cram ainda não tem HMI. Os coeficientes D/S/R são MVP, não calibração científica final.
