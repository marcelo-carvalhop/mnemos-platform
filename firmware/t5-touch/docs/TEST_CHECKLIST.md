# Checklist — T5-4.7-S3 Touch

## Bring-up

- [ ] compila em `lilygo-t5-47-s3-touch`;
- [ ] e-paper limpa corretamente;
- [ ] LittleFS monta;
- [ ] RTC responde em GPIO18/17;
- [ ] GT911 responde em 0x5D ou 0x14;
- [ ] log mostra coordenadas;
- [ ] quatro cantos correspondem à orientação da HMI.

## HMI

- [ ] Home: ação principal;
- [ ] Home: Menu;
- [ ] Menu: Sincronização / Agenda / Conexão;
- [ ] Voltar / Cancelar;
- [ ] alternativas objetivas;
- [ ] Revelar resposta;
- [ ] Não recuperei / Recuperei;
- [ ] Difícil / Normal / Fácil;
- [ ] Estudar novamente / Concluir;
- [ ] nenhuma tela exige teclado.

## Energia

- [ ] bateria preservada;
- [ ] touch continua ativo após refresh do EPD;
- [ ] GPIO21 disponível para wake.


## HMI touch-first — preview.6

- [ ] instalação sem preferência salva inicia em retrato;
- [ ] Girar preserva tela, card e posição da sessão;
- [ ] orientação é persistida entre boots;
- [ ] log informa raw, logical, zone, action e arg;
- [ ] ações aceitas respeitam debounce mínimo de 400 ms;
- [ ] Abortar existe apenas durante sessão ativa;
- [ ] primeiro toque em Abortar apenas abre confirmação;
- [ ] CancelAbort volta ao mesmo card/etapa;
- [ ] ConfirmAbort preserva revisões já confirmadas e descarta a fila restante;
- [ ] Decks apenas filtra sessão; não edita biblioteca;
- [ ] open recall não revela resposta antes da tentativa;
- [ ] múltipla escolha não exige confirmação extra;
- [ ] autoavaliação mantém Não recuperei / Recuperei;
- [ ] esforço mantém Difícil / Normal / Fácil;
- [ ] resumo não exibe Abortar;
- [ ] agenda imprime valor numérico junto da barra;
- [ ] `你` / `nǐ` / `você` renderizam corretamente;
- [ ] `学` / `xué` / `estudar` renderizam corretamente.
