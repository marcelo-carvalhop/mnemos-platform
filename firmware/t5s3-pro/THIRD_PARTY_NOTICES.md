# Componentes de terceiros — firmware/t5s3-pro

| Componente | Versão / origem | Licença | Uso |
|---|---|---|---|
| Arduino-ESP32 | 2.0.14 (`espressif32@6.5.0`) | LGPL-2.1-or-later | framework |
| ESP-IDF (pré-compilado no Arduino-ESP32) | 4.4 | Apache-2.0 | framework |
| epdiy | 2.0.0, cópia da LilyGO com patches | LGPL-3.0 | `lib/epdiy` |
| Driver BQ27220 | cópia da LilyGO com alterações | GPL-3.0 provável (ver abaixo) | `lib/BQ27220` |
| XPowersLib | 0.2.7 | MIT | dependência |
| SensorLib | 0.4.1 | MIT | dependência |
| ArduinoJson | 7.4.3 | MIT | dependência |
| QRCode (ricmoo) | `eafbde4` | MIT | dependência |
| Unity | 2.6.1 | MIT | somente testes no host |
| Geist e Geist Mono (Vercel) | `app/mobile/assets/fonts` | OFL-1.1 | fontes da interface, rasterizadas em `src/mnemos_font_data.h` |
| Literata (TypeTogether) | `app/mobile/assets/fonts` | OFL-1.1 | texto dos cards, idem |
| Noto Sans SC (Adobe/Google), recortada como "Mnemos Hanzi" | `tools/fonts/MnemosHanzi.ttf` | OFL-1.1 (`tools/fonts/OFL-NotoSansSC.txt`) | ideogramas do baralho de mandarim, idem |
| Fontes bitmap antigas (`tools/fonts/legacy/mnemos_fonts_1bpp.cpp`) | não documentada | não documentada | só os glifos que as famílias acima não cobrem (vogais com tom do pinyin e afins) |

As versões das dependências são as fixadas em `platformio.ini`; os detalhes
das cópias locais estão em [lib/README.md](lib/README.md).

## Pontos a resolver antes de distribuir binários

Estes itens são observações técnicas, não aconselhamento jurídico.

- **Driver BQ27220.** O código publicado pela LilyGO não traz licença, mas os
  comentários, os tempos e os tipos de Data Memory coincidem com o driver do
  firmware Flipper Zero, distribuído sob GPL-3.0. Se essa origem se
  confirmar, distribuir o firmware com esse código traz as obrigações da
  GPL-3.0. As alternativas são licenciar o firmware de forma compatível ou
  substituir o driver por uma implementação própria. O firmware só usa
  leituras de registradores padrão, o que torna a substituição pequena.
- **epdiy (LGPL-3.0).** Num firmware ligado estaticamente, a LGPL exige que o
  usuário consiga trocar a biblioteca, o que normalmente significa fornecer o
  código-fonte ou os objetos para religar o firmware.
- **Fontes.** As fontes da interface são OFL-1.1 e as tabelas são geradas
  por `tools/fonts/gen_mnemos_fonts.py`. Ainda vêm das fontes bitmap antigas,
  de origem não registrada, os glifos que Geist, Literata e Noto Sans SC não
  cobrem (o fallback de 1 bit). Para fechar o ponto, basta gerar esses glifos
  de uma fonte OFL (a própria Noto Sans cobre o pinyin) e apagar o legado.
- **Licença do projeto.** O repositório não tem arquivo `LICENSE` na raiz.
