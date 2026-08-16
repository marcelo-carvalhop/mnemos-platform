import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:store/store.dart' as store;

import '../providers.dart';
import '../theme.dart';

/// Screen `09 Buscar` — §5.10.
///
/// Searches as you type, through the FTS index whose tokenizer strips accents
/// — someone typing "funcao" in a hurry finds "função", which is the whole
/// reason that setting was chosen.
class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  final _controller = TextEditingController();
  Timer? _debounce;
  List<store.Card> _results = const [];
  bool _searched = false;

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onChanged(String query) {
    // Debounced, because a query per keystroke on a collection of thousands is
    // a query per keystroke.
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 180), () => _run(query));
  }

  Future<void> _run(String query) async {
    final results = await ref.read(databaseProvider).searchCards(query);
    if (!mounted) return;
    setState(() {
      _results = results;
      _searched = query.trim().isNotEmpty;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: TextField(
          controller: _controller,
          autofocus: true,
          onChanged: _onChanged,
          decoration: const InputDecoration(
            border: InputBorder.none,
            hintText: 'Buscar nos seus cards',
            hintStyle: TextStyle(fontSize: 16, color: AppColors.faint),
          ),
        ),
        actions: [
          if (_controller.text.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.close),
              onPressed: () {
                _controller.clear();
                setState(() {
                  _results = const [];
                  _searched = false;
                });
              },
            ),
        ],
      ),
      body: !_searched
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Text(
                  'Procure por qualquer palavra da frente ou do verso.\n'
                  'Acentos não fazem diferença.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 13, height: 1.6, color: AppColors.faint),
                ),
              ),
            )
          : _results.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Text(
                      'Nada encontrado para "${_controller.text.trim()}".',
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 13, color: AppColors.muted),
                    ),
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: _results.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (context, i) => _Result(card: _results[i]),
                ),
    );
  }
}

class _Result extends StatelessWidget {
  const _Result({required this.card});

  final store.Card card;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.hairline),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(card.front, style: const TextStyle(fontSize: 14.5, height: 1.35)),
          const SizedBox(height: 6),
          Text(
            card.back,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 12.5, height: 1.4, color: AppColors.muted),
          ),
        ],
      ),
    );
  }
}
