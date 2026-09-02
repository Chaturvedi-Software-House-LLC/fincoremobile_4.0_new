import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/api_exception.dart';
import '../api/base_api_client.dart';
import 'repository_providers.dart';

class ModifyUserArgs {
  final String companyUserId;
  final String currentRoleId;

  const ModifyUserArgs({
    required this.companyUserId,
    required this.currentRoleId,
  });

  @override
  bool operator ==(Object other) =>
      other is ModifyUserArgs &&
      other.companyUserId == companyUserId &&
      other.currentRoleId == currentRoleId;

  @override
  int get hashCode => Object.hash(companyUserId, currentRoleId);
}

class ModifyUserState {
  final List<Map<String, dynamic>> roles;
  final Map<String, dynamic>? selectedRole;
  final bool isActive;
  final bool isLoading;
  final bool isSaving;
  final String? loadError;

  const ModifyUserState({
    this.roles = const [],
    this.selectedRole,
    this.isActive = true,
    this.isLoading = true,
    this.isSaving = false,
    this.loadError,
  });

  ModifyUserState copyWith({
    List<Map<String, dynamic>>? roles,
    Map<String, dynamic>? selectedRole,
    bool clearSelectedRole = false,
    bool? isActive,
    bool? isLoading,
    bool? isSaving,
    String? loadError,
    bool clearLoadError = false,
  }) {
    return ModifyUserState(
      roles: roles ?? this.roles,
      selectedRole:
          clearSelectedRole ? null : (selectedRole ?? this.selectedRole),
      isActive: isActive ?? this.isActive,
      isLoading: isLoading ?? this.isLoading,
      isSaving: isSaving ?? this.isSaving,
      loadError: clearLoadError ? null : (loadError ?? this.loadError),
    );
  }
}

class ModifyUserActionResult {
  final bool success;
  final String? message;

  const ModifyUserActionResult(this.success, [this.message]);
}

class ModifyUserNotifier extends StateNotifier<ModifyUserState> {
  final Ref _ref;
  final ModifyUserArgs args;

  ModifyUserNotifier(this._ref, this.args) : super(const ModifyUserState()) {
    _load();
  }

  Future<void> _load() async {
    state = state.copyWith(isLoading: true);
    try {
      final repo = _ref.read(identityRepositoryProvider);
      final results = await Future.wait([
        repo.listRoles(limit: 100),
        repo.getCompanyUser(args.companyUserId),
      ]);

      final roleItems = ((results[0] as ApiResult).data as List)
          .cast<Map<String, dynamic>>();
      final companyUser = results[1] as Map<String, dynamic>;

      final selectedRole = roleItems.firstWhere(
        (r) => r['id'] == args.currentRoleId,
        orElse: () => roleItems.isNotEmpty ? roleItems.first : <String, dynamic>{},
      );

      state = state.copyWith(
        roles: roleItems,
        selectedRole: selectedRole,
        isActive: companyUser['isActive'] as bool? ?? true,
        isLoading: false,
      );
    } on ApiException catch (e) {
      state = state.copyWith(isLoading: false, loadError: e.message);
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        loadError: 'Could not reach the server. Please try again.',
      );
    }
  }

  void clearLoadError() {
    state = state.copyWith(clearLoadError: true);
  }

  void selectRole(Map<String, dynamic> role) {
    state = state.copyWith(selectedRole: role);
  }

  void setActive(bool value) {
    state = state.copyWith(isActive: value);
  }

  Future<ModifyUserActionResult> save() async {
    final roleId = state.selectedRole?['id'];
    if (roleId == null) {
      return const ModifyUserActionResult(false, 'Please choose a role');
    }

    state = state.copyWith(isSaving: true);
    try {
      await _ref.read(identityRepositoryProvider).updateCompanyUser(
        args.companyUserId,
        roleId: roleId as String,
        isActive: state.isActive,
      );
      state = state.copyWith(isSaving: false);
      return const ModifyUserActionResult(true, 'User updated successfully');
    } on ApiException catch (e) {
      state = state.copyWith(isSaving: false);
      return ModifyUserActionResult(false, e.message);
    } catch (e) {
      state = state.copyWith(isSaving: false);
      return const ModifyUserActionResult(
        false,
        'Could not reach the server. Please try again.',
      );
    }
  }
}

final modifyUserNotifierProvider = StateNotifierProvider.autoDispose
    .family<ModifyUserNotifier, ModifyUserState, ModifyUserArgs>(
  (ref, args) => ModifyUserNotifier(ref, args),
);
