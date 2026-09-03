import 'dart:math';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:mailer/mailer.dart';
import 'package:mailer/smtp_server.dart';
import 'UserView.dart';
import 'constants.dart';
import 'package:FincoreGo/widgets/app_bottom_nav.dart';
import 'widgets/entry_widgets.dart';
import 'widgets/searchable_selector.dart';
import 'providers/create_user_notifier.dart';

class CreateUser extends ConsumerStatefulWidget {
  const CreateUser({Key? key}) : super(key: key);
  @override
  ConsumerState<CreateUser> createState() => _CreateUserPageState();
}

class _CreateUserPageState extends ConsumerState<CreateUser>
    with TickerProviderStateMixin {
  bool _isFocused_email = false, _isFocus_name = false;

  late final TextEditingController controller_username =
      TextEditingController();
  late final TextEditingController controller_password =
      TextEditingController();
  late final TextEditingController controller_name = TextEditingController();

  bool _isFocused_password = false;
  bool _obscureText = true;

  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  bool isEmail(String value) {
    return RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$').hasMatch(value.trim());
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

  /// Creates (or reuses, per company-user.service.ts's create()) a `User`
  /// and links it to the current company-user session's company - unlike
  /// the legacy backend, there is no "allowed companies" multi-select
  /// concept: a company-user is always scoped to exactly one company (the
  /// one that's currently active), so that step is gone entirely.
  Future<void> userRegistration({
    required String userNameOrEmail,
    required String password,
    required String roleId,
    required String name,
  }) async {
    final isEmailLogin = isEmail(userNameOrEmail);
    final result = await ref.read(createUserNotifierProvider.notifier).userRegistration(
      userNameOrEmail: userNameOrEmail,
      password: password,
      roleId: roleId,
      name: name,
      isEmailLogin: isEmailLogin,
    );

    if (result.success) {
      if (result.emailToNotify != null) {
        sendUserCredentialsEmailSMTP(
          email: result.emailToNotify!,
          name: name,
          password: result.password!,
        );
      }

      controller_username.clear();
      controller_name.clear();
      controller_password.clear();
      if (mounted) FocusScope.of(context).unfocus();
    }
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
    final vm = ref.watch(createUserNotifierProvider);
    final notifier = ref.read(createUserNotifierProvider.notifier);
    ref.listen<CreateUserState>(createUserNotifierProvider, (previous, next) {
      if (next.errorMessage != null) {
        showAppMessage(context, next.errorMessage!);
        notifier.clearError();
      }
      if (next.successMessage != null) {
        showAppMessage(context, next.successMessage!, isError: false);
        notifier.clearSuccess();
      }
    });
    final myData_roles = vm.roles;
    final selectedrole = vm.selectedRole;
    final isLoading = vm.isLoading;

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
                              value: selectedrole,
                              items: myData_roles,
                              itemLabel: (item) =>
                                  (item['name'] ?? '').toString(),
                              hintText: 'Choose a role',
                              onChanged: (value) => notifier
                                  .selectRole(value as Map<String, dynamic>?),
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
                              onPressed: isLoading ? null : _submitForm,
                              child: isLoading
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

  // Mirrors tally-oauth's actual `POST /company-user` Zod schema (confirmed
  // live against the running server, not guessed): `userName` >= 8 chars,
  // `firstName`/`lastName`/`email` <= their DB column widths (VarChar(100)/
  // VarChar(100)/VarChar(320)), `phone` E.164 (`+` then up to 15 digits) if
  // given. Password has no confirmed server-side complexity/length rule
  // beyond bcrypt's 72-byte input cap, so this only enforces a conservative
  // minimum (8, matching userName) rather than inventing rules that could
  // reject a password the server would actually accept.
  static final RegExp _phoneE164 = RegExp(r'^\+[1-9]\d{1,14}$');

  void _submitForm() {
    final name = controller_name.text.trim();
    final username = controller_username.text.trim();
    final roleId =
        ref.read(createUserNotifierProvider).selectedRole?["id"] as String?;

    if (name.isEmpty) {
      showAppMessage(context, "Please enter the user's full name");
      return;
    }
    if (name.length > 100) {
      showAppMessage(context, "Full name must be 100 characters or fewer");
      return;
    }
    if (username.isEmpty) {
      showAppMessage(context, "Please enter a username or email");
      return;
    }
    if (roleId == null) {
      showAppMessage(context, "Please select a role");
      return;
    }

    String finalPassword = '';

    // EMAIL USER
    if (isEmail(username)) {
      if (username.length > 320) {
        showAppMessage(context, "Email must be 320 characters or fewer");
        return;
      }
      finalPassword = _generateRandomPassword();
    }
    // USERNAME USER
    else {
      if (username.length < 8) {
        showAppMessage(context, "Username must be at least 8 characters");
        return;
      }
      if (username.length > 100) {
        showAppMessage(context, "Username must be 100 characters or fewer");
        return;
      }

      finalPassword = controller_password.text.trim();

      if (finalPassword.isEmpty) {
        showAppMessage(context, "Please enter password");
        return;
      }

      if (finalPassword.length < 8) {
        showAppMessage(context, "Password must be at least 8 characters");
        return;
      }
      if (finalPassword.length > 72) {
        showAppMessage(context, "Password must be 72 characters or fewer");
        return;
      }
    }

    _updateFocus();

    userRegistration(
      userNameOrEmail: username,
      password: finalPassword,
      roleId: roleId,
      name: name,
    );
  }

  /*void _submitForm() {
    final name = controller_name.text;
    final email = controller_username.text;
    final password = controller_password.text;
    final role = selectedrole?["role_name"];

    if (name.isEmpty || email.isEmpty || role == null) {
      showAppMessage(context, "Please fill all required fields.");
      return;
    }


    _updateFocus();
    final generatedPassword = _generateRandomPassword(); // generates 5-char password
    userRegistration(serial_no!, email, generatedPassword, role, name);
  }*/
}
