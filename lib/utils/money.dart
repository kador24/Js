class Money {
  Money._();

  static const int scale = 100;

  static double round(double value) =>
      (value * scale).roundToDouble() / scale;

  static double add(double a, double b) => round(a + b);
  static double subtract(double a, double b) => round(a - b);
  static double multiply(double a, int quantity) => round(a * quantity);

  static double weightedAverage({
    required int oldQuantity,
    required double oldUnitCost,
    required int incomingQuantity,
    required double incomingUnitCost,
  }) {
    final quantity = oldQuantity + incomingQuantity;
    if (quantity <= 0) return 0;
    final value = (oldQuantity * oldUnitCost) +
        (incomingQuantity * incomingUnitCost);
    return round(value / quantity);
  }

  static bool same(double a, double b) => (a - b).abs() < 0.005;
}
