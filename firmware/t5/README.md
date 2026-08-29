# Mnemos T5 — v0.6.0-preview.1

Firmware de referência do Mnemos para **LILYGO T5-4.7-S3 sem touch**, ESP32-S3-WROOM-1-N16R8, display e-paper 960×540 e **Unit CardKB v1.1**.

O CYD permanece como protótipo de validação da v0.5. A partir desta preview, o T5 é o alvo principal do produto físico.

## Hardware desta preview

- LILYGO T5-4.7-S3 com ESP32-S3 N16R8, 16 MB flash e 8 MB OPI PSRAM.
- Display e-paper 960×540, sem touchscreen.
- Unit CardKB v1.1 em I2C `0x5F`.
- CardKB: `SDA = GPIO16`, `SCL = GPIO15`.
- RTC PCF8563: `SDA = GPIO18`, `SCL = GPIO17`.
- Touch futuro: mesmo barramento 18/17, `TOUCH_INT = GPIO47`; desabilitado nesta build.
- SD desabilitado: GPIO16/15 deixam de ser usados pelo barramento SD e passam ao teclado.

## Ligação do CardKB

Sinais definidos pelo firmware:

| CardKB | T5 |
|---|---|
| SDA | GPIO16 |
| SCL | GPIO15 |
| GND | GND |
| VCC | ver nota de alimentação abaixo |

O CardKB v1.1 é especificado pelo fabricante para 5 V. O firmware só pressupõe os sinais GPIO16/15. O conector auxiliar do T5 possui alimentação controlada junto ao rail do e-paper; por isso esta preview mantém esse rail ligado durante o uso. Para bancada, valide a tensão real do pino V antes de alimentar o CardKB por ele. Para uma integração elétrica definitiva, a alimentação do teclado deve ser especificada separadamente e não inferida apenas do rótulo `V` do conector.

## Filosofia de entrada

O terminal não simula touch. Toda interação é feita pelo CardKB. O código usa `UiAction` como contrato lógico entre HMI e entrada; uma futura versão touch poderá gerar as mesmas ações sem modificar o `StudyEngine`.

Atalhos principais:

| Tela | Teclas |
|---|---|
| Home | `Enter` estudar/praticar/continuar, `M` menu |
| Menu | `1` Sincronizar, `2` Agenda, `3` Conexão, `Backspace` voltar |
| Resposta aberta/cloze/aplicação | digitar texto, `Backspace` apagar, `Enter` confirmar |
| Múltipla escolha | `1`–`4` |
| Verdadeiro/falso | `1`–`2` |
| Confiança | `1` baixa, `2` média, `3` alta |
| Autoavaliação | `1` errei, `2` acertei |
| Esforço | `1` difícil, `2` normal, `3` fácil |
| Feedback objetivo | `Enter` continuar |
| Resumo | `1` estudar novamente, `Enter` concluir |

## E-paper e digitação

O texto digitado não provoca uma atualização completa a cada tecla. O CardKB é lido continuamente e a região de resposta é atualizada somente após uma pequena pausa na digitação (`EINK_TEXT_REFRESH_IDLE_MS`). Isso evita que a latência do e-paper bloqueie a captura do teclado.

## Relógio

O `TimeService` desta versão usa três níveis:

1. NTP quando existe Wi-Fi;
2. PCF8563 quando o terminal está offline;
3. fallback por Preferences/horário de compilação somente se o RTC estiver inválido.

Quando o relógio é sincronizado por NTP ou pelo celular, o PCF8563 também é atualizado. O objetivo é preservar `dueAt` e a agenda após desligamentos reais do terminal.

## Flash

A placa possui 16 MB. O layout Mnemos reserva:

- `app0`: 3 MB;
- `app1`: 3 MB;
- LittleFS: aproximadamente 9,94 MB;
- NVS + OTA metadata.

Isso mantém OTA A/B e oferece espaço muito maior para biblioteca, histórico e futuros recursos de conteúdo.

## Build

```bash
cd firmware/t5
pio run
```

Upload:

```bash
pio run -t upload
```

Monitor:

```bash
pio device monitor
```

Se a porta USB não aparecer, coloque o T5 em modo de gravação usando BOOT(IO0) + RST conforme procedimento do fabricante.

## Primeiro teste físico

A sequência mínima esperada é:

1. boot do e-paper;
2. log `[cardkb] ... online`;
3. Home Mnemos;
4. `Enter` inicia estudo;
5. em cartão aberto, texto digitado aparece após pequena pausa;
6. `Enter` leva à confiança;
7. resposta de referência é mostrada depois da confiança;
8. `1/2` registra erro/acerto;
9. Home/Agenda mostram somente a próxima revisão agregada.

## Limitações conhecidas

- touch deliberadamente desabilitado;
- SD deliberadamente desabilitado porque GPIO16/15 são usados pelo CardKB;
- política definitiva de deep sleep/energia ainda será calibrada no hardware real;
- nível/tensão de alimentação definitivo do CardKB precisa ser validado na montagem física;
- imagens/image occlusion ainda não fazem parte da capability do terminal;
- `DEMO_INTERVALS=true` continua habilitado para testes de bancada.
