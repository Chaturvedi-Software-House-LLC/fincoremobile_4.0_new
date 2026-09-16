// Widget-level integration test: drives the real RolesView widget tree
// (notifier + UI wiring together, not just the notifier in isolation like
// roles_view_notifier_test.dart) against a mocked IdentityRepository - no
// real backend/device needed, so it's fast and deterministic enough to run
// in CI. This is the automated stand-in for the manual simulator
// click-through this session relied on to catch the original search bug
// (RolesView rendering `vm.roles` instead of `vm.filteredRoles`).
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:FincoreGo/RolesView.dart';
import 'package:FincoreGo/api/identity_repository.dart';
import 'package:FincoreGo/api/base_api_client.dart';
import 'package:FincoreGo/l10n/app_localizations.dart';
import 'package:FincoreGo/providers/repository_providers.dart';

class MockIdentityRepository extends Mock implements IdentityRepository {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MockIdentityRepository repo;

  setUp(() {
    repo = MockIdentityRepository();
    SharedPreferences.setMockInitialValues({
      'company_name': 'Test Co',
      'secbtnaccess': 'True',
    });
    when(() => repo.listRoles(page: 1, limit: 20))
        .thenAnswer((_) async => ApiResult([
              {'id': '1', 'name': 'Admin', 'permissions': []},
              {'id': '2', 'name': 'Driver', 'permissions': []},
            ], null));
  });

  Widget buildApp() {
    return ProviderScope(
      overrides: [identityRepositoryProvider.overrideWithValue(repo)],
      child: const MaterialApp(
        locale: Locale('en'),
        supportedLocales: [Locale('en')],
        localizationsDelegates: [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: RolesView(),
      ),
    );
  }

  testWidgets('shows both roles after loading', (tester) async {
    await tester.pumpWidget(buildApp());
    await tester.pumpAndSettle();

    expect(find.text('Admin'), findsOneWidget);
    expect(find.text('Driver'), findsOneWidget);
  });

  testWidgets(
      'typing in the search box filters the visible list - regression '
      'test for RolesView rendering the unfiltered list', (tester) async {
    await tester.pumpWidget(buildApp());
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'driv');
    await tester.pumpAndSettle();

    expect(find.text('Driver'), findsOneWidget);
    expect(find.text('Admin'), findsNothing,
        reason: 'Admin must be filtered out once the list actually reacts '
            'to the search box');
  });

  testWidgets('clearing the search box restores the full list', (tester) async {
    await tester.pumpWidget(buildApp());
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'driv');
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '');
    await tester.pumpAndSettle();

    expect(find.text('Admin'), findsOneWidget);
    expect(find.text('Driver'), findsOneWidget);
  });

  testWidgets('a search with no matches shows the empty state', (tester) async {
    await tester.pumpWidget(buildApp());
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'no-such-role');
    await tester.pumpAndSettle();

    expect(find.text('Admin'), findsNothing);
    expect(find.text('Driver'), findsNothing);
    expect(find.text('No Roles Found'), findsOneWidget);
  });
}
