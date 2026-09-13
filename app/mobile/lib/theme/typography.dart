import 'package:flutter/widgets.dart';

import 'tokens.dart';

/// As três famílias do design, e nada além delas.
abstract final class MnemosFonts {
  /// Títulos e numerais. É a assinatura da identidade — um número grande em
  /// Literata é reconhecivelmente Mnemos; o mesmo número em sans não é.
  static const serif = 'Literata';

  /// Corpo e rótulos de interface.
  static const sans = 'Public Sans';

  /// Sobrancelhas e dados tabulares, onde o avanço fixo é o ponto: `3/12` e
  /// `28 d` precisam alinhar entre linhas.
  static const mono = 'JetBrains Mono';
}

/// Os estilos do design, nomeados pelo papel.
///
/// Nenhuma tela deve escrever `fontSize:` na mão. Antes deste arquivo havia
/// 129 `TextStyle` inline e dezesseis tamanhos diferentes espalhados por vinte
/// telas, o que quer dizer que a hierarquia tipográfica não existia — cada
/// tela reinventava a sua.
///
/// Os valores vêm dos artboards. `letterSpacing` foi convertido de `em` para
/// pixels no tamanho de cada estilo, que é como o Flutter mede.
abstract final class MnemosText {
  // -------------------------------------------------------------------------
  // Títulos — Literata
  // -------------------------------------------------------------------------

  /// A primeira linha de uma tela de aba: "Hoje", "Biblioteca", "Progresso".
  static const screenTitle = TextStyle(
    fontFamily: MnemosFonts.serif,
    fontSize: 28,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.3,
    color: MnemosColors.ink,
  );

  /// Título de tela que ocupa duas linhas — o nome de um baralho.
  static const screenTitleWrapped = TextStyle(
    fontFamily: MnemosFonts.serif,
    fontSize: 22,
    fontWeight: FontWeight.w600,
    height: 1.15,
    color: MnemosColors.ink,
  );

  /// A promessa do onboarding e o convite da assinatura: texto que é a tela.
  static const display = TextStyle(
    fontFamily: MnemosFonts.serif,
    fontSize: 34,
    fontWeight: FontWeight.w600,
    height: 1.1,
    letterSpacing: -0.9,
    color: MnemosColors.ink,
  );

  static const displaySmall = TextStyle(
    fontFamily: MnemosFonts.serif,
    fontSize: 28,
    fontWeight: FontWeight.w600,
    height: 1.2,
    color: MnemosColors.ink,
  );

  /// "Seus baralhos", "O que vem por aí".
  static const sectionTitle = TextStyle(
    fontFamily: MnemosFonts.serif,
    fontSize: 17,
    fontWeight: FontWeight.w600,
    color: MnemosColors.ink,
  );

  /// O nome de um baralho dentro do seu card.
  static const cardTitle = TextStyle(
    fontFamily: MnemosFonts.serif,
    fontSize: 19,
    fontWeight: FontWeight.w600,
    color: MnemosColors.ink,
  );

  /// A frente de um card em revisão — o objeto central daquela tela.
  static const prompt = TextStyle(
    fontFamily: MnemosFonts.serif,
    fontSize: 22,
    fontWeight: FontWeight.w600,
    height: 1.35,
    color: MnemosColors.ink,
  );

  // -------------------------------------------------------------------------
  // Numerais — Literata, porque o número é o conteúdo
  // -------------------------------------------------------------------------

  /// O número do bloco-herói: quantos cards vencem agora.
  static const heroNumeral = TextStyle(
    fontFamily: MnemosFonts.serif,
    fontFeatures: [FontFeature.tabularFigures()],
    fontSize: 44,
    fontWeight: FontWeight.w600,
    height: 1,
    color: MnemosColors.onDark,
  );

  /// "1 mês" de memória acumulada.
  static const numeralLarge = TextStyle(
    fontFamily: MnemosFonts.serif,
    fontFeatures: [FontFeature.tabularFigures()],
    fontSize: 28,
    fontWeight: FontWeight.w600,
    height: 1,
    color: MnemosColors.ink,
  );

  /// O número de um ladrilho de estatística.
  static const numeral = TextStyle(
    fontFamily: MnemosFonts.serif,
    fontFeatures: [FontFeature.tabularFigures()],
    fontSize: 28,
    fontWeight: FontWeight.w600,
    color: MnemosColors.ink,
  );

  /// Números lado a lado numa linha de três — cards, vencendo, dias médios.
  static const numeralSmall = TextStyle(
    fontFamily: MnemosFonts.serif,
    fontFeatures: [FontFeature.tabularFigures()],
    fontSize: 22,
    fontWeight: FontWeight.w600,
    color: MnemosColors.ink,
  );

  /// A unidade que acompanha um numeral: "mês", "dias", "%".
  /// A legenda de um numeral: "dias", "%", "cards".
  ///
  /// 15 sobre um numeral de 28–44 dá à unidade cerca de um terço do corpo do
  /// número, que é a proporção que o resumo do Fitness usa entre "512" e
  /// "CAL". Antes ela tinha 26 contra 38 — 68% — e a linha lia "1 mês" como
  /// duas palavras de peso igual em vez de um número com legenda. Sans e não
  /// serifa pelo mesmo motivo: a Literata é do número, não do rótulo.
  static const numeralUnit = TextStyle(
    fontFamily: MnemosFonts.sans,
    fontSize: 15,
    fontWeight: FontWeight.w600,
    letterSpacing: 0.6,
    color: MnemosColors.faint,
  );

  // -------------------------------------------------------------------------
  // Sobrancelhas e dados — JetBrains Mono
  // -------------------------------------------------------------------------

  /// `VENCENDO AGORA`, `SEQUÊNCIA`, `FRENTE`. Sempre em caixa alta — quem
  /// aplica a caixa é o widget [Eyebrow], não este estilo.
  ///
  /// Três coisas mudaram de uma vez, porque eram o mesmo defeito visto de três
  /// ângulos: a cor era `faint` no seu valor antigo (3,83:1, reprova a WCAG),
  /// o corpo era 11px — tamanho de texto normal, não de rótulo grande — e o
  /// tracking de 0,16em separava tanto as letras que a palavra deixava de ser
  /// uma palavra. Caixa alta em mono já é sinal suficiente de sobrancelha;
  /// 0,08em basta para arejá-la.
  static const eyebrow = TextStyle(
    fontFamily: MnemosFonts.mono,
    fontSize: 12,
    letterSpacing: 0.96, // 0.08em
    color: MnemosColors.muted,
  );

  /// A sobrancelha dentro de um ladrilho apertado.
  ///
  /// Mesmo corpo da irmã maior — 12px é o piso de legibilidade, não um luxo
  /// que um ladrilho estreito possa dispensar. O que encolhe é o tracking.
  static const eyebrowSmall = TextStyle(
    fontFamily: MnemosFonts.mono,
    fontSize: 12,
    letterSpacing: 0.72, // 0.06em
    color: MnemosColors.muted,
  );

  /// `3/12`, `28 d`, `74%` — números que alinham entre linhas.
  static const mono = TextStyle(
    fontFamily: MnemosFonts.mono,
    fontFeatures: [FontFeature.tabularFigures()],
    fontSize: 12,
    color: MnemosColors.muted,
  );

  static const monoSmall = TextStyle(
    fontFamily: MnemosFonts.mono,
    fontFeatures: [FontFeature.tabularFigures()],
    fontSize: 12,
    color: MnemosColors.faint,
  );

  // -------------------------------------------------------------------------
  // Corpo e rótulos — Public Sans
  // -------------------------------------------------------------------------

  /// O texto padrão do app.
  static const body = TextStyle(
    fontFamily: MnemosFonts.sans,
    fontSize: 15,
    color: MnemosColors.ink,
  );

  /// Corpo longo, com entrelinha maior: o verso de um card, um parágrafo de
  /// explicação.
  static const bodyLong = TextStyle(
    fontFamily: MnemosFonts.sans,
    fontSize: 15,
    height: 1.55,
    color: MnemosColors.inkSoft,
  );

  /// Texto de apoio sob um título.
  static const bodySmall = TextStyle(
    fontFamily: MnemosFonts.sans,
    fontSize: 13,
    height: 1.5,
    color: MnemosColors.muted,
  );

  /// A legenda de uma linha de baralho: "10 cards · 3 maduros".
  static const caption = TextStyle(
    fontFamily: MnemosFonts.sans,
    fontSize: 12,
    color: MnemosColors.faint,
  );

  /// O nome de uma coisa numa lista.
  static const itemTitle = TextStyle(
    fontFamily: MnemosFonts.sans,
    fontSize: 15,
    fontWeight: FontWeight.w600,
    color: MnemosColors.ink,
  );

  /// A pergunta de um card numa lista — mais apertada, porque quebra em duas
  /// linhas com frequência.
  static const itemPrompt = TextStyle(
    fontFamily: MnemosFonts.sans,
    fontSize: 13,
    fontWeight: FontWeight.w600,
    height: 1.35,
    color: MnemosColors.ink,
  );

  /// O texto de um botão.
  static const label = TextStyle(
    fontFamily: MnemosFonts.sans,
    fontSize: 15,
    fontWeight: FontWeight.w600,
  );

  /// O botão de ação principal, no rodapé de uma tela.
  static const labelLarge = TextStyle(
    fontFamily: MnemosFonts.sans,
    fontSize: 15,
    fontWeight: FontWeight.w600,
  );

  /// Botões dentro de blocos e chips.
  static const labelSmall = TextStyle(
    fontFamily: MnemosFonts.sans,
    fontSize: 13,
    fontWeight: FontWeight.w500,
  );

  /// O rótulo de uma aba. 12px é o corpo que o Material 3 especifica para a
  /// barra de navegação — a navegação primária não é lugar de economizar
  /// pixel.
  static const tab = TextStyle(
    fontFamily: MnemosFonts.sans,
    fontSize: 11,
  );

  /// O texto que um campo mostra enquanto está vazio.
  ///
  /// **Sempre sans, nunca a serifa do conteúdo.** Um placeholder desenhado com
  /// a mesma tipografia do que se digita ali é indistinguível de um campo
  /// preenchido, e a pessoa apaga o exemplo achando que apagou o próprio
  /// texto. A forma é que separa os dois, não só a cor.
  static const hint = TextStyle(
    fontFamily: MnemosFonts.sans,
    fontSize: 15,
    height: 1.4,
    color: MnemosColors.fainter,
  );
}
