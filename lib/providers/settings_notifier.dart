import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/biometric_auth_service.dart';

/// Riverpod migration of `Settings.dart`'s `_MyHomePageState`. Purely local
/// SharedPreferences config plus the on-device biometric toggle - no
/// backend calls. `vatController`/`inactivedaysController` (TextEditingControllers)
/// and the app-wide `themeController` listener stay in the widget since
/// they're either UI-only or an existing separate singleton, out of scope
/// for this migration.
enum BiometricToggleResult { success, missingCredentials, cancelled }

class SettingsState {
  final String currencyCode;
  final double vatValue;
  final int inactivePartiesDays;
  final String dateRangeOption;
  final DateTime? customStartDate;
  final DateTime? customEndDate;
  final int decimalPlaces;
  final String sortOption;

  final bool canCurrency;
  final bool canAmtDecimals;
  final bool canVatPerc;
  final bool canInactivePDays;
  final bool canSortType;
  final bool canDefDateRange;
  final bool canAgeingConfig;
  final bool canFastSlowInactiveItem;

  final bool biometricAvailable;
  final bool biometricEnabled;
  final String biometricLabel;

  const SettingsState({
    this.currencyCode = 'AED',
    this.vatValue = 5,
    this.inactivePartiesDays = 30,
    this.dateRangeOption = 'Today',
    this.customStartDate,
    this.customEndDate,
    this.decimalPlaces = 2,
    this.sortOption = 'Default',
    this.canCurrency = true,
    this.canAmtDecimals = true,
    this.canVatPerc = true,
    this.canInactivePDays = true,
    this.canSortType = true,
    this.canDefDateRange = true,
    this.canAgeingConfig = true,
    this.canFastSlowInactiveItem = true,
    this.biometricAvailable = false,
    this.biometricEnabled = false,
    this.biometricLabel = 'Biometric',
  });

  SettingsState copyWith({
    String? currencyCode,
    double? vatValue,
    int? inactivePartiesDays,
    String? dateRangeOption,
    DateTime? customStartDate,
    DateTime? customEndDate,
    bool clearCustomDates = false,
    int? decimalPlaces,
    String? sortOption,
    bool? canCurrency,
    bool? canAmtDecimals,
    bool? canVatPerc,
    bool? canInactivePDays,
    bool? canSortType,
    bool? canDefDateRange,
    bool? canAgeingConfig,
    bool? canFastSlowInactiveItem,
    bool? biometricAvailable,
    bool? biometricEnabled,
    String? biometricLabel,
  }) {
    return SettingsState(
      currencyCode: currencyCode ?? this.currencyCode,
      vatValue: vatValue ?? this.vatValue,
      inactivePartiesDays: inactivePartiesDays ?? this.inactivePartiesDays,
      dateRangeOption: dateRangeOption ?? this.dateRangeOption,
      customStartDate:
          clearCustomDates ? null : (customStartDate ?? this.customStartDate),
      customEndDate:
          clearCustomDates ? null : (customEndDate ?? this.customEndDate),
      decimalPlaces: decimalPlaces ?? this.decimalPlaces,
      sortOption: sortOption ?? this.sortOption,
      canCurrency: canCurrency ?? this.canCurrency,
      canAmtDecimals: canAmtDecimals ?? this.canAmtDecimals,
      canVatPerc: canVatPerc ?? this.canVatPerc,
      canInactivePDays: canInactivePDays ?? this.canInactivePDays,
      canSortType: canSortType ?? this.canSortType,
      canDefDateRange: canDefDateRange ?? this.canDefDateRange,
      canAgeingConfig: canAgeingConfig ?? this.canAgeingConfig,
      canFastSlowInactiveItem:
          canFastSlowInactiveItem ?? this.canFastSlowInactiveItem,
      biometricAvailable: biometricAvailable ?? this.biometricAvailable,
      biometricEnabled: biometricEnabled ?? this.biometricEnabled,
      biometricLabel: biometricLabel ?? this.biometricLabel,
    );
  }
}

class SettingsNotifier extends StateNotifier<SettingsState> {
  SettingsNotifier() : super(const SettingsState()) {
    _init();
  }

  Future<void> _init() async {
    final prefs = await SharedPreferences.getInstance();

    final vatValue = prefs.getDouble('vatperc') ?? 5;
    final inactiveDays = prefs.getInt('inactiveparties_days') ?? 30;
    final dateRangeOption = prefs.getString('dateRangeOption') ?? 'Today';

    DateTime? customStartDate;
    DateTime? customEndDate;
    final start = prefs.getString('startdate');
    final end = prefs.getString('enddate');
    if (start != null && end != null) {
      customStartDate = DateTime.tryParse(start);
      customEndDate = DateTime.tryParse(end);
    }

    var currencyCode = prefs.getString('currencycode') ?? 'AED';
    if (currencyCode == 'null') currencyCode = 'AED';

    var sortOption = prefs.getString('sort') ?? 'Default';
    if (sortOption == 'null') sortOption = 'Default';

    final decimalPlaces = prefs.getInt('decimalplace') ?? 2;

    final bool isAdmin = (prefs.getString('secbtnaccess') ?? 'False') == 'True';
    bool allowed(String key) =>
        isAdmin || (prefs.getString(key) ?? 'False') == 'True';

    final biometricAvailable =
        await BiometricAuthService.instance.isDeviceSupported();
    final biometricEnabled = await BiometricAuthService.instance.isEnabled();
    final biometricLabel = await BiometricAuthService.instance
        .biometricLabel();

    state = SettingsState(
      currencyCode: currencyCode,
      vatValue: vatValue,
      inactivePartiesDays: inactiveDays,
      dateRangeOption: dateRangeOption,
      customStartDate: customStartDate,
      customEndDate: customEndDate,
      decimalPlaces: decimalPlaces,
      sortOption: sortOption,
      canCurrency: allowed('settings_currency'),
      canAmtDecimals: allowed('settings_amtdecimals'),
      canVatPerc: allowed('settings_vatperc'),
      canInactivePDays: allowed('settings_inactivepdays'),
      canSortType: allowed('settings_sorttype'),
      canDefDateRange: allowed('settings_defdaterange'),
      canAgeingConfig: allowed('settings_ageingconfig'),
      canFastSlowInactiveItem: allowed('settings_fastslowinactiveitem'),
      biometricAvailable: biometricAvailable,
      biometricEnabled: biometricEnabled,
      biometricLabel: biometricLabel,
    );
  }

  Future<void> setCurrency(String code) async {
    state = state.copyWith(currencyCode: code);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('currencycode', code);
  }

  Future<void> setVat(double value) async {
    state = state.copyWith(vatValue: value);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('vatperc', value);
  }

  Future<void> setInactiveDays(int days) async {
    state = state.copyWith(inactivePartiesDays: days);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('inactiveparties_days', days);
  }

  Future<void> setDecimalPlaces(int value) async {
    state = state.copyWith(decimalPlaces: value);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('decimalplace', value);
  }

  Future<void> setSortOption(String value) async {
    state = state.copyWith(sortOption: value);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('sort', value);
  }

  Future<void> setDateRangeOption(String value) async {
    state = state.copyWith(dateRangeOption: value, clearCustomDates: true);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('dateRangeOption', value);
    await prefs.remove('startdate');
    await prefs.remove('enddate');
  }

  Future<void> setCustomDateRange(DateTime start, DateTime end) async {
    state = state.copyWith(
      dateRangeOption: 'Custom Date',
      customStartDate: start,
      customEndDate: end,
    );
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('dateRangeOption', 'Custom Date');
    await prefs.setString('startdate', start.toIso8601String());
    await prefs.setString('enddate', end.toIso8601String());
  }

  /// [confirmReason] is a pre-localized message (the widget builds it from
  /// `AppLocalizations`, since the notifier has no `BuildContext`).
  Future<BiometricToggleResult> setBiometricEnabled(
    bool enable, {
    required String confirmReason,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    if (enable) {
      final storedUser = prefs.getString('username_remember');
      final storedPass = prefs.getString('password_remember');
      if (storedUser == null || storedPass == null) {
        return BiometricToggleResult.missingCredentials;
      }
      final confirmed = await BiometricAuthService.instance.authenticate(
        reason: confirmReason,
      );
      if (!confirmed) return BiometricToggleResult.cancelled;

      await BiometricAuthService.instance.setEnabled(true);
      await prefs.setString('biometric_username', storedUser);
      await prefs.setString('biometric_password', storedPass);
    } else {
      await BiometricAuthService.instance.setEnabled(false);
      await prefs.remove('biometric_username');
      await prefs.remove('biometric_password');
    }
    state = state.copyWith(biometricEnabled: enable);
    return BiometricToggleResult.success;
  }
}

final settingsNotifierProvider =
    StateNotifierProvider.autoDispose<SettingsNotifier, SettingsState>(
  (ref) => SettingsNotifier(),
);
