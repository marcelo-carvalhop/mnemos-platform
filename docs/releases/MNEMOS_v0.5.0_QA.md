# QA v0.5.0-preview.3

## Base validada da preview.1

A preview.1 foi compilada fisicamente no ambiente PlatformIO Espressif32 7.0.1 / Arduino-ESP32 2.0.17. Resultado informado: `SUCCESS`, RAM 60.536 bytes (18,5%) e flash 1.151.657 bytes usando Huge App. A HMI física foi validada pelo usuário sem falhas observadas no fluxo principal.

## Mudanças que exigem nova validação na preview.3

A preview.3 mantém `ScheduleService`, exibição da próxima revisão na Home, tela `MENU > AGENDA` e próximo horário na tela de conclusão. O `dueAt` individual não é exibido depois de cada card; PracticeSession continua sem alterar agendamento.

O scheduler também corrige o caso de primeira falha: depois que um card recebe `dueAt` de reaprendizado, ele não deve continuar sendo considerado imediatamente vencido apenas porque ainda possui zero acertos. A maturidade passa a considerar card `new` somente quando `lastReviewedAt=0`.

O particionamento passa a `partitions/mnemos_ota.csv`: app0=1,5 MiB, app1=1,5 MiB e LittleFS=960 KiB. O offset do LittleFS permanece `0x310000`.

## Checklist local obrigatório

Executar `pio run` e registrar RAM/Flash e tamanho máximo do slot. Depois gravar o CYD e validar: Home sem pendências mostra próxima revisão; Agenda mostra contagens coerentes; erro inicial respeita intervalo de reforço; ao concluir sessão sem pendências a próxima revisão é mostrada; Practice pode iniciar imediatamente e não muda a agenda; reboot preserva agenda; multiple_choice/true_false continuam corrigindo automaticamente; DirectSync e provisionamento continuam operacionais; ACK limpa outbox sem apagar history.

Não criar tag final v0.5.0 antes de concluir este checklist.
