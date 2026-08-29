# Changelog — firmware/t5

## 0.6.0-preview.1

Primeiro port funcional do firmware Mnemos para LILYGO T5-4.7-S3 sem touch.

Principais mudanças em relação ao protótipo CYD v0.5:

- e-paper 960×540 substitui TFT;
- toda a HMI passa a ser orientada ao Unit CardKB v1.1;
- CardKB usa `Wire1`, SDA GPIO16 e SCL GPIO15, endereço 0x5F;
- respostas abertas, cloze e aplicação passam a ser realmente digitadas no terminal;
- múltipla escolha e verdadeiro/falso continuam com correção automática;
- entrada de texto usa atualização parcial/debounce de e-paper;
- I2C 18/17 fica reservado ao RTC e ao futuro touch;
- PCF8563 passa a fornecer horário offline persistente;
- capability anuncia `keyboard=true`, `touch=false`, `typedRecall=true`, display e-paper 960×540;
- BLE continua removido; DirectSync permanece Wi-Fi SoftAP/HTTP;
- flash de 16 MB recebe dois slots OTA de 3 MB e LittleFS de ~9,94 MB;
- SD fica desabilitado nesta variante porque 16/15 são reutilizados pelo teclado.
