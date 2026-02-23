import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import '../constants/app_constants.dart';

/// Database service for SQLite operations
/// 
/// Implements safe production migrations that:
/// - Check column existence before ALTER TABLE
/// - Log all migration steps
/// - Never run redundant migrations
class DatabaseService {
  static DatabaseService? _instance;
  static Database? _database;
  
  // Migration log for debugging
  static final List<String> _migrationLog = [];
  
  DatabaseService._();
  
  static DatabaseService get instance {
    _instance ??= DatabaseService._();
    return _instance!;
  }
  
  /// Get migration log for debugging
  static List<String> get migrationLog => List.unmodifiable(_migrationLog);
  
  /// Clear migration log
  static void clearMigrationLog() => _migrationLog.clear();
  
  /// Initialize the database factory for desktop platforms
  static void initializeFfi() {
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    }
  }
  
  /// Get database instance
  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }
  
  /// Initialize database
  Future<Database> _initDatabase() async {
    final Directory appDocDir = await getApplicationDocumentsDirectory();
    final String dbPath = p.join(appDocDir.path, 'PharmacyAttendance', AppConstants.databaseName);
    
    // Ensure directory exists
    final Directory dbDir = Directory(p.dirname(dbPath));
    if (!await dbDir.exists()) {
      await dbDir.create(recursive: true);
    }
    
    return await openDatabase(
      dbPath,
      version: AppConstants.databaseVersion,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
      onConfigure: _onConfigure,
    );
  }
  
  /// Configure database
  Future<void> _onConfigure(Database db) async {
    await db.execute('PRAGMA foreign_keys = ON');
  }
  
  /// Create database tables
  Future<void> _onCreate(Database db, int version) async {
    final batch = db.batch();
    
    // Branches/Pharmacies table (for multi-pharmacy support)
    batch.execute('''
      CREATE TABLE branches (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        address TEXT,
        phone TEXT,
        email TEXT,
        is_main_branch INTEGER DEFAULT 0,
        owner_id TEXT,
        device_id TEXT,
        location_lat REAL,
        location_lng REAL,
        location_radius REAL DEFAULT 100,
        is_active INTEGER DEFAULT 1,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        synced_at TEXT,
        UNIQUE(device_id)
      )
    ''');
    
    // Users table (for login/authentication)
    batch.execute('''
      CREATE TABLE users (
        id TEXT PRIMARY KEY,
        username TEXT NOT NULL UNIQUE,
        password_hash TEXT NOT NULL,
        salt TEXT NOT NULL,
        role TEXT NOT NULL DEFAULT 'employee',
        employee_id TEXT,
        branch_id TEXT,
        is_active INTEGER DEFAULT 1,
        last_login TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        synced_at TEXT,
        FOREIGN KEY (employee_id) REFERENCES employees(id) ON DELETE SET NULL,
        FOREIGN KEY (branch_id) REFERENCES branches(id) ON DELETE SET NULL
      )
    ''');
    
    // Shifts table
    batch.execute('''
      CREATE TABLE shifts (
        id TEXT PRIMARY KEY,
        branch_id TEXT NOT NULL,
        name TEXT NOT NULL,
        start_time TEXT NOT NULL,
        end_time TEXT NOT NULL,
        grace_period_minutes INTEGER DEFAULT 15,
        is_cross_midnight INTEGER DEFAULT 0,
        is_active INTEGER DEFAULT 1,
        color TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        synced_at TEXT,
        FOREIGN KEY (branch_id) REFERENCES branches(id) ON DELETE CASCADE
      )
    ''');
    
    // Employees table
    batch.execute('''
      CREATE TABLE employees (
        id TEXT PRIMARY KEY,
        branch_id TEXT NOT NULL,
        employee_code TEXT NOT NULL,
        full_name TEXT NOT NULL,
        job_title TEXT,
        email TEXT,
        phone TEXT,
        barcode_serial TEXT,
        fingerprint_id TEXT,
        assigned_shift_id TEXT,
        salary_type TEXT NOT NULL DEFAULT 'monthly',
        salary_value REAL DEFAULT 0,
        overtime_rate REAL,
        status TEXT NOT NULL DEFAULT 'active',
        hire_date TEXT,
        termination_date TEXT,
        photo_path TEXT,
        notes TEXT,
        attendance_score REAL DEFAULT 100,
        is_active INTEGER DEFAULT 1,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        synced_at TEXT,
        FOREIGN KEY (branch_id) REFERENCES branches(id) ON DELETE CASCADE,
        FOREIGN KEY (assigned_shift_id) REFERENCES shifts(id) ON DELETE SET NULL,
        UNIQUE(branch_id, employee_code),
        UNIQUE(branch_id, barcode_serial)
      )
    ''');
    
    // Employee shift assignments (for daily overrides)
    batch.execute('''
      CREATE TABLE employee_shift_assignments (
        id TEXT PRIMARY KEY,
        employee_id TEXT NOT NULL,
        shift_id TEXT NOT NULL,
        date TEXT NOT NULL,
        is_override INTEGER DEFAULT 0,
        created_by TEXT,
        created_at TEXT NOT NULL,
        synced_at TEXT,
        FOREIGN KEY (employee_id) REFERENCES employees(id) ON DELETE CASCADE,
        FOREIGN KEY (shift_id) REFERENCES shifts(id) ON DELETE CASCADE,
        FOREIGN KEY (created_by) REFERENCES users(id) ON DELETE SET NULL,
        UNIQUE(employee_id, date)
      )
    ''');
    
    // Attendance records table
    batch.execute('''
      CREATE TABLE attendance_records (
        id TEXT PRIMARY KEY,
        employee_id TEXT NOT NULL,
        branch_id TEXT NOT NULL,
        shift_id TEXT,
        date TEXT NOT NULL,
        clock_in_time TEXT,
        clock_out_time TEXT,
        clock_in_method TEXT,
        clock_out_method TEXT,
        clock_in_device_id TEXT,
        clock_out_device_id TEXT,
        scheduled_start TEXT,
        scheduled_end TEXT,
        late_minutes INTEGER DEFAULT 0,
        early_leave_minutes INTEGER DEFAULT 0,
        worked_minutes INTEGER DEFAULT 0,
        overtime_minutes INTEGER DEFAULT 0,
        break_minutes INTEGER DEFAULT 0,
        status TEXT NOT NULL DEFAULT 'present',
        is_late_forgiven INTEGER DEFAULT 0,
        late_forgiveness_reason TEXT,
        late_forgiven_by TEXT,
        late_forgiven_at TEXT,
        is_manually_modified INTEGER DEFAULT 0,
        modified_by TEXT,
        modified_at TEXT,
        modification_reason TEXT,
        notes TEXT,
        qr_token TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        synced_at TEXT,
        FOREIGN KEY (employee_id) REFERENCES employees(id) ON DELETE CASCADE,
        FOREIGN KEY (branch_id) REFERENCES branches(id) ON DELETE CASCADE,
        FOREIGN KEY (shift_id) REFERENCES shifts(id) ON DELETE SET NULL,
        FOREIGN KEY (late_forgiven_by) REFERENCES users(id) ON DELETE SET NULL,
        FOREIGN KEY (modified_by) REFERENCES users(id) ON DELETE SET NULL,
        UNIQUE(employee_id, date)
      )
    ''');
    
    // Audit log table
    batch.execute('''
      CREATE TABLE audit_logs (
        id TEXT PRIMARY KEY,
        branch_id TEXT,
        user_id TEXT,
        action TEXT NOT NULL,
        entity_type TEXT NOT NULL,
        entity_id TEXT,
        old_values TEXT,
        new_values TEXT,
        description TEXT,
        ip_address TEXT,
        device_id TEXT,
        timestamp TEXT NOT NULL,
        synced_at TEXT,
        FOREIGN KEY (branch_id) REFERENCES branches(id) ON DELETE SET NULL,
        FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE SET NULL
      )
    ''');
    
    // Leave requests table
    batch.execute('''
      CREATE TABLE leave_requests (
        id TEXT PRIMARY KEY,
        employee_id TEXT NOT NULL,
        branch_id TEXT NOT NULL,
        leave_type TEXT NOT NULL,
        start_date TEXT NOT NULL,
        end_date TEXT NOT NULL,
        reason TEXT,
        status TEXT NOT NULL DEFAULT 'pending',
        approved_by TEXT,
        approved_at TEXT,
        rejection_reason TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        synced_at TEXT,
        FOREIGN KEY (employee_id) REFERENCES employees(id) ON DELETE CASCADE,
        FOREIGN KEY (branch_id) REFERENCES branches(id) ON DELETE CASCADE,
        FOREIGN KEY (approved_by) REFERENCES users(id) ON DELETE SET NULL
      )
    ''');
    
    // Holidays table
    batch.execute('''
      CREATE TABLE holidays (
        id TEXT PRIMARY KEY,
        branch_id TEXT,
        name TEXT NOT NULL,
        date TEXT NOT NULL,
        is_recurring INTEGER DEFAULT 0,
        applies_to_all_branches INTEGER DEFAULT 1,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        synced_at TEXT,
        FOREIGN KEY (branch_id) REFERENCES branches(id) ON DELETE CASCADE
      )
    ''');
    
    // Payroll records table
    batch.execute('''
      CREATE TABLE payroll_records (
        id TEXT PRIMARY KEY,
        employee_id TEXT NOT NULL,
        branch_id TEXT NOT NULL,
        period_start TEXT NOT NULL,
        period_end TEXT NOT NULL,
        base_salary REAL NOT NULL,
        days_worked INTEGER DEFAULT 0,
        hours_worked REAL DEFAULT 0,
        shifts_worked INTEGER DEFAULT 0,
        overtime_hours REAL DEFAULT 0,
        overtime_pay REAL DEFAULT 0,
        late_deductions REAL DEFAULT 0,
        absence_deductions REAL DEFAULT 0,
        bonus REAL DEFAULT 0,
        bonus_reason TEXT,
        other_deductions REAL DEFAULT 0,
        other_deductions_reason TEXT,
        gross_salary REAL NOT NULL,
        net_salary REAL NOT NULL,
        status TEXT NOT NULL DEFAULT 'pending',
        paid_at TEXT,
        paid_by TEXT,
        notes TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        synced_at TEXT,
        FOREIGN KEY (employee_id) REFERENCES employees(id) ON DELETE CASCADE,
        FOREIGN KEY (branch_id) REFERENCES branches(id) ON DELETE CASCADE,
        FOREIGN KEY (paid_by) REFERENCES users(id) ON DELETE SET NULL
      )
    ''');
    
    // Overtime rules table
    batch.execute('''
      CREATE TABLE overtime_rules (
        id TEXT PRIMARY KEY,
        branch_id TEXT NOT NULL,
        name TEXT NOT NULL,
        min_hours_threshold REAL DEFAULT 0,
        multiplier REAL NOT NULL DEFAULT 1.5,
        applies_weekdays INTEGER DEFAULT 1,
        applies_weekends INTEGER DEFAULT 1,
        applies_holidays INTEGER DEFAULT 1,
        is_active INTEGER DEFAULT 1,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        synced_at TEXT,
        FOREIGN KEY (branch_id) REFERENCES branches(id) ON DELETE CASCADE
      )
    ''');
    
    // Deduction rules table
    batch.execute('''
      CREATE TABLE deduction_rules (
        id TEXT PRIMARY KEY,
        branch_id TEXT NOT NULL,
        name TEXT NOT NULL,
        rule_type TEXT NOT NULL,
        threshold_minutes INTEGER,
        deduction_type TEXT NOT NULL,
        deduction_value REAL NOT NULL,
        is_active INTEGER DEFAULT 1,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        synced_at TEXT,
        FOREIGN KEY (branch_id) REFERENCES branches(id) ON DELETE CASCADE
      )
    ''');
    
    // QR codes table (for dynamic QR generation)
    batch.execute('''
      CREATE TABLE qr_codes (
        id TEXT PRIMARY KEY,
        branch_id TEXT NOT NULL,
        token TEXT NOT NULL UNIQUE,
        generated_at TEXT NOT NULL,
        expires_at TEXT NOT NULL,
        is_used INTEGER DEFAULT 0,
        used_by TEXT,
        used_at TEXT,
        FOREIGN KEY (branch_id) REFERENCES branches(id) ON DELETE CASCADE,
        FOREIGN KEY (used_by) REFERENCES employees(id) ON DELETE SET NULL
      )
    ''');
    
    // Device registrations table (for device binding)
    batch.execute('''
      CREATE TABLE device_registrations (
        id TEXT PRIMARY KEY,
        branch_id TEXT NOT NULL,
        device_id TEXT NOT NULL,
        device_name TEXT,
        device_type TEXT,
        is_authorized INTEGER DEFAULT 0,
        authorized_by TEXT,
        authorized_at TEXT,
        last_seen TEXT,
        is_active INTEGER DEFAULT 1,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        synced_at TEXT,
        FOREIGN KEY (branch_id) REFERENCES branches(id) ON DELETE CASCADE,
        FOREIGN KEY (authorized_by) REFERENCES users(id) ON DELETE SET NULL,
        UNIQUE(branch_id, device_id)
      )
    ''');
    
    // Settings table
    batch.execute('''
      CREATE TABLE settings (
        id TEXT PRIMARY KEY,
        branch_id TEXT,
        key TEXT NOT NULL,
        value TEXT,
        value_type TEXT DEFAULT 'string',
        category TEXT,
        description TEXT,
        is_system INTEGER DEFAULT 0,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        synced_at TEXT,
        FOREIGN KEY (branch_id) REFERENCES branches(id) ON DELETE CASCADE,
        UNIQUE(branch_id, key)
      )
    ''');
    
    // License table
    batch.execute('''
      CREATE TABLE licenses (
        id TEXT PRIMARY KEY,
        license_key TEXT NOT NULL UNIQUE,
        license_type TEXT NOT NULL DEFAULT 'trial',
        activated_at TEXT,
        expires_at TEXT,
        max_branches INTEGER DEFAULT 1,
        max_employees INTEGER DEFAULT 50,
        features TEXT,
        is_active INTEGER DEFAULT 1,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');
    
    // Sync log table
    batch.execute('''
      CREATE TABLE sync_logs (
        id TEXT PRIMARY KEY,
        table_name TEXT NOT NULL,
        operation TEXT NOT NULL,
        record_id TEXT NOT NULL,
        status TEXT NOT NULL DEFAULT 'pending',
        error_message TEXT,
        attempted_at TEXT,
        completed_at TEXT,
        created_at TEXT NOT NULL
      )
    ''');
    
    // Create indexes for better performance
    batch.execute('CREATE INDEX idx_employees_branch ON employees(branch_id)');
    batch.execute('CREATE INDEX idx_employees_code ON employees(employee_code)');
    batch.execute('CREATE INDEX idx_employees_barcode ON employees(barcode_serial)');
    batch.execute('CREATE INDEX idx_attendance_employee ON attendance_records(employee_id)');
    batch.execute('CREATE INDEX idx_attendance_date ON attendance_records(date)');
    batch.execute('CREATE INDEX idx_attendance_branch_date ON attendance_records(branch_id, date)');
    batch.execute('CREATE INDEX idx_shifts_branch ON shifts(branch_id)');
    batch.execute('CREATE INDEX idx_audit_logs_timestamp ON audit_logs(timestamp)');
    batch.execute('CREATE INDEX idx_audit_logs_entity ON audit_logs(entity_type, entity_id)');
    batch.execute('CREATE INDEX idx_payroll_employee ON payroll_records(employee_id)');
    batch.execute('CREATE INDEX idx_payroll_period ON payroll_records(period_start, period_end)');
    batch.execute('CREATE INDEX idx_qr_codes_token ON qr_codes(token)');
    batch.execute('CREATE INDEX idx_qr_codes_expires ON qr_codes(expires_at)');
    batch.execute('CREATE INDEX idx_sync_logs_status ON sync_logs(status)');
    
    // =========================================================================
    // FINANCIAL MANAGEMENT TABLES (v3)
    // =========================================================================
    
    // Financial Shifts - Tracks shift-level financial operations
    batch.execute('''
      CREATE TABLE financial_shifts (
        id TEXT PRIMARY KEY,
        branch_id TEXT NOT NULL,
        shift_id TEXT,
        employee_id TEXT NOT NULL,
        opened_at TEXT NOT NULL,
        closed_at TEXT,
        opening_cash REAL DEFAULT 0,
        status TEXT NOT NULL DEFAULT 'open',
        notes TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        synced_at TEXT,
        FOREIGN KEY (branch_id) REFERENCES branches(id) ON DELETE CASCADE,
        FOREIGN KEY (shift_id) REFERENCES shifts(id) ON DELETE SET NULL,
        FOREIGN KEY (employee_id) REFERENCES employees(id) ON DELETE CASCADE
      )
    ''');
    
    // Shift Sales - Records all sales during a shift
    batch.execute('''
      CREATE TABLE shift_sales (
        id TEXT PRIMARY KEY,
        financial_shift_id TEXT NOT NULL,
        branch_id TEXT NOT NULL,
        amount REAL NOT NULL,
        payment_method TEXT NOT NULL DEFAULT 'cash',
        description TEXT,
        invoice_number TEXT,
        customer_name TEXT,
        recorded_by TEXT,
        created_at TEXT NOT NULL,
        synced_at TEXT,
        FOREIGN KEY (financial_shift_id) REFERENCES financial_shifts(id) ON DELETE CASCADE,
        FOREIGN KEY (branch_id) REFERENCES branches(id) ON DELETE CASCADE,
        FOREIGN KEY (recorded_by) REFERENCES employees(id) ON DELETE SET NULL
      )
    ''');
    
    // Shift Expenses - Records all expenses during a shift
    batch.execute('''
      CREATE TABLE shift_expenses (
        id TEXT PRIMARY KEY,
        financial_shift_id TEXT NOT NULL,
        branch_id TEXT NOT NULL,
        amount REAL NOT NULL,
        category TEXT NOT NULL DEFAULT 'misc',
        description TEXT NOT NULL,
        receipt_number TEXT,
        recorded_by TEXT,
        approved_by TEXT,
        created_at TEXT NOT NULL,
        synced_at TEXT,
        FOREIGN KEY (financial_shift_id) REFERENCES financial_shifts(id) ON DELETE CASCADE,
        FOREIGN KEY (branch_id) REFERENCES branches(id) ON DELETE CASCADE,
        FOREIGN KEY (recorded_by) REFERENCES employees(id) ON DELETE SET NULL,
        FOREIGN KEY (approved_by) REFERENCES users(id) ON DELETE SET NULL
      )
    ''');
    
    // Shift Closures - Records the final state when closing a shift
    batch.execute('''
      CREATE TABLE shift_closures (
        id TEXT PRIMARY KEY,
        financial_shift_id TEXT NOT NULL UNIQUE,
        branch_id TEXT NOT NULL,
        total_sales REAL NOT NULL DEFAULT 0,
        total_cash_sales REAL NOT NULL DEFAULT 0,
        total_card_sales REAL NOT NULL DEFAULT 0,
        total_wallet_sales REAL NOT NULL DEFAULT 0,
        total_insurance_sales REAL NOT NULL DEFAULT 0,
        total_credit_sales REAL NOT NULL DEFAULT 0,
        total_expenses REAL NOT NULL DEFAULT 0,
        expected_cash REAL NOT NULL DEFAULT 0,
        actual_cash REAL NOT NULL,
        difference REAL NOT NULL DEFAULT 0,
        difference_reason TEXT,
        closed_by TEXT NOT NULL,
        verified_by TEXT,
        notes TEXT,
        created_at TEXT NOT NULL,
        synced_at TEXT,
        FOREIGN KEY (financial_shift_id) REFERENCES financial_shifts(id) ON DELETE CASCADE,
        FOREIGN KEY (branch_id) REFERENCES branches(id) ON DELETE CASCADE,
        FOREIGN KEY (closed_by) REFERENCES employees(id) ON DELETE SET NULL,
        FOREIGN KEY (verified_by) REFERENCES users(id) ON DELETE SET NULL
      )
    ''');
    
    // Suppliers - Pharma companies / Vendors
    batch.execute('''
      CREATE TABLE suppliers (
        id TEXT PRIMARY KEY,
        branch_id TEXT NOT NULL,
        name TEXT NOT NULL,
        code TEXT,
        phone TEXT,
        email TEXT,
        address TEXT,
        contact_person TEXT,
        tax_number TEXT,
        payment_terms_days INTEGER DEFAULT 30,
        credit_limit REAL DEFAULT 0,
        notes TEXT,
        is_active INTEGER DEFAULT 1,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        synced_at TEXT,
        FOREIGN KEY (branch_id) REFERENCES branches(id) ON DELETE CASCADE,
        UNIQUE(branch_id, name)
      )
    ''');
    
    // Supplier Transactions - Purchases and Payments
    batch.execute('''
      CREATE TABLE supplier_transactions (
        id TEXT PRIMARY KEY,
        supplier_id TEXT NOT NULL,
        branch_id TEXT NOT NULL,
        transaction_type TEXT NOT NULL,
        amount REAL NOT NULL,
        invoice_number TEXT,
        invoice_date TEXT,
        due_date TEXT,
        payment_method TEXT,
        reference_number TEXT,
        notes TEXT,
        recorded_by TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        synced_at TEXT,
        FOREIGN KEY (supplier_id) REFERENCES suppliers(id) ON DELETE CASCADE,
        FOREIGN KEY (branch_id) REFERENCES branches(id) ON DELETE CASCADE,
        FOREIGN KEY (recorded_by) REFERENCES users(id) ON DELETE SET NULL
      )
    ''');
    
    // Financial indexes
    batch.execute('CREATE INDEX idx_financial_shifts_branch ON financial_shifts(branch_id)');
    batch.execute('CREATE INDEX idx_financial_shifts_date ON financial_shifts(opened_at)');
    batch.execute('CREATE INDEX idx_financial_shifts_status ON financial_shifts(status)');
    batch.execute('CREATE INDEX idx_shift_sales_shift ON shift_sales(financial_shift_id)');
    batch.execute('CREATE INDEX idx_shift_sales_date ON shift_sales(created_at)');
    batch.execute('CREATE INDEX idx_shift_expenses_shift ON shift_expenses(financial_shift_id)');
    batch.execute('CREATE INDEX idx_suppliers_branch ON suppliers(branch_id)');
    batch.execute('CREATE INDEX idx_supplier_transactions_supplier ON supplier_transactions(supplier_id)');
    batch.execute('CREATE INDEX idx_supplier_transactions_date ON supplier_transactions(created_at)');
    batch.execute('CREATE INDEX idx_supplier_transactions_type ON supplier_transactions(transaction_type)');
    
    // =========================================================================
    // SAFE (VAULT) MANAGEMENT TABLES (v4)
    // =========================================================================
    
    // Safe Balances - Tracks the pharmacy Safe (Vault) balance per branch
    // Only one record per branch, balance persists across shifts
    batch.execute('''
      CREATE TABLE safe_balances (
        id TEXT PRIMARY KEY,
        branch_id TEXT NOT NULL UNIQUE,
        balance REAL NOT NULL DEFAULT 0,
        last_updated_at TEXT NOT NULL,
        last_updated_by TEXT,
        last_transaction_id TEXT,
        created_at TEXT NOT NULL,
        synced_at TEXT,
        FOREIGN KEY (branch_id) REFERENCES branches(id) ON DELETE CASCADE,
        FOREIGN KEY (last_updated_by) REFERENCES employees(id) ON DELETE SET NULL
      )
    ''');
    
    // Safe Transactions - Audit log of all movements into/out of the Safe
    batch.execute('''
      CREATE TABLE safe_transactions (
        id TEXT PRIMARY KEY,
        branch_id TEXT NOT NULL,
        financial_shift_id TEXT,
        transaction_type TEXT NOT NULL,
        amount REAL NOT NULL,
        balance_before REAL NOT NULL,
        balance_after REAL NOT NULL,
        reference_id TEXT,
        reference_type TEXT,
        description TEXT NOT NULL,
        recorded_by TEXT,
        source TEXT NOT NULL DEFAULT 'system',
        created_at TEXT NOT NULL,
        synced_at TEXT,
        FOREIGN KEY (branch_id) REFERENCES branches(id) ON DELETE CASCADE,
        FOREIGN KEY (financial_shift_id) REFERENCES financial_shifts(id) ON DELETE SET NULL,
        FOREIGN KEY (recorded_by) REFERENCES employees(id) ON DELETE SET NULL
      )
    ''');
    
    // Safe indexes
    batch.execute('CREATE INDEX idx_safe_transactions_branch ON safe_transactions(branch_id)');
    batch.execute('CREATE INDEX idx_safe_transactions_shift ON safe_transactions(financial_shift_id)');
    batch.execute('CREATE INDEX idx_safe_transactions_type ON safe_transactions(transaction_type)');
    batch.execute('CREATE INDEX idx_safe_transactions_date ON safe_transactions(created_at)');
    
    await batch.commit(noResult: true);
    
    // SINGLE-BRANCH ARCHITECTURE: Auto-create default branch with id = '1'
    await _ensureDefaultBranch(db);
  }
  
  /// Ensure the default branch exists (SINGLE-BRANCH ARCHITECTURE)
  /// This creates the main branch with id = '1' if it doesn't exist
  Future<void> _ensureDefaultBranch(Database db) async {
    final now = DateTime.now().toIso8601String();
    
    // Check if default branch exists
    final existing = await db.query(
      'branches',
      where: 'id = ?',
      whereArgs: ['1'],
      limit: 1,
    );
    
    if (existing.isEmpty) {
      _logMigration('Creating default branch (id=1) for single-branch architecture');
      await db.insert('branches', {
        'id': '1',
        'name': 'Main Branch',
        'is_main_branch': 1,
        'is_active': 1,
        'created_at': now,
        'updated_at': now,
      });
      _logMigration('Default branch created successfully');
    }
  }
  
  /// Handle database upgrades with safe production migrations
  /// 
  /// IMPORTANT: All migrations must:
  /// 1. Check if change is needed (column exists, etc.)
  /// 2. Log the migration step
  /// 3. Handle failures gracefully
  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    _logMigration('Starting migration from v$oldVersion to v$newVersion');
    
    // Migration v1 -> v2: Add description column to audit_logs
    if (oldVersion < 2) {
      await _safeAddColumn(
        db,
        tableName: 'audit_logs',
        columnName: 'description',
        columnType: 'TEXT',
      );
    }
    
    // Migration v2 -> v3: Add Financial Management tables
    if (oldVersion < 3) {
      await _migrateToV3(db);
    }
    
    // Migration v3 -> v4: Add Safe (Vault) Management tables
    if (oldVersion < 4) {
      await _migrateToV4(db);
    }
    
    // Migration v3 -> v4: Employee-User integrity enhancements
    // This migration runs for all databases to ensure:
    // 1. Users without employees get employees provisioned
    // 2. User-Employee relationships are properly established
    // Note: SQLite doesn't support ALTER TABLE ADD CONSTRAINT for UNIQUE
    // The unique constraint is enforced at application level via EmployeeResolverService
    await _migrateEmployeeUserIntegrity(db);
    
    // SINGLE-BRANCH ARCHITECTURE: Ensure default branch exists for all upgrades
    await _ensureDefaultBranch(db);
    
    _logMigration('Migration completed successfully');
  }
  
  /// Migration to v3: Add Financial Management System tables
  Future<void> _migrateToV3(Database db) async {
    _logMigration('Starting v3 migration: Financial Management System');
    
    // Create financial_shifts table if not exists
    if (!await _tableExists(db, 'financial_shifts')) {
      _logMigration('Creating financial_shifts table');
      await db.execute('''
        CREATE TABLE financial_shifts (
          id TEXT PRIMARY KEY,
          branch_id TEXT NOT NULL,
          shift_id TEXT,
          employee_id TEXT NOT NULL,
          opened_at TEXT NOT NULL,
          closed_at TEXT,
          opening_cash REAL DEFAULT 0,
          status TEXT NOT NULL DEFAULT 'open',
          notes TEXT,
          created_at TEXT NOT NULL,
          updated_at TEXT NOT NULL,
          synced_at TEXT,
          FOREIGN KEY (branch_id) REFERENCES branches(id) ON DELETE CASCADE,
          FOREIGN KEY (shift_id) REFERENCES shifts(id) ON DELETE SET NULL,
          FOREIGN KEY (employee_id) REFERENCES employees(id) ON DELETE CASCADE
        )
      ''');
    }
    
    // Create shift_sales table if not exists
    if (!await _tableExists(db, 'shift_sales')) {
      _logMigration('Creating shift_sales table');
      await db.execute('''
        CREATE TABLE shift_sales (
          id TEXT PRIMARY KEY,
          financial_shift_id TEXT NOT NULL,
          branch_id TEXT NOT NULL,
          amount REAL NOT NULL,
          payment_method TEXT NOT NULL DEFAULT 'cash',
          description TEXT,
          invoice_number TEXT,
          customer_name TEXT,
          recorded_by TEXT,
          created_at TEXT NOT NULL,
          synced_at TEXT,
          FOREIGN KEY (financial_shift_id) REFERENCES financial_shifts(id) ON DELETE CASCADE,
          FOREIGN KEY (branch_id) REFERENCES branches(id) ON DELETE CASCADE,
          FOREIGN KEY (recorded_by) REFERENCES employees(id) ON DELETE SET NULL
        )
      ''');
    }
    
    // Create shift_expenses table if not exists
    if (!await _tableExists(db, 'shift_expenses')) {
      _logMigration('Creating shift_expenses table');
      await db.execute('''
        CREATE TABLE shift_expenses (
          id TEXT PRIMARY KEY,
          financial_shift_id TEXT NOT NULL,
          branch_id TEXT NOT NULL,
          amount REAL NOT NULL,
          category TEXT NOT NULL DEFAULT 'misc',
          description TEXT NOT NULL,
          receipt_number TEXT,
          recorded_by TEXT,
          approved_by TEXT,
          created_at TEXT NOT NULL,
          synced_at TEXT,
          FOREIGN KEY (financial_shift_id) REFERENCES financial_shifts(id) ON DELETE CASCADE,
          FOREIGN KEY (branch_id) REFERENCES branches(id) ON DELETE CASCADE,
          FOREIGN KEY (recorded_by) REFERENCES employees(id) ON DELETE SET NULL,
          FOREIGN KEY (approved_by) REFERENCES users(id) ON DELETE SET NULL
        )
      ''');
    }
    
    // Create shift_closures table if not exists
    if (!await _tableExists(db, 'shift_closures')) {
      _logMigration('Creating shift_closures table');
      await db.execute('''
        CREATE TABLE shift_closures (
          id TEXT PRIMARY KEY,
          financial_shift_id TEXT NOT NULL UNIQUE,
          branch_id TEXT NOT NULL,
          total_sales REAL NOT NULL DEFAULT 0,
          total_cash_sales REAL NOT NULL DEFAULT 0,
          total_card_sales REAL NOT NULL DEFAULT 0,
          total_wallet_sales REAL NOT NULL DEFAULT 0,
          total_insurance_sales REAL NOT NULL DEFAULT 0,
          total_credit_sales REAL NOT NULL DEFAULT 0,
          total_expenses REAL NOT NULL DEFAULT 0,
          expected_cash REAL NOT NULL DEFAULT 0,
          actual_cash REAL NOT NULL,
          difference REAL NOT NULL DEFAULT 0,
          difference_reason TEXT,
          closed_by TEXT NOT NULL,
          verified_by TEXT,
          notes TEXT,
          created_at TEXT NOT NULL,
          synced_at TEXT,
          FOREIGN KEY (financial_shift_id) REFERENCES financial_shifts(id) ON DELETE CASCADE,
          FOREIGN KEY (branch_id) REFERENCES branches(id) ON DELETE CASCADE,
          FOREIGN KEY (closed_by) REFERENCES employees(id) ON DELETE SET NULL,
          FOREIGN KEY (verified_by) REFERENCES users(id) ON DELETE SET NULL
        )
      ''');
    }
    
    // Create suppliers table if not exists
    if (!await _tableExists(db, 'suppliers')) {
      _logMigration('Creating suppliers table');
      await db.execute('''
        CREATE TABLE suppliers (
          id TEXT PRIMARY KEY,
          branch_id TEXT NOT NULL,
          name TEXT NOT NULL,
          code TEXT,
          phone TEXT,
          email TEXT,
          address TEXT,
          contact_person TEXT,
          tax_number TEXT,
          payment_terms_days INTEGER DEFAULT 30,
          credit_limit REAL DEFAULT 0,
          notes TEXT,
          is_active INTEGER DEFAULT 1,
          created_at TEXT NOT NULL,
          updated_at TEXT NOT NULL,
          synced_at TEXT,
          FOREIGN KEY (branch_id) REFERENCES branches(id) ON DELETE CASCADE,
          UNIQUE(branch_id, name)
        )
      ''');
    }
    
    // Create supplier_transactions table if not exists
    if (!await _tableExists(db, 'supplier_transactions')) {
      _logMigration('Creating supplier_transactions table');
      await db.execute('''
        CREATE TABLE supplier_transactions (
          id TEXT PRIMARY KEY,
          supplier_id TEXT NOT NULL,
          branch_id TEXT NOT NULL,
          transaction_type TEXT NOT NULL,
          amount REAL NOT NULL,
          invoice_number TEXT,
          invoice_date TEXT,
          due_date TEXT,
          payment_method TEXT,
          reference_number TEXT,
          notes TEXT,
          recorded_by TEXT,
          created_at TEXT NOT NULL,
          updated_at TEXT NOT NULL,
          synced_at TEXT,
          FOREIGN KEY (supplier_id) REFERENCES suppliers(id) ON DELETE CASCADE,
          FOREIGN KEY (branch_id) REFERENCES branches(id) ON DELETE CASCADE,
          FOREIGN KEY (recorded_by) REFERENCES users(id) ON DELETE SET NULL
        )
      ''');
    }
    
    // Create indexes for financial tables
    _logMigration('Creating indexes for financial tables');
    await _safeCreateIndex(db, 'idx_financial_shifts_branch', 'financial_shifts', 'branch_id');
    await _safeCreateIndex(db, 'idx_financial_shifts_date', 'financial_shifts', 'opened_at');
    await _safeCreateIndex(db, 'idx_financial_shifts_status', 'financial_shifts', 'status');
    await _safeCreateIndex(db, 'idx_shift_sales_shift', 'shift_sales', 'financial_shift_id');
    await _safeCreateIndex(db, 'idx_shift_sales_date', 'shift_sales', 'created_at');
    await _safeCreateIndex(db, 'idx_shift_expenses_shift', 'shift_expenses', 'financial_shift_id');
    await _safeCreateIndex(db, 'idx_suppliers_branch', 'suppliers', 'branch_id');
    await _safeCreateIndex(db, 'idx_supplier_transactions_supplier', 'supplier_transactions', 'supplier_id');
    await _safeCreateIndex(db, 'idx_supplier_transactions_date', 'supplier_transactions', 'created_at');
    await _safeCreateIndex(db, 'idx_supplier_transactions_type', 'supplier_transactions', 'transaction_type');
    
    _logMigration('v3 migration completed: Financial Management System tables created');
  }
  
  /// Migration to v4: Add Safe (Vault) Management tables
  Future<void> _migrateToV4(Database db) async {
    _logMigration('Starting v4 migration: Safe (Vault) Management System');
    
    // Create safe_balances table if not exists
    if (!await _tableExists(db, 'safe_balances')) {
      _logMigration('Creating safe_balances table');
      await db.execute('''
        CREATE TABLE safe_balances (
          id TEXT PRIMARY KEY,
          branch_id TEXT NOT NULL UNIQUE,
          balance REAL NOT NULL DEFAULT 0,
          last_updated_at TEXT NOT NULL,
          last_updated_by TEXT,
          last_transaction_id TEXT,
          created_at TEXT NOT NULL,
          synced_at TEXT,
          FOREIGN KEY (branch_id) REFERENCES branches(id) ON DELETE CASCADE,
          FOREIGN KEY (last_updated_by) REFERENCES employees(id) ON DELETE SET NULL
        )
      ''');
    }
    
    // Create safe_transactions table if not exists
    if (!await _tableExists(db, 'safe_transactions')) {
      _logMigration('Creating safe_transactions table');
      await db.execute('''
        CREATE TABLE safe_transactions (
          id TEXT PRIMARY KEY,
          branch_id TEXT NOT NULL,
          financial_shift_id TEXT,
          transaction_type TEXT NOT NULL,
          amount REAL NOT NULL,
          balance_before REAL NOT NULL,
          balance_after REAL NOT NULL,
          reference_id TEXT,
          reference_type TEXT,
          description TEXT NOT NULL,
          recorded_by TEXT,
          source TEXT NOT NULL DEFAULT 'system',
          created_at TEXT NOT NULL,
          synced_at TEXT,
          FOREIGN KEY (branch_id) REFERENCES branches(id) ON DELETE CASCADE,
          FOREIGN KEY (financial_shift_id) REFERENCES financial_shifts(id) ON DELETE SET NULL,
          FOREIGN KEY (recorded_by) REFERENCES employees(id) ON DELETE SET NULL
        )
      ''');
    }
    
    // Create indexes for safe tables
    _logMigration('Creating indexes for safe tables');
    await _safeCreateIndex(db, 'idx_safe_transactions_branch', 'safe_transactions', 'branch_id');
    await _safeCreateIndex(db, 'idx_safe_transactions_shift', 'safe_transactions', 'financial_shift_id');
    await _safeCreateIndex(db, 'idx_safe_transactions_type', 'safe_transactions', 'transaction_type');
    await _safeCreateIndex(db, 'idx_safe_transactions_date', 'safe_transactions', 'created_at');
    
    // Add safe-related columns to shift_closures if they don't exist
    await _safeAddColumn(db, tableName: 'shift_closures', columnName: 'safe_balance_before', columnType: 'REAL', defaultValue: '0');
    await _safeAddColumn(db, tableName: 'shift_closures', columnName: 'safe_balance_after', columnType: 'REAL', defaultValue: '0');
    await _safeAddColumn(db, tableName: 'shift_closures', columnName: 'transferred_to_safe', columnType: 'REAL', defaultValue: '0');
    await _safeAddColumn(db, tableName: 'shift_closures', columnName: 'safe_payments', columnType: 'REAL', defaultValue: '0');
    
    // Add payment_source to supplier_transactions if it doesn't exist
    await _safeAddColumn(db, tableName: 'supplier_transactions', columnName: 'payment_source', columnType: 'TEXT', defaultValue: "'safe'");
    
    _logMigration('v4 migration completed: Safe (Vault) Management System tables created');
  }
  
  /// Migration for Employee-User integrity
  /// 
  /// SINGLE-BRANCH ARCHITECTURE: Ensures all users have employee records
  /// This migration:
  /// 1. Finds users without employee links
  /// 2. Creates employee records for them
  /// 3. Links employees to users
  /// 
  /// Note: Actual provisioning is done via EmployeeResolverService at runtime
  /// This migration only ensures the database structure supports the relationship
  Future<void> _migrateEmployeeUserIntegrity(Database db) async {
    _logMigration('Starting Employee-User integrity migration');
    
    // Ensure employees.branch_id has default value '1'
    // SQLite doesn't support ALTER TABLE to modify default, but new rows will use the default
    // Existing rows should already have branch_id set
    
    // Update any employees with NULL branch_id to use default branch
    final nullBranchEmployees = await db.rawQuery(
      "SELECT COUNT(*) as count FROM employees WHERE branch_id IS NULL",
    );
    final nullCount = nullBranchEmployees.first['count'] as int? ?? 0;
    
    if (nullCount > 0) {
      _logMigration('Found $nullCount employees with NULL branch_id, setting to default branch');
      await db.rawUpdate(
        "UPDATE employees SET branch_id = '1' WHERE branch_id IS NULL",
      );
    }
    
    // Create index on users.employee_id for faster lookups
    await _safeCreateIndex(db, 'idx_users_employee_id', 'users', 'employee_id');
    
    // Log users without employees (will be provisioned at runtime)
    final usersWithoutEmployees = await db.rawQuery(
      "SELECT COUNT(*) as count FROM users WHERE employee_id IS NULL AND is_active = 1",
    );
    final orphanCount = usersWithoutEmployees.first['count'] as int? ?? 0;
    
    if (orphanCount > 0) {
      _logMigration('[INFO] Found $orphanCount active users without employee links - will be provisioned at runtime via EmployeeResolverService');
    }
    
    _logMigration('Employee-User integrity migration completed');
  }
  
  /// Check if a table exists
  Future<bool> _tableExists(Database db, String tableName) async {
    final result = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type='table' AND name=?",
      [tableName],
    );
    return result.isNotEmpty;
  }
  
  /// Safely create an index if it doesn't exist
  Future<void> _safeCreateIndex(
    Database db,
    String indexName,
    String tableName,
    String columnName,
  ) async {
    try {
      // Check if index exists
      final result = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='index' AND name=?",
        [indexName],
      );
      
      if (result.isEmpty) {
        await db.execute('CREATE INDEX $indexName ON $tableName($columnName)');
        _logMigration('Created index $indexName on $tableName($columnName)');
      } else {
        _logMigration('Index $indexName already exists - skipping');
      }
    } catch (e) {
      _logMigration('ERROR creating index $indexName: $e');
    }
  }
  
  /// Safely add a column if it doesn't exist
  /// Uses PRAGMA table_info to check column existence first
  Future<bool> _safeAddColumn(
    Database db, {
    required String tableName,
    required String columnName,
    required String columnType,
    String? defaultValue,
  }) async {
    try {
      // Check if column already exists using PRAGMA
      final tableInfo = await db.rawQuery('PRAGMA table_info($tableName)');
      final columnExists = tableInfo.any(
        (col) => col['name']?.toString().toLowerCase() == columnName.toLowerCase(),
      );
      
      if (columnExists) {
        _logMigration('Column $columnName already exists in $tableName - skipping');
        return false;
      }
      
      // Column doesn't exist, add it
      String sql = 'ALTER TABLE $tableName ADD COLUMN $columnName $columnType';
      if (defaultValue != null) {
        sql += ' DEFAULT $defaultValue';
      }
      
      await db.execute(sql);
      _logMigration('Added column $columnName to $tableName');
      return true;
    } catch (e) {
      _logMigration('ERROR adding column $columnName to $tableName: $e');
      // Don't rethrow - allow app to continue even if migration fails
      return false;
    }
  }
  
  /// Check if a column exists in a table
  Future<bool> columnExists(String tableName, String columnName) async {
    final db = await database;
    final tableInfo = await db.rawQuery('PRAGMA table_info($tableName)');
    return tableInfo.any(
      (col) => col['name']?.toString().toLowerCase() == columnName.toLowerCase(),
    );
  }
  
  /// Log migration step
  static void _logMigration(String message) {
    final timestamp = DateTime.now().toIso8601String();
    final logEntry = '[$timestamp] $message';
    _migrationLog.add(logEntry);
    // Also print for debugging
    // ignore: avoid_print
    print('DB Migration: $logEntry');
  }
  
  /// Close database
  Future<void> close() async {
    if (_database != null) {
      await _database!.close();
      _database = null;
    }
  }
  
  /// Clear all data (for testing/reset)
  Future<void> clearAllData() async {
    final db = await database;
    final tables = [
      // Financial tables first (foreign key order)
      'shift_closures',
      'shift_expenses',
      'shift_sales',
      'financial_shifts',
      'supplier_transactions',
      'suppliers',
      // Original tables
      'sync_logs',
      'licenses',
      'settings',
      'device_registrations',
      'qr_codes',
      'deduction_rules',
      'overtime_rules',
      'payroll_records',
      'holidays',
      'leave_requests',
      'audit_logs',
      'attendance_records',
      'employee_shift_assignments',
      'employees',
      'shifts',
      'users',
      'branches',
    ];
    
    for (final table in tables) {
      try {
        await db.delete(table);
      } catch (e) {
        // Table might not exist in older databases
        _logMigration('Warning: Could not clear table $table: $e');
      }
    }
  }
  
  /// Get database path
  Future<String> getDatabasePath() async {
    final Directory appDocDir = await getApplicationDocumentsDirectory();
    return p.join(appDocDir.path, 'PharmacyAttendance', AppConstants.databaseName);
  }
  
  /// Export database (for backup)
  Future<String> exportDatabase() async {
    final dbPath = await getDatabasePath();
    final exportDir = await getApplicationDocumentsDirectory();
    final timestamp = DateTime.now().toIso8601String().replaceAll(':', '-');
    final exportPath = p.join(exportDir.path, 'PharmacyAttendance', 'backups', 'backup_$timestamp.db');
    
    final exportDirectory = Directory(p.dirname(exportPath));
    if (!await exportDirectory.exists()) {
      await exportDirectory.create(recursive: true);
    }
    
    await File(dbPath).copy(exportPath);
    return exportPath;
  }
  
  /// Import database (restore from backup)
  Future<void> importDatabase(String backupPath) async {
    await close();
    final dbPath = await getDatabasePath();
    await File(backupPath).copy(dbPath);
    _database = await _initDatabase();
  }
}
