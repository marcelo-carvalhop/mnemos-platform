import 'dart:async';

import 'package:drift/drift.dart';
import 'package:drift/isolate.dart';
import 'package:drift/native.dart';
import 'package:store/store.dart';
import 'package:test/test.dart';

/// Opening across an isolate boundary, which is what the app actually does.
///
/// `drift_flutter` runs the database on a background isolate. Every other test
/// in this package uses `NativeDatabase.memory()` in the same isolate, and a
/// same-isolate executor is re-entrant in ways a port is not — so this is the
/// only place a migration that deadlocks across the boundary can be caught.
void main() {
  test('the schema is created when the database lives on another isolate',
      () async {
    final isolate = await DriftIsolate.spawn(_open);
    addTearDown(isolate.shutdownAll);

    final db = AppDatabase(await isolate.connect());
    addTearDown(db.close);

    // Any query forces the migration to run to completion.
    final tables = await db
        .customSelect("SELECT name FROM sqlite_master WHERE type = 'table'")
        .get()
        .timeout(
          const Duration(seconds: 20),
          onTimeout: () => throw TimeoutException(
            'opening deadlocked: the migration is waiting on the isolate that '
            'is running it',
          ),
        );

    final names = tables.map((r) => r.read<String>('name')).toSet();
    expect(names, contains('cards'));
    expect(names, contains('reviews'));
    // The FTS index and the append-only triggers are created by raw
    // statements, which is exactly what a migration can get wrong here.
    expect(names, contains('cards_fts'));
  }, timeout: const Timeout(Duration(seconds: 60)));
}

DatabaseConnection _open() =>
    DatabaseConnection(NativeDatabase.memory(), closeStreamsSynchronously: true);
