class Expense {
  final int? id;
  final String title;
  final double amount;
  final String? category;
  final String? notes;
  final String expenseDate;
  final String createdAt;

  Expense({
    this.id,
    required this.title,
    required this.amount,
    this.category,
    this.notes,
    required this.expenseDate,
    required this.createdAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'title': title,
      'amount': amount,
      'category': category,
      'notes': notes,
      'expense_date': expenseDate,
      'created_at': createdAt,
    };
  }

  factory Expense.fromMap(Map<String, dynamic> map) {
    return Expense(
      id: map['id'] as int?,
      title: map['title'] as String,
      amount: (map['amount'] as num).toDouble(),
      category: map['category'] as String?,
      notes: map['notes'] as String?,
      expenseDate: map['expense_date'] as String,
      createdAt: map['created_at'] as String,
    );
  }
}
