import 'package:local_auth/local_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Wraps [LocalAuthentication] to offer fingerprint (Android) / Face ID (iOS)
/// login, and persists whether the user has opted in to it.
class BiometricAuthService {
  BiometricAuthService._();
  static final BiometricAuthService instance = BiometricAuthService._();

  final LocalAuthentication _auth = LocalAuthentication();

  static const _enabledPrefsKey = 'biometric_login_enabled';

  /// Whether the device has usable biometric hardware with enrolled
  /// fingerprint/face data (independent of whether the user turned the
  /// feature on in this app).
  Future<bool> isDeviceSupported() async {
    try {
      final canCheck = await _auth.canCheckBiometrics;
      final isSupported = await _auth.isDeviceSupported();
      if (!canCheck && !isSupported) return false;
      final available = await _auth.getAvailableBiometrics();
      return available.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  /// Human-readable label for the biometric type available on this device,
  /// e.g. "Face ID" on iOS with face recognition, "Fingerprint" otherwise.
  Future<String> biometricLabel() async {
    try {
      final available = await _auth.getAvailableBiometrics();
      if (available.contains(BiometricType.face)) return 'Face ID';
      if (available.contains(BiometricType.fingerprint)) return 'Fingerprint';
      if (available.contains(BiometricType.strong) ||
          available.contains(BiometricType.weak)) {
        return 'Biometric';
      }
      return 'Biometric';
    } catch (_) {
      return 'Biometric';
    }
  }

  Future<bool> isEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_enabledPrefsKey) ?? false;
  }

  Future<void> setEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_enabledPrefsKey, enabled);
  }

  /// Prompts the OS fingerprint/Face ID dialog. Returns true only on a
  /// genuine successful biometric match.
  Future<bool> authenticate({
    String reason = 'Authenticate to sign in to Fincore Go',
  }) async {
    try {
      return await _auth.authenticate(
        localizedReason: reason,
        options: const AuthenticationOptions(
          biometricOnly: true,
          stickyAuth: true,
        ),
      );
    } catch (_) {
      return false;
    }
  }
}
