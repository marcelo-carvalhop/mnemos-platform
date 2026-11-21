# T5 E-Paper S3 Pro H752-01 — Hardware

Resumo do hardware usado pelo firmware, conferido no esquemático oficial
`T5 E-paper S3 Pro V1.0 24-12-24` e no `docs/pinmap.md` do repositório
[Xinyuan-LilyGO/T5S3-4.7-e-paper-PRO](https://github.com/Xinyuan-LilyGO/T5S3-4.7-e-paper-PRO).

## Barramento I²C (SDA GPIO39, SCL GPIO40)

| Dispositivo | Endereço | Função |
|---|---|---|
| PCA9535 | `0x20` | expansor de I/O: controle do EPD, `LORA_EN`, botão S3 |
| PCF8563 | `0x51` | RTC, com suporte para bateria de backup (J12) |
| BQ27220 | `0x55` | fuel gauge, usado somente para leitura |
| GT911 | `0x5D` | touch |
| TPS65185 | `0x68` | fontes de alta tensão do EPD |
| BQ25896 | `0x6B` | carregador, power path e hard-off |

O `Wire` do Arduino é o dono do driver I2C0; o epdiy reaproveita esse driver
(`MNEMOS_EXTERNAL_I2C_DRIVER`).

## GPIO do ESP32-S3

| Função | GPIO |
|---|---|
| Touch INT / RST | 3 / 9 |
| RTC INT | 2 |
| PCA9535 INT | 38 |
| Front light (`BL_EN`, PWM até ~1 kHz) | 11 |
| microSD CS / SCK / MOSI / MISO | 12 / 14 / 13 / 21 |
| LoRa SX1262 CS / IRQ / RST / BUSY | 46 / 10 / 1 / 47 |
| GNSS: TX / RX do ESP32 | 43 / 44 |
| EPD D0–D7 | 5, 6, 7, 15, 16, 17, 18, 8 |
| EPD CKV / STH / LEH / STV / CKH | 48 / 41 / 42 / 45 / 4 |
| BOOT | 0 |
| USB D- / D+ | 19 / 20 |

O microSD e o LoRa compartilham o SPI (SCK 14, MOSI 13, MISO 21).

## PCA9535

| Pino | Sinal |
|---|---|
| IO0_0 | `LORA_EN`: habilita o LDO de 3,3 V do LoRa e do GNSS |
| IO0_1–IO0_7 | não conectados |
| IO1_0 / IO1_1 | `EP_OE` / `EP_MODE` |
| IO1_2 | botão S3 (`BUTTON`, pull-up de 10 kΩ) |
| IO1_3 / IO1_4 / IO1_5 | `TPS_PWRUP` / `VCOM_CTRL` / `TPS_WAKEUP` |
| IO1_6 / IO1_7 | `TPS_PWR_GOOD` / `TPS_INT` (entradas) |

## Botões

| Botão | Ligação | Uso no Mnemos |
|---|---|---|
| PWR (S4) | `/QON` do BQ25896, direto ao GND | religar depois do hard-off; não é lido pelo ESP32 |
| RST (S1) | `EN` do ESP32-S3 | reset físico |
| BOOT (S2) | GPIO0, pull-up de 10 kΩ | download mode (segure BOOT, pressione RST) |
| S3 | PCA9535 IO1_2 | não usado |

O PWR só age sobre o BQ25896. Segurado por 0,9–1,3 s (`tSHIPMODE`), tira o
carregador do ship mode e religa o sistema. Com o sistema ligado e sem USB,
segurado por 16–23 s (`tQON_RST`), força um reset de energia. O firmware não
consegue detectar o PWR.

## Alimentação

- USB (VBUS) e bateria entram no BQ25896, que gera `VSYS`.
- `VSYS` alimenta:
  - o LDO ME6217 U12 (EN ligado a `VSYS`), que gera `VDD3V3` para o ESP32-S3
    e os periféricos;
  - o LDO ME6217 U7 (EN = `LORA_EN`), que gera `VCC3V3` para o LoRa e o GNSS;
  - o TPS65185 do EPD;
  - o driver do front light PT4103B23F.
- O front light é habilitado por `BL_EN` através de 100 Ω, com pull-down de
  10 kΩ no EN: sem acionamento, fica apagado.
- O BQ27220 mede a corrente da bateria por um resistor de 10 mΩ entre a
  bateria e o pino BAT do BQ25896.
- Com `REG09.BATFET_DIS=1` e sem USB, `VSYS` vai a zero e todo o sistema
  desliga. Com USB presente, o BQ25896 mantém `VSYS` pela entrada externa e o
  corte não acontece.
- Bateria oficial: Li-Po de 3,7 V / 1500 mAh.
