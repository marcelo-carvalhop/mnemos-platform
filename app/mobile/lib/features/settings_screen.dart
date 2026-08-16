import 'package:domain/domain.dart';
import 'package:drift/drift.dart' show InsertMode, Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:store/store.dart';

import '../providers.dart';
import '../providers_sync.dart';
import 'account_screen.dart';
import 'subscription_screen.dart';
import 'device_screen.dart';
import '../theme.dart';

/// Screen `10 Configurações` — §5.12, §5.7, §8.
///
/// §13 lists what the canvas was missing here: the retention target, the daily
/// limits, the timezone and day cutoff (§5.7), and the account. They are on one
/// screen because they are all "how the app behaves for me", and separating
/// them would only make the ones people need hardest to find.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(userSettingsProvider);
    final quota = ref.watch(quotaProvider);
    final local = ref.watch(localSettingsProvider).valueOrNull ?? const <String, String>{};

    return Scaffold(
      appBar: AppBar(title: const Text('Configurações')),
      body: settings.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('$e')),
        data: (values) => ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
          children: [
            const _Section('Estudo'),
            _NumberRow(
              label: 'Cards novos por dia',
              detail: 'Quantos cards inéditos entram na fila.',
              value: int.tryParse(values['new_per_day'] ?? '') ?? 10,
              min: 0,
              max: 100,
              step: 5,
              onChanged: (v) => _write(ref, 'new_per_day', '$v'),
            ),
            _NumberRow(
              label: 'Revisões por dia',
              detail: 'Teto para não acordar com quatrocentas.',
              value: int.tryParse(values['review_per_day'] ?? '') ?? 200,
              min: 20,
              max: 500,
              step: 20,
              onChanged: (v) => _write(ref, 'review_per_day', '$v'),
            ),
            _SliderRow(
              label: 'Meta de retenção',
              // §3.1 — this is an input to the interval formula, which is why
              // it syncs. Raising it means shorter intervals and more work
              // per day, and the screen says so instead of leaving it as a
              // mystery dial.
              detail: 'Mais alto significa intervalos mais curtos e mais '
                  'revisões por dia.',
              value: double.tryParse(values['desired_retention'] ?? '') ?? kDesiredRetention,
              onChanged: (v) => _write(ref, 'desired_retention', v.toStringAsFixed(2)),
            ),
            const SizedBox(height: 22),
            const _Section('O seu dia'),
            _CutoffRow(
              value: int.tryParse(values['day_cutoff_hour'] ?? '') ?? kDefaultDayCutoffHour,
              onChanged: (v) => _write(ref, 'day_cutoff_hour', '$v'),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Fuso horário', style: TextStyle(fontSize: 15)),
              subtitle: Text(
                values['timezone'] ?? 'America/Sao_Paulo',
                style: const TextStyle(fontSize: 12.5, color: AppColors.faint),
              ),
            ),
            const SizedBox(height: 22),
            const _Section('Lembrete'),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Lembrar de revisar', style: TextStyle(fontSize: 15)),
              subtitle: const Text(
                'Só chega quando há cards vencendo.',
                style: TextStyle(fontSize: 12.5, color: AppColors.faint),
              ),
              value: (local['reminder_enabled'] ?? '0') == '1',
              onChanged: (on) async {
                if (on && !await ref.read(remindersProvider).requestPermission()) {
                  return;
                }
                // §5.4 — local_settings, never synced: a reminder is a
                // property of a phone, not of a person.
                await writeLocalSetting(ref, 'reminder_enabled', on ? '1' : '0');
                await refreshReminder(ref);
              },
            ),
            if ((local['reminder_enabled'] ?? '0') == '1')
              Row(
                children: [
                  const Expanded(child: Text('Horário', style: TextStyle(fontSize: 15))),
                  DropdownButton<int>(
                    value: int.tryParse(local['reminder_hour'] ?? '') ?? 20,
                    underline: const SizedBox.shrink(),
                    items: [
                      for (var hour = 6; hour <= 23; hour++)
                        DropdownMenuItem(
                          value: hour,
                          child: Text('${hour.toString().padLeft(2, '0')}:00'),
                        ),
                    ],
                    onChanged: (v) async {
                      if (v == null) return;
                      await writeLocalSetting(ref, 'reminder_hour', '$v');
                      await refreshReminder(ref);
                    },
                  ),
                ],
              ),
            const SizedBox(height: 22),
            const _Section('Conta e dispositivos'),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.devices_other_outlined, color: AppColors.petrol),
              title: const Text('Dispositivo', style: TextStyle(fontSize: 15)),
              subtitle: const Text(
                'Identidade e configuração de conexão.',
                style: TextStyle(fontSize: 12.5, color: AppColors.faint),
              ),
              trailing: const Icon(Icons.chevron_right, color: AppColors.faint),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const DeviceScreen()),
              ),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Gerações por IA', style: TextStyle(fontSize: 15)),
              trailing: const Icon(Icons.chevron_right, color: AppColors.faint),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const SubscriptionScreen()),
              ),
              subtitle: Text(
                switch (quota.valueOrNull) {
                  null => 'Verificando…',
                  (remaining: -1, limit: _, plan: _) => 'Sem conexão',
                  (remaining: 0, limit: _, plan: _) => 'Sua geração grátis já foi usada',
                  (remaining: final r, limit: final l, plan: _) =>
                    r == 1 ? '1 de $l disponível' : '$r de $l disponíveis',
                },
                style: const TextStyle(fontSize: 12.5, color: AppColors.faint),
              ),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Seus dados', style: TextStyle(fontSize: 15)),
              subtitle: const Text(
                'Exportar tudo, ou apagar a conta.',
                style: TextStyle(fontSize: 12.5, color: AppColors.faint),
              ),
              trailing: const Icon(Icons.chevron_right, color: AppColors.faint),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const AccountScreen()),
              ),
            ),
            const SizedBox(height: 22),
            const _Section('Sobre'),
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Text(
                'Seus cards ficam neste aparelho e são copiados para o servidor '
                'como backup. Estudar funciona sem internet.',
                style: TextStyle(fontSize: 12.5, height: 1.5, color: AppColors.faint),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Settings that change how scheduling behaves are synced (§5.4), so they go
  /// through `user_settings` with a fresh `updated_at` — which is what makes
  /// last-writer-wins mean anything between two devices.
  static Future<void> _write(WidgetRef ref, String key, String value) async {
    final db = ref.read(databaseProvider);
    final now = ref.read(clockProvider)();
    await db.into(db.userSettings).insert(
          UserSettingsCompanion.insert(
            key: key,
            value: value,
            updatedAt: now.millisecondsSinceEpoch,
            deviceId: await ref.read(deviceIdProvider.future),
            serverSeq: const Value.absent(),
          ),
          mode: InsertMode.insertOrReplace,
        );
    ref.invalidate(userSettingsProvider);
    ref.invalidate(fsrsParamsProvider);
    ref.invalidate(dayBucketProvider);
    ref.invalidate(queueProvider);
  }
}

class _Section extends StatelessWidget {
  const _Section(this.title);

  final String title;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(title,
            style: const TextStyle(
                fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.faint)),
      );
}

class _NumberRow extends StatelessWidget {
  const _NumberRow({
    required this.label,
    required this.detail,
    required this.value,
    required this.min,
    required this.max,
    required this.step,
    required this.onChanged,
  });

  final String label;
  final String detail;
  final int value;
  final int min;
  final int max;
  final int step;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: const TextStyle(fontSize: 15)),
                const SizedBox(height: 2),
                Text(detail,
                    style: const TextStyle(fontSize: 12, color: AppColors.faint)),
              ],
            ),
          ),
          IconButton(
            onPressed: value > min ? () => onChanged(value - step) : null,
            icon: const Icon(Icons.remove_circle_outline),
          ),
          SizedBox(
            width: 44,
            child: Text('$value',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500)),
          ),
          IconButton(
            onPressed: value < max ? () => onChanged(value + step) : null,
            icon: const Icon(Icons.add_circle_outline),
          ),
        ],
      ),
    );
  }
}

class _SliderRow extends StatelessWidget {
  const _SliderRow({
    required this.label,
    required this.detail,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final String detail;
  final double value;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(label, style: const TextStyle(fontSize: 15))),
              Text('${(value * 100).round()}%',
                  style: const TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w500, color: AppColors.navy)),
            ],
          ),
          const SizedBox(height: 2),
          Text(detail, style: const TextStyle(fontSize: 12, height: 1.4, color: AppColors.faint)),
          Slider(
            value: value,
            // Below 0.80 the schedule stops being a schedule and above 0.95
            // the workload explodes; neither end is a choice worth offering.
            min: 0.80,
            max: 0.95,
            divisions: 15,
            label: '${(value * 100).round()}%',
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}

class _CutoffRow extends StatelessWidget {
  const _CutoffRow({required this.value, required this.onChanged});

  final int value;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text('O dia vira às', style: TextStyle(fontSize: 15)),
              ),
              DropdownButton<int>(
                value: value,
                underline: const SizedBox.shrink(),
                items: [
                  for (final hour in [0, 1, 2, 3, 4, 5, 6])
                    DropdownMenuItem(
                      value: hour,
                      child: Text('${hour.toString().padLeft(2, '0')}:00'),
                    ),
                ],
                onChanged: (v) => v == null ? null : onChanged(v),
              ),
            ],
          ),
          const SizedBox(height: 2),
          // §5.7 — the reason this setting exists at all. Someone studying at
          // 01:00 is still having Tuesday, and a day that rolls at midnight
          // breaks their streak for being awake.
          const Text(
            'Estudar de madrugada conta para o dia anterior. Mudar isto não '
            'reescreve o passado — vale a partir de hoje.',
            style: TextStyle(fontSize: 12, height: 1.4, color: AppColors.faint),
          ),
        ],
      ),
    );
  }
}
