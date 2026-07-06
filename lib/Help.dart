import 'package:flutter/material.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'constants.dart';
import 'package:FincoreGo/widgets/app_bottom_nav.dart';
import 'package:FincoreGo/widgets/app_navigation.dart';

class Help extends StatefulWidget {
  final bool showBottomNavigation;

  const Help({Key? key, this.showBottomNavigation = true}) : super(key: key);

  @override
  _HelpPageState createState() => _HelpPageState();
}

class _HelpPageState extends State<Help> with TickerProviderStateMixin {
  bool isDashEnable = true,
      isRolesVisible = true,
      isUserEnable = true,
      isUserVisible = true,
      isRolesEnable = false,
      isVisibleNoRoleFound = false;

  String rolename_fetched = "";

  final TextEditingController _textEditingController = TextEditingController();

  bool isLengthErrorVisible = false;

  String name = "", email = "";

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

  void launchMapSearch(String query) async {
    final url =
        'https://www.google.com/maps/search/?api=1&query=${Uri.encodeComponent(query)}';

    await launch(url);
  }

  Future<void> _initSharedPreferences() async {
    prefs = await SharedPreferences.getInstance();

    String? email_nav = prefs.getString('email_nav');
    String? name_nav = prefs.getString('name_nav');

    if (email_nav != null && name_nav != null) {
      name = name_nav;
      email = email_nav;
    }
  }

  _launchPhone(String phoneNumber) async {
    String url = 'tel:$phoneNumber';
    if (await canLaunch(url)) {
      await launch(url);
    } else {
      Fluttertoast.showToast(
        msg: 'Could not launch $url. Kindly dial manually',
      );
      throw 'Could not launch $url';
    }
  }

  void sendEmail() async {
    final String subject =
        'Fincore Go App Support'; // Replace with your desired subject
    final String recipientEmail =
        'saadan@ca-eim.com'; // Replace with your desired recipient email
    // final List<String> ccEmails = ["praveen@ca-eim.com"];
    final String nameAndEmail = 'Name: $name\nEmail: $email\n\n';
    final String additionalText = _textEditingController.text;

    final Uri emailUri = Uri(
      scheme: 'mailto',
      path: recipientEmail,
      queryParameters: {
        'subject': subject,
        'body': '$nameAndEmail$additionalText',
        //'cc': ccEmails.join(','),
      },
    );

    if (await canLaunchUrl(emailUri)) {
      await launchUrl(emailUri);
    } else {
      Fluttertoast.showToast(msg: 'Could not open email app');
    }
  }

  @override
  void initState() {
    super.initState();
    _scaffoldMessengerKey = GlobalKey<ScaffoldMessengerState>();
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
                      // Location
                      GestureDetector(
                        onTap: () {
                          launchMapSearch(
                            'Chaturvedi Software House LLC, Dubai',
                          );
                        },
                        child: Row(
                          children: [
                            Icon(Icons.location_on_rounded, color: app_color),
                            const SizedBox(width: 10),
                            Flexible(
                              child: Text(
                                "513 Al Khaleej Centre, Bur Dubai, Dubai U.A.E",
                                style: GoogleFonts.poppins(
                                  fontSize: 14,
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onSurface,
                                  decoration: TextDecoration.underline,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 16),

                      // Phone
                      GestureDetector(
                        onTap: () {
                          _launchPhone("+97143258361");
                        },
                        child: Row(
                          children: [
                            Icon(Icons.call_rounded, color: app_color),
                            const SizedBox(width: 10),
                            Text(
                              "+971-43258361",
                              style: GoogleFonts.poppins(
                                fontSize: 14,
                                color: Theme.of(context).colorScheme.onSurface,
                                decoration: TextDecoration.underline,
                              ),
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 16),

                      // Email
                      Row(
                        children: [
                          Icon(Icons.email_outlined, color: app_color),
                          const SizedBox(width: 10),
                          Text(
                            "saadan@ca-eim.com",
                            style: GoogleFonts.poppins(
                              fontSize: 14,
                              color: Theme.of(context).colorScheme.onSurface,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

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
                    icon: const Icon(Icons.send_rounded),
                    label: Text(
                      'Send',
                      style: GoogleFonts.poppins(fontWeight: FontWeight.w600),
                    ),
                    onPressed: () {
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
