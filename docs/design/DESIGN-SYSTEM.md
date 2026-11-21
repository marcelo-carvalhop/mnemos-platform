# Design system do Mnemos — "Marinho"

Aprovado em 2026-11-21. Substitui a paleta G2 (lavanda e coral) e o documento
[`web-brief/CORES.md`](web-brief/CORES.md).

A referência visual é a landing (`app/web/src/app/features/landing/`). Os
tokens vivem em dois arquivos, com os mesmos valores:

| Superfície | Arquivo |
|---|---|
| Web | `app/web/src/styles.css` (`--mn-*`, claro e escuro) |
| App | `app/mobile/lib/theme/tokens.dart`, `typography.dart`, `theme.dart` |

Um valor novo entra nos dois arquivos ou não entra em nenhum.

## Princípios

1. **Marinho sobre quase branco.** A interface é azul-marinho, com cinzas
   azulados entre o texto e o fundo. A cor é rara de propósito: é a raridade
   que a torna um sinal.
2. **Borda, não sombra.** Cards são brancos com borda fina. Sombra só no que
   flutua: menu suspenso, prévia em destaque.
3. **Pílula para agir, canto reto para conter.** Botões, chips e selos são
   pílula; blocos têm canto de 8 px e o que vive dentro deles, 4 px.
4. **O gradiente azul→rosa é só da IA.** Onde ele aparece, é a IA que vai
   agir: gerar cards, a tela de geração, o plano Com IA. Usá-lo como enfeite
   apaga o sinal.
5. **Serifa só no conteúdo do card.** A pergunta e a resposta são algo para
   ler; o resto é interface.

## Cor

### Papéis

| Papel | Claro | Escuro | Uso |
|---|---|---|---|
| Tela | `#FAFBFC` | `#0B1429` | fundo |
| Card | `#FFFFFF` | `#111C36` | blocos, sempre com borda |
| Afundado | `#F5F7F9` | `#071022` | barra de abas, prévia dentro de card |
| Suave | `#ECF0F3` | `#17233F` | selecionado discreto, aviso |
| Linha | `#E0E6EC` | `#1E2A47` | borda de card |
| Contorno | `#C9D3DD` | `#39445F` | botão secundário, campo |
| **Ação (marinho)** | `#0F1C3D` | `#E8EDF3` | botão principal, aba ativa, seleção |
| **Destaque (azul)** | `#2F5BA6` | `#8FB0EE` | link, foco, sobrancelha de seção, dado em gráfico |
| Firme (menta) | `#6FAE92` / tinta `#2E6B50` | — | retenção, maduro |
| Vence (coral) | `#E5876C` / tinta `#A2432A` | — | vencimento; coral puro só como preenchimento |
| Destrutivo | `#8A1F0E` | `#EE9F86` | apagar; nunca o coral |

### Texto

Contraste medido sobre `#FAFBFC` (WCAG 2.1):

| Token | Hex | Contraste | Uso |
|---|---|---|---|
| texto | `#0F1C3D` | 16,2:1 | títulos, corpo |
| apoio | `#39445F` | 9,4:1 | texto secundário forte |
| legenda | `#53687B` | 5,6:1 | sobrancelhas, legendas |
| dica | `#5E7285` | 4,8:1 | o tom mais claro permitido em texto pequeno |
| esmaecido | `#7D8FA2` | 3,2:1 | **só** a segunda linha de título com 24 px ou mais |
| decoração | `#9BAEC0` | 2,2:1 | grade, trilho, ícone que espera; nunca texto |

### Os quatro graus

Sempre nesta ordem: errei, difícil, bom, fácil.

| Grau | Tinta | Fundo |
|---|---|---|
| Errei | `#A2432A` | `#FCF3EF` |
| Difícil | `#39445F` | `#F5F7F9` |
| Bom | `#2E6B50` | `#EEF7F2` |
| Fácil | `#2F5BA6` | `#EFF3FA` |

### A cor de um numeral é da métrica

Retenção é menta, vencimento é coral, memória acumulada é azul e contagem
sem juízo é tinta. O mesmo número não muda de cor ao mudar de tela.

### Gradientes

Só estes dois:

| Nome | Valor | Onde |
|---|---|---|
| Herói | `linear-gradient(-62deg, #2F5BA6, #0F1C3D)` | o bloco-âncora de Hoje e de Progresso |
| IA | `linear-gradient(-55deg, #6A7CF0, #E14FB8)` | gerar cards, tela de geração, plano Com IA |

## Tipografia

| Família | Uso |
|---|---|
| **Geist** | interface, títulos, numerais |
| **Geist Mono** | sobrancelhas em caixa alta, atalhos, dados que alinham (`3/12`, `28 d`) |
| **Literata** | só o conteúdo do card: pergunta, resposta, prévia |

- Títulos: peso 500 e tracking de −0,03 em. Um título de seção pode ter
  duas linhas, com a segunda em esmaecido.
- Numerais: peso 400, grandes e apertados (−0,03 em).
- Sobrancelhas: Geist Mono de 12 px, caixa alta, tracking de 0,08 a 0,12 em.
- Botões: peso 500.

No app as fontes são empacotadas (`app/mobile/assets/fonts/`, todas OFL); na
web vêm do Google Fonts.

## Forma e espaço

| Token | Valor | Uso |
|---|---|---|
| raio de controle | 4 px | campo, item dentro de bloco |
| raio de card | 8 px | card, ladrilho, folha |
| pílula | 999 px / `StadiumBorder` | botão, chip, selo |
| espaçamento | 4 · 8 · 12 · 16 · 24 · 40 | a única escala |

Sombras:

| Uso | Valor |
|---|---|
| prévia em destaque | `0 8px 32px rgba(15,28,61,.10)` |
| menu | `0 8px 24px rgba(15,28,61,.24)` |

## Marca

O símbolo são dois cards sobrepostos: um contornado em marinho, e o da frente
preenchido em azul, deslocado para cima e para a direita. É um card que volta.

- Web: `<svg class="mark">`.
- App: `BrandMark` em `lib/ui/primitives.dart`.

A palavra "Mnemos" vem em Geist 600, com tracking de −0,02 em.

## Componentes que carregam o sistema

| Componente | Web | App |
|---|---|---|
| Botão principal | `.primary` (marinho, pílula) | `FilledButton` pelo tema |
| Botão da IA | `.primary` em Criar, `.create` na Biblioteca | `AiButton` |
| Bloco-herói | `.anchor` (gradiente herói) | `HeroCard` |
| Selo de vencimento | `.badge` | `DueBadge` |
| Menu no celular | `.topbar`, `.tabbar` e a folha `.sheet` (abaixo de 900 px) | `AppShell`, `MnemosTabBar` e a folha do "Mais" |
| Chip | `.chips button`, `.counts button` (pílula) | `MnemosChip` e `chipTheme` (pílula) |

O menu do celular é o mesmo nas duas superfícies:
- Em cima, um cabeçalho curto com a marca e o estado da sincronização.
- Na base, Hoje, Biblioteca, Criar (botão marinho no meio), Progresso e Mais.
- A aba ativa ganha uma pílula atrás do ícone, e Hoje mostra os cards que vencem em coral.
- "Mais" abre uma folha com a sincronização, Dispositivo, Configurações e Sair.

## Inspiração

A estrutura visual partiu do design system público do netlex.io: marinho e
cinzas azulados, Geist, cantos de 4 e 8 px, pílulas e o gradiente reservado
para IA. A marca, os textos e os componentes são do Mnemos.
