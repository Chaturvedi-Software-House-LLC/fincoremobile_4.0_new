import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:open_file/open_file.dart';
import 'package:flutter/services.dart';
import 'Help.dart';
import 'CompanySelectTallyOauth.dart';
import 'VerifyEmail.dart';
import 'constants.dart';
import 'package:flutter/material.dart';
import 'package:pin_code_fields/pin_code_fields.dart';
import 'package:flutter/cupertino.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path_provider/path_provider.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'widgets/entry_widgets.dart';
import 'services/biometric_auth_service.dart';
import 'api/api_exception.dart';
import 'api/auth_repository.dart';
import 'providers/login_notifier.dart';
// import 'package:firebase_messaging/firebase_messaging.dart';

class Login extends ConsumerStatefulWidget {
  final String username, password;
  const Login({required this.username, required this.password});
  @override
  ConsumerState<Login> createState() =>
      _LoginPageState(usernamee: username, passwordd: password);
}

class _LoginPageState extends ConsumerState<Login>
    with TickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _resetformKey = GlobalKey<FormState>();
  final _otpformKey = GlobalKey<FormState>();

  final _scaffoldKey = GlobalKey<ScaffoldState>();
  Color _buttonColor = app_color;
  Color _resetbuttonColor = app_color;

  // Drives the hero section's slow-drifting glow (see _buildAnimatedHero) -
  // a pure-Flutter stand-in for the reference design's looping video
  // background, no video asset/package needed.
  late final AnimationController _heroGlowController;

  // Measured actual rendered height of _buildAnimatedHero() (its size is
  // content-driven, not a fixed constant) - used to position the auth
  // card's Positioned(top: ...) in the compact/phone layout's Stack (see
  // build()). A Transform.translate approach was tried first but a
  // SingleChildScrollView clips any paint that lands above its own
  // content-relative y=0, which silently ate the "rise above the hero"
  // portion of the translate - a Stack + measured Positioned sidesteps
  // that entirely, since Positioned's offset is real layout, not a
  // paint-only shift inside a clipping scroll viewport.
  final GlobalKey _heroMeasureKey = GlobalKey();
  double? _heroHeight;

  void _measureHero() {
    final renderObject = _heroMeasureKey.currentContext?.findRenderObject();
    if (renderObject is! RenderBox || !renderObject.hasSize) return;
    final height = renderObject.size.height;
    if (_heroHeight != height && mounted) {
      setState(() => _heroHeight = height);
    }
  }

  late SharedPreferences prefs_login;

  String responseMessage = ''; // To store the server response.

  bool isOTPVerified = false, isAnotherDevice = false;

  final GlobalKey<ScaffoldMessengerState> _scaffoldMessengerKey =
      GlobalKey<ScaffoldMessengerState>();

  final String SHARED_PREFERENCES_NAME = "login_prefs";

  bool isDirectLogin = false, isOTPLogin = false;

  String? username_prefs, password_prefs;

  String? deviceIdentifier = '';

  // tally-oauth's password-reset flow (see AuthRepository.requestPasswordResetOtp/
  // changePassword) - "Forgot Password?" used to only call the legacy
  // backend, which doesn't exist for a tally-oauth-only account. Reuses
  // the same OTP-then-new-password flow already built for
  // ChangePassword.dart's tally-oauth path.
  final resetOtpController = TextEditingController();
  final newPasswordController = TextEditingController();
  final confirmNewPasswordController = TextEditingController();
  bool _isNewPasswordVisible = false;
  bool _isConfirmNewPasswordVisible = false;

  late String usernamee = '', resetemail = '';
  late final Color backgroundColor; // declare backgroundColor as non-nullable
  bool _obscureText = true;
  late String serial_no,
      role_id,
      license_expiry,
      hostname,
      hostpass,
      hostuser,
      dbname;

  DateTime? lastBackPressedTime;

  bool _deviceIdentifierLoaded = false;

  late String passwordd = '';

  final _usernameFocusNode = FocusNode();
  final _passwordFocusNode = FocusNode();
  final _resetemailFocusNode = FocusNode();
  late TickerProvider tickerProvider;
  static final RegExp _emailRegex = RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$');

  LoginNotifier get _login_ => ref.read(loginNotifierProvider.notifier);
  LoginState get _s => ref.read(loginNotifierProvider);

  _LoginPageState({required this.usernamee, required this.passwordd});

  /// Step 2 of the real, backend-verified login-OTP flow - exchanges the
  /// login-OTP token (from [_otplogin]'s [AuthRepository.sendLoginOtp]
  /// call) plus the code the user entered for a real session via
  /// [AuthRepository.verifyLoginOtp]. The backend rejects a wrong/expired/
  /// already-used code (401/403) - this no longer compares against
  /// anything held client-side.
  Future<void> _verifyOtpAndProceed(String enteredOTP) async {
    if (_s.isVerifyingOtp || _s.isOtpVerifyingProgress) return;

    // The backend's OtpProvider.generate() defaults to a 6-digit code (see
    // tally-admin-api's user-auth.service.ts) for every OTP flow, login
    // included - this used to be 4 because the old fake flow generated its
    // own 4-digit code client-side. Left at 4 after wiring the real
    // backend call, no real 6-digit code could ever be entered here.
    if (enteredOTP.length != 6) {
      showAppMessage(context, 'Please enter the 6-digit OTP');
      return;
    }

    _login_.update(
      (s) => s.copyWith(isVerifyingOtp: true, isOtpVerifyingProgress: true),
    );
    FocusManager.instance.primaryFocus?.unfocus();

    try {
      final session = await AuthRepository.instance.verifyLoginOtp(
        otpToken: _s.otpToken,
        otp: enteredOTP,
        fallbackUserName: usernamee,
      );

      isOTPVerified = true;
      isAnotherDevice = true;

      if (!mounted) return;
      _login_.update((s) => s.copyWith(isOtpVerifyingProgress: false));

      if (!await _isLicenseUsable()) return;
      _proceedOrRequireEmailVerification(session);
    } on ApiException catch (e) {
      isOTPVerified = false;
      isAnotherDevice = false;

      showAppMessage(context, e.message);
      currentText = '';

      if (!mounted) return;
      _login_.update(
        (s) => s.copyWith(isVerifyingOtp: false, isOtpVerifyingProgress: false),
      );
      _clearOtpFieldAfterRebuild(otpController);
    } catch (e) {
      isOTPVerified = false;
      isAnotherDevice = false;

      showAppMessage(context, 'Could not reach the server. Please try again.');
      currentText = '';

      if (!mounted) return;
      _login_.update(
        (s) => s.copyWith(isVerifyingOtp: false, isOtpVerifyingProgress: false),
      );
      _clearOtpFieldAfterRebuild(otpController);
    }
  }

  /// [PinCodeTextField] only reacts to a controller `.clear()` when its
  /// own `enabled` internally still matches `true` at the moment the
  /// listener fires (see pin_code_fields' `_textEditingControllerListener`)
  /// - clearing the controller in the same synchronous block as an
  /// `enabled: false -> true` state flip clears it *before* the widget has
  /// rebuilt with the new `enabled` value, so the boxes visually keep the
  /// wrong digits and backspace does nothing (the package's internal
  /// `_inputList` never got the memo). Scheduling the clear for the frame
  /// *after* the state update - once the field is actually rebuilt
  /// enabled - fixes it without touching the package.
  void _clearOtpFieldAfterRebuild(TextEditingController controller) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) controller.clear();
    });
  }

  bool isEmail(String value) {
    return _emailRegex.hasMatch(value.trim());
  }

  Future<void> _showConfirmationDialogAndExit(BuildContext context) async {
    await showDialog<void>(
      context: context,
      barrierDismissible: false, // user must tap button to close dialog
      builder: (BuildContext context) {
        return ScaleTransition(
          scale: CurvedAnimation(
            parent: AnimationController(
              duration: const Duration(milliseconds: 500),
              vsync: tickerProvider,
            )..forward(),
            curve: Curves.fastOutSlowIn,
          ),
          child: AlertDialog(
            title: Text('Exit Confirmation'),
            content: SingleChildScrollView(
              child: ListBody(
                children: <Widget>[Text('Do you really want to Exit?')],
              ),
            ),
            actions: <Widget>[
              TextButton(
                child: Text(
                  'No',
                  style: TextStyle(
                    color: app_color, // Change the text color here
                  ),
                ),
                onPressed: () {
                  Navigator.of(context).pop();
                },
              ),

              TextButton(
                child: Text(
                  'Yes',
                  style: TextStyle(
                    color: app_color, // Change the text color here
                  ),
                ),
                onPressed: () async {
                  Navigator.of(context).pop();
                  exit(0);
                },
              ),
            ],
          ),
        );
      },
    );
  }

  void navigateToPDFView(BuildContext context) async {
    String pdfPath =
        'assets/installation.pdf'; // Path to your PDF file in the assets folder
    ByteData data = await rootBundle.load(pdfPath);
    List<int> bytes = data.buffer.asUint8List(
      data.offsetInBytes,
      data.lengthInBytes,
    );

    // Save the PDF file to a temporary location
    final tempDir = await getTemporaryDirectory();
    final tempFilePath = '${tempDir.path}/installation_guide.pdf';
    await File(tempFilePath).writeAsBytes(bytes);

    final result = await OpenFile.open(tempFilePath);

    if (result.type == ResultType.noAppToOpen) {
      showDialog(
        context: context,
        builder: (context) {
          return AlertDialog(
            title: Text('PDF Viewer Not Found'),
            content: Text('No PDF viewer app is installed on your device.'),
            actions: <Widget>[
              TextButton(
                onPressed: () {
                  Navigator.pop(context);
                },
                child: Text('OK'),
              ),
            ],
          );
        },
      );
    }
  }

  Timer? _timer;
  int _start = 60; // 60 seconds countdown
  void _startTimer() {
    _timer?.cancel();
    _start = 60; // Reset countdown to 60 seconds
    _login_.update(
      (s) => s.copyWith(
        formattedTimerTime: _formatDuration(_start),
        isResendButtonEnabled: false,
        isVisibleTimer: true,
      ),
    );

    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_start > 0) {
        _start--;
        _login_.update(
          (s) => s.copyWith(formattedTimerTime: _formatDuration(_start)),
        );
      } else {
        _stopTimer(); // Stop the timer when it reaches zero
        _login_.update(
          (s) => s.copyWith(
            isResendButtonEnabled: true,
            isVisibleTimer: false,
          ),
        );
      }
    });
  }

  void _stopTimer() {
    _timer?.cancel(); // Cancel the timer
  }

  String _formatDuration(int seconds) {
    final minutes = (seconds ~/ 60).toString().padLeft(2, '0');
    final secs = (seconds % 60).toString().padLeft(2, '0');
    return "$minutes:$secs";
  }

  /*Future<String> generateInstructions() async {

    final pdf = pw.Document();

    List<String> lines = [
      "1. For Registration, First you need to install Fincore Desktop Application where your Tally is installed. You can download Fincore Desktop Application from the following link http://mobile.chaturvedigroup.com/download/",
      "2. After download is done, install that application in your PC/Server",
      "3. Once installation is done, Open Tally in your PC/Server and select company which you want to add",
      "4. Once the above step is done, Open Fincore Desktop Application and click 'Register Here'",
      "5. Fill the required information and click 'Register'",
      "6. After successful activation, you can now set up the Fincore Desktop Application and add companies in it of which you want to see data in Fincore Go",
      "7. If you want to experience Fincore Go, you can login with the following credentials for demonstration purposes (email address: demouser@ca-eim.com, password: user1234)",
      "8. For any kind of help, you can contact our support team at saadan@ca-eim or visit our website http://tallyuae.ae"
    ];

    final heading = pw.Text(
      "Instructions",
      style: pw.TextStyle(
        fontSize: 22,
        fontWeight: pw.FontWeight.bold,
      ),
    );

    final lineTexts = lines.map((line) => pw.Text(line, style: pw.TextStyle(fontSize: 14))).toList();

    final content = <pw.Widget>[
      pw.Center(child: heading),
      pw.SizedBox(height: 20), // Add some spacing between heading and lines
    ];
    content.addAll(lineTexts);

    pdf.addPage(
      pw.Page(
        build: (pw.Context context) {
          return pw.Container(
            padding: pw.EdgeInsets.all(20),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: content,
            ),
          );
        },
      ),
    );

    final output = await getTemporaryDirectory();
    final filePath = path.join(output.path, 'instructions.pdf');

    await File(filePath).writeAsBytes(await pdf.save());

    return filePath;
  }*/

  Future<void> _initBiometrics() async {
    final available = await BiometricAuthService.instance.isDeviceSupported();
    final enabled = await BiometricAuthService.instance.isEnabled();
    final label = await BiometricAuthService.instance.biometricLabel();

    final prefs = await SharedPreferences.getInstance();
    // Default to ON for a fresh install/new login - no saved preference
    // yet means the user hasn't explicitly turned it off.
    final rememberMeEnabled = prefs.getBool('remember_me_login_enabled') ?? true;

    if (!mounted) return;
    _login_.update(
      (s) => s.copyWith(
        biometricAvailable: available,
        biometricEnabled: enabled,
        biometricLabel: label,
        rememberMeEnabled: rememberMeEnabled,
      ),
    );
  }

  /// Called right after the login form's own `save()` (which is what
  /// actually populates `usernamee`/`passwordd` from the fields - they
  /// start blank and aren't set by [_onRememberMeChanged] itself, since
  /// toggling the switch typically happens before typing anything).
  /// Without this, "Remember Me" being on did nothing in the normal
  /// flow: the switch's own handler only ever saved credentials that
  /// happened to already be in hand at toggle time, which is never the
  /// case for a fresh login.
  Future<void> _persistRememberMeCredentialsIfEnabled() async {
    if (!_s.rememberMeEnabled) return;
    if (usernamee.isEmpty || usernamee == 'null' || passwordd.isEmpty) return;
    await prefs_login.setString('remember_me_username', usernamee);
    await prefs_login.setString('remember_me_password', passwordd);
  }

  Future<void> _onRememberMeChanged(bool value) async {
    _login_.update((s) => s.copyWith(rememberMeEnabled: value));

    final prefs = prefs_login;
    await prefs.setBool('remember_me_login_enabled', value);

    if (!value) {
      // Turning it off should immediately stop any future silent
      // auto-login - clear the saved auto-login credentials too.
      await prefs.remove('remember_me_username');
      await prefs.remove('remember_me_password');
    } else if (usernamee.isNotEmpty && usernamee != 'null' && passwordd.isNotEmpty) {
      // Already have credentials in hand (e.g. just typed and logged in
      // once, or prefilled) - save them right away instead of waiting
      // for the next successful login.
      await prefs.setString('remember_me_username', usernamee);
      await prefs.setString('remember_me_password', passwordd);
    }
  }

  Future<void> _rememberMeAutoLogin() async {
    if (_s.isRememberMeAutoLoggingIn) return;

    final storedUsername = prefs_login.getString('remember_me_username');
    final storedPassword = prefs_login.getString('remember_me_password');

    if (storedUsername == null ||
        storedUsername.isEmpty ||
        storedPassword == null ||
        storedPassword.isEmpty) {
      return;
    }

    _login_.update((s) => s.copyWith(isRememberMeAutoLoggingIn: true));
    try {
      usernamee = storedUsername;
      passwordd = storedPassword;
      usernameController.text = storedUsername;
      passwordController.text = storedPassword;
      username_prefs = storedUsername;
      password_prefs = storedPassword;

      _login();
    } finally {
      if (mounted) {
        _login_.update((s) => s.copyWith(isRememberMeAutoLoggingIn: false));
      }
    }
  }

  Future<void> _biometricLogin() async {
    if (_s.isBiometricAuthenticating) return;
    _login_.update((s) => s.copyWith(isBiometricAuthenticating: true));

    try {
      final ok = await BiometricAuthService.instance.authenticate(
        reason: 'Authenticate with ${_s.biometricLabel} to sign in',
      );
      if (!ok) {
        // authenticate() may have discovered biometrics aren't actually
        // enrolled/usable and turned itself off - re-sync our local flag
        // so the UI swaps over to the Remember Me switch right away
        // instead of waiting for the next app launch.
        final stillEnabled = await BiometricAuthService.instance.isEnabled();
        if (mounted && !stillEnabled) {
          _login_.update(
            (s) => s.copyWith(
              biometricEnabled: false,
              rememberMeEnabled: true,
            ),
          );
          await prefs_login.setBool('remember_me_login_enabled', true);
        }
        return;
      }

      final storedUsername = prefs_login.getString('biometric_username');
      final storedPassword = prefs_login.getString('biometric_password');

      if (storedUsername == null ||
          storedUsername.isEmpty ||
          storedPassword == null) {
        if (mounted) {
          showAppMessage(
            context,
            'No saved credentials found. Please log in manually once to enable ${_s.biometricLabel} login.',
          );
        }
        return;
      }

      usernamee = storedUsername;
      passwordd = storedPassword;
      usernameController.text = storedUsername;
      passwordController.text = storedPassword;
      username_prefs = storedUsername;
      password_prefs = storedPassword;

      _login();
    } finally {
      if (mounted) {
        _login_.update((s) => s.copyWith(isBiometricAuthenticating: false));
      }
    }
  }

  Future<void> _maybeOfferBiometricEnable() async {
    if (_s.biometricPromptShown ||
        _s.biometricEnabled ||
        !_s.biometricAvailable ||
        !mounted) {
      return;
    }
    _login_.update((s) => s.copyWith(biometricPromptShown: true));

    final IconData biometricIcon = _s.biometricLabel == 'Face ID'
        ? Icons.face_retouching_natural
        : Icons.fingerprint;

    final enable = await showGeneralDialog<bool>(
      context: context,
      barrierDismissible: true,
      barrierLabel: '',
      barrierColor: Colors.black.withValues(alpha: 0.45),
      transitionDuration: const Duration(milliseconds: 320),
      pageBuilder: (dialogContext, anim1, anim2) => const SizedBox.shrink(),
      transitionBuilder: (dialogContext, anim1, anim2, child) {
        final curvedValue = Curves.easeOutBack.transform(anim1.value);
        return Transform.scale(
          scale: curvedValue,
          child: Opacity(
            opacity: anim1.value,
            child: Center(
              child: Material(
                color: Colors.transparent,
                child: Container(
                  width: MediaQuery.of(dialogContext).size.width * 0.85,
                  padding: const EdgeInsets.fromLTRB(24, 28, 24, 20),
                  decoration: BoxDecoration(
                    color: Theme.of(dialogContext).cardColor,
                    borderRadius: BorderRadius.circular(28),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.2),
                        blurRadius: 24,
                        offset: const Offset(0, 12),
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 68,
                        height: 68,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: LinearGradient(
                            colors: [app_color, app_color.withValues(alpha: 0.7)],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                        ),
                        child: Icon(biometricIcon, color: Colors.white, size: 34),
                      ),
                      const SizedBox(height: 18),
                      Text(
                        'Enable ${_s.biometricLabel} login?',
                        textAlign: TextAlign.center,
                        style: GoogleFonts.poppins(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        'Use ${_s.biometricLabel} to sign in faster next time instead of typing your password.',
                        textAlign: TextAlign.center,
                        style: GoogleFonts.poppins(
                          fontSize: 13.5,
                          color: Theme.of(
                            dialogContext,
                          ).colorScheme.onSurfaceVariant,
                          height: 1.4,
                        ),
                      ),
                      const SizedBox(height: 24),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: () =>
                                  Navigator.of(dialogContext).pop(false),
                              style: OutlinedButton.styleFrom(
                                side: BorderSide(color: app_color),
                                padding: const EdgeInsets.symmetric(
                                  vertical: 14,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16),
                                ),
                              ),
                              child: Text(
                                'Not now',
                                style: GoogleFonts.poppins(
                                  color: app_color,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 14.5,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: ElevatedButton(
                              onPressed: () =>
                                  Navigator.of(dialogContext).pop(true),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: app_color,
                                elevation: 0,
                                padding: const EdgeInsets.symmetric(
                                  vertical: 14,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16),
                                ),
                              ),
                              child: Text(
                                'Enable',
                                style: GoogleFonts.poppins(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 14.5,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );

    if (enable == true) {
      final confirmed = await BiometricAuthService.instance.authenticate(
        reason: 'Confirm ${_s.biometricLabel} to enable it for sign in',
      );
      if (confirmed) {
        await BiometricAuthService.instance.setEnabled(true);
        await prefs_login.setString('biometric_username', usernamee);
        await prefs_login.setString('biometric_password', passwordd);
        if (mounted) {
          _login_.update((s) => s.copyWith(biometricEnabled: true));
        }
      }
    }
  }

  Future<void> _initSharedPreferences() async {
    fetchvanSalesSerialNumbers();

    prefs_login = await SharedPreferences.getInstance();

    username_prefs = usernamee;
    password_prefs = passwordd;

    await prefs_login.remove('username');
    await prefs_login.remove('password');
    await prefs_login.remove('company_name');
    await prefs_login.remove('serial_no');
    await prefs_login.remove('datetype');
    await prefs_login.remove('token');

    tickerProvider = this;

    // "Remember me" only remembers what was typed (prefilled into the
    // form above via initState) - it must never silently log the user
    // in on its own. Biometric/Face ID is the only thing allowed to
    // trigger sign-in automatically here; without it, the user always
    // has to tap Login themselves, even with a remembered username.
    if (usernamee != "null" && usernamee.isNotEmpty && usernamee != null) {
      final biometricEnabled = await BiometricAuthService.instance
          .isEnabled();

      if (biometricEnabled) {
        if (mounted) {
          _login_.update((s) => s.copyWith(biometricEnabled: true));
        }
        await _biometricLogin();
      } else {
        // Either there's no fingerprint/Face ID hardware at all, or the
        // device has it but the user never turned it on for this app -
        // either way, honor the plain Remember Me switch instead and
        // actually sign the user in automatically (unlike the biometric
        // path, this one is a true silent auto-login, no OS prompt).
        final rememberMeEnabled =
            prefs_login.getBool('remember_me_login_enabled') ?? true;
        if (rememberMeEnabled) {
          if (mounted) {
            _login_.update((s) => s.copyWith(rememberMeEnabled: true));
          }
          await _rememberMeAutoLogin();
        }
      }
    }
  }

  /// tally-oauth is now the sole login backend (Phase 6), so this used to
  /// call the legacy `/api/login/forgotPassword` endpoint unconditionally -
  /// unreachable/broken for every account now, since nothing else in the
  /// app talks to that backend anymore. Replaced with tally-oauth's own
  /// OTP-based reset flow (same AuthRepository methods ChangePassword.dart
  /// already uses): this step just requests the OTP; [_confirmPasswordReset]
  /// (triggered from [_buildResetOtpForm]) completes it.
  Future<void> _resetpass() async {
    _login_.update((s) => s.copyWith(isLoadingResetPass: true));
    _showProcessingDialog();

    final enteredemail = resetemailController.text;
    try {
      final token = await AuthRepository.instance.requestPasswordResetOtp(
        username: enteredemail,
      );
      if (!mounted) return;
      _login_.update(
        (s) => s.copyWith(
          passwordResetToken: token,
          isVisibleResetPassForm: false,
          isVisibleResetOtpForm: true,
          isResetOtpConfirmed: false,
        ),
      );
      resetOtpController.clear();
      newPasswordController.clear();
      confirmNewPasswordController.clear();
    } on ApiException catch (e) {
      showAppMessage(context, e.message);
    } catch (e) {
      showAppMessage(context, 'Could not reach the server. Please try again.');
    } finally {
      if (mounted) {
        _login_.update((s) => s.copyWith(isLoadingResetPass: false));
        if (Navigator.canPop(context)) {
          Navigator.pop(context);
        }
      }
    }
  }

  /// Fires once all 6 digits are entered in [_buildResetOtpForm]'s pin
  /// field - a real, non-consuming backend check
  /// ([AuthRepository.verifyResetPasswordOtp]) so the new/confirm-password
  /// fields only reveal once the code is actually correct, not just fully
  /// typed. A wrong code doesn't burn the reset token, so the user can
  /// just retype and retry; the real, single-use verification still
  /// happens in [_confirmPasswordReset] on final submit.
  Future<void> _verifyResetOtp(String enteredOtp) async {
    final resetToken = _s.passwordResetToken;
    if (resetToken == null || enteredOtp.length != 6) return;

    _login_.update(
      (s) => s.copyWith(isVerifyingResetOtp: true, isResetOtpConfirmed: false),
    );
    try {
      await AuthRepository.instance.verifyResetPasswordOtp(
        resetToken: resetToken,
        otp: enteredOtp,
      );
      if (!mounted) return;
      _login_.update(
        (s) => s
            .copyWith(isVerifyingResetOtp: false, isResetOtpConfirmed: true),
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      _login_.update((s) => s.copyWith(isVerifyingResetOtp: false));
      showAppMessage(context, e.message);
      _clearOtpFieldAfterRebuild(resetOtpController);
    } catch (e) {
      if (!mounted) return;
      _login_.update((s) => s.copyWith(isVerifyingResetOtp: false));
      showAppMessage(context, 'Could not reach the server. Please try again.');
      _clearOtpFieldAfterRebuild(resetOtpController);
    }
  }

  /// Step 2 of the tally-oauth reset flow - the OTP + new password form's
  /// submit handler.
  Future<void> _confirmPasswordReset() async {
    final resetToken = _s.passwordResetToken;
    if (resetToken == null) return;

    // The backend's OtpProvider.generate() defaults to a 6-digit code for
    // every OTP flow (see tally-admin-api's user-auth.service.ts) - this
    // was left at 4 from before this form called the real endpoint.
    if (resetOtpController.text.trim().length != 6) {
      showAppMessage(context, 'Please enter the 6-digit code');
      return;
    }
    if (newPasswordController.text.length < 8) {
      showAppMessage(context, 'Password must be at least 8 characters');
      return;
    }
    // Matches tally-admin-api's PasswordSchema - only length and one
    // special character are required (see ChangePassword.dart/
    // CreateUser.dart's matching checks).
    if (!RegExp(r'[^a-zA-Z0-9]').hasMatch(newPasswordController.text)) {
      showAppMessage(
        context,
        'Password must contain at least one special character',
      );
      return;
    }
    if (newPasswordController.text != confirmNewPasswordController.text) {
      showAppMessage(context, 'Passwords do not match');
      return;
    }

    _login_.update((s) => s.copyWith(isConfirmingPasswordReset: true));
    try {
      await AuthRepository.instance.changePassword(
        resetToken: resetToken,
        otp: resetOtpController.text.trim(),
        password: newPasswordController.text,
      );
      if (!mounted) return;
      showAppMessage(
        context,
        'Password changed successfully. Please sign in.',
        isError: false,
      );
      _login_.update(
        (s) => s.copyWith(
          clearPasswordResetToken: true,
          isConfirmingPasswordReset: false,
          isVisibleResetOtpForm: false,
          isVisibleLoginForm: true,
        ),
      );
      usernameController.text = resetemailController.text;
      resetemailController.clear();
      resetOtpController.clear();
      newPasswordController.clear();
      confirmNewPasswordController.clear();
    } on ApiException catch (e) {
      // Can't tell from here whether the server rejected the OTP
      // specifically or something else - safest is to fold back to the
      // OTP step and make the user re-enter/re-confirm the code, since a
      // stale/wrong code is the most likely real-world cause.
      _login_.update(
        (s) => s.copyWith(
          isConfirmingPasswordReset: false,
          isResetOtpConfirmed: false,
        ),
      );
      _clearOtpFieldAfterRebuild(resetOtpController);
      showAppMessage(context, e.message);
    } catch (e) {
      _login_.update((s) => s.copyWith(isConfirmingPasswordReset: false));
      showAppMessage(context, 'Network error. Please try again.');
    }
  }

  void _showProcessingDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          backgroundColor: Theme.of(context).scaffoldBackgroundColor,
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator.adaptive(
                valueColor: AlwaysStoppedAnimation<Color>(
                  app_color,
                ), // Change the color here
              ),
              SizedBox(height: 16),
              Text(
                'Sending Reset Email',
                style: GoogleFonts.poppins(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w500,
                  fontSize: 14.5,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _login() async {
    isDirectLogin = false;
    isOTPLogin = false;
    isOTPVerified = false;
    isAnotherDevice = false;

    String entered_username = usernameController.text;
    String entered_password = passwordController.text;

    if (username_prefs == null && password_prefs == null) {
      if (entered_username == 'demouser@ca-eim.com' &&
          entered_password == 'user1234') {
        isOTPVerified = true;
        isAnotherDevice = true;

        _directlogin();
      } else {
        if (isEmail(entered_username)) {
          _otplogin(entered_username);
        } else {
          isOTPVerified = true;
          isAnotherDevice = true;
          _directlogin();
        }
      }
    } else {
      if (entered_username == 'demouser@ca-eim.com' &&
          entered_password == 'user1234') {
        isOTPVerified = true;
        isAnotherDevice = true;

        _directlogin();
      } else {
        if (username_prefs != entered_username) {
          if (isEmail(entered_username)) {
            _otplogin(entered_username);
          } else {
            isOTPVerified = true;
            isAnotherDevice = true;
            _directlogin();
          }
        } else {
          _directlogin();
        }
      }
    }
  }

  /// `POST /auth/user/login` against tally-oauth, run before the legacy
  /// `/api/login/getusers` call below in both _directlogin and _otplogin.
  /// Most of the app now depends on this session, so a failure here blocks
  /// login entirely rather than silently proceeding legacy-only - a
  /// half-authed session is worse than a clear error up front.
  Future<bool> _loginToTallyOauth() async {
    try {
      _lastLoginSession = await AuthRepository.instance.loginToTallyOauth(
        userName: usernamee,
        password: passwordd,
      );
      return true;
    } on ApiException catch (e) {
      showAppMessage(context, e.message);
      return false;
    } catch (e) {
      showAppMessage(context, 'Could not reach the server. Please try again.');
      return false;
    }
  }

  /// Set by [_loginToTallyOauth] on success (direct-login path) so
  /// [_directlogin] can decide whether to route through [VerifyEmail]
  /// before company selection; the OTP-login path gets its own result
  /// straight from [AuthRepository.verifyLoginOtp]/`sendResult.session`
  /// instead, since it never calls this method.
  LoginSessionResult? _lastLoginSession;

  /// An email-shaped login whose account has not verified its email is
  /// sent to [VerifyEmail] instead of company selection - on every such
  /// login, not just the first, until the account's email is actually
  /// verified. A username-style login always skips this regardless of
  /// `emailVerified`. Restores the login-blocking gate (see this app's
  /// history: it was briefly moved to a dismissible Dashboard banner,
  /// then reverted back to blocking per updated product direction).
  void _proceedOrRequireEmailVerification(LoginSessionResult? session) {
    if (isEmail(usernamee) && session != null && !session.emailVerified) {
      if (mounted) _login_.update((s) => s.copyWith(isLoading: false));
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => VerifyEmail(email: session.email ?? usernamee),
        ),
      );
      return;
    }
    _proceedToCompanySelection();
  }

  /// tally-oauth is now the sole driver of login (Phase 6) - no legacy
  /// `/api/login/getusers` call, no OTP/device-approval socket flow. Goes
  /// straight to [CompanySelectTallyOauth] once the tally-oauth session is
  /// established. This means Sales/Receipt/Sales-Order/Delivery-Note entry
  /// screens, Van Allocation, and the AI Assistant - which depend on the
  /// legacy `hostname`/`token` prefs this used to populate - no longer work
  /// for accounts that log in this way. That's an accepted, deliberate
  /// trade-off (see the migration plan's "Phase 6"), not a bug.
  void _proceedToCompanySelection() {
    if (mounted) _login_.update((s) => s.copyWith(isLoading: false));
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const CompanySelectTallyOauth()),
    );
  }

  /// Fetches the account's licenses and blocks login right here - before
  /// OTP for an email login, before company selection for a direct login -
  /// if none is currently usable (expired/suspended/inactive), rather than
  /// letting the user proceed a screen further only to hit the same error
  /// in [CompanySelectTallyOauth]. Shows the modern blocked-license dialog
  /// and resets the loading state itself on failure, so callers can just
  /// `return` when this returns false.
  Future<bool> _isLicenseUsable() async {
    try {
      final result = await AuthRepository.instance.checkAnyLicenseUsable();
      if (result == null) return true;
      if (mounted) _login_.update((s) => s.copyWith(isLoading: false));
      await _showLicenseBlockedDialog(result.$1, result.$2);
      return false;
    } catch (e) {
      // A failure of this pre-flight check itself (network hiccup, etc.)
      // shouldn't block login - company-user login already enforces
      // validity server-side, so worst case the user sees the same
      // message one screen later instead of here.
      return true;
    }
  }

  Future<void> _showLicenseBlockedDialog(String title, String message) {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        insetPadding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 28, 24, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.red.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.lock_clock_rounded,
                  size: 38,
                  color: Colors.red.shade600,
                ),
              ),
              const SizedBox(height: 18),
              Text(
                title,
                style: GoogleFonts.poppins(
                  fontSize: 19,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                message,
                textAlign: TextAlign.center,
                style: GoogleFonts.poppins(
                  fontSize: 14,
                  height: 1.4,
                  color: Colors.black54,
                ),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: app_color,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    elevation: 0,
                  ),
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: Text(
                    'OK',
                    style: GoogleFonts.poppins(fontWeight: FontWeight.w600),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _directlogin() async {
    _login_.update((s) => s.copyWith(isLoading: true));
    isDirectLogin = true;
    isOTPLogin = false;

    if (!await _loginToTallyOauth()) {
      if (mounted) _login_.update((s) => s.copyWith(isLoading: false));
      return;
    }

    // Catch an expired/suspended/inactive license right here, before ever
    // navigating past Login - _isLicenseUsable() shows the error dialog
    // and resets loading state itself when it returns false.
    if (!await _isLicenseUsable()) return;

    _proceedOrRequireEmailVerification(_lastLoginSession);
  }

  /// Step 1 of the real, backend-verified login-OTP flow: verifies the
  /// password via `POST /auth/user/login-otp/send` (same credential check
  /// as a normal login) and, on success, emails a real server-generated
  /// OTP - no tally-oauth session exists yet at this point (unlike the old
  /// flow, which fully logged in *before* ever showing the OTP screen,
  /// making that "verification" meaningless). The session is only
  /// established once [_verifyOtpAndProceed] confirms the code.
  Future<void> _otplogin(String email) async {
    _login_.update((s) => s.copyWith(isLoading: true));
    isDirectLogin = false;
    isOTPLogin = true;

    LoginOtpSendResult sendResult;
    try {
      sendResult = await AuthRepository.instance.sendLoginOtp(
        userName: usernamee,
        password: passwordd,
      );
    } on ApiException catch (e) {
      if (mounted) {
        _login_.update((s) => s.copyWith(isLoading: false));
        showAppMessage(context, e.message);
      }
      return;
    } catch (e) {
      if (mounted) {
        _login_.update((s) => s.copyWith(isLoading: false));
        showAppMessage(context, 'Could not reach the server. Please try again.');
      }
      return;
    }

    if (!mounted) return;

    // Trusted-device shortcut: this device already passed OTP before and
    // hasn't been logged out since (see tally-admin-api's
    // UserDeviceService.isOtpVerified) - the backend already established
    // a real session, so there's nothing to verify here. Skip the OTP
    // screen entirely and proceed exactly like a direct login would.
    if (!sendResult.otpRequired) {
      _login_.update((s) => s.copyWith(isLoading: false));
      if (!await _isLicenseUsable()) return;
      _proceedOrRequireEmailVerification(sendResult.session);
      return;
    }

    // Dev/testing convenience only - the backend never includes this
    // outside a non-production environment (see UserAuthService.
    // sendLoginOtp), so debugOtp is always null against a real
    // production backend regardless of this build's own mode. Compiled
    // out of release builds either way, same guard the old fake-OTP
    // debug print used.
    if (kDebugMode && sendResult.debugOtp != null) {
      debugPrint('Login OTP (debug only): ${sendResult.debugOtp}');
    }

    _login_.update(
      (s) => s.copyWith(
        isLoading: false,
        isVisibleLoginForm: false,
        isVisibleResetPassForm: false,
        isResendButtonEnabled: false,
        isVisibleTimer: true,
        isOtpVerifyingProgress: false,
        isVerifyingOtp: false,
        isVisibleOTPForm: true,
        maskedEmail: email,
        otpToken: sendResult.otpToken!,
      ),
    );
    otpController.clear();
    currentText = '';
    _startTimer();
  }

  final passwordController = TextEditingController();

  final usernameController = TextEditingController();

  final resetemailController = TextEditingController();

  bool isButtonDisabled = true, isResetPassButtonDisabled = true;

  final requiredLength = 4; // the required length of the password

  @override
  void initState() {
    super.initState();
    _heroGlowController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 8),
    )..repeat();
    _initBiometrics();
    passwordController.addListener(_onPasswordChanged);
    resetemailController.addListener(_onResetEmailChanged);
    // Fields always start blank now - "Remember me" no longer prefills
    // them. usernamee/passwordd (passed in from a remembered login, if
    // any) still exist as fields on this State purely so _login()'s
    // existing same-user-vs-different-user comparison and the biometric
    // flow keep working; they're just never written into the visible
    // TextFields.

    /*FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      */ /*print('Got a message whilst in the foreground!');
      print('Message data: ${message.data}');*/ /*

      if (message.notification != null) {
        */ /*print('Message also contained a notification: ${message.notification}');*/ /*
      }
    });*/

    _initSharedPreferences();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _getDeviceIdentifier();
  }

  Future<void> _getDeviceIdentifier() async {
    if (_deviceIdentifierLoaded) return;
    _deviceIdentifierLoaded = true;

    DeviceInfoPlugin deviceInfo = DeviceInfoPlugin();
    String? identifier = '';

    try {
      if (Theme.of(context).platform == TargetPlatform.android) {
        final androidInfo = await deviceInfo.androidInfo;
        identifier = androidInfo.id; // use 'id' instead of 'androidId'
      } else if (Theme.of(context).platform == TargetPlatform.iOS) {
        final iosInfo = await deviceInfo.iosInfo;
        identifier = iosInfo.identifierForVendor; // same key in iOS
      }
    } catch (e) {
      debugPrint('Error getting device identifier: $e');
    }
    if (mounted) {
      setState(() {
        deviceIdentifier = identifier;
      });
    }
  }

  void _onPasswordChanged() {
    final shouldDisable = passwordController.text.length < requiredLength;
    final nextColor = shouldDisable ? Colors.grey : app_color;

    if (isButtonDisabled != shouldDisable || _buttonColor != nextColor) {
      setState(() {
        _buttonColor = nextColor;
        isButtonDisabled = shouldDisable;
      });
    }
  }

  void _onResetEmailChanged() {
    final shouldDisable = !isEmail(resetemailController.text);
    final nextColor = shouldDisable ? Colors.grey : app_color;

    if (isResetPassButtonDisabled != shouldDisable ||
        _resetbuttonColor != nextColor) {
      setState(() {
        _resetbuttonColor = nextColor;
        isResetPassButtonDisabled = shouldDisable;
      });
    }
  }

  final TextEditingController otpController = TextEditingController();
  String currentText = "";

  @override
  void dispose() {
    _timer?.cancel();
    _heroGlowController.dispose();

    passwordController.removeListener(_onPasswordChanged);
    resetemailController.removeListener(_onResetEmailChanged);

    passwordController.dispose();
    usernameController.dispose();
    resetemailController.dispose();
    otpController.dispose();
    resetOtpController.dispose();
    newPasswordController.dispose();
    confirmNewPasswordController.dispose();

    _usernameFocusNode.dispose();
    _passwordFocusNode.dispose();
    _resetemailFocusNode.dispose();

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Subscribes this widget to LoginNotifier so it rebuilds on state
    // changes - the helper methods below read the current value via the
    // `_s` (ref.read) getter, which is safe within the same build pass.
    ref.watch(loginNotifierProvider);
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final pageBackground = theme.scaffoldBackgroundColor;
    final gradientEnd = theme.brightness == Brightness.dark
        ? colorScheme.surface
        : Colors.white;

    return WillPopScope(
      child: Builder(
        builder: (BuildContext context) {
          return WillPopScope(
            onWillPop: () async {
              final now = DateTime.now();
              if (lastBackPressedTime == null ||
                  now.difference(lastBackPressedTime!) > Duration(seconds: 2)) {
                lastBackPressedTime = now;
                showAppMessage(context, 'Press back again to exit');
                return false;
              }
              return true;
            },
            child: ScaffoldMessenger(
              key: _scaffoldMessengerKey,
              child: Scaffold(
                backgroundColor: pageBackground,
                key: _scaffoldKey,
                // Old plain teal AppBar replaced by _buildAnimatedHero's
                // full-bleed gradient hero (phone layout only - the wide/
                // desktop layout keeps its side-by-side _buildBrandPanel,
                // unchanged). The "Help" action that used to live in the
                // AppBar is now a floating button over the hero/page below.
                body: Stack(
                  children: [
                    DecoratedBox(
                      decoration: BoxDecoration(
                        color: pageBackground,
                        gradient: LinearGradient(
                          colors: [
                            app_color.withOpacity(0.12),
                            pageBackground,
                            gradientEnd,
                          ],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                      ),
                      // top: false - the compact/phone hero below must
                      // paint full-bleed behind the status bar/notch too
                      // (its own gradient, not this page-level one, which
                      // was visibly lighter/mismatched there). Each
                      // branch below adds the status bar's height back
                      // as its own top inset/padding instead.
                      child: SafeArea(
                        top: false,
                        bottom: false,
                        child: LayoutBuilder(
                          builder: (context, constraints) {
                            final isWide = constraints.maxWidth >= 820;
                            final topInset = MediaQuery.paddingOf(context).top;

                            if (isWide) {
                              // Desktop/wide layout: unchanged from
                              // before - the whole page just scrolls,
                              // side-by-side brand panel + card, no hero/
                              // fill-to-bottom behavior (out of scope for
                              // this pass).
                              return SingleChildScrollView(
                                padding: EdgeInsets.fromLTRB(
                                  0,
                                  34 + topInset,
                                  0,
                                  34,
                                ),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 40,
                                  ),
                                  child: Center(
                                    child: ConstrainedBox(
                                      constraints: const BoxConstraints(
                                        maxWidth: 920,
                                      ),
                                      child: Row(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.center,
                                        children: [
                                          Expanded(child: _buildBrandPanel()),
                                          const SizedBox(width: 36),
                                          SizedBox(
                                            width: 430,
                                            child: _buildAnimatedAuthForm(),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              );
                            }

                            // Compact/phone layout: hero on top (measured
                            // via _heroMeasureKey - see _measureHero),
                            // card Positioned to start _heroCardOverlap
                            // px before the hero's measured bottom edge
                            // and fill the rest of the stack. Real Stack
                            // positioning (not a Transform.translate
                            // inside a SingleChildScrollView, which
                            // clips away any paint that lands above the
                            // scroll view's own y=0 - see _heroHeight's
                            // doc comment) - so the overlap is always
                            // actually visible, not silently clipped.
                            WidgetsBinding.instance.addPostFrameCallback(
                              (_) => _measureHero(),
                            );
                            final heroHeight = _heroHeight;
                            // SizedBox.expand forces this Stack to take
                            // the LayoutBuilder's full tight height - a
                            // bare Stack given loose constraints sizes
                            // itself to its non-positioned children only
                            // (the hero, ~315px), NOT the full screen,
                            // which made every Positioned(bottom: 0)
                            // below resolve to a near-zero-height box
                            // (stackHeight - top was only ~40px instead
                            // of the ~650px actually available) - this
                            // was the real cause of the blank/collapsed
                            // auth form, not the overlap math itself.
                            return SizedBox.expand(
                              child: Stack(
                                children: [
                                  Container(
                                    key: _heroMeasureKey,
                                    child: _buildAnimatedHero(topInset: topInset),
                                  ),
                                  if (heroHeight != null)
                                    Positioned(
                                      top: heroHeight - _heroCardOverlap,
                                      left: 0,
                                      right: 0,
                                      bottom: 0,
                                      child: SingleChildScrollView(
                                        child: _buildAnimatedAuthForm(
                                          minHeight:
                                              constraints.maxHeight -
                                              (heroHeight - _heroCardOverlap),
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                    // Floating "Help" action - replaces the old AppBar's
                    // help icon now that this screen has no AppBar.
                    SafeArea(
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Align(
                          alignment: Alignment.topRight,
                          child: Material(
                            // A fixed brand-color fill (not a translucent
                            // white overlay) so this stays legible over
                            // both the phone layout's hero gradient and
                            // the wide/desktop layout's plain page
                            // background.
                            color: app_color,
                            elevation: 3,
                            shape: const CircleBorder(),
                            child: IconButton(
                              icon: const Icon(
                                Icons.help_outline,
                                color: Colors.white,
                              ),
                              onPressed: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) => const Help(
                                      showBottomNavigation: false,
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
      onWillPop: () async {
        _showConfirmationDialogAndExit(context);
        return true;
      },
    );
  }

  Widget _buildAnimatedAuthForm({double? minHeight}) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 280),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      transitionBuilder: (child, animation) {
        return FadeTransition(
          opacity: animation,
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0, 0.025),
              end: Offset.zero,
            ).animate(animation),
            child: child,
          ),
        );
      },
      // AnimatedSwitcher's default layoutBuilder cross-fades children
      // inside a plain Stack, which always loosens (drops the minimum
      // of) the constraints it gives its children - a ConstrainedBox
      // minHeight placed *above* this widget never actually reaches
      // the card, which just renders at its natural height instead,
      // leaving the page's raw background visible below it. Threading
      // minHeight down explicitly as a value (not relying on ambient
      // BoxConstraints propagation) into _buildAuthCard's own
      // `constraints:` sidesteps that entirely.
      child: _s.isVisibleLoginForm
          ? _buildLoginForm(context, minHeight: minHeight)
          : _s.isVisibleResetPassForm
          ? _buildResetForm(context, minHeight: minHeight)
          : _s.isVisibleResetOtpForm
          ? _buildResetOtpForm(context, minHeight: minHeight)
          : _buildOtpForm(context, minHeight: minHeight),
    );
  }

  /// Full-bleed hero section for the phone-width login layout - a
  /// looping, drifting soft-glow gradient (pure Flutter, no video/Lottie
  /// asset) standing in for the reference design's video background,
  /// behind the FincoreGo logo + headline. Bigger and more dramatic than
  /// [_buildBrandPanel] (used instead of it for the compact/phone case),
  /// replacing the old plain teal AppBar this screen used to have - the
  /// "Help" action moved to a floating button over this hero instead (see
  /// build()'s Stack).
  Widget _buildAnimatedHero({double topInset = 0}) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    // Flat/square bottom (no rounding here) - the card's OWN rounded top
    // corners are what should visibly overlap and peek over this hero
    // (see _buildAuthCard's Transform.translate), with the hero's flat
    // teal background showing through in the two corner triangles beside
    // the card's curve. Rounding the hero's bottom edge too (as before)
    // made the overlap invisible - the card's rounded corner ended up
    // fully swallowed by the hero's own matching curve instead of
    // visibly rising over a flat edge.
    //
    // topInset (the status bar/notch height) is added into the top
    // padding, not consumed via SafeArea, so this Container's own
    // gradient paints full-bleed behind the status bar too - SafeArea
    // would otherwise leave that strip showing the page-level
    // background gradient instead, which is visibly lighter/mismatched.
    return Container(
        width: double.infinity,
        padding: EdgeInsets.fromLTRB(24, 28 + topInset, 24, 84),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: isDark
                ? [const Color(0xFF0B3D36), const Color(0xFF0F5C50)]
                : [app_color, const Color(0xFF0E8A76)],
          ),
        ),
        child: Stack(
          // Stack's default alignment is topStart (left), which left-
          // aligned the logo/headline Column below instead of centering
          // it - center is required since that Column isn't itself
          // wrapped in a Positioned/Align.
          alignment: Alignment.center,
          clipBehavior: Clip.none,
          children: [
            // Two soft blurred glow blobs that slowly drift in a loop -
            // the "electricity" feel from the reference thunder video,
            // reduced to something cheap and dependency-free.
            Positioned.fill(
              child: ImageFiltered(
                imageFilter: ImageFilter.blur(sigmaX: 50, sigmaY: 50),
                child: AnimatedBuilder(
                  animation: _heroGlowController,
                  builder: (context, _) {
                    final t = _heroGlowController.value * 2 * math.pi;
                    return Stack(
                      children: [
                        Positioned(
                          left: 40 + 30 * math.sin(t),
                          top: -30 + 20 * math.cos(t),
                          child: _glowBlob(180, Colors.white.withOpacity(0.22)),
                        ),
                        Positioned(
                          right: 20 + 25 * math.cos(t),
                          bottom: -20 + 25 * math.sin(t),
                          child: _glowBlob(
                            150,
                            const Color(0xFFBFFFE0).withOpacity(0.28),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ),
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: 36),
                Container(
                  width: 108,
                  height: 108,
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(22),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.18),
                        blurRadius: 20,
                        offset: const Offset(0, 10),
                      ),
                    ],
                  ),
                  child: Image.asset(
                    'assets/fincorego_logo_transparent.png',
                    fit: BoxFit.contain,
                  ),
                ),
                const SizedBox(height: 22),
                Text(
                  'Welcome back.',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.poppins(
                    color: Colors.white,
                    fontSize: 26,
                    fontWeight: FontWeight.w700,
                    height: 1.15,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Sign in to continue to your Fincore Go workspace.',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.poppins(
                    color: Colors.white.withOpacity(0.85),
                    fontSize: 13.5,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ],
        ),
    );
  }

  Widget _glowBlob(double size, Color color) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(shape: BoxShape.circle, color: color),
    );
  }

  Widget _buildBrandPanel({bool compact = false}) {
    return Column(
      crossAxisAlignment: compact
          ? CrossAxisAlignment.center
          : CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: compact ? 156 : 190,
          height: compact ? 96 : 120,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: Theme.of(context).cardColor.withOpacity(0.82),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: Theme.of(context).dividerColor),
            boxShadow: [
              BoxShadow(
                color: app_color.withOpacity(0.08),
                blurRadius: 24,
                offset: const Offset(0, 14),
              ),
            ],
          ),
          child: Image.asset(
            'assets/fincorego_logo_transparent.png',
            fit: BoxFit.contain,
            width: compact ? 138 : 168,
          ),
        ),
        const SizedBox(height: 22),
        Text(
          'Smart Finance. Simplified.',
          textAlign: compact ? TextAlign.center : TextAlign.start,
          style: GoogleFonts.poppins(
            color: Theme.of(context).colorScheme.onSurface,
            fontSize: compact ? 22 : 32,
            height: 1.14,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 10),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Text(
            'Secure access to your business dashboard, reports, and company data.',
            textAlign: compact ? TextAlign.center : TextAlign.start,
            style: GoogleFonts.poppins(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              fontSize: compact ? 13 : 15,
              height: 1.45,
              fontWeight: FontWeight.w400,
            ),
          ),
        ),
      ],
    );
  }

  /// "Fincore logo <-> TallyPrime logo" pairing - clarifies to a
  /// first-time user that this app pulls its data from their Tally
  /// installation rather than being a standalone bookkeeping app. Uses
  /// each brand's full logo (own wordmark included) rather than a
  /// cropped icon, so no separate text label is needed alongside them.
  ///
  /// Both logo files are cropped tight to their own visible content
  /// (fincorego_logo_transparent.png already is; tallyprime_logo.webp
  /// wasn't - it had a lot of transparent padding baked in, stripped by
  /// tallyprime_logo_trimmed.png), but their aspect ratios still differ a
  /// lot (Fincore's wordmark is wide ~1.3:1, TallyPrime's icon-over-text
  /// mark is narrow ~0.9:1) - matching just the *height* left Fincore's
  /// logo visibly wider/heavier than TallyPrime's at the same height. Both
  /// are pinned to the same WIDTH box instead (via BoxFit.contain) so they
  /// occupy equal horizontal footprint and read as a matched pair.
  Widget _buildTallySyncBadge({required bool compact}) {
    final logoWidth = compact ? 60.0 : 66.0;
    final logoHeight = compact ? 44.0 : 48.0;
    Widget logo(String asset) => SizedBox(
      width: logoWidth,
      height: logoHeight,
      child: Image.asset(asset, fit: BoxFit.contain),
    );

    // Plain content, no own background/shape - this now lives embedded
    // inside _buildAuthCard's own card (below the form, with a gap),
    // which already provides the background/border-radius/shadow; giving
    // this its own decorated Container on top of that would nest one
    // card-looking box inside another.
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            logo('assets/fincorego_logo_transparent.png'),
            const SizedBox(width: 10),
            Icon(
              Icons.sync_alt_rounded,
              size: 20,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: 10),
            logo('assets/tallyprime_logo_trimmed.png'),
          ],
        ),
        const SizedBox(height: 10),
        Text(
          '© 2023-2026 CSH LLC. All Rights Reserved.',
          style: GoogleFonts.poppins(
            fontSize: 11,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }

  Widget _buildAuthCard({
    required Key key,
    required Widget child,
    double? minHeight,
  }) {
    // The compact/phone layout already positions this card to overlap
    // the hero via a real Stack + Positioned (see build()'s
    // LayoutBuilder) - no translate needed here, this widget just
    // renders its own rounded-top-corner box normally.
    return Container(
        key: key,
        width: double.infinity,
        // Passed straight to Container's own `constraints:` (not just an
        // ambient BoxConstraints from a ConstrainedBox further up the
        // tree) - see _buildAnimatedAuthForm's doc comment for why that
        // ambient approach doesn't survive AnimatedSwitcher's internal
        // Stack. Container wraps its child in a real ConstrainedBox only
        // when given this parameter explicitly, which is what actually
        // forces the background to stretch to fill minHeight even when
        // the content (child) is shorter.
        constraints: minHeight != null
            ? BoxConstraints(minHeight: minHeight)
            : null,
        // Top padding is deliberately more than _heroCardOverlap - the
        // card's first content (the "Sign In" pill) must clear the
        // overlapped-into-hero zone and land in the card's own white
        // area, or it'd sit on top of the hero's similarly-colored
        // gradient and become nearly invisible (teal pill on teal hero).
        padding: const EdgeInsets.fromLTRB(24, 36, 24, 24),
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          // Top corners only, bigger radius (44) than before (28) - at
          // this size the curve (and the hero color peeking beside it)
          // is obvious at a normal glance, not just when zoomed in.
          // Reads as a sheet rising from the hero above it (edge-to-edge
          // on the compact/phone layout) rather than a bordered card
          // floating on the page.
          borderRadius: const BorderRadius.vertical(
            top: Radius.circular(50),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.12),
              blurRadius: 30,
              offset: const Offset(0, -4),
            ),
          ],
        ),
        // mainAxisSize.max + spaceBetween (not IntrinsicHeight, which
        // throws "RenderBox was not laid out" when a descendant sits
        // inside a SingleChildScrollView's child chain - tried first
        // and reverted) pushes the footer to the card's true bottom
        // when there's extra space, while still scrolling normally
        // with the rest of the card's content when there isn't (a
        // short screen/tall keyboard) - it needs to actually be part
        // of the same scrollable column, not a Positioned floating on
        // top of it (that doesn't move with scroll and can end up
        // overlapping the last form field/button instead - tried and
        // reverted too). This works without IntrinsicHeight because a
        // Column with mainAxisSize.max only throws on an unbounded
        // incoming maxHeight when it has an Expanded/Flexible child
        // demanding a share of that space - plain fixed-size children
        // (as here) just size to their natural sum, and spaceBetween
        // then distributes this Container's own resolved extra height
        // (from its `constraints: BoxConstraints(minHeight: ...)`
        // above) between them instead.
        child: Column(
          mainAxisSize: MainAxisSize.max,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            // Padding (not a bare SizedBox as a 3rd spaceBetween child -
            // that would split the leftover space into two gaps instead
            // of one) guarantees at least 32px between the form and the
            // footer even when spaceBetween's own leftover space is
            // small (a tall form/short screen).
            Padding(
              padding: const EdgeInsets.only(bottom: 32),
              child: child,
            ),
            _buildTallySyncBadge(compact: true),
          ],
        ),
    );
  }

  // Smaller than the card's own top corner radius (50, see _buildAuthCard)
  // so the corner curve still shows, but big enough that the white sheet
  // climbing up over the hero's flat bottom edge is obvious at a normal
  // glance - not just visible when zoomed into the corner pixels. At 0
  // (no climb at all) the card just sits at its natural position right
  // below the hero, and its corner cut-out only reveals the page's own
  // background gradient behind it (not the hero), which is why the
  // scoop looked mismatched/asymmetric instead of showing hero-teal.
  static const double _heroCardOverlap = 40;

  /// The "Remember Me" switch+label and "Forgot Password?" link sit in a
  /// row when both genuinely fit on one line, and drop to a left-aligned
  /// column (instead of a centered/space-between leftover layout) when
  /// they don't - small phones, or larger accessibility text scale.
  /// Measures each side's actual rendered width via [TextPainter] rather
  /// than guessing a breakpoint, so the decision matches reality.
  Widget _buildRememberMeAndForgotPasswordRow() {
    final forgotPasswordButton = TextButton(
      style: TextButton.styleFrom(
        foregroundColor: app_color,
        padding: const EdgeInsets.symmetric(horizontal: 4),
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        textStyle: GoogleFonts.poppins(
          fontSize: 13.5,
          fontWeight: FontWeight.w700,
        ),
      ),
      onPressed: () {
        resetemailController.text = usernameController.text;
        passwordController.clear();
        _login_.update(
          (s) => s.copyWith(
            isVisibleLoginForm: false,
            isVisibleResetPassForm: true,
          ),
        );
      },
      child: const Text('Forgot Password?'),
    );

    if (_s.biometricAvailable && _s.biometricEnabled) {
      // No Remember Me switch to share the row with - always fits, always
      // right-aligned, same as before. Matches the exact condition that
      // decides whether the "Sign in with Face ID/Fingerprint" button
      // itself is shown (below) - checking `biometricEnabled` alone here
      // was a real bug: `biometricEnabled` is a persisted preference that
      // can be `true` from a stale/previous state (e.g. `local_auth`
      // falsely reporting biometric hardware as available on an iOS
      // Simulator with no Face ID actually enrolled - see
      // `BiometricAuthService.authenticate`'s own doc-comment), leaving a
      // device with no real biometric hardware showing neither the
      // biometric button NOR Remember Me - completely stuck.
      return Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [forgotPasswordButton],
      );
    }

    final rememberMeRow = GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _s.isRememberMeAutoLoggingIn
          ? null
          : () => _onRememberMeChanged(!_s.rememberMeEnabled),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 22,
            height: 22,
            child: Checkbox(
              value: _s.rememberMeEnabled,
              activeColor: app_color,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(6),
              ),
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              onChanged: _s.isRememberMeAutoLoggingIn
                  ? null
                  : (value) => _onRememberMeChanged(value ?? false),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            'Remember Me',
            style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w500),
          ),
        ],
      ),
    );

    const switchWidth = 22.0 + 8;
    final textScaler = MediaQuery.textScalerOf(context);
    final rememberMeTextWidth =
        (TextPainter(
              text: TextSpan(
                text: 'Remember Me',
                style: GoogleFonts.poppins(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
              textDirection: TextDirection.ltr,
              textScaler: textScaler,
            )..layout())
            .width;
    final forgotPasswordTextWidth =
        (TextPainter(
              text: TextSpan(
                text: 'Forgot Password?',
                style: GoogleFonts.poppins(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
              textDirection: TextDirection.ltr,
              textScaler: textScaler,
            )..layout())
            .width;

    final rememberMeWidth = switchWidth + 4 + rememberMeTextWidth;
    final forgotPasswordWidth = forgotPasswordTextWidth + 8;
    const minGap = 16.0;
    final neededWidth = rememberMeWidth + minGap + forgotPasswordWidth;

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth >= neededWidth) {
          return Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [rememberMeRow, forgotPasswordButton],
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            rememberMeRow,
            const SizedBox(height: 4),
            forgotPasswordButton,
          ],
        );
      },
    );
  }

  Widget _buildFormHeader({
    required IconData icon,
    required String title,
    String? subtitle,
  }) {
    return Column(
      children: [
        Container(
          width: 54,
          height: 54,
          decoration: BoxDecoration(
            color: app_color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Icon(icon, color: app_color, size: 28),
        ),
        const SizedBox(height: 16),
        Text(
          title,
          textAlign: TextAlign.center,
          style: GoogleFonts.poppins(
            color: Theme.of(context).colorScheme.onSurface,
            fontSize: 22,
            fontWeight: FontWeight.w700,
          ),
        ),
        if (subtitle != null) ...[
          const SizedBox(height: 8),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: GoogleFonts.poppins(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              fontSize: 13.5,
              height: 1.45,
              fontWeight: FontWeight.w400,
            ),
          ),
        ],
      ],
    );
  }

  InputDecoration _inputDecoration({
    required String label,
    required IconData icon,
    Widget? suffixIcon,
  }) {
    // Flat, borderless filled fields (no visible outline in any state
    // except a real validation error) - matches the reference design's
    // plain grey pill-shaped fields rather than a standard bordered
    // Material text field.
    return InputDecoration(
      prefixIcon: Icon(icon, color: Theme.of(context).colorScheme.onSurfaceVariant),
      suffixIcon: suffixIcon,
      hintText: label,
      hintStyle: GoogleFonts.poppins(
        color: Theme.of(context).colorScheme.onSurfaceVariant,
        fontWeight: FontWeight.w500,
        fontSize: 14.5,
      ),
      filled: true,
      fillColor: Theme.of(context).brightness == Brightness.dark
          ? Theme.of(context).colorScheme.surfaceContainerHigh
          : const Color(0xFFF1F4F7),
      contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: app_color, width: 1.6),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: Color(0xFFE85C5C), width: 1.2),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: Color(0xFFE85C5C), width: 1.6),
      ),
    );
  }

  ButtonStyle _primaryButtonStyle() {
    return ElevatedButton.styleFrom(
      minimumSize: const Size.fromHeight(52),
      backgroundColor: app_color,
      foregroundColor: Colors.white,
      disabledBackgroundColor: Theme.of(context).brightness == Brightness.dark
          ? Colors.grey.shade700
          : const Color(0xFFCCD3D9),
      disabledForegroundColor: Colors.white,
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      textStyle: GoogleFonts.poppins(fontSize: 15, fontWeight: FontWeight.w700),
    );
  }

  ButtonStyle _secondaryButtonStyle() {
    return ElevatedButton.styleFrom(
      minimumSize: const Size.fromHeight(50),
      backgroundColor: Theme.of(context).brightness == Brightness.dark
          ? Theme.of(context).colorScheme.surfaceContainerHigh
          : const Color(0xFFF1F4F7),
      foregroundColor: Theme.of(context).colorScheme.onSurface,
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      textStyle: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w700),
    );
  }

  Widget _buildLoginForm(BuildContext context, {double? minHeight}) {
    return _buildAuthCard(
      key: const ValueKey('loginForm'),
      minHeight: minHeight,
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Same icon-box + title style as the other forms'
            // _buildFormHeader (reset password, OTP entry) instead of
            // the earlier standalone "Sign In" pill/chip, for visual
            // consistency across all of this card's forms.
            Align(
              alignment: Alignment.center,
              child: _buildFormHeader(
                icon: Icons.login_rounded,
                title: 'Sign In',
                subtitle: 'Enter your credentials to access your account.',
              ),
            ),
            const SizedBox(height: 24),
            TextFormField(
              controller: usernameController,
              focusNode: _usernameFocusNode,
              keyboardType: TextInputType.emailAddress,
              textInputAction: TextInputAction.next,
              decoration: _inputDecoration(
                label: 'Username or email',
                icon: Icons.alternate_email_rounded,
              ),
              validator: (v) {
                if (v == null || v.trim().isEmpty) {
                  return 'Please enter username or email';
                }
                return null;
              },
              onSaved: (v) => usernamee = v!,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: passwordController,
              focusNode: _passwordFocusNode,
              obscureText: _obscureText,
              textInputAction: TextInputAction.done,
              decoration: _inputDecoration(
                label: 'Password',
                icon: Icons.lock_outline_rounded,
                suffixIcon: IconButton(
                  tooltip: _obscureText ? 'Show password' : 'Hide password',
                  icon: Icon(
                    _obscureText
                        ? Icons.visibility_off_rounded
                        : Icons.visibility_rounded,
                    color: const Color(0xFF7A858F),
                  ),
                  onPressed: () => setState(() => _obscureText = !_obscureText),
                ),
              ),
              validator: (v) =>
                  v == null || v.isEmpty ? 'Please enter password' : null,
              onSaved: (v) => passwordd = v!,
            ),
            const SizedBox(height: 8),
            _buildRememberMeAndForgotPasswordRow(),
            const SizedBox(height: 14),
            _s.isLoading
                ? SizedBox(
                    height: 52,
                    child: Center(
                      child: CupertinoActivityIndicator(color: app_color),
                    ),
                  )
                : ElevatedButton.icon(
                    style: _primaryButtonStyle(),
                    onPressed: isButtonDisabled
                        ? null
                        : () {
                            if (_formKey.currentState != null &&
                                _formKey.currentState!.validate()) {
                              _formKey.currentState!.save();
                              _persistRememberMeCredentialsIfEnabled();
                              _login();
                            }
                          },
                    icon: const Icon(Icons.login_rounded),
                    label: const Text('Login'),
                  ),
            if (_s.biometricAvailable && _s.biometricEnabled) ...[
              const SizedBox(height: 14),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: app_color,
                  side: BorderSide(color: app_color),
                  minimumSize: const Size.fromHeight(48),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                onPressed:
                    _s.isBiometricAuthenticating ? null : _biometricLogin,
                icon: Icon(
                  _s.biometricLabel == 'Face ID'
                      ? Icons.face_retouching_natural
                      : Icons.fingerprint,
                ),
                label: Text('Sign in with ${_s.biometricLabel}'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildResetForm(BuildContext context, {double? minHeight}) {
    return _buildAuthCard(
      key: const ValueKey('resetForm'),
      minHeight: minHeight,
      child: Form(
        key: _resetformKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildFormHeader(
              icon: Icons.lock_reset_rounded,
              title: 'Reset password',
              subtitle:
                  'Enter your registered email and we will send a reset link.',
            ),
            const SizedBox(height: 26),
            TextFormField(
              controller: resetemailController,
              focusNode: _resetemailFocusNode,
              keyboardType: TextInputType.emailAddress,
              textInputAction: TextInputAction.done,
              decoration: _inputDecoration(
                label: 'Registered email address',
                icon: Icons.mail_outline_rounded,
              ),
              validator: (v) {
                if (v == null || v.isEmpty) return 'Please enter email';
                if (!RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$').hasMatch(v)) {
                  return 'Invalid email';
                }
                return null;
              },
            ),
            const SizedBox(height: 24),
            _s.isLoadingResetPass
                ? SizedBox(
                    height: 52,
                    child: Center(
                      child: CupertinoActivityIndicator(color: app_color),
                    ),
                  )
                : ElevatedButton.icon(
                    style: _primaryButtonStyle(),
                    onPressed: isResetPassButtonDisabled
                        ? null
                        : () {
                            if (_resetformKey.currentState!.validate()) {
                              if (resetemailController.text.trim() ==
                                  'demouser@ca-eim.com') {
                                showAppMessage(
                                  context,
                                  'Reset password is not allowed for Demo User',
                                );
                              } else {
                                _resetpass();
                              }
                            }
                          },
                    icon: const Icon(Icons.outgoing_mail),
                    label: const Text('Send reset link'),
                  ),
            const SizedBox(height: 12),
            ElevatedButton.icon(
              style: _secondaryButtonStyle(),
              onPressed: () {
                usernameController.text = resetemailController.text;
                resetemailController.clear();
                _login_.update(
                  (s) => s.copyWith(
                    isVisibleResetPassForm: false,
                    isVisibleLoginForm: true,
                  ),
                );
              },
              icon: const Icon(Icons.arrow_back_rounded),
              label: const Text('Back to login'),
            ),
          ],
        ),
      ),
    );
  }

  /// Step 2 of the tally-oauth password reset flow - OTP + new password,
  /// shown after [_resetpass] successfully requests the code. Mirrors
  /// ChangePassword.dart's OTP step UI-wise, adapted to this file's
  /// existing `_buildAuthCard`/`_inputDecoration`/button-style helpers.
  Widget _buildResetOtpForm(BuildContext context, {double? minHeight}) {
    return _buildAuthCard(
      key: const ValueKey('resetOtpForm'),
      minHeight: minHeight,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildFormHeader(
            icon: Icons.mark_email_read_rounded,
            title: 'Reset your password',
            subtitle:
                'Enter the 6-digit code sent to ${resetemailController.text}, then choose a new password.',
          ),
          const SizedBox(height: 26),
          LayoutBuilder(
            builder: (context, constraints) => PinCodeTextField(
              appContext: context,
              controller: resetOtpController,
              length: 6,
              keyboardType: TextInputType.number,
              enabled: !_s.isVerifyingResetOtp,
              animationType: AnimationType.fade,
              onChanged: (value) {
                // Editing after a confirmed/failed attempt un-confirms so
                // the password fields hide again until re-verified.
                if (value.length < 6 && _s.isResetOtpConfirmed) {
                  _login_.update(
                    (s) => s.copyWith(isResetOtpConfirmed: false),
                  );
                }
              },
              onCompleted: _verifyResetOtp,
              mainAxisAlignment: MainAxisAlignment.center,
              separatorBuilder: otpPinSeparator,
              pinTheme: PinTheme(
                shape: PinCodeFieldShape.box,
                borderRadius: BorderRadius.circular(12),
                fieldHeight: 46,
                fieldWidth: otpFieldWidth(constraints.maxWidth),
                activeFillColor: app_color.withOpacity(0.1),
                inactiveFillColor:
                    Theme.of(context).brightness == Brightness.dark
                    ? const Color(0xFF1F2937)
                    : const Color(0xFFF7F9FB),
                selectedFillColor:
                    Theme.of(context).brightness == Brightness.dark
                    ? const Color(0xFF1F2937)
                    : Colors.white,
                activeColor: app_color,
                inactiveColor: Theme.of(context).dividerColor,
                selectedColor: app_color,
                borderWidth: 1.2,
              ),
              enableActiveFill: true,
              // resetOtpController is a class-level field this State owns
              // and disposes itself (see dispose()) - pin_code_fields
              // defaults to disposing the controller it's given the moment
              // this widget unmounts (e.g. "Back to login"/successful
              // reset switch away from this form), which would leave the
              // shared controller unusable on a later reset attempt and
              // double-dispose it in dispose(). Must stay false wherever a
              // controller outlives one PinCodeTextField instance.
              autoDisposeControllers: false,
            ),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeInOut,
            alignment: Alignment.topCenter,
            child: !_s.isResetOtpConfirmed
                ? Padding(
                    padding: const EdgeInsets.only(top: 14),
                    child: _s.isVerifyingResetOtp
                        ? Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              SizedBox(
                                height: 14,
                                width: 14,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: app_color,
                                ),
                              ),
                              const SizedBox(width: 10),
                              Text(
                                'Verifying code...',
                                style: GoogleFonts.poppins(
                                  fontSize: 12.5,
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          )
                        : Text(
                            'Enter the code above to set a new password.',
                            textAlign: TextAlign.center,
                            style: GoogleFonts.poppins(
                              fontSize: 12.5,
                              color: Theme.of(
                                context,
                              ).colorScheme.onSurfaceVariant,
                            ),
                          ),
                  )
                : Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: newPasswordController,
                        obscureText: !_isNewPasswordVisible,
                        decoration: _inputDecoration(
                          label: 'New password',
                          icon: Icons.lock_reset_rounded,
                          suffixIcon: IconButton(
                            icon: Icon(
                              _isNewPasswordVisible
                                  ? Icons.visibility_off_rounded
                                  : Icons.visibility_rounded,
                            ),
                            onPressed: () => setState(
                              () => _isNewPasswordVisible =
                                  !_isNewPasswordVisible,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: confirmNewPasswordController,
                        obscureText: !_isConfirmNewPasswordVisible,
                        decoration: _inputDecoration(
                          label: 'Confirm new password',
                          icon: Icons.check_circle_outline_rounded,
                          suffixIcon: IconButton(
                            icon: Icon(
                              _isConfirmNewPasswordVisible
                                  ? Icons.visibility_off_rounded
                                  : Icons.visibility_rounded,
                            ),
                            onPressed: () => setState(
                              () => _isConfirmNewPasswordVisible =
                                  !_isConfirmNewPasswordVisible,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),
                      _s.isConfirmingPasswordReset
                          ? SizedBox(
                              height: 52,
                              child: Center(
                                child: CupertinoActivityIndicator(
                                  color: app_color,
                                ),
                              ),
                            )
                          : ElevatedButton.icon(
                              style: _primaryButtonStyle(),
                              onPressed: _confirmPasswordReset,
                              icon: const Icon(Icons.verified_rounded),
                              label: const Text('Change password'),
                            ),
                    ],
                  ),
          ),
          const SizedBox(height: 12),
          ElevatedButton.icon(
            style: _secondaryButtonStyle(),
            onPressed: () {
              _login_.update(
                (s) => s.copyWith(
                  clearPasswordResetToken: true,
                  isVisibleResetOtpForm: false,
                  isVisibleLoginForm: true,
                  isResetOtpConfirmed: false,
                ),
              );
              usernameController.text = resetemailController.text;
              resetemailController.clear();
              resetOtpController.clear();
              newPasswordController.clear();
              confirmNewPasswordController.clear();
            },
            icon: const Icon(Icons.arrow_back_rounded),
            label: const Text('Back to login'),
          ),
        ],
      ),
    );
  }

  Widget _buildOtpForm(BuildContext context, {double? minHeight}) {
    return _buildAuthCard(
      key: const ValueKey('otpForm'),
      minHeight: minHeight,
      child: Form(
        key: _otpformKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildFormHeader(
              icon: Icons.mark_email_read_rounded,
              title: 'Verify your login',
              subtitle: 'Enter the 6-digit code sent to your email address.',
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
              decoration: BoxDecoration(
                color: Theme.of(context).brightness == Brightness.dark
                    ? const Color(0xFF1F2937)
                    : const Color(0xFFF7F9FB),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: Theme.of(context).dividerColor),
              ),
              child: Text(
                _s.maskedEmail,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.poppins(
                  color: Theme.of(context).colorScheme.onSurface,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(height: 26),
            LayoutBuilder(
              builder: (context, constraints) => PinCodeTextField(
                appContext: context,
                controller: otpController,
                // Matches the backend's OtpProvider.generate() default (6
                // digits, every OTP flow) - was 4 from the old client-side
                // fake OTP, which physically blocked entering a real code.
                length: 6,
                enabled: !_s.isOtpVerifyingProgress,
                animationType: AnimationType.fade,
                onChanged: (value) {
                  currentText = value;
                },
                onCompleted: (value) {
                  currentText = value;
                  _verifyOtpAndProceed(value);
                },
                mainAxisAlignment: MainAxisAlignment.center,
                separatorBuilder: otpPinSeparator,
                pinTheme: PinTheme(
                  shape: PinCodeFieldShape.box,
                  borderRadius: BorderRadius.circular(12),
                  fieldHeight: 46,
                  fieldWidth: otpFieldWidth(constraints.maxWidth),
                  activeFillColor: app_color.withOpacity(0.1),
                  inactiveFillColor:
                      Theme.of(context).brightness == Brightness.dark
                      ? const Color(0xFF1F2937)
                      : const Color(0xFFF7F9FB),
                  selectedFillColor:
                      Theme.of(context).brightness == Brightness.dark
                      ? const Color(0xFF1F2937)
                      : Colors.white,
                  activeColor: app_color,
                  inactiveColor: Theme.of(context).dividerColor,
                  selectedColor: app_color,
                  borderWidth: 1.2,
                ),
                animationDuration: const Duration(milliseconds: 200),
                enableActiveFill: true,
                // Same reason as resetOtpController's PinCodeTextField
                // above - otpController is a shared class-level field this
                // State disposes itself, not owned by a single field
                // instance.
                autoDisposeControllers: false,
                keyboardType: TextInputType.number,
                obscureText: false,
              ),
            ),
            const SizedBox(height: 22),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 180),
              child: _s.isVisibleTimer
                  ? Container(
                      key: const ValueKey('timer'),
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        color: app_color.withOpacity(0.08),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Text(
                        "Resend OTP in ${_s.formattedTimerTime}",
                        textAlign: TextAlign.center,
                        style: GoogleFonts.poppins(
                          fontSize: 13.5,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    )
                  : const SizedBox.shrink(key: ValueKey('noTimer')),
            ),
            if (_s.isResendButtonEnabled) ...[
              const SizedBox(height: 12),
              ElevatedButton.icon(
                style: _secondaryButtonStyle(),
                icon: const Icon(Icons.refresh_rounded),
                // Reuses _otplogin wholesale rather than duplicating its
                // send-OTP-and-update-state logic - a resend is exactly
                // that (a fresh backend-verified send, a fresh token, a
                // restarted timer), not a different operation.
                onPressed: () => _otplogin(usernamee),
                label: const Text('Resend OTP'),
              ),
            ],
            const SizedBox(height: 14),
            ElevatedButton.icon(
              style: _primaryButtonStyle().copyWith(
                backgroundColor: MaterialStateProperty.resolveWith<Color>(
                  (states) => _s.isOtpVerifyingProgress
                      ? const Color(0xFF98A2AD)
                      : app_color,
                ),
              ),
              icon: _s.isOtpVerifyingProgress
                  ? Theme.of(context).platform == TargetPlatform.iOS
                        ? const CupertinoActivityIndicator(
                            radius: 9,
                            color: Colors.white,
                          )
                        : const SizedBox(
                            height: 18,
                            width: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.3,
                              valueColor: AlwaysStoppedAnimation<Color>(
                                Colors.white,
                              ),
                              backgroundColor: Colors.transparent,
                            ),
                          )
                  : const Icon(Icons.verified_rounded),
              onPressed: _s.isOtpVerifyingProgress
                  ? null
                  : () {
                      _verifyOtpAndProceed(currentText);
                    },
              label: Text(
                _s.isOtpVerifyingProgress ? 'Verifying...' : 'Verify',
              ),
            ),
            const SizedBox(height: 12),
            TextButton.icon(
              style: TextButton.styleFrom(
                foregroundColor: const Color(0xFF596672),
                textStyle: GoogleFonts.poppins(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
              onPressed: () {
                otpController.clear();
                _login_.update(
                  (s) => s.copyWith(
                    isVisibleOTPForm: false,
                    isVisibleLoginForm: true,
                    isVisibleTimer: false,
                  ),
                );
              },
              icon: const Icon(Icons.arrow_back_rounded),
              label: const Text("Back to login"),
            ),
          ],
        ),
      ),
    );
  }
}
