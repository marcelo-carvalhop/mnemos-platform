import 'dart:async';

import 'package:api_client/api_client.dart' show OpenGeneration;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers.dart';
import '../providers_sync.dart';
import '../providers_today.dart';
import '../sync/sync_controller.dart';
import '../theme/tokens.dart';
import '../theme/typography.dart';
import '../ui/ui.dart';
import 'create/create_screen.dart';
import 'decks_screen.dart';
import 'device_screen.dart';
import 'generation/approval_screen.dart';
import 'generation/generating_screen.dart';
import 'progress_screen.dart';
import 'settings_screen.dart';
import 'today_screen.dart';

/// A casca do aplicativo — o mesmo menu da web no celular.
///
/// Um cabeçalho curto em cima (a marca e o estado da sincronização) e a barra
/// na base com as quatro abas e "Mais". O que se usa pouco — Dispositivo,
/// Configurações, Sair — mora numa folha que sobe de baixo, como na web.
///
/// Usa [IndexedStack] e não um `switch`: trocar de aba não deve descartar a
/// rolagem nem refazer as consultas da aba que você acabou de deixar.
///
/// **Cada aba tem o seu próprio [Navigator].** Sem isso, abrir um baralho a
/// partir da Biblioteca empurrava a tela por cima da casca inteira e a barra
/// desaparecia. O que deve mesmo cobrir a barra são as tarefas com começo e fim
/// (gerar, revisar o que a IA escreveu, assinar, escrever um card): essas
/// continuam sendo empurradas no navegador raiz.
class AppShell extends ConsumerStatefulWidget {
  const AppShell({super.key, this.initialIndex = 0});

  final int initialIndex;

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> {
  late int _index = widget.initialIndex;

  /// A tela aberta veio do "Mais" (Dispositivo, Configurações).
  bool _inMore = false;

  static const _create = 2;

  static const _tabs = <MnemosTab>[
    (icon: Icons.calendar_today_outlined, label: 'Hoje'),
    (icon: Icons.library_books_outlined, label: 'Biblioteca'),
    (icon: Icons.add, label: 'Criar'),
    (icon: Icons.bar_chart_rounded, label: 'Progresso'),
  ];

  final _navigators = [
    for (var i = 0; i < _tabs.length; i++) GlobalKey<NavigatorState>(),
  ];

  /// Gerações abertas: perguntadas de novo a cada 30 s enquanto o app está
  /// aberto. Sem isso o atalho do cabeçalho só mudava de "gerando" para
  /// "para aprovar" quando a pessoa saía e voltava ao app.
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    _poll = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) ref.invalidate(openGenerationsProvider);
    });
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  /// O atalho do cabeçalho: a aprovação pendente ou a geração em curso. São
  /// tarefas com começo e fim, então cobrem a barra (navegador raiz).
  Future<void> _openGeneration(OpenGeneration job) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => job.isWaitingOnMe
            ? ApprovalScreen(jobId: job.id, deckId: job.deckId)
            : GeneratingScreen(jobId: job.id, deckId: job.deckId),
      ),
    );
    if (!mounted) return;
    ref
      ..invalidate(openGenerationsProvider)
      ..invalidate(queueProvider)
      ..invalidate(dueByDeckProvider);
  }

  void _open(int index) {
    // Tocar na aba onde já se está volta ao topo dela. É o que uma barra de
    // abas promete em todo aplicativo, e sem isso a aba atual seria o único
    // botão da barra que não faz nada.
    if (index == _index) {
      _navigators[index].currentState?.popUntil((route) => route.isFirst);
    }
    setState(() {
      _index = index;
      _inMore = false;
    });
  }

  /// Abre uma tela do "Mais" dentro da aba atual, com a barra à vista — como
  /// `/configuracoes` na web, que é uma rota do shell e não um modal.
  Future<void> _openFromMore(Widget screen) async {
    setState(() => _inMore = true);
    await _navigators[_index].currentState?.push(
      MaterialPageRoute<void>(builder: (_) => screen),
    );
    if (mounted) setState(() => _inMore = false);
  }

  Future<void> _more() async {
    final choice = await showModalBottomSheet<_MoreChoice>(
      context: context,
      backgroundColor: MnemosColors.raised,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(MnemosRadii.card)),
      ),
      builder: (_) => const _MoreSheet(),
    );
    if (!mounted || choice == null) return;
    switch (choice) {
      case _MoreChoice.device:
        await _openFromMore(const DeviceScreen());
      case _MoreChoice.settings:
        await _openFromMore(const SettingsScreen());
      case _MoreChoice.signOut:
        await SettingsScreen.signOut(context, ref);
    }
  }

  /// O botão voltar do Android, em ordem: primeiro sai da tela de dentro da
  /// aba, depois volta para a primeira aba, e só então sai do app.
  void _back(bool didPop) {
    if (didPop) return;

    final nested = _navigators[_index].currentState;
    if (nested != null && nested.canPop()) {
      nested.pop();
      return;
    }
    if (_index != 0) {
      setState(() => _index = 0);
      return;
    }
    SystemNavigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    final roots = [
      TodayScreen(onOpenLibrary: () => _open(1)),
      const DecksScreen(),
      const CreateScreen(),
      const ProgressScreen(),
    ];
    final due = ref.watch(dueTodayProvider).valueOrNull?.cards ?? 0;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) => _back(didPop),
      child: Scaffold(
        body: SafeArea(
          bottom: false,
          child: Column(
            children: [
              _TopBar(onHome: () => _open(0), onStatus: _more, onGeneration: _openGeneration),
              Expanded(
                child: IndexedStack(
                  index: _index,
                  children: [
                    for (final (i, root) in roots.indexed)
                      Navigator(
                        key: _navigators[i],
                        onGenerateRoute: (settings) => MaterialPageRoute<void>(
                          settings: settings,
                          builder: (_) => root,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
        bottomNavigationBar: MnemosTabBar(
          tabs: _tabs,
          currentIndex: _index,
          onSelected: _open,
          onMore: _more,
          moreSelected: _inMore,
          actionIndex: _create,
          badges: {0: due},
        ),
      ),
    );
  }
}

/// O cabeçalho curto da web no celular: a marca, e o estado da sincronização
/// numa pílula que abre o "Mais".
class _TopBar extends ConsumerWidget {
  const _TopBar({required this.onHome, required this.onStatus, required this.onGeneration});

  final VoidCallback onHome;
  final VoidCallback onStatus;
  final ValueChanged<OpenGeneration> onGeneration;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sync = ref.watch(syncControllerProvider);
    final (tone, label) = _syncLabel(sync, short: true);

    return Container(
      padding: const EdgeInsets.fromLTRB(MnemosSpacing.screen, 8, 14, 8),
      decoration: const BoxDecoration(
        color: MnemosColors.canvas,
        border: Border(bottom: BorderSide(color: MnemosColors.line)),
      ),
      child: Row(
        children: [
          InkWell(
            onTap: onHome,
            borderRadius: BorderRadius.circular(MnemosRadii.control),
            child: const Padding(
              padding: EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  BrandMark(size: 22),
                  SizedBox(width: 9),
                  Text(
                    'Mnemos',
                    style: TextStyle(
                      fontFamily: MnemosFonts.sans,
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      letterSpacing: -0.36,
                      color: MnemosColors.ink,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const Spacer(),
          _GenerationShortcut(onOpen: onGeneration),
          Semantics(
            button: true,
            label: 'Sincronização: $label',
            excludeSemantics: true,
            child: InkWell(
              onTap: onStatus,
              customBorder: const StadiumBorder(),
              child: Ink(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: const ShapeDecoration(
                  color: MnemosColors.raised,
                  shape: StadiumBorder(side: BorderSide(color: MnemosColors.line)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _Dot(tone),
                    const SizedBox(width: 7),
                    Text(label, style: MnemosText.caption.copyWith(color: MnemosColors.muted)),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

enum _MoreChoice { device, settings, signOut }

/// A folha do "Mais": o estado da sincronização, Dispositivo, Configurações e
/// Sair — a mesma da web.
class _MoreSheet extends ConsumerWidget {
  const _MoreSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sync = ref.watch(syncControllerProvider);
    final (tone, label) = _syncLabel(sync, short: false);

    Widget row(IconData icon, String text, _MoreChoice choice, {bool danger = false}) {
      final color = danger ? MnemosColors.destructive : MnemosColors.ink;
      return InkWell(
        onTap: () => Navigator.of(context).pop(choice),
        child: SizedBox(
          height: 52,
          child: Row(
            children: [
              const SizedBox(width: 16),
              Icon(icon, size: 20, color: danger ? color : MnemosColors.faint),
              const SizedBox(width: 14),
              Expanded(child: Text(text, style: MnemosText.body.copyWith(color: color))),
              if (!danger)
                const Icon(Icons.chevron_right, size: 20, color: MnemosColors.fainter),
              const SizedBox(width: 12),
            ],
          ),
        ),
      );
    }

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: MnemosColors.sunken,
                border: Border.all(color: MnemosColors.line),
                borderRadius: BorderRadius.circular(MnemosRadii.card),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Eyebrow('Sincronização'),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      _Dot(tone),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(label, style: MnemosText.body.copyWith(color: MnemosColors.muted)),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Container(
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                border: Border.all(color: MnemosColors.line),
                borderRadius: BorderRadius.circular(MnemosRadii.card),
              ),
              child: Material(
                color: MnemosColors.raised,
                child: Column(
                  children: [
                    row(Icons.devices_other_outlined, 'Dispositivo', _MoreChoice.device),
                    const Divider(height: 1, color: MnemosColors.line),
                    row(Icons.settings_outlined, 'Configurações', _MoreChoice.settings),
                    const Divider(height: 1, color: MnemosColors.line),
                    row(Icons.logout, 'Sair', _MoreChoice.signOut, danger: true),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            OutlinedButton(
              onPressed: () => Navigator.of(context).pop(),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
                side: const BorderSide(color: MnemosColors.line),
                foregroundColor: MnemosColors.ink,
              ),
              child: const Text('Fechar'),
            ),
          ],
        ),
      ),
    );
  }
}

enum _Tone { ok, pending, offline }

(_Tone, String) _syncLabel(SyncState sync, {required bool short}) {
  final n = sync.pending;
  if (sync.phase == SyncPhase.offline) {
    return (_Tone.offline, short ? 'Sem conexão' : 'Sem conexão. Nada foi perdido.');
  }
  if (n > 0) {
    return (
      _Tone.pending,
      short ? '$n para enviar' : '$n ${n == 1 ? 'mudança' : 'mudanças'} para enviar',
    );
  }
  if (sync.phase == SyncPhase.failed) {
    return (_Tone.pending, short ? 'Não sincronizou' : 'Não consegui sincronizar. Tento de novo sozinho.');
  }
  return (_Tone.ok, short ? 'Sincronizado' : 'Tudo enviado');
}

class _Dot extends StatelessWidget {
  const _Dot(this.tone);

  final _Tone tone;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 7,
      height: 7,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: switch (tone) {
          _Tone.ok => MnemosColors.settled,
          _Tone.pending => MnemosColors.due,
          _Tone.offline => MnemosColors.fainter,
        },
      ),
    );
  }
}

/// O caminho de volta para uma geração, em qualquer tela.
///
/// "N para aprovar" no gradiente da IA quando há cards esperando resposta;
/// "Gerando…" discreto enquanto o servidor ainda escreve. Some quando não há
/// nada aberto. O aviso grande continua em Hoje; este é o atalho que segue a
/// pessoa pelas outras abas.
class _GenerationShortcut extends ConsumerWidget {
  const _GenerationShortcut({required this.onOpen});

  final ValueChanged<OpenGeneration> onOpen;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final jobs = ref.watch(openGenerationsProvider).valueOrNull ?? const <OpenGeneration>[];
    if (jobs.isEmpty) return const SizedBox.shrink();

    final waiting = jobs.where((j) => j.isWaitingOnMe).toList();
    final job = waiting.isNotEmpty ? waiting.first : jobs.first;
    final pending = waiting.fold<int>(0, (sum, j) => sum + j.pending);
    final label = waiting.isNotEmpty ? '$pending para aprovar' : 'Gerando…';

    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Semantics(
        button: true,
        label: waiting.isNotEmpty
            ? '$pending ${pending == 1 ? 'card espera' : 'cards esperam'} sua aprovação'
            : 'Gerando seus cards',
        excludeSemantics: true,
        child: InkWell(
          onTap: () => onOpen(job),
          customBorder: const StadiumBorder(),
          child: Ink(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: ShapeDecoration(
              gradient: waiting.isNotEmpty ? MnemosGradients.ai : null,
              color: waiting.isNotEmpty ? null : MnemosColors.raised,
              shape: StadiumBorder(
                side: waiting.isNotEmpty
                    ? BorderSide.none
                    : const BorderSide(color: MnemosColors.line),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (waiting.isEmpty) ...[
                  const SizedBox.square(
                    dimension: 10,
                    child: CircularProgressIndicator(strokeWidth: 1.6),
                  ),
                  const SizedBox(width: 7),
                ] else ...[
                  const Icon(Icons.auto_awesome, size: 13, color: MnemosColors.onDark),
                  const SizedBox(width: 6),
                ],
                Text(
                  label,
                  style: MnemosText.caption.copyWith(
                    color: waiting.isNotEmpty ? MnemosColors.onDark : MnemosColors.muted,
                    fontWeight: waiting.isNotEmpty ? FontWeight.w600 : FontWeight.w400,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
