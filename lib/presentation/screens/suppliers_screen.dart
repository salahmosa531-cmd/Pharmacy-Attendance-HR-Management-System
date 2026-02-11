import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../../core/services/supplier_service.dart';
import '../../core/services/auth_service.dart';
import '../../data/models/supplier_model.dart';
import '../../data/models/supplier_transaction_model.dart';

/// Supplier Management Screen
/// 
/// Handles:
/// - Viewing all suppliers with balances
/// - Adding new suppliers
/// - Recording purchases and payments
/// - Viewing transaction history
class SuppliersScreen extends StatefulWidget {
  const SuppliersScreen({super.key});

  @override
  State<SuppliersScreen> createState() => _SuppliersScreenState();
}

class _SuppliersScreenState extends State<SuppliersScreen> {
  final _supplierService = SupplierService.instance;
  final _authService = AuthService.instance;
  
  bool _isLoading = true;
  List<Map<String, dynamic>> _suppliersWithBalances = [];
  String _searchQuery = '';
  
  final _currencyFormat = NumberFormat.currency(symbol: 'EGP ', decimalDigits: 2);
  final _dateFormat = DateFormat('dd MMM yyyy');

  @override
  void initState() {
    super.initState();
    _loadSuppliers();
  }

  Future<void> _loadSuppliers() async {
    setState(() => _isLoading = true);
    
    try {
      // Service now uses hardcoded branch_id = '1'
      _suppliersWithBalances = await _supplierService.getSuppliersWithBalances();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading suppliers: $e'), backgroundColor: Colors.red),
        );
      }
    }
    
    if (mounted) {
      setState(() => _isLoading = false);
    }
  }

  List<Map<String, dynamic>> get _filteredSuppliers {
    if (_searchQuery.isEmpty) return _suppliersWithBalances;
    
    final query = _searchQuery.toLowerCase();
    return _suppliersWithBalances.where((s) {
      final name = (s['name'] as String?)?.toLowerCase() ?? '';
      final code = (s['code'] as String?)?.toLowerCase() ?? '';
      return name.contains(query) || code.contains(query);
    }).toList();
  }

  Future<void> _addSupplier() async {
    final result = await _showSupplierDialog();
    if (result == null) return;
    
    setState(() => _isLoading = true);
    
    try {
      // Service now uses hardcoded branch_id = '1'
      await _supplierService.createSupplier(
        name: result['name'] as String,
        code: result['code'] as String?,
        phone: result['phone'] as String?,
        email: result['email'] as String?,
        address: result['address'] as String?,
        contactPerson: result['contactPerson'] as String?,
        paymentTermsDays: result['paymentTermsDays'] as int,
        creditLimit: result['creditLimit'] as double,
      );
      
      await _loadSuppliers();
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Supplier added successfully'), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      // STABILITY: Error is shown via snackbar, screen state remains stable
      // Do NOT pop, do NOT clear list, do NOT navigate away
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error adding supplier: $e'), backgroundColor: Colors.red),
        );
      }
    }
    
    if (mounted) {
      setState(() => _isLoading = false);
    }
  }

  Future<Map<String, dynamic>?> _showSupplierDialog({Supplier? supplier}) async {
    final nameController = TextEditingController(text: supplier?.name);
    final codeController = TextEditingController(text: supplier?.code);
    final phoneController = TextEditingController(text: supplier?.phone);
    final emailController = TextEditingController(text: supplier?.email);
    final addressController = TextEditingController(text: supplier?.address);
    final contactController = TextEditingController(text: supplier?.contactPerson);
    final termsController = TextEditingController(text: (supplier?.paymentTermsDays ?? 30).toString());
    final limitController = TextEditingController(text: (supplier?.creditLimit ?? 0).toString());
    
    return showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(supplier == null ? 'Add Supplier' : 'Edit Supplier'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                decoration: const InputDecoration(
                  labelText: 'Company Name *',
                  prefixIcon: Icon(Icons.business),
                  border: OutlineInputBorder(),
                ),
                autofocus: true,
              ),
              const SizedBox(height: 16),
              TextField(
                controller: codeController,
                decoration: const InputDecoration(
                  labelText: 'Supplier Code',
                  prefixIcon: Icon(Icons.qr_code),
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: phoneController,
                decoration: const InputDecoration(
                  labelText: 'Phone',
                  prefixIcon: Icon(Icons.phone),
                  border: OutlineInputBorder(),
                ),
                keyboardType: TextInputType.phone,
              ),
              const SizedBox(height: 16),
              TextField(
                controller: emailController,
                decoration: const InputDecoration(
                  labelText: 'Email',
                  prefixIcon: Icon(Icons.email),
                  border: OutlineInputBorder(),
                ),
                keyboardType: TextInputType.emailAddress,
              ),
              const SizedBox(height: 16),
              TextField(
                controller: contactController,
                decoration: const InputDecoration(
                  labelText: 'Contact Person',
                  prefixIcon: Icon(Icons.person),
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: addressController,
                decoration: const InputDecoration(
                  labelText: 'Address',
                  prefixIcon: Icon(Icons.location_on),
                  border: OutlineInputBorder(),
                ),
                maxLines: 2,
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: termsController,
                      decoration: const InputDecoration(
                        labelText: 'Payment Terms (days)',
                        prefixIcon: Icon(Icons.calendar_today),
                        border: OutlineInputBorder(),
                      ),
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: TextField(
                      controller: limitController,
                      decoration: const InputDecoration(
                        labelText: 'Credit Limit',
                        prefixIcon: Icon(Icons.credit_card),
                        border: OutlineInputBorder(),
                      ),
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}'))],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              if (nameController.text.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Please enter company name')),
                );
                return;
              }
              Navigator.pop(context, {
                'name': nameController.text,
                'code': codeController.text.isEmpty ? null : codeController.text,
                'phone': phoneController.text.isEmpty ? null : phoneController.text,
                'email': emailController.text.isEmpty ? null : emailController.text,
                'address': addressController.text.isEmpty ? null : addressController.text,
                'contactPerson': contactController.text.isEmpty ? null : contactController.text,
                'paymentTermsDays': int.tryParse(termsController.text) ?? 30,
                'creditLimit': double.tryParse(limitController.text) ?? 0,
              });
            },
            child: Text(supplier == null ? 'Add' : 'Save'),
          ),
        ],
      ),
    );
  }

  Future<void> _showSupplierDetails(String supplierId) async {
    setState(() => _isLoading = true);
    
    try {
      final summary = await _supplierService.getSupplierSummary(supplierId);
      final transactions = await _supplierService.getTransactions(supplierId, limit: 50);
      
      if (mounted) {
        setState(() => _isLoading = false);
        
        await showModalBottomSheet(
          context: context,
          isScrollControlled: true,
          useSafeArea: true,
          builder: (context) => _SupplierDetailSheet(
            summary: summary,
            transactions: transactions,
            currencyFormat: _currencyFormat,
            dateFormat: _dateFormat,
            onRecordPurchase: () => _recordPurchase(supplierId),
            onRecordPayment: () => _recordPayment(supplierId),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading supplier: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _recordPurchase(String supplierId) async {
    Navigator.pop(context); // Close bottom sheet
    
    final result = await _showPurchaseDialog();
    if (result == null) return;
    
    setState(() => _isLoading = true);
    
    try {
      // Service now uses hardcoded branch_id = '1'
      await _supplierService.recordPurchase(
        supplierId: supplierId,
        amount: result['amount'] as double,
        invoiceNumber: result['invoiceNumber'] as String?,
        invoiceDate: result['invoiceDate'] as DateTime?,
        dueDate: result['dueDate'] as DateTime?,
        notes: result['notes'] as String?,
        recordedBy: _authService.currentUser?.id,
      );
      
      await _loadSuppliers();
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Purchase recorded'), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      // STABILITY: Error shown via snackbar, screen remains stable
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error recording purchase: $e'), backgroundColor: Colors.red),
        );
      }
    }
    
    if (mounted) {
      setState(() => _isLoading = false);
    }
  }

  Future<Map<String, dynamic>?> _showPurchaseDialog() async {
    final amountController = TextEditingController();
    final invoiceController = TextEditingController();
    final notesController = TextEditingController();
    DateTime? invoiceDate = DateTime.now();
    DateTime? dueDate;
    
    return showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Record Purchase'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: amountController,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}'))],
                  decoration: const InputDecoration(
                    labelText: 'Amount (EGP) *',
                    prefixIcon: Icon(Icons.attach_money),
                    border: OutlineInputBorder(),
                  ),
                  autofocus: true,
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: invoiceController,
                  decoration: const InputDecoration(
                    labelText: 'Invoice Number',
                    prefixIcon: Icon(Icons.receipt),
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                ListTile(
                  leading: const Icon(Icons.calendar_today),
                  title: const Text('Invoice Date'),
                  subtitle: Text(invoiceDate != null ? _dateFormat.format(invoiceDate!) : 'Not set'),
                  onTap: () async {
                    final date = await showDatePicker(
                      context: context,
                      initialDate: invoiceDate ?? DateTime.now(),
                      firstDate: DateTime.now().subtract(const Duration(days: 365)),
                      lastDate: DateTime.now(),
                    );
                    if (date != null) {
                      setDialogState(() => invoiceDate = date);
                    }
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.event),
                  title: const Text('Due Date'),
                  subtitle: Text(dueDate != null ? _dateFormat.format(dueDate!) : 'Not set'),
                  onTap: () async {
                    final date = await showDatePicker(
                      context: context,
                      initialDate: dueDate ?? DateTime.now().add(const Duration(days: 30)),
                      firstDate: DateTime.now(),
                      lastDate: DateTime.now().add(const Duration(days: 365)),
                    );
                    if (date != null) {
                      setDialogState(() => dueDate = date);
                    }
                  },
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: notesController,
                  decoration: const InputDecoration(
                    labelText: 'Notes',
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
            FilledButton(
              onPressed: () {
                final amount = double.tryParse(amountController.text);
                if (amount == null || amount <= 0) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Please enter a valid amount')),
                  );
                  return;
                }
                Navigator.pop(context, {
                  'amount': amount,
                  'invoiceNumber': invoiceController.text.isEmpty ? null : invoiceController.text,
                  'invoiceDate': invoiceDate,
                  'dueDate': dueDate,
                  'notes': notesController.text.isEmpty ? null : notesController.text,
                });
              },
              child: const Text('Record Purchase'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _recordPayment(String supplierId) async {
    Navigator.pop(context); // Close bottom sheet
    
    final result = await _showPaymentDialog();
    if (result == null) return;
    
    setState(() => _isLoading = true);
    
    try {
      // Service now uses hardcoded branch_id = '1'
      await _supplierService.recordPayment(
        supplierId: supplierId,
        amount: result['amount'] as double,
        paymentMethod: result['paymentMethod'] as String?,
        referenceNumber: result['referenceNumber'] as String?,
        notes: result['notes'] as String?,
        recordedBy: _authService.currentUser?.id,
      );
      
      await _loadSuppliers();
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Payment recorded'), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      // STABILITY: Error shown via snackbar, screen remains stable
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error recording payment: $e'), backgroundColor: Colors.red),
        );
      }
    }
    
    if (mounted) {
      setState(() => _isLoading = false);
    }
  }

  Future<Map<String, dynamic>?> _showPaymentDialog() async {
    final amountController = TextEditingController();
    final referenceController = TextEditingController();
    final notesController = TextEditingController();
    String paymentMethod = 'Cash';
    
    return showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Record Payment'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: amountController,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}'))],
                  decoration: const InputDecoration(
                    labelText: 'Amount (EGP) *',
                    prefixIcon: Icon(Icons.attach_money),
                    border: OutlineInputBorder(),
                  ),
                  autofocus: true,
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  value: paymentMethod,
                  decoration: const InputDecoration(
                    labelText: 'Payment Method',
                    prefixIcon: Icon(Icons.payment),
                    border: OutlineInputBorder(),
                  ),
                  items: const [
                    DropdownMenuItem(value: 'Cash', child: Text('Cash')),
                    DropdownMenuItem(value: 'Bank Transfer', child: Text('Bank Transfer')),
                    DropdownMenuItem(value: 'Cheque', child: Text('Cheque')),
                    DropdownMenuItem(value: 'Card', child: Text('Card')),
                  ],
                  onChanged: (v) => setDialogState(() => paymentMethod = v!),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: referenceController,
                  decoration: const InputDecoration(
                    labelText: 'Reference Number',
                    prefixIcon: Icon(Icons.numbers),
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: notesController,
                  decoration: const InputDecoration(
                    labelText: 'Notes',
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
            FilledButton(
              onPressed: () {
                final amount = double.tryParse(amountController.text);
                if (amount == null || amount <= 0) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Please enter a valid amount')),
                  );
                  return;
                }
                Navigator.pop(context, {
                  'amount': amount,
                  'paymentMethod': paymentMethod,
                  'referenceNumber': referenceController.text.isEmpty ? null : referenceController.text,
                  'notes': notesController.text.isEmpty ? null : notesController.text,
                });
              },
              child: const Text('Record Payment'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final totalOwed = _suppliersWithBalances.fold<double>(
      0,
      (sum, s) => sum + ((s['balance'] as double?) ?? 0).clamp(0, double.infinity),
    );
    
    return Scaffold(
      appBar: AppBar(
        title: const Text('Suppliers'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadSuppliers,
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: Column(
        children: [
          // Summary Card
          Container(
            color: Theme.of(context).colorScheme.primaryContainer,
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Total Amount Owed',
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          color: Theme.of(context).colorScheme.onPrimaryContainer,
                        ),
                      ),
                      Text(
                        _currencyFormat.format(totalOwed),
                        style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: Theme.of(context).colorScheme.onPrimaryContainer,
                        ),
                      ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      '${_suppliersWithBalances.length}',
                      style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: Theme.of(context).colorScheme.onPrimaryContainer,
                      ),
                    ),
                    Text(
                      'Suppliers',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onPrimaryContainer,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          
          // Search Bar
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              decoration: InputDecoration(
                hintText: 'Search suppliers...',
                prefixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                filled: true,
              ),
              onChanged: (value) => setState(() => _searchQuery = value),
            ),
          ),
          
          // Suppliers List
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _filteredSuppliers.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.business, size: 64, color: Theme.of(context).colorScheme.outline),
                            const SizedBox(height: 16),
                            Text(
                              _searchQuery.isEmpty ? 'No suppliers yet' : 'No matching suppliers',
                              style: Theme.of(context).textTheme.bodyLarge,
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        itemCount: _filteredSuppliers.length,
                        itemBuilder: (context, index) {
                          final supplier = _filteredSuppliers[index];
                          final balance = (supplier['balance'] as double?) ?? 0;
                          final isOwed = balance > 0;
                          
                          return Card(
                            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                            child: ListTile(
                              leading: CircleAvatar(
                                backgroundColor: isOwed ? Colors.red.shade100 : Colors.green.shade100,
                                child: Icon(
                                  Icons.business,
                                  color: isOwed ? Colors.red : Colors.green,
                                ),
                              ),
                              title: Text(supplier['name'] as String? ?? 'Unknown'),
                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  if (supplier['code'] != null)
                                    Text('Code: ${supplier['code']}'),
                                  Text(
                                    isOwed
                                        ? 'Owed: ${_currencyFormat.format(balance)}'
                                        : balance < 0
                                            ? 'Credit: ${_currencyFormat.format(balance.abs())}'
                                            : 'Settled',
                                    style: TextStyle(
                                      color: isOwed ? Colors.red : Colors.green,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                              trailing: const Icon(Icons.chevron_right),
                              onTap: () => _showSupplierDetails(supplier['id'] as String),
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addSupplier,
        icon: const Icon(Icons.add),
        label: const Text('Add Supplier'),
      ),
    );
  }
}

/// Bottom sheet for supplier details
class _SupplierDetailSheet extends StatelessWidget {
  final SupplierSummary summary;
  final List<SupplierTransaction> transactions;
  final NumberFormat currencyFormat;
  final DateFormat dateFormat;
  final VoidCallback onRecordPurchase;
  final VoidCallback onRecordPayment;

  const _SupplierDetailSheet({
    required this.summary,
    required this.transactions,
    required this.currencyFormat,
    required this.dateFormat,
    required this.onRecordPurchase,
    required this.onRecordPayment,
  });

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.9,
      maxChildSize: 0.95,
      minChildSize: 0.5,
      builder: (context, scrollController) => Container(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          children: [
            // Handle
            Container(
              margin: const EdgeInsets.only(top: 12),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.outline,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            
            // Header
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  CircleAvatar(
                    radius: 30,
                    child: Text(
                      summary.supplier.name.substring(0, 1).toUpperCase(),
                      style: const TextStyle(fontSize: 24),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    summary.supplier.name,
                    style: Theme.of(context).textTheme.titleLarge,
                    textAlign: TextAlign.center,
                  ),
                  if (summary.supplier.code != null)
                    Text(
                      'Code: ${summary.supplier.code}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                ],
              ),
            ),
            
            // Balance Card
            Card(
              margin: const EdgeInsets.symmetric(horizontal: 16),
              color: summary.hasBalance 
                  ? Colors.red.shade50 
                  : Colors.green.shade50,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    Column(
                      children: [
                        Text('Purchases', style: Theme.of(context).textTheme.bodySmall),
                        Text(
                          currencyFormat.format(summary.totalPurchases),
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                    Column(
                      children: [
                        Text('Payments', style: Theme.of(context).textTheme.bodySmall),
                        Text(
                          currencyFormat.format(summary.totalPayments),
                          style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.green),
                        ),
                      ],
                    ),
                    Column(
                      children: [
                        Text('Balance', style: Theme.of(context).textTheme.bodySmall),
                        Text(
                          currencyFormat.format(summary.balance),
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: summary.hasBalance ? Colors.red : Colors.green,
                            fontSize: 18,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            
            // Action Buttons
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: onRecordPurchase,
                      icon: const Icon(Icons.add_shopping_cart),
                      label: const Text('Record Purchase'),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: FilledButton.tonalIcon(
                      onPressed: onRecordPayment,
                      icon: const Icon(Icons.payment),
                      label: const Text('Record Payment'),
                    ),
                  ),
                ],
              ),
            ),
            
            // Transactions Header
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Text('Transactions', style: Theme.of(context).textTheme.titleMedium),
                  const Spacer(),
                  if (summary.hasOverdue)
                    Chip(
                      label: Text('${summary.overdueCount} overdue'),
                      backgroundColor: Colors.red.shade100,
                      labelStyle: const TextStyle(color: Colors.red),
                    ),
                ],
              ),
            ),
            
            // Transactions List
            Expanded(
              child: transactions.isEmpty
                  ? Center(
                      child: Text(
                        'No transactions yet',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    )
                  : ListView.builder(
                      controller: scrollController,
                      itemCount: transactions.length,
                      itemBuilder: (context, index) {
                        final tx = transactions[index];
                        final isPurchase = tx.isPurchase;
                        
                        return ListTile(
                          leading: CircleAvatar(
                            backgroundColor: isPurchase ? Colors.red.shade100 : Colors.green.shade100,
                            child: Icon(
                              isPurchase ? Icons.shopping_cart : Icons.payment,
                              color: isPurchase ? Colors.red : Colors.green,
                              size: 20,
                            ),
                          ),
                          title: Text(
                            '${isPurchase ? "+" : "-"}${currencyFormat.format(tx.amount)}',
                            style: TextStyle(
                              color: isPurchase ? Colors.red : Colors.green,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(tx.transactionType.displayName),
                              if (tx.invoiceNumber != null)
                                Text('Invoice: ${tx.invoiceNumber}'),
                              if (tx.isOverdue)
                                Text(
                                  'OVERDUE',
                                  style: TextStyle(color: Colors.red.shade700, fontWeight: FontWeight.bold),
                                ),
                            ],
                          ),
                          trailing: Text(
                            dateFormat.format(tx.createdAt),
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
