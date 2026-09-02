import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../api/api_exception.dart';
import 'repository_providers.dart';

class CreateUserState {
  final bool isRolesVisible;
  final bool isUserVisible;
  final bool isLoading;
  final List<Map<String, dynamic>> roles;
  final Map<String, dynamic>? selectedRole;
  final String company;
  final String username;
  final String? errorMessage;
  final String? successMessage;

  const CreateUserState({
    this.isRolesVisible = true,
    this.isUserVisible = true,
    this.isLoading = false,
    this.roles = const [],
    this.selectedRole,
    this.company = '',
    this.username = '',
    this.errorMessage,
    this.successMessage,
  });

  CreateUserState copyWith({
    bool? isRolesVisible,
    bool? isUserVisible,
    bool? isLoading,
    List<Map<String, dynamic>>? roles,
    Map<String, dynamic>? selectedRole,
    bool clearSelectedRole = false,
    String? company,
    String? username,
    String? errorMessage,
    bool clearError = false,
    String? successMessage,
    bool clearSuccess = false,
  }) {
    return CreateUserState(
      isRolesVisible: isRolesVisible ?? this.isRolesVisible,
      isUserVisible: isUserVisible ?? this.isUserVisible,
      isLoading: isLoading ?? this.isLoading,
      roles: roles ?? this.roles,
      selectedRole:
          clearSelectedRole ? null : (selectedRole ?? this.selectedRole),
      company: company ?? this.company,
      username: username ?? this.username,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      successMessage:
          clearSuccess ? null : (successMessage ?? this.successMessage),
    );
  }
}

class CreateUserNotifier extends StateNotifier<CreateUserState> {
  final Ref _ref;

  CreateUserNotifier(this._ref) : super(const CreateUserState()) {
    _init();
  }

  Future<void> _init() async {
    final prefs = await SharedPreferences.getInstance();
    final company = prefs.getString('company_name') ?? '';
    final username = prefs.getString('username') ?? '';
    final securityAccess = prefs.getString('secbtnaccess');
    final visible = securityAccess == 'True';
    state = state.copyWith(
      company: company,
      username: username,
      isRolesVisible: visible,
      isUserVisible: visible,
    );
    await fetchRoles();
  }

  void clearError() => state = state.copyWith(clearError: true);
  void clearSuccess() => state = state.copyWith(clearSuccess: true);

  void selectRole(Map<String, dynamic>? role) {
    if (role == null) {
      state = state.copyWith(clearSelectedRole: true);
    } else {
      state = state.copyWith(selectedRole: role);
    }
  }

  /// Company scoping now comes from the company-user session's token - no
  /// `serialno` param needed here anymore.
  Future<void> fetchRoles() async {
    try {
      final result =
          await _ref.read(identityRepositoryProvider).listRoles(limit: 100);
      final items = (result.data as List).cast<Map<String, dynamic>>();
      state = state.copyWith(
        roles: items,
        selectedRole: items.isNotEmpty ? items.first : null,
      );
    } on ApiException catch (e) {
      state = state.copyWith(errorMessage: e.message);
    } catch (e) {
      state = state.copyWith(
        errorMessage: 'Could not reach the server. Please try again.',
      );
    }
  }

  /// Creates (or reuses, per company-user.service.ts's create()) a `User`
  /// and links it to the current company-user session's company - unlike
  /// the legacy backend, there is no "allowed companies" multi-select
  /// concept: a company-user is always scoped to exactly one company (the
  /// one that's currently active), so that step is gone entirely.
  ///
  /// Returns the (name, password, email-or-null) needed for the credentials
  /// email on success, so the widget can send it - notifiers shouldn't own
  /// SMTP/UI side effects.
  Future<({bool success, String? emailToNotify, String? password})>
      userRegistration({
    required String userNameOrEmail,
    required String password,
    required String roleId,
    required String name,
    required bool isEmailLogin,
  }) async {
    state = state.copyWith(isLoading: true);

    final nameParts = name.trim().split(RegExp(r'\s+'));
    final firstName = nameParts.first;
    final lastName =
        nameParts.length > 1 ? nameParts.sublist(1).join(' ') : firstName;

    try {
      await _ref.read(identityRepositoryProvider).createCompanyUser(
        userName: userNameOrEmail,
        firstName: firstName,
        lastName: lastName,
        password: password,
        roleId: roleId,
        email: isEmailLogin ? userNameOrEmail : null,
      );

      state = state.copyWith(
        isLoading: false,
        successMessage: 'User created successfully',
      );
      return (
        success: true,
        emailToNotify: isEmailLogin ? userNameOrEmail : null,
        password: password,
      );
    } on ApiException catch (e) {
      state = state.copyWith(isLoading: false, errorMessage: e.message);
      return (success: false, emailToNotify: null, password: null);
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        errorMessage: 'Could not reach the server. Please try again.',
      );
      return (success: false, emailToNotify: null, password: null);
    }
  }
}

final createUserNotifierProvider =
    StateNotifierProvider.autoDispose<CreateUserNotifier, CreateUserState>(
  (ref) => CreateUserNotifier(ref),
);
