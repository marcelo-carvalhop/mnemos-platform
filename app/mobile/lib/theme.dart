/// Ponto de entrada do tema.
///
/// O sistema de design vive em `lib/theme/`: [theme/tokens.dart] tem a paleta
/// e as escalas, [theme/typography.dart] os estilos por papel, e
/// [theme/theme.dart] monta o `ThemeData` a partir dos dois.
///
/// Este arquivo existe para `main.dart` e para quem quiser o conjunto inteiro
/// num import só. Uma tela normalmente importa apenas os tokens e a tipografia
/// de que precisa.
library;

export 'theme/theme.dart';
export 'theme/tokens.dart';
export 'theme/typography.dart';
