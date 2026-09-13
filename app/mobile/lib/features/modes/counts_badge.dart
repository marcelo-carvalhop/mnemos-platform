import 'package:flutter/material.dart';

import '../../theme/tokens.dart';

/// The distinction §5.9 insists must be visible.
///
/// "A distinção entre o que conta para o agendamento e o que é treino extra é
/// conceitual e precisa aparecer no desenho, com rótulo ou cor consistente."
/// One widget, used by every mode, is how the label stays consistent — a user
/// who thinks extra practice is getting work done will distort their own
/// schedule.
class CountsBadge extends StatelessWidget {
  const CountsBadge({super.key, required this.counts, this.expanded = false});

  /// Whether the mode writes a review row (§5.2). Only multiple choice does.
  final bool counts;

  /// The long form, for the top of a session; the short form for a list.
  final bool expanded;

  @override
  Widget build(BuildContext context) {
    final colour = counts ? MnemosColors.good : MnemosColors.hard;
    final background = counts ? MnemosColors.goodSurface : MnemosColors.hardSurface;
    final label = counts ? 'Conta para o agendamento' : 'Treino extra';

    return Container(
      padding: EdgeInsets.symmetric(horizontal: 10, vertical: expanded ? 10 : 5),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(expanded ? 10 : 20),
      ),
      child: Row(
        mainAxisSize: expanded ? MainAxisSize.max : MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(counts ? Icons.event_available_outlined : Icons.fitness_center_outlined,
              size: expanded ? 16 : 13, color: colour),
          const SizedBox(width: 6),
          if (!expanded)
            Text(label,
                style: TextStyle(fontSize: 11, color: colour, fontWeight: FontWeight.w500))
          else
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label,
                      style: TextStyle(
                          fontSize: 12, color: colour, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 2),
                  Text(
                    counts
                        ? 'Suas respostas aqui entram no seu histórico e mudam quando cada card volta.'
                        : 'Nada aqui altera seu cronograma. É prática a mais, não revisão.',
                    style: TextStyle(fontSize: 11, height: 1.35, color: colour),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
