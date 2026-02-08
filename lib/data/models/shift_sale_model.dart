import 'package:equatable/equatable.dart';

/// Represents a sale transaction during a financial shift
/// 
/// Records individual sales with payment method, amount, and optional
/// description. Supports multiple payment types: cash, card, wallet,
/// insurance, and credit/account sales.
class ShiftSale extends Equatable {
  final String id;
  final String financialShiftId;
  final String branchId;
  final double amount;
  final PaymentMethod paymentMethod;
  final String? description;
  final String? invoiceNumber;
  final String? customerName;
  final String? recordedBy;
  final DateTime createdAt;
  final DateTime? syncedAt;

  const ShiftSale({
    required this.id,
    required this.financialShiftId,
    required this.branchId,
    required this.amount,
    this.paymentMethod = PaymentMethod.cash,
    this.description,
    this.invoiceNumber,
    this.customerName,
    this.recordedBy,
    required this.createdAt,
    this.syncedAt,
  });

  /// Create from database map
  factory ShiftSale.fromMap(Map<String, dynamic> map) {
    return ShiftSale(
      id: map['id'] as String,
      financialShiftId: map['financial_shift_id'] as String,
      branchId: map['branch_id'] as String,
      amount: (map['amount'] as num?)?.toDouble() ?? 0,
      paymentMethod: PaymentMethod.fromString(map['payment_method'] as String? ?? 'cash'),
      description: map['description'] as String?,
      invoiceNumber: map['invoice_number'] as String?,
      customerName: map['customer_name'] as String?,
      recordedBy: map['recorded_by'] as String?,
      createdAt: DateTime.parse(map['created_at'] as String),
      syncedAt: map['synced_at'] != null 
          ? DateTime.parse(map['synced_at'] as String)
          : null,
    );
  }

  /// Convert to database map
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'financial_shift_id': financialShiftId,
      'branch_id': branchId,
      'amount': amount,
      'payment_method': paymentMethod.value,
      'description': description,
      'invoice_number': invoiceNumber,
      'customer_name': customerName,
      'recorded_by': recordedBy,
      'created_at': createdAt.toIso8601String(),
      'synced_at': syncedAt?.toIso8601String(),
    };
  }

  /// Create a copy with updated fields
  ShiftSale copyWith({
    String? id,
    String? financialShiftId,
    String? branchId,
    double? amount,
    PaymentMethod? paymentMethod,
    String? description,
    String? invoiceNumber,
    String? customerName,
    String? recordedBy,
    DateTime? createdAt,
    DateTime? syncedAt,
  }) {
    return ShiftSale(
      id: id ?? this.id,
      financialShiftId: financialShiftId ?? this.financialShiftId,
      branchId: branchId ?? this.branchId,
      amount: amount ?? this.amount,
      paymentMethod: paymentMethod ?? this.paymentMethod,
      description: description ?? this.description,
      invoiceNumber: invoiceNumber ?? this.invoiceNumber,
      customerName: customerName ?? this.customerName,
      recordedBy: recordedBy ?? this.recordedBy,
      createdAt: createdAt ?? this.createdAt,
      syncedAt: syncedAt ?? this.syncedAt,
    );
  }

  /// Check if this is a cash sale
  bool get isCashSale => paymentMethod == PaymentMethod.cash;

  @override
  List<Object?> get props => [
    id, financialShiftId, branchId, amount, paymentMethod,
    description, invoiceNumber, customerName, recordedBy,
    createdAt, syncedAt,
  ];
}

/// Payment method enum
enum PaymentMethod {
  cash('cash', 'Cash', 'Payment in cash'),
  card('card', 'Card/Visa', 'Credit or debit card payment'),
  wallet('wallet', 'E-Wallet', 'Vodafone Cash, Fawry, etc.'),
  insurance('insurance', 'Insurance', 'Insurance claim payment'),
  credit('credit', 'Credit/Account', 'Customer account/credit sale');

  final String value;
  final String displayName;
  final String description;

  const PaymentMethod(this.value, this.displayName, this.description);

  static PaymentMethod fromString(String value) {
    return PaymentMethod.values.firstWhere(
      (m) => m.value == value,
      orElse: () => PaymentMethod.cash,
    );
  }
}
