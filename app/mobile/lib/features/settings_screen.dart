import 'package:domain/domain.dart';
import 'package:drift/drift.dart' show InsertMode, Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:store/store.dart';

import '../legal.dart';
import '../providers.dart';
import '../providers_sync.dart';
import 'account_screen.dart';
import 'subscription_screen.dart';
import 'device_screen.dart';
import '../theme/tokens.dart';
import '../theme/typography.dart';
import '../ui/ui.dart';

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
      
      body: settings.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('$e')),
        data: (values) => SafeArea(
        bottom: false,
        child: ScreenBody(
          children: [
            BackHeader(label: 'Hoje'),
            const SizedBox(height: MnemosSpacing.md),
            const Text('Configurações', style: MnemosText.screenTitle),
            const SizedBox(height: MnemosSpacing.xl),
            SettingGroup(
              title: 'Estudo',
              children: [
                _NumberRow(
                  icon: Icons.playlist_add_outlined,
                  label: 'Cards novos por dia',
                  detail: 'Quantos cards inéditos entram na fila.',
                  value: int.tryParse(values['new_per_day'] ?? '') ?? 10,
                  min: 0,
                  max: 100,
                  step: 5,
                  onChanged: (v) => _write(ref, 'new_per_day', '$v'),
                ),
                _NumberRow(
                  icon: Icons.repeat_outlined,
                  label: 'Revisões por dia',
                  detail: 'Teto para não acordar com quatrocentas.',
                  value: int.tryParse(values['review_per_day'] ?? '') ?? 200,
                  min: 20,
                  max: 500,
                  step: 20,
                  onChanged: (v) => _write(ref, 'review_per_day', '$v'),
                ),
                _SliderRow(
                  icon: Icons.tune_outlined,
                  label: 'Meta de retenção',
                  // §3.1 — this is an input to the interval formula, which is
                  // why it syncs. Raising it means shorter intervals and more
                  // work per day, and the screen says so instead of leaving it
                  // as a mystery dial.
                  detail: 'Mais alto significa intervalos mais curtos e mais '
                      'revisões por dia.',
                  value: double.tryParse(values['desired_retention'] ?? '') ??
                      kDesiredRetention,
                  onChanged: (v) =>
                      _write(ref, 'desired_retention', v.toStringAsFixed(2)),
                ),
              ],
            ),
            const SizedBox(height: MnemosSpacing.xl),
            SettingGroup(
              title: 'O seu dia',
              children: [
                _CutoffRow(
                  icon: Icons.bedtime_outlined,
                  value: int.tryParse(values['day_cutoff_hour'] ?? '') ??
                      kDefaultDayCutoffHour,
                  onChanged: (v) => _write(ref, 'day_cutoff_hour', '$v'),
                ),
                SettingRow(
                  icon: Icons.public_outlined,
                  title: 'Fuso horário',
                  value: values['timezone'] ?? 'America/Sao_Paulo',
                ),
              ],
            ),
            const SizedBox(height: MnemosSpacing.xl),
            SettingGroup(
              title: 'Lembrete',
              children: [
                SettingRow(
                  icon: Icons.notifications_none_outlined,
                  title: 'Lembrar de revisar',
                  detail: 'Só chega quando há cards vencendo.',
                  trailing: Switch(
                    value: (local['reminder_enabled'] ?? '0') == '1',
                    onChanged: (on) async {
                      if (on &&
                          !await ref.read(remindersProvider).requestPermission()) {
                        return;
                      }
                      // §5.4 — local_settings, never synced: a reminder is a
                      // property of a phone, not of a person.
                      await writeLocalSetting(
                          ref, 'reminder_enabled', on ? '1' : '0');
                      await refreshReminder(ref);
                    },
                  ),
                ),
                if ((local['reminder_enabled'] ?? '0') == '1')
                  SettingRow(
                    icon: Icons.schedule_outlined,
                    title: 'Horário',
                    trailing: DropdownButton<int>(
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
                  ),
              ],
            ),
            const SizedBox(height: MnemosSpacing.xl),
            SettingGroup(
              title: 'Conta e dispositivos',
              children: [
                SettingRow(
                  icon: Icons.devices_other_outlined,
                  title: 'Dispositivo',
                  detail: 'Identidade e configuração de conexão.',
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const DeviceScreen()),
                  ),
                ),
                SettingRow(
                  icon: Icons.auto_awesome_outlined,
                  title: 'Gerações por IA',
                  detail: switch (quota.valueOrNull) {
                    null => 'Verificando…',
                    (remaining: -1, limit: _, plan: _) => 'Sem conexão',
                    (remaining: 0, limit: _, plan: _) =>
                      'Sua geração grátis já foi usada',
                    (remaining: final r, limit: final l, plan: _) =>
                      r == 1 ? '1 de $l disponível' : '$r de $l disponíveis',
                  },
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const SubscriptionScreen()),
                  ),
                ),
                SettingRow(
                  icon: Icons.folder_outlined,
                  title: 'Seus dados',
                  detail: 'Exportar tudo, ou apagar a conta.',
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const AccountScreen()),
                  ),
                ),
              ],
            ),
            const SizedBox(height: MnemosSpacing.xl),
            SettingGroup(
              title: 'Sobre',
              children: [
                const SettingRow(
                  icon: Icons.cloud_off_outlined,
                  title: 'Funciona sem internet',
                  detail: 'Seus cards ficam neste aparelho e são copiados para '
                      'o servidor como backup.',
                ),
                if (hasLegalLinks) ...[
                  SettingRow(
                    icon: Icons.description_outlined,
                    title: 'Termos de uso',
                    onTap: () {},
                  ),
                  SettingRow(
                    icon: Icons.privacy_tip_outlined,
                    title: 'Política de privacidade',
                    onTap: () {},
                  ),
                ],
                // A versão é a primeira coisa que qualquer suporte pergunta, e
                // procurá-la não deveria exigir abrir os ajustes do sistema.
                const SettingRow(
                  icon: Icons.info_outline,
                  title: 'Versão',
                  value: 'Mnemos $kAppVersion',
                ),
              ],
            ),
            const SizedBox(height: MnemosSpacing.xl),
            // §8.2 — sair não apaga nada: os tokens somem, os cards ficam. É o
            // oposto de "apagar a conta", e a tela precisa dizer isso antes de
            // alguém confundir os dois.
            OutlinedButton(
              onPressed: () => _signOut(context, ref),
              child: const Text('Sair da conta'),
            ),
            const SizedBox(height: MnemosSpacing.sm),
            const Text(
              'Seus cards continuam neste aparelho. Entrar de novo traz o '
              'histórico do servidor de volta.',
              style: MnemosText.caption,
            ),
          ],
        ),
        ),
      ),
    );
  }

  static Future<void> _signOut(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Sair da conta?'),
        content: const Text(
          'Os cards e o histórico continuam neste aparelho. Você só perde o '
          'acesso ao backup até entrar de novo.',
          style: MnemosText.bodySmall,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Ficar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Sair'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    await ref.read(tokenStoreProvider).clear();
    if (context.mounted) Navigator.of(context).pop();
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

class _NumberRow extends StatelessWidget {
  const _NumberRow({
    required this.icon,
    required this.label,
    required this.detail,
    required this.value,
    required this.min,
    required this.max,
    required this.step,
    required this.onChanged,
  });

  final IconData icon;
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
      padding: const EdgeInsets.symmetric(
        horizontal: MnemosSpacing.lg,
        vertical: MnemosSpacing.md,
      ),
      child: Row(
        children: [
          Icon(icon, size: 20, color: MnemosColors.primary),
          const SizedBox(width: MnemosSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: MnemosText.body),
                const SizedBox(height: 2),
                Text(detail,
                    style: MnemosText.caption),
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
                style: MnemosText.itemTitle.copyWith(fontSize: 16)),
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
    required this.icon,
    required this.label,
    required this.detail,
    required this.value,
    required this.onChanged,
  });

  final IconData icon;
  final String label;
  final String detail;
  final double value;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: MnemosSpacing.lg,
        vertical: MnemosSpacing.md,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 20, color: MnemosColors.primary),
              const SizedBox(width: MnemosSpacing.md),
              Expanded(child: Text(label, style: MnemosText.body)),
              Text('${(value * 100).round()}%',
                  style: const TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w500, color: MnemosColors.primary)),
            ],
          ),
          const SizedBox(height: 2),
          const SizedBox(height: 2),
          Padding(
            padding: const EdgeInsets.only(left: 32),
            child: Text(detail, style: MnemosText.caption),
          ),
          Padding(
            padding: const EdgeInsets.only(left: 32 - 10),
            child: Slider(
            value: value,
            // Below 0.80 the schedule stops being a schedule and above 0.95
            // the workload explodes; neither end is a choice worth offering.
            min: 0.80,
            max: 0.95,
            divisions: 15,
            label: '${(value * 100).round()}%',
            onChanged: onChanged,
          ),
          ),
        ],
      ),
    );
  }
}

class _CutoffRow extends StatelessWidget {
  const _CutoffRow({
    required this.icon,required this.value, required this.onChanged});

  final IconData icon;
  final int value;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: MnemosSpacing.lg,
        vertical: MnemosSpacing.md,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 20, color: MnemosColors.primary),
              const SizedBox(width: MnemosSpacing.md),
              const Expanded(
                child: Text('O dia vira às', style: MnemosText.body),
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
          const Padding(
            padding: EdgeInsets.only(left: 32),
            child: Text(
              'Estudar de madrugada conta para o dia anterior. Mudar isto não '
              'reescreve o passado — vale a partir de hoje.',
              style: MnemosText.caption,
            ),
          ),
        ],
      ),
    );
  }
}
