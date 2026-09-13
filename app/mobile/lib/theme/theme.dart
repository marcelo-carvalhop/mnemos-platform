import 'package:flutter/material.dart';

import 'tokens.dart';
import 'typography.dart';

/// O tema, montado a partir dos tokens.
///
/// Tudo aqui é derivado de [MnemosColors] e [MnemosText]. Nenhuma cor ou
/// tamanho literal deve aparecer neste arquivo — se aparecer, é sinal de que
/// falta um token.
ThemeData buildTheme() {
  const scheme = ColorScheme.light(
    primary: MnemosColors.primary,
    onPrimary: MnemosColors.onDark,
    primaryContainer: MnemosColors.soft,
    onPrimaryContainer: MnemosColors.primaryDeep,
    secondary: MnemosColors.settled,
    onSecondary: MnemosColors.onDark,
    secondaryContainer: MnemosColors.softer,
    onSecondaryContainer: MnemosColors.settledDeep,
    // §5 — coral não é decoração: significa "isto vence". Serve tanto de
    // terciária quanto de cor de alerta, porque no vocabulário do design elas
    // são a mesma ideia.
    tertiary: MnemosColors.due,
    onTertiary: MnemosColors.onDue,
    error: MnemosColors.dueText,
    onError: MnemosColors.onDue,
    errorContainer: MnemosColors.dueSurface,
    onErrorContainer: MnemosColors.onDue,
    surface: MnemosColors.canvas,
    onSurface: MnemosColors.ink,
    surfaceContainerLowest: MnemosColors.raised,
    surfaceContainerLow: MnemosColors.canvas,
    surfaceContainer: MnemosColors.sunken,
    outline: MnemosColors.line,
    outlineVariant: MnemosColors.hairline,
  );

  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: MnemosColors.canvas,
    canvasColor: MnemosColors.canvas,
    dividerColor: MnemosColors.hairline,
    splashFactory: InkSparkle.splashFactory,

    // O `fontFamily` de topo é a rede de segurança: qualquer texto que escape
    // do textTheme cai em Public Sans em vez de cair na fonte do sistema — que
    // é o que fazia os títulos saírem como tarjas pretas nas capturas.
    fontFamily: MnemosFonts.sans,

    textTheme: const TextTheme(
      displayLarge: MnemosText.display,
      displayMedium: MnemosText.displaySmall,
      headlineLarge: MnemosText.screenTitle,
      headlineMedium: MnemosText.screenTitleWrapped,
      headlineSmall: MnemosText.sectionTitle,
      titleLarge: MnemosText.cardTitle,
      titleMedium: MnemosText.itemTitle,
      titleSmall: MnemosText.labelSmall,
      bodyLarge: MnemosText.bodyLong,
      // A fonte de verdade do `DefaultTextStyle` do Material: é dela que todo
      // `Text` com estilo inline herda a família.
      bodyMedium: MnemosText.body,
      bodySmall: MnemosText.bodySmall,
      labelLarge: MnemosText.label,
      labelMedium: MnemosText.labelSmall,
      labelSmall: MnemosText.eyebrow,
    ),

    appBarTheme: const AppBarTheme(
      backgroundColor: MnemosColors.canvas,
      foregroundColor: MnemosColors.ink,
      surfaceTintColor: MnemosColors.canvas,
      elevation: 0,
      scrolledUnderElevation: 0,
      // O design alinha títulos à esquerda: a coluna de leitura começa na
      // margem, não no meio da tela.
      centerTitle: false,
      titleTextStyle: MnemosText.cardTitle,
      iconTheme: IconThemeData(color: MnemosColors.muted),
    ),

    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: MnemosColors.primary,
        foregroundColor: MnemosColors.onDark,
        // Desabilitado mantém a **cor** e perde a promessa: é o primário a 30%,
        // não um retângulo cinza. Cinza preenchido pesava mais que o secundário
        // habilitado ao lado — o elemento mais forte da tela era o que não
        // funciona, e a pessoa mirava nele. A App Store faz o mesmo com
        // "OBTER": ele perde a cor, não ganha um preenchimento novo.
        disabledBackgroundColor: Color(0x4D6E6FA0),
        disabledForegroundColor: Color(0x99FFFFFF),
        minimumSize: const Size.fromHeight(54),
        shape: squircle(MnemosRadii.control),
        textStyle: MnemosText.labelLarge,
      ),
    ),

    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: MnemosColors.primaryDeep,
        disabledForegroundColor: MnemosColors.faint,
        minimumSize: const Size.fromHeight(54),
        side: const BorderSide(color: MnemosColors.outline),
        shape: squircle(MnemosRadii.control),
        textStyle: MnemosText.label,
      ),
    ),

    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: MnemosColors.primary,
        textStyle: MnemosText.labelSmall,
      ),
    ),

    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: MnemosColors.raised,
      hintStyle: MnemosText.hint,
      labelStyle: MnemosText.bodySmall,
      contentPadding: const EdgeInsets.symmetric(
        horizontal: MnemosSpacing.lg,
        vertical: MnemosSpacing.md,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(MnemosRadii.control),
        borderSide: const BorderSide(color: MnemosColors.hairline),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(MnemosRadii.control),
        borderSide: const BorderSide(color: MnemosColors.primary, width: 1.4),
      ),
    ),

    checkboxTheme: CheckboxThemeData(
      fillColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected) ? MnemosColors.primary : null,
      ),
      checkColor: const WidgetStatePropertyAll(MnemosColors.onDark),
      side: const BorderSide(color: MnemosColors.outline),
    ),

    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected)
            ? MnemosColors.onDark
            : MnemosColors.raised,
      ),
      // Desligado em cinza neutro, não no lavanda do trilho de progresso: um
      // trilho tingido lê como "meio ligado", e o estado precisa ser legível
      // sem depender de cor.
      trackColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected)
            ? MnemosColors.primary
            : MnemosColors.switchOff,
      ),
      trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
    ),

    sliderTheme: const SliderThemeData(
      activeTrackColor: MnemosColors.primary,
      inactiveTrackColor: MnemosColors.track,
      thumbColor: MnemosColors.primary,
      overlayColor: Color(0x226E6FA0),
    ),

    progressIndicatorTheme: const ProgressIndicatorThemeData(
      color: MnemosColors.primary,
      linearTrackColor: MnemosColors.track,
      circularTrackColor: MnemosColors.hairline,
    ),

    dividerTheme: const DividerThemeData(
      color: MnemosColors.hairline,
      thickness: 1,
      space: 1,
    ),

    snackBarTheme: SnackBarThemeData(
      backgroundColor: MnemosColors.ink,
      contentTextStyle: MnemosText.body.copyWith(color: MnemosColors.onDark),
      behavior: SnackBarBehavior.floating,
      shape: squircle(MnemosRadii.control),
    ),

    dialogTheme: DialogThemeData(
      backgroundColor: MnemosColors.raised,
      surfaceTintColor: MnemosColors.raised,
      titleTextStyle: MnemosText.cardTitle,
      contentTextStyle: MnemosText.bodySmall,
      shape: squircle(MnemosRadii.card),
    ),

    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: MnemosColors.raised,
      surfaceTintColor: MnemosColors.raised,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(MnemosRadii.sheet),
        ),
      ),
    ),
  );
}
