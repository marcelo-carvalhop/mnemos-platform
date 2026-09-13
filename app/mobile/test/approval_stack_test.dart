import 'package:api_client/api_client.dart';
import 'package:flashcards/features/generation/approval_screen.dart';
import 'package:flashcards/providers_sync.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// A pilha de aprovação (§7.8).
///
/// O que vale testar aqui é a leitura do gesto: enquanto o dedo está na tela, a
/// pessoa precisa saber para onde o card está indo antes de soltar. E nada pode
/// virar card sem uma decisão.

class _FakeGeneration implements GenerationApi {
  _FakeGeneration(this.cards);

  final List<PendingCard> cards;
  final decisions = <(String, String?)>[];

  @override
  Api get api => throw UnimplementedError();

  @override
  Future<ApprovalQueue> queue(String jobId) async =>
      ApprovalQueue(cards: cards, decided: 0, total: cards.length);

  @override
  Future<PendingCard> decide(String pendingId, String? decision) async {
    decisions.add((pendingId, decision));
    final card = cards.firstWhere((c) => c.id == pendingId);
    return PendingCard(
      id: card.id,
      front: card.front,
      back: card.back,
      tags: card.tags,
      position: card.position,
      decision: decision,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

PendingCard _card(int i) => PendingCard(
      id: 'p$i',
      front: 'Pergunta $i',
      back: 'Resposta $i',
      tags: const [],
      position: i,
    );

void main() {
  Widget harness(_FakeGeneration api) => ProviderScope(
        overrides: [generationApiProvider.overrideWithValue(api)],
        child: const MaterialApp(
          home: ApprovalScreen(jobId: 'job', deckId: 'deck'),
        ),
      );

  testWidgets('o selo aparece do lado que continua na tela', (tester) async {
    // Arrastando para a direita, a metade visível do card é a esquerda. Um
    // selo "APROVAR" encostado na borda direita sai do visor junto com o
    // gesto e nunca é lido — foi o que aconteceu no aparelho.
    await tester.pumpWidget(harness(_FakeGeneration([_card(1), _card(2)])));
    await tester.pumpAndSettle();

    final gesture = await tester.startGesture(tester.getCenter(find.text('Pergunta 1')));
    await gesture.moveBy(const Offset(120, 0));
    await tester.pump();

    final aprovar = tester.getCenter(find.text('APROVAR')).dx;
    final descartar = tester.getCenter(find.text('DESCARTAR')).dx;
    expect(aprovar, lessThan(descartar));

    await gesture.up();
    await tester.pumpAndSettle();
  });

  testWidgets('arrastar o bastante decide o card', (tester) async {
    final api = _FakeGeneration([_card(1), _card(2)]);
    await tester.pumpWidget(harness(api));
    await tester.pumpAndSettle();

    await tester.drag(find.text('Pergunta 1'), const Offset(400, 0));
    await tester.pumpAndSettle();

    expect(api.decisions, [('p1', 'approved')]);
    expect(find.text('Pergunta 1'), findsNothing);
  });

  testWidgets('um arrasto curto devolve o card sem decidir', (tester) async {
    // §5.7 — hesitar não é decidir. Um gesto abaixo do limiar tem de voltar
    // exatamente para onde estava, e não gastar o card.
    final api = _FakeGeneration([_card(1), _card(2)]);
    await tester.pumpWidget(harness(api));
    await tester.pumpAndSettle();

    await tester.drag(find.text('Pergunta 1'), const Offset(40, 0));
    await tester.pumpAndSettle();

    expect(api.decisions, isEmpty);
    expect(find.text('Pergunta 1'), findsOneWidget);
  });

  testWidgets('desfazer devolve o card ao topo da pilha', (tester) async {
    final api = _FakeGeneration([_card(1), _card(2)]);
    await tester.pumpWidget(harness(api));
    await tester.pumpAndSettle();

    await tester.drag(find.text('Pergunta 1'), const Offset(-400, 0));
    await tester.pumpAndSettle();
    expect(api.decisions, [('p1', 'discarded')]);

    await tester.tap(find.text('Desfazer'));
    await tester.pumpAndSettle();

    // null é o desfazer no servidor: a decisão é apagada, não invertida.
    expect(api.decisions.last, ('p1', null));
    expect(find.text('Pergunta 1'), findsOneWidget);
  });
}
