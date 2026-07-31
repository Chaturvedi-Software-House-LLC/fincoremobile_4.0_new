import 'dart:convert';
import 'dart:math';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:mailer/mailer.dart';
import 'package:mailer/smtp_server.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'UserView.dart';
import 'constants.dart';
import 'package:http/http.dart' as http;
import 'package:FincoreGo/widgets/app_bottom_nav.dart';
import 'widgets/entry_widgets.dart';
import 'widgets/searchable_selector.dart';

class CreateUser extends StatefulWidget {
  const CreateUser({Key? key}) : super(key: key);
  @override
  _CreateUserPageState createState() => _CreateUserPageState();
}

class _CreateUserPageState extends State<CreateUser>
    with TickerProviderStateMixin {
  bool isDashEnable = true,
      isRolesVisible = true,
      isUserEnable = true,
      isUserVisible = true,
      isRolesEnable = true,
      _isLoading = false,
      isVisibleNoUserFound = false,
      _isFocused_email = false,
      _isFocus_name = false;

  List<dynamic> myData_roles = [];

  dynamic _selectedrole;
  List<String> _selectedCompanies = [];
  List<String> myDataCompanies = [];

  String user_email_fetched = "";

  late final TextEditingController controller_username =
      TextEditingController();
  late final TextEditingController controller_password =
      TextEditingController();
  late final TextEditingController controller_name = TextEditingController();

  bool _isFocused_password = false;
  bool _obscureText = true;

  String name = "", usernameOrEmail = "";

  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  late GlobalKey<ScaffoldMessengerState> _scaffoldMessengerKey;

  late SharedPreferences prefs;

  String? hostname = "",
      company = "",
      company_lowercase = "",
      serial_no = "",
      username = "",
      HttpURL = "",
      SecuritybtnAcessHolder = "";

  bool isEmail(String value) {
    return RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$').hasMatch(value.trim());
  }

  Future<void> _initSharedPreferences() async {
    prefs = await SharedPreferences.getInstance();

    setState(() {
      hostname = prefs.getString('hostname');

      company = prefs.getString('company_name');
      company_lowercase = company!.replaceAll(' ', '').toLowerCase();
      serial_no = prefs.getString('serial_no');
      username = prefs.getString('username');

      SecuritybtnAcessHolder = prefs.getString('secbtnaccess');

      String? email_nav = prefs.getString('email_nav');
      String? name_nav = prefs.getString('name_nav');

      if (email_nav != null && name_nav != null) {
        name = name_nav;
        usernameOrEmail = email_nav;
      }

      if (SecuritybtnAcessHolder == "True") {
        isRolesVisible = true;
        isUserVisible = true;
      } else {
        isRolesVisible = false;
        isUserVisible = false;
      }
      fetchRoles(serial_no!);
      fetchCompany(serial_no!);
    });
  }

  void sendUserCredentialsEmailSMTP({
    required String email,
    required String name,
    required String password,
  }) async {
    final smtpServer = SmtpServer(
      'smtp.hostinger.com',
      username: 'noreply@fincoreerp.com',
      password: '^QLNlsU8m',
      port: 465,
      ssl: true,
    );

    final message = Message()
      ..from = Address('noreply@fincoreerp.com', 'Fincore Support')
      ..recipients.add(email)
      ..subject = 'Your Login Credentials for Fincore Go'
      ..html =
          '''
<div style="border: 1px solid #ccc; padding: 30px; margin: 20px; text-align: center; font-family: Arial, sans-serif; color: #333;">
  <a href="https://tallyuae.ae/">
    <img src="https://mobile.chaturvedigroup.com/fincore_logo/tally_1.png" 
         alt="Logo" 
         style="width: 150px; height: auto; margin-bottom: 15px;">
  </a>

  <p style="font-size: 14px;">
    Hi <strong>$name</strong>,<br><br>
    Welcome to <strong>Fincore Go!</strong><br>
    Your account has been successfully created. Below are your login credentials:
  </p>

  <div style="background-color: #f5f5f5; color: #333; font-size: 14px; padding: 10px 20px; border-radius: 5px; display: inline-block; text-align: left;">
    <strong>Email:</strong> $email<br>
    <strong>Password:</strong> $password
  </div>

  <p style="font-size: 12px; margin-top: 15px;">
    You can change your password anytime from the "Reset Password" option in the app.
  </p>

  <hr style="border: none; border-top: 1px solid #ddd; margin: 25px 0;">

  <!-- 📱 Mobile App Download Buttons -->
  <div style="text-align: center;">
    <h3 style="font-family: Arial, sans-serif; color: #333; margin-bottom: 10px;">
      Get the Fincore Go Mobile App
    </h3>

    <div style="display: inline-block;">
      <a href="https://play.google.com/store/apps/details?id=com.csh.fincoremobile" target="_blank" style="margin-right: 0px;">
          <img src="https://upload.wikimedia.org/wikipedia/commons/7/78/Google_Play_Store_badge_EN.svg" 
               alt="Get it on Google Play" 
               style="width: 150px; height: auto;">
      </a>

      <a href="https://apps.apple.com/ae/app/fincore-mobile/id6451186057" target="_blank">
        <img src="https://upload.wikimedia.org/wikipedia/commons/3/3c/Download_on_the_App_Store_Badge.svg" 
             alt="Download on the App Store" 
             style="width: 150px; height: auto;">
      </a>
    </div>
  </div>

  <!-- 🖥️ Desktop App Download Button -->
  <div style="text-align: center; margin-top: 30px;">
    <h3 style="font-family: Arial, sans-serif; color: #333; margin-bottom: 10px;">
      Get the Fincore Go Desktop App
    </h3>

    <a href="https://mobile.chaturvedigroup.com/download/" target="_blank">
      <img src="https://upload.wikimedia.org/wikipedia/commons/6/68/Windows_logo_and_wordmark_-_2012–2015.svg" 
           alt="Download Fincore Go Desktop for Windows" 
           style="width: 150px; height: auto;">
    </a>
  </div>

  <hr style="border: none; border-top: 1px solid #ddd; margin: 25px 0;">

  <p style="font-size: 12px;">
    If you did not request this account, please contact 
    <a href="mailto:saadan@ca-eim.com" style="color: #1a73e8;">saadan@ca-eim.com</a>.
  </p>

  <p style="color: #999; font-style: italic; font-size: 12px;">
    Disclaimer: This email is for credential delivery only. Please do not share your password with anyone.<br>
    This is a system-generated email. Do not reply.
  </p>

  <div style="border-top: 1px solid #ccc; padding-top: 10px; margin-top: 10px; text-align: center;">
    <p style="font-size: 10px; color: #a3a2a2; line-height: 1.4;">
      © 2023-2026 Chaturvedi Software House LLC. All Rights Reserved<br>
      513 Al Khaleej Center, Bur Dubai, Dubai, United Arab Emirates | +97143258361
    </p>
  </div>
</div>
''';

    try {
      await send(message, smtpServer); // ✅ DO NOT assign it to a variable
      print('Credential email sent to $email');
    } catch (e) {
      showAppMessage(context, 'Failed to send email: $e');
    }
  }

  Future<void> userRegistration(
    String selectedserial,
    String email,
    String password,
    String rolename,
    String name,
  ) async {
    setState(() {
      _isLoading = true;
    });

    try {
      final url = Uri.parse('$BASE_URL_config/api/login/userRegistration');

      Map<String, String> headers = {
        'Authorization': 'Bearer $authTokenBase',
        "Content-Type": "application/json",
      };

      var body = jsonEncode({
        "username": email,
        "serialno": selectedserial,
        "password": password,
        "rolename": rolename,
        "name": name,
      });

      final response = await http.post(url, body: body, headers: headers);

      if (response.statusCode == 200) {
        String responsee = response.body;

        if (responsee == "User Registered Successfully") {
          showAppMessage(context, "User created successfully", isError: false);
          addAllowedCompanies(email, serial_no!, _selectedCompanies);

          controller_username.clear();
          controller_name.clear();
          controller_password.clear();
          _selectedrole = myData_roles[0];
          FocusScope.of(context).unfocus();

          if (isEmail(email)) {
            sendUserCredentialsEmailSMTP(
              email: email,
              name: name,
              password: password,
            );
          }
        } else if (responsee == "No of users exceeded") {
          controller_username.clear();
          controller_name.clear();
          controller_password.clear();
          _selectedrole = myData_roles.first;
          FocusScope.of(context).unfocus();
        } else {
          controller_username.clear();
          controller_name.clear();
          controller_password.clear();
          _selectedrole = myData_roles[0];
          FocusScope.of(context).unfocus();
        }
      } else {
        Map<String, dynamic> data = json.decode(utf8.decode(response.bodyBytes));
        String error = '';

        if (data.containsKey('error')) {
          setState(() {
            error = data['error'];
          });
        } else {
          error = 'Something went wrong!!!';
        }

        showAppMessage(context, error);
      }
      setState(() {
        _isLoading = false;
      });
    } catch (e) {
      print(e);
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> fetchRoles(String selectedserial) async {
    /*setState(() {
      _isLoading = true;
    });*/

    try {
      final url = Uri.parse('$BASE_URL_config/api/roles/get');
      Map<String, String> headers = {
        'Authorization': 'Bearer $authTokenBase',
        "Content-Type": "application/json",
      };

      var body = jsonEncode({'serialno': selectedserial});

      final response = await http.post(url, body: body, headers: headers);

      if (response.statusCode == 200) {
        myData_roles = jsonDecode(utf8.decode(response.bodyBytes));
        if (myData_roles != null) {
          setState(() {
            _selectedrole = myData_roles.first;
          });
        }

        setState(() {
          _isLoading = false;
        });
      }
    } catch (e) {
      print(e);
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> fetchCompany(String selectedserial) async {
    myDataCompanies.clear();
    final url = Uri.parse('$BASE_URL_config/api/admin/getCompany');

    Map<String, String> headers = {
      'Authorization': 'Bearer $authTokenBase',
      "Content-Type": "application/json",
    };

    var body = jsonEncode({'serialno': selectedserial});

    final response = await http.post(url, body: body, headers: headers);

    if (response.statusCode == 200) {
      final List<dynamic> responseData = jsonDecode(utf8.decode(response.bodyBytes));
      if (responseData != null) {
        setState(() {
          myDataCompanies = responseData.map<String>((item) {
            return item['company_name'] as String;
          }).toList();
        });
      }

      setState(() {
        _isLoading = false;
      });
    } else {
      Map<String, dynamic> data = json.decode(utf8.decode(response.bodyBytes));
      String error = '';

      if (data.containsKey('error')) {
        setState(() {
          error = data['error'];
        });
      } else {
        error = 'Something went wrong!!!';
      }
      showAppMessage(context, error);

      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> addAllowedCompanies(
    String email,
    String serialno,
    List<String> companies_list,
  ) async {
    // myDataCompanies.clear();
    final url = Uri.parse('$BASE_URL_config/api/roles/allowed_companies');

    Map<String, String> headers = {
      'Authorization': 'Bearer $authTokenBase',
      "Content-Type": "application/json",
    };

    print('$serialno, $email, $companies_list');

    var body = jsonEncode({
      'serial_no': serialno,
      'user_name': email,
      'companies': companies_list,
    });

    final response = await http.post(url, body: body, headers: headers);

    if (response.statusCode == 200) {
      print(response.body);

      setState(() {
        _selectedCompanies.clear();
      });
    } else {
      Map<String, dynamic> data = json.decode(utf8.decode(response.bodyBytes));
      String error = '';

      if (data.containsKey('error')) {
        setState(() {
          error = data['error'];
        });
      } else {
        error = 'Something went wrong!!!';
      }
      showAppMessage(context, error);

      setState(() {
        _isLoading = false;
      });
    }
  }

  void _openMultiSelectDialog() async {
    List<String> tempSelectedCompanies = List.from(_selectedCompanies);

    final selectedValues = await showDialog<List<String>>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          backgroundColor: Theme.of(context).scaffoldBackgroundColor,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          titlePadding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
          contentPadding: const EdgeInsets.fromLTRB(24, 12, 24, 12),
          actionsPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          title: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Select Companies',
                style: GoogleFonts.poppins(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              IconButton(
                icon: Icon(
                  Icons.close,
                  size: 20,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
                onPressed: () => Navigator.pop(context),
                splashRadius: 20,
              ),
            ],
          ),
          content: StatefulBuilder(
            builder: (context, setState) {
              bool isAllSelected =
                  tempSelectedCompanies.length == myDataCompanies.length;

              return SizedBox(
                width: double.maxFinite,
                height: 170,
                child: Scrollbar(
                  thumbVisibility: true,
                  child: ListView(
                    children: [
                      // Select All
                      CheckboxListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        title: Text(
                          'Select All',
                          style: GoogleFonts.poppins(fontSize: 14),
                        ),
                        value: isAllSelected,
                        onChanged: (bool? checked) {
                          setState(() {
                            if (checked == true) {
                              tempSelectedCompanies = List.from(
                                myDataCompanies,
                              );
                            } else {
                              tempSelectedCompanies.clear();
                            }
                          });
                        },
                        activeColor: Colors.teal,
                        controlAffinity: ListTileControlAffinity.leading,
                      ),
                      Divider(),

                      // Individual Company Checkboxes
                      ...myDataCompanies.map((company) {
                        return CheckboxListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          title: Text(
                            company,
                            style: GoogleFonts.poppins(fontSize: 14),
                          ),
                          value: tempSelectedCompanies.contains(company),
                          onChanged: (bool? checked) {
                            setState(() {
                              if (checked == true) {
                                tempSelectedCompanies.add(company);
                              } else {
                                tempSelectedCompanies.remove(company);
                              }
                            });
                          },
                          activeColor: Colors.teal,
                          controlAffinity: ListTileControlAffinity.leading,
                        );
                      }).toList(),
                    ],
                  ),
                ),
              );
            },
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, null),
              child: Text(
                'Cancel',
                style: GoogleFonts.poppins(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.teal,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 10,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              onPressed: () => Navigator.pop(context, tempSelectedCompanies),
              child: Text(
                'Confirm',
                style: GoogleFonts.poppins(fontWeight: FontWeight.w500),
              ),
            ),
          ],
        );
      },
    );

    // Save selected companies if confirmed
    if (selectedValues != null) {
      setState(() {
        _selectedCompanies = selectedValues;
      });
    }
  }

  @override
  void initState() {
    super.initState();
    _scaffoldMessengerKey = GlobalKey<ScaffoldMessengerState>();
    _initSharedPreferences();
  }

  bool isValidEmail(String email) {
    // Simple email validation pattern
    final RegExp emailRegex = RegExp(
      r'^[\w-]+(\.[\w-]+)*@[a-zA-Z0-9-]+(\.[a-zA-Z0-9-]+)*(\.[a-zA-Z]{2,})$',
    );
    return emailRegex.hasMatch(email);
  }

  @override
  Widget build(BuildContext context) {
    final bool isUsernameLogin =
        controller_username.text.isNotEmpty &&
        !isEmail(controller_username.text);

    return WillPopScope(
      onWillPop: () async {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => UserView()),
        );
        return true;
      },
      child: Scaffold(
        bottomNavigationBar: const AppBottomNav(
          activeTab: AppBottomNavTab.more,
          activeMoreItem: AppMoreItem.users,
        ),
        key: _scaffoldKey,
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        appBar: PreferredSize(
          preferredSize: Size.fromHeight(50),
          child: AppBar(
            backgroundColor: app_color,
            elevation: 6,
            automaticallyImplyLeading: false,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.vertical(bottom: Radius.circular(20)),
            ),
            leading: IconButton(
              icon: Icon(Icons.arrow_back, color: Colors.white),
              onPressed: () {
                Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(builder: (_) => UserView()),
                );
              },
            ),
            title: Text(
              "User Registration",
              style: GoogleFonts.poppins(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.w600,
              ),
            ),
            centerTitle: true,
            actions: [],
          ),
        ),
        body: LayoutBuilder(
              builder: (context, constraints) {
                return SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 16,
                  ),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      minHeight: constraints.maxHeight - 50,
                    ),
                    child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 20,
                        ),
                        decoration: BoxDecoration(
                          color: Theme.of(context).cardColor,
                          borderRadius: BorderRadius.circular(16),
                          border:
                              Theme.of(context).brightness == Brightness.dark
                              ? Border.all(
                                  color: Colors.white.withOpacity(0.10),
                                  width: 1,
                                )
                              : null,
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black12.withOpacity(0.08),
                              blurRadius: 16,
                              offset: Offset(0, 8),
                            ),
                          ],
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            ListTile(
                              contentPadding: EdgeInsets.zero,
                              leading: CircleAvatar(
                                backgroundColor: app_color.withOpacity(0.1),
                                radius: 22,
                                child: Icon(
                                  Icons.person,
                                  size: 24,
                                  color: app_color,
                                ),
                              ),
                              title: Text(
                                'Create New User',
                                style: GoogleFonts.poppins(
                                  fontSize: 17,
                                  fontWeight: FontWeight.w600,
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onSurface,
                                ),
                              ),
                              subtitle: Padding(
                                padding: EdgeInsets.only(top: 4),
                                child: Text(
                                  'Please provide the details of the user you want to add.',
                                  style: GoogleFonts.poppins(
                                    fontSize: 13,
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 16),
                            _modernTextField(
                              label: 'Full Name',
                              controller: controller_name,
                              icon: Icons.person_outline,
                              isFocused: _isFocus_name,
                              onFocus: () => _updateFocus(name: true),
                            ),
                            const SizedBox(height: 20),
                            _modernTextField(
                              label: 'Username or Email',
                              controller: controller_username,
                              icon: Icons.email_outlined,
                              keyboardType: TextInputType.emailAddress,
                              isFocused: _isFocused_email,
                              onFocus: () => _updateFocus(email: true),
                            ),
                            if (isUsernameLogin) ...[
                              const SizedBox(height: 20),

                              _modernTextField(
                                label: 'Password',
                                controller: controller_password,
                                icon: Icons.lock_outline,
                                isPassword: true,
                                obscureText: _obscureText,
                                isFocused: _isFocused_password,
                                onFocus: () => _updateFocus(password: true),
                                toggleObscure: () {
                                  setState(() {
                                    _obscureText = !_obscureText;
                                  });
                                },
                              ),
                            ],
                            const SizedBox(height: 20),

                            Text(
                              "Select Role",
                              style: GoogleFonts.poppins(
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            const SizedBox(height: 8),
                            SearchableSelectorField<dynamic>(
                              value: _selectedrole,
                              items: myData_roles,
                              itemLabel: (item) =>
                                  (item['role_name'] ?? '').toString(),
                              hintText: 'Choose a role',
                              onChanged: (value) =>
                                  setState(() => _selectedrole = value),
                            ),
                            const SizedBox(height: 20),
                            Text(
                              "Allowed Companies",
                              style: GoogleFonts.poppins(
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            const SizedBox(height: 8),
                            GestureDetector(
                              onTap: _openMultiSelectDialog,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 12,
                                ),
                                constraints: const BoxConstraints(
                                  minHeight: 56,
                                ),
                                decoration: BoxDecoration(
                                  color: Theme.of(context).cardColor,
                                  borderRadius: _formFieldBorderRadius,
                                  border: Border.all(
                                    color: Theme.of(context).dividerColor,
                                  ),
                                ),
                                alignment: Alignment.centerLeft,
                                child: Text(
                                  _selectedCompanies.isNotEmpty
                                      ? _selectedCompanies.join('\n')
                                      : 'Tap to select companies',
                                  style: GoogleFonts.poppins(fontSize: 14),
                                ),
                              ),
                            ),
                            SizedBox(height: 24),
                            ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: app_color,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(
                                  vertical: 14,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                elevation: 4,
                              ),
                              onPressed: _isLoading ? null : _submitForm,
                              child: _isLoading
                                  ? Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        SizedBox(
                                          height: 20,
                                          width: 20,
                                          child:
                                              Theme.of(context).platform ==
                                                  TargetPlatform.iOS
                                              ? const CupertinoActivityIndicator(
                                                  radius: 10,
                                                  color: Colors.white,
                                                )
                                              : const CircularProgressIndicator(
                                                  strokeWidth: 2.5,
                                                  valueColor:
                                                      AlwaysStoppedAnimation<
                                                        Color
                                                      >(Colors.white),
                                                  backgroundColor:
                                                      Colors.transparent,
                                                ),
                                        ),
                                        const SizedBox(width: 12),
                                        Text(
                                          'Saving...',
                                          style: GoogleFonts.poppins(
                                            fontWeight: FontWeight.w600,
                                            color: Colors.white,
                                          ),
                                        ),
                                      ],
                                    )
                                  : Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        const Icon(Icons.save_alt),
                                        const SizedBox(width: 10),
                                        Text(
                                          'REGISTER',
                                          style: GoogleFonts.poppins(
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ],
                                    ),
                            ),
                          ],
                        ),
                      ),
                  ),
                );
              },
            ),
      ),
    );
    // TODO: implement build
  }

  BorderRadius get _formFieldBorderRadius => BorderRadius.circular(22);

  OutlineInputBorder _formFieldBorder(Color color, {double width = 1}) {
    return OutlineInputBorder(
      borderRadius: _formFieldBorderRadius,
      borderSide: BorderSide(color: color, width: width),
    );
  }

  InputDecoration _modernDropdownDecoration() => InputDecoration(
    filled: true,
    fillColor: Theme.of(context).cardColor,
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
    border: _formFieldBorder(Theme.of(context).dividerColor),
    enabledBorder: _formFieldBorder(Theme.of(context).dividerColor),
    disabledBorder: _formFieldBorder(Theme.of(context).dividerColor),
    focusedBorder: _formFieldBorder(app_color, width: 1.5),
    errorBorder: _formFieldBorder(Theme.of(context).colorScheme.error),
    focusedErrorBorder: _formFieldBorder(
      Theme.of(context).colorScheme.error,
      width: 1.5,
    ),
  );

  String _generateRandomPassword({int length = 8}) {
    const chars =
        'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    final rand = Random.secure();
    return List.generate(
      length,
      (index) => chars[rand.nextInt(chars.length)],
    ).join();
  }

  Widget _modernTextField({
    required String label,
    required TextEditingController controller,
    required IconData icon,
    required VoidCallback onFocus,
    bool isPassword = false,
    bool obscureText = false,
    bool isFocused = false,
    VoidCallback? toggleObscure,
    TextInputType keyboardType = TextInputType.text,
  }) {
    return TextFormField(
      controller: controller,
      obscureText: obscureText,
      keyboardType: keyboardType,
      onTap: onFocus,
      onChanged: (_) {
        onFocus();
        setState(() {});
      },
      decoration: InputDecoration(
        labelText: label,
        labelStyle: GoogleFonts.poppins(
          color: isFocused
              ? app_color
              : Theme.of(context).colorScheme.onSurface,
        ),
        filled: true,
        fillColor: Theme.of(context).cardColor,
        prefixIcon: Icon(
          icon,
          color: isFocused
              ? app_color
              : Theme.of(context).colorScheme.onSurface,
        ),
        suffixIcon: isPassword
            ? IconButton(
                icon: Icon(
                  obscureText ? Icons.visibility_off : Icons.visibility,
                  color: isFocused
                      ? app_color
                      : Theme.of(context).colorScheme.onSurface,
                ),
                onPressed: toggleObscure,
              )
            : null,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 16,
        ),
        border: _formFieldBorder(Theme.of(context).dividerColor),
        enabledBorder: _formFieldBorder(Theme.of(context).dividerColor),
        disabledBorder: _formFieldBorder(Theme.of(context).dividerColor),
        focusedBorder: _formFieldBorder(app_color, width: 1.5),
        errorBorder: _formFieldBorder(Theme.of(context).colorScheme.error),
        focusedErrorBorder: _formFieldBorder(
          Theme.of(context).colorScheme.error,
          width: 1.5,
        ),
      ),
    );
  }

  void _updateFocus({
    bool name = false,
    bool email = false,
    bool password = false,
  }) {
    setState(() {
      _isFocus_name = name;
      _isFocused_email = email;
      _isFocused_password = password;
    });
  }

  void _submitForm() {
    final name = controller_name.text.trim();
    final username = controller_username.text.trim();
    final role = _selectedrole?["role_name"];

    if (name.isEmpty || username.isEmpty || role == null) {
      showAppMessage(context, "Please fill all required fields.");
      return;
    }

    String finalPassword = '';

    // EMAIL USER
    if (isEmail(username)) {
      finalPassword = _generateRandomPassword();
    }
    // USERNAME USER
    else {
      finalPassword = controller_password.text.trim();

      if (finalPassword.isEmpty) {
        showAppMessage(context, "Please enter password");
        return;
      }

      if (finalPassword.length < 4) {
        showAppMessage(context, "Password too short");
        return;
      }
    }

    _updateFocus();

    userRegistration(serial_no!, username, finalPassword, role, name);
  }

  /*void _submitForm() {
    final name = controller_name.text;
    final email = controller_username.text;
    final password = controller_password.text;
    final role = _selectedrole?["role_name"];

    if (name.isEmpty || email.isEmpty || role == null) {
      showAppMessage(context, "Please fill all required fields.");
      return;
    }


    _updateFocus();
    final generatedPassword = _generateRandomPassword(); // generates 5-char password
    userRegistration(serial_no!, email, generatedPassword, role, name);
  }*/
}
