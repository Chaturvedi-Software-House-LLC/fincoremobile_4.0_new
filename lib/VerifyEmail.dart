import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:pin_code_fields/pin_code_fields.dart';

import 'constants.dart';
import 'providers/verify_email_notifier.dart';
import 'widgets/entry_widgets.dart';

/// Opened from Dashboard.dart's "verify your email" banner (shown whenever
/// the signed-in account has an email on file that isn't verified yet -
/// see `DashboardState.isEmailVerified`). Login itself no longer blocks on
/// this (it used to redirect here instead of reaching the dashboard at
/// all - see Login.dart's `_proceedToCompanySelection`, which now always
/// runs unconditionally); verifying is a soft prompt the account can defer
/// indefinitely, not a gate. Pops back to the dashboard with `true` on
/// success so it can dismiss the banner immediately without a fresh login.
class VerifyEmail extends ConsumerStatefulWidget {
  const VerifyEmail({super.key, required this.email});

  final String email;

  @override
  ConsumerState<VerifyEmail> createState() => _VerifyEmailState();
}

class _VerifyEmailState extends ConsumerState<VerifyEmail> {
  final _otpController = TextEditingController();
  bool _codeSent = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _sendCode());
  }

  @override
  void dispose() {
    _otpController.dispose();
    super.dispose();
  }

  Future<void> _sendCode() async {
    final error = await ref.read(verifyEmailNotifierProvider.notifier).sendCode();
    if (!mounted) return;
    if (error != null) {
      showAppMessage(context, error);
      return;
    }
    setState(() => _codeSent = true);
  }

  Future<void> _verify(String otp) async {
    if (otp.length != 6) {
      showAppMessage(context, 'Please enter the 6-digit code');
      return;
    }
    final error = await ref.read(verifyEmailNotifierProvider.notifier).verify(otp);
    if (!mounted) return;
    if (error != null) {
      showAppMessage(context, error);
      // PinCodeTextField only reacts to a controller `.clear()` once the
      // field has actually rebuilt with `enabled: true` again (see
      // Login.dart's `_clearOtpFieldAfterRebuild` doc comment) - clearing
      // in the same frame as the `isVerifying: false` state flip leaves
      // the boxes showing the wrong digits with backspace not working.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _otpController.clear();
      });
      return;
    }
    if (!mounted) return;
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(verifyEmailNotifierProvider);

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: app_color,
        elevation: 6,
        iconTheme: const IconThemeData(color: Colors.white),
        centerTitle: true,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(bottom: Radius.circular(20)),
        ),
        leading: BackButton(onPressed: () => Navigator.of(context).pop(false)),
        title: Text(
          'Verify Email',
          style: GoogleFonts.poppins(
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: Colors.white,
          ),
        ),
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: app_color.withOpacity(0.1),
                  ),
                  child: Icon(
                    Icons.mark_email_read_rounded,
                    size: 32,
                    color: app_color,
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  'Verify your email',
                  style: GoogleFonts.poppins(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  _codeSent
                      ? 'Enter the 6-digit code sent to ${widget.email} to continue.'
                      : 'Sending a verification code to ${widget.email}...',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.poppins(
                    fontSize: 13,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 28),
                LayoutBuilder(
                  builder: (context, constraints) => PinCodeTextField(
                    appContext: context,
                    controller: _otpController,
                    length: 6,
                    enabled: _codeSent && !state.isVerifying,
                    animationType: AnimationType.fade,
                    onChanged: (_) {},
                    onCompleted: _verify,
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
                    // _otpController is disposed by this State's own
                    // dispose() - pin_code_fields defaults to disposing the
                    // controller itself when the field unmounts, which
                    // would double-dispose it (child widgets are torn down
                    // before the parent State's dispose() runs).
                    autoDisposeControllers: false,
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
                    ),
                    onPressed: (_codeSent && !state.isVerifying)
                        ? () => _verify(_otpController.text.trim())
                        : null,
                    child: state.isVerifying
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : Text(
                            'Verify',
                            style: GoogleFonts.poppins(fontWeight: FontWeight.w600),
                          ),
                  ),
                ),
                const SizedBox(height: 12),
                TextButton(
                  onPressed: state.isSending ? null : _sendCode,
                  child: Text(
                    'Resend code',
                    style: GoogleFonts.poppins(
                      color: app_color,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                // Verifying is a deferrable prompt, not a gate (see this
                // screen's class doc-comment) - the back arrow already
                // allows leaving, but it's easy to miss up in the AppBar
                // next to a big "Verify" button and code-entry field, so
                // "Skip for now" makes that explicit instead of relying on
                // the user to notice the back arrow is tappable.
                TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: Text(
                    'Skip for now',
                    style: GoogleFonts.poppins(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
