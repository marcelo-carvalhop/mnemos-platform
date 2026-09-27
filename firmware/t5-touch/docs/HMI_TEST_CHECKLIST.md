# Checklist de validação HMI — T5 Touch

**Base normativa:** `docs/ux/HMI_T5_TOUCH_GUIDELINES_v0.1.md`

Este checklist transforma as diretrizes de HMI em critérios verificáveis para a
variante `firmware/t5-touch`. Ele complementa os testes funcionais do firmware e
deve ser repetido em retrato e paisagem sempre que `T5Display`, `TouchZone`,
tipografia, orientação ou fluxo de estudo forem alterados.

## Geometria e hierarquia

- [ ] A barra de sistema não compartilha baseline com o título da tela.
- [ ] Título e metadado/status ocupam linhas distintas na faixa de contexto.
- [ ] Nenhum título, subtítulo, nome de deck ou status sobrepõe outro texto.
- [ ] Conteúdo começa abaixo da faixa de contexto em ambas as orientações.
- [ ] Nenhum elemento de conteúdo invade a action rail.
- [ ] Botões inferiores mantêm margem visível em relação à borda física.
- [ ] Geometria visual dos botões e `TouchZone` correspondente permanece coerente.
- [ ] Paisagem usa composição em colunas/grade; não é apenas retrato comprimido.

## Tipografia

- [ ] Título de tela utiliza 20–22 px e `BLACK`.
- [ ] Pergunta/resposta usa 18–20 px e `BLACK`.
- [ ] Metadado usa 13–14 px e não carrega informação essencial sozinho.
- [ ] Texto fino permanece legível sob iluminação ambiente normal.
- [ ] Pinyin tonal renderiza corretamente (`ā á ǎ à`, `ǖ ǘ ǚ ǜ`, etc.).
- [ ] Português renderiza acentos e cedilha sem fallback visual.
- [ ] Truncamento não divide sequências UTF-8.
- [ ] Textos longos não saem da área do componente.

## Touch

- [ ] Todo toque válido produz feedback perceptível antes do redraw final.
- [ ] Debounce mínimo de 400 ms entre ações aceitas.
- [ ] Girar preserva card, posição e etapa da sessão.
- [ ] Home durante estudo pausa sem descartar a fila.
- [ ] Abortar exige confirmação e preserva revisões já registradas.
- [ ] IRQ do GT911 permanece ativo; polling é apenas fallback.

## Fluxos

- [ ] Pergunta e resposta de referência nunca aparecem simultaneamente antes da tentativa.
- [ ] Autoavaliação mantém `Não recuperei` à esquerda e `Recuperei` à direita.
- [ ] Esforço mantém `Difícil → Normal → Fácil`.
- [ ] Decks apenas filtra/compoõe sessão; não edita biblioteca.
- [ ] Agenda sempre acompanha barra com valor numérico.
- [ ] Wi-Fi, microSD e sincronização respeitam as mesmas margens e action rail.

## E-paper

- [ ] Texto principal é `BLACK` sobre `WHITE`.
- [ ] `DARK_GRAY` fica restrito a informação secundária.
- [ ] Nenhum texto de corpo é desenhado sobre `MID_GRAY`.
- [ ] Estados não dependem apenas de tonalidade.
- [ ] Mudança de orientação usa full refresh.
- [ ] Refresh parcial/feedback não deixa artefatos persistentes após a tela seguinte.
