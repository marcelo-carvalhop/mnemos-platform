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
pio test -e native
```

Para entrar manualmente em download mode: segure BOOT, pressione e solte RST,
depois solte BOOT. Os ambientes de produto e de bancada, os scripts de
`tools/` e o ensaio de OTA estão em [docs/BENCH_BUILDS.md](docs/BENCH_BUILDS.md).

## Energia

O H752-01 usa um BQ25896 (`0x6B`) como carregador e power path. O botão PWR
está ligado só ao `/QON` desse chip, não ao ESP32 (ver
[docs/WIRING.md](docs/WIRING.md)); por isso o desligamento real é feito pelo
PMIC.

No boot, o firmware aplica o mesmo perfil elétrico do firmware de fábrica da
LilyGO (VSYS mínimo de 3,3 V, limite de entrada de 3250 mA, carga a 1024 mA
até 4,208 V, ADC ligado, OTG desligado), sem resetar os registradores do
carregador.

`Menu -> Desligar dispositivo` e o auto-off por inatividade (10 min) usam o
mesmo caminho:

1. com USB conectado, o desligamento manual é recusado e o auto-off não
   dispara: o BQ25896 não consegue cortar `VSYS` enquanto há VBUS;
2. o estado de estudo é salvo, a tela de desligado é desenhada, o Wi-Fi é
   desligado, o front light vai a zero e o microSD é desmontado;
3. o firmware grava `REG09.BATFET_DIS=1` com `BATFET_DLY=0`, preservando os
   demais bits, em até três tentativas e sem usar o USB CDC nesse trecho;
4. em bateria, `VSYS` cai a zero e o aparelho desliga por completo.

Se o corte falhar, o firmware fica inerte, sem reiniciar, para não mascarar a
falha. O terminal volta a ligar segurando PWR até o boot iniciar (cerca de
1–1,5 s; o BQ25896 exige 0,9–1,3 s) ou conectando o USB. RST continua sendo o
reset físico do ESP32-S3, e BOOT fica reservado para o download mode.

No build de produto, o light sleep é uma otimização interna que acorda por
touch ou timer, e a política de deep sleep (inatividade longa ou bateria
crítica) vira hard-off quando o aparelho está em bateria. Deep sleep não é
usado como substituto de power-off. A causa de cada boot aparece no log
`[power] boot reset=...`.

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

## Arquitetura

`src/main.cpp` mantém o estado da HMI (telas, roteamento de toque e ações) e
orquestra os serviços abaixo. Tudo roda na tarefa do `loop()` do Arduino; o
firmware não cria tarefas FreeRTOS próprias.

| Módulo | Responsabilidade |
|---|---|
| `t5_display`, `mnemos_fonts` | composição das telas em retrato 540×960, fontes em 16 tons e refresh do ED047TC1 via epdiy |
| `touch_input` | GT911 e conversão para coordenadas lógicas |
| `power_service` | BQ25896, light sleep, auto-off e hard-off |
| `battery_service` | BQ27220 somente leitura e estimativa de carga |
| `backlight_service` | PWM do front light e nível salvo |
| `study_engine` | fila e fluxo das sessões de estudo |
| `fsrs_engine`, `fsrs_replay_service` | agendamento FSRS e reconstrução dos estados a partir do histórico |
| `schedule_service` | agenda: vencidos, hoje, amanhã e próximos 7 dias |
| `storage` | LittleFS: biblioteca, estado, sessão, histórico e outbox de revisões |
| `sd_card_service` | biblioteca canônica no microSD (SD-first), decks e exportação |
| `network_service` | perfis de Wi-Fi, URL do backend e token do terminal |
| `backend_sync_service`, `sync_codec` | sincronização HTTP(S) com o backend |
| `local_link_service`, `metrics_service` | provisionamento local (LAN ou SoftAP) com token e métricas de estudo |
| `ota_service` | atualização A/B a partir do microSD |
| `time_service`, `gps_time_service` | hora pelo RTC, SNTP e GNSS |

O boot (`setup()`) inicializa nesta ordem: front light, I²C, EPD (com limpeza
completa), BQ25896, BQ27220, LittleFS, rede, relógio, touch, microSD, OTA
local, biblioteca (catálogo do SD, LittleFS ou decks padrão), sincronização
inicial e motor de estudo. O `loop()` amostra a bateria a cada 60 s, trata
desligamento e sleep, atende LocalLink, rede e sincronização e então processa
o toque.

Onde ficam os dados:

- LittleFS: `/library.json`, `/state.json`, `/session.json`,
  `/sync_meta.json`, `/review_history.ndjson`, `/review_outbox.ndjson` e
  `/progress_resets.ndjson`; os JSON são gravados em `.tmp` e renomeados;
- microSD: `/mnemos/library/cards.ndjson` (biblioteca canônica),
  `/mnemos/decks`, `/mnemos/export` e `/mnemos/update` (OTA);
- NVS (Preferences): perfis de Wi-Fi, URL do backend, token do terminal,
  preferências de HMI e nível do front light.

## Interface

As telas seguem o design system "Marinho" do web e do app
([docs/design/DESIGN-SYSTEM.md](../../docs/design/DESIGN-SYSTEM.md)), na
escala desta tela: ~1,4 px por px CSS do celular.

- **Navegação.** Barra do topo com a marca, e barra de abas embaixo (Hoje,
  Baralhos, Estudar, Sincronizar, Mais), como o web no celular. As subtelas
  do "Mais" voltam pelo "‹ Voltar" do topo. O estudo tem topo próprio: "‹"
  pausa e volta ao Hoje, "×" pede para encerrar.
- **Medidas.** `include/hmi_layout.h` é a fonte única: o desenho e as zonas
  de toque de `main.cpp` leem as mesmas constantes (`MARGIN`, `GUTTER`,
  `TAB_BAR_Y`, `actionZone(portrait, tabbed)`...).
- **Fontes.** Geist, Geist Mono, Literata e um recorte da Noto Sans SC,
  rasterizados em 16 tons. Para mudar um tamanho, edite a tabela `ROLES` de
  `tools/fonts/gen_mnemos_fonts.py` e gere de novo `src/mnemos_font_data.h`.
- **Cinzas.** Mais escuros que os do web: o ED047TC1 mostra os tons claros
  bem mais claros que um LCD (conferido com câmera). A escala fica no topo de
  `src/t5_display.cpp` (`INK` … `PAPER`).

Para revisar o desenho pelo computador, o firmware de bancada aceita
`mnemos screen` (envia o canvas) e `{"cmd":"tap","x":..,"y":..}` (toque
sintético). `tools/hmi_capture.py` usa os dois:

```bash
uv run --no-project --python 3.12 --with pyserial==3.5 --with pillow==11.1.0     python tools/hmi_capture.py COM3 tap 162 908 baralhos.png
```

## Testes e CI

- `pio test -e native` roda no PC os testes de FSRS (fixtures de referência),
  da política de bateria e do contrato do lote de revisões enviado ao backend
  (mesmas regras de `_validate_terminal_review`), com stubs de Arduino,
  `String`, Wire e BQ27220 em `test/support`.
- `.github/workflows/firmware-t5s3-pro.yml` roda esses testes, compila os
  cinco ambientes com `-Werror` e publica o binário de produto, o de bancada e
  o pacote OTA como artefatos.
- Os roteiros de validação no hardware estão em
  [docs/TEST_CHECKLIST.md](docs/TEST_CHECKLIST.md) e
  [docs/HMI_TEST_CHECKLIST.md](docs/HMI_TEST_CHECKLIST.md).

## Servidor

A ausência de backend não impede o estudo local. Quando houver servidor, o
terminal precisa de uma URL alcançável pela rede e de sua credencial de
terminal.

## Documentação

- [docs/WIRING.md](docs/WIRING.md): pinos, barramentos, botões e alimentação.
- [docs/BENCH_BUILDS.md](docs/BENCH_BUILDS.md): ambientes, scripts e ensaio OTA.
- [CHANGELOG.md](CHANGELOG.md): histórico de versões.
- [docs/ROADMAP.md](docs/ROADMAP.md): pendências conhecidas.
- [lib/README.md](lib/README.md): bibliotecas vendorizadas e patches locais.
- [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md): licenças de terceiros.

## Limitações conhecidas

- O BQ27220 desta unidade está `SEALED` com perfil de 3000 mAh; a carga
  exibida é uma estimativa por tensão (ver Bateria).
- Com USB conectado não existe desligamento físico (limite do BQ25896).
- Se o corte do BATFET falhar, o aparelho fica ligado e inerte, com a tela de
  desligado, até a bateria acabar ou o RST ser pressionado.
- Pacotes OTA são verificados por modelo, geração e SHA-256, mas não são
  assinados.
- Segredos (Wi-Fi e token) ficam em texto claro na NVS; secure boot e
  criptografia de flash estão desligados.
- O firmware aceita backend em `http://` (uso em laboratório).
- O núcleo de estudo (FSRS, storage e sincronização) é duplicado entre as
  variantes de firmware.
- `lib/BQ27220` deriva de um driver GPL-3.0; ver
  [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
