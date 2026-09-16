import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'constants.dart';
import 'package:FincoreGo/widgets/app_bottom_nav.dart';
import 'widgets/entry_widgets.dart';
import 'providers/add_role_notifier.dart';
import 'providers/roles_view_notifier.dart';

/// One entry from tally-oauth's `/company-permission` catalog - a role
/// grants a set of these by id. The catalog also carries meta-admin
/// entries (who can manage roles/users/permissions/license themselves -
/// [isMetaAdmin]) that never existed as legacy per-screen toggles; the
/// Add/Modify Role screen excludes those from what a custom role can be
/// given (per explicit request: only the legacy app's own groups -
/// Dashboard, Items, Party, Transactions, Entries, Settings, plus
/// Van Allocation for Spectra - should be selectable there, matching the
/// legacy app's exact grouping "same to same").
class PermissionOption {
  PermissionOption({
    required this.id,
    required this.displayName,
    required this.group,
    required this.resource,
  });

  final String id;
  final String displayName;
  final String group;
  final String resource;

  // The backend's seeded `displayName` values are inconsistent/misleading
  // for a handful of entries under "Company User Management" - e.g. "View
  // Role"/"View User" actually carry a CREATE action, and several READ
  // entries say "Read X" instead of "View X" like the rest of the catalog.
  // Fixed here on the client (not the backend, per explicit instruction)
  // so the Add/Modify Role permission chips read correctly without
  // touching seed data. Keyed by the raw backend label.
  static const Map<String, String> _displayNameOverrides = {
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

  /// Meta-administration resources - who can manage companies/roles/
  /// users/licenses/the permission catalog itself. These have no legacy
  /// equivalent (the legacy app never let an admin delegate "can manage
  /// other users' roles" to a custom role) and are excluded from the
  /// Add/Modify Role screen's selectable catalog entirely - only the
  /// system Admin role (which already has them, and can't be edited
  /// through this screen - see ModifyRole.dart's isSystem handling) has
  /// these.
  static const Set<String> _metaAdminResources = {
    'COMPANY',
    'COMPANY_ROLE',
    'COMPANY_USER',
    'COMPANY_PERMISSION',
    'LICENSE',
  };

  static bool isMetaAdmin(String resource) =>
      _metaAdminResources.contains(resource);

  factory PermissionOption.fromJson(Map<String, dynamic> json) {
    final rawDisplayName = json['displayName'] as String;
    final rawGroup = json['group'] as String;
    final resource = json['resource'] as String;
    final action = json['action'] as String?;
    // The legacy app split what this catalog calls a single "Entry" group
    // into two separate sections: "Transactions Access" (viewing
    // ledger/bills/inventory/cost-centre/post-dated entries - the READ
    // half, none of which have a matching creation screen in this app) and
    // "Entry Access" (actually creating a sales/receipt/sales order/
    // delivery note voucher - the CREATE half). Mirrored here by display
    // group so the UI matches the legacy app exactly, even though the
    // backend only has one "Entry" group. The backend's raw group name is
    // "Entry" (singular) - comparing against "Entries" here previously
    // never matched, so every READ permission (Postdated Transactions,
    // Cost Centre/Inventory/Ledger/Bills Entries) wrongly stayed mixed
    // into the CREATE-only "Entry" section shown on Add/Modify Role
    // instead of moving to "Transactions".
    final displayGroup = (rawGroup == 'Entry' && action == 'READ')
        ? 'Transactions'
        : rawGroup;
    return PermissionOption(
      id: json['id'] as String,
      displayName: _displayNameOverrides[rawDisplayName] ?? rawDisplayName,
      group: displayGroup,
      resource: resource,
    );
  }

  /// Legacy app's exact group display order (Dashboard, Items, Party,
  /// Transactions, Entries, Settings - see AddRole.dart's `build()` method
  /// in the legacy app), with "Van Allocation" appended last since it's
  /// new to this catalog and Spectra-only. Groups not listed here (e.g. if
  /// the backend ever adds a new one) sort after all of these, in
  /// whatever order they're first seen.
  static const List<String> _groupOrder = [
    'Dashboard',
    'Items',
    'Party',
    'Transactions',
    'Entry',
    'Settings',
    'Van Allocation',
  ];

  /// Groups a permission list by [group], in [_groupOrder] rather than
  /// whatever order the backend happened to return them in (alphabetical
  /// by display name, which put "Entries" before "Transactions" since
  /// "Create..." sorts before "View...") - AddRole/ModifyRole's
  /// `groupedPermissions` both use this so the on-screen order matches the
  /// legacy app "same to same".
  static Map<String, List<PermissionOption>> groupByLegacyOrder(
    List<PermissionOption> permissions,
  ) {
    final byGroup = <String, List<PermissionOption>>{};
    for (final permission in permissions) {
      byGroup.putIfAbsent(permission.group, () => []).add(permission);
    }
    final ordered = <String, List<PermissionOption>>{};
    for (final group in _groupOrder) {
      final entries = byGroup.remove(group);
      if (entries != null) ordered[group] = entries;
    }
    ordered.addAll(byGroup);
    return ordered;
  }
}

class AddRole extends ConsumerStatefulWidget {
  const AddRole({Key? key}) : super(key: key);
  @override
  ConsumerState<AddRole> createState() => _AddRolePageState();
}

class _AddRolePageState extends ConsumerState<AddRole> {
  final nameController = TextEditingController();

  @override
  void dispose() {
    nameController.dispose();
    super.dispose();
  }

  Future<void> _createRole() async {
    final name = nameController.text.trim();
    final result =
        await ref.read(addRoleNotifierProvider.notifier).createRole(name);
    if (!mounted) return;
    if (result.message != null) {
      showAppMessage(context, result.message!, isError: !result.success);
    }
    if (result.success) {
      // RolesView.dart pushed this screen (not pushReplacement), keeping
      // itself on the stack underneath specifically so a plain pop always
      // has somewhere to return to. Popping back to it here (instead of
      // pushReplacement-ing a brand new RolesView on top) avoids stacking
      // a duplicate RolesView on every successful create - refresh its
      // list first since it's the same underlying
      // `rolesViewNotifierProvider.autoDispose` instance (still mounted,
      // not disposed, while covered by this screen).
      await ref.read(rolesViewNotifierProvider.notifier).fetchRoles();
      if (!mounted) return;
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final vm = ref.watch(addRoleNotifierProvider);
    final notifier = ref.read(addRoleNotifierProvider.notifier);

    ref.listen<AddRoleState>(addRoleNotifierProvider, (previous, next) {
      if (next.loadError != null) {
        showAppMessage(context, next.loadError!);
        notifier.clearLoadError();
      }
    });

    final isLoadingPermissions = vm.isLoadingPermissions;
    final isSaving = vm.isSaving;
    final selectedPermissionIds = vm.selectedPermissionIds;

    return Scaffold(
      bottomNavigationBar: const AppBottomNav(
        activeTab: AppBottomNavTab.more,
        activeMoreItem: AppMoreItem.roles,
      ),
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(50),
        child: AppBar(
          backgroundColor: app_color,
          elevation: 6,
          automaticallyImplyLeading: false,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.white),
            onPressed: () => Navigator.pop(context),
          ),
          title: Text(
            'Add Role',
            style: GoogleFonts.poppins(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.w600,
            ),
          ),
          centerTitle: true,
        ),
      ),
      body: isLoadingPermissions
          ? buildRoleFormSkeleton(context)
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
              children: [
                buildRoleFormCard(
                  context: context,
                  headerIcon: Icons.add_moderator_outlined,
                  headerTitle: 'Create New Role',
                  headerSubtitle:
                      'Name the role and choose the permissions it grants.',
                  nameController: nameController,
                  groupedPermissions: vm.groupedPermissions,
                  selectedPermissionIds: selectedPermissionIds,
                  totalPermissionCount: vm.permissions.length,
                  onToggle: notifier.togglePermission,
                ),
                const SizedBox(height: 22),
                Center(
                  child: ElevatedButton(
                    onPressed: isSaving ? null : _createRole,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: app_color,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(30),
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 40,
                        vertical: 14,
                      ),
                    ),
                    child: isSaving
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2,
                            ),
                          )
                        : Text(
                            'REGISTER',
                            style: GoogleFonts.poppins(
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                  ),
                ),
                const SizedBox(height: 40),
              ],
            ),
    );
  }
}
