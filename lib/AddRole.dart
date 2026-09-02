import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'RolesView.dart';
import 'constants.dart';
import 'package:FincoreGo/widgets/app_bottom_nav.dart';
import 'widgets/entry_widgets.dart';
import 'providers/add_role_notifier.dart';

/// One entry from tally-oauth's `/company-permission` catalog - a role
/// grants a set of these by id. The catalog is meta-administration only
/// (who can manage roles/users/permissions themselves), not the legacy
/// app's ~50 per-screen feature toggles - see the migration notes on
/// [RolesView] for why.
class PermissionOption {
  PermissionOption({
    required this.id,
    required this.displayName,
    required this.group,
  });

  final String id;
  final String displayName;
  final String group;

  factory PermissionOption.fromJson(Map<String, dynamic> json) =>
      PermissionOption(
        id: json['id'] as String,
        displayName: json['displayName'] as String,
        group: json['group'] as String,
      );
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
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => const RolesView()),
      );
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
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
              children: [
                TextField(
                  controller: nameController,
                  style: GoogleFonts.poppins(),
                  decoration: InputDecoration(
                    labelText: 'Role name',
                    labelStyle: GoogleFonts.poppins(),
                    filled: true,
                    fillColor: Theme.of(context).cardColor,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  'Permissions',
                  style: GoogleFonts.poppins(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
                const SizedBox(height: 8),
                for (final entry in vm.groupedPermissions.entries) ...[
                  Padding(
                    padding: const EdgeInsets.only(top: 12, bottom: 4),
                    child: Text(
                      entry.key,
                      style: GoogleFonts.poppins(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: app_color,
                      ),
                    ),
                  ),
                  Container(
                    decoration: BoxDecoration(
                      color: Theme.of(context).cardColor,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Column(
                      children: entry.value
                          .map(
                            (permission) => CheckboxListTile(
                              value: selectedPermissionIds.contains(permission.id),
                              onChanged: (checked) {
                                notifier.togglePermission(
                                  permission.id,
                                  checked ?? false,
                                );
                              },
                              title: Text(
                                permission.displayName,
                                style: GoogleFonts.poppins(fontSize: 14),
                              ),
                              controlAffinity: ListTileControlAffinity.leading,
                              activeColor: app_color,
                            ),
                          )
                          .toList(),
                    ),
                  ),
                ],
                const SizedBox(height: 24),
                ElevatedButton(
                  onPressed: isSaving ? null : _createRole,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: app_color,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
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
                          'Create Role',
                          style: GoogleFonts.poppins(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                ),
              ],
            ),
    );
  }
}
