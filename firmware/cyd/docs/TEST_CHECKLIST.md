# Checklist físico CYD v0.5.0-preview.3

1. `pio run` termina com SUCCESS e registra RAM/Flash e tamanho máximo do slot.
2. O build usa `partitions/mnemos_ota.csv` e o máximo de aplicação é compatível com um slot de 1,5 MiB.
3. Home mantém somente ação primária e Menu; quando não há revisão vencida, mostra a próxima revisão se existir.
4. Home diferencia revisão vencida de card novo; card `dueAt=0` não aparece como revisão vencida na Agenda.
5. `MENU > AGENDA` mostra Agora, Ainda hoje, Amanhã, Próximos 7 dias e Próxima revisão sem alterar estado.
6. Após uma Review, o terminal mostra o `dueAt` recém-calculado antes do próximo card/resumo.
7. Após uma primeira falha, o card só volta a ficar vencido quando o intervalo de reforço expira; com `DEMO_INTERVALS=true`, Again deve respeitar aproximadamente 30 s.
8. Sessão Review completa e imediatamente depois Practice continua disponível quando não há conteúdo agendado/novo obrigatório.
9. Practice não altera D/S/dueAt; Review e Practice avançam sem tela de agendamento individual.
10. Multiple choice e true/false registram resultado automaticamente após confiança.
11. Open recall solicita confiança, mostra referência, pede ERREI/ACERTEI e esforço somente após acerto.
12. A tela de conclusão mostra revisões ainda vencidas; na ausência delas, mostra cards novos disponíveis ou a próxima revisão global.
13. Reboot preserva `dueAt` e a Agenda reproduz os mesmos horários, salvo avanço natural do relógio.
14. Provisionamento cria `MNEMOS-*`, grava perfil e volta à rede conhecida após `/v4/complete`.
15. DirectSync funciona sem roteador e não oferece rota de provisionamento.
16. ACK limpa outbox e preserva history.
17. `/v4/metrics` retorna `mnemos.metrics/v1` após reviews.
