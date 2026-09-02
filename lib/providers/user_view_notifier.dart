import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../UserView.dart';
import '../api/api_exception.dart';
import 'repository_providers.dart';

int _compareUsers(UserModel a, UserModel b) => a.name.compareTo(b.name);

class UserViewState {
  final bool isRolesVisible;
  final bool isUserVisible;
  final bool isLoading;
  final bool isVisibleNoUserFound;
  final List<UserModel> users;
  final List<UserModel> filteredUsers;
  final String company;
  final String? errorMessage;

  const UserViewState({
    this.isRolesVisible = true,
    this.isUserVisible = true,
    this.isLoading = false,
    this.isVisibleNoUserFound = false,
    this.users = const [],
    this.filteredUsers = const [],
    this.company = '',
    this.errorMessage,
  });

  UserViewState copyWith({
    bool? isRolesVisible,
    bool? isUserVisible,
    bool? isLoading,
    bool? isVisibleNoUserFound,
    List<UserModel>? users,
    List<UserModel>? filteredUsers,
    String? company,
    String? errorMessage,
    bool clearError = false,
  }) {
    return UserViewState(
      isRolesVisible: isRolesVisible ?? this.isRolesVisible,
      isUserVisible: isUserVisible ?? this.isUserVisible,
      isLoading: isLoading ?? this.isLoading,
      isVisibleNoUserFound: isVisibleNoUserFound ?? this.isVisibleNoUserFound,
      users: users ?? this.users,
      filteredUsers: filteredUsers ?? this.filteredUsers,
      company: company ?? this.company,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    );
  }
}

class UserViewActionResult {
  final bool success;
  final String message;

  const UserViewActionResult(this.success, this.message);
}

class UserViewNotifier extends StateNotifier<UserViewState> {
  final Ref _ref;
  String _searchQuery = '';

  UserViewNotifier(this._ref) : super(const UserViewState()) {
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
    await fetchUsers();
  }

  void filterUsers(String query) {
    _searchQuery = query;
    if (query.trim().isEmpty) {
      state = state.copyWith(filteredUsers: List.from(state.users));
    } else {
      final lower = query.toLowerCase();
      state = state.copyWith(
        filteredUsers: state.users
            .where((u) =>
                u.name.toLowerCase().contains(lower) ||
                u.email.toLowerCase().contains(lower) ||
                u.roleName.toLowerCase().contains(lower))
            .toList(),
      );
    }
  }

  /// Company scoping now comes from the company-user session's token (see
  /// company-user.controller.ts's `findAll`), not a `serialno` in the
  /// request body - no param needed here anymore.
  Future<void> fetchUsers() async {
    state = state.copyWith(isLoading: true);
    try {
      final result = await _ref
          .read(identityRepositoryProvider)
          .listCompanyUsers(limit: 100);
      final items = (result.data as List).cast<Map<String, dynamic>>();

      final users = items.map(UserModel.fromJson).toList()
        ..sort(_compareUsers);
      final filtered = (_searchQuery.trim().isEmpty
          ? List<UserModel>.from(users)
          : users.where((u) {
              final lower = _searchQuery.toLowerCase();
              return u.name.toLowerCase().contains(lower) ||
                  u.email.toLowerCase().contains(lower) ||
                  u.roleName.toLowerCase().contains(lower);
            }).toList())
        ..sort(_compareUsers);

      state = state.copyWith(
        users: users,
        filteredUsers: filtered,
        isVisibleNoUserFound: users.isEmpty ? true : state.isVisibleNoUserFound,
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

  Future<UserViewActionResult> deleteUser(String companyUserId) async {
    state = state.copyWith(isLoading: true);
    try {
      await _ref.read(identityRepositoryProvider).deleteCompanyUser(companyUserId);
      await fetchUsers();
      return const UserViewActionResult(true, 'User deleted');
    } on ApiException catch (e) {
      state = state.copyWith(isLoading: false);
      return UserViewActionResult(false, e.message);
    } catch (e) {
      state = state.copyWith(isLoading: false);
      return const UserViewActionResult(
        false,
        'Could not reach the server. Please try again.',
      );
    }
  }
}

final userViewNotifierProvider =
    StateNotifierProvider.autoDispose<UserViewNotifier, UserViewState>(
  (ref) => UserViewNotifier(ref),
);
