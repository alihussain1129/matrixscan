import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;
import 'package:sqlite3/sqlite3.dart' show SqliteException;
import 'package:exalted/industrial/db/industrial_database.dart';

/// Exact SQLite error codes: 275 CHECK, 2067 UNIQUE, 787 FOREIGN KEY,
/// 1811 audit trigger.
Matcher code(int c) => throwsA(
  isA<SqliteException>().having((e) => e.extendedResultCode, 'code', c),
);

void main() {
  late IndustrialDatabase db;
  Future<void> sql(String s) => db.customStatement(s);

  setUp(() async {
    db = IndustrialDatabase(NativeDatabase.memory());
    await sql(
      "INSERT INTO products (sku,name,created_at) VALUES ('P1','P1',0)",
    );
    await sql(
      "INSERT INTO production_orders (order_number,product_id,planned_quantity,created_at,updated_at) VALUES ('O1',1,5,0,0)",
    );
    await sql(
      "INSERT INTO print_jobs (order_id,quantity,created_at,updated_at) VALUES (1,2,0,0)",
    );
    await sql(
      "INSERT INTO serial_numbers (order_id,product_id,serial,created_at,updated_at) VALUES (1,1,'S1',0,0)",
    );
    await sql(
      "INSERT INTO audit_events (actor,action,entity_type,entity_id,occurred_at) VALUES ('a','b','c','1',0)",
    );
  });
  tearDown(() => db.close());

  test(
    'product: GTIN letters, GTIN length, status are CHECK failures',
    () async {
      await expectLater(
        sql(
          "INSERT INTO products (sku,name,gtin,created_at) VALUES ('X','x','40063813X3931',0)",
        ),
        code(275),
      );
      await expectLater(
        sql(
          "INSERT INTO products (sku,name,gtin,created_at) VALUES ('X','x','12345',0)",
        ),
        code(275),
      );
      await expectLater(
        sql(
          "INSERT INTO products (sku,name,status,created_at) VALUES ('X','x','deleted',0)",
        ),
        code(275),
      );
    },
  );

  test('product: duplicate SKU is UNIQUE', () async {
    await expectLater(
      sql("INSERT INTO products (sku,name,created_at) VALUES ('P1','x',0)"),
      code(2067),
    );
  });

  test(
    'batch: expiry before manufacture is CHECK, missing product is FK',
    () async {
      await expectLater(
        sql(
          "INSERT INTO batches (product_id,lot_number,manufacturing_date,expiry_date,created_at) VALUES (1,'L1',100,50,0)",
        ),
        code(275),
      );
      await expectLater(
        sql(
          "INSERT INTO batches (product_id,lot_number,created_at) VALUES (999,'L1',0)",
        ),
        code(787),
      );
    },
  );

  test('order: quantity and status are CHECK, missing product is FK', () async {
    await expectLater(
      sql(
        "INSERT INTO production_orders (order_number,product_id,planned_quantity,created_at,updated_at) VALUES ('O2',1,0,0,0)",
      ),
      code(275),
    );
    await expectLater(
      sql(
        "INSERT INTO production_orders (order_number,product_id,planned_quantity,status,created_at,updated_at) VALUES ('O3',1,5,'finished',0,0)",
      ),
      code(275),
    );
    await expectLater(
      sql(
        "INSERT INTO production_orders (order_number,product_id,planned_quantity,created_at,updated_at) VALUES ('O4',999,5,0,0)",
      ),
      code(787),
    );
  });

  test('a product or order that is in use cannot be deleted (FK)', () async {
    await expectLater(sql('DELETE FROM products WHERE id = 1'), code(787));
    await expectLater(
      sql('DELETE FROM production_orders WHERE id = 1'),
      code(787),
    );
  });

  test('audit events cannot be updated or deleted (trigger)', () async {
    await expectLater(sql("UPDATE audit_events SET action = 'x'"), code(1811));
    await expectLater(sql('DELETE FROM audit_events'), code(1811));
  });

  test('serial: same product and serial twice is UNIQUE', () async {
    await expectLater(
      sql(
        "INSERT INTO serial_numbers (order_id,product_id,serial,created_at,updated_at) VALUES (1,1,'S1',0,0)",
      ),
      code(2067),
    );
  });

  test(
    'serial: bad status and 21 characters are CHECK, missing order is FK',
    () async {
      await expectLater(
        sql(
          "INSERT INTO serial_numbers (order_id,product_id,serial,status,created_at,updated_at) VALUES (1,1,'S2','lost',0,0)",
        ),
        code(275),
      );
      await expectLater(
        sql(
          "INSERT INTO serial_numbers (order_id,product_id,serial,created_at,updated_at) VALUES (1,1,'ABCDEFGHIJKLMNOPQRSTU',0,0)",
        ),
        code(275),
      );
      await expectLater(
        sql(
          "INSERT INTO serial_numbers (order_id,product_id,serial,created_at,updated_at) VALUES (999,1,'S3',0,0)",
        ),
        code(787),
      );
    },
  );

  test(
    'print job: quantity and status are CHECK, missing order is FK',
    () async {
      await expectLater(
        sql(
          "INSERT INTO print_jobs (order_id,quantity,created_at,updated_at) VALUES (1,0,0,0)",
        ),
        code(275),
      );
      await expectLater(
        sql(
          "INSERT INTO print_jobs (order_id,quantity,status,created_at,updated_at) VALUES (1,1,'stuck',0,0)",
        ),
        code(275),
      );
      await expectLater(
        sql(
          "INSERT INTO print_jobs (order_id,quantity,created_at,updated_at) VALUES (999,1,0,0)",
        ),
        code(787),
      );
    },
  );

  test('v1 migration preserves serial rows and enforces future length writes', () async {
    await db.close();

    final directory = await Directory.systemTemp.createTemp(
      'exalted_industrial_v1_migration_',
    );
    addTearDown(() => directory.delete(recursive: true));
    final file = File(
      '${directory.path}${Platform.pathSeparator}legacy.sqlite',
    );

    final legacy = sqlite.sqlite3.open(file.path);
    legacy.execute('CREATE TABLE serial_numbers (serial TEXT NOT NULL)');
    legacy.execute(
      "INSERT INTO serial_numbers (serial) VALUES ('EXISTING-SERIAL-OVER-20-CHARS')",
    );
    legacy.execute('PRAGMA user_version = 1');
    legacy.dispose();

    db = IndustrialDatabase(NativeDatabase(file));

    final existing = await db
        .customSelect('SELECT serial FROM serial_numbers')
        .get();
    expect(existing, hasLength(1));
    expect(
      existing.single.read<String>('serial'),
      'EXISTING-SERIAL-OVER-20-CHARS',
    );

    await expectLater(
      sql(
        "INSERT INTO serial_numbers (serial) VALUES ('ABCDEFGHIJKLMNOPQRSTU')",
      ),
      code(1811),
    );
    await expectLater(
      sql("UPDATE serial_numbers SET serial = 'ABCDEFGHIJKLMNOPQRSTU'"),
      code(1811),
    );
    await sql("INSERT INTO serial_numbers (serial) VALUES ('VALID-20-CHARS')");
  });

  test('a print job in use cannot be deleted (FK)', () async {
    await sql('UPDATE serial_numbers SET print_job_id = 1');
    await expectLater(sql('DELETE FROM print_jobs WHERE id = 1'), code(787));
  });
}
