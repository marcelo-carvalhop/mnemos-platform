# Refresh do ED047TC1 (T5S3 Pro H752-01)

Motor de refresh anti-ghosting do `T5Display`. Código em
`src/t5_display.cpp` (política e acionamento) e
`src/epd_waveform_builder.cpp` (geração de waveform). Parâmetros em
`include/config.h`, bloco `EPD_*`.

## Causa do fantasma

1. **Pixels escuros nunca piscavam.** O GC16 embutido do epdiy não aciona um
   pixel preto que continua preto (0→0 = nada). Os botões são blocos pretos e
   cinza na mesma área em todas as telas; o texto branco de um rótulo vira
   fundo preto "novo" ao lado de fundo preto "antigo", e os dois não ficam
   iguais. Os restos de rótulos se acumulam até a próxima limpeza profunda.
2. **Flash só na grade alterada.** `epd_hl_update_screen` só aciona as
   linhas × colunas com diferença; o resto do painel nunca é renovado.
3. **Tempos de fase ignorados.** No ESP32-S3 o epdiy usa o periférico LCD,
   que não lê `phase_times`: todo quadro dura o mesmo. A energia de cada
   transição depende só do número de quadros × período de quadro.

### O que deu errado na v2

A v2 forçou o clock do LCD em 10 MHz (quadro de ~14 ms) e aplicava 26
quadros por excursão. Mas o epdiy, no Arduino, já roda num clock reduzido
(quadro de ~27 ms): os 15 quadros do GC16 original davam ~410 ms por
excursão, mais do que os ~360 ms da v2. Além disso a v2 não piscava pixels
escuros que continuavam escuros e reduziu a limpeza profunda de 5 em 5
para 20 em 20 telas. Resultado: restos de rótulos empilhados nos botões.

## O que a v3 faz

| Recurso | Como |
|---|---|
| Troca de tela pisca **todo** pixel | Cada pixel vai ao preto e ao branco, com sobre-acionamento X em cada extremo, e só então ao destino — inclusive o fundo preto dos botões. |
| Energia nunca abaixo da anterior | Clock padrão do epdiy (o mesmo do firmware anterior). N = `EPD_SATURATION_DRIVE_MS` ÷ período de quadro **medido**, com piso de 15 quadros (o GC16 original). |
| Temperatura | Termistor do TPS65185 (validado contra o gauge), senão BQ27220 (lido pelo próprio display no I2C, registrador `0x06`), senão 25 °C. Abaixo de 20 °C aumenta N e X (até 3×); calor nunca reduz. |
| Balanço DC exato | Impulso líquido de f→t = Φ(t) − Φ(f); o sobre-acionamento é simétrico. |
| Quadro neutro final | `EPD_SETTLE_FRAMES` quadros de 0 V no fim de cada update. |
| Underrun | `EPD_DRAW_EMPTY_LINE_QUEUE` baixa o clock para `EPD_LCD_PIXEL_CLOCK_MIN_MHZ` e refaz o update com flash. |
| Modo legado | `EPD_USE_LEGACY_REFRESH = true` restaura exatamente o comportamento anterior. |

Sequência de uma troca de tela (N = saturação, X = sobre-acionamento):

```
escurece Φ(origem) + X   → todos no preto (+X)
clareia  N + X           → todos no branco (+X)
[EPD_CLEAN_FLASH_CYCLES × (escurece N + X, clareia N + X)]
escurece N − Φ(destino)  → destino
neutro
```

## Política

Cada `show*()` publica via `refreshFull()`. A chave da tela é o nome da função
chamadora (`__builtin_FUNCTION()`); sem chave confiável, toda publicação conta
como troca de tela.

| Situação | Tipo | Área |
|---|---|---|
| Painel branco e limpo (boot, após limpeza profunda) | `FROM-WHITE` | pixels alterados |
| Troca de tela | `CLEAN` (preto → branco → destino) | **painel inteiro** |
| Mesma tela, > 1 % dos pixels ou retângulo > 12 % | `CLEAN` | painel inteiro |
| Mesma tela, mudança pequena (bateria, teclado Wi-Fi) | `PARTIAL`, sem flash | pixels alterados |
| 5 parciais seguidos | `CLEAN` | painel inteiro |
| Falha anterior | `CLEAN` (`recovery`) | painel inteiro |
| 30 trocas com flash | limpeza profunda + `FROM-WHITE` | — |

Tempos estimados no clock padrão (quadro ≈ 27,5 ms, N = 17, X = 6): troca de
tela ≈ 1,8 s, parcial ≈ 0,6–0,7 s, limpeza profunda ≈ 3,1 s. O GC16 anterior
levava ≈ 0,8 s, mas deixava restos.

## Logs

```
[display] acionamento N=17 X=6 quadros (quadro=27.5ms temp=24C)
[display] T5S3 Pro pronto ... clock=padrao quadro=27.5ms N=17 X=6 temp=24C(gauge) ...
[display] refresh #12 CLEAN reason=screen screen=showSelfAssessment changed=48213 bbox=480x610 N=17 X=6 phases=64 ... epd=1760ms ... result=0x0
[display] refresh #13 PARTIAL reason=same-screen screen=showWifiPassword changed=812 bbox=96x40 N=17 X=0 phases=26 ...
```

- `screen=` deve mostrar o nome da tela (`showQuestion`, `showSelfAssessment`…).
  Troca de tela deve sair como `CLEAN`.
- `quadro` deve ficar estável (±10 %).
- `result=0x400` = underrun; deve aparecer no máximo uma vez.
- `temp=...(default)` = nem termistor nem gauge responderam; tenta de novo a
  cada 30 s.

## Ajuste em bancada

Mude um parâmetro por vez e compare sempre a mesma sequência de telas
(ex.: pergunta → revelar → avaliar, 5 vezes).

| Sintoma | Ajuste |
|---|---|
| Ainda sobra resto de rótulo nos botões | `EPD_CLEAN_FLASH_CYCLES = 1` (+~1,2 s) ou `EPD_RAIL_OVERDRIVE_MS` 150 → 300 |
| Texto novo acinzentado / pouco contraste | `EPD_SATURATION_DRIVE_MS` 450 → 600 |
| Fundo branco "sujo" ou imagem que "gruda" em todas as telas | VCOM: usar o valor impresso na flex do painel em `EPD_VCOM_MV` |
| Troca de tela lenta e imagem já limpa | `EPD_RAIL_OVERDRIVE_MS` 150 → 80 |
| Fantasma após vários parciais | `EPD_MAX_CONSECUTIVE_PARTIALS` menor |
| Quero o comportamento antigo | `EPD_USE_LEGACY_REFRESH = true` |

Antes de cada comparação, use Configurações → limpeza profunda para partir
de um painel limpo.

## Testes de host

```bash
cd firmware/t5s3-pro
g++ -std=c++17 -O2 -Wall -Wextra -Iinclude \
    test/epd_waveform_builder_test.cpp src/epd_waveform_builder.cpp \
    -o /tmp/epd_waveform_builder_test && /tmp/epd_waveform_builder_test
```

Verifica balanço DC, estado final, que na troca de tela **todo** pixel
(inclusive preto→preto) visita o preto e o branco, que `PARTIAL` nunca toca
pixels inalterados, quadros neutros no fim e o limite de 250 fases do epdiy.
O teste usa um modelo ideal de partícula; a calibração de energia só pode ser
confirmada no painel.

## Arquivos alterados

Somente o módulo do display; `main.cpp`, `BatteryService` e demais serviços
não foram tocados.

- `src/t5_display.cpp`, `include/t5_display.h`: motor de refresh.
- `src/epd_waveform_builder.cpp`, `include/epd_waveform_builder.h`: gerador
  de waveform (sem dependência de Arduino/epdiy).
- `include/config.h`: bloco `EPD_*` (substitui `EPD_AUTO_DEEP_CLEAN_INTERVAL = 5`).
- `test/epd_waveform_builder_test.cpp`: teste de host.
