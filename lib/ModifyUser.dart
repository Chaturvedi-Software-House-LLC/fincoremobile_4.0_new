import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'UserView.dart';
import 'constants.dart';
import 'package:FincoreGo/widgets/app_bottom_nav.dart';
import 'widgets/entry_widgets.dart';
import 'widgets/searchable_selector.dart';
import 'providers/modify_user_notifier.dart';

/// tally-oauth's `CompanyUserUpdateDto` only supports `{roleId?, isActive?}`
/// - there is no endpoint for a company-user to change another
/// company-user's name/email/password (that's a `User`-level record, only
/// editable by the `User` themselves via `PATCH /user`, or by an EMPLOYEE).
/// So unlike the legacy screen, this no longer edits name/password - just
/// role and active status.
class ModifyUser extends ConsumerStatefulWidget {
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
  ConsumerState<ModifyUser> createState() => _ModifyUserPageState();
}

class _ModifyUserPageState extends ConsumerState<ModifyUser> {
  late final _args = ModifyUserArgs(
    companyUserId: widget.companyUserId,
    currentRoleId: widget.currentRoleId,
  );

  Future<void> _save() async {
    final result =
        await ref.read(modifyUserNotifierProvider(_args).notifier).save();
    if (!mounted) return;
    if (result.message != null) {
      showAppMessage(context, result.message!, isError: !result.success);
    }
    if (result.success) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => const UserView()),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = modifyUserNotifierProvider(_args);
    final vm = ref.watch(provider);
    final notifier = ref.read(provider.notifier);

    ref.listen<ModifyUserState>(provider, (previous, next) {
      if (next.loadError != null) {
        showAppMessage(context, next.loadError!);
        notifier.clearLoadError();
      }
    });

    final isLoading = vm.isLoading;
    final isSaving = vm.isSaving;
    final roles = vm.roles;
    final selectedRole = vm.selectedRole;
    final isActive = vm.isActive;

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
                            notifier.selectRole(value as Map<String, dynamic>),
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
                        onChanged: (value) => notifier.setActive(value),
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
