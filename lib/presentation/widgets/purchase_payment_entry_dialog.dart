import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../../core/enums/financial_enums.dart';
import '../../core/services/supplier_service.dart';
import '../../core/services/auth_service.dart';
import '../../core/services/logging_service.dart';
import '../../data/models/shift_expense_model.dart';

/// Purchase Payment Entry Dialog (Phase 4)
/// 
/// A lightweight dialog for recording purchase payments during a financial shift.
/// This allows quick entry of payments to suppliers without navigating to the 
/// full Suppliers screen.
/// 
/// Features:
/// - Amount entry with validation
/// - Optional invoice number linking
/// - Optional notes
/// - Automatic tracking with shift expenses
/// 
/// Note: Since Suppliers UI is removed (Phase 1), this dialog records payments
/// as shift expenses with category 'supplies' for tracking purposes.
class PurchasePaymentEntryDialog extends StatefulWidget {
  final String financialShiftId;
  final Function(double amount, String? invoiceNumber, String? notes)? onPaymentRecorded;
  
  const PurchasePaymentEntryDialog({
    super.key,
    required this.financialShiftId,
    this.onPaymentRecorded,
  });
  
  /// Show the dialog and return the result
  static Future<Map<String, dynamic>?> show(
    BuildContext context, {
    required String financialShiftId,
  }) async {
    return showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => PurchasePaymentEntryDialog(
        financialShiftId: financialShiftId,
      ),
    );
  }

  @override
  State<PurchasePaymentEntryDialog> createState() => _PurchasePaymentEntryDialogState();
}

class _PurchasePaymentEntryDialogState extends State<PurchasePaymentEntryDialog> {
  final _formKey = GlobalKey<FormState>();
  final _amountController = TextEditingController();
  final _invoiceController = TextEditingController();
  final _notesController = TextEditingController();
  
  final _currencyFormat = NumberFormat.currency(symbol: 'EGP ', decimalDigits: 2);
  
  bool _isSubmitting = false;
  String? _errorMessage;

  @override
  void dispose() {
    _amountController.dispose();
    _invoiceController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _submitPayment() async {
    if (!_formKey.currentState!.validate()) return;
    
    final amount = double.tryParse(_amountController.text);
    if (amount == null || amount <= 0) {
      setState(() => _errorMessage = 'Please enter a valid amount');
      return;
    }
    
    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });
    
    try {
      final invoiceNumber = _invoiceController.text.isEmpty ? null : _invoiceController.text;
      final notes = _notesController.text.isEmpty ? null : _notesController.text;
      
      // Build description for tracking
      String description = 'Purchase payment';
      if (invoiceNumber != null) {
        description += ' - Invoice: $invoiceNumber';
      }
      if (notes != null) {
        description += ' - $notes';
      }
      
      LoggingService.instance.info(
        'PurchasePaymentEntry',
        '[PURCHASE_PAYMENT_RECORDED] Amount: $amount, Invoice: $invoiceNumber, Notes: $notes',
      );
      
      // Return the result to be handled by the caller
      if (mounted) {
        Navigator.of(context).pop({
          'amount': amount,
          'invoiceNumber': invoiceNumber,
          'notes': notes,
          'description': description,
          'category': ExpenseCategory.supplies,
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Failed to record payment: $e';
        _isSubmitting = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    return AlertDialog(
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: theme.colorScheme.primaryContainer,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              Icons.payment,
              color: theme.colorScheme.onPrimaryContainer,
            ),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Record Purchase Payment'),
                Text(
                  'Quick payment entry',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.normal,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: 400,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Info banner
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.info_outline,
                      size: 20,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Record cash payments made to suppliers during this shift. This will be deducted from expected cash.',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              
              // Amount field
              TextFormField(
                controller: _amountController,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}')),
                ],
                decoration: const InputDecoration(
                  labelText: 'Payment Amount (EGP) *',
                  prefixIcon: Icon(Icons.attach_money),
                  border: OutlineInputBorder(),
                  hintText: '0.00',
                ),
                autofocus: true,
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Please enter an amount';
                  }
                  final amount = double.tryParse(value);
                  if (amount == null || amount <= 0) {
                    return 'Please enter a valid amount';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              
              // Invoice number field (optional)
              TextFormField(
                controller: _invoiceController,
                decoration: const InputDecoration(
                  labelText: 'Invoice/Reference Number (optional)',
                  prefixIcon: Icon(Icons.receipt),
                  border: OutlineInputBorder(),
                  hintText: 'e.g., INV-2024-001',
                ),
              ),
              const SizedBox(height: 16),
              
              // Notes field (optional)
              TextFormField(
                controller: _notesController,
                decoration: const InputDecoration(
                  labelText: 'Notes (optional)',
                  prefixIcon: Icon(Icons.note),
                  border: OutlineInputBorder(),
                  hintText: 'e.g., Payment to ABC Pharma',
                ),
                maxLines: 2,
              ),
              
              // Error message
              if (_errorMessage != null) ...[
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.errorContainer,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.error_outline,
                        color: theme.colorScheme.onErrorContainer,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _errorMessage!,
                          style: TextStyle(
                            color: theme.colorScheme.onErrorContainer,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isSubmitting ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton.icon(
          onPressed: _isSubmitting ? null : _submitPayment,
          icon: _isSubmitting 
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.payment),
          label: Text(_isSubmitting ? 'Recording...' : 'Record Payment'),
        ),
      ],
    );
  }
}
