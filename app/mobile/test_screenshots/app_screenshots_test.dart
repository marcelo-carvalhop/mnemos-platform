import 'package:drift/native.dart';
import 'package:flashcards/features/account_screen.dart';
import 'package:flashcards/features/app_shell.dart';
import 'package:flashcards/features/deck_detail_screen.dart';
import 'package:flashcards/features/device_screen.dart';
import 'package:flashcards/features/editor_screen.dart';
import 'package:flashcards/features/generation/approval_screen.dart';
import 'package:flashcards/features/generation/generating_screen.dart';
import 'package:flashcards/features/generation/paywall_screen.dart';
import 'package:flashcards/features/onboarding/onboarding_screen.dart';
import 'package:flashcards/features/settings_screen.dart';
import 'package:flashcards/features/subscription_screen.dart';
import 'package:flashcards/features/terminal_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:store/store.dart';
import 'package:timezone/data/latest.dart' as tzdata;

import 'harness.dart';

/// Renderiza todas as telas do app e grava em `screenshots/mobile`.
///
/// Não é teste de comportamento: nada é afirmado além de "esta tela desenha".
/// Fica fora de `test/` para o `flutter test` não pegá-lo — as imagens são
/// documentação, e um arquivo de documentação que quebra a CI porque um
/// padding mudou é um arquivo que ninguém atualiza.
///
///   flutter test test_screenshots --update-goldens
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    tzdata.initializeTimeZones();
    await loadRealFonts();
  });

  late AppDatabase db;

  Future<void> open({bool withHistory = true}) async {
    db = await seedDatabase(withHistory: withHistory);
  }

  tearDown(() async => db.close());

  // -------------------------------------------------------------------------
  // Primeiro uso — artboard 10
  // -------------------------------------------------------------------------

  group('onboarding', () {
    Future<void> advance(WidgetTester tester, String label) async {
      await tester.tap(find.text(label));
      await tester.pumpAndSettle();
    }

    testWidgets('01 boas-vindas', (tester) async {
      await open(withHistory: false);
      await shoot(tester, '01-onboarding-boas-vindas', OnboardingScreen(onDone: () {}),
          overrides: appOverrides(db: db));
    });

    testWidgets('02 o que estudar', (tester) async {
      await open(withHistory: false);
      await shoot(
        tester,
        '02-onboarding-o-que-estudar',
        OnboardingScreen(onDone: () {}),
        overrides: appOverrides(db: db),
        act: (tester) => advance(tester, 'Começar'),
      );
    });

    testWidgets('03 meta diária', (tester) async {
      await open(withHistory: false);
      await shoot(
        tester,
        '03-onboarding-meta-diaria',
        OnboardingScreen(onDone: () {}),
        overrides: appOverrides(db: db),
        act: (tester) async {
          await advance(tester, 'Começar');
          await tester.enterText(find.byType(TextField), 'Direito Constitucional');
          await tester.pump();
          await advance(tester, 'Continuar');
        },
      );
    });

    testWidgets('04 geração gratuita', (tester) async {
      await open(withHistory: false);
      await shoot(
        tester,
        '04-onboarding-geracao-gratis',
        OnboardingScreen(onDone: () {}),
        overrides: appOverrides(db: db),
        act: (tester) async {
          await advance(tester, 'Começar');
          await tester.enterText(find.byType(TextField), 'Direito Constitucional');
          await tester.pump();
          await advance(tester, 'Continuar');
          await advance(tester, 'Continuar');
        },
      );
    });
  });

  // -------------------------------------------------------------------------
  // As quatro abas — artboards 01, 02, 04, 07
  // -------------------------------------------------------------------------

  testWidgets('05 hoje', (tester) async {
    await open();
    await shoot(tester, '05-hoje', const AppShell(),
        overrides: appOverrides(db: db, backend: mockBackend()));
  });

  testWidgets('06 biblioteca vazia', (tester) async {
    db = AppDatabase(NativeDatabase.memory());
    await shoot(tester, '06-biblioteca-vazia', const AppShell(initialIndex: 1),
        overrides: appOverrides(db: db, backend: mockBackend()));
  });

  testWidgets('07 biblioteca', (tester) async {
    await open();
    await shoot(tester, '07-biblioteca', const AppShell(initialIndex: 1),
        overrides: appOverrides(db: db, backend: mockBackend()));
  });

  testWidgets('08 busca', (tester) async {
    await open();
    await shoot(
      tester,
      '08-busca',
      const AppShell(initialIndex: 1),
      overrides: appOverrides(db: db, backend: mockBackend()),
      act: (tester) async {
        await tester.enterText(find.byType(TextField).first, 'protocolo');
        await tester.pump(const Duration(milliseconds: 400));
        await tester.pumpAndSettle();
      },
    );
  });

  testWidgets('09 criar', (tester) async {
    await open();
    await shoot(tester, '09-criar', const AppShell(initialIndex: 2),
        overrides: appOverrides(db: db, backend: mockBackend()));
  });

  testWidgets('09b criar texto colado', (tester) async {
    await open();
    await shoot(
      tester,
      '09b-criar-texto-colado',
      const AppShell(initialIndex: 2),
      overrides: appOverrides(db: db, backend: mockBackend()),
      act: (tester) async {
        await tester.tap(find.text('Texto'));
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byType(TextField).first,
          'A camada de transporte oferece comunicação lógica entre processos. '
          'O TCP acrescenta confiabilidade, controle de fluxo e controle de '
          'congestionamento sobre o serviço de melhor esforço do IP; o UDP não '
          'acrescenta nada além da multiplexação por porta e de um checksum '
          'opcional, e por isso é preferido quando a latência importa mais que '
          'a entrega garantida.',
        );
        await tester.pumpAndSettle();
      },
    );
  });

  testWidgets('10 progresso', (tester) async {
    await open();
    await shoot(tester, '10-progresso', const AppShell(initialIndex: 3),
        overrides: appOverrides(db: db, backend: mockBackend()));
  });

  // -------------------------------------------------------------------------
  // Baralho e edição — artboard 03
  // -------------------------------------------------------------------------

  testWidgets('11 baralho', (tester) async {
    await open();
    final deck = await firstDeck(db);
    await shoot(
      tester,
      '11-baralho',
      DeckDetailScreen(deckId: deck.id, deckName: deck.name),
      overrides: appOverrides(db: db, backend: mockBackend()),
    );
  });

  testWidgets('12 editor vazio', (tester) async {
    await open();
    final deck = await firstDeck(db);
    await shoot(
      tester,
      '12-editor-card-novo',
      EditorScreen(deckId: deck.id, deckName: deck.name),
      overrides: appOverrides(db: db),
    );
  });

  testWidgets('13 editor preenchido', (tester) async {
    await open();
    final deck = await firstDeck(db);
    await shoot(
      tester,
      '13-editor-card-preenchido',
      EditorScreen(deckId: deck.id, deckName: deck.name),
      overrides: appOverrides(db: db),
      act: (tester) async {
        await tester.enterText(
          find.byType(TextField).first,
          'O que o campo TTL de um datagrama IP evita?',
        );
        await tester.pump();
        await tester.enterText(
          find.byType(TextField).last,
          'Que um pacote preso em um laço de roteamento circule indefinidamente: '
          'cada roteador decrementa o TTL e descarta o pacote quando chega a zero.',
        );
        await tester.pump();
      },
    );
  });

  // -------------------------------------------------------------------------
  // Geração — artboards 05, 06, 09
  // -------------------------------------------------------------------------

  testWidgets('14 gerando', (tester) async {
    await open();
    final deck = await firstDeck(db);
    await shoot(
      tester,
      '14-gerando',
      GeneratingScreen(
        jobId: 'job-demo',
        deckId: deck.id,
        topic: 'Camada de transporte: TCP, UDP e controle de congestionamento',
      ),
      settle: false,
      overrides: appOverrides(
        db: db,
        backend: mockBackend(job: {
          'id': 'job-demo',
          'status': 'generating',
          'stage': 'escrevendo as perguntas',
          'card_count': 5,
        }),
      ),
    );
  });

  testWidgets('15 geração falhou', (tester) async {
    await open();
    final deck = await firstDeck(db);
    await shoot(
      tester,
      '15-geracao-falhou',
      GeneratingScreen(jobId: 'job-demo', deckId: deck.id),
      settle: false,
      overrides: appOverrides(
        db: db,
        backend: mockBackend(job: {
          'id': 'job-demo',
          'status': 'failed',
          'stage': 'falhou',
          'error_code': 'unreadable_source',
          'card_count': 0,
        }),
      ),
    );
  });

  testWidgets('16 revisar gerados', (tester) async {
    await open();
    final deck = await firstDeck(db);
    await shoot(
      tester,
      '16-revisar-cards-gerados',
      ApprovalScreen(jobId: 'job-demo', deckId: deck.id),
      settle: false,
      overrides: appOverrides(db: db, backend: mockBackend(approvalQueue: approvalQueue)),
    );
  });

  testWidgets('17 cota esgotada', (tester) async {
    await open();
    await shoot(tester, '17-cota-esgotada', const PaywallScreen(),
        overrides: appOverrides(db: db, backend: mockBackend()));
  });

  testWidgets('18 assinatura', (tester) async {
    await open();
    await shoot(
      tester,
      '18-assinatura',
      const SubscriptionScreen(),
      overrides: appOverrides(
        db: db,
        backend: mockBackend(quota: (remaining: 0, limit: 1, plan: 'free')),
      ),
    );
  });

  // -------------------------------------------------------------------------
  // Ajustes e dados
  // -------------------------------------------------------------------------

  testWidgets('19 configurações', (tester) async {
    await open();
    await shoot(tester, '19-configuracoes', const SettingsScreen(),
        overrides: appOverrides(db: db, backend: mockBackend()));
  });

  testWidgets('20 configurações roladas', (tester) async {
    await open();
    await shoot(
      tester,
      '20-configuracoes-continuacao',
      const SettingsScreen(),
      overrides: appOverrides(db: db, backend: mockBackend()),
      act: (tester) async {
        await tester.drag(find.byType(Scrollable).first, const Offset(0, -700));
        await tester.pumpAndSettle();
      },
    );
  });

  testWidgets('21 seus dados', (tester) async {
    await open();
    await shoot(tester, '21-seus-dados', const AccountScreen(),
        overrides: appOverrides(db: db, backend: mockBackend()));
  });

  // -------------------------------------------------------------------------
  // Terminal — artboard 08
  // -------------------------------------------------------------------------

  testWidgets('22 dispositivo sem terminal', (tester) async {
    await open();
    await shoot(tester, '22-dispositivo-sem-terminal', const DeviceScreen(),
        overrides: appOverrides(db: db, backend: mockBackend()));
  });

  testWidgets('23 dispositivo conectado', (tester) async {
    await open();
    final terminal = await storeTerminal(db);
    final decks = await db.select(db.decks).get();
    await shoot(
      tester,
      '23-dispositivo-conectado',
      const DeviceScreen(),
      overrides: appOverrides(
        db: db,
        backend: mockBackend(
          terminalSummary: terminalSummary(terminal, [decks.first.id]),
        ),
      ),
    );
  });

  testWidgets('24 conectar terminal', (tester) async {
    await open();
    await shoot(tester, '24-conectar-terminal', const TerminalScreen(),
        overrides: appOverrides(db: db, backend: mockBackend()));
  });
}
