import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../locale_controller.dart';
import '../theme_controller.dart';

/// Bridges the existing [themeController]/[localeController] singletons
/// (still consumed directly via `addListener`/`removeListener` by
/// [Settings.dart], not yet migrated) into Riverpod, without changing their
/// [ChangeNotifier]-based API. Screens migrated to Riverpod should watch
/// these providers instead of the raw singletons; unmigrated screens keep
/// working against the singletons unchanged.
final themeControllerProvider = ChangeNotifierProvider<ThemeController>(
  (ref) => themeController,
);

final localeControllerProvider = ChangeNotifierProvider<LocaleController>(
  (ref) => localeController,
);
