import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers.dart';
import '../theme.dart';
import 'editor_screen.dart';
import 'generation/capture_screen.dart';
import 'generation/generate_screen.dart';

/// Screen `34 Gerenciar baralho` — §5.10.
///
/// Rename, archive, delete, and add cards to it. Two distinctions the screen
/// has to make honestly, because both are easy to blur and expensive to get
/// wrong:
///
/// * **Archiving is not deleting.** An archived deck stops appearing and stops
///   scheduling; nothing is lost, and it comes back intact. It is the right
///   answer for "I finished this course", which is what most people mean when
///   they reach for delete.
/// * **Deleting a deck deletes its cards and their history.** §3 makes the
///   review log the source of truth, so this is not a tidy-up — it is throwing
///   away the record of having learned something.
class DeckManageScreen extends ConsumerStatefulWidget {
  const DeckManageScreen({super.key, required this.deckId, required this.deckName});

  final String deckId;
  final String deckName;

  @override
  ConsumerState<DeckManageScreen> createState() => _DeckManageScreenState();
}

class _DeckManageScreenState extends ConsumerState<DeckManageScreen> {
  bool _busy = false;

  Future<void> _rename() async {
    final controller = TextEditingController(text: widget.deckName);
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Nome do baralho'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(border: OutlineInputBorder()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text.trim()),
            child: const Text('Salvar'),
          ),
        ],
      ),
    );
    if (name == null || name.isEmpty || name == widget.deckName) return;

    final authoring = await ref.read(authoringServiceProvider.future);
    await authoring.renameDeck(widget.deckId, name, ref.read(clockProvider)());
    ref.invalidate(decksProvider);
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _archive() async {
    setState(() => _busy = true);
    final authoring = await ref.read(authoringServiceProvider.future);
    await authoring.archiveDeck(widget.deckId, ref.read(clockProvider)());
    ref
      ..invalidate(decksProvider)
      ..invalidate(deckCardCountsProvider)
      ..invalidate(queueProvider)
      ..invalidate(deckMaturityProvider);
    if (!mounted) return;
    Navigator.of(context).pop();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Arquivado. Nada foi perdido.')),
    );
  }

  Future<void> _delete() async {
    final counts = await ref.read(deckCardCountsProvider.future);
    if (!mounted) return;
    final total = counts[widget.deckId] ?? 0;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Apagar o baralho?'),
        content: Text(
          total == 0
              ? 'O baralho está vazio. Nada de histórico se perde.'
              : 'Apaga $total ${total == 1 ? "card" : "cards"} e todo o '
                  'histórico de revisão deles. Não dá para desfazer.\n\n'
                  'Se você só terminou o assunto, arquivar guarda tudo.',
          style: const TextStyle(fontSize: 13.5, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: FilledButton.styleFrom(backgroundColor: AppColors.again),
            child: const Text('Apagar'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _busy = true);
    final authoring = await ref.read(authoringServiceProvider.future);
    final removed = await authoring.deleteDeck(widget.deckId, ref.read(clockProvider)());
    ref
      ..invalidate(decksProvider)
      ..invalidate(deckCardCountsProvider)
      ..invalidate(queueProvider)
      ..invalidate(hasAnyCardsProvider)
      ..invalidate(deckMaturityProvider);

    if (!mounted) return;
    Navigator.of(context).pop();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Baralho apagado ($removed cards).')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.deckName)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 40),
        children: [
          const _Section('Adicionar cards'),
          const SizedBox(height: 10),
          // A IA primeiro, e com tamanho: é o caminho que produz vinte cards
          // em vinte segundos, contra vinte minutos digitando.
          _Primary(
            title: 'Gerar com IA',
            detail: 'Mais cards sobre este assunto, aprovados um a um.',
            onTap: _busy
                ? null
                : () => Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => GenerateScreen(
                        deckId: widget.deckId,
                        deckName: widget.deckName,
                      ),
                    )),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _Secondary(
                  icon: Icons.photo_camera_outlined,
                  label: 'Foto ou PDF',
                  onTap: _busy
                      ? null
                      : () => Navigator.of(context).push(MaterialPageRoute(
                            builder: (_) => CaptureScreen(deckId: widget.deckId),
                          )),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _Secondary(
                  icon: Icons.edit_outlined,
                  label: 'Escrever',
                  onTap: _busy
                      ? null
                      : () => Navigator.of(context).push(MaterialPageRoute(
                            builder: (_) => EditorScreen(
                              deckId: widget.deckId,
                              deckName: widget.deckName,
                            ),
                          )),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          const _Section('O baralho'),
          _Action(
            icon: Icons.drive_file_rename_outline,
            title: 'Renomear',
            detail: null,
            onTap: _busy ? null : _rename,
          ),
          _Action(
            icon: Icons.inventory_2_outlined,
            title: 'Arquivar',
            // The distinction this screen exists to make.
            detail: 'Some da lista e para de agendar. Volta inteiro.',
            onTap: _busy ? null : _archive,
          ),
          _Action(
            icon: Icons.delete_outline,
            title: 'Apagar',
            detail: 'Leva os cards e o histórico junto.',
            danger: true,
            onTap: _busy ? null : _delete,
          ),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section(this.title);

  final String title;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Text(title,
            style: const TextStyle(
                fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.faint)),
      );
}

class _Action extends StatelessWidget {
  const _Action({
    required this.icon,
    required this.title,
    required this.detail,
    required this.onTap,
    this.danger = false,
  });

  final IconData icon;
  final String title;
  final String? detail;
  final VoidCallback? onTap;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final colour = danger ? AppColors.again : AppColors.navy;

    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(icon, size: 20, color: onTap == null ? AppColors.faint : colour),
      title: Text(title,
          style: TextStyle(fontSize: 15, color: danger ? AppColors.again : AppColors.ink)),
      subtitle: detail == null
          ? null
          : Text(detail!,
              style: const TextStyle(fontSize: 12.5, height: 1.35, color: AppColors.faint)),
      onTap: onTap,
    );
  }
}


/// A ação que o produto quer que seja escolhida: grande, com a cor da ação e
/// espaço para explicar o que faz.
class _Primary extends StatelessWidget {
  const _Primary({required this.title, required this.detail, required this.onTap});

  final String title;
  final String detail;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    return Material(
      color: enabled ? AppColors.petrol : AppColors.mist,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 18, 16, 18),
          child: Row(
            children: [
              const Icon(Icons.auto_awesome, color: AppColors.ivory, size: 22),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: AppColors.ivory)),
                    const SizedBox(height: 3),
                    Text(detail,
                        style: TextStyle(
                            fontSize: 12.5,
                            height: 1.35,
                            color: AppColors.ivory.withValues(alpha: .8))),
                  ],
                ),
              ),
              Icon(Icons.chevron_right,
                  color: AppColors.ivory.withValues(alpha: .7), size: 22),
            ],
          ),
        ),
      ),
    );
  }
}

class _Secondary extends StatelessWidget {
  const _Secondary({required this.icon, required this.label, required this.onTap});

  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          border: Border.all(color: AppColors.mist),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          children: [
            Icon(icon, size: 19, color: enabled ? AppColors.petrol : AppColors.mist),
            const SizedBox(height: 7),
            Text(label,
                style: TextStyle(
                    fontSize: 12.5,
                    color: enabled ? AppColors.graphite : AppColors.mist)),
          ],
        ),
      ),
    );
  }
}
