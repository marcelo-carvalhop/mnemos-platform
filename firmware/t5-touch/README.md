# Mnemos T5 — v0.6.0-preview.2

Firmware de referência do terminal físico Mnemos para o LILYGO T5-4.7-S3, com display e-paper 960×540 sem touchscreen e Unit CardKB v1.1 como dispositivo principal de entrada.

Esta versão consolida o T5 como cliente completo da plataforma Mnemos. Web, aplicativo móvel e terminal físico seguem a mesma metodologia de estudo e o mesmo modelo determinístico de agendamento. O diferencial do T5 não é possuir uma metodologia separada, mas oferecer uma superfície dedicada de estudo, com baixa distração, e-paper e interação física simples.

## Hardware

Configuração atualmente validada:

- LILYGO T5-4.7-S3 com ESP32-S3;
- display e-paper 960×540;
- Unit CardKB v1.1 em I2C, endereço `0x5F`;
- CardKB: `SDA = GPIO16`, `SCL = GPIO15`;
- RTC PCF8563: `SDA = GPIO18`, `SCL = GPIO17`;
- futuro touch reservado ao barramento do sistema, ainda desabilitado;
- SD desabilitado porque GPIO16/15 são utilizados pelo teclado;
- monitoramento de bateria integrado ao firmware.

O hardware utilizado apresentou inversão física de SDA/SCL no barramento associado ao RTC em relação às primeiras hipóteses de ligação. A configuração acima corresponde à ligação validada em bancada e deve ser considerada a referência do projeto.

## Filosofia de interação

O terminal não simula touchscreen.

A entrada é convertida para `UiAction`, mantendo separação entre dispositivo físico e lógica de aplicação. O CardKB é atualmente a implementação principal; uma futura versão com touchscreen poderá produzir as mesmas ações sem alterar o `StudyEngine`.

A HMI foi projetada para privilegiar:

- recuperação ativa;
- baixa carga visual;
- ausência de elementos técnicos desnecessários;
- separação entre pergunta e resposta;
- foco na tarefa atual;
- indicação de problemas apenas quando requerem atenção.

O estado normal do relógio não é exibido. A interface mostra aviso somente quando o horário não é considerado confiável.

## Metodologia e scheduler

O T5 utiliza o mesmo contrato pedagógico compartilhado pelos demais clientes.

O agendamento é baseado em FSRS determinístico com:

- vetor compartilhado de 21 pesos;
- passos de aprendizagem definidos pelo contrato;
- passos de reaprendizagem definidos pelo contrato;
- intervalo máximo compartilhado;
- fuzz desabilitado;
- retenção desejada padrão definida em `shared/contract.yaml`.

O firmware não mantém um algoritmo D/S/R próprio.

O histórico de eventos é a fonte canônica do estado pedagógico. O estado FSRS persistido é tratado como dado derivado e pode ser reconstruído por replay.

Para cada cartão, as revisões são ordenadas deterministicamente por:

`(reviewedAtMs, id)`

O último `progress_reset` funciona como corte temporal: revisões anteriores ou no mesmo instante do reset permanecem no histórico, mas não participam do estado FSRS reconstruído após o reset.

A configuração `desired_retention` pode ser sincronizada pela conta. Quando ausente, o terminal utiliza o valor padrão do contrato compartilhado.

## Histórico e persistência

Arquivos principais no LittleFS:

- `review_history.ndjson`: histórico local e remoto de revisões;
- `review_outbox.ndjson`: revisões originadas no T5 que ainda precisam ser enviadas;
- `progress_resets.ndjson`: eventos de reinicialização de progresso;
- `state.json`: cache derivado do estado dos cartões;
- `sync_meta.json`: cursores e parâmetros sincronizados;
- arquivos de sessão para retomada de estudo interrompido.

Reviews recebidas de outros clientes entram no histórico, mas nunca no outbox.

Isso evita ciclos de sincronização do tipo:

Web → backend → T5 → backend.

## Sincronização multicliente

O T5 participa do mesmo histórico de estudo utilizado pelo Web e pelo aplicativo móvel.

O fluxo de backend utiliza:

- snapshot de biblioteca;
- push de reviews originadas no terminal;
- pull incremental de reviews;
- pull incremental de `progress_resets`;
- pull de configurações pedagógicas;
- cursores baseados em `server_seq`.

O relógio do dispositivo não é utilizado como watermark de sincronização.

Os cursores são persistidos separadamente para cada classe de dado.

## Protocolo local

O protocolo local atual do terminal é versão 4.

O T5 pode criar um ponto de acesso temporário para:

- provisionamento inicial;
- sincronização direta com o aplicativo móvel.

O QR utiliza o formato:

`mnemos://local?v=4&mode=...`

Principais rotas locais:

- `/v4/info`
- `/v4/time`
- `/v4/provision`
- `/v4/complete`
- `/v4/network/status`
- `/v4/sync/library`
- `/v4/sync/reviews`
- `/v4/sync/reviews/ack`

O aplicativo móvel mantém compatibilidade com versões anteriores do protocolo.

## Credenciais

O terminal não recebe o token normal da conta do usuário.

Durante o provisionamento, o backend cria uma credencial própria do dispositivo, restrita e revogável independentemente.

Essa credencial é armazenada pelo terminal e utilizada nas sincronizações posteriores.

## Relógio

O `TimeService` utiliza, em ordem de preferência:

1. NTP quando disponível;
2. RTC PCF8563 em operação offline;
3. fallback persistido quando nenhuma fonte confiável estiver disponível.

Quando ocorre sincronização válida por NTP ou por dispositivo externo, o RTC é atualizado.

A HMI não apresenta indicadores positivos para o estado do relógio. Apenas um horário não confiável produz aviso visual.

Durante os testes da preview.2 foi observado que o RTC de bancada precisava de uma correção inicial de horário. A validação temporal definitiva deve ser executada antes dos testes finais de agenda.

## HMI

A interface v0.6 utiliza `MNEMOS` como assinatura constante e uma hierarquia visual simples adequada ao e-paper.

Telas principais:

- Estudo;
- Menu;
- Agenda;
- Sincronização;
- Conexão;
- Configuração/sincronização com celular;
- Pergunta;
- Conferência de resposta;
- Feedback objetivo;
- Esforço de recuperação;
- Resumo da sessão.

A resposta de referência nunca é apresentada juntamente com a pergunta antes da tentativa do usuário.

## Entrada pelo CardKB

Atalhos principais:

| Tela | Ação |
|---|---|
| Home | `Enter` estudar/praticar/continuar |
| Home | `M` abrir menu |
| Menu | `1` sincronização |
| Menu | `2` agenda |
| Menu | `3` conexão |
| Voltar | `Backspace` |
| Múltipla escolha | `1`–`4` |
| Verdadeiro/falso | `1`–`2` |
| Autoavaliação | `1` não recuperei, `2` recuperei |
| Esforço | `1` difícil, `2` normal, `3` fácil |
| Feedback | `Enter` continuar |

O CardKB é lido continuamente. Atualizações de texto são agrupadas para evitar refresh completo do e-paper a cada tecla.

## Build

```bash
cd firmware/t5
pio run
