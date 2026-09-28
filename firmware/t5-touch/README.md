# Mnemos T5 Touch — firmware 0.7

Firmware do terminal físico Mnemos para o LILYGO T5-4.7-S3 com
touchscreen capacitivo. O T5 Touch é a plataforma intermediária antes da
migração prevista para o LILYGO T5S3 Pro 4,7".

O firmware do T5 sem touch permanece independente em `firmware/t5`.

## HMI

A arquitetura HMI touch-first está congelada funcionalmente na série 0.7.
Pequenas correções visuais continuam permitidas quando forem observadas no
hardware.

## Contrato pedagógico

O T5 Touch é orientado a recuperação ativa e memorização. Nenhum tipo de
cartão exige digitação.

Todos os tipos (`open_recall`, `cloze`, `application`, `multiple_choice` e
`true_false`) seguem:

```text
enunciado
  -> tentativa mental
  -> Revelar resposta
  -> Não recuperei / Recuperei
  -> se recuperou: Difícil / Normal / Fácil
  -> FSRS
```

Cartões objetivos podem exibir alternativas, mas tocar numa alternativa não
é usado para avaliar automaticamente o usuário.

## Capabilities normativas

```text
primary=touch
touch=true
keyboard=false
typedRecall=false
microSD=true
bleSync=false
display=epaper-960x540
```

## Configuração normal e bancada

`DEMO_INTERVALS=false` é o padrão. Ensaios comprimidos precisam ser ativados
deliberadamente.

O deck de mandarim não é mais semeado automaticamente em instalações novas;
continua disponível como conteúdo importável.

## Rede

Scan e conexão iniciados pela HMI são assíncronos. Reconexão automática
também não espera em loop bloqueante.

Quando já existe Wi-Fi, LocalLink usa a LAN corrente e não tenta STA->APSTA.
SoftAP fica como fallback offline.

## Tempo

RTC PCF8563 e GT911 compartilham SDA18/SCL17. NTP é iniciado e observado de
forma assíncrona; boot/HMI não aguardam resposta de servidor.

## HTTPS

O firmware nunca usa TLS inseguro. A CA pode ser compilada em
`Config::BACKEND_ROOT_CA` ou armazenada em LittleFS como `/backend_ca.pem`.

Sem CA, HTTPS é rejeitado. HTTP permanece útil somente para laboratório/LAN.

## microSD

Pinos onboard:

- MISO GPIO16
- MOSI GPIO15
- SCK GPIO11
- CS GPIO42

A migração para biblioteca SD-first será o próximo incremento funcional,
separada da estabilização da rede.

## Build

```bash
cd firmware/t5-touch
pio run
pio run --target upload
pio device monitor -b 115200
```

## Integração externa

Requisitos para App/Web/Backend ficam em
`docs/integration/T5_TOUCH_EXTERNAL_TODO.md`. O firmware não modifica código
dessas áreas.


## Gerenciamento de energia

A `0.7.0-preview.2` introduz política em dois níveis.

Após 2 minutos sem interação, quando não há LocalLink nem operação de rede em
andamento, o terminal entra em **light sleep**. Touch GPIO47 e botão GPIO21
podem acordá-lo.

Após 20 minutos de inatividade, ou quando uma bateria detectada chega a 5%,
o terminal entra em **deep sleep**. Na placa T5-4.7-S3 atual o GT911 está no
GPIO47, que não é RTC IO; portanto o touch não acorda deep sleep sem alteração
física. O wake suportado é o botão GPIO21, além de um timer de manutenção a
cada 6 horas.

Antes de dormir, FSRS/sessão e relógio são persistidos, microSD é desmontado e
Wi-Fi é desligado sem alterar a preferência de rede do usuário. Após light
sleep esses serviços são retomados.

Os limiares de 15% (bateria baixa) e 5% (crítica) são provisórios para a T5
atual e devem ser reavaliados na futura T5S3 Pro.

## Timezone

`TimeService` passa a persistir `tzOffset` e `dstOffset` em Preferences.
`Config::GMT_OFFSET_SECONDS` e `DAYLIGHT_OFFSET_SECONDS` continuam como
fallback. A agenda e o cálculo do dia acadêmico usam o offset efetivo.

O offset UTC aceito vai de UTC-12 a UTC+14.


## Biblioteca SD-first

A `0.7.0-preview.3` transforma o microSD na fonte canônica das definições de
cartões quando ele está disponível.

A biblioteca normalizada fica em:

```text
/mnemos/library/cards.ndjson
```

Cada linha contém um cartão completo. Em RAM, `cards[]` funciona como catálogo
leve: mantém identificadores, deck, tipo, formato e revisão, mas libera
`question`, `answer` e `options`. O conteúdo completo é hidratado do SD somente
quando o cartão atual precisa ser desenhado.

LittleFS continua responsável por estados FSRS, sessão retomável, histórico e
outbox de reviews, cursores de sync e fallback de biblioteca.

Na primeira inicialização com SD, uma biblioteca completa existente em
LittleFS é migrada para o arquivo canônico e o catálogo é compactado em RAM.

Importações em `/mnemos/decks` atualizam diretamente a biblioteca canônica.
Exportação reconstrói `/mnemos/export/library.json` a partir do NDJSON.

`MAX_DEVICE_CARDS=128` passa a representar a capacidade do catálogo ativo, não
a capacidade física do microSD.



## OTA local verificada

A `0.7.0-preview.4` introduz instalação A/B pelo microSD, usando `app0`,
`app1` e `otadata` já presentes na tabela de partições.

O pacote de atualização fica em:

```text
/mnemos/update/manifest.json
/mnemos/update/firmware.bin
```

O manifesto usa `mnemos.ota/v1` e é validado antes de qualquer gravação:
modelo, protocolo, geração monotônica, tamanho, magic byte de imagem ESP e
SHA-256. A imagem só é entregue a `Update` depois da verificação completa.

`generation` é o mecanismo anti-downgrade do firmware. A build atual usa
`70401`; um pacote OTA precisa ter geração maior.

A atualização é recusada quando uma bateria detectada está abaixo de 20%.
O manifesto também precisa conter `apply=true`, evitando instalação apenas por
copiar acidentalmente um arquivo para o cartão.

Após sucesso, `manifest.json` é renomeado para `manifest.applied.json` e o
ESP32 reinicia no outro slot OTA.

A tabela atual fornece dois slots de 3 MiB. Imagens maiores são rejeitadas.

### Rollback

A infraestrutura usa A/B e consulta o estado OTA do ESP-IDF. Quando
`CONFIG_BOOTLOADER_APP_ROLLBACK_ENABLE` estiver realmente habilitado no
bootloader, a aplicação confirma a nova imagem depois de concluir o boot.

No Arduino-ESP32 2.0.17 usado atualmente, rollback automático do bootloader
não deve ser presumido. A/B reduz o risco de sobrescrever a imagem em execução,
mas uma imagem que não inicialize pode ainda exigir recuperação por USB.

### Geração do pacote

Depois de compilar uma versão futura:

```bash
python3 tools/make_ota_bundle.py \
  .pio/build/lilygo-t5-47-s3-touch/firmware.bin \
  --version 0.7.0-preview.4.2-touch \
  --generation 70402
```

Copiar `firmware.bin` e `manifest.json` gerados para `/mnemos/update/` no SD.



## Builds de bancada

O ambiente padrão de desenvolvimento é `lilygo-t5-47-s3-touch-bench`, que mantém light/deep sleep e OTA automática desabilitados. Consulte `docs/BENCH_BUILDS.md`.


## Primeiro teste OTA A/B

A serie `0.7.0-preview.4.2` adiciona dois ambientes temporarios de bancada:

- `lilygo-t5-47-s3-touch-bench-ota-source`: generation 70402, sleep OFF, OTA automatica ON;
- `lilygo-t5-47-s3-touch-bench-ota-target`: generation 70403, sleep OFF, OTA automatica OFF.

O primeiro e gravado por USB apenas para fornecer uma origem segura ao ensaio.
O segundo e compilado em bundle e instalado pelo microSD no slot OTA inativo.

Use:

```bash
./tools/upload-ota-source.sh
./tools/build-ota-target.sh
```
