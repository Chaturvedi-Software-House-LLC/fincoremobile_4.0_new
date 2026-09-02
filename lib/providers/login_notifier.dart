import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Login.dart is unusually large and interconnected (biometric auth, OTP,
/// remember-me auto-login, password reset, a countdown Timer all feeding
/// one auth flow). Rather than move every orchestration method here (which
/// would risk subtle regressions in a screen that gates every session),
/// this notifier only replaces the `setState`-held UI/business *flags* the
/// widget's build() reads - the actual network calls, dialogs, Timer, and
/// TickerProvider stay in the widget, calling into this notifier's setters
/// instead of setState. See CLAUDE.md/the migration plan for why this
/// screen gets a lighter-touch treatment than the rest of Batch 2.
class LoginState {
  final bool isLoading;
  final bool isLoadingResetPass;
  final bool isConfirmingPasswordReset;
  final bool isOtpVerifyingProgress;
  final bool isVerifyingOtp;

  final bool isVisibleLoginForm;
  final bool isVisibleResetPassForm;
  final bool isVisibleOTPForm;
  final bool isVisibleResetOtpForm;

  final bool biometricAvailable;
  final bool biometricEnabled;
  final bool biometricPromptShown;
  final bool isBiometricAuthenticating;
  final String biometricLabel;

  final bool rememberMeEnabled;
  final bool isRememberMeAutoLoggingIn;

  final bool isVisibleTimer;
  final bool isResendButtonEnabled;
  final String formattedTimerTime;

  final String generatedOtp;
  final String maskedEmail;
  final String? passwordResetToken;

  const LoginState({
    this.isLoading = false,
    this.isLoadingResetPass = false,
    this.isConfirmingPasswordReset = false,
    this.isOtpVerifyingProgress = false,
    this.isVerifyingOtp = false,
    this.isVisibleLoginForm = true,
    this.isVisibleResetPassForm = false,
    this.isVisibleOTPForm = false,
    this.isVisibleResetOtpForm = false,
    this.biometricAvailable = false,
    this.biometricEnabled = false,
    this.biometricPromptShown = false,
    this.isBiometricAuthenticating = false,
    this.biometricLabel = 'Biometric',
    this.rememberMeEnabled = true,
    this.isRememberMeAutoLoggingIn = false,
    this.isVisibleTimer = false,
    this.isResendButtonEnabled = false,
    this.formattedTimerTime = '01:00',
    this.generatedOtp = '',
    this.maskedEmail = '',
    this.passwordResetToken,
  });

  LoginState copyWith({
    bool? isLoading,
    bool? isLoadingResetPass,
    bool? isConfirmingPasswordReset,
    bool? isOtpVerifyingProgress,
    bool? isVerifyingOtp,
    bool? isVisibleLoginForm,
    bool? isVisibleResetPassForm,
    bool? isVisibleOTPForm,
    bool? isVisibleResetOtpForm,
    bool? biometricAvailable,
    bool? biometricEnabled,
    bool? biometricPromptShown,
    bool? isBiometricAuthenticating,
    String? biometricLabel,
    bool? rememberMeEnabled,
    bool? isRememberMeAutoLoggingIn,
    bool? isVisibleTimer,
    bool? isResendButtonEnabled,
    String? formattedTimerTime,
    String? generatedOtp,
    String? maskedEmail,
    String? passwordResetToken,
    bool clearPasswordResetToken = false,
  }) {
    return LoginState(
      isLoading: isLoading ?? this.isLoading,
      isLoadingResetPass: isLoadingResetPass ?? this.isLoadingResetPass,
      isConfirmingPasswordReset:
          isConfirmingPasswordReset ?? this.isConfirmingPasswordReset,
      isOtpVerifyingProgress:
          isOtpVerifyingProgress ?? this.isOtpVerifyingProgress,
      isVerifyingOtp: isVerifyingOtp ?? this.isVerifyingOtp,
      isVisibleLoginForm: isVisibleLoginForm ?? this.isVisibleLoginForm,
      isVisibleResetPassForm:
          isVisibleResetPassForm ?? this.isVisibleResetPassForm,
      isVisibleOTPForm: isVisibleOTPForm ?? this.isVisibleOTPForm,
      isVisibleResetOtpForm:
          isVisibleResetOtpForm ?? this.isVisibleResetOtpForm,
      biometricAvailable: biometricAvailable ?? this.biometricAvailable,
      biometricEnabled: biometricEnabled ?? this.biometricEnabled,
      biometricPromptShown: biometricPromptShown ?? this.biometricPromptShown,
      isBiometricAuthenticating:
          isBiometricAuthenticating ?? this.isBiometricAuthenticating,
      biometricLabel: biometricLabel ?? this.biometricLabel,
      rememberMeEnabled: rememberMeEnabled ?? this.rememberMeEnabled,
      isRememberMeAutoLoggingIn:
          isRememberMeAutoLoggingIn ?? this.isRememberMeAutoLoggingIn,
      isVisibleTimer: isVisibleTimer ?? this.isVisibleTimer,
      isResendButtonEnabled:
          isResendButtonEnabled ?? this.isResendButtonEnabled,
      formattedTimerTime: formattedTimerTime ?? this.formattedTimerTime,
      generatedOtp: generatedOtp ?? this.generatedOtp,
      maskedEmail: maskedEmail ?? this.maskedEmail,
      passwordResetToken: clearPasswordResetToken
          ? null
          : (passwordResetToken ?? this.passwordResetToken),
    );
  }
}

class LoginNotifier extends StateNotifier<LoginState> {
  LoginNotifier() : super(const LoginState());

  void update(LoginState Function(LoginState state) updater) {
    state = updater(state);
  }
}

final loginNotifierProvider =
    StateNotifierProvider.autoDispose<LoginNotifier, LoginState>(
  (ref) => LoginNotifier(),
);
