import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'constants.dart';
import 'package:FincoreGo/widgets/app_bottom_nav.dart';
import 'widgets/entry_widgets.dart';
import 'providers/change_password_notifier.dart';

class ChangePassword extends ConsumerStatefulWidget {
  @override
  ConsumerState<ChangePassword> createState() => _ChangePasswordScreenState();
}

class _ChangePasswordScreenState extends ConsumerState<ChangePassword> {
  final newPassController = TextEditingController();
  final confirmPassController = TextEditingController();
  final otpController = TextEditingController();

  dynamic _formKey = GlobalKey<FormState>();

  void validateNewPassword(String value) {
    ref
        .read(changePasswordNotifierProvider.notifier)
        .validateNewPassword(value, confirmPassController.text);
  }

  void validateConfirmPassword(String value) {
    ref
        .read(changePasswordNotifierProvider.notifier)
        .validateConfirmPassword(value, newPassController.text);
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
    final result =
        await ref.read(changePasswordNotifierProvider.notifier).sendOtp();
    if (!mounted) return;
    _showMessage(result.message);
  }

  /// Step 2 of the tally-oauth OTP flow - the "Update Password" button's
  /// tally-oauth path once an OTP has been requested.
  Future<void> _handleConfirmReset() async {
    if (!_formKey.currentState!.validate()) return;

    final result = await ref
        .read(changePasswordNotifierProvider.notifier)
        .confirmReset(otp: otpController.text, newPassword: newPassController.text);
    if (!mounted) return;
    _showMessage(result.message);
    if (result.success) {
      FocusScope.of(context).unfocus();
      _formKey.currentState?.reset();
      setState(() {
        _formKey = GlobalKey<FormState>();
        otpController.clear();
        newPassController.clear();
        confirmPassController.clear();
      });
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
    final vm = ref.watch(changePasswordNotifierProvider);
    final notifier = ref.read(changePasswordNotifierProvider.notifier);
    final username = vm.username;
    final resetToken = vm.resetToken;
    final isOtpVisible = vm.isOtpVisible;
    final isNewPassVisible = vm.isNewPassVisible;
    final isConfirmPassVisible = vm.isConfirmPassVisible;
    final showNewPassValidation = vm.showNewPassValidation;
    final showConfirmValidation = vm.showConfirmValidation;
    final hasLower = vm.hasLower;
    final hasUpper = vm.hasUpper;
    final hasNumber = vm.hasNumber;
    final isMatch = vm.isMatch;
    final isLoading = vm.isLoading;
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
                                if (resetToken == null) ...[
                                  Text(
                                    "We'll send a one-time code to $username to verify it's you.",
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

                                if (resetToken != null) ...[
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
                                    notifier.toggleOtpVisible,
                                  ),
                                  SizedBox(height: 15),
                                ],

                                if (resetToken != null) ...[
                                _modernField(
                                  "New Password",
                                  newPassController,
                                  Icons.lock_reset,
                                  isNewPassVisible,
                                  notifier.toggleNewPassVisible,
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
                                  notifier.toggleConfirmPassVisible,
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
                                ], // end resetToken != null

                                SizedBox(height: 15),

                                // 🔥 BUTTON ALWAYS AT BOTTOM INSIDE CARD
                                SizedBox(
                                  width: double.infinity,
                                  child: GestureDetector(
                                    onTap: isLoading
                                        ? null
                                        : (resetToken == null)
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
                                                (resetToken == null)
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
