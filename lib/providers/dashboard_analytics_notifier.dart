import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../utils/number_formatter.dart';

/// Riverpod migration of `DashboardAnalytics.dart`'s `_AnalyticsScreenState`.
/// This screen is purely presentational (its chart data all arrives as
/// constructor params from the caller, no network calls of its own), so the
/// only real state is the number-scale preference and the percentage/amount
/// toggle - everything else in the old State class (`company`,
/// `companyLowercase`, `serialNo`, `username`, `securityButtonAccessHolder`)
/// was set from SharedPreferences but never actually read anywhere, so it's
/// dropped rather than carried over.
class DashboardAnalyticsArgs {
  final NumberScale initialScale;

  const DashboardAnalyticsArgs({required this.initialScale});

  @override
  bool operator ==(Object other) =>
      other is DashboardAnalyticsArgs && other.initialScale == initialScale;

  @override
  int get hashCode => initialScale.hashCode;
}

class DashboardAnalyticsState {
  final NumberScale selectedScale;
  final bool showPercentage;

  const DashboardAnalyticsState({
    required this.selectedScale,
    this.showPercentage = false,
  });

  DashboardAnalyticsState copyWith({
    NumberScale? selectedScale,
    bool? showPercentage,
  }) {
    return DashboardAnalyticsState(
      selectedScale: selectedScale ?? this.selectedScale,
      showPercentage: showPercentage ?? this.showPercentage,
    );
  }
}

class DashboardAnalyticsNotifier extends StateNotifier<DashboardAnalyticsState> {
  final DashboardAnalyticsArgs args;

  DashboardAnalyticsNotifier(this.args)
      : super(DashboardAnalyticsState(selectedScale: args.initialScale)) {
    _init();
  }

  void setShowPercentage(bool value) {
    state = state.copyWith(showPercentage: value);
  }

  Future<void> _init() async {
    final prefs = await SharedPreferences.getInstance();
    final scale = _numberScaleFromString(prefs.getString('number_scale'));
    if (scale != null) {
      state = state.copyWith(selectedScale: scale);
    }
  }

  NumberScale? _numberScaleFromString(String? value) {
    switch (value) {
      case 'thousand':
        return NumberScale.thousand;
      case 'million':
        return NumberScale.million;
      case 'billion':
        return NumberScale.billion;
      case 'full':
        return NumberScale.full;
      default:
        return null;
    }
  }
}

final dashboardAnalyticsNotifierProvider = StateNotifierProvider.autoDispose
    .family<DashboardAnalyticsNotifier, DashboardAnalyticsState, DashboardAnalyticsArgs>(
  (ref, args) => DashboardAnalyticsNotifier(args),
);
