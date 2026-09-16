import 'package:flutter_test/flutter_test.dart';
import 'package:FincoreGo/AddRole.dart';

Map<String, dynamic> _permission({
  required String id,
  required String displayName,
  required String group,
  required String resource,
  required String action,
}) {
  return {
    'id': id,
    'displayName': displayName,
    'group': group,
    'resource': resource,
    'action': action,
  };
}

void main() {
  group('PermissionOption.fromJson', () {
    test('keeps group unchanged for non-Entry permissions', () {
      final option = PermissionOption.fromJson(_permission(
        id: '1',
        displayName: 'View Item Rate',
        group: 'Items',
        resource: 'ITEM_RATE',
        action: 'READ',
      ));
      expect(option.group, 'Items');
    });

    test('splits Entry:READ into the "Transactions" display group', () {
      final option = PermissionOption.fromJson(_permission(
        id: '1',
        displayName: 'View Ledger in Entry',
        group: 'Entry',
        resource: 'ENTRY_LEDGER',
        action: 'READ',
      ));
      expect(option.group, 'Transactions');
    });

    test('keeps Entry:CREATE in the "Entry" display group', () {
      final option = PermissionOption.fromJson(_permission(
        id: '1',
        displayName: 'Create Sales Entry',
        group: 'Entry',
        resource: 'ENTRY_SALES',
        action: 'CREATE',
      ));
      expect(option.group, 'Entry');
    });

    test('overrides misleading backend display names', () {
      final cases = {
        'View Role': 'Create Role',
        'View User': 'Create User',
        'All Role': 'Full Role Management',
        'All User': 'Full User Management',
        'Read Company': 'View Company',
        'Read Permission': 'View Permissions',
        'Read Role': 'View Roles',
        'Read User': 'View Users',
        'Read License': 'View License',
      };
      for (final entry in cases.entries) {
        final option = PermissionOption.fromJson(_permission(
          id: '1',
          displayName: entry.key,
          group: 'Company User Management',
          resource: 'COMPANY_ROLE',
          action: 'CREATE',
        ));
        expect(option.displayName, entry.value,
            reason: 'expected "${entry.key}" to map to "${entry.value}"');
      }
    });

    test('leaves already-correct display names untouched', () {
      final option = PermissionOption.fromJson(_permission(
        id: '1',
        displayName: 'View Van Allocation',
        group: 'Van Allocation',
        resource: 'VAN_ALLOCATION',
        action: 'READ',
      ));
      expect(option.displayName, 'View Van Allocation');
    });
  });

  group('PermissionOption.isMetaAdmin', () {
    test('flags every meta-admin resource', () {
      for (final resource in [
        'COMPANY',
        'COMPANY_ROLE',
        'COMPANY_USER',
        'COMPANY_PERMISSION',
        'LICENSE',
      ]) {
        expect(PermissionOption.isMetaAdmin(resource), isTrue,
            reason: '$resource should be treated as meta-admin');
      }
    });

    test('does not flag business resources', () {
      for (final resource in [
        'DASHBOARD_SALES',
        'ENTRY_SALES',
        'ITEM_RATE',
        'PARTY_SALES',
        'SETTINGS_VAT_PERCENTAGE',
        'VAN_ALLOCATION',
      ]) {
        expect(PermissionOption.isMetaAdmin(resource), isFalse,
            reason: '$resource should NOT be treated as meta-admin');
      }
    });
  });

  group('PermissionOption.groupByLegacyOrder', () {
    test('orders groups Dashboard, Items, Party, Transactions, Entry, '
        'Settings, Van Allocation regardless of input order', () {
      final permissions = [
        PermissionOption(
            id: '1', displayName: 'x', group: 'Van Allocation', resource: 'VAN_ALLOCATION'),
        PermissionOption(id: '2', displayName: 'x', group: 'Settings', resource: 'SETTINGS_X'),
        PermissionOption(id: '3', displayName: 'x', group: 'Entry', resource: 'ENTRY_SALES'),
        PermissionOption(
            id: '4', displayName: 'x', group: 'Transactions', resource: 'ENTRY_LEDGER'),
        PermissionOption(id: '5', displayName: 'x', group: 'Party', resource: 'PARTY_SALES'),
        PermissionOption(id: '6', displayName: 'x', group: 'Items', resource: 'ITEM_RATE'),
        PermissionOption(
            id: '7', displayName: 'x', group: 'Dashboard', resource: 'DASHBOARD_SALES'),
      ];

      final grouped = PermissionOption.groupByLegacyOrder(permissions);

      expect(grouped.keys.toList(), [
        'Dashboard',
        'Items',
        'Party',
        'Transactions',
        'Entry',
        'Settings',
        'Van Allocation',
      ]);
    });

    test('an unknown group sorts after all known legacy groups', () {
      final permissions = [
        PermissionOption(id: '1', displayName: 'x', group: 'Mystery', resource: 'X'),
        PermissionOption(
            id: '2', displayName: 'x', group: 'Dashboard', resource: 'DASHBOARD_SALES'),
      ];

      final grouped = PermissionOption.groupByLegacyOrder(permissions);

      expect(grouped.keys.toList(), ['Dashboard', 'Mystery']);
    });

    test('preserves every permission within its group', () {
      final permissions = [
        PermissionOption(
            id: '1', displayName: 'Sales', group: 'Dashboard', resource: 'DASHBOARD_SALES'),
        PermissionOption(
            id: '2', displayName: 'Cash', group: 'Dashboard', resource: 'DASHBOARD_CASH'),
      ];

      final grouped = PermissionOption.groupByLegacyOrder(permissions);

      expect(grouped['Dashboard']!.map((p) => p.id), ['1', '2']);
    });
  });
}
