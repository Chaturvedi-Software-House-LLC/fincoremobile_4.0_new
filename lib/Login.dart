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
import 'constants.dart';
import 'package:flutter/material.dart';
import 'package:pin_code_fields/pin_code_fields.dart';
import 'package:http/http.dart' as http;
import 'package:flutter/cupertino.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path_provider/path_provider.dart';
import 'package:socket_io_client/socket_io_client.dart' as IO;
import 'package:device_info_plus/device_info_plus.dart';
import 'widgets/entry_widgets.dart';
import 'services/biometric_auth_service.dart';
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

  bool isValidId = false;
  String responseMessage = ''; // To store the server response.
  String socketId = ''; // To store the socket ID.

  bool isVisibleTimer = false;

  late IO.Socket socket;

  bool isOTPVerified = false, isAnotherDevice = false;

  dynamic socket_data;

  final GlobalKey<ScaffoldMessengerState> _scaffoldMessengerKey =
      GlobalKey<ScaffoldMessengerState>();

  bool _isLoading = false, _isLoadingResetPass = false;

  final String SHARED_PREFERENCES_NAME = "login_prefs";

  bool isDirectLogin = false, isOTPLogin = false;

  String? username_prefs, password_prefs;

  String? deviceIdentifier = '';

  String generatedotp = '';

  dynamic jsonPayload, response_getusers, response_resetpass;

  bool isVisibleLoginForm = true,
      isVisibleResetPassForm = false,
      isVisibleOTPForm = false;

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

        socket.emit('deleteMyId', socket_data);

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

  void emitSaveId(final jsonPayload, final response) {
    if (!mounted || !isOTPVerified) return;

    final navigator = Navigator.of(context);

    socket.emit('saveMyId', jsonPayload);

    socket.once('isIdSaved', (data) async {
      if (!mounted) return;

      if (data == true) {
        final responseData = json.decode(utf8.decode(response.bodyBytes));

        if (responseData is List && responseData.isNotEmpty) {
          final userName = responseData[0]['name']?.toString() ?? '';
          await prefs_login.setString('name', userName);
        }

        final myList = <Map<String, dynamic>>[];

        for (final data in responseData) {
          final newObj = <String, dynamic>{
            'serial_no': data['serial_no'],
            'role_id': data['role_id'],
            'license_expiry': data['license_expiry'],
            'website_url': data['website_url'],
            'token': data['token'],
          };

          if (data['spectra_allocations'] != null) {
            newObj['spectra_allocations'] = data['spectra_allocations'];
          }

          myList.add(newObj);
        }

        final jsonString = jsonEncode(myList);

        // "Remember me" as a user-facing toggle is gone - username/
        // password are no longer prefilled into the form on next launch.
        // These are still saved every time, silently, purely as the
        // credential source Settings' biometric toggle and the post-
        // login "Enable Face ID/Biometric?" prompt need to persist
        // biometric_username/biometric_password - never shown back to
        // the user or used to auto-fill/auto-submit the login form.
        prefs_login.setString('username_remember', usernamee);
        prefs_login.setString('password_remember', passwordd);
        prefs_login.setString('username', usernamee);
        prefs_login.setString('password', passwordd);
        prefs_login.remove('sync_pref');
        prefs_login.remove('serial_no');

        prefs_login.setString('login_list', jsonString);

        if (_biometricEnabled) {
          prefs_login.setString('biometric_username', usernamee);
          prefs_login.setString('biometric_password', passwordd);
        }

        if (!mounted) return;

        await _maybeOfferBiometricEnable();

        if (!mounted) return;

        navigator.pushReplacement(
          MaterialPageRoute(
            builder: (_) => SerialSelect(autoNavigate: myList.length == 1),
          ),
        );
      } else {
        if (!mounted) return;

        showAppMessage(context, 'An error occured.');
      }
    });
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
    if (!mounted) return;
    setState(() {
      _biometricAvailable = available;
      _biometricEnabled = enabled;
      _biometricLabel = label;
    });
  }

  Future<void> _biometricLogin() async {
    if (_isBiometricAuthenticating) return;
    setState(() => _isBiometricAuthenticating = true);

    try {
      final ok = await BiometricAuthService.instance.authenticate(
        reason: 'Authenticate with $_biometricLabel to sign in',
      );
      if (!ok) return;

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
      }
    }
  }

  Future<void> _resetpass() async {
    setState(() {
      _isLoadingResetPass = true;
    });
    _showProcessingDialog();

    String enteredemail = resetemailController.text;
    try {
      Map<String, String> headers = {
        'Authorization': 'Bearer $authTokenBase',
        "Content-Type": "application/json",
      };

      var body = jsonEncode({'email': enteredemail});

      response_resetpass = await http.post(
        Uri.parse('$BASE_URL_config/api/login/forgotPassword'),
        body: body,
        headers: headers,
      );

      final decodedBody = jsonDecode(response_resetpass.body);

      if (response_resetpass.statusCode == 200) {
        final token = decodedBody['token'];
        final name = decodedBody['name'];

        // Send password reset email
        await _sendPasswordResetEmail(enteredemail, token, name);

        // Show success message
        showAppMessage(
          context,
          'Password reset email sent successfully',
          isError: false,
        );
        setState(() {
          usernameController.text = resetemailController.text;
          resetemailController.clear();
          isVisibleResetPassForm = false;
          isVisibleLoginForm = true;
        });
      } else {
        final error = decodedBody['error'];
        /*print(error);*/
        showAppMessage(context, '$error');
      }
    } catch (e) {
      showAppMessage(context, e.toString());
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingResetPass = false;
        });
        if (Navigator.canPop(context)) {
          Navigator.pop(context);
        }
      }
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

  Future<void> _sendPasswordResetEmail(
    String emailAddress,
    String token,
    String name,
  ) async {
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
      ..recipients.add(emailAddress) // Use the email entered by the user
      ..subject = 'Password Reset Request'
      ..html =
          '''
         <div style="border: 1px solid #ccc; padding-left: 30px; padding-right: 30px; padding-top: 30px; padding-bottom: 30px; margin-left: 20px; margin-right: 20px; margin-top: 0px; text-align: center;">

          <a href="https://tallyuae.ae/">
              <img src="https://mobile.chaturvedigroup.com/fincore_logo/tally_1.png" alt="Image" style="width: 150px; height: auto; margin-bottom: 10px;">
          </a>
         <div style="text-align: center;"><p style="font-size: 16px; font-family: Arial, sans-serif; color: #30D5C8; font-weight: bold">Fincore Go Password Reset</p></div>
         
        <div style="text-align: start;"><p style="font-size: 14px; font-family: Arial, sans-serif; color: #333;">Dear $name,</p></div>
        <div style="text-align: start;"><p style="font-size: 12px; font-family: Arial, sans-serif; color: #333;">We’ve received your request to reset your password. Please click the link below to complete the reset.</p></div>
        <br>
        <div style="text-align: center;">
          <p>
            <a href="$BASE_URL_config/setPassword?token=$token" style="display: inline-block; background-color: #30D5C8; color: #fff; font-size: 16px; font-family: Arial, sans-serif; text-decoration: none; padding: 10px 20px; border-radius: 5px;">Reset Password</a>
          </p> 
        </div>        
        <br>
        <div style="text-align: start;"><p style="font-size: 12px; font-family: Arial, sans-serif; color: #333;">If you need additional assistance, or you did not make this change, please contact <a href="mailto:saadan@ca-eim.com">saadan@ca-eim.com</a></p></div>
        <br>
        <div style="text-align: start;"><p style="color: #999999; font-style: italic; font-size: 12px">This is system generated email. Do not reply.</p>
    </div>
        
        <div style="text-align: start;"><div style="text-align: start; border-top: 1px solid #ccc; padding-top: 10px;  "><p style="font-size: 10px; font-family: Arial, sans-serif; color: #a3a2a2;">© 2023-2026 Chaturvedi Software House LLC. All Rights Reserved</p>
        <p style="font-size: 10px; font-family: Arial, sans-serif; color: #a3a2a2; padding-top: 0px">513 Al Khaleej Center Bur Dubai, Dubai United Arab Emirates, +97143258361 </p></div>
      </div>
      ''';
    try {
      final sendReport = await send(message, smtpServer); // send mail

      /*showAppMessage(context, 'Message sent', isError: false);*/

      /*print('Reset Email sent: ${sendReport.toString()}');*/
    } catch (e) {
      showAppMessage(context, e.toString());
      /*print('$e');*/
    }
  }

  /*Future<void> _sendPasswordResetEmail(String emailAddress, String token) async {
    final Email email = Email(
      body: '''
        <p>Dear Fincore Go user,</p>
        <p>We’ve received your request to reset your password. Please click the link below to complete the reset.</p>
        <p><a href="http://$BASE_URL_config/setPassword?token=$token">Reset My Password</a></p>
        <p>If you need additional assistance, or you did not make this change, please contact <a href="mailto:saadan@ca-eim.com">saadan@ca-eim.com</a>.</p>
        <p>© 2024 Chaturvedi Software House LLC. All Rights Reserved<br>
        513 Al Khaleej Center Bur Dubai, Dubai United Arab Emirates, +971-43258361 </p>
      ''',
      subject: 'Password Reset Request',
      recipients: [emailAddress],
      isHTML: true,
    );

    try {
      await FlutterEmailSender.send(email);
    } catch (error) {
      print('Error sending email: $error');
    }
  }*/

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

        final jsonPayload = {
          'username': entered_username,
          'password': entered_password,
          'macId': deviceIdentifier,
        };

        socket.emit('deleteMyId', jsonPayload);

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

  Future<void> _directlogin() async {
    setState(() {
      _isLoading = true;
      isDirectLogin = true;
      isOTPLogin = false;
      response_getusers = null;
    });

    try {
      Map<String, String> headers = {
        'Authorization': 'Bearer $authTokenBase',
        "Content-Type": "application/json",
      };

      var body = jsonEncode({'username': usernamee, 'password': passwordd});

      response_getusers = await http.post(
        Uri.parse('$BASE_URL_config/api/login/getusers'),
        body: body,
        headers: headers,
      );
      print('response login -> ${response_getusers.body}');

      if (response_getusers.statusCode == 200) {
        String expectedBody = "Invalid Username or Password Please Try Again";

        String responsee = response_getusers.body;
        responsee = responsee.trim();

        if (responsee == expectedBody) {
          showAppMessage(context, responsee);
          _usernameFocusNode.unfocus();
          _passwordFocusNode.unfocus();
        } else {
          try {
            jsonPayload = {
              'username': usernamee,
              'password': passwordd,
              'macId': deviceIdentifier,
            };
            /*print('emitting');*/
            socket.emit('myId', jsonPayload);
          } catch (e) {
            showAppMessage(context, e.toString());
          }
        }
      } else {
        final error = jsonDecode(response_getusers.body)['error'];
        /*print(error);*/
        showAppMessage(context, '$error');
      }
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    } catch (e) {
      showAppMessage(context, e.toString());
      print(e.toString());
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _otplogin(String email) async {
    setState(() {
      _isLoading = true;
      isDirectLogin = false;
      isOTPLogin = true;
      response_getusers = null;
    });

    try {
      Map<String, String> headers = {
        'Authorization': 'Bearer $authTokenBase',
        "Content-Type": "application/json",
      };

      var body = jsonEncode({'username': usernamee, 'password': passwordd});

      response_getusers = await http.post(
        Uri.parse('$BASE_URL_config/api/login/getusers'),
        body: body,
        headers: headers,
      );

      print('response login -> ${response_getusers.body}');
      /*response_getusers = await http.post(
        Uri.parse('$BASE_URL_config/api/login/getusers'),
        body: {
          'username': usernamee,
          'password': passwordd,
        },
      );*/

      /*int code = response_getusers.statusCode;

      final body = response_getusers.body;

      print('response code : $code');

      print('body : $body');
*/

      if (response_getusers.statusCode == 200) {
        String expectedBody = "Invalid Username or Password Please Try Again";

        String responsee = response_getusers.body;
        responsee = responsee.trim();
        if (responsee == expectedBody) {
          showAppMessage(context, responsee);

          _usernameFocusNode.unfocus();
          _passwordFocusNode.unfocus();
        } else {
          try {
            // Create a JSON object containing username and password
            jsonPayload = {
              'username': usernamee,
              'password': passwordd,
              'macId': deviceIdentifier,
            };
            /*print('emitting');*/

            socket.emit('myId', jsonPayload);
          } catch (e) {
            showAppMessage(context, e.toString());
          }
        }
      } else {
        final error = jsonDecode(response_getusers.body)['error'];
        /*print(error);*/
        showAppMessage(context, error);
      }
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    } catch (e) {
      showAppMessage(context, e.toString());
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
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

    // Initialize Socket.IO connection
    socket = IO.io(SOCKET_URL, <String, dynamic>{
      'transports': ['websocket'],
      'path': '/main/socket.io',
      'autoConnect': false,
      'reconnection': true,
      'reconnectionAttempts': 10,
      'reconnectionDelay': 1500,
      'timeout': 20000,
      'forceNew': true,
      'auth': {'token': authTokenBase},
    });

    socket.onConnect((_) {
      print("🔌 Socket Connected");
    });

    socket.onConnectError((data) {
      print("❌ Connect Error: $data");
    });

    socket.onDisconnect((_) {
      debugPrint("Socket disconnected");
    });

    socket.connect();

    /*socket = IO.io('http://192.168.2.110:5999', <String, dynamic>{
      'transports': ['websocket'],
      'autoConnect': true,
      'auth' : {
        'token' : '$authTokenBase'
      }
    });*/

    /*socket = IO.io('http://192.168.2.80:5999', <String, dynamic>{
      'transports': ['websocket'],
      'autoConnect': true,
      'auth' : {
        'token' : '$authTokenBase'
      }
    });*/

    // Listen for the socket connection event and get the socket ID

    socket.on('connect', (_) {
      socketId = socket.id!;
    });

    socket.on('idConflict', (data) {
      // show dialog
      if (mounted) {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (BuildContext context) {
            return Dialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              elevation: 12,
              backgroundColor: Theme.of(context).colorScheme.surface,
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.warning_amber_rounded,
                      color: app_color,
                      size: 48,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'User Already Logged In',

                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'This user is already logged in on another device. Do you want to continue here?',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 15,
                        height: 1.4,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 24),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            style: OutlinedButton.styleFrom(
                              side: BorderSide(color: app_color),
                              foregroundColor: app_color,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              padding: const EdgeInsets.symmetric(vertical: 14),
                            ),
                            onPressed: () {
                              Navigator.of(context).pop();
                              // Handle "No"
                            },
                            child: const Text(
                              'No',
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: app_color,
                              foregroundColor: Colors.white,
                              elevation: 2,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              padding: const EdgeInsets.symmetric(vertical: 14),
                            ),
                            onPressed: () async {
                              String username = usernameController.text;
                              Navigator.of(context).pop();

                              String entered_username = usernameController.text;
                              String entered_password = passwordController.text;

                              if (entered_username == 'demouser@ca-eim.com' &&
                                  entered_password == 'user1234') {
                                isOTPVerified = true;
                                isAnotherDevice = true;
                                socket.emit('deleteMyId', data);
                                _directlogin();
                              } else {
                                if (isEmail(username)) {
                                  sendOTP(username);
                                  socket_data = data;

                                  setState(() {
                                    isVisibleLoginForm = false;
                                    isVisibleResetPassForm = false;
                                    _isButtonEnabled = false;
                                    isVisibleTimer = true;
                                    _isOtpVerifyingProgress = false;
                                    _isVerifyingOtp = false;
                                    otpController.clear();
                                    currentText = '';

                                    _startTimer();
                                    isVisibleOTPForm = true;
                                    maskedEmail = username;
                                  });
                                } else {
                                  isOTPVerified = true;
                                  isAnotherDevice = true;
                                  socket.emit('deleteMyId', data);
                                  _directlogin();
                                }

                                /* sendOTP(username);
                                socket_data = data;
                                setState(() {
                                  isVisibleLoginForm = false;
                                  isVisibleResetPassForm = false;
                                  _isButtonEnabled = false;
                                  isVisibleTimer = true;
                                  _isOtpVerifyingProgress = false;
                                  _isVerifyingOtp = false;
                                  otpController.clear();
                                  currentText = '';

                                  _startTimer();
                                  isVisibleOTPForm = true;
                                  maskedEmail = username;
                                });*/
                              }
                            },
                            child: const Text(
                              'Yes, Continue',
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      }
    });

    socket.on('isValidId', (data) {
      /*print('isValidiD : $data');*/
      if (!mounted) return;

      if ((data &&
              isDirectLogin &&
              isOTPVerified == true &&
              isAnotherDevice == true) ||
          (data &&
              isDirectLogin &&
              isOTPVerified == false &&
              isAnotherDevice == false)) {
        isValidId = data;

        if (data) {
          isOTPVerified = true;
          emitSaveId(jsonPayload, response_getusers);
        } else {
          isOTPVerified = false;

          prefs_login.remove('username_remember');
          prefs_login.remove('password_remember');

          showAppMessage(context, 'User is active on another device.');
        }
      } else if (data && isOTPLogin && isOTPVerified == false) {
        isValidId = data;

        if (data) {
          /*setState(() {
              isOTPVerified = true;
              emitSaveId(jsonPayload, response_getusers);
            });*/

          /*sendOTP('saadan@ca-eim.com');*/

          if (isEmail(usernamee)) {
            sendOTP(usernamee);

            socket_data = data;

            setState(() {
              isVisibleLoginForm = false;
              isVisibleResetPassForm = false;
              _isButtonEnabled = false;
              isVisibleTimer = true;
              _isOtpVerifyingProgress = false;
              _isVerifyingOtp = false;
              otpController.clear();
              currentText = '';

              _startTimer();
              isVisibleOTPForm = true;
              maskedEmail = usernamee;
            });
          } else {
            isOTPVerified = true;
            isAnotherDevice = true;
            _directlogin();
            // return;
          }

          /* if (isEmail(usernamee)) {
              sendOTP(usernamee);
            } else {
              isOTPVerified = true;
              isAnotherDevice = true;
              _directlogin();
            }

            socket_data = data;

            setState(() {
              isVisibleLoginForm = false;
              isVisibleResetPassForm = false;
              _isButtonEnabled = false;
              isVisibleTimer = true;
              _isOtpVerifyingProgress = false;
              _isVerifyingOtp = false;
              otpController.clear();
              currentText = '';

              _startTimer();
              isVisibleOTPForm = true;
              maskedEmail = usernamee;
            });*/
        } else {
          isOTPVerified = false;
          prefs_login.remove('username_remember');
          prefs_login.remove('password_remember');

          showAppMessage(context, 'User is active on another device.');
        }
      } else {
        prefs_login.remove('username_remember');
        prefs_login.remove('password_remember');

        showAppMessage(context, 'User is active on another device.');
      }
    });

    try {
      socket.connect();
    } catch (e) {
      showAppMessage(context, e.toString());
    }
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
      // await send(message, smtpServer);

      /*showAppMessage(context, 'Message sent', isError: false);*/

      /*print('Message sent: ${sendReport.toString()}');*/
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

    socket.off('isValidId');
    socket.off('idConflict');
    socket.off('isIdSaved');
    socket.disconnect();
    socket.dispose();

    passwordController.removeListener(_onPasswordChanged);
    resetemailController.removeListener(_onResetEmailChanged);

    passwordController.dispose();
    usernameController.dispose();
    resetemailController.dispose();
    otpController.dispose();

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
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                style: TextButton.styleFrom(
                  foregroundColor: app_color,
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
              ),
            ),
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
