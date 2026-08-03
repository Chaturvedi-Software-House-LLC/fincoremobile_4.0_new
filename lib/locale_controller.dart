import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'SharedPreferencesService.dart';

final LocaleController localeController = LocaleController();

class LocaleController extends ChangeNotifier {
  static const String _localeKey = 'appLocale';

  Locale _locale = const Locale('en');

  Locale get locale => _locale;

  Future<void> loadLocale() async {
    final prefs =
        SharedPreferencesService.preferences ??
        await SharedPreferences.getInstance();
    _locale = Locale(prefs.getString(_localeKey) ?? 'en');
    notifyListeners();
  }

  Future<void> setLocale(Locale locale) async {
    if (_locale == locale) {
      return;
    }

    _locale = locale;
    notifyListeners();

    final prefs =
        SharedPreferencesService.preferences ??
        await SharedPreferences.getInstance();
    await prefs.setString(_localeKey, locale.languageCode);
  }
}
