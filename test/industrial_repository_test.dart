import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:exalted/industrial/db/industrial_database.dart';
import 'package:exalted/industrial/db/industrial_repository.dart';
import 'package:exalted/industrial/domain/order_status.dart';
import 'package:exalted/industrial/domain/print_job_status.dart';
import 'package:exalted/industrial/domain/serial_status.dart';

void main() {
  late IndustrialDatabase db;
  late IndustrialRepository repo;
  const actor = 'tester';

  setUp(() {
    db = IndustrialDatabase(NativeDatabase.memory());
    repo = IndustrialRepository(db, clock: () => DateTime(2026, 11, 17, 9));
  });
  tearDown(() => db.close());

  Matcher failsWith(String text) => throwsA(
    isA<IndustrialException>().having(
      (e) => e.message,
      'message',
      contains(text),
    ),
  );

  Future<List<String>> auditActions() async =>
      (await db.select(db.auditEvents).get()).map((e) => e.action).toList();

  Future<String> orderStatus(int id) async =>
      (await db.select(db.productionOrders).get())
          .firstWhere((r) => r.id == id)
          .status;

  Future<({int product, int batch, int order})> readyOrder({
    int qty = 5,
    String number = 'PO-1',
  }) async {
    final p = await repo.createProduct(
      actor: actor,
      sku: 'SKU-$number',
      name: 'Test',
      gtin: null,
    );
    final b = await repo.createBatch(
      actor: actor,
      productId: p,
      lotNumber: 'LOT1',
    );
    final o = await repo.createOrder(
      actor: actor,
      orderNumber: number,
      productId: p,
      batchId: b,
      plannedQuantity: qty,
    );
    await repo.transitionOrder(
      actor: actor,
      orderId: o,
      to: OrderStatus.approved,
    );
    await repo.transitionOrder(actor: actor, orderId: o, to: OrderStatus.ready);
    return (product: p, batch: b, order: o);
  }

  group('products and batches', () {
    test('a bad check digit is refused and nothing is stored', () async {
      await expectLater(
        repo.createProduct(
          actor: actor,
          sku: 'A',
          name: 'A',
          gtin: '4006381333932',
        ),
        failsWith('Check Digit'),
      );
      expect(await db.select(db.products).get(), isEmpty);
    });

    test('a valid product writes one audit event', () async {
      await repo.createProduct(
        actor: actor,
        sku: 'A',
        name: 'A',
        gtin: '4006381333931',
      );
      expect(await auditActions(), ['product.created']);
    });

    test('a duplicate SKU gives a clear message', () async {
      await repo.createProduct(actor: actor, sku: 'A', name: 'A');
      await expectLater(
        repo.createProduct(actor: actor, sku: 'A', name: 'B'),
        failsWith('already exists'),
      );
    });

    test('a bad lot is refused', () async {
      final p = await repo.createProduct(actor: actor, sku: 'A', name: 'A');
      await expectLater(
        repo.createBatch(actor: actor, productId: p, lotNumber: 'BAD LOT'),
        failsWith('Lot'),
      );
    });
  });

  group('orders', () {
    test('an order cannot start without a batch', () async {
      final p = await repo.createProduct(actor: actor, sku: 'A', name: 'A');
      final o = await repo.createOrder(
        actor: actor,
        orderNumber: 'PO-1',
        productId: p,
        plannedQuantity: 5,
      );
      await repo.transitionOrder(
        actor: actor,
        orderId: o,
        to: OrderStatus.approved,
      );
      await repo.transitionOrder(
        actor: actor,
        orderId: o,
        to: OrderStatus.ready,
      );
      await expectLater(
        repo.transitionOrder(
          actor: actor,
          orderId: o,
          to: OrderStatus.inProgress,
        ),
        failsWith('batch'),
      );
      expect(await orderStatus(o), 'ready');
    });

    test('a batch of another product is refused', () async {
      final p1 = await repo.createProduct(actor: actor, sku: 'A', name: 'A');
      final p2 = await repo.createProduct(actor: actor, sku: 'B', name: 'B');
      final b2 = await repo.createBatch(
        actor: actor,
        productId: p2,
        lotNumber: 'L1',
      );
      await expectLater(
        repo.createOrder(
          actor: actor,
          orderNumber: 'PO-1',
          productId: p1,
          batchId: b2,
          plannedQuantity: 5,
        ),
        failsWith('does not belong'),
      );
    });

    test('a skipped step is refused and writes nothing', () async {
      final p = await repo.createProduct(actor: actor, sku: 'A', name: 'A');
      final o = await repo.createOrder(
        actor: actor,
        orderNumber: 'PO-1',
        productId: p,
        plannedQuantity: 5,
      );
      final before = (await auditActions()).length;
      await expectLater(
        repo.transitionOrder(
          actor: actor,
          orderId: o,
          to: OrderStatus.inProgress,
        ),
        failsWith('cannot go'),
      );
      expect(await orderStatus(o), 'draft');
      expect((await auditActions()).length, before);
    });

    test(
      'the full path ends completed with one audit event per step',
      () async {
        final r = await readyOrder();
        await repo.transitionOrder(
          actor: actor,
          orderId: r.order,
          to: OrderStatus.inProgress,
        );
        await repo.transitionOrder(
          actor: actor,
          orderId: r.order,
          to: OrderStatus.completed,
        );
        expect(await orderStatus(r.order), 'completed');
        expect(await auditActions(), [
          'product.created',
          'batch.created',
          'order.created',
          ...List.filled(4, 'order.status_changed'),
        ]);
      },
    );

    test('a completed order is final', () async {
      final r = await readyOrder();
      await repo.transitionOrder(
        actor: actor,
        orderId: r.order,
        to: OrderStatus.inProgress,
      );
      await repo.transitionOrder(
        actor: actor,
        orderId: r.order,
        to: OrderStatus.completed,
      );
      await expectLater(
        repo.transitionOrder(
          actor: actor,
          orderId: r.order,
          to: OrderStatus.cancelled,
        ),
        failsWith('cannot go'),
      );
    });
  });

  group('serials', () {
    test('not allowed while the order is draft', () async {
      final p = await repo.createProduct(actor: actor, sku: 'A', name: 'A');
      final o = await repo.createOrder(
        actor: actor,
        orderNumber: 'PO-1',
        productId: p,
        plannedQuantity: 5,
      );
      await expectLater(
        repo.allocateSerials(actor: actor, orderId: o, serials: ['A1']),
        failsWith('ready or in progress'),
      );
    });

    test('allocated for a ready order', () async {
      final r = await readyOrder();
      final ids = await repo.allocateSerials(
        actor: actor,
        orderId: r.order,
        serials: ['A1', 'A2'],
      );
      expect(ids.length, 2);
      final rows = await db.select(db.serialNumbers).get();
      expect(rows.map((s) => s.status).toSet(), {'allocated'});
    });

    test('duplicates in one request are refused', () async {
      final r = await readyOrder();
      await expectLater(
        repo.allocateSerials(
          actor: actor,
          orderId: r.order,
          serials: ['A1', 'A1'],
        ),
        failsWith('twice'),
      );
    });

    test('bad serials are refused', () async {
      final r = await readyOrder();
      await expectLater(
        repo.allocateSerials(actor: actor, orderId: r.order, serials: ['A B']),
        failsWith('unsupported'),
      );
      await expectLater(
        repo.allocateSerials(
          actor: actor,
          orderId: r.order,
          serials: ['ABCDEFGHIJKLMNOPQRSTU'],
        ),
        failsWith('1-20'),
      );
    });

    test(
      'more than the planned quantity is refused and nothing is stored',
      () async {
        final r = await readyOrder(qty: 2);
        await expectLater(
          repo.allocateSerials(
            actor: actor,
            orderId: r.order,
            serials: ['A1', 'A2', 'A3'],
          ),
          failsWith('allows'),
        );
        expect(await db.select(db.serialNumbers).get(), isEmpty);
      },
    );

    test('the same serial for the same product in another order is refused, all or nothing', () async {
      final r = await readyOrder();
      await repo.allocateSerials(
        actor: actor,
        orderId: r.order,
        serials: ['A1'],
      );
      final o2 = await repo.createOrder(
        actor: actor,
        orderNumber: 'PO-2',
        productId: r.product,
        batchId: r.batch,
        plannedQuantity: 5,
      );
      await repo.transitionOrder(
        actor: actor,
        orderId: o2,
        to: OrderStatus.approved,
      );
      await repo.transitionOrder(
        actor: actor,
        orderId: o2,
        to: OrderStatus.ready,
      );
      await expectLater(
        repo.allocateSerials(actor: actor, orderId: o2, serials: ['B1', 'A1']),
        failsWith('already exists'),
      );
      final rows = await db.select(db.serialNumbers).get();
      expect(rows.where((s) => s.orderId == o2), isEmpty);
    });

    test('a verified serial is final', () async {
      final r = await readyOrder();
      final ids = await repo.allocateSerials(
        actor: actor,
        orderId: r.order,
        serials: ['A1'],
      );
      await repo.transitionSerial(
        actor: actor,
        serialId: ids.first,
        to: SerialStatus.printed,
      );
      await repo.transitionSerial(
        actor: actor,
        serialId: ids.first,
        to: SerialStatus.verified,
      );
      await expectLater(
        repo.transitionSerial(
          actor: actor,
          serialId: ids.first,
          to: SerialStatus.voided,
        ),
        failsWith('cannot go'),
      );
    });
  });

  group('print jobs', () {
    test(
      'a job takes allocated serials and completing it marks them printed',
      () async {
        final r = await readyOrder(qty: 3);
        await repo.allocateSerials(
          actor: actor,
          orderId: r.order,
          serials: ['S1', 'S2', 'S3'],
        );
        final job = await repo.createPrintJob(
          actor: actor,
          orderId: r.order,
          quantity: 2,
          printerName: 'Line1',
        );
        var rows = await db.select(db.serialNumbers).get();
        expect(rows.where((s) => s.printJobId == job).length, 2);
        await repo.transitionPrintJob(
          actor: actor,
          jobId: job,
          to: PrintJobStatus.printing,
        );
        await repo.transitionPrintJob(
          actor: actor,
          jobId: job,
          to: PrintJobStatus.completed,
        );
        rows = await db.select(db.serialNumbers).get();
        expect(rows.where((s) => s.status == 'printed').length, 2);
        expect(rows.where((s) => s.status == 'allocated').length, 1);
      },
    );

    test('a job cannot ask for more serials than are free', () async {
      final r = await readyOrder(qty: 3);
      await repo.allocateSerials(
        actor: actor,
        orderId: r.order,
        serials: ['S1'],
      );
      await expectLater(
        repo.createPrintJob(actor: actor, orderId: r.order, quantity: 2),
        failsWith('free'),
      );
      expect(await db.select(db.printJobs).get(), isEmpty);
    });

    test('cancelling a queued job frees its serials', () async {
      final r = await readyOrder(qty: 2);
      await repo.allocateSerials(
        actor: actor,
        orderId: r.order,
        serials: ['S1', 'S2'],
      );
      final job = await repo.createPrintJob(
        actor: actor,
        orderId: r.order,
        quantity: 2,
      );
      await repo.transitionPrintJob(
        actor: actor,
        jobId: job,
        to: PrintJobStatus.cancelled,
      );
      final rows = await db.select(db.serialNumbers).get();
      expect(rows.every((s) => s.printJobId == null), isTrue);
    });

    test(
      'cancelling after printing started keeps the serials attached',
      () async {
        final r = await readyOrder(qty: 2);
        await repo.allocateSerials(
          actor: actor,
          orderId: r.order,
          serials: ['S1', 'S2'],
        );
        final job = await repo.createPrintJob(
          actor: actor,
          orderId: r.order,
          quantity: 2,
        );
        await repo.transitionPrintJob(
          actor: actor,
          jobId: job,
          to: PrintJobStatus.printing,
        );
        await repo.transitionPrintJob(
          actor: actor,
          jobId: job,
          to: PrintJobStatus.cancelled,
        );
        final rows = await db.select(db.serialNumbers).get();
        expect(rows.where((s) => s.printJobId == job).length, 2);
      },
    );

    test('a completed job is final', () async {
      final r = await readyOrder(qty: 1);
      await repo.allocateSerials(
        actor: actor,
        orderId: r.order,
        serials: ['S1'],
      );
      final job = await repo.createPrintJob(
        actor: actor,
        orderId: r.order,
        quantity: 1,
      );
      await repo.transitionPrintJob(
        actor: actor,
        jobId: job,
        to: PrintJobStatus.printing,
      );
      await repo.transitionPrintJob(
        actor: actor,
        jobId: job,
        to: PrintJobStatus.completed,
      );
      await expectLater(
        repo.transitionPrintJob(
          actor: actor,
          jobId: job,
          to: PrintJobStatus.queued,
        ),
        failsWith('cannot go'),
      );
    });
  });
}
