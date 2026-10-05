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
| Fontes bitmap de `src/mnemos_fonts.cpp` | não documentada | não documentada | firmware |

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
- **Fontes.** A família e a licença das fontes convertidas em
  `src/mnemos_fonts.cpp` não estão registradas no repositório.
- **Licença do projeto.** O repositório não tem arquivo `LICENSE` na raiz.
