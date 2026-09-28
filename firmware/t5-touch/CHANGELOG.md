# Changelog — firmware/t5-touch

## 0.7.0-preview.4.2-touch

- prepara o primeiro ensaio OTA A/B real;
- adiciona ambiente `bench-ota-source` em generation 70402;
- adiciona ambiente `bench-ota-target` em generation 70403;
- mantem sleep desabilitado nos dois lados do ensaio;
- habilita OTA automatica apenas na imagem fonte;
- gera o alvo via `tools/build-ota-target.sh`;
- nao altera HMI, FSRS ou biblioteca SD-first.

## 0.7.0-preview.4.1.2-touch

- separa build de produto e builds de bancada;
- define `bench` como ambiente padrão;
- desabilita light/deep sleep e OTA automática na bancada;
- adiciona `bench-demo`;
- reduz upload de bancada para 460800;
- adiciona uploader que rejeita fallback para `/dev/ttyS0`;
- adiciona diagnóstico do perfil de build;
- avança `OTA_GENERATION` para `70402`.

## 0.7.0-preview.4.1.1-touch

- garante explicitamente `OtaService::begin()` no boot;
- garante verificacao do manifesto local depois da montagem do SD;
- adiciona `[ota-summary]` ao final de `setup()`;
- mantem `OTA_GENERATION=70401` para este hotfix via USB.

## 0.7.0-preview.4.1-touch

- corrige conflito entre a tabela hexadecimal da OTA e a macro `HEX` do Arduino;
- renomeia a tabela interna para `HEX_DIGITS`;
- define geração OTA `70401`;
- não altera o fluxo de verificação ou instalação OTA.

## 0.7.0-preview.4-touch

- adiciona `OtaService`;
- instala firmware no slot OTA inativo a partir do microSD;
- valida manifesto `mnemos.ota/v1`;
- exige modelo e protocolo compatíveis;
- usa geração monotônica para bloquear downgrade;
- valida tamanho e SHA-256 antes de gravar a flash;
- exige `apply=true`;
- bloqueia OTA com bateria detectada abaixo de 20%;
- move manifesto aplicado para `manifest.applied.json`;
- detecta e documenta disponibilidade real de rollback do bootloader;
- adiciona ferramenta de geração de bundle OTA;
- não altera HMI.


## 0.7.0-preview.3-touch

- microSD passa a ser armazenamento canônico das definições de cartões;
- cria `/mnemos/library/cards.ndjson`;
- RAM mantém catálogo leve de cards;
- pergunta/resposta/opções são hidratadas sob demanda;
- migra biblioteca LittleFS existente para o SD;
- importação atualiza a biblioteca canônica;
- exportação reconstrói JSON completo a partir do SD;
- LittleFS permanece com FSRS, sessão, reviews e fallback;
- anuncia `sdFirstLibrary=true` e `lazyCardContent=true`;
- não altera HMI, FSRS ou rede.

## 0.7.0-preview.2-touch

- adiciona `PowerService`;
- light sleep com wake por touch GPIO47 e botão GPIO21;
- deep sleep com wake por botão GPIO21 e timer de manutenção;
- deep sleep automático em bateria crítica;
- persiste sessão/FSRS e checkpoint do relógio antes do sleep;
- suspende/retoma Wi-Fi e microSD em light sleep;
- corrige `BoardConfig::USE_SD=true`;
- timezone passa a ser persistido em Preferences e usado pela agenda;
- anuncia `deepSleepTouchWake=false`;
- mantém a HMI congelada.

## 0.7.0-preview.1-touch

- congela a arquitetura atual da HMI touch-first;
- desativa `DEMO_INTERVALS` no padrão normal;
- desativa seed automático de mandarim em instalações novas;
- corrige capabilities do T5 Touch;
- torna scan/conexão/reconexão Wi-Fi cooperativos;
- torna NTP não bloqueante;
- unifica todos os cartões em revelar + autoavaliação;
- aceita CA HTTPS compilada ou em `/backend_ca.pem`;
- tenta recuperar cursores HTTP 410 a partir de zero;
- atualiza documentação e TODO de integração externa.

## 0.6.0-preview.6-touch

- consolida a HMI touch-first;
- retrato passa a ser a orientação inicial;
- adiciona layouts independentes retrato/paisagem;
- adiciona confirmação de interrupção de sessão;
- adiciona filtro de decks para composição de sessão;
- adiciona zonas nomeadas de touch e diagnóstico serial detalhado;
- adiciona debounce de 400 ms;
- adiciona Noto Sans CJK SC em 14/18/22 px;
- mantém pinyin tonal e Hanzi no mesmo renderer Unicode.


## 0.6.0-preview.4-touch

- Home redesenhada como agenda semanal;
- log serial associa coordenada touch a UiAction;
- adiciona botao de abortar sessao com retomada segura;
- aumenta biblioteca local para 128 cartoes;
- adiciona deck de treinamento com 100 caracteres de mandarim;
- adiciona subconjunto grafico CJK especifico para os 100 ideogramas.


## 0.6.0-preview.3-touch

- variante dedicada ao T5-4.7-S3 capacitive touch;
- GT911 substitui CardKB como entrada;
- RTC e GT911 compartilham GPIO18/17;
- GT911 sondado em 0x5D e 0x14;
- HMI convertida para áreas de toque;
- StudyEngine, FSRS, sincronização e bateria permanecem desacoplados do input.


## 0.6.0-preview.2

- substituição do scheduler próprio pelo FSRS determinístico compartilhado;
- geração do contrato compartilhado também para C++;
- replay do estado pedagógico a partir do histórico de reviews;
- suporte a `progress_resets` no replay e na sincronização;
- sincronização de `desired_retention`;
- pull incremental de reviews e eventos por `server_seq`;
- protocolo local atualizado para versão 4;
- alinhamento do aplicativo móvel ao protocolo local v4;
- credencial dedicada de terminal mantida separada do token da conta;
- nova HMI e-paper com menor carga visual e foco em recuperação ativa;
- remoção de indicadores positivos de relógio da interface normal;
- atualização da documentação e do checklist físico.

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
