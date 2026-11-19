import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:exalted/industrial/db/industrial_database.dart';

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late IndustrialDatabase db;

  setUp(() => db = IndustrialDatabase(NativeDatabase.memory()));
  tearDown(() => db.close());

  Future<int> addProduct({String sku = 'SKU-1', String? gtin}) => db
      .into(db.products)
      .insert(
        ProductsCompanion.insert(
          sku: sku,
          name: 'Test product',
          gtin: Value(gtin),
        ),
      );

  Future<int> addOrder({
    required int productId,
    String number = 'PO-1',
    int qty = 100,
    String? status,
  }) => db
      .into(db.productionOrders)
      .insert(
        ProductionOrdersCompanion.insert(
          orderNumber: number,
          productId: productId,
          plannedQuantity: qty,
          status: status == null ? const Value.absent() : Value(status),
        ),
      );

  group('products', () {
    test('a valid product is stored', () async {
      final id = await addProduct(gtin: '04006381333931');
      final row = await (db.select(
        db.products,
      )..where((t) => t.id.equals(id))).getSingle();
      expect(row.status, 'active');
      expect(row.unitOfMeasure, 'EA');
    });

    test('duplicate SKU is rejected', () async {
      await addProduct(sku: 'A');
      await expectLater(addProduct(sku: 'A'), throwsA(anything));
    });

    test('duplicate GTIN is rejected', () async {
      await addProduct(sku: 'A', gtin: '4006381333931');
      await expectLater(
        addProduct(sku: 'B', gtin: '4006381333931'),
        throwsA(anything),
      );
    });

    test('a GTIN with letters or the wrong length is rejected', () async {
      await expectLater(
        addProduct(sku: 'A', gtin: '40063813X3931'),
        throwsA(anything),
      );
      await expectLater(addProduct(sku: 'B', gtin: '12345'), throwsA(anything));
    });

    test('an invalid status is rejected', () async {
      await expectLater(
        db.customStatement(
          "INSERT INTO products (sku, name, status, created_at) "
          "VALUES ('X', 'X', 'deleted', 0)",
        ),
        throwsA(anything),
      );
    });
  });

  group('batches', () {
    test('lot numbers are unique per product', () async {
      final p = await addProduct();
      Future<int> lot(String n) => db
          .into(db.batches)
          .insert(BatchesCompanion.insert(productId: p, lotNumber: n));
      await lot('L1');
      await expectLater(lot('L1'), throwsA(anything));
      await lot('L2');
    });

    test('a batch needs an existing product', () async {
      await expectLater(
        db
            .into(db.batches)
            .insert(BatchesCompanion.insert(productId: 999, lotNumber: 'L1')),
        throwsA(anything),
      );
    });

    test('expiry before manufacture is rejected', () async {
      final p = await addProduct();
      await expectLater(
        db
            .into(db.batches)
            .insert(
              BatchesCompanion.insert(
                productId: p,
                lotNumber: 'L1',
                manufacturingDate: Value(DateTime(2026, 6, 1)),
                expiryDate: Value(DateTime(2026, 1, 1)),
              ),
            ),
        throwsA(anything),
      );
    });
  });

  group('production orders', () {
    test('a new order starts as draft', () async {
      final p = await addProduct();
      final id = await addOrder(productId: p);
      final row = await (db.select(
        db.productionOrders,
      )..where((t) => t.id.equals(id))).getSingle();
      expect(row.status, 'draft');
    });

    test('an order needs an existing product', () async {
      await expectLater(addOrder(productId: 999), throwsA(anything));
    });

    test('zero or negative quantity is rejected', () async {
      final p = await addProduct();
      await expectLater(addOrder(productId: p, qty: 0), throwsA(anything));
      await expectLater(
        addOrder(productId: p, number: 'PO-2', qty: -5),
        throwsA(anything),
      );
    });

    test('duplicate order numbers are rejected', () async {
      final p = await addProduct();
      await addOrder(productId: p, number: 'PO-1');
      await expectLater(
        addOrder(productId: p, number: 'PO-1'),
        throwsA(anything),
      );
    });

    test('an unknown status value is rejected', () async {
      final p = await addProduct();
      await expectLater(
        addOrder(productId: p, status: 'finished'),
        throwsA(anything),
      );
    });

    test('a product that has orders cannot be deleted', () async {
      final p = await addProduct();
      await addOrder(productId: p);
      await expectLater(
        (db.delete(db.products)..where((t) => t.id.equals(p))).go(),
        throwsA(anything),
      );
    });
  });

  group('audit events', () {
    Future<int> addAudit() => db
        .into(db.auditEvents)
        .insert(
          AuditEventsCompanion.insert(
            actor: 'tester',
            action: 'order.created',
            entityType: 'production_order',
            entityId: '1',
          ),
        );

    test('events can be appended', () async {
      await addAudit();
      await addAudit();
      final rows = await db.select(db.auditEvents).get();
      expect(rows.length, 2);
    });

    test('events cannot be changed', () async {
      final id = await addAudit();
      await expectLater(
        (db.update(db.auditEvents)..where((t) => t.id.equals(id))).write(
          const AuditEventsCompanion(action: Value('tampered')),
        ),
        throwsA(anything),
      );
    });

    test('events cannot be deleted', () async {
      final id = await addAudit();
      await expectLater(
        (db.delete(db.auditEvents)..where((t) => t.id.equals(id))).go(),
        throwsA(anything),
      );
      expect((await db.select(db.auditEvents).get()).length, 1);
    });
  });

  test('data survives closing and reopening a file database', () async {
    final dir = Directory.systemTemp.createTempSync('exalted_industrial_');
    addTearDown(() => dir.deleteSync(recursive: true));

    final first = IndustrialDatabase.inDirectory(dir);
    await first
        .into(first.products)
        .insert(ProductsCompanion.insert(sku: 'KEEP', name: 'Kept'));
    await first.close();

    final second = IndustrialDatabase.inDirectory(dir);
    addTearDown(second.close);
    final rows = await second.select(second.products).get();
    expect(rows.map((r) => r.sku), ['KEEP']);
  });
}
