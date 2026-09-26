# Ligação de bancada — T5 + Unit CardKB v1.1

Pinagem lógica adotada pelo firmware:

| Unit CardKB v1.1 | LILYGO T5-4.7-S3 |
|---|---|
| GND | GND |
| SDA | GPIO16 |
| SCL | GPIO15 |
| VCC | fonte 5 V validada; ver nota |

GPIO16 e GPIO15 pertencem ao conjunto do SD na placa T5 e são liberados quando o SD não é utilizado. Nesta variante o firmware não inicializa SD.

## Atenção à alimentação

A documentação do CardKB especifica VCC de 5 V. O rótulo `V` do conector auxiliar do T5 não é suficiente para concluir que esse pino entrega 5 V. Antes de ligar o fio de alimentação do CardKB nesse conector, medir a tensão com multímetro nas condições reais de uso.

Para o primeiro bring-up, a opção eletricamente mais conservadora é usar GND comum, sinais GPIO16/15 e alimentar o CardKB por uma fonte 5 V adequada/VBUS cuja tensão esteja confirmada. Não aplicar 5 V diretamente aos GPIO16/15.

O firmware usa I2C a 100 kHz e faz probe em `0x5F` no boot. O resultado aparece no monitor serial.
