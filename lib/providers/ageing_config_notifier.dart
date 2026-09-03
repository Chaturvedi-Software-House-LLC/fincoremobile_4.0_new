import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Riverpod migration of `AgeingConfig.dart`'s `_AgeingConfigState`. Purely
/// local SharedPreferences config, no backend calls - the only state is the
/// five ageing-bracket day values and the cascading defaults each one seeds
/// into the ones after it, ported verbatim from the old `onChanged` handlers.
class AgeingConfigState {
  final String heading1;
  final String heading2;
  final String heading3;
  final String heading4;
  final String heading5;

  const AgeingConfigState({
    this.heading1 = '30',
    this.heading2 = '60',
    this.heading3 = '90',
    this.heading4 = '120',
    this.heading5 = '180',
  });

  AgeingConfigState copyWith({
    String? heading1,
    String? heading2,
    String? heading3,
    String? heading4,
    String? heading5,
  }) {
    return AgeingConfigState(
      heading1: heading1 ?? this.heading1,
      heading2: heading2 ?? this.heading2,
      heading3: heading3 ?? this.heading3,
      heading4: heading4 ?? this.heading4,
      heading5: heading5 ?? this.heading5,
    );
  }
}

class AgeingConfigNotifier extends StateNotifier<AgeingConfigState> {
  AgeingConfigNotifier() : super(const AgeingConfigState()) {
    _init();
  }

  Future<void> _init() async {
    final prefs = await SharedPreferences.getInstance();
    state = AgeingConfigState(
      heading1: prefs.getString('heading1') ?? '30',
      heading2: prefs.getString('heading2') ?? '60',
      heading3: prefs.getString('heading3') ?? '90',
      heading4: prefs.getString('heading4') ?? '120',
      heading5: prefs.getString('heading5') ?? '180',
    );
  }

  void setHeading1(String value) {
    if (value.isEmpty) return;
    final base = int.tryParse(value) ?? 0;
    state = state.copyWith(
      heading1: value,
      heading2: '${base + base}',
      heading3: '${base + base * 2}',
      heading4: '${base + base * 3}',
      heading5: '${base + base * 4}',
    );
  }

  void setHeading2(String value) {
    if (value.isEmpty) return;
    final base = int.tryParse(value) ?? 0;
    state = state.copyWith(
      heading2: value,
      heading3: '${base + base}',
      heading4: '${base + base * 2}',
      heading5: '${base + base * 3}',
    );
  }

  void setHeading3(String value) {
    if (value.isEmpty) return;
    final base = int.tryParse(value) ?? 0;
    state = state.copyWith(
      heading3: value,
      heading4: '${base + base}',
      heading5: '${base + base * 2}',
    );
  }

  void setHeading4(String value) {
    if (value.isEmpty) return;
    final base = int.tryParse(value) ?? 0;
    state = state.copyWith(heading4: value, heading5: '${base + base}');
  }

  void setHeading5(String value) {
    if (value.isEmpty) return;
    state = state.copyWith(heading5: value);
  }

  /// Returns a user-facing message; the widget decides success/error styling
  /// from whether it contains "saved", matching the original `showToast`.
  Future<String> save() async {
    final h1 = state.heading1;
    final h2 = state.heading2;
    final h3 = state.heading3;
    final h4 = state.heading4;
    final h5 = state.heading5;

    if (h1.isEmpty || h2.isEmpty || h3.isEmpty || h4.isEmpty || h5.isEmpty) {
      return 'Ageing Field Cannot be Empty';
    }

    final h1Int = int.tryParse(h1);
    final h2Int = int.tryParse(h2);
    final h3Int = int.tryParse(h3);
    final h4Int = int.tryParse(h4);
    final h5Int = int.tryParse(h5);

    if (h1Int == null ||
        h2Int == null ||
        h3Int == null ||
        h4Int == null ||
        h5Int == null) {
      return 'Please enter valid numbers for all ageing fields';
    }

    if (h1Int > 0 && h2Int > h1Int && h3Int > h2Int && h4Int > h3Int && h5Int > h4Int) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('heading1', h1);
      await prefs.setString('heading2', h2);
      await prefs.setString('heading3', h3);
      await prefs.setString('heading4', h4);
      await prefs.setString('heading5', h5);
      return 'Ageing Configuration Saved';
    }

    return 'Ageing Value should be greater than lower limit';
  }
}

final ageingConfigNotifierProvider =
    StateNotifierProvider.autoDispose<AgeingConfigNotifier, AgeingConfigState>(
  (ref) => AgeingConfigNotifier(),
);
