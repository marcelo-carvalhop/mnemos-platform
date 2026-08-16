import 'package:authoring/authoring.dart';
import 'package:domain/domain.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers.dart';
import '../theme.dart';

/// Screen `17 Criar card`.
///
/// The counter and the device preview are the point (§5.4): the limit exists
/// because of the e-reader screen, and showing the card at that shape is what
/// teaches someone to write a short card. Save is disabled while over — it is
/// a hard restriction, not a suggestion.
class EditorScreen extends ConsumerStatefulWidget {
  const EditorScreen({super.key, required this.deckId, required this.deckName});

  final String deckId;
  final String deckName;

  @override
  ConsumerState<EditorScreen> createState() => _EditorScreenState();
}

class _EditorScreenState extends ConsumerState<EditorScreen> {
  final _front = TextEditingController();
  final _back = TextEditingController();

  @override
  void dispose() {
    _front.dispose();
    _back.dispose();
    super.dispose();
  }

  int get _frontLength => CardText.graphemeLength(_front.text);
  int get _backLength => CardText.graphemeLength(_back.text);

  bool get _canSave =>
      _front.text.trim().isNotEmpty &&
      _back.text.trim().isNotEmpty &&
      _frontLength <= kFrontMaxGraphemes &&
      _backLength <= kBackMaxGraphemes;

  Future<void> _save({required bool another}) async {
    final authoring = await ref.read(authoringServiceProvider.future);
    try {
      await authoring.createCard(
        deckId: widget.deckId,
        front: _front.text.trim(),
        back: _back.text.trim(),
        at: ref.read(clockProvider)(),
      );
    } on CardTooLong catch (e) {
      // Belt and braces: the button is disabled, and the service refuses
      // anyway. The rule has one home (§5.4).
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
      }
      return;
    }

    ref.invalidate(deckMaturityProvider);
    ref.invalidate(queueProvider);

    if (!mounted) return;
    if (another) {
      _front.clear();
      _back.clear();
      setState(() {});
      FocusScope.of(context).unfocus();
    } else {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.deckName)),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            _Field(
              label: 'Frente',
              controller: _front,
              length: _frontLength,
              limit: kFrontMaxGraphemes,
              minLines: 2,
              onChanged: () => setState(() {}),
            ),
            const SizedBox(height: 20),
            _Field(
              label: 'Verso',
              controller: _back,
              length: _backLength,
              limit: kBackMaxGraphemes,
              minLines: 3,
              onChanged: () => setState(() {}),
            ),
            const SizedBox(height: 26),
            const Text('Como fica no aparelho',
                style: TextStyle(fontSize: 12, color: AppColors.faint)),
            const SizedBox(height: 8),
            _DevicePreview(text: _front.text.isEmpty ? 'Frente do card' : _front.text),
            const SizedBox(height: 28),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _canSave ? () => _save(another: false) : null,
                    child: const Text('Salvar e sair'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton(
                    onPressed: _canSave ? () => _save(another: true) : null,
                    child: const Text('Salvar e criar outro'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Field extends StatelessWidget {
  const _Field({
    required this.label,
    required this.controller,
    required this.length,
    required this.limit,
    required this.minLines,
    required this.onChanged,
  });

  final String label;
  final TextEditingController controller;
  final int length;
  final int limit;
  final int minLines;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final over = length > limit;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: const TextStyle(fontSize: 12, color: AppColors.faint)),
            Text(
              '$length / $limit',
              style: TextStyle(
                fontSize: 12,
                color: over ? AppColors.again : AppColors.faint,
                fontWeight: over ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          minLines: minLines,
          maxLines: minLines + 3,
          onChanged: (_) => onChanged(),
          decoration: InputDecoration(
            filled: true,
            fillColor: over ? const Color(0xFFFEFBFB) : AppColors.ivory,
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(
                color: over ? const Color(0xFFE8B4AE) : AppColors.hairline,
                width: over ? 1.6 : 1,
              ),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: over ? AppColors.again : AppColors.navy),
            ),
          ),
        ),
        if (over) ...[
          const SizedBox(height: 6),
          Text(
            '${length - limit} ${length - limit == 1 ? "caractere acima" : "caracteres acima"} do limite. '
            'O card precisa caber na tela do aparelho.',
            style: const TextStyle(fontSize: 11, color: AppColors.again),
          ),
        ],
      ],
    );
  }
}

/// The card at the shape and type size of the device (§5.4).
///
/// Present before the device exists, because it is what teaches the user to
/// write short.
class _DevicePreview extends StatelessWidget {
  const _DevicePreview({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 130,
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(horizontal: 22),
      decoration: BoxDecoration(
        color: const Color(0xFFFBFBF9),
        border: Border.all(color: AppColors.hairline),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: const TextStyle(
          fontSize: 15,
          height: 1.4,
          color: Color(0xFF2A2A28),
          fontFamily: 'serif',
        ),
      ),
    );
  }
}
