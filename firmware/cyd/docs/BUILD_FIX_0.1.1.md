# Correções de compilação — v0.1.1

Esta revisão corrige dois erros observados com o ambiente PlatformIO `espressif32 7.0.1` e a biblioteca `XPT2046_Touchscreen` instalada pelo registro:

1. O touch passa a usar o objeto global `SPI` (VSPI) com a pinagem própria do ESP32-2432S028 e chama `touch.begin()` sem argumentos, compatível com a versão instalada.
2. A estrutura interna `Button` recebeu um construtor explícito compatível com o padrão C++11 usado pelo toolchain Xtensa.

O TFT continua no barramento HSPI por meio de `USE_HSPI_PORT=1`, enquanto o touchscreen permanece no VSPI.
