import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/theme/app_theme.dart';

/// Dialog for recording debt collection payments
/// 
/// Used when receiving payments from customers on credit accounts,
/// insurance reimbursements, or other receivables.
class DebtCollectionDialog extends StatefulWidget {
  final String financialShiftId;
  
  const DebtCollectionDialog({
    super.key,
    required this.financialShiftId,
  });
  
  /// Show the dialog and return the collection details
  static Future<Map<String, dynamic>?> show(
    BuildContext context, {
    required String financialShiftId,
  }) {
    return showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => DebtCollectionDialog(
        financialShiftId: financialShiftId,
      ),
    );
  }

  @override
  State<DebtCollectionDialog> createState() => _DebtCollectionDialogState();
}

class _DebtCollectionDialogState extends State<DebtCollectionDialog> {
  final _amountController = TextEditingController();
  final _customerNameController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _referenceController = TextEditingController();
  
  _CollectionType _selectedType = _CollectionType.customerAccount;
  
  @override
  void dispose() {
    _amountController.dispose();
    _customerNameController.dispose();
    _descriptionController.dispose();
    _referenceController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.teal.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.payments, color: Colors.teal),
          ),
          const SizedBox(width: 12),
          const Text('Collect Debt Payment'),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Info Card
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.teal.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.teal.withOpacity(0.3)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.info_outline, color: Colors.teal, size: 20),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'Record payment received from customer accounts, insurance, or other receivables.',
                      style: TextStyle(fontSize: 12, color: Colors.teal),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            
            // Collection Type
            const Text(
              'Payment Type',
              style: TextStyle(fontWeight: FontWeight.w500, fontSize: 12),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: _CollectionType.values.map((type) {
                final isSelected = _selectedType == type;
                return ChoiceChip(
                  label: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        type.icon,
                        size: 16,
                        color: isSelected ? Colors.white : Colors.teal,
                      ),
                      const SizedBox(width: 4),
                      Text(type.displayName),
                    ],
                  ),
                  selected: isSelected,
                  selectedColor: Colors.teal,
                  onSelected: (selected) {
                    if (selected) {
                      setState(() => _selectedType = type);
                    }
                  },
                );
              }).toList(),
            ),
            const SizedBox(height: 20),
            
            // Amount
            TextField(
              controller: _amountController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}')),
              ],
              decoration: const InputDecoration(
                labelText: 'Amount (EGP) *',
                prefixIcon: Icon(Icons.attach_money),
                border: OutlineInputBorder(),
                suffixText: 'EGP',
              ),
              autofocus: true,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            
            // Customer Name / Source
            TextField(
              controller: _customerNameController,
              decoration: InputDecoration(
                labelText: _selectedType == _CollectionType.insurance 
                    ? 'Insurance Company *'
                    : 'Customer Name *',
                prefixIcon: Icon(_selectedType.icon),
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            
            // Reference Number
            TextField(
              controller: _referenceController,
              decoration: InputDecoration(
                labelText: _selectedType == _CollectionType.insurance 
                    ? 'Claim Reference'
                    : 'Invoice/Account Reference',
                prefixIcon: const Icon(Icons.receipt),
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            
            // Description
            TextField(
              controller: _descriptionController,
              decoration: const InputDecoration(
                labelText: 'Notes (optional)',
                prefixIcon: Icon(Icons.note),
                border: OutlineInputBorder(),
              ),
              maxLines: 2,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton.icon(
          style: FilledButton.styleFrom(backgroundColor: Colors.teal),
          onPressed: _submit,
          icon: const Icon(Icons.check),
          label: const Text('Record Collection'),
        ),
      ],
    );
  }
  
  void _submit() {
    final amount = double.tryParse(_amountController.text);
    if (amount == null || amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a valid amount')),
      );
      return;
    }
    
    if (_customerNameController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter customer/source name')),
      );
      return;
    }
    
    Navigator.pop(context, {
      'amount': amount,
      'customerName': _customerNameController.text,
      'reference': _referenceController.text.isEmpty 
          ? null 
          : _referenceController.text,
      'description': _descriptionController.text.isEmpty 
          ? '${_selectedType.displayName} payment'
          : _descriptionController.text,
      'type': _selectedType.value,
    });
  }
}

enum _CollectionType {
  customerAccount('customer', 'Customer Account', Icons.person),
  insurance('insurance', 'Insurance', Icons.health_and_safety),
  instalment('instalment', 'Instalment', Icons.calendar_month),
  other('other', 'Other', Icons.more_horiz);
  
  final String value;
  final String displayName;
  final IconData icon;
  
  const _CollectionType(this.value, this.displayName, this.icon);
}
