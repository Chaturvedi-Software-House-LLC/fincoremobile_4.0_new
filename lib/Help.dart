import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:mailer/mailer.dart';
import 'package:mailer/smtp_server.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'constants.dart';
import 'package:FincoreGo/AssistantChat.dart';
import 'package:FincoreGo/widgets/app_bottom_nav.dart';
import 'package:FincoreGo/widgets/app_navigation.dart';
import 'widgets/entry_widgets.dart';
import 'utils/support_email_template.dart';

class Help extends StatefulWidget {
  final bool showBottomNavigation;

  const Help({Key? key, this.showBottomNavigation = true}) : super(key: key);

  @override
  _HelpPageState createState() => _HelpPageState();
}

class _MapPatternPainter extends CustomPainter {
  final Color lineColor;

  const _MapPatternPainter({required this.lineColor});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = lineColor
      ..strokeWidth = 1.4
      ..style = PaintingStyle.stroke;

    for (double y = 24; y < size.height; y += 36) {
      final path = Path()
        ..moveTo(0, y)
        ..quadraticBezierTo(size.width * 0.25, y - 18, size.width * 0.5, y)
        ..quadraticBezierTo(size.width * 0.75, y + 18, size.width, y);
      canvas.drawPath(path, paint);
    }

    for (double x = 28; x < size.width; x += 54) {
      final path = Path()
        ..moveTo(x, 0)
        ..quadraticBezierTo(x + 16, size.height * 0.3, x - 4, size.height * 0.6)
        ..quadraticBezierTo(x - 18, size.height * 0.82, x + 8, size.height);
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _MapPatternPainter oldDelegate) {
    return oldDelegate.lineColor != lineColor;
  }
}

class _HelpPageState extends State<Help> with TickerProviderStateMixin {
  static const String _officeMapQuery =
      'Chaturvedi Software House LLC, 513 Al Khaleej Centre, Bur Dubai, Dubai';

  bool isDashEnable = true,
      isRolesVisible = true,
      isUserEnable = true,
      isUserVisible = true,
      isRolesEnable = false,
      isVisibleNoRoleFound = false;

  String rolename_fetched = "";

  final TextEditingController _textEditingController = TextEditingController();

  bool isLengthErrorVisible = false;
  bool _isSendingSupportMessage = false;

  String name = "", email = "";

  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  late SharedPreferences prefs;

  String? hostname = "",
      company = "",
      company_lowercase = "",
      serial_no = "",
      license_expiry,
      username = "",
      HttpURL = "",
      SecuritybtnAcessHolder = "";

  Future<void> launchMapSearch(String query) async {
    final uri = Uri.parse(
      'https://www.google.com/maps/search/?api=1&query=${Uri.encodeComponent(query)}',
    );

    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      showAppMessage(context, 'Could not open Google Maps');
    }
  }

  Future<void> _initSharedPreferences() async {
    prefs = await SharedPreferences.getInstance();

    String? email_nav = prefs.getString('email_nav');
    String? name_nav = prefs.getString('name_nav');

    if (email_nav != null && name_nav != null) {
      name = name_nav;
      email = email_nav;
    }

    serial_no = prefs.getString('serial_no');
    license_expiry = prefs.getString('license_expiry');
  }

  /// Formats the raw "YYYYMMDD" license_expiry string the same way
  /// Dashboard.dart does, for display in the support email. Falls back to
  /// the raw value if it isn't in the expected format rather than throwing.
  String _formattedLicenseExpiry() {
    final raw = license_expiry;
    if (raw == null || raw.isEmpty) return 'Not available';
    try {
      return DateFormat('dd-MMM-yyyy').format(DateTime.parse(raw));
    } catch (_) {
      return raw;
    }
  }

  _launchPhone(String phoneNumber) async {
    String url = 'tel:$phoneNumber';
    if (await canLaunch(url)) {
      await launch(url);
    } else {
      showAppMessage(context, 'Could not launch $url. Kindly dial manually');
      throw 'Could not launch $url';
    }
  }

  static const String _supportEmailAddress = 'saadan@ca-eim.com';

  Future<void> launchSupportEmail() async {
    final Uri emailUri = Uri(
      scheme: 'mailto',
      path: _supportEmailAddress,
      queryParameters: {'subject': 'Fincore Go App Support'},
    );

    if (await canLaunchUrl(emailUri)) {
      await launchUrl(emailUri);
    } else {
      // No mailto handler available (e.g. no Mail account configured on
      // this device) - falling back to a dead-end error isn't useful here,
      // since (unlike the message form above) there's no message content to
      // send on the user's behalf. Copy the address instead so they can
      // paste it into whatever email app they actually use. This is a
      // successful outcome for the user, not a failure - shown as such
      // (green, not red) rather than framed as an error.
      await Clipboard.setData(const ClipboardData(text: _supportEmailAddress));
      if (!mounted) return;
      showAppMessage(
        context,
        'Copied $_supportEmailAddress to your clipboard.',
        isError: false,
      );
    }
  }

  // Sends the support message directly via SMTP (same pattern used by the
  // AI Assistant's "Contact Support Team" card and the password-reset email
  // in Login.dart) rather than handing off to a mailto: link. Relying on the
  // device's Mail app was unreliable in practice - canLaunchUrl(mailto:) can
  // return false on real devices with no Mail account configured, which is
  // outside the app's control and not something a plist/manifest fix can
  // work around. Sending the email ourselves removes that dependency
  // entirely.
  Future<void> sendEmail() async {
    final String additionalText = _textEditingController.text;

    setState(() => _isSendingSupportMessage = true);
    try {
      final smtpServer = SmtpServer(
        'smtp.hostinger.com',
        username: 'noreply@fincoreerp.com',
        password: '^QLNlsU8m',
        port: 465,
        ssl: true,
      );

      final message = Message()
        ..from = Address('noreply@fincoreerp.com', 'Fincore Go App')
        ..recipients.add('saadan@ca-eim.com')
        ..subject = 'Fincore Go App Support'
        ..html = buildSupportEmailHtml(
          title: 'New Support Request',
          subtitle: "Submitted from the Fincore Go app's Help screen",
          details: [
            MapEntry('Name', name),
            MapEntry('Email', email),
            MapEntry(
              'Serial No',
              serial_no?.isNotEmpty == true ? serial_no! : 'Not available',
            ),
            MapEntry('License Expiry', _formattedLicenseExpiry()),
          ],
          message: additionalText,
        );

      await send(message, smtpServer);
      if (!mounted) return;
      _textEditingController.clear();
      showAppMessage(
        context,
        'Message sent - our team will get back to you shortly.',
        isError: false,
      );
    } catch (e) {
      if (!mounted) return;
      showAppMessage(context, 'Could not send your message. Please try again.');
    } finally {
      if (mounted) setState(() => _isSendingSupportMessage = false);
    }
  }

  static const List<Color> _liveChatGradient = [
    Color(0xFF6D5BFF),
    Color(0xFF00C2CB),
  ];

  Widget _buildLiveChatCard() {
    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const AssistantChat()),
      ),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: _liveChatGradient,
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(
              color: _liveChatGradient.last.withValues(alpha: 0.35),
              blurRadius: 14,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.2),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.auto_awesome_rounded,
                color: Colors.white,
                size: 24,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        'Live Chat',
                        style: GoogleFonts.poppins(
                          fontSize: 15.5,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 7,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.22),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.auto_awesome_rounded,
                              color: Colors.white,
                              size: 11,
                            ),
                            const SizedBox(width: 3),
                            Text(
                              'Powered by AI',
                              style: GoogleFonts.poppins(
                                fontSize: 9,
                                fontWeight: FontWeight.w600,
                                color: Colors.white,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                    'Get instant answers about using Fincore Go',
                    style: GoogleFonts.poppins(
                      fontSize: 12,
                      color: Colors.white.withValues(alpha: 0.9),
                    ),
                  ),
                ],
              ),
            ),
            const Icon(
              Icons.arrow_forward_ios_rounded,
              color: Colors.white,
              size: 16,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGoogleLocationCard() {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;

    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: () => launchMapSearch(_officeMapQuery),
      child: Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Theme.of(context).dividerColor),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(isDark ? 0.18 : 0.05),
              blurRadius: 12,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              height: 150,
              width: double.infinity,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: isDark
                      ? [const Color(0xFF102525), const Color(0xFF121A2A)]
                      : [app_color.withOpacity(0.12), const Color(0xFFEAF7F4)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              child: Stack(
                children: [
                  Positioned.fill(
                    child: CustomPaint(
                      painter: _MapPatternPainter(
                        lineColor: isDark
                            ? Colors.white.withOpacity(0.06)
                            : app_color.withOpacity(0.12),
                      ),
                    ),
                  ),
                  Center(
                    child: Container(
                      height: 62,
                      width: 62,
                      decoration: BoxDecoration(
                        color: app_color,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: app_color.withOpacity(0.32),
                            blurRadius: 18,
                            offset: const Offset(0, 8),
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.location_on_rounded,
                        color: Colors.white,
                        size: 34,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.business_rounded, color: app_color),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Chaturvedi Software House LLC',
                          style: GoogleFonts.poppins(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: Theme.of(context).colorScheme.onSurface,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '513 Al Khaleej Centre, Bur Dubai, Dubai U.A.E',
                    style: GoogleFonts.poppins(
                      fontSize: 13,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 14),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () => launchMapSearch(_officeMapQuery),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: app_color,
                        side: BorderSide(color: app_color.withOpacity(0.45)),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      icon: const Icon(Icons.map_outlined),
                      label: Text(
                        'Open in Google Maps',
                        style: GoogleFonts.poppins(fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    _initSharedPreferences();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      bottomNavigationBar: widget.showBottomNavigation
          ? const AppBottomNav(
              activeTab: AppBottomNavTab.more,
              activeMoreItem: AppMoreItem.help,
            )
          : null,
      key: _scaffoldKey,
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: PreferredSize(
        preferredSize: Size.fromHeight(50),
        child: AppBar(
          backgroundColor: app_color,
          elevation: 6,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(bottom: Radius.circular(20)),
          ),
          automaticallyImplyLeading: false,
          leading: IconButton(
            icon: Icon(Icons.arrow_back, color: Colors.white),
            onPressed: () {
              if (!widget.showBottomNavigation && Navigator.canPop(context)) {
                Navigator.pop(context);
                return;
              }

              AppNavigation.backOrDashboard(context);
            },
          ),
          centerTitle: true,
          title: GestureDetector(
            onTap: () {},
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: Text(
                    "Help",
                    style: GoogleFonts.poppins(
                      fontSize: 20,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),

      body: Stack(
        children: [
          SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Modern header
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 20,
                  ),
                  width: MediaQuery.of(context).size.width,
                  decoration: BoxDecoration(
                    color: Theme.of(context).cardColor,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black12.withOpacity(0.05),
                        blurRadius: 12,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.support_agent_rounded,
                        size: 48,
                        color: app_color,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        "Help & Support",
                        style: GoogleFonts.poppins(
                          fontSize: 20,
                          fontWeight: FontWeight.w600,
                          color: Theme.of(context).colorScheme.onSurface,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        "Get in touch with our trusted support team.",
                        style: GoogleFonts.poppins(
                          fontSize: 13,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 14),
                _buildLiveChatCard(),

                const SizedBox(height: 14),
                // Contact Info Card
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 20,
                  ),
                  decoration: BoxDecoration(
                    color: Theme.of(context).cardColor,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black12.withOpacity(0.05),
                        blurRadius: 12,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: () => _launchPhone("+97143258361"),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: app_color,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 13),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            elevation: 0,
                          ),
                          icon: const Icon(Icons.call_rounded),
                          label: Text(
                            "Call Support  +971-43258361",
                            style: GoogleFonts.poppins(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),

                      const SizedBox(height: 16),

                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: launchSupportEmail,
                          style: OutlinedButton.styleFrom(
                            foregroundColor: app_color,
                            side: BorderSide(
                              color: app_color.withOpacity(0.45),
                            ),
                            padding: const EdgeInsets.symmetric(vertical: 13),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          icon: const Icon(Icons.email_outlined),
                          label: Text(
                            "Email Support  saadan@ca-eim.com",
                            style: GoogleFonts.poppins(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 14),

                _buildGoogleLocationCard(),

                const SizedBox(height: 24),

                // Message box with label
                Text(
                  "Message",
                  style: GoogleFonts.poppins(
                    fontWeight: FontWeight.w500,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _textEditingController,
                  decoration: InputDecoration(
                    hintText: "Type your message here...",
                    hintStyle: GoogleFonts.poppins(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                    filled: true,
                    fillColor: Colors.transparent,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(
                        color: Theme.of(context).dividerColor,
                      ),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(
                        color: Theme.of(context).dividerColor,
                      ),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: app_color, width: 1.5),
                    ),
                  ),
                  keyboardType: TextInputType.multiline,
                  maxLines: 5,
                  maxLength: 200,
                ),

                // Error message
                Visibility(
                  visible: isLengthErrorVisible,
                  child: Column(
                    children: [
                      const SizedBox(height: 8),
                      Text(
                        'Message must be greater than 10 characters',
                        style: GoogleFonts.poppins(
                          color: Colors.red,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 24),

                // Send button
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: app_color,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      elevation: 4,
                    ),
                    icon: _isSendingSupportMessage
                        ? const _LineSpinner(size: 18, color: Colors.white)
                        : const Icon(Icons.send_rounded),
                    label: Text(
                      _isSendingSupportMessage ? 'Sending...' : 'Send Message',
                      style: GoogleFonts.poppins(fontWeight: FontWeight.w600),
                    ),
                    onPressed: _isSendingSupportMessage
                        ? null
                        : () {
                            if (_textEditingController.text.length <= 10) {
                              setState(() {
                                isLengthErrorVisible = true;
                              });
                            } else {
                              setState(() {
                                isLengthErrorVisible = false;
                              });
                              sendEmail();
                            }
                          },
                  ),
                ),

                const SizedBox(height: 40),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// A small rotating "activity indicator" style spinner - a ring of short
/// radiating lines that fade around in a circle (the classic iOS/macOS
/// spinner look), rather than a single solid rotating arc. Used in place of
/// a plain `CircularProgressIndicator` for the Send button's loading state.
class _LineSpinner extends StatefulWidget {
  const _LineSpinner({required this.size, required this.color});

  final double size;
  final Color color;

  @override
  State<_LineSpinner> createState() => _LineSpinnerState();
}

class _LineSpinnerState extends State<_LineSpinner>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  static const int _lineCount = 12;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          return CustomPaint(
            painter: _LineSpinnerPainter(
              progress: _controller.value,
              color: widget.color,
              lineCount: _lineCount,
            ),
          );
        },
      ),
    );
  }
}

class _LineSpinnerPainter extends CustomPainter {
  _LineSpinnerPainter({
    required this.progress,
    required this.color,
    required this.lineCount,
  });

  final double progress;
  final Color color;
  final int lineCount;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final outerRadius = size.width / 2;
    final innerRadius = outerRadius * 0.45;
    final lineWidth = size.width * 0.11;

    for (int i = 0; i < lineCount; i++) {
      // Each line's opacity is offset by its position around the circle and
      // the current animation progress, so the faded "tail" appears to
      // chase around continuously.
      final fraction = ((i / lineCount) - progress) % 1.0;
      final opacity = (0.15 + 0.85 * fraction).clamp(0.15, 1.0);

      final angle = (i / lineCount) * 2 * math.pi;
      final paint = Paint()
        ..color = color.withOpacity(opacity)
        ..strokeWidth = lineWidth
        ..strokeCap = StrokeCap.round;

      final start = center + Offset(math.cos(angle), math.sin(angle)) * innerRadius;
      final end = center + Offset(math.cos(angle), math.sin(angle)) * outerRadius;
      canvas.drawLine(start, end, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _LineSpinnerPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.color != color ||
        oldDelegate.lineCount != lineCount;
  }
}
