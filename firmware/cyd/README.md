# Mnemos CYD firmware — v0.5.0-preview.3

Esta pasta contém o firmware de validação para ESP32-2432S028 (CYD). A v0.5 reduz a HMI, separa revisão programada de prática voluntária, introduz cartões objetivos com correção automática, registra métricas metodológicas e remove BLE do caminho de sincronização.

A conectividade usa somente Wi-Fi. Em infraestrutura, o terminal opera como station e sincroniza com backend. Sem infraestrutura, o usuário abre `SINCRONIZAR > COM O CELULAR`; o terminal cria temporariamente `MNEMOS-XXXXXX` em 2,4 GHz e expõe Device Protocol v4 por HTTP em `192.168.4.1`. A mesma infraestrutura SoftAP também é usada para provisionamento, mas os modos possuem permissões diferentes.

## Build

```bash
cd firmware/cyd
pio run
```

A preview.3 usa `partitions/mnemos_ota.csv`: dois slots OTA de 1,5 MiB e 960 KiB de LittleFS. A mudança foi habilitada depois que a preview.1 compilou fisicamente com 1.151.657 bytes de flash e 60.536 bytes de RAM, deixando margem suficiente dentro de cada slot de 1,5 MiB. O LittleFS permanece no offset `0x310000`, o mesmo usado pelo layout Huge App anterior.

## Fluxo de estudo

A Home mostra apenas a ação contextual `ESTUDAR`, `PRATICAR` ou `CONTINUAR`, além de `MENU`. Quando não existe revisão pendente, ela também informa o próximo horário agendado sem criar um novo botão. `MENU > AGENDA` mostra apenas carga imediata: agora, ainda hoje, amanhã, próximos sete dias e a próxima revisão. O `dueAt` individual de cada card não é exibido após a resposta. O scheduler permanece transparente durante a sessão; o usuário vê apenas a próxima revisão agregada na Home, na Agenda e no resumo da sessão.

Respostas abertas/cloze/aplicação seguem pergunta -> confiança -> resposta de referência -> erro/acerto -> esforço se correta. Múltipla escolha e verdadeiro/falso seguem pergunta -> alternativa -> confiança -> correção automática -> esforço se correta.

`PracticeSession` produz eventos, mas `affectsSchedule=false`; portanto não altera D, S ou `dueAt`. `ReviewSession` altera o agendamento pelo `LearningModel`.

## Limitações do protótipo CYD

O CYD ainda não integra CardKB, NFC, cartão SD nem image occlusion. Em respostas abertas, o usuário formula mentalmente/externamente a resposta e faz autoavaliação. Modo cram está representado no domínio e no `LearningModel`, mas ainda não aparece na HMI principal. Os coeficientes D/S/R são provisórios e centralizados em `include/config.h` para calibração posterior.
