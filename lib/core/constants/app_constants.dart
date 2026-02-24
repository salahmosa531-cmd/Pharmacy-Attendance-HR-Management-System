/// Application-wide constants
class AppConstants {
  // App Info
  static const String appName = 'Pharmacy Attendance';
  static const String appVersion = '2.0.0';
  static const String appBuildNumber = '1';
  
  // Database
  static const String databaseName = 'pharmacy_attendance.db';
  static const int databaseVersion = 5; // v5: Added sync_queue for cloud migration
  
  // Subscription/Trial
  static const int trialPeriodDays = 30;
  
  // QR Code
  static const int qrRefreshSeconds = 30;
  
  // Attendance
  static const int defaultGracePeriodMinutes = 15;
  static const int attendanceWindowMinutes = 120; // 2 hours before/after shift
  
  // Anti-fraud
  static const int duplicateScanProtectionSeconds = 60;
  static const int maxFailedScansAlert = 3;
  
  // Payroll
  static const double defaultOvertimeMultiplier = 1.5;
  static const double weekendOvertimeMultiplier = 2.0;
  
  // Reports
  static const int defaultPaginationLimit = 50;
  
  // Date/Time formats
  static const String dateFormat = 'yyyy-MM-dd';
  static const String timeFormat = 'HH:mm';
  static const String dateTimeFormat = 'yyyy-MM-dd HH:mm:ss';
  static const String displayDateFormat = 'dd MMM yyyy';
  static const String displayTimeFormat = 'hh:mm a';
  static const String displayDateTimeFormat = 'dd MMM yyyy, hh:mm a';
  
  // UI
  static const double cardElevation = 2.0;
  static const double borderRadius = 12.0;
  static const double defaultPadding = 16.0;
  
  // Validation
  static const int minPasswordLength = 6;
  static const int maxEmployeeCodeLength = 20;
  static const int maxBarcodeLength = 50;
}

/// Salary types enum
enum SalaryType {
  monthly,
  hourly,
  perShift,
}

extension SalaryTypeExtension on SalaryType {
  String get displayName {
    switch (this) {
      case SalaryType.monthly:
        return 'Monthly';
      case SalaryType.hourly:
        return 'Hourly';
      case SalaryType.perShift:
        return 'Per Shift';
    }
  }
  
  String get value {
    switch (this) {
      case SalaryType.monthly:
        return 'monthly';
      case SalaryType.hourly:
        return 'hourly';
      case SalaryType.perShift:
        return 'per_shift';
    }
  }
  
  static SalaryType fromString(String value) {
    switch (value) {
      case 'monthly':
        return SalaryType.monthly;
      case 'hourly':
        return SalaryType.hourly;
      case 'per_shift':
        return SalaryType.perShift;
      default:
        return SalaryType.monthly;
    }
  }
}

/// Employee status enum
enum EmployeeStatus {
  active,
  inactive,
  suspended,
  terminated,
}

extension EmployeeStatusExtension on EmployeeStatus {
  String get displayName {
    switch (this) {
      case EmployeeStatus.active:
        return 'Active';
      case EmployeeStatus.inactive:
        return 'Inactive';
      case EmployeeStatus.suspended:
        return 'Suspended';
      case EmployeeStatus.terminated:
        return 'Terminated';
    }
  }
  
  String get value {
    switch (this) {
      case EmployeeStatus.active:
        return 'active';
      case EmployeeStatus.inactive:
        return 'inactive';
      case EmployeeStatus.suspended:
        return 'suspended';
      case EmployeeStatus.terminated:
        return 'terminated';
    }
  }
  
  static EmployeeStatus fromString(String value) {
    switch (value) {
      case 'active':
        return EmployeeStatus.active;
      case 'inactive':
        return EmployeeStatus.inactive;
      case 'suspended':
        return EmployeeStatus.suspended;
      case 'terminated':
        return EmployeeStatus.terminated;
      default:
        return EmployeeStatus.active;
    }
  }
}

/// Attendance status enum
enum AttendanceStatus {
  present,
  absent,
  late,
  earlyLeave,
  halfDay,
  onLeave,
  holiday,
}

extension AttendanceStatusExtension on AttendanceStatus {
  String get displayName {
    switch (this) {
      case AttendanceStatus.present:
        return 'Present';
      case AttendanceStatus.absent:
        return 'Absent';
      case AttendanceStatus.late:
        return 'Late';
      case AttendanceStatus.earlyLeave:
        return 'Early Leave';
      case AttendanceStatus.halfDay:
        return 'Half Day';
      case AttendanceStatus.onLeave:
        return 'On Leave';
      case AttendanceStatus.holiday:
        return 'Holiday';
    }
  }
  
  String get value {
    switch (this) {
      case AttendanceStatus.present:
        return 'present';
      case AttendanceStatus.absent:
        return 'absent';
      case AttendanceStatus.late:
        return 'late';
      case AttendanceStatus.earlyLeave:
        return 'early_leave';
      case AttendanceStatus.halfDay:
        return 'half_day';
      case AttendanceStatus.onLeave:
        return 'on_leave';
      case AttendanceStatus.holiday:
        return 'holiday';
    }
  }
  
  static AttendanceStatus fromString(String value) {
    switch (value) {
      case 'present':
        return AttendanceStatus.present;
      case 'absent':
        return AttendanceStatus.absent;
      case 'late':
        return AttendanceStatus.late;
      case 'early_leave':
        return AttendanceStatus.earlyLeave;
      case 'half_day':
        return AttendanceStatus.halfDay;
      case 'on_leave':
        return AttendanceStatus.onLeave;
      case 'holiday':
        return AttendanceStatus.holiday;
      default:
        return AttendanceStatus.present;
    }
  }
}

/// User role enum
enum UserRole {
  superAdmin,
  admin,
  manager,
  employee,
}

extension UserRoleExtension on UserRole {
  String get displayName {
    switch (this) {
      case UserRole.superAdmin:
        return 'Super Admin';
      case UserRole.admin:
        return 'Admin';
      case UserRole.manager:
        return 'Manager';
      case UserRole.employee:
        return 'Employee';
    }
  }
  
  String get value {
    switch (this) {
      case UserRole.superAdmin:
        return 'super_admin';
      case UserRole.admin:
        return 'admin';
      case UserRole.manager:
        return 'manager';
      case UserRole.employee:
        return 'employee';
    }
  }
  
  static UserRole fromString(String value) {
    switch (value) {
      case 'super_admin':
        return UserRole.superAdmin;
      case 'admin':
        return UserRole.admin;
      case 'manager':
        return UserRole.manager;
      case 'employee':
        return UserRole.employee;
      default:
        return UserRole.employee;
    }
  }
  
  bool get canManageEmployees {
    return this == UserRole.superAdmin || this == UserRole.admin || this == UserRole.manager;
  }
  
  bool get canManageShifts {
    return this == UserRole.superAdmin || this == UserRole.admin;
  }
  
  bool get canApproveOverrides {
    return this == UserRole.superAdmin || this == UserRole.admin || this == UserRole.manager;
  }
  
  bool get canViewReports {
    return this == UserRole.superAdmin || this == UserRole.admin || this == UserRole.manager;
  }
  
  bool get canManageSettings {
    return this == UserRole.superAdmin || this == UserRole.admin;
  }
  
  bool get canManageBranches {
    return this == UserRole.superAdmin;
  }
}

/// Attendance method enum
enum AttendanceMethod {
  manual,
  barcode,
  qrCode,
  fingerprint,
  nfc,
  faceRecognition,
}

extension AttendanceMethodExtension on AttendanceMethod {
  String get displayName {
    switch (this) {
      case AttendanceMethod.manual:
        return 'Manual Entry';
      case AttendanceMethod.barcode:
        return 'Barcode Scanner';
      case AttendanceMethod.qrCode:
        return 'QR Code';
      case AttendanceMethod.fingerprint:
        return 'Fingerprint';
      case AttendanceMethod.nfc:
        return 'NFC';
      case AttendanceMethod.faceRecognition:
        return 'Face Recognition';
    }
  }
  
  String get value {
    switch (this) {
      case AttendanceMethod.manual:
        return 'manual';
      case AttendanceMethod.barcode:
        return 'barcode';
      case AttendanceMethod.qrCode:
        return 'qr_code';
      case AttendanceMethod.fingerprint:
        return 'fingerprint';
      case AttendanceMethod.nfc:
        return 'nfc';
      case AttendanceMethod.faceRecognition:
        return 'face_recognition';
    }
  }
  
  static AttendanceMethod fromString(String value) {
    switch (value) {
      case 'manual':
        return AttendanceMethod.manual;
      case 'barcode':
        return AttendanceMethod.barcode;
      case 'qr_code':
        return AttendanceMethod.qrCode;
      case 'fingerprint':
        return AttendanceMethod.fingerprint;
      case 'nfc':
        return AttendanceMethod.nfc;
      case 'face_recognition':
        return AttendanceMethod.faceRecognition;
      default:
        return AttendanceMethod.manual;
    }
  }
}

/// License type enum
enum LicenseType {
  trial,
  lifetime,
  subscription,
}

extension LicenseTypeExtension on LicenseType {
  String get displayName {
    switch (this) {
      case LicenseType.trial:
        return 'Trial';
      case LicenseType.lifetime:
        return 'Lifetime';
      case LicenseType.subscription:
        return 'Subscription';
    }
  }
  
  String get value {
    switch (this) {
      case LicenseType.trial:
        return 'trial';
      case LicenseType.lifetime:
        return 'lifetime';
      case LicenseType.subscription:
        return 'subscription';
    }
  }
  
  static LicenseType fromString(String value) {
    switch (value) {
      case 'trial':
        return LicenseType.trial;
      case 'lifetime':
        return LicenseType.lifetime;
      case 'subscription':
        return LicenseType.subscription;
      default:
        return LicenseType.trial;
    }
  }
}

// ============================================================================
// FINANCIAL MANAGEMENT ENUMS
// ============================================================================

/// Financial shift status
enum FinancialShiftStatus {
  open,
  closed,
  pending,
}

extension FinancialShiftStatusExtension on FinancialShiftStatus {
  String get displayName {
    switch (this) {
      case FinancialShiftStatus.open:
        return 'Open';
      case FinancialShiftStatus.closed:
        return 'Closed';
      case FinancialShiftStatus.pending:
        return 'Pending Review';
    }
  }
  
  String get value {
    switch (this) {
      case FinancialShiftStatus.open:
        return 'open';
      case FinancialShiftStatus.closed:
        return 'closed';
      case FinancialShiftStatus.pending:
        return 'pending';
    }
  }
  
  static FinancialShiftStatus fromString(String value) {
    switch (value) {
      case 'open':
        return FinancialShiftStatus.open;
      case 'closed':
        return FinancialShiftStatus.closed;
      case 'pending':
        return FinancialShiftStatus.pending;
      default:
        return FinancialShiftStatus.open;
    }
  }
}

/// Payment method for sales
enum PaymentMethod {
  cash,
  visa,
  wallet,
  insurance,
  credit,
}

extension PaymentMethodExtension on PaymentMethod {
  String get displayName {
    switch (this) {
      case PaymentMethod.cash:
        return 'Cash';
      case PaymentMethod.visa:
        return 'Visa/Card';
      case PaymentMethod.wallet:
        return 'E-Wallet';
      case PaymentMethod.insurance:
        return 'Insurance';
      case PaymentMethod.credit:
        return 'Credit/Deferred';
    }
  }
  
  String get value {
    switch (this) {
      case PaymentMethod.cash:
        return 'cash';
      case PaymentMethod.visa:
        return 'visa';
      case PaymentMethod.wallet:
        return 'wallet';
      case PaymentMethod.insurance:
        return 'insurance';
      case PaymentMethod.credit:
        return 'credit';
    }
  }
  
  static PaymentMethod fromString(String value) {
    switch (value) {
      case 'cash':
        return PaymentMethod.cash;
      case 'visa':
        return PaymentMethod.visa;
      case 'wallet':
        return PaymentMethod.wallet;
      case 'insurance':
        return PaymentMethod.insurance;
      case 'credit':
        return PaymentMethod.credit;
      default:
        return PaymentMethod.cash;
    }
  }
}

/// Expense category
enum ExpenseCategory {
  utilities,
  shortage,
  emergency,
  supplies,
  maintenance,
  transportation,
  misc,
}

extension ExpenseCategoryExtension on ExpenseCategory {
  String get displayName {
    switch (this) {
      case ExpenseCategory.utilities:
        return 'Utilities';
      case ExpenseCategory.shortage:
        return 'Shortage/Deficit';
      case ExpenseCategory.emergency:
        return 'Emergency';
      case ExpenseCategory.supplies:
        return 'Supplies';
      case ExpenseCategory.maintenance:
        return 'Maintenance';
      case ExpenseCategory.transportation:
        return 'Transportation';
      case ExpenseCategory.misc:
        return 'Miscellaneous';
    }
  }
  
  String get value {
    switch (this) {
      case ExpenseCategory.utilities:
        return 'utilities';
      case ExpenseCategory.shortage:
        return 'shortage';
      case ExpenseCategory.emergency:
        return 'emergency';
      case ExpenseCategory.supplies:
        return 'supplies';
      case ExpenseCategory.maintenance:
        return 'maintenance';
      case ExpenseCategory.transportation:
        return 'transportation';
      case ExpenseCategory.misc:
        return 'misc';
    }
  }
  
  static ExpenseCategory fromString(String value) {
    switch (value) {
      case 'utilities':
        return ExpenseCategory.utilities;
      case 'shortage':
        return ExpenseCategory.shortage;
      case 'emergency':
        return ExpenseCategory.emergency;
      case 'supplies':
        return ExpenseCategory.supplies;
      case 'maintenance':
        return ExpenseCategory.maintenance;
      case 'transportation':
        return ExpenseCategory.transportation;
      case 'misc':
        return ExpenseCategory.misc;
      default:
        return ExpenseCategory.misc;
    }
  }
}

/// Supplier transaction type
enum SupplierTransactionType {
  purchase,
  payment,
  refund,
  adjustment,
}

extension SupplierTransactionTypeExtension on SupplierTransactionType {
  String get displayName {
    switch (this) {
      case SupplierTransactionType.purchase:
        return 'Purchase';
      case SupplierTransactionType.payment:
        return 'Payment';
      case SupplierTransactionType.refund:
        return 'Refund';
      case SupplierTransactionType.adjustment:
        return 'Adjustment';
    }
  }
  
  String get value {
    switch (this) {
      case SupplierTransactionType.purchase:
        return 'purchase';
      case SupplierTransactionType.payment:
        return 'payment';
      case SupplierTransactionType.refund:
        return 'refund';
      case SupplierTransactionType.adjustment:
        return 'adjustment';
    }
  }
  
  static SupplierTransactionType fromString(String value) {
    switch (value) {
      case 'purchase':
        return SupplierTransactionType.purchase;
      case 'payment':
        return SupplierTransactionType.payment;
      case 'refund':
        return SupplierTransactionType.refund;
      case 'adjustment':
        return SupplierTransactionType.adjustment;
      default:
        return SupplierTransactionType.purchase;
    }
  }
  
  /// Returns true if this transaction increases supplier balance (we owe them)
  bool get increasesBalance {
    return this == SupplierTransactionType.purchase;
  }
  
  /// Returns true if this transaction decreases supplier balance (we paid them)
  bool get decreasesBalance {
    return this == SupplierTransactionType.payment || 
           this == SupplierTransactionType.refund;
  }
}
