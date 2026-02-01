import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Application state provider for global state management
class AppStateProvider extends ChangeNotifier {
  static const String _themeKey = 'theme_mode';
  static const String _localeKey = 'locale';
  
  ThemeMode _themeMode = ThemeMode.system;
  Locale _locale = const Locale('en', '');
  bool _isLoading = false;
  String? _errorMessage;
  
  ThemeMode get themeMode => _themeMode;
  Locale get locale => _locale;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  
  AppStateProvider() {
    _loadPreferences();
  }
  
  /// Load saved preferences
  Future<void> _loadPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    
    // Load theme
    final themeModeIndex = prefs.getInt(_themeKey) ?? 0;
    _themeMode = ThemeMode.values[themeModeIndex];
    
    // Load locale
    final localeCode = prefs.getString(_localeKey) ?? 'en';
    _locale = Locale(localeCode, '');
    
    notifyListeners();
  }
  
  /// Set theme mode
  Future<void> setThemeMode(ThemeMode mode) async {
    if (_themeMode == mode) return;
    
    _themeMode = mode;
    
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_themeKey, mode.index);
    
    notifyListeners();
  }
  
  /// Set locale
  Future<void> setLocale(Locale locale) async {
    if (_locale == locale) return;
    
    _locale = locale;
    
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_localeKey, locale.languageCode);
    
    notifyListeners();
  }
  
  /// Toggle theme (light/dark)
  Future<void> toggleTheme() async {
    final newMode = _themeMode == ThemeMode.light 
        ? ThemeMode.dark 
        : ThemeMode.light;
    await setThemeMode(newMode);
  }
  
  /// Toggle locale (English/Arabic)
  Future<void> toggleLocale() async {
    final newLocale = _locale.languageCode == 'en' 
        ? const Locale('ar', '') 
        : const Locale('en', '');
    await setLocale(newLocale);
  }
  
  /// Set loading state
  void setLoading(bool loading) {
    _isLoading = loading;
    notifyListeners();
  }
  
  /// Set error message
  void setError(String? message) {
    _errorMessage = message;
    notifyListeners();
  }
  
  /// Clear error message
  void clearError() {
    _errorMessage = null;
    notifyListeners();
  }
}
