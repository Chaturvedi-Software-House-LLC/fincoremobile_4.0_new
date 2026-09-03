import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Riverpod migration of `FastMovingInactiveItemsCriteria.dart`'s
/// `_FastMovingInactiveItemsState`. Purely local SharedPreferences config,
/// no backend calls - closest sibling `ageing_config_notifier.dart` (same
/// load/edit/validate/save shape), minus the cascading-default behaviour
/// this screen's fields never had.
class FastMovingInactiveItemsCriteriaState {
  final String fastMovingDays;
  final String fastMovingQty;
  final String fastMovingValue;
  final String slowMovingDays;
  final String slowMovingQty;
  final String slowMovingValue;
  final String inactiveDays;

  const FastMovingInactiveItemsCriteriaState({
    this.fastMovingDays = '180',
    this.fastMovingQty = '1000',
    this.fastMovingValue = '10000',
    this.slowMovingDays = '181',
    this.slowMovingQty = '1000',
    this.slowMovingValue = '10000',
    this.inactiveDays = '182',
  });

  FastMovingInactiveItemsCriteriaState copyWith({
    String? fastMovingDays,
    String? fastMovingQty,
    String? fastMovingValue,
    String? slowMovingDays,
    String? slowMovingQty,
    String? slowMovingValue,
    String? inactiveDays,
  }) {
    return FastMovingInactiveItemsCriteriaState(
      fastMovingDays: fastMovingDays ?? this.fastMovingDays,
      fastMovingQty: fastMovingQty ?? this.fastMovingQty,
      fastMovingValue: fastMovingValue ?? this.fastMovingValue,
      slowMovingDays: slowMovingDays ?? this.slowMovingDays,
      slowMovingQty: slowMovingQty ?? this.slowMovingQty,
      slowMovingValue: slowMovingValue ?? this.slowMovingValue,
      inactiveDays: inactiveDays ?? this.inactiveDays,
    );
  }
}

class FastMovingInactiveItemsCriteriaNotifier
    extends StateNotifier<FastMovingInactiveItemsCriteriaState> {
  FastMovingInactiveItemsCriteriaNotifier()
      : super(const FastMovingInactiveItemsCriteriaState()) {
    _init();
  }

  Future<void> _init() async {
    final prefs = await SharedPreferences.getInstance();
    state = FastMovingInactiveItemsCriteriaState(
      fastMovingDays: prefs.getString('fastmovingdays') ?? '180',
      fastMovingQty: prefs.getString('fastmovingqty') ?? '1000',
      fastMovingValue: prefs.getString('fastmovingvalue') ?? '10000',
      slowMovingDays: prefs.getString('slowmovingdays') ?? '181',
      slowMovingQty: prefs.getString('slowmovingqty') ?? '1000',
      slowMovingValue: prefs.getString('slowmovingvalue') ?? '10000',
      inactiveDays: prefs.getString('inactivedays') ?? '182',
    );
  }

  void setFastMovingDays(String value) =>
      state = state.copyWith(fastMovingDays: value);
  void setFastMovingQty(String value) =>
      state = state.copyWith(fastMovingQty: value);
  void setFastMovingValue(String value) =>
      state = state.copyWith(fastMovingValue: value);
  void setSlowMovingDays(String value) =>
      state = state.copyWith(slowMovingDays: value);
  void setSlowMovingQty(String value) =>
      state = state.copyWith(slowMovingQty: value);
  void setSlowMovingValue(String value) =>
      state = state.copyWith(slowMovingValue: value);
  void setInactiveDays(String value) =>
      state = state.copyWith(inactiveDays: value);

  /// Returns a user-facing message; the widget decides success/error styling
  /// from whether it contains "saved", matching the original `showToast`.
  Future<String> save() async {
    final s = state;
    if (s.fastMovingDays.isEmpty ||
        s.fastMovingQty.isEmpty ||
        s.fastMovingValue.isEmpty ||
        s.slowMovingDays.isEmpty ||
        s.slowMovingQty.isEmpty ||
        s.slowMovingValue.isEmpty ||
        s.inactiveDays.isEmpty) {
      return 'Fields cannot be empty';
    }

    final fastMovingDaysInt = int.tryParse(s.fastMovingDays);
    final slowMovingDaysInt = int.tryParse(s.slowMovingDays);
    final inactiveDaysInt = int.tryParse(s.inactiveDays);

    if (fastMovingDaysInt == null ||
        slowMovingDaysInt == null ||
        inactiveDaysInt == null) {
      return 'Please enter valid numbers for the day fields';
    }

    if (inactiveDaysInt <= slowMovingDaysInt ||
        inactiveDaysInt <= fastMovingDaysInt) {
      return 'Inactive days must be greater than fast/slow moving days';
    }

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('fastmovingdays', s.fastMovingDays);
    await prefs.setString('fastmovingqty', s.fastMovingQty);
    await prefs.setString('fastmovingvalue', s.fastMovingValue);
    await prefs.setString('slowmovingdays', s.slowMovingDays);
    await prefs.setString('slowmovingqty', s.slowMovingQty);
    await prefs.setString('slowmovingvalue', s.slowMovingValue);
    await prefs.setString('inactivedays', s.inactiveDays);

    return 'Criteria Saved';
  }
}

final fastMovingInactiveItemsCriteriaNotifierProvider = StateNotifierProvider
    .autoDispose<FastMovingInactiveItemsCriteriaNotifier,
        FastMovingInactiveItemsCriteriaState>(
  (ref) => FastMovingInactiveItemsCriteriaNotifier(),
);
