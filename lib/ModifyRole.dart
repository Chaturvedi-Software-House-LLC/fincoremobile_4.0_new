import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'AddRole.dart';
import 'RolesView.dart';
import 'constants.dart';
import 'package:FincoreGo/widgets/app_bottom_nav.dart';
import 'widgets/entry_widgets.dart';
import 'api/api_exception.dart';
import 'api/base_api_client.dart';
import 'api/identity_repository.dart';

class ModifyRole extends StatefulWidget {
  final String roleId;
  const ModifyRole({Key? key, required this.roleId}) : super(key: key);

  @override
  _ModifyRolePageState createState() => _ModifyRolePageState();
}

class _ModifyRolePageState extends State<ModifyRole> {
  final nameController = TextEditingController();
  final Set<String> selectedPermissionIds = {};

  List<PermissionOption> permissions = [];
  bool isLoading = true;
  bool isSaving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    nameController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => isLoading = true);
    try {
      final results = await Future.wait([
        IdentityRepository.instance.listPermissions(),
        IdentityRepository.instance.getRole(widget.roleId),
      ]);

      final permissionItems = ((results[0] as ApiResult).data as List)
          .cast<Map<String, dynamic>>();
      permissions = permissionItems.map(PermissionOption.fromJson).toList();

      final role = results[1] as Map<String, dynamic>;
      nameController.text = role['name'] as String;

      // Each item is `{permision: {id, ...}}` - see the misspelled key
      // note in identity_repository.dart's listRoles doc-comment.
      final grantedPermissions = (role['permissions'] as List? ?? const [])
          .cast<Map<String, dynamic>>();
      selectedPermissionIds.addAll(
        grantedPermissions.map(
          (p) => (p['permision'] as Map<String, dynamic>)['id'] as String,
        ),
      );
    } on ApiException catch (e) {
      showAppMessage(context, e.message);
    } catch (e) {
      showAppMessage(context, 'Could not reach the server. Please try again.');
    }
    setState(() => isLoading = false);
  }

  Future<void> _saveRole() async {
    final name = nameController.text.trim();
    if (name.isEmpty) {
      showAppMessage(context, 'Please enter a role name');
      return;
    }

    setState(() => isSaving = true);
    try {
      await IdentityRepository.instance.updateRole(
        widget.roleId,
        name: name,
        permissionIds: selectedPermissionIds.toList(),
      );
      showAppMessage(context, 'Role updated successfully', isError: false);
      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => const RolesView()),
        );
      }
    } on ApiException catch (e) {
      showAppMessage(context, e.message);
    } catch (e) {
      showAppMessage(context, 'Could not reach the server. Please try again.');
    } finally {
      if (mounted) setState(() => isSaving = false);
    }
  }

  Map<String, List<PermissionOption>> get _groupedPermissions {
    final grouped = <String, List<PermissionOption>>{};
    for (final permission in permissions) {
      grouped.putIfAbsent(permission.group, () => []).add(permission);
    }
    return grouped;
  }

  @override
  Widget build(BuildContext context) {
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
                for (final entry in _groupedPermissions.entries) ...[
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
                                setState(() {
                                  if (checked ?? false) {
                                    selectedPermissionIds.add(permission.id);
                                  } else {
                                    selectedPermissionIds.remove(permission.id);
                                  }
                                });
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
