# T5S3 Pro BOOT wake diagnostic

Teste mínimo do BOOT/GPIO0 como fonte de wake de deep sleep no H752-01.

Ferramenta de investigação de hardware, fora do firmware Mnemos. O produto não
usa o BOOT como botão de energia: o desligamento é o hard-off do BQ25896 e o
religamento é feito pelo PWR (`/QON`). Mantenha este projeto apenas para
reproduzir o comportamento de wake por GPIO0 isoladamente.

O projeto usa `espressif32@6.5.0`, o mesmo ambiente base do firmware Mnemos,
e configura `esp_sleep_enable_ext0_wakeup(GPIO_NUM_0, 0)`, como o firmware
oficial da LilyGO.

## Linux

```bash
cd firmware/t5s3-pro/tools/diagnostics/boot-wake
pio run -t upload
pio device monitor -b 115200
```

Ao iniciar, aguarde o dispositivo entrar em deep sleep. Em seguida pressione
e solte apenas BOOT. Não pressione RST.

Resultado esperado:

```text
PASS: o ESP32-S3 acordou do deep sleep pelo BOOT/GPIO0.
```

Se nada acontecer ao pressionar BOOT e somente RST fizer o dispositivo voltar,
o wake por GPIO0 não ocorreu e o problema foi reproduzido fora do Mnemos.

Depois do teste, grave novamente o firmware Mnemos.
