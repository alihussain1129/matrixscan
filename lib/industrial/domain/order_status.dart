/// Production order lifecycle. The database only checks that a status value is
/// valid; the allowed transitions are enforced here.
enum OrderStatus {
  draft('draft'),
  approved('approved'),
  ready('ready'),
  inProgress('in_progress'),
  completed('completed'),
  suspended('suspended'),
  cancelled('cancelled');

  const OrderStatus(this.dbValue);

  final String dbValue;

  static OrderStatus? fromDb(String value) {
    for (final s in OrderStatus.values) {
      if (s.dbValue == value) return s;
    }
    return null;
  }

  Set<OrderStatus> get allowedNext => switch (this) {
    OrderStatus.draft => {OrderStatus.approved, OrderStatus.cancelled},
    OrderStatus.approved => {
      OrderStatus.ready,
      OrderStatus.suspended,
      OrderStatus.cancelled,
    },
    OrderStatus.ready => {
      OrderStatus.inProgress,
      OrderStatus.suspended,
      OrderStatus.cancelled,
    },
    OrderStatus.inProgress => {
      OrderStatus.completed,
      OrderStatus.suspended,
      OrderStatus.cancelled,
    },
    OrderStatus.suspended => {OrderStatus.inProgress, OrderStatus.cancelled},
    OrderStatus.completed => <OrderStatus>{},
    OrderStatus.cancelled => <OrderStatus>{},
  };

  bool canMoveTo(OrderStatus next) => allowedNext.contains(next);

  bool get isFinal => allowedNext.isEmpty;
}
