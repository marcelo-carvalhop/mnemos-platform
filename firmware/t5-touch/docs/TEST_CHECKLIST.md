# Checklist físico — T5 v0.6.0-preview.2

## Bring-up

- [ ] `pio run` finaliza com SUCCESS.
- [ ] Flash reporta 16 MB e PSRAM está habilitada.
- [ ] Upload via USB funciona.
- [ ] Serial mostra inicialização do display.
- [ ] Serial mostra RTC PCF8563 online ou uma falha explícita.
- [ ] Serial mostra CardKB `0x5F` online em GPIO16/15.

## E-paper

- [ ] Home ocupa orientação paisagem 960×540 corretamente.
- [ ] Não há texto cortado nas bordas.
- [ ] Trocas de tela não deixam artefatos impeditivos.
- [ ] Digitação atualiza apenas a área de resposta após pequena pausa.
- [ ] Digitação rápida não perde caracteres por causa do refresh.

## CardKB

- [ ] letras minúsculas funcionam.
- [ ] Shift produz maiúsculas.
- [ ] espaço funciona.
- [ ] Backspace remove o último caractere.
- [ ] Enter confirma resposta.
- [ ] números 1–4 selecionam alternativas corretamente.
- [ ] Menu responde a 1/2/3 e Backspace.

## Sessão

- [ ] open_recall aceita texto antes da confiança.
- [ ] cloze aceita texto antes da confiança.
- [ ] application aceita texto antes da confiança.
- [ ] multiple_choice corrige automaticamente.
- [ ] true_false corrige automaticamente.
- [ ] confiança é sempre coletada antes da resposta correta aparecer.
- [ ] erro não pergunta esforço.
- [ ] acerto pergunta difícil/normal/fácil.
- [ ] prática não altera dueAt.
- [ ] nova prática pode começar imediatamente após uma sessão concluída.
- [ ] não existe feedback de reagendamento por cartão.
- [ ] Home/Resumo/Agenda mostram somente a próxima revisão agregada.

## RTC e persistência

- [ ] sincronizar relógio via Wi-Fi ou DirectSync.
- [ ] desligar totalmente o terminal por alguns minutos.
- [ ] religar sem Wi-Fi.
- [ ] serial informa restauração pelo RTC.
- [ ] próxima revisão permanece coerente com o tempo realmente decorrido.

## Rede

- [ ] configuração SoftAP funciona.
- [ ] DirectSync SoftAP funciona.
- [ ] `/v4/info` anuncia `keyboard=true`, `touch=false`, `typedRecall=true`.
- [ ] reviews saem da outbox somente após ACK.
- [ ] review_history permanece depois do ACK.
