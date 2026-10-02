# Builds de bancada — T5-4.7-S3 Touch

A partir da série `0.7.0-preview.4.1.2`, o firmware possui perfis separados
para produto e desenvolvimento.

## Produto

`lilygo-t5-47-s3-touch`

- light sleep habilitado;
- deep sleep habilitado;
- OTA local automática habilitada;
- intervalos pedagógicos reais;
- upload em 921600.

```bash
pio run -e lilygo-t5-47-s3-touch
```

## Bancada

`lilygo-t5-47-s3-touch-bench`

- light sleep desabilitado;
- deep sleep desabilitado;
- OTA local automática desabilitada;
- intervalos pedagógicos reais;
- USB CDC/JTAG permanece disponível enquanto o firmware executa;
- upload em 460800.

Este é o `default_envs`; portanto `pio run` compila a bancada.

## Bancada demo

`lilygo-t5-47-s3-touch-bench-demo` mantém as proteções da bancada e ativa
`DEMO_INTERVALS=true` para testes rápidos de agenda e FSRS.

## Ferramentas

```bash
./tools/build-bench.sh bench
./tools/build-bench.sh demo
./tools/build-bench.sh product
./tools/upload-bench.sh
./tools/monitor-bench.sh
```

O uploader aceita somente uma porta `/dev/ttyACM*` identificada como Espressif
e aborta se ela não existir. Isso impede o fallback acidental para
`/dev/ttyS0`.

Se houver mais de um ESP32 conectado:

```bash
MNEMOS_UPLOAD_PORT=/dev/ttyACM0 ./tools/upload-bench.sh
```

## Diagnóstico

Bancada:

```text
[build] flavor=bench bench=1 demo=0 light-sleep=0 deep-sleep=0 ota-auto=0
```

Produto:

```text
[build] flavor=product bench=0 demo=0 light-sleep=1 deep-sleep=1 ota-auto=1
```

Testes reais de consumo, wake, light sleep e deep sleep devem ser feitos na
build de produto, não na build de bancada.
