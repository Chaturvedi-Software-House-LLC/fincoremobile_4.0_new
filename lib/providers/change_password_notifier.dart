import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/api_exception.dart';
import 'repository_providers.dart';

/// Legacy-style single-step flow: old password + new password + confirm,
/// verified against the account's current stored password - no OTP/email
/// step (see `AuthRepository.changePasswordWithOldPassword` and
/// tally-admin-api's `POST /auth/user/change-password-with-old`, added
/// specifically to restore this - the account's `id` comes from the
/// normal user access token already attached to the request, so unlike
/// the old OTP flow this doesn't need the username/email at all).
class ChangePasswordState {
  final bool isLoading;
  final bool showNewPassValidation;
  final bool showConfirmValidation;
  // Matches tally-admin-api's PasswordSchema - only length and one special
  // character are required now (lowercase/uppercase/number rules were
  // dropped from both sides - see CreateUser.dart's matching change).
  final bool hasSpecial;
  final bool isMatch;
  final bool isOldPassVisible;
  final bool isNewPassVisible;
  final bool isConfirmPassVisible;

  const ChangePasswordState({
    this.isLoading = false,
    this.showNewPassValidation = false,
    this.showConfirmValidation = false,
    this.hasSpecial = false,
    this.isMatch = false,
    this.isOldPassVisible = false,
    this.isNewPassVisible = false,
    this.isConfirmPassVisible = false,
  });

  ChangePasswordState copyWith({
    bool? isLoading,
    bool? showNewPassValidation,
    bool? showConfirmValidation,
    bool? hasSpecial,
    bool? isMatch,
    bool? isOldPassVisible,
    bool? isNewPassVisible,
    bool? isConfirmPassVisible,
  }) {
    return ChangePasswordState(
      isLoading: isLoading ?? this.isLoading,
      showNewPassValidation:
          showNewPassValidation ?? this.showNewPassValidation,
      showConfirmValidation:
          showConfirmValidation ?? this.showConfirmValidation,
      hasSpecial: hasSpecial ?? this.hasSpecial,
      isMatch: isMatch ?? this.isMatch,
      isOldPassVisible: isOldPassVisible ?? this.isOldPassVisible,
      isNewPassVisible: isNewPassVisible ?? this.isNewPassVisible,
      isConfirmPassVisible: isConfirmPassVisible ?? this.isConfirmPassVisible,
    );
  }
}

/// Result of a submit attempt, so the widget can show a message without the
/// notifier reaching into `BuildContext`.
class ChangePasswordResult {
  final bool success;
  final String message;

  const ChangePasswordResult(this.success, this.message);
}

class ChangePasswordNotifier extends StateNotifier<ChangePasswordState> {
  final Ref _ref;

  ChangePasswordNotifier(this._ref) : super(const ChangePasswordState());

  void validateNewPassword(String value, String confirmText) {
    state = state.copyWith(
      showNewPassValidation: value.isNotEmpty,
      hasSpecial: RegExp(r'[^a-zA-Z0-9]').hasMatch(value),
      isMatch: value == confirmText,
    );
  }

  void validateConfirmPassword(String value, String newPassText) {
    state = state.copyWith(
      showConfirmValidation: value.isNotEmpty,
      isMatch: value == newPassText,
    );
  }

  void toggleOldPassVisible() {
    state = state.copyWith(isOldPassVisible: !state.isOldPassVisible);
  }

  void toggleNewPassVisible() {
    state = state.copyWith(isNewPassVisible: !state.isNewPassVisible);
  }

  void toggleConfirmPassVisible() {
    state = state.copyWith(isConfirmPassVisible: !state.isConfirmPassVisible);
  }

  Future<ChangePasswordResult> changePassword({
    required String oldPassword,
    required String newPassword,
  }) async {
    state = state.copyWith(isLoading: true);
    try {
      await _ref.read(authRepositoryProvider).changePasswordWithOldPassword(
            oldPassword: oldPassword,
            newPassword: newPassword,
          );
      state = state.copyWith(
        isLoading: false,
        showNewPassValidation: false,
        showConfirmValidation: false,
        hasSpecial: false,
        isMatch: false,
      );
      return const ChangePasswordResult(
        true,
        'Password changed successfully.',
      );
    } on ApiException catch (e) {
      state = state.copyWith(isLoading: false);
      // The backend's own wording ("Current password is incorrect") is
      // already clear - surfaced as-is rather than overridden.
      return ChangePasswordResult(false, e.message);
    } catch (e) {
      state = state.copyWith(isLoading: false);
      return const ChangePasswordResult(
        false,
        'Could not reach the server. Please try again.',
      );
    }
  }
}

final changePasswordNotifierProvider =
    StateNotifierProvider.autoDispose<ChangePasswordNotifier, ChangePasswordState>(
  (ref) => ChangePasswordNotifier(ref),
);
