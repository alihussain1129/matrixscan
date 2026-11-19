import 'package:drift/drift.dart';

/// Product master record. SKUs and GTINs are unique; products are archived,
/// never deleted.
class Products extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get sku => text().withLength(min: 1, max: 64).unique()();
  TextColumn get name => text().withLength(min: 1, max: 200)();
  TextColumn get description => text().nullable()();

  /// Digits only, 8, 12, 13 or 14 long. Check-digit validation happens in the
  /// domain layer, not here.
  TextColumn get gtin => text().nullable().unique()();
  TextColumn get unitOfMeasure => text().withDefault(const Constant('EA'))();
  TextColumn get status => text().withDefault(const Constant('active'))();
  DateTimeColumn get createdAt => dateTime().clientDefault(DateTime.now)();

  @override
  List<String> get customConstraints => [
    "CHECK (status IN ('active','archived'))",
    "CHECK (gtin IS NULL OR (length(gtin) IN (8,12,13,14) "
        "AND gtin NOT GLOB '*[^0-9]*'))",
  ];
}

class Batches extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get productId => integer().references(Products, #id)();
  TextColumn get lotNumber => text().withLength(min: 1, max: 64)();
  DateTimeColumn get manufacturingDate => dateTime().nullable()();
  DateTimeColumn get expiryDate => dateTime().nullable()();
  DateTimeColumn get createdAt => dateTime().clientDefault(DateTime.now)();

  @override
  List<Set<Column>> get uniqueKeys => [
    {productId, lotNumber},
  ];

  @override
  List<String> get customConstraints => [
    "CHECK (expiry_date IS NULL OR manufacturing_date IS NULL "
        "OR expiry_date >= manufacturing_date)",
  ];
}

class ProductionOrders extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get orderNumber => text().withLength(min: 1, max: 64).unique()();
  IntColumn get productId => integer().references(Products, #id)();
  IntColumn get batchId => integer().nullable().references(Batches, #id)();
  IntColumn get plannedQuantity => integer()();
  TextColumn get status => text().withDefault(const Constant('draft'))();
  TextColumn get productionLine => text().nullable()();
  TextColumn get shift => text().nullable()();
  TextColumn get operatorName => text().nullable()();
  DateTimeColumn get createdAt => dateTime().clientDefault(DateTime.now)();
  DateTimeColumn get updatedAt => dateTime().clientDefault(DateTime.now)();

  @override
  List<String> get customConstraints => [
    "CHECK (planned_quantity > 0)",
    "CHECK (status IN ('draft','approved','ready','in_progress',"
        "'completed','suspended','cancelled'))",
  ];
}

/// Append-only. UPDATE and DELETE are blocked by triggers created in
/// IndustrialDatabase.
class AuditEvents extends Table {
  IntColumn get id => integer().autoIncrement()();
  DateTimeColumn get occurredAt => dateTime().clientDefault(DateTime.now)();
  TextColumn get actor => text()();
  TextColumn get action => text()();
  TextColumn get entityType => text()();
  TextColumn get entityId => text()();
  TextColumn get detailsJson => text().withDefault(const Constant('{}'))();
}

/// One serial number for one product. A serial is unique per product forever
/// (voided serials are never reused).
class SerialNumbers extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get orderId => integer().references(ProductionOrders, #id)();
  IntColumn get productId => integer().references(Products, #id)();
  TextColumn get serial => text().withLength(min: 1, max: 20)();
  TextColumn get status => text().withDefault(const Constant('allocated'))();
  IntColumn get printJobId => integer().nullable().references(PrintJobs, #id)();
  DateTimeColumn get createdAt => dateTime().clientDefault(DateTime.now)();
  DateTimeColumn get updatedAt => dateTime().clientDefault(DateTime.now)();

  @override
  List<Set<Column>> get uniqueKeys => [
    {productId, serial},
  ];

  @override
  List<String> get customConstraints => [
    "CHECK (length(serial) BETWEEN 1 AND 20)",
    "CHECK (status IN ('allocated','printed','verified','rejected','voided'))",
  ];
}

class PrintJobs extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get orderId => integer().references(ProductionOrders, #id)();
  IntColumn get quantity => integer()();
  TextColumn get status => text().withDefault(const Constant('queued'))();
  TextColumn get printerName => text().nullable()();
  DateTimeColumn get createdAt => dateTime().clientDefault(DateTime.now)();
  DateTimeColumn get updatedAt => dateTime().clientDefault(DateTime.now)();

  @override
  List<String> get customConstraints => [
    "CHECK (quantity > 0)",
    "CHECK (status IN ('queued','printing','completed','failed','cancelled'))",
  ];
}
