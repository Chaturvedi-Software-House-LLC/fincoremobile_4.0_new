import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../api/api_exception.dart';
import '../api/auth_repository.dart';

class VerifyEmailState {
  final bool isSending;
  final bool isVerifying;

  const VerifyEmailState({this.isSending = false, this.isVerifying = false});

  VerifyEmailState copyWith({bool? isSending, bool? isVerifying}) {
    return VerifyEmailState(
      isSending: isSending ?? this.isSending,
      isVerifying: isVerifying ?? this.isVerifying,
    );
  }
}

/// Drives VerifyEmail.dart, opened from Dashboard.dart's "verify your
/// email" banner rather than a login-time gate (see VerifyEmail.dart's
/// own doc comment for why that changed).
class VerifyEmailNotifier extends StateNotifier<VerifyEmailState> {
  VerifyEmailNotifier() : super(const VerifyEmailState());

  String? _verifyToken;

  /// `POST /auth/user/send-verification-email` - returns null on success,
  /// or a message to show the user on failure. Called once automatically
  /// when the prompt screen opens, and again on "Resend".
  Future<String?> sendCode() async {
    state = state.copyWith(isSending: true);
    try {
      _verifyToken = await AuthRepository.instance.sendVerificationEmail();
      return null;
    } on ApiException catch (e) {
      return e.message;
    } catch (e) {
      return 'Could not reach the server. Please try again.';
    } finally {
      state = state.copyWith(isSending: false);
    }
  }

  /// `POST /auth/user/verify-email` - returns null on success, or a
  /// message to show the user on failure (e.g. wrong/expired code).
  Future<String?> verify(String otp) async {
    if (_verifyToken == null) {
      return 'Please request a code first.';
    }
    state = state.copyWith(isVerifying: true);
    try {
      await AuthRepository.instance.verifyEmail(
        verifyToken: _verifyToken!,
        otp: otp,
      );
      // Dashboard.dart's own markEmailVerified() call (after this screen
      // pops back with `true`) keeps this same session's Dashboard
      // instance in sync; this persists it so the banner stays gone across
      // an app restart too, without relying on a fresh login re-reading
      // `emailVerifiedAt` from the server.
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('email_verified', 'True');
      return null;
    } on ApiException catch (e) {
      return e.message;
    } catch (e) {
      return 'Could not reach the server. Please try again.';
    } finally {
      state = state.copyWith(isVerifying: false);
    }
  }
}

final verifyEmailNotifierProvider =
    StateNotifierProvider.autoDispose<VerifyEmailNotifier, VerifyEmailState>(
  (ref) => VerifyEmailNotifier(),
);
