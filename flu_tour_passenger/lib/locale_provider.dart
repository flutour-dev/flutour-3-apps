// lib/locale_provider.dart
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class LocaleProvider extends ChangeNotifier {
  Locale _locale;

  LocaleProvider(this._locale);

  Locale get locale => _locale;

  Future<void> setLocale(Locale locale) async {
    if (_locale == locale) return;
    _locale = locale;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('locale', locale.languageCode);
  }

  static Future<LocaleProvider> load({required Locale defaultLocale}) async {
    final prefs = await SharedPreferences.getInstance();
    final code = prefs.getString('locale');
    final locale = (code != null) ? Locale(code) : defaultLocale;
    return LocaleProvider(locale);
  }
}
