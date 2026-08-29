import 'package:api_client/api_client.dart';
import 'package:drift/native.dart';
import 'package:flashcards/features/today_screen.dart';
import 'package:flashcards/providers.dart';
import 'package:flashcards/providers_sync.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:store/store.dart';
import 'package:timezone/data/latest.dart' as tzdata;

/// O caminho de volta para uma geração deixada no meio (§7.8).
///
/// A tela de progresso diz "pode sair — o trabalho continua no servidor". Isso
/// era falso: a fila de aprovação só era alcançável pela tela que a abriu, e no
/// plano grátis ela guarda a única geração que a conta vai ter (§7.7.1).

class _FakeGeneration implements GenerationApi {
  _FakeGeneration(this.jobs);

  final List<OpenGeneration> jobs;

  @override
  Future<List<OpenGeneration>> open() async => jobs;

  @override
  Future<({int limit, String plan, int remaining})> quota() async =>
      (remaining: 1, limit: 1, plan: 'free');

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

OpenGeneration _job({required int pending, String status = 'ready'}) => OpenGeneration(
      id: 'job',
      status: status,
      stage: status == 'ready' ? 'pronto' : 'escrevendo os cards',
      deckId: 'deck',
      topic: 'Ciclo de Krebs',
      pending: pending,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(tzdata.initializeTimeZones);

  late AppDatabase db;

  Widget harness(_FakeGeneration api) {
    db = AppDatabase(NativeDatabase.memory());
    return ProviderScope(
      overrides: [
        databaseProvider.overrideWithValue(db),
        clockProvider.overrideWithValue(() => DateTime.utc(2026, 8, 23, 15)),
        generationApiProvider.overrideWithValue(api),
      ],
      child: const MaterialApp(home: TodayScreen(embedded: true)),
    );
  }

  tearDown(() => db.close());

  testWidgets('uma fila abandonada é encontrável em Hoje', (tester) async {
    await tester.pumpWidget(harness(_FakeGeneration([_job(pending: 12)])));
    await tester.pumpAndSettle();

    expect(find.textContaining('12 cards esperam sua aprovação'), findsOneWidget);
    // O assunto identifica a geração: o baralho pode ter qualquer nome.
    expect(find.text('Ciclo de Krebs'), findsOneWidget);
  });

  testWidgets('uma geração ainda rodando é informação, não cobrança',
      (tester) async {
    await tester.pumpWidget(
      harness(_FakeGeneration([_job(pending: 0, status: 'generating')])),
    );
    await tester.pumpAndSettle();

    expect(find.text('Gerando seus cards'), findsOneWidget);
    expect(find.textContaining('aprovação'), findsNothing);
  });

  testWidgets('um card só fala no singular', (tester) async {
    await tester.pumpWidget(harness(_FakeGeneration([_job(pending: 1)])));
    await tester.pumpAndSettle();

    expect(find.textContaining('1 card espera sua aprovação'), findsOneWidget);
  });

  testWidgets('sem nada pendente, Hoje não inventa um aviso', (tester) async {
    await tester.pumpWidget(harness(_FakeGeneration(const [])));
    await tester.pumpAndSettle();

    expect(find.textContaining('aprovação'), findsNothing);
    expect(find.text('Gerando seus cards'), findsNothing);
  });
}
