import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../RolesView.dart';
import '../api/api_exception.dart';
import 'repository_providers.dart';

class RolesViewState {
  final bool isRolesVisible;
  final bool isUserVisible;
  final bool isLoading;
  final bool isLoadingMore;
  final bool isVisibleNoRoleFound;
  final List<RoleModel> roles;
  final List<RoleModel> filteredRoles;
  final String company;
  final String? errorMessage;

  const RolesViewState({
    this.isRolesVisible = true,
    this.isUserVisible = true,
    this.isLoading = false,
    this.isLoadingMore = false,
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
    bool? isLoadingMore,
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
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
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

  static const int _pageLimit = 20;
  int _requestGen = 0;
  int? _nextPage = 2;
  int _totalPages = 1;

  bool get canLoadMoreRoles => _nextPage != null;

  RolesViewNotifier(this._ref) : super(const RolesViewState()) {
    _init();
  }

  void clearError() {
    state = state.copyWith(clearError: true);
  }

  Future<void> _init() async {
    final prefs = await SharedPreferences.getInstance();
    // This provider is invalidated on every RolesView entry (see
    // RolesView.dart's initState - forces a fresh fetch rather than
    // trusting a stale instance survived a company switch), which can
    // dispose this very instance while the `await` above is still
    // in-flight. Checking `mounted` after every await point below avoids
    // "Tried to use RolesViewNotifier after `dispose` was called" - a
    // disposed instance's in-flight work should just stop, not crash.
    if (!mounted) return;
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
    final filtered = query.trim().isEmpty
        ? List<RoleModel>.from(state.roles)
        : state.roles
            .where((r) => r.name.toLowerCase().contains(query.toLowerCase()))
            .toList();
    state = state.copyWith(
      filteredRoles: filtered,
      isVisibleNoRoleFound: filtered.isEmpty,
    );
  }

  /// The role's own company scoping now comes from the company-user
  /// session's token (see company-role.controller.ts's `findAll`), not a
  /// `serialno` in the request body - no param needed here anymore.
  Future<void> fetchRoles() async {
    if (!mounted) return;
    final myGen = ++_requestGen;
    state = state.copyWith(isLoading: true);
    try {
      final result = await _ref
          .read(identityRepositoryProvider)
          .listRoles(page: 1, limit: _pageLimit);
      if (!mounted || myGen != _requestGen) return;
      final items = (result.data as List).cast<Map<String, dynamic>>();
      final roles = items.map(RoleModel.fromJson).toList();

      _totalPages = (result.meta?['lastPage'] as int?) ?? 1;
      _nextPage = _totalPages > 1 ? 2 : null;

      final filtered = _searchQuery.trim().isEmpty
          ? List<RoleModel>.from(roles)
          : roles
              .where((r) =>
                  r.name.toLowerCase().contains(_searchQuery.toLowerCase()))
              .toList();
      state = state.copyWith(
        roles: roles,
        filteredRoles: filtered,
        isVisibleNoRoleFound: filtered.isEmpty && _nextPage == null,
        isLoading: false,
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      state = state.copyWith(isLoading: false, errorMessage: e.message);
    } catch (e) {
      if (!mounted) return;
      state = state.copyWith(
        isLoading: false,
        errorMessage: 'Could not reach the server. Please try again.',
      );
    }
  }

  /// Fetches the next page of roles and appends it - called by
  /// `RolesView.dart`'s `ScrollController` listener when the user scrolls
  /// near the bottom.
  Future<void> loadMoreRoles() async {
    if (!mounted || state.isLoadingMore) return;
    final page = _nextPage;
    if (page == null || page > _totalPages) {
      _nextPage = null;
      return;
    }
    final myGen = _requestGen;
    state = state.copyWith(isLoadingMore: true);
    try {
      final result = await _ref
          .read(identityRepositoryProvider)
          .listRoles(page: page, limit: _pageLimit);
      if (!mounted || myGen != _requestGen) {
        if (mounted) state = state.copyWith(isLoadingMore: false);
        return;
      }
      final items = (result.data as List).cast<Map<String, dynamic>>();
      final newRoles = items.map(RoleModel.fromJson).toList();
      final roles = [...state.roles, ...newRoles];
      _nextPage = page + 1 <= _totalPages ? page + 1 : null;

      final filtered = _searchQuery.trim().isEmpty
          ? List<RoleModel>.from(roles)
          : roles
              .where((r) =>
                  r.name.toLowerCase().contains(_searchQuery.toLowerCase()))
              .toList();
      state = state.copyWith(
        roles: roles,
        filteredRoles: filtered,
        isVisibleNoRoleFound: filtered.isEmpty && _nextPage == null,
        isLoadingMore: false,
      );
    } catch (e) {
      if (mounted && myGen == _requestGen) {
        state = state.copyWith(isLoadingMore: false);
      }
    }
  }

  Future<RolesViewActionResult> deleteRole(
    String roleId,
    String roleName,
  ) async {
    if (!mounted) return const RolesViewActionResult(false, '');
    state = state.copyWith(isLoading: true);
    try {
      await _ref.read(identityRepositoryProvider).deleteRole(roleId);
      await fetchRoles();
      return RolesViewActionResult(true, "Role '$roleName' deleted");
    } on ApiException catch (e) {
      if (mounted) state = state.copyWith(isLoading: false);
      return RolesViewActionResult(false, e.message);
    } catch (e) {
      if (mounted) state = state.copyWith(isLoading: false);
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
