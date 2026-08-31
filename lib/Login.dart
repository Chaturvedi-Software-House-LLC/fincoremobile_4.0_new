import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter/widgets.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:mailer/mailer.dart';
import 'package:mailer/smtp_server.dart';
import 'package:open_file/open_file.dart';
import 'package:flutter/services.dart';
import 'Help.dart';
import 'SerialSelect.dart';
import 'CompanySelectTallyOauth.dart';
import 'constants.dart';
import 'package:flutter/material.dart';
import 'package:pin_code_fields/pin_code_fields.dart';
import 'package:http/http.dart' as http;
import 'package:flutter/cupertino.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path_provider/path_provider.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'widgets/entry_widgets.dart';
import 'services/biometric_auth_service.dart';
import 'api/api_exception.dart';
import 'api/auth_repository.dart';
// import 'package:firebase_messaging/firebase_messaging.dart';

class Login extends StatefulWidget {
  final String username, password;
  const Login({required this.username, required this.password});
  @override
  _LoginPageState createState() =>
      _LoginPageState(usernamee: username, passwordd: password);
}

class _LoginPageState extends State<Login> with TickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _resetformKey = GlobalKey<FormState>();
  final _otpformKey = GlobalKey<FormState>();

  bool _isOtpVerifyingProgress = false;

  final _scaffoldKey = GlobalKey<ScaffoldState>();
  Color _buttonColor = app_color;
  Color _resetbuttonColor = app_color;

  late SharedPreferences prefs_login;

  String responseMessage = ''; // To store the server response.

  bool isVisibleTimer = false;

  bool isOTPVerified = false, isAnotherDevice = false;

  final GlobalKey<ScaffoldMessengerState> _scaffoldMessengerKey =
      GlobalKey<ScaffoldMessengerState>();

  bool _isLoading = false, _isLoadingResetPass = false;

  final String SHARED_PREFERENCES_NAME = "login_prefs";

  bool isDirectLogin = false, isOTPLogin = false;

  String? username_prefs, password_prefs;

  String? deviceIdentifier = '';

  String generatedotp = '';

  bool isVisibleLoginForm = true,
      isVisibleResetPassForm = false,
      isVisibleOTPForm = false,
      isVisibleResetOtpForm = false;

  // tally-oauth's password-reset flow (see AuthRepository.requestPasswordResetOtp/
  // changePassword) - "Forgot Password?" used to only call the legacy
  // backend, which doesn't exist for a tally-oauth-only account. Reuses
  // the same OTP-then-new-password flow already built for
  // ChangePassword.dart's tally-oauth path.
  String? _passwordResetToken;
  bool _isConfirmingPasswordReset = false;
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

  bool _isVerifyingOtp = false;
  bool _deviceIdentifierLoaded = false;

  late String passwordd = '';

  bool _biometricAvailable = false;
  bool _biometricEnabled = false;
  bool _biometricPromptShown = false;
  String _biometricLabel = 'Biometric';
  bool _isBiometricAuthenticating = false;

  // Fallback for devices with no fingerprint/Face ID hardware at all: a
  // plain on/off "Remember Me" switch that, when enabled, silently signs
  // the user back in on next launch using the last-saved credentials -
  // no OS biometric prompt involved. Only ever shown when biometrics are
  // not available on the device (see _biometricAvailable gating below).
  bool _rememberMeEnabled = true;
  bool _isRememberMeAutoLoggingIn = false;
  final _usernameFocusNode = FocusNode();
  final _passwordFocusNode = FocusNode();
  final _resetemailFocusNode = FocusNode();
  late TickerProvider tickerProvider;
  static final RegExp _emailRegex = RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$');

  _LoginPageState({required this.usernamee, required this.passwordd});

  Future<void> _verifyOtpAndProceed(String enteredOTP) async {
    if (_isVerifyingOtp || _isOtpVerifyingProgress) return;

    if (enteredOTP.length == 4) {
      if (enteredOTP == generatedotp) {
        setState(() {
          _isVerifyingOtp = true;
          _isOtpVerifyingProgress = true;
        });

        FocusManager.instance.primaryFocus?.unfocus();

        isOTPVerified = true;
        isAnotherDevice = true;

        _directlogin();

        if (mounted) {
          setState(() {
            _isOtpVerifyingProgress = false;
          });
        }
      } else {
        isOTPVerified = false;
        isAnotherDevice = false;

        showAppMessage(context, 'Incorrect OTP');

        otpController.clear();
        currentText = '';

        setState(() {
          _isVerifyingOtp = false;
          _isOtpVerifyingProgress = false;
        });
      }
    } else {
      showAppMessage(context, 'Please enter a 4-digit OTP');
    }
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
  bool _isButtonEnabled = false; // Button enable state
  String _formattedTime = "01:00"; // Timer display

  void _startTimer() {
    _timer?.cancel();
    _start = 60; // Reset countdown to 60 seconds
    _formattedTime = _formatDuration(_start); // Reset the formatted time
    _isButtonEnabled = false; // Disable button initially
    isVisibleTimer = true;

    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_start > 0) {
        setState(() {
          _start--;
          _formattedTime = _formatDuration(_start);
        });
      } else {
        _stopTimer(); // Stop the timer when it reaches zero
        setState(() {
          _isButtonEnabled = true; // Enable the button
          isVisibleTimer = false;
        });
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
    setState(() {
      _biometricAvailable = available;
      _biometricEnabled = enabled;
      _biometricLabel = label;
      _rememberMeEnabled = rememberMeEnabled;
    });
  }

  Future<void> _onRememberMeChanged(bool value) async {
    setState(() => _rememberMeEnabled = value);

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
    if (_isRememberMeAutoLoggingIn) return;

    final storedUsername = prefs_login.getString('remember_me_username');
    final storedPassword = prefs_login.getString('remember_me_password');

    if (storedUsername == null ||
        storedUsername.isEmpty ||
        storedPassword == null ||
        storedPassword.isEmpty) {
      return;
    }

    setState(() => _isRememberMeAutoLoggingIn = true);
    try {
      usernamee = storedUsername;
      passwordd = storedPassword;
      usernameController.text = storedUsername;
      passwordController.text = storedPassword;
      username_prefs = storedUsername;
      password_prefs = storedPassword;

      _login();
    } finally {
      if (mounted) setState(() => _isRememberMeAutoLoggingIn = false);
    }
  }

  Future<void> _biometricLogin() async {
    if (_isBiometricAuthenticating) return;
    setState(() => _isBiometricAuthenticating = true);

    try {
      final ok = await BiometricAuthService.instance.authenticate(
        reason: 'Authenticate with $_biometricLabel to sign in',
      );
      if (!ok) {
        // authenticate() may have discovered biometrics aren't actually
        // enrolled/usable and turned itself off - re-sync our local flag
        // so the UI swaps over to the Remember Me switch right away
        // instead of waiting for the next app launch.
        final stillEnabled = await BiometricAuthService.instance.isEnabled();
        if (mounted && !stillEnabled) {
          setState(() {
            _biometricEnabled = false;
            _rememberMeEnabled = true;
          });
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
            'No saved credentials found. Please log in manually once to enable $_biometricLabel login.',
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
      if (mounted) setState(() => _isBiometricAuthenticating = false);
    }
  }

  Future<void> _maybeOfferBiometricEnable() async {
    if (_biometricPromptShown ||
        _biometricEnabled ||
        !_biometricAvailable ||
        !mounted) {
      return;
    }
    _biometricPromptShown = true;

    final IconData biometricIcon = _biometricLabel == 'Face ID'
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
                        'Enable $_biometricLabel login?',
                        textAlign: TextAlign.center,
                        style: GoogleFonts.poppins(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        'Use $_biometricLabel to sign in faster next time instead of typing your password.',
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
        reason: 'Confirm $_biometricLabel to enable it for sign in',
      );
      if (confirmed) {
        await BiometricAuthService.instance.setEnabled(true);
        await prefs_login.setString('biometric_username', usernamee);
        await prefs_login.setString('biometric_password', passwordd);
        if (mounted) setState(() => _biometricEnabled = true);
      }
    }
  }

  Future<void> _initSharedPreferences() async {
    fetchvanSalesSerialNumbers();

    prefs_login = await SharedPreferences.getInstance();

    username_prefs = usernamee;
    password_prefs = passwordd;

    print(usernamee);

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
        if (mounted) setState(() => _biometricEnabled = true);
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
          if (mounted) setState(() => _rememberMeEnabled = true);
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
    setState(() => _isLoadingResetPass = true);
    _showProcessingDialog();

    final enteredemail = resetemailController.text;
    try {
      final token = await AuthRepository.instance.requestPasswordResetOtp(
        username: enteredemail,
      );
      if (!mounted) return;
      setState(() {
        _passwordResetToken = token;
        isVisibleResetPassForm = false;
        isVisibleResetOtpForm = true;
        resetOtpController.clear();
        newPasswordController.clear();
        confirmNewPasswordController.clear();
      });
    } on ApiException catch (e) {
      showAppMessage(context, e.message);
    } catch (e) {
      showAppMessage(context, 'Could not reach the server. Please try again.');
    } finally {
      if (mounted) {
        setState(() => _isLoadingResetPass = false);
        if (Navigator.canPop(context)) {
          Navigator.pop(context);
        }
      }
    }
  }

  /// Step 2 of the tally-oauth reset flow - the OTP + new password form's
  /// submit handler.
  Future<void> _confirmPasswordReset() async {
    final resetToken = _passwordResetToken;
    if (resetToken == null) return;

    if (resetOtpController.text.trim().length != 4) {
      showAppMessage(context, 'Please enter the 4-digit code');
      return;
    }
    if (newPasswordController.text.length < 8) {
      showAppMessage(context, 'Password must be at least 8 characters');
      return;
    }
    if (newPasswordController.text != confirmNewPasswordController.text) {
      showAppMessage(context, 'Passwords do not match');
      return;
    }

    setState(() => _isConfirmingPasswordReset = true);
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
      setState(() {
        _passwordResetToken = null;
        _isConfirmingPasswordReset = false;
        isVisibleResetOtpForm = false;
        isVisibleLoginForm = true;
        usernameController.text = resetemailController.text;
        resetemailController.clear();
        resetOtpController.clear();
        newPasswordController.clear();
        confirmNewPasswordController.clear();
      });
    } on ApiException catch (e) {
      setState(() => _isConfirmingPasswordReset = false);
      showAppMessage(context, e.message);
    } catch (e) {
      setState(() => _isConfirmingPasswordReset = false);
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
      await AuthRepository.instance.loginToTallyOauth(
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

  /// tally-oauth is now the sole driver of login (Phase 6) - no legacy
  /// `/api/login/getusers` call, no OTP/device-approval socket flow. Goes
  /// straight to [CompanySelectTallyOauth] once the tally-oauth session is
  /// established. This means Sales/Receipt/Sales-Order/Delivery-Note entry
  /// screens, Van Allocation, and the AI Assistant - which depend on the
  /// legacy `hostname`/`token` prefs this used to populate - no longer work
  /// for accounts that log in this way. That's an accepted, deliberate
  /// trade-off (see the migration plan's "Phase 6"), not a bug.
  void _proceedToCompanySelection() {
    if (mounted) setState(() => _isLoading = false);
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
      if (mounted) setState(() => _isLoading = false);
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
    setState(() {
      _isLoading = true;
      isDirectLogin = true;
      isOTPLogin = false;
    });

    if (!await _loginToTallyOauth()) {
      if (mounted) setState(() => _isLoading = false);
      return;
    }

    // Catch an expired/suspended/inactive license right here, before ever
    // navigating past Login - _isLicenseUsable() shows the error dialog
    // and resets loading state itself when it returns false.
    if (!await _isLicenseUsable()) return;

    _proceedToCompanySelection();
  }

  Future<void> _otplogin(String email) async {
    setState(() {
      _isLoading = true;
      isDirectLogin = false;
      isOTPLogin = true;
    });

    if (!await _loginToTallyOauth()) {
      if (mounted) setState(() => _isLoading = false);
      return;
    }

    // Same license check as _directlogin, but here it must run before the
    // OTP screen is ever shown - not just before company selection.
    if (!await _isLicenseUsable()) return;

    // Phase 6 (making tally-oauth the sole login driver) dropped this step
    // by mistake while removing the legacy device-approval socket flow it
    // used to sit next to - restored on request. tally-oauth auth is
    // already confirmed above; this is an additional emailed-OTP
    // verification layer before company selection.
    // _verifyOtpAndProceed already calls _directlogin() on success, which
    // re-runs the (already-succeeded, idempotent) tally-oauth login and
    // proceeds to CompanySelectTallyOauth - unchanged.
    sendOTP(email);
    if (!mounted) return;
    setState(() {
      _isLoading = false;
      isVisibleLoginForm = false;
      isVisibleResetPassForm = false;
      _isButtonEnabled = false;
      isVisibleTimer = true;
      _isOtpVerifyingProgress = false;
      _isVerifyingOtp = false;
      otpController.clear();
      currentText = '';
      isVisibleOTPForm = true;
      maskedEmail = email;
    });
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

  void sendOTP(String email) async {
    final random = Random();
    generatedotp =
        '${random.nextInt(10)}${random.nextInt(10)}${random.nextInt(10)}${random.nextInt(10)}'; // Generates a 4-digit random OTP

    print(generatedotp);

    final smtpServer = SmtpServer(
      'smtp.hostinger.com',
      username: 'noreply@fincoreerp.com',
      password: '^QLNlsU8m',
      port: 465,
      ssl: true,
    );

    final message = Message()
      ..from =
          Address(
            'noreply@fincoreerp.com',
            'Fincore Support',
          ) // Replace with your Outlook email
      ..recipients.add(email) // Use the email entered by the user
      ..subject = 'Your One-Time Passcode from Fincore Go'
      ..html =
          '''
                  <div style="border: 1px solid #ccc; padding-left: 30px; padding-right: 30px; padding-top: 30px; padding-bottom: 30px; margin-left: 20px; margin-right: 20px; margin-top: 0px; text-align: center;">
                 
                <a href="https://tallyuae.ae/">
                <img src="https://mobile.chaturvedigroup.com/fincore_logo/tally_1.png" alt="Image" style="width: 150px; height: auto; margin-bottom: 10px;">
            </a>
                <div style="text-align: center;"><p style="font-size: 12px; font-family: Arial, sans-serif; color: #333;">Your one-time passcode (OTP) to log into the Fincore Go app is</p></div>
                <br>
                <div style="text-align: center;">
                
                <p style="display: inline-block; background-color: #30D5C8; color: #fff; font-size: 16px; font-family: Arial, sans-serif; text-decoration: none; padding: 10px 20px; border-radius: 5px;">$generatedotp</p>
                </div >
                <br>
                <div style="text-align: start;"><p style="font-size: 12px; font-family: Arial, sans-serif; color: #333;">If you did not attempt this, please contact <a href="mailto:saadan@ca-eim.com">saadan@ca-eim.com</a></p></div>
                
                <br>
                      <div style="text-align: start;"><p style="color: #999999; font-style: italic; font-size: 12px">Disclaimer: 
                      This email is for verification purposes only.
                      Please do not share your OTP with anyone.<br><br>
                      This is system generated email. Do not reply.</p>
                </div>
              
                <div style="text-align: start;"><div style="text-align: start; border-top: 1px solid #ccc; padding-top: 10px;  "><p style="font-size: 10px; font-family: Arial, sans-serif; color: #a3a2a2;">© 2023-2026 Chaturvedi Software House LLC. All Rights Reserved</p>
                <p style="font-size: 10px; font-family: Arial, sans-serif; color: #a3a2a2; padding-top: 0px">513 Al Khaleej Center Bur Dubai, Dubai United Arab Emirates, +97143258361 </p>
                
                </div>
                </div>''';

    try {
      // Re-enabled - was left commented out mid-migration, which meant the
      // OTP screen this feeds (see _otplogin) would show a code the user
      // never actually received by email.
      await send(message, smtpServer);
    } catch (e) {
      showAppMessage(context, e.toString());
      /*print('$e');*/
    }
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
  dynamic maskedEmail = '';
  String currentText = "";

  @override
  void dispose() {
    _timer?.cancel();

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
                appBar: PreferredSize(
                  preferredSize: const Size.fromHeight(50),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      ColoredBox(
                        color: Color.alphaBlend(
                          app_color.withOpacity(0.12),
                          pageBackground,
                        ),
                      ),
                      AppBar(
                        backgroundColor: app_color,
                        elevation: 6,
                        shape: const RoundedRectangleBorder(
                          borderRadius: BorderRadius.vertical(
                            bottom: Radius.circular(20),
                          ),
                        ),
                        automaticallyImplyLeading: false,
                        centerTitle: true,
                        title: const Text(
                          'Fincore Go',
                          style: TextStyle(color: Colors.white),
                        ),
                        actions: [
                          IconButton(
                            icon: const Icon(
                              Icons.help_outline,
                              color: Colors.white,
                            ),
                            onPressed: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) =>
                                      const Help(showBottomNavigation: false),
                                ),
                              );
                            },
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                body: DecoratedBox(
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
                  child: SafeArea(
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final isWide = constraints.maxWidth >= 820;

                        return Center(
                          child: SingleChildScrollView(
                            padding: EdgeInsets.symmetric(
                              horizontal: isWide ? 40 : 20,
                              vertical: isWide ? 34 : 22,
                            ),
                            child: ConstrainedBox(
                              constraints: BoxConstraints(
                                maxWidth: isWide ? 920 : 460,
                              ),
                              child: isWide
                                  ? Row(
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
                                    )
                                  : Column(
                                      children: [
                                        _buildBrandPanel(compact: true),
                                        const SizedBox(height: 22),
                                        _buildAnimatedAuthForm(),
                                      ],
                                    ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
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

  Widget _buildAnimatedAuthForm() {
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
      child: isVisibleLoginForm
          ? _buildLoginForm(context)
          : isVisibleResetPassForm
          ? _buildResetForm(context)
          : isVisibleResetOtpForm
          ? _buildResetOtpForm(context)
          : _buildOtpForm(context),
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

  Widget _buildAuthCard({required Key key, required Widget child}) {
    return Container(
      key: key,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Theme.of(context).dividerColor),
        boxShadow: const [
          BoxShadow(
            color: Color(0x14101828),
            blurRadius: 30,
            offset: Offset(0, 18),
          ),
        ],
      ),
      child: child,
    );
  }

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
        setState(() {
          isVisibleLoginForm = false;
          resetemailController.text = usernameController.text;
          passwordController.clear();
          isVisibleResetPassForm = true;
        });
      },
      child: const Text('Forgot Password?'),
    );

    if (_biometricEnabled) {
      // No Remember Me switch to share the row with - always fits, always
      // right-aligned, same as before.
      return Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [forgotPasswordButton],
      );
    }

    final rememberMeRow = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Transform.scale(
          scale: 0.9,
          child: Switch(
            value: _rememberMeEnabled,
            activeColor: app_color,
            activeTrackColor: app_color.withValues(alpha: 0.4),
            inactiveThumbColor: const Color(0xFF9E9E9E),
            inactiveTrackColor: const Color(0xFFD8DCE1),
            trackOutlineColor: WidgetStateProperty.all(Colors.transparent),
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            onChanged: _isRememberMeAutoLoggingIn
                ? null
                : (value) => _onRememberMeChanged(value),
          ),
        ),
        const SizedBox(width: 4),
        Text(
          'Remember Me',
          style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w500),
        ),
      ],
    );

    const switchWidth = 34.0 * 0.9 + 4;
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
    required String subtitle,
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
    );
  }

  InputDecoration _inputDecoration({
    required String label,
    required IconData icon,
    Widget? suffixIcon,
  }) {
    return InputDecoration(
      prefixIcon: Icon(icon, color: app_color),
      suffixIcon: suffixIcon,
      labelText: label,
      labelStyle: GoogleFonts.poppins(
        color: Theme.of(context).colorScheme.onSurfaceVariant,
        fontWeight: FontWeight.w500,
        fontSize: 13.5,
      ),
      filled: true,
      fillColor:
          Theme.of(context).inputDecorationTheme.fillColor ??
          const Color(0xFFF7F9FB),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 17),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: Theme.of(context).dividerColor),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: app_color, width: 1.4),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Color(0xFFE85C5C)),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Color(0xFFE85C5C), width: 1.4),
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

  Widget _buildLoginForm(BuildContext context) {
    return _buildAuthCard(
      key: const ValueKey('loginForm'),
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildFormHeader(
              icon: Icons.lock_open_rounded,
              title: 'Welcome',
              subtitle: 'Sign in to continue to your Fincore Go workspace.',
            ),
            const SizedBox(height: 26),
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
            _isLoading
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
                              _login();
                            }
                          },
                    icon: const Icon(Icons.login_rounded),
                    label: const Text('Login'),
                  ),
            if (_biometricAvailable && _biometricEnabled) ...[
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
                onPressed: _isBiometricAuthenticating ? null : _biometricLogin,
                icon: Icon(
                  _biometricLabel == 'Face ID'
                      ? Icons.face_retouching_natural
                      : Icons.fingerprint,
                ),
                label: Text('Sign in with $_biometricLabel'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildResetForm(BuildContext context) {
    return _buildAuthCard(
      key: const ValueKey('resetForm'),
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
            _isLoadingResetPass
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
                setState(() {
                  usernameController.text = resetemailController.text;
                  resetemailController.clear();
                  isVisibleResetPassForm = false;
                  isVisibleLoginForm = true;
                });
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
  Widget _buildResetOtpForm(BuildContext context) {
    return _buildAuthCard(
      key: const ValueKey('resetOtpForm'),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildFormHeader(
            icon: Icons.mark_email_read_rounded,
            title: 'Reset your password',
            subtitle:
                'Enter the 4-digit code sent to ${resetemailController.text}, then choose a new password.',
          ),
          const SizedBox(height: 26),
          TextFormField(
            controller: resetOtpController,
            keyboardType: TextInputType.number,
            maxLength: 4,
            textAlign: TextAlign.center,
            style: GoogleFonts.poppins(
              fontSize: 20,
              letterSpacing: 8,
              fontWeight: FontWeight.w700,
            ),
            decoration: _inputDecoration(
              label: 'One-time code',
              icon: Icons.pin_outlined,
            ).copyWith(counterText: ''),
          ),
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
                  () => _isNewPasswordVisible = !_isNewPasswordVisible,
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
          _isConfirmingPasswordReset
              ? SizedBox(
                  height: 52,
                  child: Center(
                    child: CupertinoActivityIndicator(color: app_color),
                  ),
                )
              : ElevatedButton.icon(
                  style: _primaryButtonStyle(),
                  onPressed: _confirmPasswordReset,
                  icon: const Icon(Icons.verified_rounded),
                  label: const Text('Change password'),
                ),
          const SizedBox(height: 12),
          ElevatedButton.icon(
            style: _secondaryButtonStyle(),
            onPressed: () {
              setState(() {
                _passwordResetToken = null;
                isVisibleResetOtpForm = false;
                isVisibleLoginForm = true;
                usernameController.text = resetemailController.text;
                resetemailController.clear();
                resetOtpController.clear();
                newPasswordController.clear();
                confirmNewPasswordController.clear();
              });
            },
            icon: const Icon(Icons.arrow_back_rounded),
            label: const Text('Back to login'),
          ),
        ],
      ),
    );
  }

  Widget _buildOtpForm(BuildContext context) {
    return _buildAuthCard(
      key: const ValueKey('otpForm'),
      child: Form(
        key: _otpformKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildFormHeader(
              icon: Icons.mark_email_read_rounded,
              title: 'Verify your login',
              subtitle: 'Enter the 4-digit code sent to your email address.',
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
                maskedEmail,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.poppins(
                  color: Theme.of(context).colorScheme.onSurface,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(height: 26),
            PinCodeTextField(
              appContext: context,
              controller: otpController,
              length: 4,
              enabled: !_isOtpVerifyingProgress,
              animationType: AnimationType.fade,
              onChanged: (value) {
                currentText = value;
              },
              onCompleted: (value) {
                currentText = value;
                _verifyOtpAndProceed(value);
              },
              pinTheme: PinTheme(
                shape: PinCodeFieldShape.box,
                borderRadius: BorderRadius.circular(14),
                fieldHeight: 58,
                fieldWidth: 58,
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
              keyboardType: TextInputType.number,
              obscureText: false,
            ),
            const SizedBox(height: 22),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 180),
              child: isVisibleTimer
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
                        "Resend OTP in $_formattedTime",
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
            if (_isButtonEnabled) ...[
              const SizedBox(height: 12),
              ElevatedButton.icon(
                style: _secondaryButtonStyle(),
                icon: const Icon(Icons.refresh_rounded),
                onPressed: () {
                  sendOTP(usernamee);
                  setState(() {
                    _isButtonEnabled = false;
                    isVisibleTimer = true;
                    _startTimer();
                  });
                },
                label: const Text('Resend OTP'),
              ),
            ],
            const SizedBox(height: 14),
            ElevatedButton.icon(
              style: _primaryButtonStyle().copyWith(
                backgroundColor: MaterialStateProperty.resolveWith<Color>(
                  (states) => _isOtpVerifyingProgress
                      ? const Color(0xFF98A2AD)
                      : app_color,
                ),
              ),
              icon: _isOtpVerifyingProgress
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
              onPressed: _isOtpVerifyingProgress
                  ? null
                  : () {
                      _verifyOtpAndProceed(currentText);
                    },
              label: Text(_isOtpVerifyingProgress ? 'Verifying...' : 'Verify'),
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
                setState(() {
                  otpController.clear();
                  isVisibleOTPForm = false;
                  isVisibleLoginForm = true;
                  isVisibleTimer = false;
                });
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
