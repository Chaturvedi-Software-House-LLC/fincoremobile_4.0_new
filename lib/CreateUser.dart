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
import 'utils/email_template.dart';

class CreateUser extends ConsumerStatefulWidget {
  const CreateUser({Key? key}) : super(key: key);
  @override
  ConsumerState<CreateUser> createState() => _CreateUserPageState();
}

class _CreateUserPageState extends ConsumerState<CreateUser>
    with TickerProviderStateMixin {
  bool _isFocused_email = false, _isFocus_fullname = false;

  late final TextEditingController controller_username =
      TextEditingController();
  late final TextEditingController controller_password =
      TextEditingController();
  late final TextEditingController controller_fullname =
      TextEditingController();

  bool _isFocused_password = false;
  bool _obscureText = true;

  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  @override
  void dispose() {
    controller_username.dispose();
    controller_password.dispose();
    controller_fullname.dispose();
    super.dispose();
  }

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
      ..from = Address('noreply@fincoreerp.com', 'Fincore Go Support')
      ..recipients.add(email)
      ..subject = 'Your Login Credentials for Fincore Go'
      ..html = buildBrandedEmailHtml('''
  <p style="font-size: 14px; font-family: Arial, sans-serif; color: #333;">
    Hi <strong>$name</strong>,<br><br>
    Welcome to <strong>Fincore Go!</strong><br>
    Your account has been successfully created. Below are your login credentials:
  </p>

  <div style="background-color: #f5f5f5; color: #333; font-size: 14px; font-family: Arial, sans-serif; padding: 10px 20px; border-radius: 5px; display: inline-block; text-align: left;">
    <strong>Email:</strong> $email<br>
    <strong>Password:</strong> $password
  </div>

  <p style="font-size: 12px; font-family: Arial, sans-serif; color: #333; margin-top: 15px;">
    You can change your password anytime from the "Reset Password" option in the app.
  </p>

  <hr style="border: none; border-top: 1px solid #ddd; margin: 25px 0;">

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
''');

    try {
      await send(message, smtpServer); // ✅ DO NOT assign it to a variable
      debugPrint('Credential email sent to $email');
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
    required String firstName,
    required String lastName,
  }) async {
    final isEmailLogin = isEmail(userNameOrEmail);
    final result = await ref.read(createUserNotifierProvider.notifier).userRegistration(
      userNameOrEmail: userNameOrEmail,
      password: password,
      roleId: roleId,
      firstName: firstName,
      lastName: lastName,
      isEmailLogin: isEmailLogin,
    );

    if (result.success) {
      final fullName = '$firstName $lastName'.trim();
      if (result.emailToNotify != null) {
        sendUserCredentialsEmailSMTP(
          email: result.emailToNotify!,
          name: fullName,
          password: result.password!,
        );
      }

      controller_username.clear();
      controller_fullname.clear();
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
        // Returning `true` here told Flutter to ALSO run the default pop
        // right after this already navigated away via `pushReplacement` -
        // two conflicting navigation operations firing back-to-back (most
        // visible via iOS's edge-swipe-back gesture, which goes through
        // this exact callback). Since this handles the navigation itself,
        // it must return `false` to say "already handled, don't also
        // pop" - same fix as ModifyUser.dart's WillPopScope.
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => UserView()),
        );
        return false;
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
                              controller: controller_fullname,
                              icon: Icons.person_outline,
                              isFocused: _isFocus_fullname,
                              onFocus: () => _updateFocus(fullname: true),
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
    bool fullname = false,
    bool email = false,
    bool password = false,
  }) {
    setState(() {
      _isFocus_fullname = fullname;
      _isFocused_email = email;
      _isFocused_password = password;
    });
  }

  // Mirrors tally-oauth's actual `POST /company-user` Zod schema: `userName`
  // just needs to be non-empty (no length policy - see UserNameSchema),
  // `firstName` non-empty/<=100 chars, `lastName` <=100 chars but may be
  // empty (see FirstNameSchema/LastNameSchema - this screen's single "Full
  // Name" field is split on the first space, and a single-word name
  // legitimately leaves lastName empty), `phone` E.164 (`+` then up to 15
  // digits) if given. Password has no confirmed server-side
  // complexity/length rule beyond bcrypt's 72-byte input cap, so this only
  // enforces a conservative minimum (8) rather than inventing rules that
  // could reject a password the server would actually accept.
  static final RegExp _phoneE164 = RegExp(r'^\+[1-9]\d{1,14}$');

  /// Splits the single "Full Name" field into the backend's
  /// firstName/lastName pair (see UserCreateSchema's FirstNameSchema/
  /// LastNameSchema) - first word goes to firstName, everything else
  /// (possibly nothing, for a single-word name) to lastName.
  ({String firstName, String lastName}) _splitFullName(String fullName) {
    final parts = fullName.trim().split(RegExp(r'\s+'));
    return (firstName: parts.first, lastName: parts.skip(1).join(' '));
  }

  void _submitForm() {
    final fullName = controller_fullname.text.trim();
    final username = controller_username.text.trim();
    final roleId =
        ref.read(createUserNotifierProvider).selectedRole?["id"] as String?;

    if (fullName.isEmpty) {
      showAppMessage(context, "Please enter a name");
      return;
    }
    if (fullName.length > 100) {
      showAppMessage(context, "Name must be 100 characters or fewer");
      return;
    }
    final (:firstName, :lastName) = _splitFullName(fullName);
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
      // Matches tally-admin-api's PasswordSchema - only length and one
      // special character are required now (lowercase/uppercase/number
      // rules were dropped from both sides).
      if (!RegExp(r'[^a-zA-Z0-9]').hasMatch(finalPassword)) {
        showAppMessage(
          context,
          "Password must contain at least one special character",
        );
        return;
      }
    }

    _updateFocus();

    userRegistration(
      userNameOrEmail: username,
      password: finalPassword,
      roleId: roleId,
      firstName: firstName,
      lastName: lastName,
    );
  }
}
