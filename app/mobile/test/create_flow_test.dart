import 'package:api_client/api_client.dart';
import 'package:drift/native.dart';
import 'package:flashcards/features/create/create_screen.dart';
import 'package:flashcards/providers.dart';
import 'package:flashcards/providers_sync.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:store/store.dart';
import 'package:sync_client/sync_client.dart';
import 'package:timezone/data/latest.dart' as tzdata;

/// O fluxo de criação começando pela IA.
///
/// O que vale testar aqui não é que um botão existe: é que a cota é dita antes
/// de ser gasta, que o caminho grátis nunca some, e que um 402 não destrói o
/// trabalho que já foi criado.

class _FakeGeneration implements GenerationApi {
  _FakeGeneration({this.remaining = 1, this.failWith});

  final int remaining;
  final Object? failWith;
  int creates = 0;

  /// O que já tinha sido sincronizado no instante em que o job foi pedido.
  /// Guardado aqui porque a ordem é o ponto: empurrar depois não serve.
  List<String> pushedWhenAsked = const [];
  List<String> Function()? witness;

  @override
  Api get api => throw UnimplementedError();

  @override
  Future<({int limit, String plan, int remaining})> quota() async =>
      (remaining: remaining, limit: 1, plan: 'free');

  @override
  Future<GenerationJob> create({
    required String sourceType,
    required String targetDeckId,
    String? topic,
    String? uploadKey,
    int requestedCount = 10,
    String level = 'intermediario',
  }) async {
    creates++;
    pushedWhenAsked = witness?.call() ?? const [];
    if (failWith != null) throw failWith!;
    return const GenerationJob(id: 'job', status: 'queued', stage: 'na fila');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

/// Um servidor de sync que só anota o que foi empurrado.
class _FakeSyncApi implements SyncApi {
  final pushed = <String>[];

  @override
  Future<PushResult> push(
    String table,
    List<Map<String, Object?>> rows,
    String idempotencyKey,
  ) async {
    pushed.add(table);
    return PushResult(
      applied: rows.length,
      assignedSeqs: {for (final r in rows) r['id']! as String: 1},
    );
  }

  @override
  Future<({List<Map<String, Object?>> rows, int cursor, bool hasMore})> pull(
          String table, int since, int limit) async =>
      (rows: const <Map<String, Object?>>[], cursor: since, hasMore: false);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(tzdata.initializeTimeZones);

  late AppDatabase db;
  late _FakeSyncApi sync;
  final now = DateTime.utc(2026, 8, 23, 15);

  Widget harness(_FakeGeneration api) {
    db = AppDatabase(NativeDatabase.memory());
    sync = _FakeSyncApi();
    api.witness = () => List.of(sync.pushed);
    return ProviderScope(
      overrides: [
        databaseProvider.overrideWithValue(db),
        clockProvider.overrideWithValue(() => now),
        generationApiProvider.overrideWithValue(api),
        syncClientProvider.overrideWithValue(SyncClient(db, sync)),
      ],
      child: const MaterialApp(home: Scaffold(body: CreateScreen())),
    );
  }

  tearDown(() => db.close());

  testWidgets('a cota é dita antes de qualquer campo', (tester) async {
    // §7.7.1 — uma geração para a vida da conta. Contar isso só depois de
    // gasto é tirar algo que a pessoa não sabia que tinha.
    await tester.pumpWidget(harness(_FakeGeneration()));
    await tester.pumpAndSettle();

    expect(find.textContaining('1 geração grátis restante'), findsOneWidget);
  });

  testWidgets('sem cota, o botão vira assinatura e não uma tentativa fadada',
      (tester) async {
    final api = _FakeGeneration(remaining: 0);
    await tester.pumpWidget(harness(api));
    await tester.pumpAndSettle();

    expect(find.textContaining('Assinar remove o limite'), findsOneWidget);
    expect(find.text('Assinar para gerar'), findsOneWidget);
    expect(find.text('Gerar 8 cards'), findsNothing);
  });

  testWidgets('o caminho grátis nunca some', (tester) async {
    // Mesmo sem cota: escrever cards à mão é livre, sempre, e uma tela que
    // esconde isso quando o dinheiro entra em jogo está mentindo.
    await tester.pumpWidget(harness(_FakeGeneration(remaining: 0)));
    await tester.pumpAndSettle();

    expect(find.text('Escrever um card à mão'), findsOneWidget);
  });

  testWidgets('gerar exige um assunto', (tester) async {
    await tester.pumpWidget(harness(_FakeGeneration()));
    await tester.pumpAndSettle();

    final button = find.widgetWithText(FilledButton, 'Gerar 8 cards');
    expect(tester.widget<FilledButton>(button).onPressed, isNull);

    await tester.enterText(find.byType(TextField).first, 'Ciclo de Krebs');
    await tester.pump();
    expect(tester.widget<FilledButton>(button).onPressed, isNotNull);
  });

  testWidgets('o nível e a quantidade são escolhas, não padrões escondidos',
      (tester) async {
    // A tela anterior revelava nível e quantidade só depois do assunto, com o
    // argumento de que refinamento antes da decisão é ruído. Aqui eles ficam
    // visíveis desde o início, por duas razões: o artboard 04 os mostra
    // sempre, e a fileira de origens no topo já ancora a tela — revelar
    // controles conforme se digita faz o layout saltar embaixo do dedo.
    //
    // O que o teste protege continua sendo o mesmo: que existam, que venham
    // com um padrão declarado, e que dê para trocar.
    await tester.pumpWidget(harness(_FakeGeneration()));
    await tester.pumpAndSettle();

    expect(find.text('NÍVEL'), findsOneWidget);
    expect(find.text('QUANTOS CARDS'), findsOneWidget);
    expect(find.text('Médio'), findsOneWidget);

    // `ensureVisible` antes de cada toque: as fichas ficam abaixo da dobra da
    // janela de teste, e um `tap` fora da viewport não acerta nada — sem
    // erro, o que faz o teste falhar três linhas depois por um motivo que não
    // é o dele.
    await tester.ensureVisible(find.text('Avançado'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Avançado'));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('12'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('12'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).first, 'Ciclo de Krebs');
    await tester.pumpAndSettle();
    expect(find.text('Gerar 12 cards'), findsOneWidget);
  });

  testWidgets('o baralho e os cards nascem da mesma ação', (tester) async {
    final api = _FakeGeneration();
    await tester.pumpWidget(harness(api));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).first, 'Ciclo de Krebs');
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Gerar 8 cards'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    // O nome do baralho sai do que a pessoa escreveu: ninguém é perguntado
    // duas vezes sobre o mesmo assunto.
    final decks = await db.select(db.decks).get();
    expect(decks.map((d) => d.name), ['Ciclo de Krebs']);
    expect(api.creates, 1);
  });

  testWidgets('o baralho chega ao servidor antes de a geração ser pedida',
      (tester) async {
    // O servidor recusa gerar dentro de um baralho que não conhece. Como o
    // baralho nasce neste telefone segundos antes do pedido, empurrá-lo faz
    // parte da mesma ação — sem isso o job volta 404 e a pessoa lê "algo deu
    // errado" por um detalhe de sincronização que não é dela.
    final api = _FakeGeneration();
    await tester.pumpWidget(harness(api));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).first, 'Ciclo de Krebs');
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Gerar 8 cards'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(api.creates, 1);
    expect(api.pushedWhenAsked, contains('decks'));
  });

  testWidgets('um 402 não apaga o baralho que já foi criado', (tester) async {
    // Punir a pessoa por uma decisão comercial nossa seria destruir trabalho
    // dela. O baralho fica, e escrever à mão nele continua livre.
    final api = _FakeGeneration(failWith: const ApiException(402));
    await tester.pumpWidget(harness(api));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).first, 'Ciclo de Krebs');
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Gerar 8 cards'));
    await tester.pumpAndSettle();

    expect((await db.select(db.decks).get()).map((d) => d.name), ['Ciclo de Krebs']);
  });

  testWidgets('um assunto longo vira um nome de baralho utilizável',
      (tester) async {
    final api = _FakeGeneration();
    await tester.pumpWidget(harness(api));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byType(TextField).first,
      'Revolução Gloriosa de 1688 e a consolidação do parlamentarismo inglês '
      'ao longo do século XVIII',
    );
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Gerar 8 cards'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    final name = (await db.select(db.decks).getSingle()).name;
    expect(name.length, lessThanOrEqualTo(44));
    // Corta em palavra, não no meio de uma.
    expect(name, startsWith('Revolução Gloriosa de 1688'));
  });
}
