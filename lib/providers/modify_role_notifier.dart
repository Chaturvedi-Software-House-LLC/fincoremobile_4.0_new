import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../AddRole.dart';
import '../api/api_exception.dart';
import '../api/base_api_client.dart';
import 'repository_providers.dart';

class ModifyRoleState {
  final String name;
  final List<PermissionOption> permissions;
  final Set<String> selectedPermissionIds;
  final bool isLoading;
  final bool isSaving;
  final String? loadError;

  const ModifyRoleState({
    this.name = '',
    this.permissions = const [],
    this.selectedPermissionIds = const {},
    this.isLoading = true,
    this.isSaving = false,
    this.loadError,
  });

  ModifyRoleState copyWith({
    String? name,
    List<PermissionOption>? permissions,
    Set<String>? selectedPermissionIds,
    bool? isLoading,
    bool? isSaving,
    String? loadError,
    bool clearLoadError = false,
  }) {
    return ModifyRoleState(
      name: name ?? this.name,
      permissions: permissions ?? this.permissions,
      selectedPermissionIds:
          selectedPermissionIds ?? this.selectedPermissionIds,
      isLoading: isLoading ?? this.isLoading,
      isSaving: isSaving ?? this.isSaving,
      loadError: clearLoadError ? null : (loadError ?? this.loadError),
    );
  }

  Map<String, List<PermissionOption>> get groupedPermissions {
    final grouped = <String, List<PermissionOption>>{};
    for (final permission in permissions) {
      grouped.putIfAbsent(permission.group, () => []).add(permission);
    }
    return grouped;
  }
}

class ModifyRoleActionResult {
  final bool success;
  final String? message;

  const ModifyRoleActionResult(this.success, [this.message]);
}

class ModifyRoleNotifier extends StateNotifier<ModifyRoleState> {
  final Ref _ref;
  final String roleId;

  ModifyRoleNotifier(this._ref, this.roleId) : super(const ModifyRoleState()) {
    _load();
  }

  Future<void> _load() async {
    state = state.copyWith(isLoading: true);
    try {
      final repo = _ref.read(identityRepositoryProvider);
      final results = await Future.wait([
        repo.listPermissions(),
        repo.getRole(roleId),
      ]);

      final permissionItems = ((results[0] as ApiResult).data as List)
          .cast<Map<String, dynamic>>();
      final permissions =
          permissionItems.map(PermissionOption.fromJson).toList();

      final role = results[1] as Map<String, dynamic>;
      final name = role['name'] as String;

      // Each item is `{permision: {id, ...}}` - see the misspelled key
      // note in identity_repository.dart's listRoles doc-comment.
      final grantedPermissions = (role['permissions'] as List? ?? const [])
          .cast<Map<String, dynamic>>();
      final selectedPermissionIds = grantedPermissions
          .map(
            (p) => (p['permision'] as Map<String, dynamic>)['id'] as String,
          )
          .toSet();

      state = state.copyWith(
        name: name,
        permissions: permissions,
        selectedPermissionIds: selectedPermissionIds,
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

  void togglePermission(String permissionId, bool checked) {
    final updated = Set<String>.from(state.selectedPermissionIds);
    if (checked) {
      updated.add(permissionId);
    } else {
      updated.remove(permissionId);
    }
    state = state.copyWith(selectedPermissionIds: updated);
  }

  Future<ModifyRoleActionResult> saveRole(String name) async {
    if (name.isEmpty) {
      return const ModifyRoleActionResult(false, 'Please enter a role name');
    }

    state = state.copyWith(isSaving: true);
    try {
      await _ref.read(identityRepositoryProvider).updateRole(
        roleId,
        name: name,
        permissionIds: state.selectedPermissionIds.toList(),
      );
      state = state.copyWith(isSaving: false);
      return const ModifyRoleActionResult(true, 'Role updated successfully');
    } on ApiException catch (e) {
      state = state.copyWith(isSaving: false);
      return ModifyRoleActionResult(false, e.message);
    } catch (e) {
      state = state.copyWith(isSaving: false);
      return const ModifyRoleActionResult(
        false,
        'Could not reach the server. Please try again.',
      );
    }
  }
}

final modifyRoleNotifierProvider = StateNotifierProvider.autoDispose
    .family<ModifyRoleNotifier, ModifyRoleState, String>(
  (ref, roleId) => ModifyRoleNotifier(ref, roleId),
);
