import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';

import 'industrial_tables.dart';

part 'industrial_database.g.dart';

@DriftDatabase(
  tables: [
    Products,
    Batches,
    ProductionOrders,
    AuditEvents,
    SerialNumbers,
    PrintJobs,
  ],
)
class IndustrialDatabase extends _$IndustrialDatabase {
  IndustrialDatabase(super.executor);

  /// Opens (or creates) `industrial.sqlite` inside [directory]. Pass the
  /// folder from dataDirectoryProvider so the data-directory setting is
  /// respected. Nothing is moved or deleted.
  factory IndustrialDatabase.inDirectory(Directory directory) {
    final file = File(
      '${directory.path}${Platform.pathSeparator}industrial.sqlite',
    );
    return IndustrialDatabase(
      NativeDatabase(
        file,
        setup: (raw) {
          raw.execute('PRAGMA journal_mode = WAL;');
        },
      ),
    );
  }

  @override
  int get schemaVersion => 2;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) async {
      await m.createAll();
      await customStatement('''
        CREATE TRIGGER audit_events_no_update
        BEFORE UPDATE ON audit_events
        BEGIN SELECT RAISE(ABORT, 'audit_events is append-only'); END;
      ''');
      await customStatement('''
        CREATE TRIGGER audit_events_no_delete
        BEFORE DELETE ON audit_events
        BEGIN SELECT RAISE(ABORT, 'audit_events is append-only'); END;
      ''');
    },
    onUpgrade: (m, from, to) async {
      if (from < 2) {
        // Do not rebuild v1 tables: existing serials, foreign keys, and audit
        // history remain untouched. Triggers enforce future writes.
        await customStatement('''
          CREATE TRIGGER serial_numbers_length_before_insert
          BEFORE INSERT ON serial_numbers
          WHEN length(NEW.serial) NOT BETWEEN 1 AND 20
          BEGIN
            SELECT RAISE(ABORT, 'serial_numbers.serial must be 1..20 characters');
          END;
        ''');
        await customStatement('''
          CREATE TRIGGER serial_numbers_length_before_update
          BEFORE UPDATE OF serial ON serial_numbers
          WHEN length(NEW.serial) NOT BETWEEN 1 AND 20
          BEGIN
            SELECT RAISE(ABORT, 'serial_numbers.serial must be 1..20 characters');
          END;
        ''');
      }
    },
    beforeOpen: (details) async {
      await customStatement('PRAGMA foreign_keys = ON');
    },
  );
}
