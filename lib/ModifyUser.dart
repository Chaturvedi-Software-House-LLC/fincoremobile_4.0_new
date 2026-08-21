import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'UserView.dart';
import 'constants.dart';
import 'package:FincoreGo/widgets/app_bottom_nav.dart';
import 'widgets/entry_widgets.dart';
import 'widgets/searchable_selector.dart';
import 'api/api_exception.dart';
import 'api/base_api_client.dart';
import 'api/identity_repository.dart';

/// tally-oauth's `CompanyUserUpdateDto` only supports `{roleId?, isActive?}`
/// - there is no endpoint for a company-user to change another
/// company-user's name/email/password (that's a `User`-level record, only
/// editable by the `User` themselves via `PATCH /user`, or by an EMPLOYEE).
/// So unlike the legacy screen, this no longer edits name/password - just
/// role and active status.
class ModifyUser extends StatefulWidget {
  final String companyUserId;
  final String userName;
  final String currentRoleId;

  const ModifyUser({
    Key? key,
    required this.companyUserId,
    required this.userName,
    required this.currentRoleId,
  }) : super(key: key);

  @override
  _ModifyUserPageState createState() => _ModifyUserPageState();
}

class _ModifyUserPageState extends State<ModifyUser> {
  List<Map<String, dynamic>> roles = [];
  Map<String, dynamic>? selectedRole;
  bool isActive = true;

  bool isLoading = true;
  bool isSaving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => isLoading = true);
    try {
      final results = await Future.wait([
        IdentityRepository.instance.listRoles(limit: 100),
        IdentityRepository.instance.getCompanyUser(widget.companyUserId),
      ]);

      final roleItems = ((results[0] as ApiResult).data as List)
          .cast<Map<String, dynamic>>();
      final companyUser = results[1] as Map<String, dynamic>;

      roles = roleItems;
      selectedRole = roles.firstWhere(
        (r) => r['id'] == widget.currentRoleId,
        orElse: () => roles.isNotEmpty ? roles.first : <String, dynamic>{},
      );
      isActive = companyUser['isActive'] as bool? ?? true;
    } on ApiException catch (e) {
      showAppMessage(context, e.message);
    } catch (e) {
      showAppMessage(context, 'Could not reach the server. Please try again.');
    }
    setState(() => isLoading = false);
  }

  Future<void> _save() async {
    if (selectedRole == null || selectedRole!['id'] == null) {
      showAppMessage(context, 'Please choose a role');
      return;
    }

    setState(() => isSaving = true);
    try {
      await IdentityRepository.instance.updateCompanyUser(
        widget.companyUserId,
        roleId: selectedRole!['id'] as String,
        isActive: isActive,
      );
      showAppMessage(context, 'User updated successfully', isError: false);
      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => const UserView()),
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      bottomNavigationBar: const AppBottomNav(
        activeTab: AppBottomNavTab.more,
        activeMoreItem: AppMoreItem.users,
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
            'User Modification',
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
              padding: const EdgeInsets.all(16),
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 20,
                  ),
                  decoration: BoxDecoration(
                    color: Theme.of(context).cardColor,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: CircleAvatar(
                          backgroundColor: app_color.withOpacity(0.1),
                          radius: 22,
                          child: Icon(Icons.person, color: app_color),
                        ),
                        title: Text(
                          widget.userName,
                          style: GoogleFonts.poppins(
                            fontSize: 17,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Role',
                        style: GoogleFonts.poppins(fontWeight: FontWeight.w500),
                      ),
                      const SizedBox(height: 8),
                      SearchableSelectorField<dynamic>(
                        value: selectedRole,
                        items: roles,
                        itemLabel: (item) => (item['name'] ?? '').toString(),
                        hintText: 'Choose a role',
                        onChanged: (value) =>
                            setState(() => selectedRole = value),
                      ),
                      const SizedBox(height: 8),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(
                          'Active',
                          style: GoogleFonts.poppins(fontWeight: FontWeight.w500),
                        ),
                        value: isActive,
                        activeColor: app_color,
                        onChanged: (value) => setState(() => isActive = value),
                      ),
                      const SizedBox(height: 20),
                      ElevatedButton(
                        onPressed: isSaving ? null : _save,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: app_color,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: isSaving
                            ? const SizedBox(
                                height: 20,
                                width: 20,
                                child: CupertinoActivityIndicator(
                                  radius: 10,
                                  color: Colors.white,
                                ),
                              )
                            : Text(
                                'Save Changes',
                                style: GoogleFonts.poppins(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}
