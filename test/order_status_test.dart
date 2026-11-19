import 'package:flutter_test/flutter_test.dart';
import 'package:exalted/industrial/domain/order_status.dart';

void main() {
  test('the happy path is allowed step by step', () {
    expect(OrderStatus.draft.canMoveTo(OrderStatus.approved), isTrue);
    expect(OrderStatus.approved.canMoveTo(OrderStatus.ready), isTrue);
    expect(OrderStatus.ready.canMoveTo(OrderStatus.inProgress), isTrue);
    expect(OrderStatus.inProgress.canMoveTo(OrderStatus.completed), isTrue);
  });

  test('steps cannot be skipped or reversed', () {
    expect(OrderStatus.draft.canMoveTo(OrderStatus.inProgress), isFalse);
    expect(OrderStatus.draft.canMoveTo(OrderStatus.completed), isFalse);
    expect(OrderStatus.inProgress.canMoveTo(OrderStatus.draft), isFalse);
  });

  test('completed and cancelled are final', () {
    expect(OrderStatus.completed.isFinal, isTrue);
    expect(OrderStatus.cancelled.isFinal, isTrue);
    for (final s in OrderStatus.values) {
      expect(OrderStatus.completed.canMoveTo(s), isFalse);
      expect(OrderStatus.cancelled.canMoveTo(s), isFalse);
    }
  });

  test('suspended orders can resume or be cancelled only', () {
    expect(OrderStatus.suspended.allowedNext, {
      OrderStatus.inProgress,
      OrderStatus.cancelled,
    });
  });

  test('database values round-trip', () {
    for (final s in OrderStatus.values) {
      expect(OrderStatus.fromDb(s.dbValue), s);
    }
    expect(OrderStatus.fromDb('nonsense'), isNull);
  });
}
