import 'dart:convert';
import 'dart:io';

import 'package:api_client/api_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../providers.dart';
import '../providers_sync.dart';
import '../theme.dart';

/// §8.4 — export and deletion.
///
/// The product is Brazilian and the LGPD applies, so neither of these is a
/// feature to be traded away: they are rights. The screen is written to make
/// both easy to find and only one of them easy to do by accident.
class AccountScreen extends ConsumerStatefulWidget {
  const AccountScreen({super.key});

  @override
  ConsumerState<AccountScreen> createState() => _AccountScreenState();
}

class _AccountScreenState extends ConsumerState<AccountScreen> {
  bool _busy = false;

  Future<void> _export() async {
    setState(() => _busy = true);
    try {
      final data = await ref.read(accountApiProvider).export();
      final file = File(
        '${(await getTemporaryDirectory()).path}/mnemos-export.json',
      );
      await file.writeAsString(const JsonEncoder.withIndent('  ').convert(data));

      // Handed to the OS share sheet rather than dropped somewhere the user
      // has to go looking: an export they cannot find is not an export.
      await Share.shareXFiles(
        [XFile(file.path)],
        subject: 'Meus cards e histórico',
      );
    } on Offline {
      _say('Sem conexão. O export vem do servidor, então precisa de internet.');
    } on Object catch (e) {
      _say('Não consegui exportar: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => const _DeleteDialog(),
    );
    if (confirmed != true) return;

    setState(() => _busy = true);
    try {
      await ref.read(accountApiProvider).delete(confirmation: 'APAGAR');
      await ref.read(tokenStoreProvider).clear();

      // The local database is the source of truth (§3), so deleting the
      // account on the server and leaving the cards here would be a lie about
      // what was deleted.
      final db = ref.read(databaseProvider);
      await db.transaction(() async {
        for (final table in db.allTables) {
          await db.delete(table).go();
        }
      });

      if (!mounted) return;
      Navigator.of(context).popUntil((route) => route.isFirst);
      _say('Conta apagada. Nada ficou.');
    } on Offline {
      _say('Sem conexão. Apagar a conta precisa falar com o servidor.');
    } on Object catch (e) {
      _say('Não consegui apagar: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _say(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Seus dados')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 40),
        children: [
          const Text(
            'Exportar seus dados',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
          ),
          const SizedBox(height: 8),
          const Text(
            'Um arquivo JSON com seus baralhos, seus cards e todo o histórico '
            'de revisões. É o suficiente para reconstruir tudo — inclusive se '
            'você parar de pagar.',
            style: TextStyle(fontSize: 13, height: 1.5, color: AppColors.muted),
          ),
          const SizedBox(height: 14),
          OutlinedButton(
            onPressed: _busy ? null : _export,
            child: const Text('Exportar'),
          ),
          const SizedBox(height: 36),
          const Divider(color: AppColors.hairline),
          const SizedBox(height: 24),
          const Text(
            'Apagar a conta',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
          ),
          const SizedBox(height: 8),
          const Text(
            'Apaga os cards, o histórico e a conta, no servidor e neste '
            'aparelho. Não dá para desfazer, e não guardamos cópia.',
            style: TextStyle(fontSize: 13, height: 1.5, color: AppColors.muted),
          ),
          const SizedBox(height: 8),
          // Said out loud rather than discovered later: §8.1 attaches the free
          // allowance to the device precisely so a reinstall cannot mint a
          // second one, and deleting the account is a reinstall with an extra
          // step.
          const Text(
            'Sua geração grátis não volta — ela é uma por aparelho, para '
            'sempre.',
            style: TextStyle(fontSize: 12, height: 1.45, color: AppColors.faint),
          ),
          const SizedBox(height: 14),
          OutlinedButton(
            onPressed: _busy ? null : _delete,
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.again,
              side: const BorderSide(color: AppColors.again),
            ),
            child: const Text('Apagar minha conta'),
          ),
        ],
      ),
    );
  }
}

/// Typed, not tapped.
///
/// Deletion is irreversible and the review log is years of someone's work; a
/// confirmation that can be produced by a mis-tap is not a confirmation.
class _DeleteDialog extends StatefulWidget {
  const _DeleteDialog();

  @override
  State<_DeleteDialog> createState() => _DeleteDialogState();
}

class _DeleteDialogState extends State<_DeleteDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ready = _controller.text.trim() == 'APAGAR';

    return AlertDialog(
      title: const Text('Apagar tudo?'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Escreva APAGAR para confirmar. Não dá para desfazer.',
            style: TextStyle(fontSize: 13, height: 1.45),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _controller,
            autofocus: true,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              hintText: 'APAGAR',
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: ready ? () => Navigator.of(context).pop(true) : null,
          style: FilledButton.styleFrom(backgroundColor: AppColors.again),
          child: const Text('Apagar'),
        ),
      ],
    );
  }
}
