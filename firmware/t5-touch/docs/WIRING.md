# T5-4.7-S3 Touch — Hardware

| Função | GPIO / endereço |
|---|---|
| RTC/Touch SDA | GPIO18 |
| RTC/Touch SCL | GPIO17 |
| GT911 IRQ | GPIO47 |
| PCF8563 | 0x51 |
| GT911 | 0x5D ou 0x14 |
| Battery ADC | GPIO14 |
| Wake button | GPIO21 |

O GT911 e o RTC compartilham o mesmo `Wire`.

GPIO47 não é RTC GPIO nessa placa. O touchscreen não deve ser tratado
como fonte nativa de wake de deep sleep; GPIO21 permanece como wake.
