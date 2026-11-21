# Bibliotecas vendorizadas

Código de terceiros copiado para o projeto, com alterações locais. Ao
atualizar a partir da origem, reaplique os patches listados aqui. As licenças
estão em [../THIRD_PARTY_NOTICES.md](../THIRD_PARTY_NOTICES.md).

## epdiy

- Origem: `lib/epdiy` do repositório
  [Xinyuan-LilyGO/T5S3-4.7-e-paper-PRO](https://github.com/Xinyuan-LilyGO/T5S3-4.7-e-paper-PRO)
  (epdiy 2.0.0). Licença LGPL-3.0 (`epdiy/LICENSE`).
- Patches em `epdiy/src/board/epd_board_v7.c`:
  - `MNEMOS_EXTERNAL_I2C_DRIVER`: a placa não instala nem remove o driver
    I2C0, que pertence ao `Wire` do Arduino;
  - `epd_board_poweron()` espera o `PWR_GOOD` do TPS65185 por no máximo 500
    tentativas, uma por tick; na origem a espera era infinita.
- As demais diferenças em relação à cópia da LilyGO são apenas de espaços em
  branco.

## BQ27220

- Origem: `lib/BQ27220` do mesmo repositório da LilyGO, publicado sem
  cabeçalho de licença. Os comentários, os tempos e os tipos de Data Memory
  coincidem com `lib/drivers/bq27220.c` e `bq27220_data_memory.h` do firmware
  Flipper Zero (GPL-3.0).
- Alterações locais:
  - transporte I²C com verificação de `endTransmission()`, da quantidade
    recebida e de cada byte, usando repeated START;
  - `readRegU16(reg, value)`, que distingue falha de I²C de um valor `0xFFFF`;
  - getters de status que retornam `false` em falha de I²C;
  - Device Number lido via MAC com validação do subcomando ecoado;
  - `ENTER_CFG_UPDATE` enviado como subcomando de `Control()`;
  - atraso de seleção de MAC de 15 ms e escrita de checksum/comprimento com
    2 bytes;
  - perfil de Data Memory identificado como H752-01 3,7 V / 1500 mAh.
- O firmware usa apenas a API de leitura. `init()`, `reset()`,
  `sealAccess()`, `unsealAccess()`, `fullAccess()` e
  `dateMemoryCheck(..., true)` escrevem no gauge e não devem ser chamados sem
  um procedimento de provisionamento confirmado para o H752-01.
