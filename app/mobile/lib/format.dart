/// Formatação de datas em português, sem `intl`.
///
/// O app precisa de duas frases — "TERÇA, 31 DE AGOSTO" e "há 2 h" — e ambas
/// cabem em trinta linhas. Trazer o `intl` inteiro, com os seus dados de
/// localização, para produzir duas strings seria pagar um pacote por um par de
/// listas de nomes.
library;

const _weekdays = [
  'segunda-feira',
  'terça-feira',
  'quarta-feira',
  'quinta-feira',
  'sexta-feira',
  'sábado',
  'domingo',
];

const _months = [
  'janeiro',
  'fevereiro',
  'março',
  'abril',
  'maio',
  'junho',
  'julho',
  'agosto',
  'setembro',
  'outubro',
  'novembro',
  'dezembro',
];

/// "terça, 31 de agosto" — a sobrancelha da tela Hoje, que o widget põe em
/// caixa alta.
///
/// O dia da semana vem curto porque a linha é estreita: "terça-feira, 31 de
/// agosto" em caixa alta e mono não cabe em 390 pt.
String longDate(DateTime date) {
  final weekday = _weekdays[date.weekday - 1].split('-').first;
  return '$weekday, ${date.day} de ${_months[date.month - 1]}';
}

/// "há 2 h", "há 5 min", "agora" — a idade de uma sincronização.
///
/// Corta em dias: "há 40 dias" já não é uma informação acionável, e a tela
/// prefere dizer a data nesse caso.
String? relativeSince(DateTime? moment, DateTime now) {
  if (moment == null) return null;

  final elapsed = now.difference(moment);
  if (elapsed.isNegative || elapsed.inMinutes < 1) return 'agora';
  if (elapsed.inMinutes < 60) return 'há ${elapsed.inMinutes} min';
  if (elapsed.inHours < 24) return 'há ${elapsed.inHours} h';
  if (elapsed.inDays == 1) return 'ontem';
  if (elapsed.inDays < 30) return 'há ${elapsed.inDays} dias';
  return 'em ${moment.day} de ${_months[moment.month - 1]}';
}

/// "10 cards", "1 card" — plural sem sufixo colado entre parênteses.
String plural(int count, String singular, String pluralForm) =>
    '$count ${count == 1 ? singular : pluralForm}';
