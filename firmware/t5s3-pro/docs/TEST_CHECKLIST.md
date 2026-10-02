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


## Série 0.7 — estabilidade funcional

- [ ] boot não espera conexão Wi-Fi;
- [ ] boot não espera NTP;
- [ ] scan Wi-Fi não congela touch;
- [ ] tentativa de conexão Wi-Fi não congela touch;
- [ ] senha incorreta retorna ao teclado;
- [ ] reconexão automática não congela a interface;
- [ ] LocalLink em LAN não muda STA para APSTA;
- [ ] open_recall usa revelar -> autoavaliação;
- [ ] cloze usa revelar -> autoavaliação;
- [ ] application usa revelar -> autoavaliação;
- [ ] multiple_choice exibe alternativas mas usa revelar -> autoavaliação;
- [ ] true_false exibe alternativas mas usa revelar -> autoavaliação;
- [ ] backend status anuncia keyboard=false;
- [ ] backend status anuncia typedRecall=false;
- [ ] backend status anuncia microSD=true;
- [ ] LocalLink info anuncia sdStorage=true;
- [ ] HTTPS sem CA é rejeitado explicitamente;
- [ ] /backend_ca.pem válido habilita HTTPS;
- [ ] cursor HTTP 410 tenta recuperação sem apagar histórico local.


## Série 0.7 preview.2 — energia e timezone

- [ ] após 2 min o terminal entra em light sleep quando ocioso;
- [ ] toque acorda do light sleep;
- [ ] botão GPIO21 acorda do light sleep;
- [ ] sessão continua retomável depois do sleep;
- [ ] SD volta a montar após light sleep se estava presente;
- [ ] Wi-Fi reconecta assincronamente após light sleep;
- [ ] após 20 min o terminal entra em deep sleep;
- [ ] touch GPIO47 não é anunciado como wake de deep sleep;
- [ ] botão GPIO21 acorda/reinicia do deep sleep;
- [ ] wake periódico de 6 h inicializa normalmente;
- [ ] bateria <=5% força deep sleep somente quando detectada;
- [ ] agenda usa offset persistido;
- [ ] mudança de timezone reescreve RTC preservando UTC.


## Série 0.7 preview.3 — biblioteca SD-first

- [ ] primeira inicialização com SD migra library.json para cards.ndjson;
- [ ] log mostra catálogo compactado e aumento de heap livre;
- [ ] Home/Agenda/Decks funcionam com catálogo leve;
- [ ] pergunta é hidratada do SD ao ser exibida;
- [ ] resposta é hidratada após Revelar resposta;
- [ ] múltipla escolha hidrata alternativas do card atual;
- [ ] sessão completa preserva FSRS;
- [ ] reboot carrega catálogo de cards.ndjson;
- [ ] importação atualiza cards.ndjson;
- [ ] estado de revisão existente é preservado ao atualizar definição;
- [ ] exportação contém perguntas/respostas completas;
- [ ] ausência do SD usa fallback LittleFS;
- [ ] remoção do SD durante estudo não causa crash.



## Série 0.7 preview.4 — OTA local

- [ ] boot sem `/mnemos/update/manifest.json` continua normal;
- [ ] manifesto com `apply=false` não instala;
- [ ] modelo incorreto é rejeitado;
- [ ] protocolo incompatível é rejeitado;
- [ ] geração <= geração atual é rejeitada;
- [ ] SHA-256 incorreto é rejeitado antes de `Update.begin`;
- [ ] tamanho incorreto é rejeitado;
- [ ] bateria detectada <20% bloqueia instalação;
- [ ] bundle válido é gravado no slot OTA inativo;
- [ ] após instalação o dispositivo reinicia no novo slot;
- [ ] manifesto vira `manifest.applied.json`;
- [ ] biblioteca SD-first permanece intacta;
- [ ] estados FSRS permanecem intactos;
- [ ] serial informa `running=app0/app1` e `next=app1/app0`;
- [ ] serial informa explicitamente se rollback do bootloader está habilitado.



## Builds de bancada

- [ ] `pio run` compila apenas `lilygo-t5-47-s3-touch-bench`;
- [ ] boot da bancada informa `flavor=bench`;
- [ ] bancada informa `light-sleep=0 deep-sleep=0 ota-auto=0`;
- [ ] após 25 minutos sem interação, USB continua enumerado;
- [ ] `tools/upload-bench.sh` nunca tenta `/dev/ttyS0`;
- [ ] `bench-demo` informa `demo=1`;
- [ ] build de produto informa `flavor=product`;
- [ ] build de produto mantém light/deep sleep habilitados.


## Primeiro OTA A/B

- [ ] `bench-ota-source` inicia em app0 com generation 70402;
- [ ] `bench-ota-source` informa `ota-auto=1`;
- [ ] bundle 70403 valida SHA-256 e tamanho;
- [ ] manifesto e firmware ficam em `/mnemos/update/`;
- [ ] source detecta e verifica a imagem antes de `Update.begin`;
- [ ] instalacao grava o slot inativo;
- [ ] reboot entra em app1 com generation 70403;
- [ ] boot completo chama `confirmRunningImage`;
- [ ] `ota-summary` mostra `running=app1 next=app0 rollback=1`;
- [ ] FSRS e biblioteca SD-first permanecem intactos;
- [ ] USB continua enumerado apos o update.
