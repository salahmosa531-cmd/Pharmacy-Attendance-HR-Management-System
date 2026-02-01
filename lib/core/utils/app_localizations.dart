import 'package:flutter/material.dart';

/// Application localization support
class AppLocalizations {
  final Locale locale;
  
  AppLocalizations(this.locale);
  
  static AppLocalizations? of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations);
  }
  
  static const LocalizationsDelegate<AppLocalizations> delegate = _AppLocalizationsDelegate();
  
  static final Map<String, Map<String, String>> _localizedValues = {
    'en': {
      // App
      'app_name': 'Pharmacy Attendance',
      'app_subtitle': 'HR Management System',
      
      // Auth
      'login': 'Login',
      'logout': 'Logout',
      'username': 'Username',
      'password': 'Password',
      'confirm_password': 'Confirm Password',
      'change_password': 'Change Password',
      'current_password': 'Current Password',
      'new_password': 'New Password',
      'forgot_password': 'Forgot Password?',
      'remember_me': 'Remember Me',
      'invalid_credentials': 'Invalid username or password',
      'account_deactivated': 'Account is deactivated',
      
      // Navigation
      'dashboard': 'Dashboard',
      'attendance': 'Attendance',
      'employees': 'Employees',
      'shifts': 'Shifts',
      'reports': 'Reports',
      'payroll': 'Payroll',
      'settings': 'Settings',
      'enterprise': 'Enterprise',
      'branches': 'Branches',
      'audit_log': 'Audit Log',
      
      // Dashboard
      'today_overview': 'Today\'s Overview',
      'currently_working': 'Currently Working',
      'late_today': 'Late Today',
      'absent_today': 'Absent Today',
      'on_leave': 'On Leave',
      'total_employees': 'Total Employees',
      'attendance_rate': 'Attendance Rate',
      'recent_activity': 'Recent Activity',
      'quick_actions': 'Quick Actions',
      
      // Attendance
      'clock_in': 'Clock In',
      'clock_out': 'Clock Out',
      'scan_barcode': 'Scan Barcode',
      'scan_qr': 'Scan QR Code',
      'enter_code': 'Enter Employee Code',
      'fingerprint': 'Fingerprint',
      'select_method': 'Select Attendance Method',
      'attendance_recorded': 'Attendance recorded successfully',
      'already_clocked_in': 'Already clocked in today',
      'not_clocked_in': 'Not clocked in today',
      'already_clocked_out': 'Already clocked out today',
      'employee_not_found': 'Employee not found',
      'late_minutes': 'Late by {minutes} minutes',
      'early_leave': 'Left early by {minutes} minutes',
      'worked_hours': 'Worked: {hours}',
      'overtime': 'Overtime: {hours}',
      
      // Employees
      'add_employee': 'Add Employee',
      'edit_employee': 'Edit Employee',
      'delete_employee': 'Delete Employee',
      'employee_details': 'Employee Details',
      'employee_code': 'Employee Code',
      'full_name': 'Full Name',
      'job_title': 'Job Title',
      'email': 'Email',
      'phone': 'Phone',
      'barcode': 'Barcode',
      'fingerprint_id': 'Fingerprint ID',
      'assigned_shift': 'Assigned Shift',
      'salary_type': 'Salary Type',
      'salary_value': 'Salary Amount',
      'status': 'Status',
      'hire_date': 'Hire Date',
      'active': 'Active',
      'inactive': 'Inactive',
      'suspended': 'Suspended',
      'terminated': 'Terminated',
      'monthly': 'Monthly',
      'hourly': 'Hourly',
      'per_shift': 'Per Shift',
      
      // Shifts
      'add_shift': 'Add Shift',
      'edit_shift': 'Edit Shift',
      'delete_shift': 'Delete Shift',
      'shift_name': 'Shift Name',
      'start_time': 'Start Time',
      'end_time': 'End Time',
      'grace_period': 'Grace Period (minutes)',
      'cross_midnight': 'Crosses Midnight',
      'shift_color': 'Shift Color',
      
      // Reports
      'generate_report': 'Generate Report',
      'daily_report': 'Daily Report',
      'weekly_report': 'Weekly Report',
      'monthly_report': 'Monthly Report',
      'employee_report': 'Employee Report',
      'shift_report': 'Shift Report',
      'salary_report': 'Salary Report',
      'export_pdf': 'Export PDF',
      'export_excel': 'Export Excel',
      'print_report': 'Print Report',
      'select_date_range': 'Select Date Range',
      'from_date': 'From Date',
      'to_date': 'To Date',
      
      // Payroll
      'generate_payroll': 'Generate Payroll',
      'payroll_period': 'Payroll Period',
      'base_salary': 'Base Salary',
      'overtime_pay': 'Overtime Pay',
      'deductions': 'Deductions',
      'bonus': 'Bonus',
      'net_salary': 'Net Salary',
      'mark_as_paid': 'Mark as Paid',
      'pending': 'Pending',
      'approved': 'Approved',
      'paid': 'Paid',
      
      // Settings
      'general_settings': 'General Settings',
      'attendance_settings': 'Attendance Settings',
      'payroll_settings': 'Payroll Settings',
      'notification_settings': 'Notifications',
      'backup_restore': 'Backup & Restore',
      'device_management': 'Device Management',
      'language': 'Language',
      'theme': 'Theme',
      'light_theme': 'Light',
      'dark_theme': 'Dark',
      'system_theme': 'System',
      'auto_clock_out': 'Auto Clock Out',
      'overtime_rules': 'Overtime Rules',
      'deduction_rules': 'Deduction Rules',
      
      // Enterprise
      'branch_management': 'Branch Management',
      'add_branch': 'Add Branch',
      'edit_branch': 'Edit Branch',
      'branch_name': 'Branch Name',
      'branch_address': 'Address',
      'main_branch': 'Main Branch',
      'cross_branch_reports': 'Cross-Branch Reports',
      
      // Actions
      'save': 'Save',
      'cancel': 'Cancel',
      'delete': 'Delete',
      'edit': 'Edit',
      'add': 'Add',
      'search': 'Search',
      'filter': 'Filter',
      'refresh': 'Refresh',
      'export': 'Export',
      'import': 'Import',
      'print': 'Print',
      'confirm': 'Confirm',
      'close': 'Close',
      'back': 'Back',
      'next': 'Next',
      'submit': 'Submit',
      'apply': 'Apply',
      'reset': 'Reset',
      
      // Messages
      'success': 'Success',
      'error': 'Error',
      'warning': 'Warning',
      'info': 'Information',
      'loading': 'Loading...',
      'no_data': 'No data available',
      'confirm_delete': 'Are you sure you want to delete this item?',
      'unsaved_changes': 'You have unsaved changes. Do you want to discard them?',
      'required_field': 'This field is required',
      'invalid_email': 'Please enter a valid email',
      'invalid_phone': 'Please enter a valid phone number',
      'password_mismatch': 'Passwords do not match',
      'password_too_short': 'Password must be at least {length} characters',
      
      // Time
      'today': 'Today',
      'yesterday': 'Yesterday',
      'this_week': 'This Week',
      'this_month': 'This Month',
      'last_month': 'Last Month',
      'custom_range': 'Custom Range',
      
      // Manager controls
      'forgive_lateness': 'Forgive Lateness',
      'manual_override': 'Manual Override',
      'override_reason': 'Override Reason',
      'requires_password': 'Please enter your password to confirm',
      
      // License
      'license': 'License',
      'trial_version': 'Trial Version',
      'days_remaining': '{days} days remaining',
      'activate_license': 'Activate License',
      'license_key': 'License Key',
      'lifetime_license': 'Lifetime License',
      'trial_expired': 'Trial period has expired',
    },
    'ar': {
      // App
      'app_name': 'حضور الصيدلية',
      'app_subtitle': 'نظام إدارة الموارد البشرية',
      
      // Auth
      'login': 'تسجيل الدخول',
      'logout': 'تسجيل الخروج',
      'username': 'اسم المستخدم',
      'password': 'كلمة المرور',
      'confirm_password': 'تأكيد كلمة المرور',
      'change_password': 'تغيير كلمة المرور',
      'current_password': 'كلمة المرور الحالية',
      'new_password': 'كلمة المرور الجديدة',
      'forgot_password': 'نسيت كلمة المرور؟',
      'remember_me': 'تذكرني',
      'invalid_credentials': 'اسم المستخدم أو كلمة المرور غير صحيحة',
      'account_deactivated': 'الحساب معطل',
      
      // Navigation
      'dashboard': 'لوحة التحكم',
      'attendance': 'الحضور',
      'employees': 'الموظفون',
      'shifts': 'الورديات',
      'reports': 'التقارير',
      'payroll': 'الرواتب',
      'settings': 'الإعدادات',
      'enterprise': 'المؤسسة',
      'branches': 'الفروع',
      'audit_log': 'سجل المراجعة',
      
      // Dashboard
      'today_overview': 'نظرة عامة اليوم',
      'currently_working': 'يعملون حالياً',
      'late_today': 'متأخرون اليوم',
      'absent_today': 'غائبون اليوم',
      'on_leave': 'في إجازة',
      'total_employees': 'إجمالي الموظفين',
      'attendance_rate': 'نسبة الحضور',
      'recent_activity': 'النشاط الأخير',
      'quick_actions': 'إجراءات سريعة',
      
      // Attendance
      'clock_in': 'تسجيل الحضور',
      'clock_out': 'تسجيل الانصراف',
      'scan_barcode': 'مسح الباركود',
      'scan_qr': 'مسح رمز QR',
      'enter_code': 'أدخل رمز الموظف',
      'fingerprint': 'البصمة',
      'select_method': 'اختر طريقة الحضور',
      'attendance_recorded': 'تم تسجيل الحضور بنجاح',
      'already_clocked_in': 'تم تسجيل الحضور مسبقاً اليوم',
      'not_clocked_in': 'لم يتم تسجيل الحضور اليوم',
      'already_clocked_out': 'تم تسجيل الانصراف مسبقاً اليوم',
      'employee_not_found': 'الموظف غير موجود',
      'late_minutes': 'متأخر {minutes} دقيقة',
      'early_leave': 'غادر مبكراً {minutes} دقيقة',
      'worked_hours': 'العمل: {hours}',
      'overtime': 'إضافي: {hours}',
      
      // Employees
      'add_employee': 'إضافة موظف',
      'edit_employee': 'تعديل موظف',
      'delete_employee': 'حذف موظف',
      'employee_details': 'تفاصيل الموظف',
      'employee_code': 'رمز الموظف',
      'full_name': 'الاسم الكامل',
      'job_title': 'المسمى الوظيفي',
      'email': 'البريد الإلكتروني',
      'phone': 'الهاتف',
      'barcode': 'الباركود',
      'fingerprint_id': 'رقم البصمة',
      'assigned_shift': 'الوردية المعينة',
      'salary_type': 'نوع الراتب',
      'salary_value': 'قيمة الراتب',
      'status': 'الحالة',
      'hire_date': 'تاريخ التعيين',
      'active': 'نشط',
      'inactive': 'غير نشط',
      'suspended': 'موقوف',
      'terminated': 'منتهي',
      'monthly': 'شهري',
      'hourly': 'بالساعة',
      'per_shift': 'لكل وردية',
      
      // Shifts
      'add_shift': 'إضافة وردية',
      'edit_shift': 'تعديل وردية',
      'delete_shift': 'حذف وردية',
      'shift_name': 'اسم الوردية',
      'start_time': 'وقت البداية',
      'end_time': 'وقت النهاية',
      'grace_period': 'فترة السماح (دقائق)',
      'cross_midnight': 'تمتد لليوم التالي',
      'shift_color': 'لون الوردية',
      
      // Reports
      'generate_report': 'إنشاء تقرير',
      'daily_report': 'تقرير يومي',
      'weekly_report': 'تقرير أسبوعي',
      'monthly_report': 'تقرير شهري',
      'employee_report': 'تقرير الموظف',
      'shift_report': 'تقرير الوردية',
      'salary_report': 'تقرير الرواتب',
      'export_pdf': 'تصدير PDF',
      'export_excel': 'تصدير Excel',
      'print_report': 'طباعة التقرير',
      'select_date_range': 'اختر نطاق التاريخ',
      'from_date': 'من تاريخ',
      'to_date': 'إلى تاريخ',
      
      // Payroll
      'generate_payroll': 'إنشاء كشف الرواتب',
      'payroll_period': 'فترة الرواتب',
      'base_salary': 'الراتب الأساسي',
      'overtime_pay': 'أجر العمل الإضافي',
      'deductions': 'الخصومات',
      'bonus': 'المكافأة',
      'net_salary': 'صافي الراتب',
      'mark_as_paid': 'تحديد كمدفوع',
      'pending': 'قيد الانتظار',
      'approved': 'موافق عليه',
      'paid': 'مدفوع',
      
      // Settings
      'general_settings': 'الإعدادات العامة',
      'attendance_settings': 'إعدادات الحضور',
      'payroll_settings': 'إعدادات الرواتب',
      'notification_settings': 'الإشعارات',
      'backup_restore': 'النسخ الاحتياطي والاستعادة',
      'device_management': 'إدارة الأجهزة',
      'language': 'اللغة',
      'theme': 'المظهر',
      'light_theme': 'فاتح',
      'dark_theme': 'داكن',
      'system_theme': 'النظام',
      'auto_clock_out': 'الانصراف التلقائي',
      'overtime_rules': 'قواعد العمل الإضافي',
      'deduction_rules': 'قواعد الخصم',
      
      // Enterprise
      'branch_management': 'إدارة الفروع',
      'add_branch': 'إضافة فرع',
      'edit_branch': 'تعديل فرع',
      'branch_name': 'اسم الفرع',
      'branch_address': 'العنوان',
      'main_branch': 'الفرع الرئيسي',
      'cross_branch_reports': 'تقارير عبر الفروع',
      
      // Actions
      'save': 'حفظ',
      'cancel': 'إلغاء',
      'delete': 'حذف',
      'edit': 'تعديل',
      'add': 'إضافة',
      'search': 'بحث',
      'filter': 'تصفية',
      'refresh': 'تحديث',
      'export': 'تصدير',
      'import': 'استيراد',
      'print': 'طباعة',
      'confirm': 'تأكيد',
      'close': 'إغلاق',
      'back': 'رجوع',
      'next': 'التالي',
      'submit': 'إرسال',
      'apply': 'تطبيق',
      'reset': 'إعادة تعيين',
      
      // Messages
      'success': 'نجاح',
      'error': 'خطأ',
      'warning': 'تحذير',
      'info': 'معلومات',
      'loading': 'جار التحميل...',
      'no_data': 'لا توجد بيانات',
      'confirm_delete': 'هل أنت متأكد من حذف هذا العنصر؟',
      'unsaved_changes': 'لديك تغييرات غير محفوظة. هل تريد تجاهلها؟',
      'required_field': 'هذا الحقل مطلوب',
      'invalid_email': 'الرجاء إدخال بريد إلكتروني صحيح',
      'invalid_phone': 'الرجاء إدخال رقم هاتف صحيح',
      'password_mismatch': 'كلمات المرور غير متطابقة',
      'password_too_short': 'يجب أن تكون كلمة المرور {length} أحرف على الأقل',
      
      // Time
      'today': 'اليوم',
      'yesterday': 'أمس',
      'this_week': 'هذا الأسبوع',
      'this_month': 'هذا الشهر',
      'last_month': 'الشهر الماضي',
      'custom_range': 'نطاق مخصص',
      
      // Manager controls
      'forgive_lateness': 'العفو عن التأخير',
      'manual_override': 'تجاوز يدوي',
      'override_reason': 'سبب التجاوز',
      'requires_password': 'الرجاء إدخال كلمة المرور للتأكيد',
      
      // License
      'license': 'الترخيص',
      'trial_version': 'نسخة تجريبية',
      'days_remaining': 'متبقي {days} يوم',
      'activate_license': 'تفعيل الترخيص',
      'license_key': 'مفتاح الترخيص',
      'lifetime_license': 'ترخيص مدى الحياة',
      'trial_expired': 'انتهت الفترة التجريبية',
    },
  };
  
  /// Get localized string
  String translate(String key) {
    final languageCode = locale.languageCode;
    return _localizedValues[languageCode]?[key] ?? 
           _localizedValues['en']?[key] ?? 
           key;
  }
  
  /// Get localized string with parameters
  String translateWithParams(String key, Map<String, String> params) {
    var value = translate(key);
    params.forEach((paramKey, paramValue) {
      value = value.replaceAll('{$paramKey}', paramValue);
    });
    return value;
  }
  
  /// Check if current locale is RTL
  bool get isRtl => locale.languageCode == 'ar';
}

class _AppLocalizationsDelegate extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();
  
  @override
  bool isSupported(Locale locale) {
    return ['en', 'ar'].contains(locale.languageCode);
  }
  
  @override
  Future<AppLocalizations> load(Locale locale) async {
    return AppLocalizations(locale);
  }
  
  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

/// Extension for easy access to localization
extension LocalizationExtension on BuildContext {
  AppLocalizations? get l10n => AppLocalizations.of(this);
  
  String tr(String key) => l10n?.translate(key) ?? key;
  
  String trParams(String key, Map<String, String> params) =>
      l10n?.translateWithParams(key, params) ?? key;
  
  bool get isRtl => l10n?.isRtl ?? false;
}
