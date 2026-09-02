import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../RolesView.dart';
import '../api/api_exception.dart';
import 'repository_providers.dart';

class RolesViewState {
  final bool isRolesVisible;
  final bool isUserVisible;
  final bool isLoading;
  final bool isVisibleNoRoleFound;
  final List<RoleModel> roles;
  final List<RoleModel> filteredRoles;
  final String company;
  final String? errorMessage;

  const RolesViewState({
    this.isRolesVisible = true,
    this.isUserVisible = true,
    this.isLoading = false,
    this.isVisibleNoRoleFound = false,
    this.roles = const [],
    this.filteredRoles = const [],
    this.company = '',
    this.errorMessage,
  });

  RolesViewState copyWith({
    bool? isRolesVisible,
    bool? isUserVisible,
    bool? isLoading,
    bool? isVisibleNoRoleFound,
    List<RoleModel>? roles,
    List<RoleModel>? filteredRoles,
    String? company,
    String? errorMessage,
    bool clearError = false,
  }) {
    return RolesViewState(
      isRolesVisible: isRolesVisible ?? this.isRolesVisible,
      isUserVisible: isUserVisible ?? this.isUserVisible,
      isLoading: isLoading ?? this.isLoading,
      isVisibleNoRoleFound: isVisibleNoRoleFound ?? this.isVisibleNoRoleFound,
      roles: roles ?? this.roles,
      filteredRoles: filteredRoles ?? this.filteredRoles,
      company: company ?? this.company,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    );
  }
}

class RolesViewNotifier extends StateNotifier<RolesViewState> {
  final Ref _ref;
  String _searchQuery = '';

  RolesViewNotifier(this._ref) : super(const RolesViewState()) {
    _init();
  }

  void clearError() {
    state = state.copyWith(clearError: true);
  }

  Future<void> _init() async {
    final prefs = await SharedPreferences.getInstance();
    final company = prefs.getString('company_name') ?? '';
    final securityAccess = prefs.getString('secbtnaccess');
    final visible = securityAccess == 'True';
    state = state.copyWith(
      company: company,
      isRolesVisible: visible,
      isUserVisible: visible,
    );
    await fetchRoles();
  }

  void filterRoles(String query) {
    _searchQuery = query;
    if (query.trim().isEmpty) {
      state = state.copyWith(filteredRoles: List.from(state.roles));
    } else {
      state = state.copyWith(
        filteredRoles: state.roles
            .where((r) => r.name.toLowerCase().contains(query.toLowerCase()))
            .toList(),
      );
    }
  }

  /// The role's own company scoping now comes from the company-user
  /// session's token (see company-role.controller.ts's `findAll`), not a
  /// `serialno` in the request body - no param needed here anymore.
  Future<void> fetchRoles() async {
    state = state.copyWith(isLoading: true);
    try {
      final result =
          await _ref.read(identityRepositoryProvider).listRoles(limit: 100);
      final items = (result.data as List).cast<Map<String, dynamic>>();
      final roles = items.map(RoleModel.fromJson).toList();
      final filtered = _searchQuery.trim().isEmpty
          ? List<RoleModel>.from(roles)
          : roles
              .where((r) =>
                  r.name.toLowerCase().contains(_searchQuery.toLowerCase()))
              .toList();
      state = state.copyWith(
        roles: roles,
        filteredRoles: filtered,
        isVisibleNoRoleFound: roles.isEmpty,
        isLoading: false,
      );
    } on ApiException catch (e) {
      state = state.copyWith(isLoading: false, errorMessage: e.message);
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        errorMessage: 'Could not reach the server. Please try again.',
      );
    }
  }

  Future<RolesViewActionResult> deleteRole(
    String roleId,
    String roleName,
  ) async {
    state = state.copyWith(isLoading: true);
    try {
      await _ref.read(identityRepositoryProvider).deleteRole(roleId);
      await fetchRoles();
      return RolesViewActionResult(true, "Role '$roleName' deleted");
    } on ApiException catch (e) {
      state = state.copyWith(isLoading: false);
      return RolesViewActionResult(false, e.message);
    } catch (e) {
      state = state.copyWith(isLoading: false);
      return const RolesViewActionResult(
        false,
        'Could not reach the server. Please try again.',
      );
    }
  }
}

class RolesViewActionResult {
  final bool success;
  final String message;

  const RolesViewActionResult(this.success, this.message);
}

final rolesViewNotifierProvider =
    StateNotifierProvider.autoDispose<RolesViewNotifier, RolesViewState>(
  (ref) => RolesViewNotifier(ref),
);
