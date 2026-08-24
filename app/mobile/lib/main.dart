import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:timezone/data/latest.dart' as tzdata;

import 'features/home_screen.dart';
import 'features/onboarding/onboarding_screen.dart';
import 'providers.dart';
import 'providers_sync.dart';
import 'theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // §5.7 — day bucketing needs IANA zones, and Dart core knows only UTC and
  // "local".
  tzdata.initializeTimeZones();
  runApp(const ProviderScope(child: MnemosApp()));
}

class MnemosApp extends ConsumerWidget {
  const MnemosApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp(
      title: 'Mnemos',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      home: const _Bootstrap(),
    );
  }
}

/// Waits for the device id, then seeds a first-run database so the app is
/// never a blank screen (§5.1's empty state is a screen, not an accident).
///
/// Registration and the first sync are deliberately **not** awaited: §2.2
/// makes local SQLite the source of truth, so a device with no network must
/// reach the study screen exactly as fast as one with a connection.
class _Bootstrap extends ConsumerStatefulWidget {
  const _Bootstrap();

  @override
  ConsumerState<_Bootstrap> createState() => _BootstrapState();
}

class _BootstrapState extends ConsumerState<_Bootstrap> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Coming back to the app is the moment another device's changes are most
    // likely to be waiting (§6). `syncNow` coalesces, so a resume during an
    // in-flight sync joins it rather than starting a second.
    if (state == AppLifecycleState.resumed) {
      ref.read(syncControllerProvider.notifier).syncNow();
      // A geração roda no servidor com ou sem este telefone olhando (§7.8), e
      // voltar para o app é justamente quando ela costuma ter terminado.
      ref.invalidate(openGenerationsProvider);
    }
  }

  Future<void> _start(String deviceId) async {
    // Registration and the first sync are not awaited: see the class comment.
    unawaited(_registerAndSync());
  }

  Future<void> _registerAndSync() async {
    await ref.read(remindersProvider).initialise();
    await refreshReminder(ref);
    await ensureRegistered(ref);
    if (!mounted) return;
    await ref.read(syncControllerProvider.notifier).syncNow();
  }

  @override
  Widget build(BuildContext context) {
    final deviceId = ref.watch(deviceIdProvider);

    return deviceId.when(
      loading: () => const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (e, _) => Scaffold(body: Center(child: Text('Erro ao iniciar: $e'))),
      data: (id) => FutureBuilder(
        future: _start(id),
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Scaffold(body: Center(child: CircularProgressIndicator()));
          }
          if (snapshot.hasError) {
            // Previously swallowed: a failed start showed the home screen as
            // if nothing had happened.
            return Scaffold(body: Center(child: Text('Erro ao iniciar: ${snapshot.error}')));
          }
          return ref.watch(onboardingDoneProvider).when(
                loading: () =>
                    const Scaffold(body: Center(child: CircularProgressIndicator())),
                error: (e, _) => Scaffold(body: Center(child: Text('$e'))),
                data: (done) => done
                    ? const HomeScreen()
                    : OnboardingScreen(
                        onDone: () => ref.invalidate(onboardingDoneProvider),
                      ),
              );
        },
      ),
    );
  }
}

/// Local `unawaited`, to say plainly that the future is not being dropped by
/// accident.
void unawaited(Future<void> future) {
  future.catchError((Object _) {
    // Registration and sync report through SyncState; nothing here should be
    // able to take down the app.
  });
}
