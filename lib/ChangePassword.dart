import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'constants.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:FincoreGo/widgets/app_bottom_nav.dart';
import 'widgets/entry_widgets.dart';
import 'api/auth_repository.dart';
import 'api/api_exception.dart';

class ChangePassword extends StatefulWidget {
  @override
  _ChangePasswordScreenState createState() => _ChangePasswordScreenState();
}

class _ChangePasswordScreenState extends State<ChangePassword> {
  final newPassController = TextEditingController();
  final confirmPassController = TextEditingController();
  final otpController = TextEditingController();
  bool showNewPassValidation = false;
  bool showConfirmValidation = false;

  dynamic _formKey = GlobalKey<FormState>();

  bool hasLower = false;
  bool hasUpper = false;
  bool hasNumber = false;
  bool isMatch = false;
  bool isLoading = false;

  bool isNewPassVisible = false;
  bool isConfirmPassVisible = false;
  bool isOtpVisible = false;

  // tally-oauth has no "change password with your current password"
  // endpoint - only the OTP-based reset flow below (the app's sole login
  // driver since Phase 6, so this is the only path any session ever takes).
  String _username = '';
  // Set once step 1 (send OTP) succeeds - the short-lived token from
  // `reset-password` that authorizes the actual `change-password` call.
  String? _resetToken;

  @override
  void initState() {
    super.initState();
    _loadSession();
  }

  Future<void> _loadSession() async {
    final prefs = await SharedPreferences.getInstance();
    final username = prefs.getString('username') ?? '';
    if (!mounted) return;
    setState(() {
      _username = username;
    });
  }

  void validateNewPassword(String value) {
    setState(() {
      showNewPassValidation = value.isNotEmpty;

      hasLower = RegExp(r'[a-z]').hasMatch(value);
      hasUpper = RegExp(r'[A-Z]').hasMatch(value);
      hasNumber = RegExp(r'[0-9]').hasMatch(value);

      // also update match in case confirm already filled
      isMatch = value == confirmPassController.text;
    });
  }

  void validateConfirmPassword(String value) {
    setState(() {
      showConfirmValidation = value.isNotEmpty;
      isMatch = value == newPassController.text;
    });
  }

  Widget _modernField(
    String label,
    TextEditingController controller,
    IconData icon,
    bool isVisible,
    VoidCallback toggleVisibility, {
    Function(String)? onChanged,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      obscureText: !isVisible,
      autovalidateMode: AutovalidateMode.onUserInteraction,

      validator: validator, // 🔥 THIS IS THE KEY
      onChanged: onChanged,
      style: GoogleFonts.poppins(),
      decoration: InputDecoration(
        prefixIcon: Icon(icon, color: app_color),
        // 👇 Eye icon
        suffixIcon: IconButton(
          icon: Icon(
            isVisible ? Icons.visibility : Icons.visibility_off,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
          onPressed: toggleVisibility,
        ),

        labelText: label,
        labelStyle: GoogleFonts.poppins(
          color: Theme.of(context).colorScheme.onSurfaceVariant, // default
        ),

        floatingLabelStyle: GoogleFonts.poppins(
          color: app_color, // 🔥 when selected (focus)
          fontWeight: FontWeight.w500,
        ),

        filled: true,
        fillColor:
            Theme.of(context).inputDecorationTheme.fillColor ??
            Colors.white, // ✅ white background

        contentPadding: EdgeInsets.symmetric(vertical: 14),

        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: Theme.of(context).dividerColor),
        ),

        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: Theme.of(context).dividerColor),
        ),

        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: app_color, width: 1.3),
        ),
      ),
    );
  }

  Future<void> handleChangePassword() => _handleConfirmReset();

  /// Step 1 of the tally-oauth OTP flow - sends an OTP to the account's
  /// email and stashes the short-lived reset token step 2 needs.
  Future<void> _handleSendOtp() async {
    setState(() => isLoading = true);
    try {
      final token = await AuthRepository.instance.requestPasswordResetOtp(
        username: _username,
      );
      if (!mounted) return;
      setState(() {
        _resetToken = token;
        isLoading = false;
      });
      _showMessage('OTP sent to your registered email.');
    } on ApiException catch (e) {
      setState(() => isLoading = false);
      _showMessage(e.message);
    } catch (e) {
      setState(() => isLoading = false);
      _showMessage('Network error. Please try again.');
    }
  }

  /// Step 2 of the tally-oauth OTP flow - the "Update Password" button's
  /// tally-oauth path once an OTP has been requested.
  Future<void> _handleConfirmReset() async {
    if (!_formKey.currentState!.validate()) return;
    final resetToken = _resetToken;
    if (resetToken == null) return;

    setState(() => isLoading = true);
    try {
      await AuthRepository.instance.changePassword(
        resetToken: resetToken,
        otp: otpController.text,
        password: newPassController.text,
      );
      if (!mounted) return;
      _showMessage('Password changed successfully.');
      FocusScope.of(context).unfocus();
      _formKey.currentState?.reset();
      setState(() {
        _formKey = GlobalKey<FormState>();
        _resetToken = null;
        otpController.clear();
        newPassController.clear();
        confirmPassController.clear();
        showNewPassValidation = false;
        showConfirmValidation = false;
        hasLower = false;
        hasUpper = false;
        hasNumber = false;
        isMatch = false;
        isLoading = false;
      });
    } on ApiException catch (e) {
      setState(() => isLoading = false);
      _showMessage(e.message);
    } catch (e) {
      setState(() => isLoading = false);
      _showMessage('Network error. Please try again.');
    }
  }

  void _showMessage(String msg) {
    showAppMessage(context, msg);
  }

  Widget _buildRule(String text, bool valid) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          Icon(
            valid ? Icons.check : Icons.cancel_outlined,
            color: valid ? Colors.green : Colors.red,
            size: 18,
          ),
          SizedBox(width: 8),
          Text(
            text,
            style: GoogleFonts.poppins(
              fontSize: 13,
              color: valid ? Colors.green : Colors.red,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      bottomNavigationBar: const AppBottomNav(
        activeTab: AppBottomNavTab.more,
        activeMoreItem: AppMoreItem.changePassword,
      ),
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: app_color,
        elevation: 6,
        iconTheme: const IconThemeData(color: Colors.white),
        automaticallyImplyLeading: true,
        centerTitle: true,

        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(bottom: Radius.circular(20)),
        ),

        title: Text(
          "Change Password",
          style: GoogleFonts.poppins(
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: Colors.white,
          ),
        ),
      ),

      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              // 🔐 Top Icon
              Container(
                padding: EdgeInsets.all(16),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: app_color.withOpacity(0.1),
                ),
                child: Icon(Icons.lock_outline, size: 32, color: app_color),
              ),

              SizedBox(height: 16),

              Text(
                "Update Your Password",
                style: GoogleFonts.poppins(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                ),
              ),

              SizedBox(height: 6),

              Text(
                "Make sure your new password is strong and secure",
                textAlign: TextAlign.center,
                style: GoogleFonts.poppins(
                  fontSize: 13,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),

              SizedBox(height: 25),

              // 🔥 THIS IS THE MAGIC PART
              Expanded(
                child: Container(
                  padding: EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: Theme.of(context).cardColor,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black12,
                        blurRadius: 12,
                        offset: Offset(0, 6),
                      ),
                    ],
                  ),

                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // 👇 Wrap fields in scroll (only fields scroll)
                        Expanded(
                          child: SingleChildScrollView(
                            child: Column(
                              children: [
                                // tally-oauth has no "change with current
                                // password" endpoint - only this OTP-based
                                // reset flow. Step 1: request an OTP; the
                                // rest of the form (OTP + new/confirm
                                // password) only appears once it's sent.
                                if (_resetToken == null) ...[
                                  Text(
                                    "We'll send a one-time code to $_username to verify it's you.",
                                    textAlign: TextAlign.center,
                                    style: GoogleFonts.poppins(
                                      fontSize: 13,
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                  SizedBox(height: 15),
                                ],

                                if (_resetToken != null) ...[
                                  _modernField(
                                    "One-Time Code",
                                    otpController,
                                    Icons.pin_outlined,
                                    isOtpVisible,
                                    validator: (value) {
                                      if (value == null || value.isEmpty) {
                                        return "OTP required";
                                      }
                                      return null;
                                    },
                                    () {
                                      setState(() {
                                        isOtpVisible = !isOtpVisible;
                                      });
                                    },
                                  ),
                                  SizedBox(height: 15),
                                ],

                                if (_resetToken != null) ...[
                                _modernField(
                                  "New Password",
                                  newPassController,
                                  Icons.lock_reset,
                                  isNewPassVisible,
                                  () {
                                    setState(
                                      () =>
                                          isNewPassVisible = !isNewPassVisible,
                                    );
                                  },
                                  onChanged: validateNewPassword,
                                  validator: (value) {
                                    if (value == null || value.isEmpty) {
                                      return "New Password required";
                                    }
                                    if (value.length < 5) {
                                      return "Password must be greater than 4 characters";
                                    }
                                    if (!hasLower || !hasUpper || !hasNumber) {
                                      return "Password must meet all requirements";
                                    }

                                    /* if (!RegExp(r'[a-z]').hasMatch(value)) {
                                      return "Must contain lowercase letter";
                                    }
                                    if (!RegExp(r'[A-Z]').hasMatch(value)) {
                                      return "Must contain uppercase letter";
                                    }
                                    if (!RegExp(r'[0-9]').hasMatch(value)) {
                                      return "Must contain number";
                                    }*/
                                    return null;
                                  },
                                ),

                                if (showNewPassValidation) ...[
                                  SizedBox(height: 8),
                                  _buildRule("1 lowercase letter", hasLower),
                                  _buildRule("1 uppercase letter", hasUpper),
                                  _buildRule("1 number", hasNumber),
                                ],

                                SizedBox(height: 15),

                                _modernField(
                                  "Confirm Password",
                                  confirmPassController,
                                  Icons.check_circle_outline,
                                  isConfirmPassVisible,
                                  () {
                                    setState(
                                      () => isConfirmPassVisible =
                                          !isConfirmPassVisible,
                                    );
                                  },
                                  validator: (value) {
                                    if (value == null || value.isEmpty) {
                                      return "Confirm your password";
                                    }
                                    if (value.length < 5) {
                                      return "Password must be greater than 4 characters";
                                    }
                                    if (value != newPassController.text) {
                                      return "Passwords do not match";
                                    }
                                    return null;
                                  },
                                ),

                                if (showConfirmValidation && !isMatch) ...[
                                  SizedBox(height: 8),
                                  Row(
                                    children: [
                                      Icon(
                                        Icons.cancel,
                                        color: Colors.red,
                                        size: 18,
                                      ),
                                      SizedBox(width: 8),
                                      Text(
                                        "Passwords do not match",
                                        style: GoogleFonts.poppins(
                                          fontSize: 13,
                                          color: Colors.red,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],

                                if (showConfirmValidation && isMatch) ...[
                                  SizedBox(height: 8),
                                  Row(
                                    children: [
                                      Icon(
                                        Icons.check_circle,
                                        color: Colors.green,
                                        size: 18,
                                      ),
                                      SizedBox(width: 8),
                                      Text(
                                        "Passwords Matched",
                                        style: GoogleFonts.poppins(
                                          fontSize: 13,
                                          color: Colors.green,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                                ], // end _resetToken != null

                                SizedBox(height: 15),

                                // 🔥 BUTTON ALWAYS AT BOTTOM INSIDE CARD
                                SizedBox(
                                  width: double.infinity,
                                  child: GestureDetector(
                                    onTap: isLoading
                                        ? null
                                        : (_resetToken == null)
                                            ? _handleSendOtp
                                            : handleChangePassword,
                                    child: Container(
                                      margin: EdgeInsets.only(top: 20),
                                      padding: EdgeInsets.symmetric(
                                        vertical: 15,
                                      ),
                                      decoration: BoxDecoration(
                                        gradient: LinearGradient(
                                          colors: [
                                            app_color,
                                            app_color.withOpacity(0.8),
                                          ],
                                        ),
                                        borderRadius: BorderRadius.circular(14),
                                        boxShadow: [
                                          BoxShadow(
                                            color: app_color.withOpacity(0.4),
                                            blurRadius: 10,
                                            offset: Offset(0, 5),
                                          ),
                                        ],
                                      ),
                                      child: Center(
                                        child: isLoading
                                            ? SizedBox(
                                                height: 22,
                                                width: 22,
                                                child: Platform.isIOS
                                                    ? CupertinoTheme(
                                                        data: const CupertinoThemeData(
                                                          brightness: Brightness
                                                              .dark, // 🔥 forces white spinner
                                                        ),
                                                        child:
                                                            const CupertinoActivityIndicator(
                                                              radius: 11,
                                                            ),
                                                      )
                                                    : SizedBox(
                                                        height: 28,
                                                        width: 28,
                                                        child: CircularProgressIndicator(
                                                          strokeWidth: 3,
                                                          color: Colors.white,
                                                          backgroundColor: Colors
                                                              .white24, // 🔥 makes rotation visible
                                                        ),
                                                      ),
                                              )
                                            : Text(
                                                (_resetToken == null)
                                                    ? "Send OTP"
                                                    : "Update Password",
                                                style: GoogleFonts.poppins(
                                                  color: Colors.white,
                                                  fontWeight: FontWeight.w600,
                                                  fontSize: 15,
                                                ),
                                              ),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
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
