import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'RolesView.dart';
import 'constants.dart';
import 'package:FincoreGo/widgets/app_bottom_nav.dart';
import 'widgets/entry_widgets.dart';
import 'api/api_exception.dart';
import 'api/identity_repository.dart';

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

class AddRole extends StatefulWidget {
  const AddRole({Key? key}) : super(key: key);
  @override
  _AddRolePageState createState() => _AddRolePageState();
}

class _AddRolePageState extends State<AddRole> {
  final nameController = TextEditingController();
  final Set<String> selectedPermissionIds = {};

  List<PermissionOption> permissions = [];
  bool isLoadingPermissions = true;
  bool isSaving = false;

  @override
  void initState() {
    super.initState();
    _loadPermissions();
  }

  @override
  void dispose() {
    nameController.dispose();
    super.dispose();
  }

  Future<void> _loadPermissions() async {
    setState(() => isLoadingPermissions = true);
    try {
      final result = await IdentityRepository.instance.listPermissions();
      final items = (result.data as List).cast<Map<String, dynamic>>();
      permissions = items.map(PermissionOption.fromJson).toList();
    } on ApiException catch (e) {
      showAppMessage(context, e.message);
    } catch (e) {
      showAppMessage(context, 'Could not reach the server. Please try again.');
    }
    setState(() => isLoadingPermissions = false);
  }

  Future<void> _createRole() async {
    final name = nameController.text.trim();
    if (name.isEmpty) {
      showAppMessage(context, 'Please enter a role name');
      return;
    }

    setState(() => isSaving = true);
    try {
      await IdentityRepository.instance.createRole(
        name: name,
        permissionIds: selectedPermissionIds.toList(),
      );
      showAppMessage(context, 'Role created successfully', isError: false);
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
