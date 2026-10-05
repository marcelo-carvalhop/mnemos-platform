# Mnemos T5S3 Pro — H752-01

Firmware do terminal dedicado Mnemos para o LILYGO T5 E-Paper S3 Pro H752-01.

A HMI opera em retrato lógico 540×960 sobre o painel físico 960×540. O
terminal é offline-first: estudo, sessão, FSRS, biblioteca local e histórico
não dependem de servidor.

## Build

```bash
cd firmware/t5s3-pro
pio run -e t5s3-pro-bench
pio run -e t5s3-pro-bench -t upload
pio device monitor -b 115200
```

Para entrar manualmente em download mode: segure BOOT, pressione e solte RST,
depois solte BOOT.

## Energia

O gerenciamento de power-off usa um serviço direto do BQ25896 pelo barramento
I2C compartilhado. No boot, o firmware reseta os registradores do carregador,
sai de HIZ, habilita explicitamente o caminho da bateria, desliga OTG e
watchdog e reaplica o perfil elétrico do H752-01.

No desligamento, todas as gravações e suspensões de periféricos acontecem antes
do comando destrutivo. Em seguida OTG e carga são desabilitados e
`REG09.BATFET_DIS=1` é a última escrita I2C. `BATFET_DLY` fica desligado. Se o
ESP32 ainda estiver executando 1,5 s depois, o terminal reinicia
automaticamente em vez de permanecer com aparência falsa de desligado.


O H752-01 possui BQ25896 em `0x6B` para gerenciamento de energia e BQ27220 em
`0x55` para fuel gauge.

O Mnemos segue o modelo do firmware oficial da LilyGO:

- `Menu -> Desligar dispositivo` salva estado, suspende periféricos e chama
  `REG09.BATFET_DIS=1` no BQ25896, preservando os demais bits;
- o auto-off por inatividade usa o mesmo shutdown físico;
- em alimentação somente por bateria, o BQ25896 corta o battery power path;
- o terminal volta a ligar mantendo `PWR/QON` pressionado até o boot iniciar (~1–1,5 s no hardware validado) ou conectando USB;
- `RST` permanece reset físico pelo EN;
- `BOOT` fica reservado para boot/download do ESP32-S3 e não é tratado como
  botão de energia pelo aplicativo.

O BQ25896 não consegue desligar fisicamente o sistema enquanto VBUS/USB está
alimentando a placa. Por isso o auto-off é bloqueado com USB conectado e o
shutdown manual é recusado nesse estado. O teste final de liga/desliga deve ser
feito somente com bateria.

O light sleep continua sendo uma otimização interna. Ele pode acordar por touch
ou timer. Deep sleep não é usado como substituto de power-off.

## Bateria

O BQ27220 (`0x55`) é usado estritamente como sensor read-only. O firmware lê
identidade (Device Number `0x0220`), estado de segurança, tensão, corrente e
capacidades, mas nunca envia chaves de UNSEAL/FULL ACCESS, `RESET`,
`CFGUPDATE` ou `SEAL`, nem escreve Data Memory.

A confiança no gauge tem três níveis:

- **ausente** — sem resposta em `0x55` ou Device Number diferente de `0x0220`.
  O ícone aparece riscado e nenhuma decisão de energia usa a bateria; a
  identificação é tentada novamente a cada amostra;
- **perfil não validado** — o gauge responde, mas `DesignCapacity()` não é
  1500 mAh (célula oficial do H752-01) ou `FullChargeCapacity()` /
  `RemainingCapacity()` são incoerentes com ela. SOC e capacidades do gauge
  vão apenas para o log; a carga exibida é estimada pela tensão;
- **perfil validado** — capacidades coerentes com 1500 mAh, `INITCOMP=1` e
  `CFGUPDATE=0`. O SOC do BQ27220 passa a ser a fonte da porcentagem.

A estimativa por tensão compensa a queda I·R com a corrente medida pelo gauge
(0,12 Ω, limitada a ±0,15 V), aplica filtro exponencial a cada amostra de 60 s
e histerese: em bateria o indicador só desce e, carregando, só sobe; o sentido
oposto exige diferença de pelo menos 10 pontos.

Bateria crítica só é avaliada sem alimentação externa (VBUS do BQ25896 ou
corrente de carga medida): tensão compensada ≤ 3,45 V em duas amostras
seguidas (sem o filtro da HMI, para não atrasar o corte no fim da descarga) e,
com perfil validado, também SOC ≤ 5%. O SOC de um perfil não validado nunca
dispara hard-off. O limite de 20% do OTA usa a mesma porcentagem exibida.

Estado conhecido da unidade de desenvolvimento: o gauge está `SEALED` com
perfil de 3000 mAh (`DesignCapacity` e `FullChargeCapacity`), as sequências
`0x0414/0x3672` e `0x8000/0x8000` não o devolveram a `UNSEALED` e o firmware
factory da LilyGO também reporta `BQ27220 NOK`. Reprovisionar exige a golden
image ou o procedimento oficial do H752-01; não use tentativa e erro.

A barra superior mantém somente o ícone de bateria; não há porcentagem numérica
redundante.

## Servidor

A ausência de backend não impede o estudo local. Quando houver servidor, o
terminal precisa de uma URL alcançável pela rede e de sua credencial de
terminal.
