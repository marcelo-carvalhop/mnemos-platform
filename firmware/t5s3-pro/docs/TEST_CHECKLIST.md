# Checklist final — Mnemos T5S3 Pro H752-01

## Build e boot

- [ ] `pio run -e t5s3-pro-bench` compila.
- [ ] upload entra por BOOT + RST.
- [ ] display inicia em 960×540 físico / 540×960 lógico.
- [ ] LittleFS monta.
- [ ] microSD monta quando presente.

## Bateria

- [ ] boot registra `[battery] identity=OK device=0x0220`.
- [ ] boot registra `profile=UNTRUSTED reason=design-capacity` com
  `design=3000 mAh expected=1500 mAh percent=voltage data-memory=UNTOUCHED`
  nesta unidade.
- [ ] nenhum log de unseal, full-access, seal, reset ou CFGUPDATE aparece no boot
  e o `SEC` do gauge é o mesmo de antes do boot.
- [ ] a cada 60 s a serial mostra `trust=UNTRUSTED source=voltage` com tensão,
  corrente, tensão compensada (`comp`) e filtrada (`filt`).
- [ ] ícone de bateria aparece (não riscado) e muda de nível conforme a estimativa.
- [ ] em bateria, o indicador não sobe depois de picos de consumo (sync Wi-Fi,
  refresh); com USB carregando, não desce.
- [ ] `charging=1` e o `+` do ícone só aparecem com corrente de carga ≥ 20 mA.
- [ ] com USB conectado, `critical=0` mesmo com bateria baixa.
- [ ] `critical=1` só aparece em bateria, com `comp` ≤ 3,45 V em duas amostras
  seguidas.
- [ ] não existe porcentagem textual na barra superior.

## PMIC e energia

- [ ] log de boot mostra `batfet=0 dly=0 qon=1`.

- [ ] boot registra `BQ25896 online`.
- [ ] BQ25896 responde em `0x6B`.
- [x] com USB conectado, shutdown é recusado e o terminal permanece recuperável.
- [x] em bateria apenas, `Menu -> Desligar dispositivo` corta o BATFET e remove `VSYS`; se o corte falhar, o firmware permanece inerte sem reboot.
- [x] depois do corte por BQ25896, manter `PWR/QON` por ~1–1,5 s liga o terminal.
- [x] conectar USB também liga o terminal desligado.
- [ ] RST continua reiniciando o ESP32-S3.
- [ ] BOOT não é usado pelo Mnemos como botão de energia.
- [ ] auto-off de 10 min usa o mesmo shutdown físico quando em bateria.
- [ ] auto-off não corta o sistema enquanto USB/VBUS está presente.
- [x] desafio resolvido — hard-off/PWR: o fluxo de desligamento travava em `Serial.flush()` após a remoção física do USB, antes de alcançar o BQ25896; o caminho crítico foi tornado independente de USB CDC, permitindo aplicar `REG09.BATFET_DIS`, cortar `VSYS` em bateria e religar por `PWR/QON` (~1–1,5 s). A conexão de USB também religa o terminal por comportamento do próprio PMIC.

## Touch e estudo

- [ ] GT911 responde em `0x5D`.
- [ ] quatro cantos correspondem à HMI retrato.
- [ ] uma sessão pode ser iniciada, respondida e concluída.
- [ ] reboot preserva estado FSRS.
- [ ] sessão interrompida permanece retomável.

## Rede e relógio

- [ ] PCF8563 responde em `0x51`.
- [ ] Wi-Fi escaneia/conecta sem bloquear a HMI.
- [ ] GNSS pode corrigir a hora quando necessário.
- [ ] rádio Wi-Fi pode ser suspenso sem apagar credenciais.
