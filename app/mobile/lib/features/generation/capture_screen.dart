import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:store/store.dart' show Deck;

import '../../providers.dart';
import '../../providers_sync.dart';
import '../../theme.dart';
import 'error_copy.dart';
import 'generating_screen.dart';
import 'paywall_screen.dart';

/// Screen `20 Capturar material` — §5.6.
///
/// A page of a book, a handwritten notebook, a lecture slide, or a PDF. The
/// file goes straight to storage on a pre-signed URL and only its key reaches
/// our API (§7.2) — a forty-megabyte PDF must not pass through a request
/// handler.
class CaptureScreen extends ConsumerStatefulWidget {
  const CaptureScreen({super.key, this.deckId});

  final String? deckId;

  @override
  ConsumerState<CaptureScreen> createState() => _CaptureScreenState();
}

class _CaptureScreenState extends ConsumerState<CaptureScreen> {
  /// §7.2's ceiling. Checked here as well as on the server, because finding
  /// out after a two-minute upload on mobile data is a bad way to learn it.
  static const _maxBytes = 25 * 1024 * 1024;

  String? _deckId;
  ({String name, Uint8List bytes, String contentType})? _picked;
  String? _problem;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _deckId = widget.deckId;
  }

  Future<void> _pickPhoto(ImageSource source) async {
    final file = await ImagePicker().pickImage(
      source: source,
      // Enough for the model to read a page; far less than a 12-megapixel
      // original, which is minutes of upload for no extra legibility.
      maxWidth: 2200,
      imageQuality: 88,
    );
    if (file == null) return;
    await _accept(file.name, await file.readAsBytes(), 'image/jpeg');
  }

  Future<void> _pickPdf() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf'],
      withData: true,
    );
    final file = result?.files.singleOrNull;
    if (file == null) return;

    final bytes = file.bytes ??
        (file.path == null ? null : await File(file.path!).readAsBytes());
    if (bytes == null) return;
    await _accept(file.name, bytes, 'application/pdf');
  }

  Future<void> _accept(String name, Uint8List bytes, String contentType) async {
    if (bytes.length > _maxBytes) {
      setState(() {
        _picked = null;
        _problem = GenerationFailure.forCode('file_too_large').detail;
      });
      return;
    }
    setState(() {
      _picked = (name: name, bytes: bytes, contentType: contentType);
      _problem = null;
    });
  }

  Future<void> _send(String deckId) async {
    final picked = _picked;
    if (picked == null) return;

    setState(() => _busy = true);
    final api = ref.read(generationApiProvider);
    try {
      // O baralho de destino pode ter nascido offline e ainda não existir no
      // servidor, que então recusa o job com 404. Empurrar antes de pedir.
      try {
        await ref.read(syncClientProvider).pushAll();
      } on Object {
        // A falha real aparece abaixo, com a copy certa.
      }

      final target = await api.createUpload(picked.contentType);
      await api.upload(target.url, picked.bytes, picked.contentType);

      final job = await api.create(
        sourceType: picked.contentType == 'application/pdf' ? 'pdf' : 'photo',
        targetDeckId: deckId,
        uploadKey: target.uploadKey,
      );

      if (!mounted) return;
      await Navigator.of(context).pushReplacement(MaterialPageRoute(
        builder: (_) => GeneratingScreen(jobId: job.id, deckId: deckId),
      ));
    } on Object catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      final failure = GenerationFailure.forException(e);
      if (failure.showsPaywall) {
        await Navigator.of(context)
            .push(MaterialPageRoute(builder: (_) => const PaywallScreen()));
        return;
      }
      if (!mounted) return;
      setState(() => _problem = '${failure.title}. ${failure.detail}');
    }
  }

  @override
  Widget build(BuildContext context) {
    final decks = ref.watch(decksProvider).valueOrNull ?? const <Deck>[];
    final target = _deckId ?? (decks.isNotEmpty ? decks.first.id : null);
    final picked = _picked;

    return Scaffold(
      appBar: AppBar(title: const Text('Capturar material')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
          children: [
            const Text(
              'Fotografe uma página, um caderno ou o quadro — ou escolha um PDF.',
              style: TextStyle(fontSize: 13.5, height: 1.5, color: AppColors.muted),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: _Source(
                    icon: Icons.photo_camera_outlined,
                    label: 'Tirar foto',
                    onTap: _busy ? null : () => _pickPhoto(ImageSource.camera),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _Source(
                    icon: Icons.image_outlined,
                    label: 'Da galeria',
                    onTap: _busy ? null : () => _pickPhoto(ImageSource.gallery),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _Source(
                    icon: Icons.picture_as_pdf_outlined,
                    label: 'PDF',
                    onTap: _busy ? null : _pickPdf,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            const Text(
              'Escrita à mão funciona. Foto reta, sem sombra sobre o texto.',
              style: TextStyle(fontSize: 11.5, height: 1.4, color: AppColors.faint),
            ),
            if (picked != null) ...[
              const SizedBox(height: 22),
              _Preview(
                name: picked.name,
                bytes: picked.bytes,
                isPdf: picked.contentType == 'application/pdf',
                onRemove: _busy ? null : () => setState(() => _picked = null),
              ),
            ],
            if (_problem != null) ...[
              const SizedBox(height: 16),
              Text(_problem!,
                  style: const TextStyle(fontSize: 12.5, height: 1.45, color: AppColors.again)),
            ],
            const SizedBox(height: 26),
            if (decks.length > 1) ...[
              const Text('Baralho de destino',
                  style: TextStyle(fontSize: 12, color: AppColors.faint)),
              const SizedBox(height: 6),
              DropdownButtonFormField<String>(
                initialValue: target,
                decoration: const InputDecoration(border: OutlineInputBorder()),
                items: [
                  for (final d in decks) DropdownMenuItem(value: d.id, child: Text(d.name)),
                ],
                onChanged: (v) => setState(() => _deckId = v),
              ),
              const SizedBox(height: 22),
            ],
            FilledButton(
              onPressed: picked == null || target == null || _busy
                  ? null
                  : () => _send(target),
              child: _busy
                  ? const SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.ivory),
                    )
                  : const Text('Gerar cards deste material'),
            ),
            const SizedBox(height: 10),
            const Center(
              child: Text(
                'O arquivo é apagado depois que os cards são criados.',
                style: TextStyle(fontSize: 11.5, color: AppColors.faint),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Source extends StatelessWidget {
  const _Source({required this.icon, required this.label, required this.onTap});

  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 18),
        decoration: BoxDecoration(
          border: Border.all(color: AppColors.hairline),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          children: [
            Icon(icon, size: 22, color: onTap == null ? AppColors.faint : AppColors.navy),
            const SizedBox(height: 8),
            Text(label,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 11.5, color: AppColors.muted)),
          ],
        ),
      ),
    );
  }
}

class _Preview extends StatelessWidget {
  const _Preview({
    required this.name,
    required this.bytes,
    required this.isPdf,
    required this.onRemove,
  });

  final String name;
  final Uint8List bytes;
  final bool isPdf;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final kb = (bytes.length / 1024).round();

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.fill,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: isPdf
                ? Container(
                    width: 52,
                    height: 52,
                    color: AppColors.ivory,
                    child: const Icon(Icons.picture_as_pdf_outlined,
                        color: AppColors.navy, size: 24),
                  )
                : Image.memory(bytes, width: 52, height: 52, fit: BoxFit.cover),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 13)),
                const SizedBox(height: 2),
                Text(kb > 1024 ? '${(kb / 1024).toStringAsFixed(1)} MB' : '$kb KB',
                    style: const TextStyle(fontSize: 11.5, color: AppColors.faint)),
              ],
            ),
          ),
          IconButton(onPressed: onRemove, icon: const Icon(Icons.close, size: 18)),
        ],
      ),
    );
  }
}
