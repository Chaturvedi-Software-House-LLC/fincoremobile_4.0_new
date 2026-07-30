import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter/widgets.dart';
import 'package:fluttertoast/fluttertoast.dart';
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

  GlobalKey<ScaffoldMessengerState> _scaffoldMessengerKey =
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

  late String passwordd = '';
  bool remember_me = true;
  final _usernameFocusNode = FocusNode();
  final _passwordFocusNode = FocusNode();
  final _resetemailFocusNode = FocusNode();
  late TickerProvider tickerProvider;

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

        Fluttertoast.showToast(msg: 'Incorrect OTP');

        otpController.clear();
        currentText = '';

        setState(() {
          _isVerifyingOtp = false;
          _isOtpVerifyingProgress = false;
        });
      }
    } else {
      Fluttertoast.showToast(msg: 'Please enter a 4-digit OTP');
    }
  }

  bool isEmail(String value) {
    return RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$').hasMatch(value.trim());
  }

  void emitSaveId(final jsonPayload, final response) {
    if (isOTPVerified) {
      socket.emit('saveMyId', jsonPayload);

      socket.once('isIdSaved', (data) async {
        if (data) {
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

            // ✅ Save spectra allocations only if not null
            if (data['spectra_allocations'] != null) {
              newObj['spectra_allocations'] = data['spectra_allocations'];
            }
            myList.add(newObj);
          }
          String jsonString = jsonEncode(myList);

          if (remember_me) {
            prefs_login.setString('username_remember', usernamee);
            prefs_login.setString('password_remember', passwordd);
            prefs_login.setString('username', usernamee);

            prefs_login.setString('password', passwordd);
            prefs_login.remove('sync_pref');
            prefs_login.remove('serial_no');
          } else {
            prefs_login.remove('username_remember');
            prefs_login.remove('password_remember');
            prefs_login.setString('username', usernamee);
            prefs_login.setString('password', passwordd);
          }
          prefs_login.setString('login_list', jsonString);

          if (mounted) {
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(builder: (context) => SerialSelect()),
            );
          }
        } else {
          _scaffoldMessengerKey.currentState?.showSnackBar(
            SnackBar(content: Text('An error occured.')),
          );
        }
      });
    }
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
    _start = 60; // Reset countdown to 60 seconds
    _formattedTime = _formatDuration(_start); // Reset the formatted time
    _isButtonEnabled = false; // Disable button initially

    _timer = Timer.periodic(Duration(seconds: 1), (timer) {
      if (_start > 0) {
        setState(() {
          _isButtonEnabled = false;
          isVisibleTimer = true;

          /*print('_start value $_start');*/
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

    if (usernamee != "null" && usernamee.isNotEmpty && usernamee != null) {
      _login();
    }
  }

  Future<void> _resetpass() async {
    setState(() {
      _showProcessingDialog();
    });

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

      if (response_resetpass.statusCode == 200) {
        final token = jsonDecode(response_resetpass.body)['token'];
        final name = jsonDecode(response_resetpass.body)['name'];

        // Send password reset email
        await _sendPasswordResetEmail(enteredemail, token, name);

        // Show success message
        _scaffoldMessengerKey.currentState?.showSnackBar(
          SnackBar(content: Text('Password reset email sent successfully')),
        );
        setState(() {
          usernameController.text = resetemailController.text;
          resetemailController.clear();
          isVisibleResetPassForm = false;
          isVisibleLoginForm = true;
        });
      } else {
        final error = jsonDecode(response_resetpass.body)['error'];
        /*print(error);*/
        _scaffoldMessengerKey.currentState?.showSnackBar(
          SnackBar(content: Text('$error')),
        );
      }
    } catch (e) {
      _scaffoldMessengerKey.currentState?.showSnackBar(
        SnackBar(content: Text(e.toString())),
      );
    } finally {
      setState(() {
        _isLoading = false;
      });
      Navigator.pop(context);
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

      /*_scaffoldMessengerKey.currentState?.showSnackBar(
        SnackBar(
          content: Text('Message sent'),
        ),
      );*/

      /*print('Reset Email sent: ${sendReport.toString()}');*/
    } catch (e) {
      _scaffoldMessengerKey.currentState?.showSnackBar(
        SnackBar(content: Text(e.toString())),
      );
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
          _scaffoldMessengerKey.currentState?.showSnackBar(
            SnackBar(content: Text(responsee)),
          );
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
            _scaffoldMessengerKey.currentState?.showSnackBar(
              SnackBar(content: Text(e.toString())),
            );
          }
        }
      } else {
        final error = jsonDecode(response_getusers.body)['error'];
        /*print(error);*/
        _scaffoldMessengerKey.currentState?.showSnackBar(
          SnackBar(content: Text('$error')),
        );
      }
      setState(() {
        _isLoading = false;
      });
    } catch (e) {
      _scaffoldMessengerKey.currentState?.showSnackBar(
        SnackBar(content: Text(e.toString())),
      );
      print(e.toString());
      setState(() {
        _isLoading = false;
      });
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
          _scaffoldMessengerKey.currentState?.showSnackBar(
            SnackBar(content: Text(responsee)),
          );

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
            _scaffoldMessengerKey.currentState?.showSnackBar(
              SnackBar(content: Text(e.toString())),
            );
          }
        }
      } else {
        final error = jsonDecode(response_getusers.body)['error'];
        /*print(error);*/
        _scaffoldMessengerKey.currentState?.showSnackBar(
          SnackBar(content: Text(error)),
        );
      }
      setState(() {
        _isLoading = false;
      });
    } catch (e) {
      _scaffoldMessengerKey.currentState?.showSnackBar(
        SnackBar(content: Text(e.toString())),
      );
      setState(() {
        _isLoading = false;
      });
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
    passwordController.addListener(_onPasswordChanged);
    resetemailController.addListener(_onResetEmailChanged);
    usernameController.text = usernamee;
    passwordController.text = passwordd;

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
      print("⚠️ Socket Disconnected");
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

          _scaffoldMessengerKey.currentState?.showSnackBar(
            SnackBar(content: Text('User is active on another device.')),
          );
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

          _scaffoldMessengerKey.currentState?.showSnackBar(
            SnackBar(content: Text('User is active on another device.')),
          );
        }
      } else {
        prefs_login.remove('username_remember');
        prefs_login.remove('password_remember');

        _scaffoldMessengerKey.currentState?.showSnackBar(
          SnackBar(content: Text('User is active on another device.')),
        );
      }
    });

    try {
      socket.connect();
    } catch (e) {
      _scaffoldMessengerKey.currentState?.showSnackBar(
        SnackBar(content: Text(e.toString())),
      );
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

      /*_scaffoldMessengerKey.currentState?.showSnackBar(
        SnackBar(
          content: Text('Message sent'),
        ),
      );*/

      /*print('Message sent: ${sendReport.toString()}');*/
    } catch (e) {
      _scaffoldMessengerKey.currentState?.showSnackBar(
        SnackBar(content: Text(e.toString())),
      );
      /*print('$e');*/
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _getDeviceIdentifier();
  }

  Future<void> _getDeviceIdentifier() async {
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
    setState(() {
      deviceIdentifier = identifier;
    });
  }

  void _onPasswordChanged() {
    // Check the length of the password
    if (passwordController.text.length < requiredLength) {
      // If the password is too short, update the button color to grey
      setState(() {
        _buttonColor = Colors.grey;
        isButtonDisabled = true;
      });
    } else {
      setState(() {
        _buttonColor = app_color;
        isButtonDisabled = false;
      });
    }
  }

  void _onResetEmailChanged() {
    // Check the length of the password
    if (resetemailController.text.isEmpty) {
      // If the password is too short, update the button color to grey
      setState(() {
        _resetbuttonColor = Colors.grey;
        isResetPassButtonDisabled = true;
      });
    } else {
      if (!RegExp(
        r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$',
      ).hasMatch(resetemailController.text)) {
        setState(() {
          _resetbuttonColor = Colors.grey;
          isResetPassButtonDisabled = true;
        });
      } else {
        setState(() {
          _resetbuttonColor = app_color;
          isResetPassButtonDisabled = false;
        });
      }
    }
  }

  final TextEditingController otpController = TextEditingController();
  dynamic maskedEmail = '';
  String currentText = "";

  @override
  void dispose() {
    // passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      child: MaterialApp(
        home: Builder(
          builder: (BuildContext context) {
            return WillPopScope(
              onWillPop: () async {
                final now = DateTime.now();
                if (lastBackPressedTime == null ||
                    now.difference(lastBackPressedTime!) >
                        Duration(seconds: 2)) {
                  lastBackPressedTime = now;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Press back again to exit')),
                  );
                  return false;
                }
                return true;
              },
              child: ScaffoldMessenger(
                key: _scaffoldMessengerKey,
                child: Scaffold(
                  key: _scaffoldKey,
                  appBar: PreferredSize(
                    preferredSize: Size.fromHeight(50),
                    child: AppBar(
                      backgroundColor: app_color,
                      elevation: 6,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.vertical(
                          bottom: Radius.circular(20),
                        ),
                      ),
                      automaticallyImplyLeading: false,

                      centerTitle: true,
                      title: Text(
                        'Fincore Go',
                        style: TextStyle(color: Colors.white),
                      ),
                      actions: [
                        IconButton(
                          icon: Icon(Icons.help_outline, color: Colors.white),
                          onPressed: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(builder: (context) => Help()),
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                  // 💫 Modern Login Body with Fade Transitions Between Forms
                  body: Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [app_color.withOpacity(0.1), Colors.white],
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                      ),
                    ),
                    child: SafeArea(
                      child: Center(
                        child: AnimatedSwitcher(
                          duration: const Duration(milliseconds: 400),
                          transitionBuilder:
                              (Widget child, Animation<double> animation) =>
                                  FadeTransition(
                                    opacity: animation,
                                    child: child,
                                  ),

                          // 🔹 Dynamically switch between forms
                          child: isVisibleLoginForm
                              ? _buildLoginForm(context)
                              : isVisibleResetPassForm
                              ? _buildResetForm(context)
                              : _buildOtpForm(context),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
      onWillPop: () async {
        _showConfirmationDialogAndExit(context);
        return true;
      },
    );
  }

  Widget _buildLoginForm(BuildContext context) {
    return SingleChildScrollView(
      key: const ValueKey('loginForm'),
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 20),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // 🖼 Logo
          Image.asset(
            'assets/fincorego_logo_transparent.png',
            width: 350,
            height: 230,
          ),
          Text(
            "Smart Finance. Simplified.",
            style: GoogleFonts.poppins(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 40),

          // 💠 Glass Card
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Theme.of(context).cardColor.withOpacity(0.9),
              borderRadius: BorderRadius.circular(30),
              boxShadow: [
                BoxShadow(
                  color: Colors.black12.withOpacity(0.08),
                  blurRadius: 16,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Form(
              key: _formKey,
              child: Column(
                children: [
                  // 📧 Email
                  TextFormField(
                    controller: usernameController,
                    focusNode: _usernameFocusNode,
                    decoration: InputDecoration(
                      prefixIcon: Icon(Icons.email_outlined, color: app_color),
                      labelText: 'Username or Email',
                      labelStyle: GoogleFonts.poppins(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w500,
                        fontSize: 14.5,
                      ),
                      filled: true,
                      fillColor:
                          Theme.of(context).inputDecorationTheme.fillColor ??
                          Colors.white,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: BorderSide.none,
                      ),
                    ),
                    validator: (v) {
                      if (v == null || v.trim().isEmpty) {
                        return 'Please enter username or email';
                      }
                      return null;
                    },
                    onSaved: (v) => usernamee = v!,
                  ),
                  const SizedBox(height: 18),

                  // 🔒 Password
                  TextFormField(
                    controller: passwordController,
                    focusNode: _passwordFocusNode,
                    obscureText: _obscureText,

                    decoration: InputDecoration(
                      prefixIcon: Icon(Icons.lock_outline, color: app_color),
                      suffixIcon: IconButton(
                        icon: Icon(
                          _obscureText
                              ? Icons.visibility_off_rounded
                              : Icons.visibility_rounded,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                        onPressed: () =>
                            setState(() => _obscureText = !_obscureText),
                      ),
                      labelText: 'Password',
                      labelStyle: GoogleFonts.poppins(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w500,
                        fontSize: 14.5,
                      ),
                      filled: true,
                      fillColor:
                          Theme.of(context).inputDecorationTheme.fillColor ??
                          Colors.white,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: BorderSide.none,
                      ),
                    ),
                    validator: (v) =>
                        v == null || v.isEmpty ? 'Please enter password' : null,
                    onSaved: (v) => passwordd = v!,
                  ),
                  const SizedBox(height: 12),

                  // ✅ Remember Me + Forgot Password
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Checkbox(
                              value: remember_me,
                              activeColor: app_color,
                              onChanged: (v) =>
                                  setState(() => remember_me = v!),
                            ),
                            Text(
                              "Remember Me",
                              style: GoogleFonts.poppins(
                                fontSize: 14,
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                        Center(
                          child: GestureDetector(
                            onTap: () {
                              setState(() {
                                isVisibleLoginForm = false;
                                resetemailController.text =
                                    usernameController.text;
                                passwordController.clear();
                                isVisibleResetPassForm = true;
                              });
                            },
                            child: Text(
                              "Forgot Password?",
                              style: GoogleFonts.poppins(
                                color: app_color,
                                fontWeight: FontWeight.w600,
                                decoration: TextDecoration.underline,
                                fontSize: 14,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),

                  // 🔘 Login Button
                  _isLoading
                      ? const CupertinoActivityIndicator(radius: 18)
                      : ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: app_color,
                            padding: const EdgeInsets.symmetric(
                              vertical: 14,
                              horizontal: 80,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          onPressed: isButtonDisabled
                              ? null
                              : () {
                                  if (_formKey.currentState != null &&
                                      _formKey.currentState!.validate()) {
                                    _formKey.currentState!.save();
                                    _login();
                                  }
                                },
                          child: Text(
                            'Login',
                            style: GoogleFonts.poppins(
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),

                  /*const SizedBox(height: 12),
                  GestureDetector(
                    onTap: () => navigateToPDFView(context),
                    child: Text.rich(
                      TextSpan(
                        text: 'Not Registered? ',
                        style: GoogleFonts.poppins(
                            color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 13),
                        children: [
                          TextSpan(
                            text: 'Click here for instructions',
                            style: GoogleFonts.poppins(
                              color: app_color,
                              fontWeight: FontWeight.w600,
                              decoration: TextDecoration.underline,
                            ),
                          ),
                        ],
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),*/
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildResetForm(BuildContext context) {
    return SingleChildScrollView(
      key: const ValueKey('resetForm'),
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 40),
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor.withOpacity(0.9),
          borderRadius: BorderRadius.circular(30),
          boxShadow: [
            BoxShadow(
              color: Colors.black12.withOpacity(0.08),
              blurRadius: 16,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Form(
          key: _resetformKey,
          child: Column(
            children: [
              Icon(Icons.lock_reset, size: 80, color: app_color),
              const SizedBox(height: 20),
              Text(
                'Reset Password',
                style: GoogleFonts.poppins(
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 20),

              TextFormField(
                controller: resetemailController,
                focusNode: _resetemailFocusNode,
                decoration: InputDecoration(
                  prefixIcon: Icon(Icons.email_outlined, color: app_color),
                  labelText: 'Registered Email Address',
                  labelStyle: GoogleFonts.poppins(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w500,
                    fontSize: 14.5,
                  ),
                  filled: true,
                  fillColor:
                      Theme.of(context).inputDecorationTheme.fillColor ??
                      Colors.white,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide.none,
                  ),
                ),
                validator: (v) {
                  if (v == null || v.isEmpty) return 'Please enter email';
                  if (!RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$').hasMatch(v))
                    return 'Invalid email';
                  return null;
                },
              ),
              const SizedBox(height: 30),
              _isLoadingResetPass
                  ? const CupertinoActivityIndicator(radius: 18)
                  : ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: app_color,
                        padding: const EdgeInsets.symmetric(
                          vertical: 14,
                          horizontal: 60,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      onPressed: isResetPassButtonDisabled
                          ? null
                          : () {
                              if (_resetformKey.currentState!.validate()) {
                                if (resetemailController.text.trim() ==
                                    'demouser@ca-eim.com') {
                                  _scaffoldMessengerKey.currentState?.showSnackBar(
                                    const SnackBar(
                                      content: Text(
                                        'Reset password is not allowed for Demo User',
                                      ),
                                    ),
                                  );
                                } else {
                                  _resetpass();
                                }
                              }
                            },
                      child: Text(
                        'Reset Password',
                        style: GoogleFonts.poppins(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
              const SizedBox(height: 12),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.grey.shade300,
                  padding: const EdgeInsets.symmetric(
                    vertical: 14,
                    horizontal: 60,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                onPressed: () {
                  setState(() {
                    usernameController.text = resetemailController.text;
                    resetemailController.clear();
                    isVisibleResetPassForm = false;
                    isVisibleLoginForm = true;
                  });
                },
                child: Text(
                  'Cancel',
                  style: GoogleFonts.poppins(
                    color: Theme.of(context).colorScheme.onSurface,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildOtpForm(BuildContext context) {
    return SingleChildScrollView(
      key: const ValueKey('otpForm'),
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 40),
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor.withOpacity(0.9),
          borderRadius: BorderRadius.circular(30),
          boxShadow: [
            BoxShadow(
              color: Colors.black12.withOpacity(0.08),
              blurRadius: 16,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Form(
          key: _otpformKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // 🔹 Icon + Title
              Icon(Icons.mark_email_read_outlined, size: 80, color: app_color),
              const SizedBox(height: 16),
              Text(
                'Enter Verification Code',
                style: GoogleFonts.poppins(
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 6),
              RichText(
                textAlign: TextAlign.center,
                text: TextSpan(
                  style: GoogleFonts.poppins(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    fontSize: 14,
                  ),
                  children: [
                    const TextSpan(text: "We've sent an OTP to "),
                    TextSpan(
                      text: maskedEmail,
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                    ),
                    const TextSpan(
                      text: ". Please enter it below to continue.",
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 25),

              // 🔢 OTP Input Fields
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
                  borderRadius: BorderRadius.circular(12),
                  fieldHeight: 55,
                  fieldWidth: 55,
                  activeFillColor: app_color.withOpacity(0.15),
                  inactiveFillColor: Colors.white,
                  selectedFillColor: Colors.white,
                  activeColor: app_color,
                  inactiveColor: Colors.grey.shade400,
                  selectedColor: app_color,
                  borderWidth: 1.2,
                ),
                animationDuration: const Duration(milliseconds: 200),
                enableActiveFill: true,
                keyboardType: TextInputType.number,
                obscureText: false,
              ),

              const SizedBox(height: 25),

              // ⏳ Countdown timer
              if (isVisibleTimer)
                Column(
                  children: [
                    Text(
                      "Resend OTP in: $_formattedTime",
                      textAlign: TextAlign.center,
                      style: GoogleFonts.poppins(
                        fontSize: 14,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 18),
                  ],
                ),

              // 🔁 Resend OTP
              Visibility(
                visible: _isButtonEnabled,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: app_color,
                    padding: const EdgeInsets.symmetric(
                      vertical: 12,
                      horizontal: 20,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  icon: const Icon(Icons.refresh_rounded, color: Colors.white),
                  onPressed: () {
                    sendOTP(usernamee);
                    setState(() {
                      _isButtonEnabled = false;
                      isVisibleTimer = true;
                      _startTimer();
                    });
                  },
                  label: Text(
                    'Resend OTP',
                    style: GoogleFonts.poppins(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 10),

              // ✅ Verify Button
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: _isOtpVerifyingProgress
                      ? Colors.grey
                      : app_color,
                  padding: const EdgeInsets.symmetric(
                    vertical: 14,
                    horizontal: 60,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
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
                    : const Icon(Icons.verified_rounded, color: Colors.white),
                onPressed: _isOtpVerifyingProgress
                    ? null
                    : () {
                        _verifyOtpAndProceed(currentText);
                      },
                label: Text(
                  _isOtpVerifyingProgress ? 'Verifying...' : 'Verify',
                  style: GoogleFonts.poppins(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),

              /*ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: app_color,
                  padding:
                  const EdgeInsets.symmetric(vertical: 14, horizontal: 60),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                icon: const Icon(Icons.verified_rounded, color: Colors.white),
                */
              /*onPressed: () {
                  if (currentText.length == 4) {
                    final enteredOTP = currentText;
                    if (enteredOTP == generatedotp) {
                      // ✅ Same backend logic as before
                      socket.emit('deleteMyId', socket_data);
                      isOTPVerified = true;
                      isAnotherDevice = true;
                      _directlogin();
                    } else {
                      isOTPVerified = false;
                      isAnotherDevice = false;
                      Fluttertoast.showToast(msg: 'Incorrect OTP');
                    }
                  } else {
                    Fluttertoast.showToast(msg: 'Please enter a 4-digit OTP');
                  }
                },*/
              /*

                onPressed: () {
                  _verifyOtpAndProceed(currentText);
                },
                label: Text(
                  'Verify',
                  style: GoogleFonts.poppins(
                      color: Colors.white, fontWeight: FontWeight.w600),
                ),
              ),*/
              const SizedBox(height: 16),

              // 🔙 Cancel Button
              TextButton.icon(
                onPressed: () {
                  setState(() {
                    otpController.clear();
                    isVisibleOTPForm = false;
                    isVisibleLoginForm = true;
                    isVisibleTimer = false;
                  });
                },
                icon: Icon(
                  Icons.arrow_back_rounded,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
                label: Text(
                  "Back to Login",
                  style: GoogleFonts.poppins(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
