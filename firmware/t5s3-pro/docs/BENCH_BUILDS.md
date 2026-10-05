# Builds de bancada — T5S3 Pro H752-01

O firmware tem perfis separados para produto e desenvolvimento, todos em
`platformio.ini`. O ambiente padrão (`pio run`) é a bancada.

| Ambiente | Uso | Sleep | OTA automática | Geração OTA |
|---|---|---|---|---|
| `t5s3-pro` | produto | light sleep e política de deep sleep | ligada | 70403 |
| `t5s3-pro-bench` | desenvolvimento (padrão) | desligado | desligada | 70403 |
| `t5s3-pro-bench-demo` | bancada com intervalos de agenda e FSRS acelerados | desligado | desligada | 70403 |
| `t5s3-pro-bench-ota-source` | imagem fonte do ensaio OTA A/B | desligado | ligada | 70402 |
| `t5s3-pro-bench-ota-target` | imagem alvo do ensaio OTA A/B | desligado | desligada | 70403 |

Todos gravam a 460800 baud. O hard-off pelo menu e o auto-off por
inatividade (10 min, só em bateria) valem também na bancada. Light sleep e o
hard-off por bateria crítica só agem no produto; testes reais de consumo e
de sleep devem usar o ambiente `t5s3-pro`.

## Ferramentas

```bash
./tools/build-bench.sh [bench|demo|product]
./tools/upload-bench.sh [bench|demo|product]
./tools/monitor-bench.sh
```

O uploader aceita somente uma porta `/dev/ttyACM*` identificada como
Espressif e aborta se ela não existir, o que impede o fallback acidental para
`/dev/ttyS0`. Com mais de um ESP32 conectado:

```bash
MNEMOS_UPLOAD_PORT=/dev/ttyACM0 ./tools/upload-bench.sh
```

Versão, geração OTA, modelo e protocolo de cada ambiente vêm de
`include/config.h`:

```bash
python3 tools/firmware_meta.py --env t5s3-pro-bench-ota-target
```

## Ensaio OTA A/B

1. `./tools/upload-ota-source.sh` grava por USB a imagem fonte (geração
   70402, OTA automática ligada).
2. `./tools/build-ota-target.sh` compila o alvo (geração 70403) e gera
   `firmware.bin` + `manifest.json`. A saída padrão é
   `/tmp/mnemos-ota-<geração>`; use `MNEMOS_OTA_OUT=<dir>` para mudar.
3. Copie os dois arquivos para `/mnemos/update/` no microSD, recoloque o
   cartão e reinicie a placa.

Para empacotar qualquer outro binário:

```bash
python3 tools/make_ota_bundle.py .pio/build/t5s3-pro/firmware.bin --env t5s3-pro
```

O manifesto é rejeitado pelo terminal se o modelo não for
`LILYGO-T5S3-PRO-H752-01`, se a geração não for maior que a instalada ou se o
SHA-256 não conferir.

## Testes

```bash
pio test -e native
```

Roda no PC os testes de FSRS e da política de bateria. Os ambientes do
ESP32 ignoram os testes (`test_ignore = *`), então `pio test` nunca grava
nada na placa.

## Diagnóstico

Bancada:

```text
[build] flavor=bench bench=1 demo=0 light-sleep=0 deep-sleep=0 ota-auto=0
```

Produto:

```text
[build] flavor=product bench=0 demo=0 light-sleep=1 deep-sleep=1 ota-auto=1
```

A causa do último reset aparece em `[power] boot reset=...` (`POWERON`, `SW`,
`PANIC`, `TASK_WDT`, `BROWNOUT`...).

O projeto isolado `tools/diagnostics/boot-wake/` testa o wake de deep sleep
pelo BOOT/GPIO0, fora do firmware Mnemos.
