// Gera os fixtures que o cliente web usa para provar que sua implementação de
// FSRS concorda com a do aplicativo.
//
//     dart run tool/dump_fixtures.dart > ../../../web/src/app/core/fsrs-fixtures.json
//
// Por que isso existe: §3 diz que o log de revisões é a verdade e `card_state`
// é um cache reconstruível — reconstruído *identicamente* em qualquer lugar.
// O app usa o pacote `fsrs` do pub, a web usa `ts-fsrs` do npm. São duas
// implementações independentes do mesmo algoritmo, e nada além de um teste
// impede que divirjam. Se divergirem, as duas superfícies discordam sobre o
// que vence hoje — e a pessoa vê um número no telefone e outro no navegador
// sem nenhuma pista de qual está certo.

import 'dart:convert';

import 'package:domain/domain.dart';
import 'package:scheduler/scheduler.dart';

const _params = FsrsParams(weights: defaultFsrsWeights);

/// Sequências escolhidas para cobrir os caminhos que se comportam diferente:
/// aprendizado, graduação, recaída (que incrementa `lapses`) e reaprendizado.
const _sequences = <String, List<int>>{
  'tudo bom': [3, 3, 3, 3],
  'sempre facil': [4, 4, 4],
  'sempre errei': [1, 1, 1],
  'recaida depois de graduar': [3, 3, 4, 1, 3],
  'dificil no meio': [3, 2, 3, 2, 4],
  'um so': [3],
  'errei primeiro': [1, 3, 3],
  'alternando': [1, 4, 1, 4],
};

void main() {
  final start = DateTime.utc(2026, 1, 1, 9);
  final out = <Map<String, Object?>>[];

  for (final entry in _sequences.entries) {
    // Um dia entre revisões: intervalos reais divergiriam entre as duas
    // implementações por acumular arredondamento, e o que se quer medir aqui é
    // o algoritmo, não a aritmética de datas do teste.
    final history = <Review>[];
    for (var i = 0; i < entry.value.length; i++) {
      history.add(Review(
        id: 'r${i.toString().padLeft(3, '0')}',
        cardId: 'c1',
        reviewedAt: start.add(Duration(days: i)),
        grade: Grade.fromValue(entry.value[i]),
        source: ReviewSource.standard,
      ));
    }

    final state = Scheduler.replay(history, const [], _params, cardId: 'c1');
    out.add({
      'name': entry.key,
      'grades': entry.value,
      'startUtc': start.toIso8601String(),
      'expected': {
        'stability': state.stability,
        'difficulty': state.difficulty,
        'dueAt': state.dueAt?.toUtc().toIso8601String(),
        'reps': state.reps,
        'lapses': state.lapses,
        'phase': state.phase.name,
        'step': state.step,
      },
    });
  }

  print(const JsonEncoder.withIndent('  ').convert({
    'note': 'GERADO por packages/scheduler/tool/dump_fixtures.dart — não editar à mão.',
    'desiredRetention': _params.desiredRetention,
    'weights': _params.weights,
    'cases': out,
  }));
}
