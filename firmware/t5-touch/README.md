# Mnemos T5 Touch — v0.6.0-preview.3-touch

Firmware do terminal físico Mnemos para o LILYGO T5-4.7-S3 com
touchscreen capacitivo. Esta variante será utilizada até a chegada do
T5S3 Pro.

O firmware do T5 sem touchscreen permanece preservado em `firmware/t5`.
Esta pasta (`firmware/t5-touch`) é independente.

## Hardware

- ESP32-S3;
- e-paper 4,7" 960×540;
- GT911 como entrada principal;
- RTC PCF8563 e GT911 em SDA GPIO18 / SCL GPIO17;
- IRQ do GT911 em GPIO47;
- GT911 sondado em `0x5D` e `0x14`;
- Battery ADC em GPIO14;
- botão físico GPIO21 preservado para wake/fallback;
- microSD desabilitado.

A transformação segue o exemplo oficial LILYGO:

```cpp
touch.setMaxCoordinates(960, 540);
touch.setSwapXY(true);
touch.setMirrorXY(false, true);
```

## Arquitetura de entrada

```text
GT911
  ↓
TouchInput
  ↓
MnemosTouchPoint
  ↓
UiAction
  ↓
processAction()
  ↓
StudyEngine
```

O CardKB não participa desta variante.

## Build

```bash
cd firmware/t5-touch
pio run
```

Upload:

```bash
pio run --target upload
```

Monitor:

```bash
pio device monitor -b 115200
```

Log esperado:

```text
[touch] GT911 online addr=0x5D SDA=18 SCL=17 IRQ=47
```

O endereço também pode ser `0x14`.


## Agenda semanal e diagnostico touch

A Home apresenta os proximos sete dias. Cada linha mostra a quantidade
de cartoes e os decks previstos pelo estado FSRS. Cartoes vencidos e
cartoes novos aparecem em hoje.

Cada toque resolvido produz uma linha serial como:

```text
[touch][action] screen=Question x=481 y=503 -> Revelar resposta
```

Uma area `Abortar` aparece nas telas de estudo. Ao usa-la, o cartao atual
nao gera evento de revisao; a sessao permanece disponivel para retomada.

## Deck de treinamento de mandarim

A preview.4 inclui um deck local de 100 caracteres essenciais para
iniciante. Os ideogramas usam um subconjunto bitmap CJK de 100 glifos.
A resposta usa pinyin com numero de tom, por exemplo `ni3 - voce`.


## Rotacao por software - preview.5.3

A versao da LilyGo-EPD47 usada pelo projeto nao expoe a API moderna de
rotacao. O Mnemos usa um canvas logico 8-bit em PSRAM e um framebuffer
fisico separado, fazendo a rotacao no refresh.

O GT911 usa TouchDrv.hpp e getTouchPoints().


## Preview 0.6.0-preview.6-touch — HMI touch-first

A variante touch passa a seguir `docs/HMI_T5_TOUCH_GUIDELINES_v0.1.md`.

- retrato 540x960 como padrão de primeira execução;
- paisagem 960x540 com layout próprio em duas colunas quando aplicável;
- barra de sistema com Menu, Girar e Abortar contextual;
- aborto confirmado em dois passos;
- tela Decks apenas como filtro de sessão;
- zonas nomeadas de touch convertidas para `UiAction`;
- log `raw/logical/zone/action`;
- debounce de 400 ms entre ações aceitas;
- Noto Sans CJK SC rasterizada em 14, 18 e 22 px;
- português, pinyin tonal e Hanzi no mesmo renderer;
- full refresh mantido nesta etapa; refresh parcial fica para spike posterior.
