import 'package:flutter/material.dart';

/// Global navigator key so non-widget code (`BaseApiClient`, on a dead
/// refresh token - see [SessionExpiredException]) can force navigation
/// back to the login screen without a `BuildContext` threaded through
/// every API call site. `main.dart`'s `MaterialApp` is wired to this same
/// key - defined in its own file (rather than in `main.dart` itself) so
/// `lib/api/*.dart` can depend on it without importing `main.dart`/`Login.dart`
/// and the rest of the app's widget tree.
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();
