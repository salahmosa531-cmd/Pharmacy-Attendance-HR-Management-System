/// ⚠️ DOMAIN CONTRACT - FINANCIAL ENUMS
/// 
/// This file re-exports financial enums from their canonical sources.
/// Do not rename enum values without migration.
/// Do not move this file.
/// All financial modules can import from this file for convenience.
/// 
/// CANONICAL SOURCES:
/// - PaymentMethod, ExpenseCategory, SupplierTransactionType: app_constants.dart
/// - FinancialShiftStatus: financial_shift_model.dart

// Re-export from app_constants.dart
export '../constants/app_constants.dart' 
    show PaymentMethod, PaymentMethodExtension,
         ExpenseCategory, ExpenseCategoryExtension,
         SupplierTransactionType, SupplierTransactionTypeExtension;

// Re-export from financial_shift_model.dart  
export '../../data/models/financial_shift_model.dart'
    show FinancialShiftStatus;
