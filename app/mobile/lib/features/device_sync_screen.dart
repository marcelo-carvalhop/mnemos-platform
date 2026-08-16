import 'dart:convert';

import 'package:api_client/api_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../device/device_ble.dart';
import '../device/terminal_local_store.dart';
import '../device/terminal_sync_service.dart';
import '../providers.dart';
import '../providers_sync.dart';
import '../theme.dart';

class DeviceSyncScreen extends ConsumerStatefulWidget {
  const DeviceSyncScreen({super.key});

  @override
  ConsumerState<DeviceSyncScreen> createState() => _DeviceSyncScreenState();
}

class _DeckRow {
  const _DeckRow(this.id, this.name, this.cardCount);
  final String id;
  final String name;
  final int cardCount;
}

class _DeviceSyncScreenState extends ConsumerState<DeviceSyncScreen> {
  StoredTerminal? _terminal;
  List<_DeckRow> _decks = const [];
  Set<String> _desired = {};
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

      // The phone owns the user's desired-state decision. An explicit empty
      // local set therefore means "remove everything", not "not loaded".
      if (!hasLocalIntent) {
        desired = remote.desiredDeckIds.toSet();
        await store.setDesiredDeckIds(terminal.deviceId, desired);
      }

      // Physical state can arrive from BLE or the backend. Keep whichever
      // observation is newer so a direct/offline sync is not overwritten by a
      // stale cloud report on the next screen open.
      final remoteSyncAt = DateTime.tryParse(remote.lastSyncAt ?? '');
      final remoteIsAtLeastAsFresh = localSyncAt == null ||
          (remoteSyncAt != null && !remoteSyncAt.isBefore(localSyncAt));
      if (remoteIsAtLeastAsFresh) {
        actual = remote.reportedDeckIds.toSet();
        await store.setActualDeckIds(terminal.deviceId, actual);
      }
    } on Offline {
      // Offline is expected. Local intent/state remain fully usable.
    } on ApiException {
      // Keep local state. The screen must remain useful without the backend.
    }

    if (!mounted) return;
    setState(() {
      _terminal = terminal;
      _decks = [for (final r in rows) _DeckRow(r.read<String>('id'), r.read<String>('name'), r.read<int>('card_count'))];
      _desired = desired;
      _actual = actual;
      _loading = false;
    });
  }

  int get _desiredCardCount => _decks
      .where((d) => _desired.contains(d.id))
      .fold(0, (sum, d) => sum + d.cardCount);

  Future<void> _applyIntent() async {
    final terminal = _terminal;
    if (terminal == null) return;
    if (_desiredCardCount > terminal.maxCards) {
      setState(() {
        _message = 'O estado escolhido usa $_desiredCardCount cards, acima da capacidade de ${terminal.maxCards} deste terminal.';
        _error = true;
      });
      return;
    }

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
      setState(() => _message = 'Estado desejado salvo. O Mnemos aplicará as alterações na próxima sincronização.');
    } on Offline {
      if (!mounted) return;
      setState(() => _message = 'Estado desejado salvo no celular. Será aplicado quando o backend ou o Mnemos estiver disponível.');
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _message = e.detail ?? 'Não foi possível atualizar o backend. A decisão continua salva localmente.';
        _error = true;
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _syncBle() async {
    final terminal = _terminal;
    if (terminal == null) return;
    if (_desiredCardCount > terminal.maxCards) {
      setState(() {
        _message = 'A seleção atual excede a capacidade do terminal.';
        _error = true;
      });
      return;
    }

    setState(() {
      _busy = true;
      _message = 'Procurando o Mnemos por Bluetooth…';
      _error = false;
    });
    try {
      final db = ref.read(databaseProvider);
      final study = await ref.read(studyServiceProvider.future);
      final service = TerminalSyncService(db, study);
      final bundle = await service.buildLibraryBundle(deckIds: _desired, maxCards: terminal.maxCards);
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
        // Direct BLE sync is complete even if cloud telemetry is offline.
      }
      if (!mounted) return;
      setState(() {
        _actual = Set.of(_desired);
        _message = 'Sincronização concluída: ${report.sentCards} cards no Mnemos e ${imported.$1} revisões recebidas.';
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

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final terminal = _terminal;
    if (terminal == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Sincronização')),
        body: Center(child: Padding(padding: EdgeInsets.all(28), child: Text('Conecte um Mnemos antes de escolher o conteúdo do dispositivo.'))),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Sincronização')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 36),
        children: [
          Text(terminal.deviceId, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 4),
          Text('$_desiredCardCount de ${terminal.maxCards} cards', style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 24),
          for (final deck in _decks) ...[
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
            const Divider(height: 1),
          ],
          if (_message != null) ...[
            const SizedBox(height: 18),
            Text(_message!, style: TextStyle(color: _error ? AppColors.terracotta : AppColors.sage, height: 1.4)),
          ],
          const SizedBox(height: 26),
          FilledButton(
            onPressed: _busy ? null : _applyIntent,
            child: Text(_busy ? 'Salvando…' : 'Aplicar alterações'),
          ),
          const SizedBox(height: 10),
          OutlinedButton(
            onPressed: _busy || !terminal.bleSync ? null : _syncBle,
            child: Text(terminal.bleSync ? 'Sincronizar agora por Bluetooth' : 'Bluetooth não disponível neste firmware'),
          ),
        ],
      ),
    );
  }
}

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
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(deck.name, style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w500)),
          const SizedBox(height: 5),
          Text(
            'App · ${deck.cardCount} cards     Mnemos · ${actual ? 'presente' : 'ausente'}',
            style: const TextStyle(fontSize: 12.5, color: AppColors.sage),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: SegmentedButton<bool>(
              segments: const [
                ButtonSegment(value: true, label: Text('No Mnemos')),
                ButtonSegment(value: false, label: Text('Somente no app')),
              ],
              selected: {desired},
              onSelectionChanged: enabled ? (selection) => onChanged(selection.first) : null,
              showSelectedIcon: false,
            ),
          ),
          if (pending) ...[
            const SizedBox(height: 7),
            const Text(
              'Alteração pendente',
              style: TextStyle(fontSize: 12, color: AppColors.brass),
            ),
          ],
        ],
      ),
    );
  }
}
