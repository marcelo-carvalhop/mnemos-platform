import 'package:api_client/api_client.dart';
import 'package:drift/native.dart';
import 'package:flashcards/features/generation/approval_screen.dart';
import 'package:flashcards/features/create/create_screen.dart';
import 'package:flashcards/features/today_screen.dart';
import 'package:flashcards/providers.dart';
import 'package:flashcards/providers_sync.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
// `store` também exporta um PendingCard (a tabela local). Aqui o que interessa
// é o da API — o card que ainda não é card.
import 'package:store/store.dart' hide PendingCard;
import 'package:sync_client/sync_client.dart';
import 'package:timezone/data/latest.dart' as tzdata;

/// Valores nulos, vazios e absurdos nos três fluxos de geração.
///
/// O que se procura aqui não é o caminho feliz — é o que a tela diz quando o
/// servidor responde algo que ninguém desenhou: uma fila sem cards, uma cota
/// desconhecida, um assunto que é só espaço em branco, um job sem assunto.

class _Gen implements GenerationApi {
  _Gen({
    this.remaining = 1,
    this.cards = const [],
    this.jobs = const [],
    this.quotaThrows,
  });

  final int remaining;
  final List<PendingCard> cards;
  final List<OpenGeneration> jobs;
  final Object? quotaThrows;
  int creates = 0;

  @override
  Api get api => throw UnimplementedError();

  @override
  Future<({int limit, String plan, int remaining})> quota() async {
    if (quotaThrows != null) throw quotaThrows!;
    return (remaining: remaining, limit: 1, plan: 'free');
  }

  @override
  Future<List<OpenGeneration>> open() async => jobs;

  @override
  Future<ApprovalQueue> queue(String jobId) async =>
      ApprovalQueue(cards: cards, decided: 0, total: cards.length);

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
    return const GenerationJob(id: 'job', status: 'queued', stage: 'na fila');
  }

  @override
  Future<PendingCard> decide(String pendingId, String? decision) async =>
      cards.firstWhere((c) => c.id == pendingId);

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

class _Sync implements SyncApi {
  @override
  Future<PushResult> push(String t, List<Map<String, Object?>> rows, String k) async =>
      PushResult(applied: rows.length, assignedSeqs: {
        for (final r in rows) r['id']! as String: 1,
      });

  @override
  Future<({List<Map<String, Object?>> rows, int cursor, bool hasMore})> pull(
          String table, int since, int limit) async =>
      (rows: const <Map<String, Object?>>[], cursor: since, hasMore: false);
}

PendingCard _card(int i, {String? front, String? back, List<String>? tags}) => PendingCard(
      id: 'p$i',
      front: front ?? 'Pergunta $i',
      back: back ?? 'Resposta $i',
      tags: tags ?? const [],
      position: i,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(tzdata.initializeTimeZones);

  late AppDatabase db;

  Widget create(_Gen api) {
    db = AppDatabase(NativeDatabase.memory());
    return ProviderScope(
      overrides: [
        databaseProvider.overrideWithValue(db),
        clockProvider.overrideWithValue(() => DateTime.utc(2026, 8, 23, 15)),
        generationApiProvider.overrideWithValue(api),
        syncClientProvider.overrideWithValue(SyncClient(db, _Sync())),
      ],
      child: const MaterialApp(home: Scaffold(body: CreateScreen())),
    );
  }

  Widget approval(_Gen api) => ProviderScope(
        overrides: [generationApiProvider.overrideWithValue(api)],
        child: const MaterialApp(home: ApprovalScreen(jobId: 'j', deckId: 'd')),
      );

  Widget today(_Gen api) {
    db = AppDatabase(NativeDatabase.memory());
    return ProviderScope(
      overrides: [
        databaseProvider.overrideWithValue(db),
        clockProvider.overrideWithValue(() => DateTime.utc(2026, 8, 23, 15)),
        generationApiProvider.overrideWithValue(api),
      ],
      child: MaterialApp(home: Scaffold(body: TodayScreen(onOpenLibrary: () {}))),
    );
  }

  // -------------------------------------------------------------------------
  // A cota, quando o servidor não responde o que se espera
  // -------------------------------------------------------------------------

  testWidgets('offline, a cota diz que não sabe em vez de chutar', (tester) async {
    // quotaProvider devolve -1 quando está offline. -1 não é "nenhuma" nem
    // "uma": prometer geração a quem não tem, ou negá-la a quem tem, são erros
    // simétricos e os dois queimam confiança.
    await tester.pumpWidget(create(_Gen(quotaThrows: const Offline('sem rede'))));
    await tester.pumpAndSettle();

    expect(find.textContaining('já foi usada'), findsNothing);
    expect(find.text('Assinar para gerar'), findsNothing);
    expect(find.text('Escrever um card à mão'), findsOneWidget);
  });

  testWidgets('uma cota negativa não vira texto sobre gerações negativas',
      (tester) async {
    await tester.pumpWidget(create(_Gen(remaining: -1)));
    await tester.pumpAndSettle();

    expect(find.textContaining('-1'), findsNothing);
  });

  testWidgets('uma cota grande fala no plural certo', (tester) async {
    await tester.pumpWidget(create(_Gen(remaining: 7)));
    await tester.pumpAndSettle();

    expect(find.textContaining('7 gerações'), findsOneWidget);
  });

  // -------------------------------------------------------------------------
  // O assunto
  // -------------------------------------------------------------------------

  testWidgets('só espaço em branco não é assunto', (tester) async {
    final api = _Gen();
    await tester.pumpWidget(create(api));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).first, '     ');
    await tester.pump();

    expect(
      tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Gerar 8 cards')).onPressed,
      isNull,
    );
    expect(find.text('Nível'), findsNothing);
    expect(api.creates, 0);
  });

  testWidgets('um assunto em várias linhas vira um nome de baralho de uma linha',
      (tester) async {
    // O campo aceita até quatro linhas. Um \n dentro do nome quebra a lista de
    // baralhos, que assume uma linha por card.
    final api = _Gen();
    await tester.pumpWidget(create(api));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byType(TextField).first,
      'Ciclo de Krebs\ne a cadeia respiratória',
    );
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Gerar 8 cards'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    final name = (await db.select(db.decks).getSingle()).name;
    expect(name, isNot(contains('\n')));
  });

  testWidgets('uma palavra única e enorme não vira um nome ilegível',
      (tester) async {
    final api = _Gen();
    await tester.pumpWidget(create(api));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).first, 'A' * 200);
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Gerar 8 cards'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    final name = (await db.select(db.decks).getSingle()).name;
    expect(name.length, lessThanOrEqualTo(44));
  });

  // -------------------------------------------------------------------------
  // A fila de aprovação, vazia ou estranha
  // -------------------------------------------------------------------------

  testWidgets('uma fila vazia não diz que você aprovou tudo', (tester) async {
    // "Você aprovou todos" com zero cards é 0 == 0 virando elogio. Ninguém
    // aprovou nada: a geração não produziu card nenhum.
    await tester.pumpWidget(approval(_Gen(cards: const [])));
    await tester.pumpAndSettle();

    expect(find.text('Você aprovou todos'), findsNothing);
  });

  testWidgets('uma fila vazia oferece uma saída', (tester) async {
    // Sem cards, aprovar, descartar e criar ficam todos desabilitados. Uma tela
    // onde nenhum botão funciona é um beco sem saída.
    await tester.pumpWidget(approval(_Gen(cards: const [])));
    await tester.pumpAndSettle();

    final live = find.byWidgetPredicate(
      (w) => w is ButtonStyleButton && w.onPressed != null,
    );
    expect(live, findsWidgets, reason: 'alguma ação tem de estar viva');
  });

  testWidgets('um card sem verso ainda é julgável', (tester) async {
    await tester.pumpWidget(approval(_Gen(cards: [_card(1, back: '')])));
    await tester.pumpAndSettle();

    expect(find.text('Pergunta 1'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('um card com muitas tags não estoura a largura', (tester) async {
    await tester.pumpWidget(approval(_Gen(cards: [
      _card(1, tags: List.generate(14, (i) => 'etiqueta-numero-$i')),
    ])));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });

  // -------------------------------------------------------------------------
  // O aviso de geração aberta
  // -------------------------------------------------------------------------

  testWidgets('um job de PDF não tem assunto e o aviso não mostra "null"',
      (tester) async {
    await tester.pumpWidget(today(_Gen(jobs: [
      const OpenGeneration(
        id: 'j',
        status: 'ready',
        stage: 'pronto',
        deckId: 'd',
        pending: 4,
      ),
    ])));
    await tester.pumpAndSettle();

    expect(find.textContaining('null'), findsNothing);
    expect(find.text('pronto'), findsOneWidget);
  });

  testWidgets('duas gerações abertas aparecem as duas', (tester) async {
    await tester.pumpWidget(today(_Gen(jobs: const [
      OpenGeneration(
        id: 'a',
        status: 'ready',
        stage: 'pronto',
        deckId: 'd1',
        topic: 'Ciclo de Krebs',
        pending: 3,
      ),
      OpenGeneration(
        id: 'b',
        status: 'generating',
        stage: 'escrevendo os cards',
        deckId: 'd2',
        topic: 'Teorema de Bayes',
        pending: 0,
      ),
    ])));
    await tester.pumpAndSettle();

    expect(find.textContaining('3 cards esperam'), findsOneWidget);
    expect(find.text('Gerando seus cards'), findsOneWidget);
  });

  testWidgets('o servidor fora do ar não impede Hoje de abrir', (tester) async {
    await tester.pumpWidget(today(_Gen(quotaThrows: const Offline('x'))));
    await tester.pumpAndSettle();

    expect(find.text('Hoje'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  tearDown(() async {
    // Nem todo teste abre um banco.
    try {
      await db.close();
    } on Object {
      // ignora
    }
  });
}
