# Auditoria de design — Mnemos (app + web)

Base: 25 PNGs em `screenshots/mobile/` (800×1760 px, 400×880 pt @2x) e 11 PNGs em
`screenshots/web/` (2880×1800 px, 1440×900 CSS @2x). Valores de token conferidos em
`app/mobile/lib/theme/tokens.dart`, `app/mobile/lib/theme/typography.dart` e
`app/web/src/styles.css`.

Cada achado é marcado **(A) violação de princípio** ou **(B) divergência de estilo**.
Severidade: **alto / médio / baixo**, por impacto na percepção de qualidade.

---

## 1. Veredito

Isto parece um produto *bem pensado* e *mal terminado*. Alguém aqui sabe o que está
fazendo: o arquivo de tokens documenta decisões de contraste com número (o comentário
sobre `#FCFBFE` dar 1,06:1 sobre a tela e por isso virar branco puro é o tipo de coisa
que 90% dos times não escreve), a tipografia é nomeada por papel, o texto de interface
é escrito por gente e não por comitê. Mas quando você abre as 36 telas em sequência, a
impressão que fica não é "caro" — é "protótipo caprichado". Três razões, e nenhuma tem
a ver com a paleta: **as telas estão vazias pela metade** (mobile 15, 22 e 24 têm 55% a
70% da altura em branco morto; web 04 e 08 têm mais de metade da largura útil sem
nada), **as superfícies não têm sistema** (sete raios diferentes no app, três no web,
nenhum deles concêntrico com o pai) e **há defeitos que passariam em qualquer revisão
de PR mas não em uma de design** — a palavra "Descartar" quebrada no meio em
`16-revisar-cards-gerados.png`, o botão de apagar a conta pintado com a cor de
"vencendo" em vez do token `destructive` que o próprio arquivo define. Um produto caro
não tem o vazio embaixo; ele preenche ou encurta. O Mnemos hoje faz nem uma coisa nem
outra: desenha o topo com muito cuidado e abandona o resto da tela.

---

## 2. Os cinco problemas mais graves

### 2.1 O vazio de baixo — nenhuma tela tem âncora vertical (A) — **alto**

**Onde.** `mobile/15-geracao-falhou.png` (o bloco de erro ocupa y≈620–1130 de 1760, com
620 px de nada acima e 630 px abaixo); `mobile/22-dispositivo-sem-terminal.png` (todo o
conteúdo acaba em y≈650, restam 1110 px vazios); `mobile/24-conectar-terminal.png`
(idem, acaba em y≈630); `mobile/06-biblioteca-vazia.png` (acaba em y≈740, 900 px
vazios); `web/04-biblioteca.png` (dois cards em uma grade de três colunas, ~1500 px CSS
de largura e ~700 px de altura sem nada); `web/08-dispositivo.png` (o painel morre em
y≈700 de 1250 e a metade direita da tela nunca é usada).

**O problema.** O conteúdo é jogado no topo e o resto da tela fica em branco, sem que
nada — nem ilustração, nem centralização, nem redução de escala — reconheça que sobrou
espaço.

**A referência Apple.** Estados vazios da Apple são **centrados no espaço disponível,
não empilhados no topo**. Lembretes sem lembretes centra vertical e horizontalmente um
glifo grande em cinza, um título e uma linha de apoio; Fotos ("Nenhuma foto"), Arquivos
e Mail fazem o mesmo. E nenhum deles usa botão primário preenchido no estado vazio — a
ação fica na barra de navegação ou na toolbar, porque um botão lavanda de 60 pt de
altura no meio do nada grita mais alto que a explicação que ele deveria acompanhar. No
iPad, Ajustes e Mail nunca deixam a coluna direita vazia: ou centram um placeholder, ou
não mostram a coluna.

**A correção.**
- Telas de estado único (15, 22, 24, 06): centralizar o bloco verticalmente no espaço
  disponível (`Center` + `ConstrainedBox(maxWidth: 320)`), glifo de 44–52 pt em
  `MnemosColors.fainter` acima do título, título 22 pt Literata, apoio 15 pt, e a ação
  como **botão secundário de largura de texto**, não um preenchido de largura total.
- `web/04`: com menos de 3 baralhos, colapsar para uma coluna de largura máxima 720 px
  em vez de esticar uma grade de 3 colunas com dois itens.
- `web/08`: usar a segunda metade da largura, ou reduzir o painel para
  `max-width: 900px` e centralizá-lo.

---

### 2.2 Não existe escala de raio, e o aninhamento não é concêntrico (A) — **alto**

**Onde.** `app/mobile/lib/theme/tokens.dart`, `MnemosRadii`: `bar 3, small 12,
control 14, action 16, tile 18, pill 20, card 22, sheet 24`. Visível em
`mobile/11-baralho.png`, onde em 400 px de altura convivem os ladrilhos de estatística
(18), os botões "Adicionar card"/"Enviar ao T5" (16) e os cards de pergunta (22); e em
`mobile/09-criar.png`, onde o card branco (22) contém os chips 5/8/12/20 (14) com 20 pt
de padding.

**O problema.** Sete raios entre 12 e 24 são sete valores que ninguém consegue
distinguir e que, somados, fazem cada bloco parecer desenhado por uma pessoa diferente.
Pior: um raio interno de 14 dentro de um raio externo de 22 com 20 pt de padding produz
um canto visivelmente *errado* — o interno deveria ser 22 − 20 = 2, ou o externo
deveria ser 14 + 20 = 34.

**A referência Apple.** A Apple usa **poucos raios, com curvatura contínua (squircle)**,
e sempre **concêntricos**: no widget de Fitness, no card de Destaques da Saúde e nos
cards de Atalhos, o raio do elemento interno é o raio do pai menos o padding, de modo
que as duas curvas ficam paralelas. A HIG chama isso de *nested corner radii*, e é o
motivo pelo qual um card da Apple parece torneado de um bloco só e um card comum parece
uma caixa com outra dentro.

**A correção.** Reduzir para **três raios**: `control = 12` (chips, campos, botões
dentro de blocos), `card = 20` (todo card e ladrilho), `sheet = 28` (o objeto central da
tela — o card em revisão, o bloco-herói). Matar `bar`, `small`, `action`, `tile` e
`pill` (pílula é `StadiumBorder`, não um número). Para qualquer elemento aninhado,
`raioInterno = raioExterno − padding`, com piso de 6. E usar
`ContinuousRectangleBorder` / `superellipse` em vez de `RoundedRectangleBorder` — o
squircle é metade da razão pela qual as superfícies da Apple parecem caras.

---

### 2.3 Inversão de hierarquia: o botão desabilitado pesa mais que o secundário habilitado (A) — **alto**

**Onde.** `mobile/09-criar.png`, rodapé: "Gerar 8 cards" **desabilitado** é uma barra
preenchida de largura total (`disabledBackgroundColor: MnemosColors.line` = `#DEDAE8`,
em `theme.dart:88`), e logo abaixo "Escrever um card à mão" — **habilitado** — é texto
lavanda sem fundo. O mesmo em `mobile/12-editor-card-novo.png` ("Salvar e criar outro"
desabilitado preenchido sobre "Salvar e sair" habilitado com contorno) e em
`web/05-criar.png`, `05b`, `05c` ("Gerar 12 cards" desabilitado, cinza-lavanda
preenchido, ao lado de "Escrever eu mesmo" habilitado, branco com contorno de 1 px).

**O problema.** O elemento mais pesado da tela é o que não funciona. A pessoa mira nele,
não acontece nada, e o único caminho aberto está desenhado como se fosse menos
importante.

**A referência Apple.** Na App Store, quando um app não pode ser baixado, o botão
"OBTER" **não vira um retângulo cinza preenchido** — ele perde a cor e fica com o peso
do fundo. Em Ajustes e nas planilhas de compra do iOS, o primário desabilitado usa o
preenchimento do primário com opacidade reduzida (≈30–40%), o que preserva a *cor* e
portanto a leitura de "é este botão, só que ainda não". Nunca há um preenchido cinza
mais forte que o secundário ativo.

**A correção.** Desabilitado = `MnemosColors.primary` a 30% de opacidade, rótulo em
`onDark` a 50% — mantém a cor, mata a promessa. E promover o secundário: "Escrever um
card à mão" / "Escrever eu mesmo" precisa de contorno `outline` (`#CBC7DC`) de 1 px e
altura igual à do primário, para que os dois formem um par, não uma barra e uma nota de
rodapé.

---

### 2.4 O coral de "vencendo" está pintando a ação destrutiva — contra o próprio sistema (A) — **alto**

**Onde.** `mobile/21-seus-dados.png`, botão "Apagar minha conta" (contorno e rótulo
coral claro). Código: `app/mobile/lib/features/account_screen.dart:149-150` usa
`MnemosColors.due` no `foregroundColor` e no `side`; a linha 214 usa `due` como
`backgroundColor` do "Apagar" no diálogo de confirmação.

**O problema.** Duplo. Semântico: `tokens.dart` define `destructive = #7A2410` e
escreve, textualmente, *"O coral ensina 'tem coisa para fazer hoje'; encontrá-lo depois
num botão que destrói dados desfaz a lição"* — e o botão que destrói dados usa o coral.
De contraste: o mesmo arquivo registra que `due` (`#E08A72`) dá **2,39:1** como tinta
sobre a tela clara. O rótulo da ação irreversível é o texto menos legível da tela.

**A referência Apple.** Em Ajustes › Geral › Transferir ou Redefinir iPhone, "Apagar
Todo o Conteúdo e Ajustes" é **vermelho sistema saturado** (`systemRed`), a mesma cor do
`Delete` do alerta destrutivo, e ela **não aparece em nenhum outro papel** no app — nem
em badge, nem em gráfico, nem em estado. Ajustes usa laranja/amarelo para aviso e
vermelho *só* para destruição. A separação é rígida exatamente para que o vermelho
continue significando alguma coisa.

**A correção.** Trocar as três ocorrências por `MnemosColors.destructive` (9,22:1 sobre
a tela, já medido no token). O mesmo no web: `09-configuracoes.png`, "Apagar a conta" —
conferir se usa `--mn-destructive` (`#7a2410`) e não `--mn-terracotta`.

---

### 2.5 Defeitos de layout visíveis a olho nu (A) — **alto**

Três, todos no balde de "isto não passaria em uma revisão de design":

**a) "Descartar" quebra no meio da palavra.** `mobile/16-revisar-cards-gerados.png`,
rodapé: o botão mostra `Descarta` / `r` em duas linhas. Causa em
`app/mobile/lib/features/generation/approval_screen.dart:281-293` — `Expanded` (flex 1)
para "Descartar" contra `Expanded(flex: 2)` para "Aprovar", sem largura mínima.
*Correção:* dar ao secundário largura intrínseca (`IntrinsicWidth`, ou `flex: 1` com
`minWidth: 120`) e ao primário `Expanded`; ou `maxLines: 1` + `softWrap: false`.
Nenhuma tela de triagem da Apple (Fotos › Duplicados, a triagem de Mail) quebra o rótulo
de um botão.

**b) Ladrilhos 2-up com alturas diferentes.** `mobile/05-hoje.png`: o ladrilho
"SEQUÊNCIA" vai de y≈601 a 840 px; o "RETENÇÃO 90 D", ao lado, de 601 a 800. 40 px de
degrau na base de uma fileira de dois. Mesmo defeito em `mobile/17-cota-esgotada.png`,
onde os cartões "Mensal" e "Anual" não compartilham nem topo nem base. *Referência:* os
cards de Destaques da Saúde e os ladrilhos do resumo do Fitness têm sempre altura
idêntica na fileira — o conteúdo mais curto ganha espaço, a fileira não ganha degrau.
*Correção:* `IntrinsicHeight` na `Row` com `CrossAxisAlignment.stretch` e o conteúdo
distribuído (`MainAxisAlignment.spaceBetween`).

**c) Cards esticados com vazio no rodapé.** `web/07-progresso.png`: os quatro ladrilhos
do topo têm a mesma altura (y 165–365 exibido) porque o primeiro é mais alto, mas os
três brancos têm conteúdo só até y≈270 — ~68 px CSS de nada dentro de cada um.
*Correção:* `align-items: start` na fileira, ou distribuir o conteúdo (numeral no topo,
rótulo colado na base), como faz o card de Destaques da Saúde.

---

## 3. Aplicativo

### 3.1 Tipografia e peso ótico

**Quinze tamanhos, cinco deles no mesmo oitavo (A) — médio.**
`typography.dart` declara 44, 38, 34, 30, 30, 28, 26, 22, 22, 19, 17, 16, 15, 15, 14,
13, 13, 12, 12, 12, 11. Cinco tamanhos de display entre 28 e 44, e dois pares duplicados
(30 em `screenTitle` e `numeral`; 22 em `prompt` e `numeralSmall`). *Referência:* os
text styles do iOS são dez (largeTitle 34, title1 28, title2 22, title3 20,
headline/body 17, callout 16, subhead 15, footnote 13, caption1 12, caption2 11), e cada
um tem papel exclusivo — não há dois estilos do mesmo tamanho. *Correção:* colapsar para
34 / 28 / 22 / 19 / 17 / 15 / 13 / 12, com o hero numeral em 44 como única exceção.

**A unidade compete com o numeral (A) — médio.**
`mobile/10-progresso.png`, ladrilho "MEMÓRIA ACUMULADA": "1" em 38 pt e "mês" em 26 pt
(`numeralUnit`) — a unidade tem 68% do corpo do número, e a linha lê "1 mês" como duas
palavras de peso igual, não como um número com legenda. *Referência:* no resumo do
Fitness, "512" fica em ~40 pt e "CAL" em 13 pt caixa alta — a unidade tem ~32% do
numeral e nunca disputa; o mesmo em Bolsa e Relógio. *Correção:* `numeralUnit` para
15 pt caixa alta em `MnemosColors.faint`, alinhado à linha de base, ou 55% do corpo do
numeral que acompanha.

**Numerais sem figuras tabulares (A) — médio.**
`heroNumeral`, `numeralLarge` e `numeral` usam Literata com figuras proporcionais.
"19 dias" em `05-hoje` vira "20 dias" amanhã e a caixa inteira se desloca.
*Referência:* a Apple usa a variante *monospaced digit* da SF em tudo que muda sozinho —
cronômetro, anéis do Fitness, cotações da Bolsa. *Correção:*
`fontFeatures: [FontFeature.tabularFigures()]` em todos os estilos de numeral. Custa uma
linha, e é a diferença entre um painel que respira e um que treme.

**A sobrancelha mono faz oito trabalhos diferentes (A) — médio.**
O mesmo `eyebrow` (JetBrains Mono 12, caixa alta, 0,08 em) rotula seção de tela
(`ESTUDO`, `O SEU DIA`, `CONTA E DISPOSITIVOS` em 19/20), campo de formulário
(`SOBRE O QUE`, `QUANTOS CARDS` em 09), face de card (`FRENTE`, `VERSO` em 16), métrica
(`SEQUÊNCIA`, `RETENÇÃO 90 D` em 05), eixo de gráfico (`JUN`, `JUL`, `AGO` em 10),
estado (`VENCENDO HOJE 3`, `ESTA SEMANA 7` em 11) e **string de versão**
(`FIRMWARE 0.5.0  PROTOCOLO V3` em 23). Quando um recurso marca tudo, ele não marca
nada — em `23-dispositivo-conectado.png` a versão do firmware tem exatamente o mesmo
posto visual que o cabeçalho "CONTEÚDO NO APARELHO". *Referência:* a Apple reserva o
caixa-alta pequeno para **um** papel — o cabeçalho de grupo em Ajustes (13 pt, SF,
cinza, sem tracking exagerado). Em News o *kicker* acima da manchete também é caixa
alta, mas é SF, colorido pela editoria, e aparece uma vez por card. *Correção:* manter o
mono só para (i) cabeçalho de grupo e (ii) dado técnico/tabular. Rótulo de campo vira
sans 13 pt `muted` em caixa mista; string de versão vira `caption` 12 pt `fainter`, sem
caixa alta.

### 3.2 Navegação e barra de abas

**A aba selecionada muda só de cor (A) — médio.**
`mobile/05-hoje.png` / `07` / `09` / `10`: os quatro ícones são o mesmo desenho vazado
nos dois estados; só a cor muda (lavanda vs. `faint`). *Referência:* toda barra de abas
da Apple — Fitness, Saúde, App Store, Podcasts — troca o **símbolo vazado pelo
preenchido** na aba ativa, além da cor. É redundância deliberada: quem não distingue os
dois tons ainda distingue as duas formas. *Correção:* usar os pares vazado/preenchido do
SF Symbols (`calendar`, `books.vertical` / `.fill`, `plus.circle` / `.fill`,
`chart.line.uptrend.xyaxis`).

**Proporção ícone/rótulo invertida (A) — baixo.**
`ui/tab_bar.dart:88` desenha o ícone em 22 px com rótulo de 12 pt. *Referência:* a barra
de abas do iOS usa glifo de ~25–28 pt com rótulo de 10 pt — o ícone domina, o rótulo
confirma. Aqui o rótulo quase iguala o ícone, e a barra lê como uma fileira de palavras
com desenhinhos. *Correção:* ícone 26, rótulo 11.

**Ícones Material dentro de um app editorial (A) — alto.**
As abas (`add_circle_outline` para Criar, o rabisco com faíscas para Progresso), a
engrenagem de `05-hoje`, a câmera e o `picture_as_pdf` de `09-criar` — que tem **as
letras "PDF" desenhadas dentro do ícone** — são glifos do Material Icons, com traço
uniforme de 2 px. Colados a uma Literata 600 e a uma Public Sans 15, têm peso ótico
errado: leves demais para os títulos, genéricos demais para a marca. *Referência:* o SF
Symbols existe justamente para casar peso de glifo com peso de texto (`.weight(.semibold)`
ao lado de um headline semibold), e a Apple nunca coloca texto dentro de um ícone — em
Arquivos e Mail o tipo de documento é `doc.text` e a palavra fica no rótulo abaixo.
*Correção:* trocar o set inteiro por SF Symbols (iOS) e Material Symbols com `wght`
casado (Android), e remover as letras de dentro do ícone de PDF. Este é, sozinho, o item
de maior retorno estético por hora de trabalho no app.

**Sem título grande colapsável e sem tratamento de borda de rolagem (A) — médio.**
`mobile/11-baralho.png` rola uma lista longa; ao rolar, "Redes de Computadores" some e
não sobra nada dizendo onde você está. E o último card é guilhotinado no pixel inferior
da tela, sem fade nem safe area. *Referência:* o large title do iOS colapsa em título
inline na barra de navegação, e o *scroll edge effect* impede que o conteúdo encoste no
vivo. *Correção:* `SliverAppBar` com `FlexibleSpaceBar` para o colapso, e máscara de
degradê de 24 pt no topo e na base do `ScrollView`.

**Chevron do voltar desalinhado do título grande (A) — baixo.**
`mobile/19-configuracoes.png`, `12`, `22`, `24`: o "‹" começa ~8 px à direita da margem
onde começa o título grande logo abaixo. *Referência:* no iOS o chevron do botão de
voltar compartilha exatamente a margem de layout com o large title, formando uma coluna
única. *Correção:* padding esquerdo negativo no `IconButton` (−8) para que o vivo óptico
do chevron caia em `MnemosSpacing.screen` (20).

### 3.3 Ajustes — a tela mais distante do padrão Apple

**Não há lista agrupada (A) — alto.**
`mobile/19-configuracoes.png` e `20`: as linhas "Cards novos por dia", "Revisões por
dia", "Meta de retenção", "O dia vira às", "Fuso horário", "Lembrar de revisar",
"Dispositivo", "Gerações por IA" e "Seus dados" flutuam direto sobre o canvas `#F6F4FA`,
sem superfície, sem separador e sem altura de linha constante. Não dá para saber onde
uma linha termina e a outra começa, nem quais são tocáveis (só três das nove levam a
algum lugar).

**Pior: o alinhamento do texto pula.** "Dispositivo" tem ícone e o título começa em
x≈120 px; "Gerações por IA" e "Seus dados", logo abaixo, não têm ícone e começam em
x≈40. Três linhas do mesmo grupo, duas margens diferentes.

*Referência Apple:* Ajustes do iOS é *inset grouped* — linhas brancas sobre cinza, raio
10, altura mínima 44 pt, separador hairline que **começa depois do ícone** (nunca na
margem), ícone de 29×29 com fundo colorido, título 17 pt, valor secundário cinza à
direita e `chevron.right` em `tertiaryLabel`. E a regra que este arquivo quebra: **se
qualquer linha do grupo tem ícone, todas têm** — quando um item não tem ícone natural,
Ajustes inventa um, exatamente para que a coluna de texto não pule.

*Correção:* envolver cada grupo em um card `raised` com raio 20 e margem lateral 20,
separadores `hairline` de 1 px recuados até a coluna do texto, altura mínima de linha
48, e um ícone para **todas** as linhas de "CONTA E DISPOSITIVOS" — ou nenhuma.

**Interruptor desligado com trilho tingido (A) — médio.**
`mobile/20`, "Lembrar de revisar", e `mobile/23`, "Direito Constitucional": o estado
*off* tem trilho lavanda-claro, não cinza neutro. Lê como "meio ligado", ou como ligado
e desabilitado. *Referência:* o `UISwitch` do iOS usa `systemGray5` (`#E9E9EA`,
rigorosamente neutro) no off, e a cor de acento só no on — é a única maneira de o estado
ser legível sem depender de cor. *Correção:* `inactiveTrackColor: Color(0xFFE3E1E8)`
dessaturado, `primary` só no ligado.

**Passo-a-passo com o valor no meio (B/A) — baixo.**
`mobile/19`: os steppers `⊖ 10 ⊕` colocam o número entre os dois botões. O `UIStepper`
do iOS não mostra o valor — ele fica no rótulo da linha, à esquerda do controle. Aqui
funciona, mas cada círculo tem ~22 pt visuais; confirme que o
`BoxConstraints(minHeight: 48, minWidth: 48)` de `primitives.dart:336` está aplicado a
esses botões e não só ao de voltar.

### 3.4 Estados

**O erro não tem nenhum sinal cromático (A) — alto.**
`mobile/15-geracao-falhou.png`: "NÃO DEU CERTO / Algo deu errado" em preto sobre o mesmo
fundo lavanda-claro de todas as outras telas, com o botão "Tentar de novo" no mesmo
lavanda do botão primário de sucesso. Sem ícone, sem cor, sem superfície. Tire o texto e
esta tela é indistinguível de `24-conectar-terminal.png`. *Referência:* nas telas de
falha do iOS (falha de compra na App Store, "Não foi possível conectar" no iCloud) há
sempre um glifo de estado — `exclamationmark.triangle` ou `xmark.circle` — em
`systemOrange`/`systemRed` acima do título, e o corpo do erro em um card, não solto no
fundo. *Correção:* glifo de 44 pt em `MnemosColors.destructive` ou `dueText` acima da
sobrancelha, e bloco centrado verticalmente (ver 2.1).

**Carregando: 400 px de vazio acima do conteúdo (A) — médio.**
`mobile/14-gerando.png`: o "X" fica sozinho no topo e a lista de etapas começa em y≈900
de 1760. As etapas em si estão bem resolvidas (menta preenchido = concluído, contorno
lavanda = atual, contorno cinza = pendente — vocabulário correto, igual ao do progresso
de restauração do iCloud). O problema é só a ancoragem. *Correção:* centralizar o
conjunto sobrancelha + título + barra + etapas.

**Vazio: três elementos competindo, todos no topo (A) — médio.**
`mobile/06-biblioteca-vazia.png` tem card branco + botão preenchido de largura total +
linha de dica, um sobre o outro, e 900 px vazios abaixo. *Referência:* Lembretes e Fotos
resolvem o vazio com **um** bloco centrado. *Correção:* ver 2.1.

**"Vencendo hoje 3" e "2 entram na fila de hoje" na mesma tela (A) — baixo.**
`mobile/11-baralho.png`: o cabeçalho da seção diz 3, a linha de apoio logo abaixo diz 2,
e o ladrilho acima diz "2 na fila hoje". Os três números estão certos por definições
diferentes, mas a tela não explica isso a tempo. *Correção:* o cabeçalho conta o mesmo
que o ladrilho ("VENCENDO HOJE 2") e a diferença vai para a nota.

### 3.5 Cor e contraste

**Letra miúda da paywall reprova (A) — médio.** `mobile/17-cota-esgotada.png`: os
parágrafos centrados no rodapé usam `onPrimaryFaint` (`#A8A7CB`) sobre `primaryDark`
(`#3B3B63`) — ≈4,2:1, abaixo do mínimo de 4,5:1 para 13 pt. E são **quatro linhas
centralizadas**: a Apple centraliza no máximo duas e alinha à esquerda qualquer coisa
mais longa (as condições de assinatura na App Store são alinhadas à esquerda, sempre).
*Correção:* `#C2C1DC` ou mais claro, e alinhar à esquerda.

**Badge "-30%" atravessando a borda do cartão (A) — baixo.** Mesma tela: a pílula coral
fica montada sobre o vivo superior do cartão "Anual". *Referência:* o selo de economia
nas páginas de assinatura da App Store fica **dentro** da linha do plano, como um chip
ao lado do preço. *Correção:* mover para dentro, à direita de "Anual".

**Chave de legenda invisível (A) — médio.** `mobile/07-biblioteca.png`: os três pontos
da legenda são coral, lavanda e um lilás pálido (`primary40`/`track`). O ponto de "10
total" tem ≈1,5:1 sobre o card branco, muito abaixo dos 3:1 exigidos para elemento
gráfico portador de significado. *Correção:* o terceiro ponto vira contorno de 1,5 px em
`outline`, ou ganha `primary60` (`#A9A9CE`).

**Um numeral, quatro regras de cor (A) — médio.** `mobile/10-progresso` pinta "86 %" e
"19 dias" de lavanda; `mobile/11-baralho` pinta "2 na fila" de `dueText` e "10"/"1,4" de
`ink`; `web/07-progresso` pinta "98%" de menta e "16"/"7" de `ink`; `web/03-hoje` pinta
"575 dias" de `ink` e "98%" de lavanda. Quatro telas, quatro critérios. *Referência:*
Saúde e Fitness pintam o numeral com a cor da **categoria** (movimento = vermelho,
exercício = verde, atividade = azul), sempre a mesma para a mesma métrica. *Correção:*
fixar a regra no token e aplicá-la nas duas superfícies — retenção = menta, vencimento =
coral escuro, contagem neutra = `ink`, memória acumulada = lavanda.

**A cor de acento também é o fundo (A/B) — médio.** O lavanda `#6E6FA0` é o botão
primário, o bloco-herói, a aba ativa, a barra de progresso, o chip selecionado, o mapa
de calor **e** — em versões claras — a superfície `soft`, o `tint` e o próprio canvas.
Quando tudo é lavanda, o botão lavanda não se destaca de nada. *Referência:* os apps da
Apple são majoritariamente neutros com **um** acento que aparece pouco: em Ajustes, o
azul ocorre só nos chevrons e nos valores tocáveis; o resto é cinza e branco. É a
raridade do acento que o torna uma indicação. *Correção (mantendo a paleta):* neutralizar
as superfícies — canvas e cards em cinzas quase neutros (`#F7F6F8`, `#FFFFFF`) — e
reservar o lavanda saturado para ação e seleção. A marca continua lavanda; ela só para
de ser o papel de parede.

### 3.6 Superfície e densidade

**Campos de texto quase invisíveis (A) — médio.** `mobile/12-editor-card-novo.png`: os
campos "Frente" e "Verso" são retângulos do mesmo tom do fundo com contorno de 1 px em
`hairline` — sem preenchimento, sem sombra, sem nada dizendo "digite aqui". Em `13` o
campo focado ganha contorno lavanda, o que só evidencia que o não focado não tem estado
nenhum. *Referência:* os campos de Lembretes, Notas e dos formulários do iOS têm
**preenchimento** (`secondarySystemGroupedBackground`, branco sobre cinza), o que
funciona mesmo com brilho baixo e mesmo sem foco. *Correção:* preenchimento `raised`
sobre canvas, contorno `line` de 1 px, foco = contorno lavanda de 2 px.

**Padding interno de card varia por tipo (A) — baixo.** Cards de baralho em
`07-biblioteca` usam ~20 pt de padding; os resultados de busca em `08-busca` usam ~12; os
cards de pergunta em `11-baralho` usam ~14. Três densidades para três listas do mesmo
app. *Correção:* 16 pt para linha de lista, 20 pt para card de conteúdo. Duas medidas,
não três.

**Círculo menta reutilizado com outro sentido (A) — baixo.** `mobile/09-criar.png`: "1
geração grátis restante" mostra o dígito "1" dentro de um anel menta fino — e em
`14-gerando.png` o círculo menta é "etapa concluída". Mesmo desenho, dois sentidos.
*Correção:* a cota vira um chip de texto (`1 de 1 disponível`), sem anel.

---

## 4. Web

### 4.1 Barra lateral e layout de duas colunas

**Estado ativo não cobre todos os itens (A) — médio.**
`web/03`, `04`, `07` e `08` mostram a rota atual com uma pílula lavanda clara. Em
`web/09-configuracoes.png` a rota é `/configuracoes` e o item "Configurações", no rodapé
da barra, **não recebe pílula nenhuma** — a barra inteira parece sem seleção.
*Referência:* a sidebar do developer.apple.com e a de Mail/Notas no iPad marcam o item
ativo em qualquer posição da lista, inclusive nos grupos de rodapé. *Correção:* aplicar
a mesma classe de ativo aos itens de rodapé.

**A dica de teclado é ruído no lugar mais nobre (A) — baixo.**
O "N" em JetBrains Mono dentro do botão "Criar" (todas as telas) e o "espaço" dentro de
"Estudar agora" (`web/03`) ficam **colados ao rótulo, centralizados**, não alinhados à
direita. *Referência:* no macOS a tecla de atalho de um item de menu é sempre
right-aligned, em coluna própria, em cinza terciário; no Spotlight o hint vive na borda
direita da linha. *Correção:* `justify-content: space-between` no botão e hint em
`--mn-text-fainter` — ou ensinar o atalho uma vez e tirá-lo do botão.

**A coluna direita não existe em metade das rotas (A) — médio.**
`web/04-biblioteca.png` e `web/08-dispositivo.png` deixam ~1200 px CSS de largura sem
uso; `web/06-estudar.png` e `web/09-configuracoes.png` idem. *Referência:* iCloud.com e
a App Store para web ou preenchem a segunda coluna, ou limitam a largura do conteúdo e o
centram. Uma coluna esquerda de 720 px numa janela de 1440 com nada à direita lê como
layout quebrado, não como respiro. *Correção:* `max-width: 960px; margin-inline: auto`
no contêiner de conteúdo das rotas de coluna única.

**A barra lateral não sai no modo de foco (A) — médio.**
`web/06-estudar.png`: durante a revisão, a navegação completa continua na tela, com badge
de vencimento e bloco de sincronização. *Referência:* toda superfície de foco da Apple
remove o cromo — Fotos em tela cheia, o leitor de Books, o player da TV, o modo de
apresentação do Keynote. *Correção:* `/estudar` esconde a barra lateral e deixa só o "X"
e a régua de progresso.

### 4.2 Telas

**`01-landing.png` — a página não mostra o produto (A/B) — médio.**
A dobra tem manchete, subtítulo, um botão de 135×45 px CSS com raio ~10, e três colunas
de texto com um filete lavanda de 2 px acima de cada. Não há nenhuma imagem, nenhuma
tela, nenhum aparelho — e o produto é um objeto físico de tinta eletrônica.
*Referência (A):* toda página de produto da apple.com abre com **o objeto**, grande, e o
texto vem depois; o CTA é uma pílula (raio total) com rótulo de 17 px e padding
generoso, geralmente em par ("Saiba mais" + "Comprar"). *Correção:* botão em
`StadiumBorder`, rótulo 17 px, padding 14×28; e uma imagem do T5 na dobra. *(O filete
acima das colunas é recurso editorial — ver §6.)*

**`02-entrar.png` — formulário ancorado no topo (A) — baixo.**
O painel começa em y≈250 CSS e sobram ~750 px abaixo. *Referência:* a tela de login do
iCloud.com centra o painel nos dois eixos. *Correção:* `min-height: 100dvh; display:
grid; place-items: center`.

**`03-hoje.png` — o bloco-herói é 613×274 px CSS para quatro elementos curtos (A) —
médio.** Sobrancelha, "7 cards em 1 baralho", uma barra de progresso cheia e uma linha de
texto, e ~90 px CSS de vazio no rodapé do card. *Referência:* um card do resumo do
Fitness dessa área carrega três anéis, três métricas e um chevron. *Correção:* listar os
baralhos dentro do herói (é a informação que a coluna de baixo repete), ou reduzir a
altura do card para acompanhar o conteúdo.

**`03-hoje.png` — "Próximos 14 dias" mostra 3 barras (A) — médio.**
Os dias sem vencimento não são desenhados, então três barras vizinhas rotuladas 02, 03 e
08 sugerem três dias consecutivos. O app faz certo: em `mobile/10-progresso.png`, "O que
vem por aí / 14 DIAS" desenha os catorze slots, com os vazios como trilho.
*Referência:* Saúde e Tempo de Uso sempre renderizam o período inteiro; a ausência de
dado é um espaço, não uma barra ausente. *Correção:* renderizar os 14 slots, como o
mobile já faz.

**`04-biblioteca.png` — legenda sem chave de cor (A) — médio.**
A barra tem três segmentos (coral, lavanda, pálido), mas os rótulos "7 vencendo · 1
maduro · 10 total" não têm marcador nenhum — só "7 vencendo" está colorido. O mobile
resolve com pontos (`07-biblioteca.png`). *Correção:* adotar os pontos do mobile, com o
terceiro em `--mn-accent-60` para passar 3:1.

**`04-biblioteca.png` — campo de busca de 1130 px CSS (A) — baixo.**
Uma linha de entrada mais larga que a medida de leitura confortável. *Referência:* a
busca da App Store e a do iCloud.com são limitadas a ~400–560 px mesmo em janelas
largas. *Correção:* `max-width: 480px`.

**`05` / `05b` / `05c-criar` — o terceiro card da prévia está apagado sem explicação (A)
— baixo.** "Para que serve o handshake de três vias?" aparece a ~45% de opacidade
enquanto os dois acima estão cheios. Sem legenda, lê como falha de renderização.
*Correção:* se a intenção é "há mais", usar máscara de degradê na base da coluna (como a
lista de resultados do Spotlight), não opacidade num item inteiro.

**`06-estudar.png` — a única ação da tela é a coisa mais fraca dela (A) — alto.**
"Ver a resposta" é um retângulo de largura total com fundo quase igual ao do card e
contorno de 1 px — mais leve que o card de pergunta acima. *Referência:* em Books o
botão de continuar a leitura é preenchido e colorido; em qualquer fluxo de revisão da
Apple a ação de avanço é a mais pesada da tela. *Correção:* preenchido em `--mn-accent`,
rótulo em `--mn-text-on-accent`, altura 52, `max-width: 420px` centrado.

**`06-estudar.png` — quatro tratamentos de tipo numa faixa de 40 px (A) — baixo.**
"Redes de Computadores" em sans 15, a régua de segmentos, "1 DE 7" e "0 CERTOS · 0
ERRADOS" em mono caixa alta, e "ESPAÇO PARA VIRAR" em mono caixa alta mais claro, tudo
na mesma linha. *Correção:* deck e contador numa linha (sans), atalho fora dela.

**`07-progresso.png` — gráfico sem eixo e sem valor (A) — médio.**
"Revisões por dia" tem 30 barras, dois rótulos de data e nenhuma referência de altura;
os dias zerados viram traços de 2 px que parecem artefato. *Referência:* os gráficos de
Saúde e de Tempo de Uso trazem sempre linha de base, uma ou duas linhas de grade com
valor, e o valor do dia ao tocar. *Correção:* linha de base de 1 px em `--mn-line`, uma
linha de grade rotulada no máximo, e dia zerado como trilho de altura mínima 3 px na cor
do trilho — nunca na cor da barra.

**`08-dispositivo.png` — três superfícies arredondadas aninhadas (A) — médio.**
Painel externo (raio 20) contendo painel `soft` (raio 16) contendo card branco (raio 12),
cada um com seu fundo e sua borda. *Referência:* Saúde e Fitness usam no máximo dois
níveis — card sobre fundo — e criam o terceiro com espaçamento e tipo, não com mais uma
caixa. *Correção:* eliminar o painel externo e deixar os dois blocos internos lado a
lado direto sobre o fundo da página.

**`08-dispositivo.png` — checkbox nativo numa lista de conteúdo (A) — médio.**
O quadradinho de ~13 px CSS ao lado de "Direito Constitucional" é um
`input[type=checkbox]` estilizado, enquanto **a mesma lista no app usa switches**
(`mobile/23`). E o rótulo do primeiro item quebra em duas linhas enquanto o do segundo
não, deixando o quadradinho fora do eixo do texto. *Correção:* switch nas duas
superfícies, rótulo em uma linha com `min-width` na coluna, e o estado ("aguardando o
terminal" / "no aparelho") como texto secundário sob o título, não numa terceira coluna
mono.

**`09-configuracoes.png` — três ajustes contra os oito do app (A) — médio.**
O web expõe assinatura, retenção e dados. O app expõe também cards novos/dia,
revisões/dia, hora de virada do dia, fuso e lembretes. Quem configurou pelo celular não
encontra o que mexeu. *Correção:* paridade, ou uma linha explícita ("Estes ajustes ficam
no aplicativo").

### 4.3 Sistema

**As duas superfícies usam escalas de espaçamento diferentes (A) — alto.**
`styles.css` define `4 / 8 / 12 / 18 / 26 / 40`; `tokens.dart` define
`4 / 8 / 12 / 16 / 20 / 24 / 32 / 40`. Os degraus 18 e 26 do web não existem no app, e
16/20/24 do app não existem no web — ou seja, **nenhum padding de card pode coincidir
entre as duas superfícies**, por construção. O mesmo no raio: web `10 / 16 / 20`, app
`3 / 12 / 14 / 16 / 18 / 20 / 22 / 24`. *Correção:* uma escala só —
`4 / 8 / 12 / 16 / 24 / 40` — e três raios (`12 / 20 / 28`), escritos nos dois arquivos
com os mesmos números.

**Nenhuma das duas superfícies tem modo escuro (A) — médio.**
Não há `Brightness.dark` em `app/mobile/lib/` nem `prefers-color-scheme` em
`app/web/src/`. *Referência:* todo app de primeira parte da Apple entrega Dark Mode, e
um produto cujo objeto companheiro é um terminal de tinta eletrônica usado à noite tem
ainda menos desculpa. *Correção:* como as cores já estão todas em token, é uma segunda
tabela de valores, não um redesenho. (Crédito: `prefers-reduced-motion` **está**
tratado, em `styles.css:147`.)

---

## 5. Coerência entre as superfícies

1. **O seletor de origem é outro controle.** No app (`mobile/09-criar.png`) são quatro
   quadrados com ícone acima do rótulo; no web (`web/05-criar.png`) são quatro pílulas
   largas só com texto. Mesmo passo, mesmo produto, duas linguagens. *Correção:* um
   segmented control em ambos, com ícone + rótulo.
2. **A cor do numeral não segue regra comum** (§3.5): lavanda no app, menta ou tinta no
   web, para as mesmas métricas.
3. **A previsão de 14 dias** desenha os 14 slots no app e só os dias com dado no web.
4. **A escolha de conteúdo do T5** usa switch no app e checkbox no web.
5. **A legenda da barra do baralho** tem pontos de cor no app e não tem no web.
6. **Escalas de espaçamento e raio incompatíveis** (§4.3) — a causa estrutural de 1 a 5.
7. **A data.** `mobile/05-hoje` diz "SEGUNDA, 31 DE AGOSTO"; `web/03-hoje` diz
   "QUARTA-FEIRA, 2 DE SETEMBRO". Um abrevia o dia da semana, o outro não. Detalhe — mas
   é o primeiro texto das duas telas equivalentes.
8. **Configurações têm escopos diferentes** (§4.2).

O que *segura* a coerência hoje é a paleta e a tipografia, que são as mesmas. O que a
quebra é tudo que está uma camada abaixo: métrica, componente e estado.

---

## 6. Divergências de estilo (categoria B)

Aqui não há erro; há escolha. Aponto o custo de cada uma.

**Literata nos títulos e nos numerais.** Legítima e bem defendida. A própria Apple usa
serifa quando a leitura é o produto: **News usa New York nas manchetes** e SF nos
metadados — exatamente a divisão que o Mnemos faz. *Ganha:* uma identidade reconhecível
à distância; um "3" em Literata é Mnemos, em SF é qualquer app. *Perde:* Literata não
tem a otimização de legibilidade em corpo pequeno da SF Text, então precisa mesmo ficar
restrita a título e numeral — o que já acontece. **Manter.** O único ajuste técnico é
ligar figuras tabulares (§3.1), que é categoria A.

**JetBrains Mono nas sobrancelhas.** *Ganha:* o eco do terminal de tinta eletrônica na
tela do celular é boa ideia de marca — o objeto e o app parecem parentes. *Perde:* mono
em caixa alta com tracking é o recurso mais "startup de dev tools" do repertório atual,
e usado em oito papéis diferentes (§3.1) vira ruído. **Manter a escolha, restringir o
uso.**

**Paleta lavanda/menta/coral.** *Ganha:* diferenciação real num mercado de azuis, e a
regra semântica (lavanda = app, menta = firme, coral = vence) é boa e está escrita.
*Perde:* três hues análogos-frios com pouquíssima variação de croma fazem toda a
interface ter o mesmo peso — não há nada quente nem escuro para ancorar a leitura, e o
coral, que deveria ser o alarme, é pastel demais para alarmar. **Manter a paleta,
aumentar o contraste interno:** superfícies mais neutras, acento mais saturado (§3.5).

**Filete de 2 px acima das colunas de features na landing.** Recurso editorial (Wired,
Monocle), não Apple. *Ganha:* cara de publicação, o que combina com a serifa. *Perde:*
na apple.com a separação entre colunas de feature é feita por espaço e por imagem, nunca
por régua — a régua envelhece a página. **Escolha do time.**

**A paywall invertida em lavanda escuro (`mobile/17`).** Isto **é** um padrão Apple — a
aba Fitness+ dentro do Fitness e as telas do Apple One invertem para escuro justamente
no upsell. É a tela mais bem resolvida do app. **Manter.**

**Barra de abas opaca em vez de flutuante com material.** O iOS recente usa uma barra de
abas em cápsula flutuante com material translúcido; aqui é uma faixa opaca `#F0EDF6` com
filete. *Ganha:* previsibilidade e paridade com Android. *Perde:* parece iOS 15, não iOS
26. **Escolha do time** — mas se o alvo é "parecer Apple hoje", esta é a divergência mais
datada da lista.

Não dá para julgar movimento, transição nem retorno tátil a partir de PNGs estáticos;
nada aqui é afirmação sobre esses eixos.

---

## 7. O que já está bom

- **`tokens.dart` e `typography.dart` são melhores que o produto que eles pintam.** Cor
  nomeada por papel, decisões de contraste registradas com o número medido, e o
  comentário explicando por que `#FCFBFE` virou branco puro. Isso é trabalho de time
  maduro. Boa parte deste relatório é sobre telas que **não estão usando** o que esses
  arquivos oferecem.
- **A escrita.** "Teto para não acordar com quatrocentas", "Estudar de madrugada conta
  para o dia anterior", "Nada vira card sem você aprovar, um por vez". É o registro em
  que a Apple escreve: específico, sem hype, e explica a consequência. Não mexer.
- **`mobile/17-cota-esgotada.png`** é a tela mais forte do conjunto — inversão, lista
  numerada com ordinais em mono, dois planos, um CTA. Corrigido o contraste da letra
  miúda e a posição do selo, está pronta.
- **A régua de etapas de `mobile/14-gerando.png`**: menta preenchido = feito, contorno
  lavanda = agora, contorno cinza = depois. Vocabulário correto, igual ao do progresso de
  restauração do iCloud.
- **Um card por vez em `mobile/16-revisar`** é o modelo de interação certo para
  aprovação, e a régua de segmentos no topo dá a noção de fim.
- **O alinhamento de colunas de `web/03-hoje.png`**: a coluna esquerda (198–578 px
  exibidos) e a soma dos dois cards da direita (199–376 + 393–578) fecham no mesmo topo e
  na mesma base, e os dois títulos de seção abaixo compartilham a linha. Isso é cuidado
  real, e é raro.
- **`prefers-reduced-motion` tratado** e anel de foco preservado, com um comentário
  explicando por quê (`styles.css:147` e a regra `:focus-visible`). A maioria dos times
  remove o anel de foco por estética; aqui ele foi defendido por escrito.

---

## Estado da aplicação (2 de setembro de 2026)

Os achados abaixo foram corrigidos e as capturas desta pasta já mostram o
resultado. O que **não** foi feito está no fim, com o motivo.

### Fundação, nas duas superfícies

- **Uma escala de espaçamento só** — `4 / 8 / 12 / 16 / 24 / 40`, escrita com os
  mesmos números em `MnemosSpacing` e em `--mn-gap-*`. Os degraus inventados no
  meio das telas (`md + 2`, `xxl - 4`) voltaram para os degraus que existem.
- **Três raios** — `control 12 / card 20 / sheet 28`, também nos dois arquivos.
  `MnemosRadii.nested(pai, padding)` dá o raio de um filho, com piso de 6.
- **Curvatura contínua** — `squircle()` em `tokens.dart` troca
  `RoundedRectangleBorder` por `ContinuousRectangleBorder` em todo card, botão e
  ladrilho do app, incluindo o respingo do `InkWell`.
- **Escala tipográfica colapsada** — de vinte e um tamanhos para
  `44 / 34 / 28 / 22 / 19 / 17 / 15 / 13 / 12`, sem pares duplicados.
- **Figuras tabulares** em todo estilo de numeral: o painel deixa de tremer
  quando "19 dias" vira "20 dias".
- **Superfícies neutralizadas e na lightness da Apple** — canvas `#f2f1f6`,
  afundado `#ebeaf1`, card branco puro nas duas superfícies. A marca continua
  lavanda; ela só parou de pintar o papel de parede.

  Cinza e não branco de propósito: todas as telas do Mnemos são cards e listas,
  a família do `systemGroupedBackground` do iOS (`#F2F2F7`) e não a do
  `systemBackground` (`#FFFFFF`). Ajustes, Saúde e Fitness são cinza com linhas
  brancas por cima — num fundo branco os grupos brancos somem.

  A primeira passada deixou o canvas em `#f7f6f9`, que dava **1,08:1** contra o
  card branco onde o agrupado da Apple dá **1,12:1** — o card se destacava menos
  aqui do que se destacaria num app da Apple. `#f2f1f6` fecha em 1,124:1. E o
  web tinha os cards em `#fcfbfe` contra o branco puro do app: mesma superfície,
  dois valores; agora é o mesmo nos dois.
- **Cor do numeral pela métrica**, não pela tela: retenção é menta, memória
  acumulada é lavanda, vencimento é coral escuro, contagem neutra é tinta. A
  regra está escrita em `tokens.dart` e em `styles.css`.
- **Modo escuro no web** — tabela completa sob `prefers-color-scheme: dark`.

### Aplicativo

- Ação destrutiva em `destructive` (9,22:1) e não no coral de vencimento
  (2,39:1) — `account_screen.dart`. Todo coral usado como tinta virou `dueText`.
- Primário desabilitado = primário a 30%, com rótulo a 60%: mantém a cor, perde
  a promessa. "Escrever um card à mão" virou `OutlinedButton` da mesma altura.
- "Descartar" não quebra mais no meio da palavra (`IntrinsicWidth` + piso de
  120 px, `maxLines: 1`).
- Ladrilhos 2-up com altura igual e conteúdo distribuído (`IntrinsicHeight` +
  `spaceBetween`).
- `StatusScreen`: estado vazio, erro e falha centrados no espaço disponível,
  com glifo de 48 pt e ação secundária de largura de texto. Aplicado à
  biblioteca vazia, ao dispositivo sem terminal e à geração que falhou — esta
  última ganhou o glifo em `destructive` que não tinha.
- Ajustes virou lista agrupada: `SettingGroup` + `SettingRow`, superfície por
  grupo, separador recuado até a coluna do texto, altura mínima de 48 e **ícone
  em todas as linhas** — o `icon` é parâmetro obrigatório justamente para a
  coluna não pular.
- Barra de abas com par vazado/preenchido no ativo, glifo 26 e rótulo 11.
- Ícones com texto dentro removidos: `picture_as_pdf` → `description_outlined`,
  `fiber_new` → `playlist_add_outlined`.
- Interruptor desligado em cinza neutro (`switchOff`).
- Chevron de voltar deslocado −6 px para dividir a margem com o título grande.
- Campos do editor preenchidos, com foco de 2 px.
- Letra miúda da paywall em `#C6C5DE` e alinhada à esquerda; selo "-30%" dentro
  do cartão, ao lado do rótulo do plano.
- Anel menta da cota virou glifo — o anel menta significa "etapa concluída".
- `numeralUnit` em 15 pt sans e cor secundária: a unidade parou de disputar com
  o número.

### Web

- Barra lateral some em `/estudar` (removida do DOM — `[hidden]` perde para o
  `display: flex` declarado). "Configurações" recebe a pílula de ativo.
- "Ver a resposta" preenchida, 52 px de altura, largura máxima de 420 px
  centrada: a única ação da tela virou a mais pesada dela.
- Conteúdo com medida única de 1180 px, centrada.
- Previsão de catorze dias com os catorze slots; dia zerado em trilho de 3 px.
- Gráfico de revisões com linha de base tracejada e o valor do pico rotulado;
  dia zerado na cor do trilho.
- Ladrilhos de progresso com conteúdo distribuído, sem vazio no rodapé.
- Dispositivo: dois níveis de superfície em vez de três, e interruptor no lugar
  do checkbox — o mesmo controle do app, com o estado sob o nome.
- Biblioteca com pontos de legenda (o de "total" em `--mn-accent-60`, que passa
  3:1) e busca limitada a 480 px.
- Seletor de origem com ícone acima do rótulo, como os azulejos do app.
- Prévia com máscara de degradê em vez do terceiro card a 55% de opacidade.
- Atalhos de teclado alinhados à direita.
- Login centrado nos dois eixos; CTA da landing em pílula de 17 px.
- "Apagar a conta" em `--mn-destructive` e não no grau "errei"; desabilitados
  com a mesma regra do app.
- Data sem `-feira`, como no aplicativo.
- Uma seção "No aplicativo" nomeia os cinco ajustes que só existem lá.

### O que não foi feito

**Modo escuro no aplicativo.** O relatório diz que "as cores já estão todas em
token, é uma segunda tabela de valores". Isso vale para o web, onde as cores são
custom properties do CSS e a troca é uma tabela sob `prefers-color-scheme`. No
Flutter não vale: `MnemosColors` é `static const`, e há **302 referências
diretas em 23 arquivos**, 29 delas dentro de construtores `const`. Um modo
escuro de verdade exige trocar todas por resolução via contexto
(`ThemeExtension`), remover os `const` que isso quebra em cascata, e reconferir
as 25 capturas. É um refatoramento estrutural de tamanho diferente do resto
desta lista, e entregá-lo pela metade — tema escuro com widgets pintando cor
clara na mão — produz um modo escuro quebrado, que é pior que nenhum.

**Troca do set de ícones por SF Symbols.** O relatório aponta, com razão, que os
glifos Material têm peso ótico errado ao lado da Literata. Mas o SF Symbols é
licenciado para uso em plataformas Apple e não pode ser empacotado num app
Flutter que também roda no Android. O que dava para fazer foi feito: os dois
ícones com letras desenhadas dentro saíram, e a barra de abas ganhou o par
vazado/preenchido. Um set próprio, desenhado para casar com a Literata, é
trabalho de ilustração e não de código.

**Imagem do T5 na dobra da landing.** Depende de uma fotografia ou render do
aparelho, que não existe no repositório.

### Onde discordo do relatório

**"A tela de gerando tem 400 px de vazio acima do conteúdo" (§3.4).** O bloco já
está centrado (`mainAxisAlignment: center` dentro do `Expanded`), e o vazio é
simétrico: ~350 px acima e ~340 px abaixo. O diagnóstico de ancoragem não
procede; o que existe é ar, e ar simétrico numa tela de espera é intencional.
Deixei como está.

**"'Vencendo hoje 3' e '2 entram na fila' na mesma tela" (§3.4).** A correção
sugerida é o cabeçalho contar 2, como o ladrilho. Não fiz: o cabeçalho rotula a
**lista logo abaixo dele**, que tem três cards; escrever 2 ali faria o rótulo
mentir sobre o próprio conteúdo. Os dois números medem coisas diferentes — o
balde tem 3 vencendo, a fila aceita 2 por causa do teto diário — e a linha de
apoio já diz exatamente isso ("2 entram na fila de hoje; o resto espera o teto
diário abrir"). O problema apontado é real, mas a solução proposta troca uma
ambiguidade por um erro.

