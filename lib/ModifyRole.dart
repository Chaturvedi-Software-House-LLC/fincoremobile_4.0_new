import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'constants.dart';
import 'package:FincoreGo/widgets/app_bottom_nav.dart';
import 'widgets/entry_widgets.dart';
import 'providers/modify_role_notifier.dart';
import 'providers/roles_view_notifier.dart';

class ModifyRole extends ConsumerStatefulWidget {
  final String roleId;
  const ModifyRole({Key? key, required this.roleId}) : super(key: key);

  @override
  ConsumerState<ModifyRole> createState() => _ModifyRolePageState();
}

class _ModifyRolePageState extends ConsumerState<ModifyRole> {
  final nameController = TextEditingController();
  bool _nameSeeded = false;

  @override
  void dispose() {
    nameController.dispose();
    super.dispose();
  }

  Future<void> _saveRole() async {
    final name = nameController.text.trim();
    final result = await ref
        .read(modifyRoleNotifierProvider(widget.roleId).notifier)
        .saveRole(name);
    if (!mounted) return;
    if (result.message != null) {
      showAppMessage(context, result.message!, isError: !result.success);
    }
    if (result.success) {
      // RolesView.dart pushed this screen (not pushReplacement), keeping
      // itself on the stack underneath specifically so a plain pop always
      // has somewhere to return to. Popping back to it here (instead of
      // pushReplacement-ing a brand new RolesView on top) avoids stacking
      // a duplicate RolesView on every successful save - refresh its list
      // first since it's the same underlying
      // `rolesViewNotifierProvider.autoDispose` instance (still mounted,
      // not disposed, while covered by this screen).
      await ref.read(rolesViewNotifierProvider.notifier).fetchRoles();
      if (!mounted) return;
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = modifyRoleNotifierProvider(widget.roleId);
    final vm = ref.watch(provider);
    final notifier = ref.read(provider.notifier);

    ref.listen<ModifyRoleState>(provider, (previous, next) {
      if (next.loadError != null) {
        showAppMessage(context, next.loadError!, isError: !next.shouldGoBack);
        notifier.clearLoadError();
      }
      if (next.shouldGoBack) {
        Navigator.pop(context);
      }
    });

    // Seed the name field once the role loads, without clobbering
    // in-progress edits on every rebuild.
    if (!_nameSeeded && !vm.isLoading && vm.name.isNotEmpty) {
      _nameSeeded = true;
      nameController.text = vm.name;
    }

    final isLoading = vm.isLoading;
    final isSaving = vm.isSaving;
    final isSystem = vm.isSystem;
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
            'Edit Role',
            style: GoogleFonts.poppins(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.w600,
            ),
          ),
          centerTitle: true,
        ),
      ),
      body: isLoading
          ? buildRoleFormSkeleton(context)
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
              children: [
                // System roles (e.g. "Admin", one auto-created per company)
                // can't be edited by a regular company-user - the backend
                // rejects the update outright. Shown read-only with a clear
                // explanation up front instead of letting the user fill out
                // the form and hit a confusing error on submit.
                if (isSystem)
                  Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Colors.amber.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: Colors.amber.shade700),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.info_outline, color: Colors.amber.shade800),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'This is a system role and cannot be modified. You can still view its permissions.',
                            style: GoogleFonts.poppins(
                              fontSize: 12.5,
                              color: Colors.amber.shade900,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                IgnorePointer(
                  ignoring: isSystem,
                  child: Opacity(
                    opacity: isSystem ? 0.6 : 1,
                    child: buildRoleFormCard(
                      context: context,
                      headerIcon: Icons.edit_outlined,
                      headerTitle: 'Edit Role',
                      headerSubtitle:
                          'Update the role name and adjust its permissions.',
                      nameController: nameController,
                      groupedPermissions: vm.groupedPermissions,
                      selectedPermissionIds: selectedPermissionIds,
                      totalPermissionCount: vm.permissions.length,
                      onToggle: notifier.togglePermission,
                    ),
                  ),
                ),
                const SizedBox(height: 22),
                Center(
                  child: ElevatedButton(
                    onPressed: (isSaving || isSystem) ? null : _saveRole,
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
                            'MODIFY',
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
