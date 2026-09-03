import 'dart:convert';

import 'package:api_client/api_client.dart';
import 'package:flutter/foundation.dart' show setEquals;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../device/device_ble.dart';
import '../device/terminal_local_store.dart';
import '../device/terminal_sync_service.dart';
import '../format.dart';
import '../providers.dart';
import '../providers_sync.dart';
import '../providers_today.dart';
import '../theme/tokens.dart';
import '../theme/typography.dart';
import '../ui/ui.dart';
import 'terminal_screen.dart';

/// Um baralho e a sua presença no terminal.
class _DeckRow {
  const _DeckRow(this.id, this.name, this.cardCount);
  final String id;
  final String name;
  final int cardCount;
}

/// O terminal — artboard 08.
///
/// Funde as antigas "Dispositivo" e "Sincronização". Eram duas telas para uma
/// pergunta só ("o que está no meu Mnemos, e está atualizado?"), e a divisão
/// obrigava a lembrar em qual delas ficava cada metade da resposta.
///
/// **Lacuna conhecida:** o artboard também mostra o nível de bateria e um
/// espelho do card que está na tela do terminal. Nenhum dos dois existe no
/// protocolo (`lib/device/terminal_protocol.dart`), no `TerminalSummary` do
/// backend nem no firmware. Ficam de fora até o terminal saber reportá-los.
class DeviceScreen extends ConsumerStatefulWidget {
  const DeviceScreen({super.key});

  @override
  ConsumerState<DeviceScreen> createState() => _DeviceScreenState();
}

class _DeviceScreenState extends ConsumerState<DeviceScreen> {
  StoredTerminal? _terminal;
  List<_DeckRow> _decks = const [];
  Set<String> _desired = {};
  Set<String> _applied = {};
  Set<String> _actual = {};
  bool _loading = true;
  bool _busy = false;
  String? _message;
  bool _error = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final db = ref.read(databaseProvider);
    final store = TerminalLocalStore(db);
    final terminal = await store.activeTerminal();
    if (terminal == null) {
      if (mounted) setState(() => _loading = false);
      return;
    }

    final rows = await db.customSelect(
      '''
      SELECT d.id, d.name, COUNT(c.id) AS card_count
      FROM decks d
      LEFT JOIN cards c ON c.deck_id = d.id AND c.deleted_at IS NULL
      WHERE d.deleted_at IS NULL AND d.archived_at IS NULL
      GROUP BY d.id, d.name
      ORDER BY d.name COLLATE NOCASE
      ''',
      readsFrom: {db.decks, db.cards},
    ).get();

    var desired = await store.desiredDeckIds(terminal.deviceId);
    var actual = await store.actualDeckIds(terminal.deviceId);
    final hasLocalIntent = await store.hasDesiredDeckIntent(terminal.deviceId);
    final localSync = await store.lastSync(terminal.deviceId);
    final localSyncAt = DateTime.tryParse(localSync?['at']?.toString() ?? '');

    try {
      final remote = await ref.read(terminalApiProvider).summary(terminal.deviceId);

      // O celular é dono da decisão do usuário. Um conjunto local vazio e
      // explícito quer dizer "remover tudo", não "ainda não carregou".
      if (!hasLocalIntent) {
        desired = remote.desiredDeckIds.toSet();
        await store.setDesiredDeckIds(terminal.deviceId, desired);
      }

      // O estado físico chega por BLE ou pelo backend. Vale a observação mais
      // nova, para uma sincronização direta não ser desfeita por um relatório
      // velho da nuvem na próxima abertura.
      final remoteSyncAt = DateTime.tryParse(remote.lastSyncAt ?? '');
      final remoteIsAtLeastAsFresh = localSyncAt == null ||
          (remoteSyncAt != null && !remoteSyncAt.isBefore(localSyncAt));
      if (remoteIsAtLeastAsFresh) {
        actual = remote.reportedDeckIds.toSet();
        await store.setActualDeckIds(terminal.deviceId, actual);
      }
    } on Offline {
      // Estar offline é o caso normal. A intenção e o estado locais seguem
      // inteiramente utilizáveis.
    } on ApiException {
      // Idem: a tela precisa continuar útil sem backend.
    }

    if (!mounted) return;
    setState(() {
      _terminal = terminal;
      _decks = [
        for (final r in rows)
          _DeckRow(r.read<String>('id'), r.read<String>('name'), r.read<int>('card_count')),
      ];
      _desired = desired;
      _applied = Set.of(desired);
      _actual = actual;
      _loading = false;
    });
  }

  int get _desiredCards =>
      _decks.where((d) => _desired.contains(d.id)).fold(0, (sum, d) => sum + d.cardCount);

  /// Cards escolhidos que ainda não estão no aparelho.
  int get _pendingCards => _decks
      .where((d) => _desired.contains(d.id) && !_actual.contains(d.id))
      .fold(0, (sum, d) => sum + d.cardCount);

  bool get _dirty => !setEquals(_desired, _applied);

  bool _overCapacity() {
    final terminal = _terminal;
    if (terminal == null) return false;
    if (_desiredCards <= terminal.maxCards) return false;
    setState(() {
      _message = 'O estado escolhido usa $_desiredCards cards, acima da '
          'capacidade de ${terminal.maxCards} deste terminal.';
      _error = true;
    });
    return true;
  }

  Future<void> _applyIntent() async {
    final terminal = _terminal;
    if (terminal == null || _overCapacity()) return;

    setState(() {
      _busy = true;
      _message = null;
      _error = false;
    });

    final store = TerminalLocalStore(ref.read(databaseProvider));
    await store.setDesiredDeckIds(terminal.deviceId, _desired);
    try {
      await ref.read(terminalApiProvider).updateDecks(terminal.deviceId, _desired);
      if (!mounted) return;
      setState(() => _message =
          'Estado desejado salvo. O Mnemos aplica na próxima sincronização.');
    } on Offline {
      if (!mounted) return;
      setState(() => _message = 'Salvo no celular. Será aplicado quando o backend '
          'ou o Mnemos estiver disponível.');
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _message = e.detail ??
            'Não foi possível atualizar o backend. A decisão continua salva aqui.';
        _error = true;
      });
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _applied = Set.of(_desired);
        });
      }
    }
  }

  Future<void> _syncBle() async {
    final terminal = _terminal;
    if (terminal == null || _overCapacity()) return;

    setState(() {
      _busy = true;
      _message = 'Procurando o Mnemos por Bluetooth…';
      _error = false;
    });

    try {
      final db = ref.read(databaseProvider);
      final study = await ref.read(studyServiceProvider.future);
      final service = TerminalSyncService(db, study);
      final bundle = await service.buildLibraryBundle(
        deckIds: _desired,
        maxCards: terminal.maxCards,
      );
      final report = await DeviceBle.sync(
        deviceId: terminal.deviceId,
        snapshotJson: jsonEncode(bundle),
      );
      final imported = await service.importReviewBatchJson(
        report.reviewsJson,
        deviceId: terminal.deviceId,
      );

      final store = TerminalLocalStore(db);
      await store.setActualDeckIds(terminal.deviceId, _desired);
      await store.markSync(
        terminal.deviceId,
        sentCards: report.sentCards,
        receivedReviews: imported.$1,
      );
      try {
        await ref.read(terminalApiProvider).reportObserved(
              terminal.deviceId,
              deckIds: _desired,
              cardCount: report.sentCards,
              maxCards: terminal.maxCards,
            );
      } on Object {
        // A sincronização direta terminou mesmo se a telemetria da nuvem falhar.
      }

      ref.invalidate(terminalLastSyncProvider);
      if (!mounted) return;
      setState(() {
        _actual = Set.of(_desired);
        _applied = Set.of(_desired);
        _message = 'Concluído: ${report.sentCards} cards no Mnemos e '
            '${imported.$1} revisões recebidas.';
      });
    } on PlatformException catch (e) {
      if (!mounted) return;
      setState(() {
        _message = e.message ?? 'Não foi possível sincronizar via Bluetooth.';
        _error = true;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _message = e.toString();
        _error = true;
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _openConnection() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const TerminalScreen()),
    );
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final terminal = _terminal;
    if (terminal == null) return _empty();

    final lastSync = ref.watch(terminalLastSyncProvider).valueOrNull;
    final now = ref.watch(clockProvider)();

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: ScreenBody(
          children: [
            BackHeader(label: 'Hoje', onMenu: _openConnection),
            const SizedBox(height: MnemosSpacing.md),
            Text(terminal.model, style: MnemosText.screenTitle),
            const SizedBox(height: 6),
            Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: const BoxDecoration(
                    color: MnemosColors.settled,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: MnemosSpacing.sm),
                Text('Conectado',
                    style: MnemosText.bodySmall.copyWith(fontSize: 13.5)),
                const SizedBox(width: MnemosSpacing.sm),
                Flexible(
                  child: Text(
                    terminal.deviceId,
                    style: MnemosText.mono.copyWith(color: MnemosColors.fainter),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: MnemosSpacing.xl),
            SurfaceCard(
              background: MnemosColors.softer,
              border: MnemosColors.line,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Eyebrow('memória', small: true),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Expanded(
                        child: MeterBar(
                          fraction: terminal.maxCards == 0
                              ? 0
                              : _desiredCards / terminal.maxCards,
                          track: MnemosColors.track,
                        ),
                      ),
                      const SizedBox(width: MnemosSpacing.sm),
                      Text('$_desiredCards/${terminal.maxCards}',
                          style: MnemosText.mono),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: MnemosSpacing.lg),
            SurfaceCard(
              radius: MnemosRadii.card,
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          lastSync == null
                              ? 'Ainda não sincronizou'
                              : 'Sincronizado ${relativeSince(lastSync, now)}',
                          style: MnemosText.itemTitle,
                        ),
                        const SizedBox(height: 3),
                        Text(
                          _pendingCards == 0
                              ? 'O aparelho está com o conteúdo escolhido.'
                              : '${plural(_pendingCards, "card novo esperando", "cards novos esperando")} envio',
                          style: MnemosText.caption,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: MnemosSpacing.md),
                  FilledButton(
                    onPressed: (_busy || !terminal.bleSync) ? null : _syncBle,
                    style: FilledButton.styleFrom(
                      minimumSize: Size.zero,
                      padding: const EdgeInsets.symmetric(
                        horizontal: MnemosSpacing.lg,
                        vertical: MnemosSpacing.md,
                      ),
                      textStyle: MnemosText.label.copyWith(fontSize: 14),
                    ),
                    child: const Text('Sincronizar'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: MnemosSpacing.xl),
            const Eyebrow('conteúdo no aparelho'),
            const SizedBox(height: MnemosSpacing.md),
            for (final deck in _decks)
              _DeckPresence(
                deck: deck,
                desired: _desired.contains(deck.id),
                actual: _actual.contains(deck.id),
                enabled: !_busy,
                onChanged: (present) => setState(() {
                  if (present) {
                    _desired.add(deck.id);
                  } else {
                    _desired.remove(deck.id);
                  }
                }),
              ),
            const Divider(),
            if (_message != null) ...[
              const SizedBox(height: MnemosSpacing.lg),
              Text(
                _message!,
                style: MnemosText.bodySmall.copyWith(
                  color: _error ? MnemosColors.dueText : MnemosColors.settledDeep,
                ),
              ),
            ],
            if (_dirty) ...[
              const SizedBox(height: MnemosSpacing.xl),
              FilledButton(
                onPressed: _busy ? null : _applyIntent,
                child: Text(_busy ? 'Salvando…' : 'Aplicar alterações'),
              ),
            ],
            const SizedBox(height: MnemosSpacing.xl),
            Row(
              children: [
                Eyebrow('firmware ${terminal.firmware}', small: true),
                const SizedBox(width: MnemosSpacing.xl),
                Eyebrow('protocolo v${terminal.protocol}', small: true),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// Nenhum terminal pareado. §5.1 — um estado vazio é uma tela, não um
  /// acidente: diz o que falta e como resolver.
  Widget _empty() {
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: MnemosSpacing.screen),
              child: BackHeader(label: 'Hoje'),
            ),
            // Centrado no que sobra da tela: empilhado no topo, o conteúdo
            // acabava em y≈650 de 1760 e o resto era branco morto.
            Expanded(
              child: StatusScreen(
                icon: Icons.tablet_mac_outlined,
                title: 'Nenhum Mnemos configurado',
                message: 'O pareamento acontece por aqui, lendo o QR Code do '
                    'aparelho. Depois disso você escolhe nesta tela o que vai nele.',
                action: _openConnection,
                actionLabel: 'Conectar um Mnemos',
              ),
            ),
          ],
        ),
      ),
    );
  }
}


/// Uma linha de baralho com a chave de presença no aparelho.
///
/// A legenda distingue o **desejado** do **observado**: marcar a chave declara
/// uma intenção, e até a próxima sincronização o aparelho ainda não a cumpriu.
/// Esconder essa diferença faria a chave mentir.
class _DeckPresence extends StatelessWidget {
  const _DeckPresence({
    required this.deck,
    required this.desired,
    required this.actual,
    required this.enabled,
    required this.onChanged,
  });

  final _DeckRow deck;
  final bool desired;
  final bool actual;
  final bool enabled;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final pending = desired != actual;

    return Column(
      children: [
        const Divider(),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: MnemosSpacing.md),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(deck.name, style: MnemosText.itemPrompt),
                    const SizedBox(height: 2),
                    Text(
                      pending
                          ? '${plural(deck.cardCount, "card", "cards")} · aguardando sincronização'
                          : plural(deck.cardCount, 'card', 'cards'),
                      style: MnemosText.caption.copyWith(
                        color: pending ? MnemosColors.dueText : MnemosColors.faint,
                      ),
                    ),
                  ],
                ),
              ),
              Switch(
                value: desired,
                onChanged: enabled ? onChanged : null,
              ),
            ],
          ),
        ),
      ],
    );
  }
}
