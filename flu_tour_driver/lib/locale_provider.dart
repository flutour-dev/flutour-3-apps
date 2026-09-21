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
    await prefs.setBool('locale_user_set', true);
  }

  static Future<LocaleProvider> load({required Locale defaultLocale}) async {
    final prefs = await SharedPreferences.getInstance();
    final code = prefs.getString('locale');
    // If no explicit user choice was made, use defaultLocale.
    // Reset: if old default was 'ar' but new default is 'en' and user never
    // explicitly switched, detect this by checking a 'locale_user_set' flag.
    final userSetLocale = prefs.getBool('locale_user_set') ?? false;
    final locale = (code != null && userSetLocale) ? Locale(code) : defaultLocale;
    return LocaleProvider(locale);
  }
}
