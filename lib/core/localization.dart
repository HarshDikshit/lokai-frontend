import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

// We'll use this to access preferences throughout the app if needed
final sharedPrefsProvider = Provider<SharedPreferences>((ref) => throw UnimplementedError());

class AppLocalization {
  final Locale locale;
  static Map<String, String>? _localizedValues;

  AppLocalization(this.locale);

  static AppLocalization? of(BuildContext context) {
    return Localizations.of<AppLocalization>(context, AppLocalization);
  }

  Future<void> load() async {
    String jsonString = await rootBundle.loadString('assets/lang/${locale.languageCode}.json');
    Map<String, dynamic> mappedJson = json.decode(jsonString);
    _localizedValues = mappedJson.map((key, value) => MapEntry(key, value.toString()));
  }

  String translate(String key) {
    return _localizedValues?[key] ?? key;
  }

  static const LocalizationsDelegate<AppLocalization> delegate = _AppLocalizationDelegate();
}

class _AppLocalizationDelegate extends LocalizationsDelegate<AppLocalization> {
  const _AppLocalizationDelegate();

  @override
  bool isSupported(Locale locale) {
    return ['en', 'hi'].contains(locale.languageCode);
  }

  @override
  Future<AppLocalization> load(Locale locale) async {
    AppLocalization localization = AppLocalization(locale);
    await localization.load();
    return localization;
  }

  @override
  bool shouldReload(_AppLocalizationDelegate old) => false;
}

class LocaleNotifier extends Notifier<Locale> {
  static const _key = 'selected_language';

  @override
  Locale build() {
    // Initial state is English, but we'll try to load from prefs immediately
    _loadSavedLocale();
    return const Locale('en');
  }

  Future<void> _loadSavedLocale() async {
    final prefs = ref.read(sharedPrefsProvider);
    final code = prefs.getString(_key);
    if (code != null && code != state.languageCode) {
      state = Locale(code);
    }
  }

  Future<void> setLocale(Locale lo) async {
    state = lo;
    final prefs = ref.read(sharedPrefsProvider);
    await prefs.setString(_key, lo.languageCode);
  }
}

final localeProvider = NotifierProvider<LocaleNotifier, Locale>(LocaleNotifier.new);

extension LocalizationExtension on BuildContext {
  String translate(String key) {
    return AppLocalization.of(this)?.translate(key) ?? key;
  }
}

