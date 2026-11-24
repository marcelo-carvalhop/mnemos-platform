import 'package:flutter/widgets.dart';

/// Identidade visual Mnemos — design system "Marinho"
/// (`docs/design/DESIGN-SYSTEM.md`).
///
/// As cores são nomeadas pelo papel que cumprem, não pelo tom que têm. Uma
/// tela que escreve `MnemosColors.due` continua correta se o coral virar outro
/// tom amanhã; uma que escreve `Color(0xFFE5876C)` vira dívida no mesmo dia.
///
/// Regra de leitura da paleta: **marinho é a ação, azul é o destaque, menta é
/// o que já está firme, coral é o que vence, e o gradiente azul→rosa é só da
/// IA.** A cor é rara de propósito — é a raridade que a torna um sinal.
///
/// Os valores são exatamente os de `--mn-*` em `app/web/src/styles.css`: a
/// mesma decisão é a mesma cor nas duas superfícies.
abstract final class MnemosColors {
  // -------------------------------------------------------------------------
  // Superfícies
  // -------------------------------------------------------------------------

  /// O fundo de toda tela. Quase branco, levemente frio.
  static const canvas = Color(0xFFFAFBFC);

  /// Cards e blocos. Branco, separado da tela pela borda fina ([line]) e não
  /// por sombra: sombra fica para o que flutua.
  static const raised = Color(0xFFFFFFFF);

  /// Barra de abas, faixas e o fundo de uma prévia dentro de um card.
  static const sunken = Color(0xFFF5F7F9);

  /// Blocos de aviso e o estado selecionado discreto.
  static const soft = Color(0xFFECF0F3);

  /// Destaque azul bem claro — o selecionado que carrega a cor de destaque.
  static const softer = Color(0xFFEFF3FA);

  /// Fundo do ícone quadrado no cartão "novo baralho".
  static const tint = Color(0xFFECF0F3);

  // -------------------------------------------------------------------------
  // Linhas
  // -------------------------------------------------------------------------

  /// Divisórias internas: a linha entre duas fileiras de um mesmo card.
  static const hairline = Color(0xFFECF0F3);

  /// Bordas de card — o que separa uma superfície da outra.
  static const line = Color(0xFFE0E6EC);

  /// Contorno de botão secundário e de campo.
  static const outline = Color(0xFFC9D3DD);

  /// Trilhos de barra de progresso e medidores.
  static const track = Color(0xFFE0E6EC);

  /// Trilho de interruptor desligado.
  static const switchOff = Color(0xFFE0E6EC);

  // -------------------------------------------------------------------------
  // Texto — contraste sobre [canvas]: 16,2 · 9,4 · 5,6 · 4,8
  // -------------------------------------------------------------------------

  /// Títulos e qualquer texto que precise ser lido primeiro.
  static const ink = Color(0xFF0F1C3D);

  /// Corpo longo — o verso de um card, uma explicação.
  static const inkSoft = Color(0xFF1E2A47);

  /// Texto de apoio que ainda se lê sem esforço.
  static const muted = Color(0xFF39445F);

  /// Sobrancelhas, legendas e o rótulo de uma aba inativa.
  static const faint = Color(0xFF53687B);

  /// O degrau mais claro que ainda é texto: dicas de campo.
  static const fainter = Color(0xFF5E7285);

  /// A segunda linha que esmaece num título grande. 3,2:1 — **só** em texto
  /// de 24 px ou mais, onde a WCAG pede 3:1.
  static const quiet = Color(0xFF7D8FA2);

  /// Decoração: grade, trilho, ícone que espera. Nunca texto a ser lido.
  static const deco = Color(0xFF9BAEC0);

  /// Texto sobre marinho ou sobre o gradiente da IA.
  static const onDark = Color(0xFFFAFBFC);

  /// O bloco-âncora do Hoje: branco a 66%, borda de vidro a 10% de marinho e
  /// grade fina a 6%. Sem gradiente de cor — o marinho fica no numeral.
  static const panel = Color(0xA8FFFFFF);
  static const panelLine = Color(0x1A0F1C3D);
  static const panelGrid = Color(0x0F0F1C3D);

  // -------------------------------------------------------------------------
  // Marinho — a ação
  // -------------------------------------------------------------------------

  /// Botões primários, aba ativa, seleção.
  static const primary = Color(0xFF0F1C3D);

  /// Destaque azul: link, foco, dado em gráfico, memória acumulada.
  /// 6,4:1 sobre a tela.
  static const primaryDeep = Color(0xFF2F5BA6);

  /// O mesmo azul, nos mapas de calor.
  static const primaryDeeper = Color(0xFF2F5BA6);

  /// Fundo da tela de assinatura, onde o app inverte.
  static const primaryDark = Color(0xFF0F1C3D);
  static const primaryDarkLine = Color(0xFF26324F);

  /// Escala clara, para gráficos e barras de intensidade.
  static const primary60 = Color(0xFF9BAEC0);
  static const primary40 = Color(0xFFC9D3DD);

  /// Texto secundário sobre marinho.
  static const onPrimaryMuted = Color(0xFFC9D3DD);
  static const onPrimaryFaint = Color(0xFF9BAEC0);
  static const onPrimarySoft = Color(0xFFE0E6EC);

  // -------------------------------------------------------------------------
  // Azul — o destaque
  // -------------------------------------------------------------------------

  static const highlight = Color(0xFF2F5BA6);
  static const highlightSoft = Color(0xFFEFF3FA);

  // -------------------------------------------------------------------------
  // Menta — o que já está firme
  // -------------------------------------------------------------------------

  /// Etapas concluídas, cards maduros, retenção saudável. Só preenchimento.
  static const settled = Color(0xFF6FAE92);

  /// Menta como tinta, sobre fundo claro.
  static const settledDeep = Color(0xFF2E6B50);

  // -------------------------------------------------------------------------
  // Coral — o que vence
  // -------------------------------------------------------------------------

  /// Badges de vencimento, barras de "vencendo". **Só como preenchimento**:
  /// como tinta o coral não passa contraste. Quem escreve em coral usa
  /// [dueText].
  static const due = Color(0xFFE5876C);

  /// Texto sobre coral.
  static const onDue = Color(0xFF4A1F12);

  /// Coral como tinta: "2 vencendo", "aguardando sincronização".
  static const dueText = Color(0xFFA2432A);

  /// Fundo e borda do card que está vencendo hoje.
  static const dueSurface = Color(0xFFFCF3EF);
  static const dueLine = Color(0xFFF3D9CF);

  // -------------------------------------------------------------------------
  // Os quatro graus de revisão
  // -------------------------------------------------------------------------

  /// Errei, difícil, bom, fácil — **sempre nesta ordem**.
  ///
  /// A ordem carrega significado e nunca é alfabética nem por frequência. Os
  /// valores são exatamente os de `--mn-again/hard/good/easy` no cliente web.
  static const again = Color(0xFFA2432A);
  static const againSurface = Color(0xFFFCF3EF);
  static const hard = Color(0xFF39445F);
  static const hardSurface = Color(0xFFF5F7F9);
  static const good = Color(0xFF2E6B50);
  static const goodSurface = Color(0xFFEEF7F2);
  static const easy = Color(0xFF2F5BA6);
  static const easySurface = Color(0xFFEFF3FA);

  /// Bordas tingidas dos graus, quando o botão é desenhado com contorno
  /// (o card de exemplo das boas-vindas, os graus da web).
  static const goodLine = Color(0xFFCFE6DA);
  static const easyLine = Color(0xFFD3DEF0);

  /// A cor de um numeral é da **métrica**, não da tela.
  ///
  /// Retenção é menta ([settledDeep]), vencimento é coral escuro ([dueText]),
  /// memória acumulada é azul ([primaryDeep]) e contagem sem juízo é tinta
  /// ([ink]). A mesma regra vale no cliente web.

  // -------------------------------------------------------------------------
  // Destrutivo — o que apaga
  // -------------------------------------------------------------------------

  /// Apagar um baralho, apagar a conta. Separado do coral de propósito: o
  /// coral ensina "tem coisa para fazer hoje"; encontrá-lo depois num botão
  /// que destrói dados desfaz a lição.
  static const destructive = Color(0xFF8A1F0E);

  // -------------------------------------------------------------------------
  // IA
  // -------------------------------------------------------------------------

  /// As duas pontas do gradiente da IA. Não usar soltas: ver [MnemosGradients.ai].
  static const aiStart = Color(0xFF6A7CF0);
  static const aiEnd = Color(0xFFE14FB8);
}

/// O único gradiente do sistema.
abstract final class MnemosGradients {
  /// **Exclusivo da IA.** Onde ele aparece, é a IA agindo — gerar cards, a
  /// tela de geração. Usá-lo como enfeite apaga esse sinal.
  static const ai = LinearGradient(
    begin: Alignment.bottomRight,
    end: Alignment.topLeft,
    colors: [MnemosColors.aiStart, MnemosColors.aiEnd],
  );
}

/// A escala de espaçamento do design, toda em múltiplos de 4.
///
/// **Os mesmos seis degraus do web** (`--mn-gap-*` em `app/web/src/styles.css`).
/// Um degrau novo entra nos dois arquivos ou não entra em nenhum.
abstract final class MnemosSpacing {
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
  static const double xxl = 40;

  /// Margem lateral padrão das telas.
  static const double screen = 20;
}

/// Os raios do design: 4 dentro de um bloco, 8 no bloco. Botões, chips e
/// selos são pílula ([StadiumBorder]), não um raio.
///
/// Para qualquer elemento aninhado o raio interno é [nested]: raio do pai menos
/// o padding. É o que deixa as duas curvas paralelas.
abstract final class MnemosRadii {
  /// Campos e elementos **dentro** de um bloco.
  static const double control = 4;

  /// Todo card e ladrilho.
  static const double card = 8;

  /// O objeto central da tela: o card em revisão, a folha que sobe.
  static const double sheet = 8;

  /// Barras de progresso e segmentos finos.
  static const double bar = 3;

  /// O raio de um filho, dado o raio do pai e o espaço entre os dois.
  ///
  /// O piso de 2 evita que um padding grande devolva um retângulo duro; ele
  /// nunca passa do próprio pai.
  static double nested(double parent, double padding) =>
      (parent - padding).clamp(parent < 2 ? parent : 2, parent);
}

/// Cantos contínuos — a *squircle*.
///
/// `RoundedRectangleBorder` emenda a reta na curva de repente; a superelipse
/// distribui a curvatura ao longo da aresta. O raio da
/// [ContinuousRectangleBorder] lê mais fechado que o do arredondado comum para
/// o mesmo número — daí o fator.
ContinuousRectangleBorder squircle(double radius, {BorderSide side = BorderSide.none}) =>
    ContinuousRectangleBorder(borderRadius: BorderRadius.circular(radius * 1.4), side: side);
