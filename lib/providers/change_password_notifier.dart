import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../api/api_exception.dart';
import 'repository_providers.dart';

class ChangePasswordState {
  final String username;
  // Set once step 1 (send OTP) succeeds - the short-lived token from
  // `reset-password` that authorizes the actual `change-password` call.
  final String? resetToken;
  final bool isLoading;
  final bool showNewPassValidation;
  final bool showConfirmValidation;
  final bool hasLower;
  final bool hasUpper;
  final bool hasNumber;
  final bool isMatch;
  final bool isNewPassVisible;
  final bool isConfirmPassVisible;
  final bool isOtpVisible;

  const ChangePasswordState({
    this.username = '',
    this.resetToken,
    this.isLoading = false,
    this.showNewPassValidation = false,
    this.showConfirmValidation = false,
    this.hasLower = false,
    this.hasUpper = false,
    this.hasNumber = false,
    this.isMatch = false,
    this.isNewPassVisible = false,
    this.isConfirmPassVisible = false,
    this.isOtpVisible = false,
  });

  ChangePasswordState copyWith({
    String? username,
    String? resetToken,
    bool clearResetToken = false,
    bool? isLoading,
    bool? showNewPassValidation,
    bool? showConfirmValidation,
    bool? hasLower,
    bool? hasUpper,
    bool? hasNumber,
    bool? isMatch,
    bool? isNewPassVisible,
    bool? isConfirmPassVisible,
    bool? isOtpVisible,
  }) {
    return ChangePasswordState(
      username: username ?? this.username,
      resetToken: clearResetToken ? null : (resetToken ?? this.resetToken),
      isLoading: isLoading ?? this.isLoading,
      showNewPassValidation:
          showNewPassValidation ?? this.showNewPassValidation,
      showConfirmValidation:
          showConfirmValidation ?? this.showConfirmValidation,
      hasLower: hasLower ?? this.hasLower,
      hasUpper: hasUpper ?? this.hasUpper,
      hasNumber: hasNumber ?? this.hasNumber,
      isMatch: isMatch ?? this.isMatch,
      isNewPassVisible: isNewPassVisible ?? this.isNewPassVisible,
      isConfirmPassVisible: isConfirmPassVisible ?? this.isConfirmPassVisible,
      isOtpVisible: isOtpVisible ?? this.isOtpVisible,
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

  ChangePasswordNotifier(this._ref) : super(const ChangePasswordState()) {
    _loadSession();
  }

  Future<void> _loadSession() async {
    final prefs = await SharedPreferences.getInstance();
    final username = prefs.getString('username') ?? '';
    state = state.copyWith(username: username);
  }

  void validateNewPassword(String value, String confirmText) {
    state = state.copyWith(
      showNewPassValidation: value.isNotEmpty,
      hasLower: RegExp(r'[a-z]').hasMatch(value),
      hasUpper: RegExp(r'[A-Z]').hasMatch(value),
      hasNumber: RegExp(r'[0-9]').hasMatch(value),
      isMatch: value == confirmText,
    );
  }

  void validateConfirmPassword(String value, String newPassText) {
    state = state.copyWith(
      showConfirmValidation: value.isNotEmpty,
      isMatch: value == newPassText,
    );
  }

  void toggleNewPassVisible() {
    state = state.copyWith(isNewPassVisible: !state.isNewPassVisible);
  }

  void toggleConfirmPassVisible() {
    state = state.copyWith(isConfirmPassVisible: !state.isConfirmPassVisible);
  }

  void toggleOtpVisible() {
    state = state.copyWith(isOtpVisible: !state.isOtpVisible);
  }

  /// Step 1 of the tally-oauth OTP flow - sends an OTP to the account's
  /// email and stashes the short-lived reset token step 2 needs.
  Future<ChangePasswordResult> sendOtp() async {
    state = state.copyWith(isLoading: true);
    try {
      final token = await _ref
          .read(authRepositoryProvider)
          .requestPasswordResetOtp(username: state.username);
      state = state.copyWith(resetToken: token, isLoading: false);
      return const ChangePasswordResult(
        true,
        'OTP sent to your registered email.',
      );
    } on ApiException catch (e) {
      state = state.copyWith(isLoading: false);
      return ChangePasswordResult(false, e.message);
    } catch (e) {
      state = state.copyWith(isLoading: false);
      return const ChangePasswordResult(false, 'Network error. Please try again.');
    }
  }

  /// Step 2 of the tally-oauth OTP flow - the "Update Password" button's
  /// tally-oauth path once an OTP has been requested.
  Future<ChangePasswordResult> confirmReset({
    required String otp,
    required String newPassword,
  }) async {
    final resetToken = state.resetToken;
    if (resetToken == null) {
      return const ChangePasswordResult(false, 'Please request an OTP first.');
    }

    state = state.copyWith(isLoading: true);
    try {
      await _ref.read(authRepositoryProvider).changePassword(
        resetToken: resetToken,
        otp: otp,
        password: newPassword,
      );
      state = state.copyWith(
        clearResetToken: true,
        isLoading: false,
        showNewPassValidation: false,
        showConfirmValidation: false,
        hasLower: false,
        hasUpper: false,
        hasNumber: false,
        isMatch: false,
      );
      return const ChangePasswordResult(
        true,
        'Password changed successfully.',
      );
    } on ApiException catch (e) {
      state = state.copyWith(isLoading: false);
      return ChangePasswordResult(false, e.message);
    } catch (e) {
      state = state.copyWith(isLoading: false);
      return const ChangePasswordResult(false, 'Network error. Please try again.');
    }
  }
}

final changePasswordNotifierProvider =
    StateNotifierProvider.autoDispose<ChangePasswordNotifier, ChangePasswordState>(
  (ref) => ChangePasswordNotifier(ref),
);
