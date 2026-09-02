import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'RolesView.dart';
import 'constants.dart';
import 'package:FincoreGo/widgets/app_bottom_nav.dart';
import 'widgets/entry_widgets.dart';
import 'providers/modify_role_notifier.dart';

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
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => const RolesView()),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = modifyRoleNotifierProvider(widget.roleId);
    final vm = ref.watch(provider);
    final notifier = ref.read(provider.notifier);

    ref.listen<ModifyRoleState>(provider, (previous, next) {
      if (next.loadError != null) {
        showAppMessage(context, next.loadError!);
        notifier.clearLoadError();
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
                  onPressed: isSaving ? null : _saveRole,
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
                          'Save Changes',
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
