# Capturas de tela

Todas as telas do aplicativo móvel e do cliente web, renderizadas a partir do
código deste repositório. As imagens são **geradas por script**, não tiradas à
mão: qualquer pessoa consegue reproduzi-las byte a byte, e regerá-las depois de
mudar a interface é um comando só.

| Pasta | O quê | Como | Quantas |
|---|---|---|---|
| [`mobile/`](mobile/) | App Flutter (`app/mobile`) | goldens do `flutter test` | 29 |
| [`web/`](web/) | Cliente web (`app/web/dist`) | Chrome headless | 11 |

Nenhuma das duas precisa de emulador, dispositivo físico, Docker, backend ou
conta real.

---

## O que **não** está aqui

O **terminal T5** (`firmware/t5`) desenha em tinta eletrônica e não tem
framebuffer que se possa exportar por software. Registrar aquelas telas exige
fotografar o aparelho.

---

## `mobile/` — aplicativo Flutter

### Como foi gerado

[`app/mobile/test_screenshots/`](../app/mobile/test_screenshots/) monta cada
tela com o tema real do app, um banco SQLite em memória já povoado e um backend
falso, e grava o resultado como golden file:

```bash
cd app/mobile
flutter test test_screenshots --update-goldens
```

Roda em ~30 s. O diretório fica **fora** de `test/`, então `flutter test` normal
não o executa — as imagens são documentação, e um arquivo de documentação que
quebra a CI porque um padding mudou é um arquivo que ninguém atualiza.

### O que é real e o que é fixture

Real: o widget, o tema (`lib/theme.dart`), toda a lógica de tela, os textos, e
os números derivados de dados (intervalos, retenção, sequência, mapa de calor).

Fixture ([`harness.dart`](../app/mobile/test_screenshots/harness.dart)):

- **Relógio fixo** em 31/08/2026 15:00 (America/Sao_Paulo), para que datas e
  intervalos saiam idênticos em toda execução.
- **Dados semeados**: dois baralhos (*Redes de Computadores*, 10 cards;
  *Direito Constitucional*, 6) e ~21 dias de log de revisões com duas faltas
  propositais e mistura realista de notas. É daí que vêm os 19 dias seguidos,
  os 86% de retenção e o mapa de calor.
- **Backend simulado** por `MockClient`, respondendo cota, jobs de geração,
  fila de aprovação e resumo do terminal.
- **Sem plugins de plataforma**: keychain, notificações e BLE são substituídos
  por implementações vazias.
- **Fontes**: o `flutter test` não embarca glifos, então a Roboto e a fonte de
  ícones são carregadas do cache do SDK. O tema também recebe um `fontFamily`
  explícito nos dois pontos em que instala um `DefaultTextStyle` do zero
  (título da AppBar e `FilledButton`) — no celular esses estilos herdam a fonte
  do sistema; no ambiente de teste cairiam na fonte sem glifos e sairiam como
  tarjas pretas.

Formato: 400×880 pt a 2x → **800×1760 px**.

### As telas

| # | Arquivo | Tela | Artboard |
|---|---|---|---|
| 01 | `01-onboarding-boas-vindas.png` | `OnboardingScreen` | 10 |
| 02 | `02-onboarding-o-que-estudar.png` | `OnboardingScreen` | — |
| 03 | `03-onboarding-meta-diaria.png` | `OnboardingScreen` | — |
| 04 | `04-onboarding-geracao-gratis.png` | `OnboardingScreen` | — |
| 05 | `05-hoje.png` | `TodayScreen` (aba 1) | 01 |
| 06 | `06-biblioteca-vazia.png` | `DecksScreen`, conta nova | 02 |
| 07 | `07-biblioteca.png` | `DecksScreen` (aba 2) | 02 |
| 08 | `08-busca.png` | `DecksScreen`, busca embutida | 02 |
| 09 | `09-criar.png` | `CreateScreen` (aba 3), origem tópico | 04 |
| 09b | `09b-criar-texto-colado.png` | `CreateScreen`, origem texto colado | — |
| 10 | `10-progresso.png` | `ProgressScreen` (aba 4) | 07 |
| 11 | `11-baralho.png` | `DeckDetailScreen` | 03 |
| 12 | `12-editor-card-novo.png` | `EditorScreen`, vazio | — |
| 13 | `13-editor-card-preenchido.png` | `EditorScreen`, preenchido | — |
| 14 | `14-gerando.png` | `GeneratingScreen` | 05 |
| 15 | `15-geracao-falhou.png` | `GeneratingScreen`, falha | 05 |
| 16 | `16-revisar-cards-gerados.png` | `ApprovalScreen` | 06 |
| 17 | `17-cota-esgotada.png` | `PaywallScreen` | 09 |
| 18 | `18-assinatura.png` | `SubscriptionScreen` | — |
| 19 | `19-configuracoes.png` | `SettingsScreen`, topo | — |
| 20 | `20-configuracoes-continuacao.png` | `SettingsScreen`, rolada | — |
| 21 | `21-seus-dados.png` | `AccountScreen` | — |
| 22 | `22-dispositivo-sem-terminal.png` | `DeviceScreen`, sem terminal | 08 |
| 23 | `23-dispositivo-conectado.png` | `DeviceScreen`, T5 pareado | 08 |
| 24 | `24-conectar-terminal.png` | `TerminalScreen`, pareamento | — |
| 25 | `25-estudar.png` | `StudyScreen`, pergunta | — |
| 26 | `26-estudar-resposta.png` | `StudyScreen`, resposta revelada | — |
| 27 | `27-outros-modos.png` | `ModesScreen` | — |
| 28 | `28-simulado.png` | `SimuladoSetupScreen` | — |

As quatro últimas vieram da `integration/v0.6-multiclient` — estudo pelo
telefone e os modos alternativos — e receberam a camada visual do sistema nesta
branch. Não têm artboard porque o canvas foi desenhado antes de elas existirem.

As telas marcadas com "—" não têm artboard: foram desenhadas extrapolando a
linguagem do design (serifa Literata nos títulos, sobrancelhas em JetBrains
Mono, cards em `#FCFBFE` sobre `#F6F4FA`, ação principal fixa no rodapé).

A tela de estudo não aparece porque **não existe no app**: o estudo acontece no
terminal físico. O app cria conteúdo, organiza, administra o dispositivo e
mostra o progresso.

### O que mudou no redesign

Estas imagens são do app já refeito conforme o canvas `Mnemos App.dc.html`.
Três mudanças estruturais, nas palavras do próprio design — *"barra de abas no
lugar do menu, a Início vira o painel do dia, e cada tela ganha um bloco-âncora
no topo em vez de começar com uma lista solta"*. Na prática:

- **A Home virou a aba Hoje.** Era um índice de quatro links; agora responde o
  que vence hoje, em quais baralhos, e se o T5 está com esse conteúdo.
- **Quatro abas fixas** — Hoje, Biblioteca, Criar, Progresso.
- **Telas que se fundiram:** "Gerar por tópico" + "Capturar material" viraram a
  aba Criar; "Dispositivo" + "Sincronização" viraram uma tela só; a busca saiu
  de um destino separado e virou o campo no topo da Biblioteca; "Gerenciar
  baralho" virou o detalhe do baralho, com os cards à vista e as ações
  destrutivas no menu.
- **Aprovar cards passou a ser um de cada vez**, em vez de uma lista rolável.

**Duas lacunas conscientes**, ambas por falta de dado e não de desenho: o
artboard 08 mostra bateria do T5 e um espelho do card que está na tela dele —
nenhum dos dois existe no protocolo do terminal. E o artboard 06 tem um botão
"Editar" na revisão que a API de geração não suporta (ela só aceita aprovar ou
descartar), então ele não foi implementado.

---

## `web/` — cliente web

### O cliente web

As imagens são do web **já redesenhado** conforme o canvas `Mnemos Web.dc.html`,
com a mesma paleta e a mesma tipografia do aplicativo.

Uma ressalva sobre a branch: o código-fonte do web vive em `origin/dev`
(commit `6011801`), não em `main`. Para trabalhar nele eu o trouxe para a árvore
com `git checkout origin/dev -- app/web`, sem trocar de branch. Se você recriar
o ambiente do zero, precisa repetir esse passo antes de rodar o build.

Requisitos: Node 24 (o `.nvmrc` pede 24.19) e `npm ci` em `app/web/`.

    cd app/web && npx ng build --configuration development

### Como foi gerado

```bash
tools/screenshots/capture_web.sh
```

O script sobe [`web_fixture_server.py`](../tools/screenshots/web_fixture_server.py),
que serve o build estático com fallback de SPA e:

- injeta uma sessão em `localStorage` (`mnemos.access` / `mnemos.refresh` /
  `mnemos.device`) antes do app iniciar, para alcançar as telas internas sem
  backend nem conta — `?anon=1` desativa a injeção e rende as telas deslogadas;
- responde `/v1/*` com dados de fixture, caso a camada de dados venha a ser
  ligada no futuro;
- aperta um botão de origem quando a rota traz `?clique=<rótulo>`. As quatro
  origens de Criar são estado do componente e não rota, e o Chrome em
  `--screenshot` não clica em nada. Fica no servidor de fixture de propósito:
  uma porta de entrada que só o fotógrafo usa não deveria existir no produto.

Depois dispara o Chrome headless em cada rota. Formato: 1440×900 CSS a 2x →
**2880×1800 px**.

### As telas

| # | Arquivo | Rota | Estado |
|---|---|---|---|
| 01 | `01-landing.png` | `/` | página pública |
| 02 | `02-entrar.png` | `/entrar` | login |
| 03 | `03-hoje.png` | `/hoje` | bloco-âncora, fila do dia, sequência e previsão |
| 04 | `04-biblioteca.png` | `/biblioteca` | filtros e grade de baralhos |
| 05 | `05-criar.png` | `/criar` | origem tópico |
| 05b | `05b-criar-texto-colado.png` | `/criar` | origem texto colado |
| 05c | `05c-criar-pdf.png` | `/criar` | origem PDF, zona de arquivo |
| 06 | `06-estudar.png` | `/estudar` | sessão de revisão |
| 07 | `07-progresso.png` | `/progresso` | métricas |
| 08 | `08-dispositivo.png` | `/dispositivo` | nenhum terminal pareado |
| 09 | `09-configuracoes.png` | `/configuracoes` | assinatura, retenção, dados |

Ficaram de fora `/biblioteca/:deckId`, `/gerar/:jobId` e `/aprovar/:jobId`: as
três exigem um id que a captura teria de inventar.

**O que o redesign do web mudou.** A troca de tokens em `src/styles.css`
repintou o cliente inteiro de uma vez — não havia nenhuma cor fixa fora do
`:root`, o que é mérito de quem escreveu aquele arquivo. Sobre essa base, as
sete telas ganharam a estrutura do canvas:

- **Barra lateral** — contador de vencimento em coral, total da biblioteca e o
  bloco de estado no rodapé.
- **Hoje** — bloco-âncora com a fila repartida por baralho, duas colunas,
  memória + retenção, régua da semana e previsão de catorze dias.
- **Biblioteca** — filtros, grade de três colunas, barra de três segmentos com
  legenda e as ações "Estudar N" / "Abrir".
- **Criar** — duas colunas, com a prévia do formato à direita; quantidades e
  nível em chips; as origens de material visíveis.
- **Estudar** — régua de segmentos por card, "N certos · N errados", pergunta em
  serifa grande e os quatro graus com o intervalo antes da escolha.
- **Progresso** — filtro de período, o bloco-âncora como primeiro cartão da
  fileira e duas colunas para o gráfico e as distribuições.
- **Dispositivo** — moldura do aparelho com a memória, cartão de sincronização e
  o conteúdo escolhido, com a distinção entre desejado e reportado.

A captura de **Estudar** mostra a pergunta ainda virada para baixo: o Chrome
headless não digita, e revelar a resposta depende de uma tecla. Os quatro botões
de grau aparecem depois desse toque.

O bloco lateral do canvas mostra o estado do **T5**; a web não tem cliente de
terminal para isso — o endpoint `/v1/terminals` existe e alimenta a tela
Dispositivo, mas nada reporta bateria nem o card que está na tela do aparelho —
então o bloco mostra o estado da sincronização, que é o que ela de fato sabe.

A rota `/estudar` existe porque estudar pelo navegador é uso previsto: o Mnemos
tem várias superfícies de estudo — terminal, celular e web — e todas gravam no
mesmo log de revisões. Ver [`app/web/README.md`](../app/web/README.md).
