import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:FincoreGo/api/identity_repository.dart';
import 'package:FincoreGo/api/base_api_client.dart';
import 'package:FincoreGo/providers/repository_providers.dart';
import 'package:FincoreGo/providers/roles_view_notifier.dart';

class MockIdentityRepository extends Mock implements IdentityRepository {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MockIdentityRepository repo;
  late ProviderContainer container;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    repo = MockIdentityRepository();
    container = ProviderContainer(
      overrides: [identityRepositoryProvider.overrideWithValue(repo)],
    );
  });

  tearDown(() {
    container.dispose();
  });

  test('fetchRoles populates roles and filteredRoles identically when no '
      'search is active', () async {
    when(() => repo.listRoles(page: 1, limit: 20)).thenAnswer((_) async => ApiResult([
          {'id': '1', 'name': 'Admin', 'permissions': []},
          {'id': '2', 'name': 'Driver', 'permissions': []},
        ], null));

    final notifier = container.read(rolesViewNotifierProvider.notifier);
    await notifier.fetchRoles();

    final state = container.read(rolesViewNotifierProvider);
    expect(state.roles.map((r) => r.name), ['Admin', 'Driver']);
    expect(state.filteredRoles.map((r) => r.name), ['Admin', 'Driver']);
    expect(state.isVisibleNoRoleFound, isFalse);
  });

  test('filterRoles narrows filteredRoles without touching roles - '
      'regression test for the bug where the UI rendered the unfiltered '
      'list and the search box appeared to do nothing', () async {
    when(() => repo.listRoles(page: 1, limit: 20)).thenAnswer((_) async => ApiResult([
          {'id': '1', 'name': 'Admin', 'permissions': []},
          {'id': '2', 'name': 'Driver', 'permissions': []},
        ], null));

    final notifier = container.read(rolesViewNotifierProvider.notifier);
    await notifier.fetchRoles();

    notifier.filterRoles('driv');

    final state = container.read(rolesViewNotifierProvider);
    expect(state.roles.map((r) => r.name), ['Admin', 'Driver'],
        reason: 'the full list must stay intact');
    expect(state.filteredRoles.map((r) => r.name), ['Driver'],
        reason: 'only filteredRoles narrows');
    expect(state.isVisibleNoRoleFound, isFalse);
  });

  test('filterRoles with no matches shows the empty state', () async {
    when(() => repo.listRoles(page: 1, limit: 20)).thenAnswer((_) async => ApiResult([
          {'id': '1', 'name': 'Admin', 'permissions': []},
        ], null));

    final notifier = container.read(rolesViewNotifierProvider.notifier);
    await notifier.fetchRoles();

    notifier.filterRoles('zzz-no-match');

    final state = container.read(rolesViewNotifierProvider);
    expect(state.filteredRoles, isEmpty);
    expect(state.isVisibleNoRoleFound, isTrue);
  });

  test('clearing the search query restores the full list', () async {
    when(() => repo.listRoles(page: 1, limit: 20)).thenAnswer((_) async => ApiResult([
          {'id': '1', 'name': 'Admin', 'permissions': []},
          {'id': '2', 'name': 'Driver', 'permissions': []},
        ], null));

    final notifier = container.read(rolesViewNotifierProvider.notifier);
    await notifier.fetchRoles();
    notifier.filterRoles('driv');
    notifier.filterRoles('');

    final state = container.read(rolesViewNotifierProvider);
    expect(state.filteredRoles.map((r) => r.name), ['Admin', 'Driver']);
  });

  test('a disposed notifier does not throw when an in-flight fetch resolves '
      '- regression test for "Tried to use RolesViewNotifier after dispose '
      'was called"', () async {
    when(() => repo.listRoles(page: 1, limit: 20)).thenAnswer(
      (_) => Future.delayed(
        const Duration(milliseconds: 50),
        () => ApiResult([
          {'id': '1', 'name': 'Admin', 'permissions': []},
        ], null),
      ),
    );

    final notifier = container.read(rolesViewNotifierProvider.notifier);
    final pending = notifier.fetchRoles();
    container.dispose(); // disposes the notifier while the fetch is in flight

    // Must resolve without throwing "used after dispose".
    await expectLater(pending, completes);
  });
}
