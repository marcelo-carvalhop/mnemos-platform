# Mnemos T5S3 Pro — pacote de migração completa

Este pacote gera `firmware/t5s3-pro` a partir da implementação funcional existente em `firmware/t5-touch`, preservando as bibliotecas locais `lib/epdiy` e `lib/BQ27220` que já foram validadas no H752-01.

O instalador não executa operações Git remotas.

## Uso

```bash
unzip mnemos-t5s3-pro-package.zip
cd mnemos-t5s3-pro-package
chmod +x install.sh
./install.sh /caminho/para/mnemos-platform
```

Depois:

```bash
cd firmware/t5s3-pro
pio run -e t5s3-pro-bench -t clean
pio run -e t5s3-pro-bench
```

Somente depois de um build bem-sucedido:

```bash
pio run -e t5s3-pro-bench -t upload
pio device monitor -b 115200
```

A HMI fica permanentemente em retrato lógico 540×960.
