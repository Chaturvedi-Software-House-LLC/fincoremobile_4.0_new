import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../AddRole.dart';
import '../api/api_exception.dart';
import 'repository_providers.dart';

class AddRoleState {
  final List<PermissionOption> permissions;
  final Set<String> selectedPermissionIds;
  final bool isLoadingPermissions;
  final bool isSaving;
  // A load error to be surfaced once via `ref.listen` + [AddRoleNotifier.clearLoadError],
  // since the initial load runs before any widget can await it directly.
  final String? loadError;

  const AddRoleState({
    this.permissions = const [],
    this.selectedPermissionIds = const {},
    this.isLoadingPermissions = true,
    this.isSaving = false,
    this.loadError,
  });

  AddRoleState copyWith({
    List<PermissionOption>? permissions,
    Set<String>? selectedPermissionIds,
    bool? isLoadingPermissions,
    bool? isSaving,
    String? loadError,
    bool clearLoadError = false,
  }) {
    return AddRoleState(
      permissions: permissions ?? this.permissions,
      selectedPermissionIds:
          selectedPermissionIds ?? this.selectedPermissionIds,
      isLoadingPermissions: isLoadingPermissions ?? this.isLoadingPermissions,
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

/// Result of an action, so the widget can show a message/navigate without
/// the notifier reaching into `BuildContext`.
class AddRoleActionResult {
  final bool success;
  final String? message;

  const AddRoleActionResult(this.success, [this.message]);
}

class AddRoleNotifier extends StateNotifier<AddRoleState> {
  final Ref _ref;

  AddRoleNotifier(this._ref) : super(const AddRoleState()) {
    _loadPermissions();
  }

  Future<void> _loadPermissions() async {
    state = state.copyWith(isLoadingPermissions: true);
    try {
      final result =
          await _ref.read(identityRepositoryProvider).listPermissions();
      final items = (result.data as List).cast<Map<String, dynamic>>();
      state = state.copyWith(
        permissions: items.map(PermissionOption.fromJson).toList(),
        isLoadingPermissions: false,
      );
    } on ApiException catch (e) {
      state = state.copyWith(isLoadingPermissions: false, loadError: e.message);
    } catch (e) {
      state = state.copyWith(
        isLoadingPermissions: false,
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

  Future<AddRoleActionResult> createRole(String name) async {
    if (name.isEmpty) {
      return const AddRoleActionResult(false, 'Please enter a role name');
    }

    state = state.copyWith(isSaving: true);
    try {
      await _ref.read(identityRepositoryProvider).createRole(
        name: name,
        permissionIds: state.selectedPermissionIds.toList(),
      );
      state = state.copyWith(isSaving: false);
      return const AddRoleActionResult(true, 'Role created successfully');
    } on ApiException catch (e) {
      state = state.copyWith(isSaving: false);
      return AddRoleActionResult(false, e.message);
    } catch (e) {
      state = state.copyWith(isSaving: false);
      return const AddRoleActionResult(
        false,
        'Could not reach the server. Please try again.',
      );
    }
  }
}

final addRoleNotifierProvider =
    StateNotifierProvider.autoDispose<AddRoleNotifier, AddRoleState>(
  (ref) => AddRoleNotifier(ref),
);
