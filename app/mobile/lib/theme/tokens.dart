import 'package:flutter/widgets.dart';

/// Identidade visual Mnemos — paleta G2, lavanda e coral.
///
/// As cores são nomeadas pelo papel que cumprem, não pelo tom que têm. Uma
/// tela que escreve `MnemosColors.due` continua correta se o coral virar outro
/// tom amanhã; uma que escreve `Color(0xFFE08A72)` vira dívida no mesmo dia.
///
/// Regra de leitura da paleta, como o design a define: **lavanda é o app,
/// menta é o que já está firme, coral é o que vence.** O coral nunca aparece
/// como enfeite — ele significa que algo pede ação hoje.
abstract final class MnemosColors {
  // -------------------------------------------------------------------------
  // Superfícies
  // -------------------------------------------------------------------------

  /// O fundo de toda tela.
  ///
  /// Cinza, e não branco: todas as telas do Mnemos são cards e listas, que é a
  /// família do `systemGroupedBackground` do iOS (`#F2F2F7`) e não a do
  /// `systemBackground` (`#FFFFFF`). Ajustes, Saúde e Fitness são cinza com
  /// linhas brancas por cima — num fundo branco os grupos brancos somem, e é o
  /// contraste entre os dois que faz o card existir. Branco fica reservado a
  /// superfície de leitura, que aqui é o card, não a tela.
  ///
  /// A lightness é a de `#F2F2F7`, com a lavanda da marca no lugar do azul da
  /// Apple. Antes era `#F7F6F9`: 1,08:1 contra o card branco, onde o agrupado
  /// da Apple dá 1,12:1 — o card se destacava **menos** aqui do que se
  /// destacaria num app da Apple.
  static const canvas = Color(0xFFF2F1F6);

  /// Cards e blocos que se destacam do fundo.
  ///
  /// Branco puro, e não o lavanda quase branco de antes: `#FCFBFE` sobre a
  /// tela dava 1,06:1, o que quer dizer que o card não existia — o que se via
  /// era só a borda. A diferença ainda é sutil, como o design quer, mas agora
  /// é uma diferença.
  static const raised = Color(0xFFFFFFFF);

  /// Barra de abas e faixas que afundam em vez de subir.
  ///
  /// Desce junto com o canvas: afundado tem de continuar mais escuro que a
  /// tela, senão a barra de abas para de afundar.
  static const sunken = Color(0xFFEBEAF1);

  /// Blocos de aviso e destaques discretos (cota, moldura do terminal).
  static const soft = Color(0xFFEFECF7);
  static const softer = Color(0xFFEAE7F3);

  /// Fundo do ícone quadrado no cartão "novo baralho".
  static const tint = Color(0xFFE7E4F2);

  // -------------------------------------------------------------------------
  // Linhas
  // -------------------------------------------------------------------------

  /// Divisórias internas: a linha entre duas fileiras de um mesmo card.
  static const hairline = Color(0xFFE5E1EE);

  /// Bordas de card e a moldura do aparelho — o que separa uma superfície da
  /// outra. Mais fechada que [hairline] de propósito: é ela que faz o card ter
  /// contorno num telefone com brilho baixo.
  static const line = Color(0xFFDEDAE8);

  /// Contorno de botão secundário.
  static const outline = Color(0xFFCBC7DC);

  /// Trilhos de barra de progresso e medidores.
  static const track = Color(0xFFD5D1E3);

  /// Trilho de interruptor desligado. Cinza sem tinta: o lavanda claro que
  /// estava aqui lia como "meio ligado".
  static const switchOff = Color(0xFFE3E1E8);

  // -------------------------------------------------------------------------
  // Texto
  // -------------------------------------------------------------------------

  /// Títulos e qualquer texto que precise ser lido primeiro.
  static const ink = Color(0xFF232130);

  /// Corpo longo — o verso de um card, uma explicação.
  static const inkSoft = Color(0xFF2E2C3B);

  /// Texto de apoio que ainda se lê sem esforço.
  static const muted = Color(0xFF4C4A5C);

  /// Sobrancelhas, legendas e o rótulo de uma aba inativa.
  ///
  /// Era `#7C7A8C`, que dava 3,83:1 sobre a tela — reprova o mínimo de 4,5:1
  /// da WCAG para texto normal, e era justamente a cor de todo o texto pequeno
  /// do app. A escala inteira subiu um degrau: legenda não é enfeite, é texto.
  static const faint = Color(0xFF5A5868);

  /// O que está deliberadamente em segundo plano — dicas de campo, um ícone
  /// que espera. Era `#908FA0` (2,91:1); continua sendo o degrau mais claro da
  /// escala, mas agora um que ainda se lê.
  static const fainter = Color(0xFF6A6878);

  /// Texto sobre lavanda, menta ou coral escuro.
  static const onDark = Color(0xFFF6F4FA);

  // -------------------------------------------------------------------------
  // Lavanda — a cor do aplicativo
  // -------------------------------------------------------------------------

  /// Botões primários, bloco-herói, aba ativa.
  static const primary = Color(0xFF6E6FA0);

  /// Rótulos sobre fundo claro e o estado pressionado do primário.
  static const primaryDeep = Color(0xFF55568A);

  /// Variante do primaryDeep usada nos mapas de calor.
  static const primaryDeeper = Color(0xFF575893);

  /// Fundo da tela de assinatura, onde o app inverte.
  static const primaryDark = Color(0xFF3B3B63);
  static const primaryDarkLine = Color(0xFF2E2E52);

  /// Escala clara, para gráficos e barras de intensidade.
  static const primary60 = Color(0xFFA9A9CE);
  static const primary40 = Color(0xFFC9C8E1);

  /// Texto secundário sobre fundo lavanda escuro.
  static const onPrimaryMuted = Color(0xFFCDCDE6);
  static const onPrimaryFaint = Color(0xFFC6C5DE);
  static const onPrimarySoft = Color(0xFFE1E1F3);

  // -------------------------------------------------------------------------
  // Menta — o que já está firme
  // -------------------------------------------------------------------------

  /// Etapas concluídas, cards maduros, retenção saudável.
  static const settled = Color(0xFF7FA894);

  /// Texto sobre fundo claro quando ele precisa carregar o sentido de menta.
  static const settledDeep = Color(0xFF4A6B5C);

  // -------------------------------------------------------------------------
  // Coral — o que vence
  // -------------------------------------------------------------------------

  /// Badges de vencimento, barras de "vencendo", o cursor de digitação.
  ///
  /// **Só como preenchimento.** Como tinta sobre a tela clara o coral dá
  /// 2,39:1 — a palavra "vencendo" era a coisa menos legível da tela que a
  /// anunciava. Quem precisa escrever em coral usa [dueText].
  static const due = Color(0xFFE08A72);

  /// Texto sobre coral. Escuro de propósito: o badge é pequeno e precisa de
  /// contraste real, não de branco sobre pastel.
  static const onDue = Color(0xFF48261B);

  /// Coral como tinta: "2 vencendo", "aguardando sincronização". 6,28:1 sobre
  /// a tela, 6,65:1 sobre um card.
  static const dueText = Color(0xFF9A3D22);

  /// Fundo e borda do card que está vencendo hoje.
  static const dueSurface = Color(0xFFF7F1EE);
  static const dueLine = Color(0xFFEBD9D1);

  // -------------------------------------------------------------------------
  // Destrutivo — o que apaga
  // -------------------------------------------------------------------------

  /// Apagar um baralho, apagar a conta.
  ///
  /// Separado do coral de propósito. O coral ensina "tem coisa para fazer
  /// hoje"; encontrá-lo depois num botão que destrói dados desfaz a lição.
  // -------------------------------------------------------------------------
  // Os quatro graus de revisão
  // -------------------------------------------------------------------------

  /// Errei, difícil, bom, fácil — **sempre nesta ordem**.
  ///
  /// A ordem carrega significado e nunca é alfabética nem por frequência. Os
  /// valores são exatamente os de `--mn-again/hard/good/easy` no cliente web:
  /// a mesma decisão é o mesmo botão nas duas superfícies, e alguém que
  /// estudou pelo navegador não deve reaprender as cores no telefone.
  ///
  /// Entraram com o estudo pelo telefone, que veio da `integration/v0.6`. Até
  /// então o app não tinha tela de revisão e a paleta não precisava deles.
  static const again = Color(0xFF9E4A2C);
  static const againSurface = Color(0xFFF7F1EE);
  static const hard = Color(0xFF55568A);
  static const hardSurface = Color(0xFFEFECF7);
  static const good = Color(0xFF4A6B5C);
  static const goodSurface = Color(0xFFE8EFEA);
  static const easy = Color(0xFF6E6FA0);
  static const easySurface = Color(0xFFE1E1F3);

  /// A cor de um numeral é da **métrica**, não da tela.
  ///
  /// Retenção é menta ([settledDeep]), vencimento é coral escuro ([dueText]),
  /// memória acumulada é lavanda ([primaryDeep]) e contagem sem juízo é tinta
  /// ([ink]). Quatro telas com quatro critérios fazem o mesmo "98%" mudar de
  /// cor ao mudar de tela — e aí a cor deixa de informar. A mesma regra vale
  /// no cliente web (`--mn-*` em `app/web/src/styles.css`).

  /// Este tom é mais escuro e mais fechado — 9,22:1 sobre a tela, e o mesmo
  /// número com [onDark] por cima quando ele é o preenchimento.
  static const destructive = Color(0xFF7A2410);
}

/// A escala de espaçamento do design, toda em múltiplos de 4.
///
/// Existe para que o próximo `SizedBox` seja escolhido de uma lista curta em
/// vez de inventado. O `screen` é a margem lateral de toda tela.
///
/// **Os mesmos seis degraus do web** (`--mn-gap-*` em `app/web/src/styles.css`).
/// Antes eram oito aqui e seis lá, com só três em comum: `18` e `26` do web não
/// existiam no app, `16`/`20`/`24` do app não existiam no web. O efeito era que
/// nenhum padding de card podia coincidir entre as duas superfícies — não por
/// descuido de quem escreveu a tela, mas por construção. Um degrau novo entra
/// nos dois arquivos ou não entra em nenhum.
abstract final class MnemosSpacing {
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
  static const double xxl = 40;

  /// Margem lateral padrão das telas (artboards 01–10).
  static const double screen = 20;
}

/// Os raios do design.
///
/// Três, e não os oito de antes (`3, 12, 14, 16, 18, 20, 22, 24`). Oito valores
/// entre 12 e 24 são oito valores que ninguém distingue e que, somados, fazem
/// cada bloco parecer desenhado por uma pessoa diferente.
///
/// Para qualquer elemento aninhado o raio interno é [nested]: raio do pai menos
/// o padding. É o que deixa as duas curvas paralelas em vez de uma caixa dentro
/// da outra.
abstract final class MnemosRadii {
  /// Chips, campos e botões **dentro** de um bloco.
  static const double control = 12;

  /// Todo card e ladrilho.
  static const double card = 20;

  /// O objeto central da tela: o card em revisão, o bloco-herói.
  static const double sheet = 28;

  /// Barras de progresso e segmentos finos, que são pílulas de altura pequena.
  static const double bar = 3;

  /// O raio de um filho, dado o raio do pai e o espaço entre os dois.
  ///
  /// Curvas concêntricas: um raio interno de 14 dentro de um externo de 22 com
  /// 20 pt de padding produz um canto visivelmente errado. O piso de 6 evita
  /// que um padding grande zere o canto e devolva um retângulo duro.
  static double nested(double parent, double padding) =>
      (parent - padding).clamp(6, parent);
}

/// Cantos contínuos — a *squircle*.
///
/// `RoundedRectangleBorder` emenda a reta na curva de repente; a superelipse
/// distribui a curvatura ao longo da aresta, e é metade da razão pela qual uma
/// superfície da Apple parece torneada de um bloco só. O Flutter expõe isso em
/// [ContinuousRectangleBorder], mas o raio dela lê mais fechado que o do
/// arredondado comum para o mesmo número — daí o fator.
ContinuousRectangleBorder squircle(double radius, {BorderSide side = BorderSide.none}) =>
    ContinuousRectangleBorder(
      borderRadius: BorderRadius.circular(radius * 1.4),
      side: side,
    );
