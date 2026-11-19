import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';

void main() {
  test('native SQLite loads and enforces keys and uniqueness', () {
    final db = sqlite3.openInMemory();
    addTearDown(db.close);

    db.execute('PRAGMA foreign_keys = ON');
    final version = db.select('SELECT sqlite_version() AS v').first['v'];
    expect(version, isA<String>());

    db.execute('CREATE TABLE p (id INTEGER PRIMARY KEY)');
    db.execute('''
      CREATE TABLE s (
        id INTEGER PRIMARY KEY,
        p_id INTEGER NOT NULL REFERENCES p(id),
        serial TEXT NOT NULL,
        UNIQUE (p_id, serial)
      )
    ''');
    db.execute('INSERT INTO p (id) VALUES (1)');
    db.execute("INSERT INTO s (p_id, serial) VALUES (1, 'A')");

    expect(
      () => db.execute("INSERT INTO s (p_id, serial) VALUES (1, 'A')"),
      throwsA(isA<SqliteException>()),
    );
    expect(
      () => db.execute("INSERT INTO s (p_id, serial) VALUES (2, 'B')"),
      throwsA(isA<SqliteException>()),
    );
  });
}
