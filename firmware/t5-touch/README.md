# Firmware Mnemos T5 Touch

Firmware do terminal de estudo para LILYGO T5-4.7-S3 com e-paper 960×540, GT911 por I²C e RTC PCF8563. A versão definida em `include/config.h` é `0.7.0-preview.4.2-touch`, geração OTA **70403** na build usual. Esta pasta é independente de `firmware/t5/` sem touch e de `firmware/cyd/`; não aplicar limites e procedimentos dessas variantes sem negociar capacidades. A plataforma inclui também clientes móvel e web e o backend; o terminal é uma superfície de estudo adicional.

## Estudo e capacidades

A HMI usa tentativa mental, revelação de resposta e autoavaliação. Todos os tipos (`open_recall`, `cloze`, `application`, `multiple_choice`, `true_false`) usam “Não recuperei / Recuperei” e, quando recuperado, “Difícil / Normal / Fácil”. Alternativas podem ser exibidas, mas um toque na opção não avalia automaticamente a recuperação. Não há digitação (`typedRecall=false`, `keyboard=false`). `StudyEngine` mantém a sessão e aplica o agendamento FSRS localmente; `Config::DEMO_INTERVALS=false` por padrão. O deck de mandarim é importável, mas não semeado automaticamente em instalação nova.

`GET /v4/info` anuncia `protocol=4`, cinco tipos, formato `plain`, quatro alternativas no máximo, catálogo de até **128 cartões** e payload local de até **120000 bytes**. As capacidades do firmware não equivalem à capacidade de autoria dos produtores de snapshot: móvel e backend atualmente enviam `open_recall` para todo cartão. Veja [a integração](../../docs/integration/t5-touch.md#conteúdo-e-tipos-de-cartão) e [as diretrizes HMI](../../docs/ux/HMI_T5_TOUCH_GUIDELINES_v0.1.md).

## Persistência

Com microSD montado, `/mnemos/library/cards.ndjson` é a fonte das definições completas. `cards[]` na RAM é um catálogo leve, e o conteúdo do cartão ativo é hidratado sob demanda. Na primeira montagem, uma biblioteca completa de LittleFS pode ser migrada para o arquivo canônico; importações atualizam o NDJSON e a exportação reconstrói `/mnemos/export/library.json`. `MAX_DEVICE_CARDS=128` limita o catálogo ativo, não a capacidade física do cartão microSD. Sem microSD, o firmware recorre à biblioteca local de LittleFS.

LittleFS retém estados FSRS, sessão retomável, histórico e outbox de revisões e cursores de sincronização. Perfis Wi-Fi e credencial de backend ficam em `Preferences`/NVS. A definição de um cartão pode mudar sem apagar seu histórico: os estados são associados por ID. O payload gravado na outbox usa `mnemos.review/v2`, `reviewedAt` em segundos e `source=terminal`. Esses valores não satisfazem o validador atual da API remota; não contar um build bem-sucedido como prova de sincronização ponta a ponta. Consulte [o diagnóstico de payload](../../docs/integration/t5-touch.md#incompatibilidade-de-payload-bloqueador).

## Rede, tempo e interfaces

Scans Wi-Fi, associação, reconexão com backoff e observação de NTP não bloqueiam a HMI. RTC PCF8563 e GT911 compartilham SDA GPIO18/SCL GPIO17; o offset de fuso e horário de verão é persistido, com constantes de `Config` como fallback. A hora confiável é necessária para agendar eventos, mas boot e interface não aguardam NTP. O [mapa de pinos](docs/WIRING.md) registra também touch IRQ, bateria e botão de wake.

Para configurar rede ou sincronizar pelo móvel, `LocalLinkService` usa a LAN já conectada ou abre SoftAP como fallback. O QR v4 fornece host, modo, token e credenciais efêmeras; o HTTP local exige `?token=` em todas as rotas. `provision` aceita `mnemos.provision/v2`; `sync` aceita snapshot `mnemos.sync/v2`, exporta revisões e confirma a outbox. O T5 Touch anuncia `bleSync=false`. Detalhes de rotas e erros estão no [Device Protocol v4](../../spec/protocol/device-protocol-v4.md).

`BackendSyncService` usa token exclusivo de terminal para `/v1/terminal/*`. Primeiro tenta enviar revisões pendentes, obtém snapshot, puxa deltas de revisões, resets e configurações, e reporta status. A outbox direta só é limpa após 2xx; o envio atual recebe 422 por incompatibilidade de contrato. Para HTTPS, configure `Config::BACKEND_ROOT_CA` ou `/backend_ca.pem` no LittleFS; sem CA, HTTPS é recusado. HTTP é apropriado apenas para laboratório/LAN controlada. O terminal físico precisa alcançar o endereço da API; `10.0.2.2` é um alias do emulador Android, não do ESP32.

## Energia e atualização

Na build de produto, após dois minutos de ociosidade, sem operação local ou de rede em andamento, há light sleep; touch GPIO47 e botão GPIO21 podem acordar. Após vinte minutos, ou bateria detectada em 5%, há deep sleep. GPIO47 **não** é RTC IO nessa placa e não acorda o deep sleep; usar GPIO21 ou wake periódico de seis horas. Biblioteca, estados e sessão são persistidos antes de dormir, e microSD e rede são retomados conforme a política. Os limiares de bateria desta placa ainda exigem verificação física.

O OTA local A/B lê `/mnemos/update/manifest.json` e `/mnemos/update/firmware.bin` do microSD. O manifesto `mnemos.ota/v1` precisa de `apply=true`, modelo/protocolo corretos, geração maior que a instalada, tamanho dentro do slot de **3 MiB**, magic byte e SHA-256; bateria detectada abaixo de 20% impede instalação. Após sucesso, o manifesto vira `manifest.applied.json` e o aparelho reinicia no outro slot. A existência de app0/app1 não garante rollback automático: isso depende do bootloader realmente configurado com `CONFIG_BOOTLOADER_APP_ROLLBACK_ENABLE` e deve ser conferido na placa. A recuperação por USB pode ser necessária se a imagem não inicializar.

Para gerar um pacote a partir de uma **build futura**, escolha versão e geração maiores que os valores de `include/config.h`:

```bash
python3 tools/make_ota_bundle.py \
  .pio/build/lilygo-t5-47-s3-touch/firmware.bin \
  --version 0.7.0-preview.4.3-touch \
  --generation 70404
```

Copie os dois arquivos gerados para `/mnemos/update/` no microSD. Para o ensaio de origem/target das gerações 70402→70403, consulte [o checklist](docs/TEST_CHECKLIST.md) e os scripts `tools/upload-ota-source.sh` e `tools/build-ota-target.sh`; não use o valor 70402 para atualizar uma build usual já em 70403.

## Builds e verificação

`platformio.ini` define `lilygo-t5-47-s3-touch-bench` como ambiente padrão. Ele mantém intervalos reais e desliga sleep e OTA automática para preservar depuração USB. O perfil `-bench-demo` comprime intervalos; o perfil `lilygo-t5-47-s3-touch` habilita políticas de produto. Escolha o ambiente explicitamente para ensaios de energia/OTA:

```bash
cd firmware/t5-touch
pio run
pio run -e lilygo-t5-47-s3-touch
./tools/upload-bench.sh
./tools/monitor-bench.sh
```

Não subir uma imagem de produto por acidente ao testar bancada. Leia [perfis e upload](docs/BENCH_BUILDS.md), [checklist funcional](docs/TEST_CHECKLIST.md) e [checklist HMI](docs/HMI_TEST_CHECKLIST.md). As caixas desses roteiros registram testes a executar, não resultados já comprovados. A validação da integração com app/backend deve seguir os [critérios de aceite](../../docs/integration/t5-touch.md#critérios-de-aceite-para-integração), em ambas as builds.
