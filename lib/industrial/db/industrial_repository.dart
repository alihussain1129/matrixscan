import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:sqlite3/sqlite3.dart' show SqliteException;

import '../domain/industrial_rules.dart';
import '../domain/order_status.dart';
import '../domain/print_job_status.dart';
import '../domain/serial_status.dart';
import 'industrial_database.dart';

/// A business rule was broken. [message] is safe to show to the operator.
class IndustrialException implements Exception {
  IndustrialException(this.message);

  final String message;

  @override
  String toString() => 'IndustrialException: $message';
}

/// All changes run in one transaction and write an audit event, so a failed
/// change leaves nothing behind.
class IndustrialRepository {
  IndustrialRepository(this.db, {DateTime Function()? clock})
    : _now = clock ?? DateTime.now;

  final IndustrialDatabase db;
  final DateTime Function() _now;

  Future<void> _audit(
    String actor,
    String action,
    String entityType,
    int entityId, [
    Map<String, Object?> details = const {},
  ]) async {
    await db
        .into(db.auditEvents)
        .insert(
          AuditEventsCompanion.insert(
            actor: actor,
            action: action,
            entityType: entityType,
            entityId: entityId.toString(),
            occurredAt: Value(_now()),
            detailsJson: Value(jsonEncode(details)),
          ),
        );
  }

  Future<T> _uniqueAs<T>(String message, Future<T> Function() body) async {
    try {
      return await body();
    } on SqliteException catch (e) {
      if (e.extendedResultCode == 2067) throw IndustrialException(message);
      rethrow;
    }
  }

  Future<Product> _product(int id) async {
    final row = await (db.select(
      db.products,
    )..where((t) => t.id.equals(id))).getSingleOrNull();
    if (row == null) throw IndustrialException('Product $id does not exist');
    return row;
  }

  Future<ProductionOrder> _order(int id) async {
    final row = await (db.select(
      db.productionOrders,
    )..where((t) => t.id.equals(id))).getSingleOrNull();
    if (row == null) throw IndustrialException('Order $id does not exist');
    return row;
  }

  // ---------------- products and batches ----------------

  Future<int> createProduct({
    required String actor,
    required String sku,
    required String name,
    String? gtin,
  }) => db.transaction(() async {
    if (gtin != null) {
      final problem = gtinProblem(gtin);
      if (problem != null) throw IndustrialException(problem);
    }
    final id = await _uniqueAs(
      'SKU or GTIN already exists',
      () => db
          .into(db.products)
          .insert(
            ProductsCompanion.insert(sku: sku, name: name, gtin: Value(gtin)),
          ),
    );
    await _audit(actor, 'product.created', 'product', id, {'sku': sku});
    return id;
  });

  Future<int> createBatch({
    required String actor,
    required int productId,
    required String lotNumber,
    DateTime? manufacturingDate,
    DateTime? expiryDate,
  }) => db.transaction(() async {
    final problem = lotProblem(lotNumber);
    if (problem != null) throw IndustrialException(problem);
    await _product(productId);
    if (manufacturingDate != null &&
        expiryDate != null &&
        expiryDate.isBefore(manufacturingDate)) {
      throw IndustrialException('Expiry date is before the manufacturing date');
    }
    final id = await _uniqueAs(
      'Lot "$lotNumber" already exists for this product',
      () => db
          .into(db.batches)
          .insert(
            BatchesCompanion.insert(
              productId: productId,
              lotNumber: lotNumber,
              manufacturingDate: Value(manufacturingDate),
              expiryDate: Value(expiryDate),
            ),
          ),
    );
    await _audit(actor, 'batch.created', 'batch', id, {
      'lot': lotNumber,
      'productId': productId,
    });
    return id;
  });

  // ---------------- orders ----------------

  Future<int> createOrder({
    required String actor,
    required String orderNumber,
    required int productId,
    required int plannedQuantity,
    int? batchId,
  }) => db.transaction(() async {
    if (plannedQuantity <= 0) {
      throw IndustrialException('Planned quantity must be positive');
    }
    final product = await _product(productId);
    if (product.status != 'active') {
      throw IndustrialException('Product ${product.sku} is archived');
    }
    if (batchId != null) {
      final batch = await (db.select(
        db.batches,
      )..where((t) => t.id.equals(batchId))).getSingleOrNull();
      if (batch == null || batch.productId != productId) {
        throw IndustrialException(
          'Batch $batchId does not belong to product $productId',
        );
      }
    }
    final id = await _uniqueAs(
      'Order number "$orderNumber" already exists',
      () => db
          .into(db.productionOrders)
          .insert(
            ProductionOrdersCompanion.insert(
              orderNumber: orderNumber,
              productId: productId,
              plannedQuantity: plannedQuantity,
              batchId: Value(batchId),
            ),
          ),
    );
    await _audit(actor, 'order.created', 'production_order', id, {
      'orderNumber': orderNumber,
    });
    return id;
  });

  Future<void> transitionOrder({
    required String actor,
    required int orderId,
    required OrderStatus to,
  }) => db.transaction(() async {
    final row = await _order(orderId);
    final from = OrderStatus.fromDb(row.status);
    if (from == null) {
      throw IndustrialException(
        'Order ${row.orderNumber} has unknown status "${row.status}"',
      );
    }
    if (!from.canMoveTo(to)) {
      throw IndustrialException(
        'Order ${row.orderNumber} cannot go from ${from.dbValue} to ${to.dbValue}',
      );
    }
    if (to == OrderStatus.inProgress && row.batchId == null) {
      throw IndustrialException('An order needs a batch before it can start');
    }
    final changed =
        await (db.update(db.productionOrders)..where(
              (t) => t.id.equals(orderId) & t.status.equals(from.dbValue),
            ))
            .write(
              ProductionOrdersCompanion(
                status: Value(to.dbValue),
                updatedAt: Value(_now()),
              ),
            );
    if (changed != 1) {
      throw IndustrialException('Order changed while updating; try again');
    }
    await _audit(actor, 'order.status_changed', 'production_order', orderId, {
      'from': from.dbValue,
      'to': to.dbValue,
    });
  });

  // ---------------- serials ----------------

  Future<List<int>> allocateSerials({
    required String actor,
    required int orderId,
    required List<String> serials,
  }) => db.transaction(() async {
    final order = await _order(orderId);
    final status = OrderStatus.fromDb(order.status);
    if (status != OrderStatus.ready && status != OrderStatus.inProgress) {
      throw IndustrialException(
        'Serials can only be allocated while the order is ready or in progress',
      );
    }
    if (serials.isEmpty) throw IndustrialException('No serials given');
    final seen = <String>{};
    for (final s in serials) {
      final problem = serialProblem(s);
      if (problem != null) throw IndustrialException('Serial "$s": $problem');
      if (!seen.add(s)) {
        throw IndustrialException('Serial "$s" appears twice in the request');
      }
    }
    final countExp = db.serialNumbers.id.count();
    final query = db.selectOnly(db.serialNumbers)
      ..addColumns([countExp])
      ..where(
        db.serialNumbers.orderId.equals(orderId) &
            db.serialNumbers.status.equals(SerialStatus.voided.dbValue).not(),
      );
    final existing = await query
        .map((row) => row.read(countExp) ?? 0)
        .getSingle();
    if (existing + serials.length > order.plannedQuantity) {
      throw IndustrialException(
        'Order allows ${order.plannedQuantity} serials, $existing already '
        'allocated, ${serials.length} requested',
      );
    }
    final ids = <int>[];
    for (final s in serials) {
      final id = await _uniqueAs(
        'Serial "$s" already exists for this product',
        () => db
            .into(db.serialNumbers)
            .insert(
              SerialNumbersCompanion.insert(
                orderId: orderId,
                productId: order.productId,
                serial: s,
              ),
            ),
      );
      ids.add(id);
      await _audit(actor, 'serial.allocated', 'serial', id, {
        'orderId': orderId,
        'serial': s,
      });
    }
    return ids;
  });

  Future<void> transitionSerial({
    required String actor,
    required int serialId,
    required SerialStatus to,
  }) => db.transaction(() async {
    final row = await (db.select(
      db.serialNumbers,
    )..where((t) => t.id.equals(serialId))).getSingleOrNull();
    if (row == null) throw IndustrialException('Serial $serialId does not exist');
    final from = SerialStatus.fromDb(row.status);
    if (from == null) {
      throw IndustrialException('Serial has unknown status "${row.status}"');
    }
    if (!from.canMoveTo(to)) {
      throw IndustrialException(
        'Serial "${row.serial}" cannot go from ${from.dbValue} to ${to.dbValue}',
      );
    }
    final changed =
        await (db.update(db.serialNumbers)..where(
              (t) => t.id.equals(serialId) & t.status.equals(from.dbValue),
            ))
            .write(
              SerialNumbersCompanion(
                status: Value(to.dbValue),
                updatedAt: Value(_now()),
              ),
            );
    if (changed != 1) {
      throw IndustrialException('Serial changed while updating; try again');
    }
    await _audit(actor, 'serial.status_changed', 'serial', serialId, {
      'from': from.dbValue,
      'to': to.dbValue,
    });
  });

  // ---------------- print jobs ----------------

  /// Takes the oldest [quantity] allocated serials of the order that are not
  /// in a job yet and attaches them to a new queued job.
  Future<int> createPrintJob({
    required String actor,
    required int orderId,
    required int quantity,
    String? printerName,
  }) => db.transaction(() async {
    if (quantity <= 0) throw IndustrialException('Quantity must be positive');
    final order = await _order(orderId);
    final status = OrderStatus.fromDb(order.status);
    if (status != OrderStatus.ready && status != OrderStatus.inProgress) {
      throw IndustrialException(
        'Print jobs can only be created while the order is ready or in progress',
      );
    }
    final free =
        await (db.select(db.serialNumbers)
              ..where(
                (t) =>
                    t.orderId.equals(orderId) &
                    t.status.equals(SerialStatus.allocated.dbValue) &
                    t.printJobId.isNull(),
              )
              ..orderBy([(t) => OrderingTerm.asc(t.id)])
              ..limit(quantity))
            .get();
    if (free.length < quantity) {
      throw IndustrialException(
        'Only ${free.length} free serials are available, $quantity requested',
      );
    }
    final jobId = await db
        .into(db.printJobs)
        .insert(
          PrintJobsCompanion.insert(
            orderId: orderId,
            quantity: quantity,
            printerName: Value(printerName),
          ),
        );
    await (db.update(
      db.serialNumbers,
    )..where((t) => t.id.isIn(free.map((s) => s.id)))).write(
      SerialNumbersCompanion(
        printJobId: Value(jobId),
        updatedAt: Value(_now()),
      ),
    );
    await _audit(actor, 'print_job.created', 'print_job', jobId, {
      'orderId': orderId,
      'quantity': quantity,
    });
    return jobId;
  });

  /// Completed: attached serials become printed.
  /// Cancelled from queued: serials are freed. Cancelled after printing
  /// started: serials stay attached for a person to review.
  Future<void> transitionPrintJob({
    required String actor,
    required int jobId,
    required PrintJobStatus to,
  }) => db.transaction(() async {
    final job = await (db.select(
      db.printJobs,
    )..where((t) => t.id.equals(jobId))).getSingleOrNull();
    if (job == null) throw IndustrialException('Print job $jobId does not exist');
    final from = PrintJobStatus.fromDb(job.status);
    if (from == null) {
      throw IndustrialException('Print job has unknown status "${job.status}"');
    }
    if (!from.canMoveTo(to)) {
      throw IndustrialException(
        'Print job $jobId cannot go from ${from.dbValue} to ${to.dbValue}',
      );
    }
    final changed =
        await (db.update(db.printJobs)..where(
              (t) => t.id.equals(jobId) & t.status.equals(from.dbValue),
            ))
            .write(
              PrintJobsCompanion(
                status: Value(to.dbValue),
                updatedAt: Value(_now()),
              ),
            );
    if (changed != 1) {
      throw IndustrialException('Print job changed while updating; try again');
    }
    if (to == PrintJobStatus.completed) {
      await (db.update(db.serialNumbers)..where(
            (t) =>
                t.printJobId.equals(jobId) &
                t.status.equals(SerialStatus.allocated.dbValue),
          ))
          .write(
            SerialNumbersCompanion(
              status: Value(SerialStatus.printed.dbValue),
              updatedAt: Value(_now()),
            ),
          );
    }
    if (to == PrintJobStatus.cancelled && from == PrintJobStatus.queued) {
      await (db.update(
        db.serialNumbers,
      )..where((t) => t.printJobId.equals(jobId))).write(
        SerialNumbersCompanion(
          printJobId: const Value<int?>(null),
          updatedAt: Value(_now()),
        ),
      );
    }
    await _audit(actor, 'print_job.status_changed', 'print_job', jobId, {
      'from': from.dbValue,
      'to': to.dbValue,
    });
  });
}
