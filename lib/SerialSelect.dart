import 'dart:convert';
import 'dart:io';
import 'dart:ui';
import 'package:FincoreGo/Dashboard.dart';
import 'package:FincoreGo/Login.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/material.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:progress_dialog_null_safe/progress_dialog_null_safe.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:socket_io_client/socket_io_client.dart' as IO;
import 'package:url_launcher/url_launcher.dart';
import 'constants.dart';
// import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class Serial {
  final String serial;
  final String role_id;
  final String license_expiry;
  final String hostname;
  final String token;

  Serial({
    required this.serial,
    required this.role_id,
    required this.license_expiry,
    required this.hostname,
    required this.token,
  });
}

class SerialSelect extends StatefulWidget {
  /// When true the screen skips rendering the selection UI and navigates
  /// straight to Dashboard as soon as the auto 1-serial-1-company check passes.
  final bool autoNavigate;
  const SerialSelect({Key? key, this.autoNavigate = false}) : super(key: key);

  @override
  _MyHomePageState createState() => _MyHomePageState();
}

class _MyHomePageState extends State<SerialSelect>
    with TickerProviderStateMixin {
  late String SalesDashHolder,
      ReceiptsDashHolder,
      PurchaseDashHolder,
      PaymentsDashHolder,
      OutstandingReceivablesDashHolder,
      OutstandingPayablesDashHolder,
      CashDashHolder,
      AllitemsHolder,
      InActiveitemsHolder,
      ActiveitemsHolder,
      RateHolder,
      AmountHolder,
      ItemSalesHolder,
      ItemPurchaseHolder,
      SalesPartyHolder,
      ReceiptPartyHolder,
      PurchasePartyHolder,
      PaymentPartyHolder,
      CreditNotePartyHolder,
      DebitNotePartyHolder,
      JournalPartyHolder,
      ReceivablePartyHolder,
      PayablePartyHolder,
      PendingSalesOrderPartyHolder,
      PartySuppliersHolder,
      PartyCustomersHolder,
      PendingPurchaseOrderPartyHolder,
      LedgerEntriesHolder,
      BillsEntriesHolder,
      InventoryEntriesHolder,
      CostCentreEntriesHolder,
      PostDatedTransactionsHolder,
      BarChartDashHolder,
      LineChartDashHolder,
      PieChartDashHolder,
      SalesEntryHolder,
      ReceiptEntryHolder,
      SalesOrderEntryHolder,
      VanAllocationHolder,
      DeliveryNoteEntryHolder;
  List<dynamic> myData = [];
  List<dynamic> myData_company = [];
  List<dynamic> myData_admin = [];
  List<dynamic> myData_role = [];

  // late FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin;

  bool isVisibleCompanyName = false;

  String socketId = ''; // To store the socket ID.
  String? deviceIdentifier = '';

  bool _showAllSerials = false;
  bool _showAllCompanies = false;

  late IO.Socket socket;
  String? username_prefs = '', password_prefs = '';

  late String lastsyncvalue = "Not Available";

  late TickerProvider tickerProvider;

  String? company;

  late GlobalKey<ScaffoldMessengerState> _scaffoldMessengerKey;

  late String admin_email = "", allowed_user = "";

  Map<String, Map<String, String>> companySyncInfo = {};

  bool _isVisibleCompany = false;
  dynamic _selectedserial, _selectcompany, _selectedadmin, _selectedrole;
  bool _isLoading = false;
  // True while we're silently attempting auto-navigate (1 serial + 1 company).
  // Flips to false if auto-navigate doesn't apply, revealing the normal UI.
  bool _silentMode = false;
  String serial_no = "",
      role_id = "",
      license_expiry = "",
      license_expiry_text = "",
      hostname = "",
      token = "";
  String secbtnaccess = "", company_name = "", startfrom = "", currency = "";
  late SharedPreferences prefs;

  /*void showNotification(int daysRemaining, String serial_no) async {
     const AndroidNotificationDetails androidPlatformChannelSpecifics =
     AndroidNotificationDetails(
       '2', // Channel ID
       'expiryChannel', // Channel name
       channelDescription: 'Notification channel for license expiry alerts',
       importance: Importance.max,
       priority: Priority.high,
       showWhen: false,
     );


     const DarwinNotificationDetails iosPlatformChannelSpecifics =
     DarwinNotificationDetails(); // ✅ updated for iOS/macOS

     const NotificationDetails platformChannelSpecifics = NotificationDetails(
       android: androidPlatformChannelSpecifics,
       iOS: iosPlatformChannelSpecifics,
     );

     await flutterLocalNotificationsPlugin.show(
       0, // notification ID
       'Fincore Go License Expiry Alert',
       '$serial_no license will expire in $daysRemaining days ($license_expiry_text)',
       platformChannelSpecifics,
       payload:
       'mailto:example@example.com?subject=License%20Expiry&body=My%20license%20is%20expiring%20soon.',
     );
   }*/

  Future<void> loadCompanySyncInfo() async {
    companySyncInfo.clear();

    for (final company in myData_company) {
      final companyName = company['company_name'].toString();

      final result = await getCompanyLastSync(context, companyName, serial_no);

      companySyncInfo[companyName] = result;
    }

    if (mounted) {
      setState(() {});
    }
  }

  void checkExpiryDate(String expiryDate, String serial_no) {
    final DateTime now = DateTime.now();
    final DateTime expiry = DateTime.parse(expiryDate);

    final int difference = expiry.difference(now).inDays;

    if (difference <= 60) {
      //showNotification(difference,serial_no);
    }
  }

  void showProgressDialog(BuildContext context, bool _isLoading) {
    ProgressDialog progressDialog;
    progressDialog = ProgressDialog(context, isDismissible: true);

    progressDialog.style(
      message: 'Processing your request...', // Message displayed in the dialog
      messageTextStyle: GoogleFonts.poppins(fontWeight: FontWeight.bold),
    );
    if (_isLoading) {
      progressDialog.show();
    } else {
      progressDialog.hide();
    }
  }

  void _showContinueDialog(
    BuildContext context,
    String company,
    String lastsync,
  ) {
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (BuildContext context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          backgroundColor: Theme.of(context).scaffoldBackgroundColor,
          titlePadding: EdgeInsets.fromLTRB(24, 24, 24, 8),
          contentPadding: EdgeInsets.fromLTRB(24, 8, 24, 0),
          actionsPadding: EdgeInsets.only(right: 16, bottom: 16),

          title: Row(
            children: [
              Icon(Icons.sync, color: app_color),
              SizedBox(width: 10),
              Text(
                "Sync Information",
                style: GoogleFonts.poppins(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
            ],
          ),

          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                "$company was last synced on $lastsync",
                style: GoogleFonts.poppins(
                  fontSize: 14.5,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
              SizedBox(height: 24), // <-- This adds space above the button
            ],
          ),

          actions: [
            ElevatedButton.icon(
              onPressed: () async {
                Map<String, dynamic> selected_data = _selectcompany;
                company_name = selected_data['company_name'] as String;
                startfrom = selected_data['startfrom'] as String;
                currency = selected_data['base_currency'].toString();

                prefs = await SharedPreferences.getInstance();
                prefs.setString("startfrom", startfrom);
                prefs.setString("company_name", normalizeCompany(company_name));
                prefs.setString("serial_no", serial_no);
                prefs.setString("base_currency", currency);

                if (secbtnaccess == "True") {
                  for (String key in [
                    "salesdash",
                    "purchasedash",
                    "barchartdash",
                    "linechartdash",
                    "piechartdash",
                    "salesentry",
                    "receiptentry",
                    "salesorderentry",
                    "outstandingreceivabledash",
                    "outstandingpayabledash",
                    "cashdash",
                    "receiptsdash",
                    "paymentsdash",
                    "allitems",
                    "activeitems",
                    "inactiveitems",
                    "rate",
                    "item_amount",
                    "item_sales",
                    "item_purchase",
                    "salesparty",
                    "purchaseparty",
                    "creditnoteparty",
                    "journalparty",
                    "payableparty",
                    "pendingpurchaseorderparty",
                    "receiptparty",
                    "paymentparty",
                    "debitnoteparty",
                    "receivableparty",
                    "pendingsalesorderparty",
                    "party_suppliers",
                    "party_customers",
                    "ledgerentries",
                    "inventoryentries",
                    "postdatedtransactions",
                    "billsentries",
                    "costcentreentries",
                    "vanallocation",
                    "deliverynoteentry",
                  ]) {
                    prefs.setString(key, "True");
                  }

                  Navigator.of(context).pop();
                  Navigator.pushReplacement(
                    context,
                    MaterialPageRoute(builder: (context) => Dashboard()),
                  );
                } else {
                  if (mounted) {
                    setState(() {
                      _isLoading = true;
                    });
                  }
                  getroledata(context, serial_no, role_id);
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: app_color,
                elevation: 3,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(30),
                ),
                padding: EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              ),
              icon: Icon(Icons.arrow_forward, color: Colors.white, size: 18),
              label: Text(
                "Continue",
                style: GoogleFonts.poppins(
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                  color: Colors.white,
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Color getExpiryColor(String expiryDate) {
    try {
      final now = DateTime.now();
      final expiry = DateTime.parse(expiryDate);
      final daysLeft = expiry.difference(now).inDays;

      if (daysLeft < 0) {
        return Colors.redAccent; // ❌ Expired
      } else if (daysLeft <= 30) {
        return Colors.orangeAccent; // ⚠️ Expiring soon
      } else {
        return Colors.white; // ✅ Valid
      }
    } catch (e) {
      return Colors.grey; // fallback color
    }
  }

  void _showExpiredLicenseDialog(
    BuildContext context,
    String serialNo,
    String expiryDate,
  ) {
    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: '',
      barrierColor: Colors.black.withOpacity(0.4),
      transitionDuration: const Duration(milliseconds: 400),
      pageBuilder: (context, anim1, anim2) => const SizedBox.shrink(),
      transitionBuilder: (context, anim1, anim2, child) {
        final curvedValue = Curves.easeOutBack.transform(anim1.value);
        return Transform.scale(
          scale: curvedValue,
          child: Opacity(
            opacity: anim1.value,
            child: AlertDialog(
              elevation: 12,
              backgroundColor: Theme.of(context).cardColor.withOpacity(0.9),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(24),
              ),
              contentPadding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
              insetPadding: const EdgeInsets.symmetric(horizontal: 24),
              titlePadding: EdgeInsets.zero,
              title: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  vertical: 16,
                  horizontal: 20,
                ),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Color(0xFFF83600), Color(0xFFFE8C00)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.warning_amber_rounded,
                      color: Colors.white,
                      size: 28,
                    ),
                    const SizedBox(width: 10),
                    Text(
                      "License Expired",
                      style: GoogleFonts.poppins(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              content: ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 6, sigmaY: 6),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 10),
                      Text(
                        "Your license for Serial No:",
                        style: GoogleFonts.poppins(
                          fontSize: 14.5,
                          color: Theme.of(context).colorScheme.onSurface,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          const Icon(
                            Icons.confirmation_number_outlined,
                            size: 18,
                            color: Colors.deepOrange,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            serialNo,
                            style: GoogleFonts.poppins(
                              fontWeight: FontWeight.w600,
                              fontSize: 15,
                              color: Theme.of(context).colorScheme.onSurface,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Text(
                        "Expired on:",
                        style: GoogleFonts.poppins(
                          fontSize: 14.5,
                          color: Theme.of(context).colorScheme.onSurface,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          const Icon(
                            Icons.calendar_month,
                            size: 18,
                            color: Colors.redAccent,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            DateFormat(
                              'dd-MMM-yyyy',
                            ).format(DateTime.parse(expiryDate)),
                            style: GoogleFonts.poppins(
                              fontWeight: FontWeight.w600,
                              fontSize: 15,
                              color: Colors.redAccent,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 18),
                      Divider(thickness: 1, color: Colors.grey.shade300),
                      const SizedBox(height: 12),
                      Text(
                        "Your license has expired. To renew your access, please contact our support team below:",
                        style: GoogleFonts.poppins(
                          fontSize: 14.5,
                          color: Theme.of(context).colorScheme.onSurface,
                        ),
                      ),
                      const SizedBox(height: 16),

                      // ✅ Modern chips for contact options
                      Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: [
                          // 📧 Email Chip
                          InkWell(
                            borderRadius: BorderRadius.circular(30),
                            onTap: () async {
                              final Uri emailUri = Uri(
                                scheme: 'mailto',
                                path: 'saadan@ca-eim.com',
                                query:
                                    'subject=License%20Renewal%20Request&body=Dear%20CSH%20LLC%20Support,%0A%0AMy%20license%20for%20Serial%20No%20$serialNo%20expired%20on%20$expiryDate.%20Please%20assist%20with%20renewal.%0A%0ARegards,',
                              );

                              if (await canLaunchUrl(emailUri)) {
                                await launchUrl(emailUri);
                              }
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 10,
                              ),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(30),
                                border: Border.all(
                                  width: 1.3,
                                  color: Colors.teal.shade400,
                                ),
                                gradient: LinearGradient(
                                  colors: [
                                    Colors.teal.withOpacity(0.05),
                                    Colors.teal.withOpacity(0.1),
                                  ],
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(
                                    Icons.email_outlined,
                                    size: 18,
                                    color: Colors.teal,
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    "saadan@ca-eim.com",
                                    style: GoogleFonts.poppins(
                                      fontSize: 13.5,
                                      color: Colors.teal.shade800,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),

                          // 🌐 Website Chip
                          InkWell(
                            borderRadius: BorderRadius.circular(30),
                            onTap: () async {
                              const url = "https://cshllc.ae/contact-us/";
                              if (await canLaunchUrl(Uri.parse(url))) {
                                await launchUrl(
                                  Uri.parse(url),
                                  mode: LaunchMode.externalApplication,
                                );
                              }
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 10,
                              ),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(30),
                                border: Border.all(
                                  width: 1.3,
                                  color: Colors.deepPurple.shade400,
                                ),
                                gradient: LinearGradient(
                                  colors: [
                                    Colors.deepPurple.withOpacity(0.05),
                                    Colors.deepPurple.withOpacity(0.1),
                                  ],
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(
                                    Icons.language_rounded,
                                    size: 18,
                                    color: Colors.deepPurple,
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    "cshllc.ae/contact-us",
                                    style: GoogleFonts.poppins(
                                      fontSize: 13.5,
                                      color: Colors.deepPurple.shade800,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 26),
                      Align(
                        alignment: Alignment.center,
                        child: ElevatedButton.icon(
                          onPressed: () => Navigator.pop(context),
                          icon: const Icon(
                            Icons.check_circle_outline,
                            color: Colors.white,
                          ),
                          label: Text(
                            "Got it",
                            style: GoogleFonts.poppins(
                              fontWeight: FontWeight.w500,
                              fontSize: 15,
                              color: Colors.white,
                            ),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: app_color,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(30),
                            ),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 30,
                              vertical: 12,
                            ),
                          ),
                        ),
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
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _getDeviceIdentifier();
  }

  /*Future<String> getCompanyLastSync (BuildContext context,  String company, String serial) async {

     setState(() {
       _isLoading = true;
     });

           DateTime now = DateTime.now();

           // Get the timezone offset
           Duration offset = now.timeZoneOffset;

           // Format the offset in "+HH:mm" format
           String formattedTimeZone = '${offset.isNegative ? '-' : '+'}'
               '${offset.inHours.abs().toString().padLeft(2, '0')}:'
               '${(offset.inMinutes % 60).abs().toString().padLeft(2, '0')}';
      try
      {
        final url = Uri.parse("$hostname/api/main/$company/$serial");
        Map<String,String> headers = {
          'Authorization' : 'Bearer $token',
          "Content-Type": "application/json"
        };



        final response = await http.get(
            url,
            headers:headers
        );

        if (response.statusCode == 200)
        {
          Map<String, dynamic> jsonMap = jsonDecode(response.body);

          // Extract the "lastSync" value
          String lastSyncString = jsonMap['lastSync'];

          String trn = jsonMap['trn'];


          // Define the input format of the "lastSync" string
          DateFormat inputFormat = DateFormat('yyyy-MM-dd hh:mm:ss a');

          // Parse the "lastSync" string into a DateTime object
          DateTime lastSync;
          try {
            lastSync = inputFormat.parse(lastSyncString);
          } catch (e) {
            print('Error parsing date: $e');
            return "";
          }
          String formattedLastSync =
          DateFormat('dd-MMM-yyyy hh:mm a').format(lastSync);
          setState(() {
            company_name = _selectcompany['company_name'].toString();
            lastsyncvalue = formattedLastSync;
          });
        }
        else
        {
          setState(() {
            lastsyncvalue = "Not Available";
            isVisibleCompanyName = false;
          });
        }
      }
      catch (e)
      {
        setState(()
        {
               lastsyncvalue = "Not Available";
               isVisibleCompanyName = false;
        });
             print(e);
           }
     setState(() {
       _isLoading = false;
     });
     return lastsyncvalue;
   }*/

  String normalizeCompany(String value) {
    value = value.trim();

    // 1. Remove trailing dot (e.g. "L.L.C." → "L.L.C")
    value = value.replaceAll(RegExp(r'\.$'), '');

    return value;
  }

  Future<Map<String, String>> getCompanyLastSync(
    BuildContext context,
    String company,
    String serial,
  ) async {
    setState(() {
      _isLoading = true;
    });

    final fixedCompany = normalizeCompany(company);

    try {
      final url = Uri.parse("$hostname/api/main/$fixedCompany/$serial");
      Map<String, String> headers = {
        'Authorization': 'Bearer $token',
        "Content-Type": "application/json",
      };

      final response = await http.get(url, headers: headers);

      if (response.statusCode == 200) {
        Map<String, dynamic> jsonMap = jsonDecode(response.body);

        debugPrint('company sync -> $jsonMap');
        // Extract the "lastSync" and "trn" values
        String lastSyncString = jsonMap['lastSync'];
        String trn = jsonMap['trn'].toString();
        String address = jsonMap['address'].toString();
        String emirate = jsonMap['state'].toString();
        String country = jsonMap['country'].toString();

        // Define the input format of the "lastSync" string
        DateFormat inputFormat = DateFormat('yyyy-MM-dd hh:mm:ss a');

        // Parse the "lastSync" string into a DateTime object
        DateTime lastSync;
        try {
          lastSync = inputFormat.parse(lastSyncString);
        } catch (e) {
          print('Error parsing date: $e');
          return {
            "lastSync": "",
            "trn": "",
            "address": "",
            "emirate": "",
            "country": "",
          };
        }

        String formattedLastSync = DateFormat(
          'dd-MMM-yyyy hh:mm a',
        ).format(lastSync);

        // Update UI elements if needed
        setState(() {
          company_name = normalizeCompany(
            _selectcompany['company_name'].toString(),
          );
          lastsyncvalue = formattedLastSync;
        });

        // Return both "lastSync" and "trn"
        return {
          "lastSync": formattedLastSync,
          "trn": trn,
          "address": address,
          "emirate": emirate,
          "country": country,
        };
      } else {
        setState(() {
          lastsyncvalue = "Not Available";
          isVisibleCompanyName = false;
        });
        return {
          "lastSync": "Not Available",
          "trn": "Not Available",
          "address": "Not Available",
          "emirate": "Not Available",
          "country": "Not Available",
        };
      }
    } catch (e) {
      setState(() {
        lastsyncvalue = "Not Available";
        isVisibleCompanyName = false;
      });
      print(e);
      return {
        "lastSync": "Not Available",
        "trn": "Not Available",
        "address": "Not Available",
        "emirate": "Not Available",
        "country": "Not Available",
      };
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _getDeviceIdentifier() async {
    DeviceInfoPlugin deviceInfo = DeviceInfoPlugin();
    String? identifier = '';

    try {
      if (Theme.of(context).platform == TargetPlatform.android) {
        final androidInfo = await deviceInfo.androidInfo;
        identifier = androidInfo.id; // ✅ use 'id' instead of 'androidId'
      } else if (Theme.of(context).platform == TargetPlatform.iOS) {
        final iosInfo = await deviceInfo.iosInfo;
        identifier = iosInfo.identifierForVendor; // ✅ same key in iOS
      }
    } catch (e) {
      debugPrint('Error getting device identifier: $e');
    }
    setState(() {
      deviceIdentifier = identifier;
    });
  }

  Future<void> _showConfirmationDialogAndNavigate(BuildContext context) async {
    await showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (context) {
        return Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          backgroundColor: Theme.of(context).scaffoldBackgroundColor,
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 32,
            vertical: 24,
          ),
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // 🔹 Header Icon
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: app_color.withOpacity(0.1),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.logout_rounded,
                    size: 40,
                    color: app_color,
                  ),
                ),
                const SizedBox(height: 18),

                // 📝 Title
                Text(
                  'Logout Confirmation',
                  style: GoogleFonts.poppins(
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                  textAlign: TextAlign.center,
                ),

                const SizedBox(height: 10),

                // 💬 Message
                Text(
                  'Are you sure you want to log out of your account?',
                  style: GoogleFonts.poppins(
                    fontSize: 14.5,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                  textAlign: TextAlign.center,
                ),

                const SizedBox(height: 28),

                // 🔘 Action Buttons
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    // ❌ Cancel Button
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.of(context).pop(),
                        style: OutlinedButton.styleFrom(
                          side: BorderSide(color: app_color),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                        child: Text(
                          'Cancel',
                          style: GoogleFonts.poppins(
                            color: app_color,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),

                    // ✅ Logout Button
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () async {
                          final prefs = await SharedPreferences.getInstance();
                          await prefs.clear();

                          final jsonPayload = {
                            'username': username_prefs,
                            'password': password_prefs,
                            'macId': deviceIdentifier,
                          };

                          Navigator.of(context).pop();
                          emitDeleteMyId(jsonPayload, () {
                            Navigator.pushReplacement(
                              context,
                              MaterialPageRoute(
                                builder: (_) =>
                                    Login(username: '', password: ''),
                              ),
                            );
                          });
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: app_color,
                          elevation: 2,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                        child: Text(
                          'Logout',
                          style: GoogleFonts.poppins(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
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
                  style: GoogleFonts.poppins(
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
                  style: GoogleFonts.poppins(
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

  void emitDeleteMyId(Map<String, dynamic> jsonPayload, Function() onComplete) {
    socket.emit('deleteMyId', jsonPayload);

    if (onComplete != null) {
      onComplete();
    }
  }

  Future<void> _initSharedPreferences() async {
    prefs = await SharedPreferences.getInstance();

    username_prefs = prefs.getString('username');
    password_prefs = prefs.getString('password');

    await prefs.remove('company_name');
    await prefs.remove('serial_no');
    await prefs.remove('datetype');
    await prefs.remove('startdate');
    await prefs.remove('enddate');
    await prefs.remove('name_nav');
    await prefs.remove('email_nav');
    await prefs.remove('sort');

    // flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();

    tickerProvider = this;

    fetchSerial();
  }

  Widget _buildProgressOverlay() {
    if (!_isLoading) return const SizedBox.shrink();

    return Positioned.fill(
      child: AbsorbPointer(
        absorbing: true,
        child: Container(
          color: Colors.black.withOpacity(0.25),
          child: Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 22),
              decoration: BoxDecoration(
                color: Theme.of(context).cardColor,
                borderRadius: BorderRadius.circular(22),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.12),
                    blurRadius: 18,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AppLogoLoader(),
                  const SizedBox(height: 16),
                  Text(
                    "Please wait...",
                    style: GoogleFonts.poppins(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    _scaffoldMessengerKey = GlobalKey<ScaffoldMessengerState>();
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
    socket.connect();

    _silentMode = widget.autoNavigate;
    _initSharedPreferences();
  }

  @override
  Widget build(BuildContext context) {
    // While silently attempting auto-navigate show a plain loading screen.
    // _silentMode flips to false if auto-navigate doesn't apply.
    if (_silentMode) {
      return Scaffold(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const AppLogoLoader(size: 80),
              const SizedBox(height: 20),
              Text(
                'Signing in…',
                style: GoogleFonts.poppins(
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return WillPopScope(
      child: Scaffold(
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
            leading: null,
            centerTitle: true,
            actions: [
              IconButton(
                icon: Icon(Icons.logout, color: Colors.white),
                onPressed: () {
                  _showConfirmationDialogAndNavigate(context);
                },
              ),
              SizedBox(width: 5),
            ],
            title: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: Text(
                    "Fincore Go",
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

        body: Stack(
          children: [
            SingleChildScrollView(
              child: Container(
                height: MediaQuery.of(context).size.height,
                width: MediaQuery.of(context).size.width,
                child: Align(
                  alignment: Alignment.topLeft,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _buildInfoHeader(),

                              const SizedBox(height: 18),

                              _buildSectionHeader(
                                title: "Serial Numbers",
                                count: myData.length,
                                icon: Icons.confirmation_number_outlined,
                              ),

                              const SizedBox(height: 10),

                              _buildSerialList(),

                              const SizedBox(height: 22),

                              if (_isVisibleCompany) ...[
                                _buildSectionHeader(
                                  title: "Companies",
                                  count: myData_company.length,
                                  icon: Icons.business_rounded,
                                ),

                                const SizedBox(height: 10),

                                _buildCompanyList(),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            _buildProgressOverlay(),
          ],
        ),
      ),
      onWillPop: () async {
        _showConfirmationDialogAndExit(context);
        return true;
      },
    );
  }

  Widget _buildInfoHeader() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: app_color.withOpacity(0.06),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: app_color.withOpacity(0.12)),
      ),
      child: Row(
        children: [
          Container(
            height: 44,
            width: 44,
            decoration: BoxDecoration(
              color: app_color.withOpacity(0.12),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(Icons.person_outline_rounded, color: app_color),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  admin_email.isEmpty ? "Account" : admin_email,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.poppins(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w600,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  "Users Allowed: $allowed_user",
                  style: GoogleFonts.poppins(
                    fontSize: 12.5,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader({
    required String title,
    required int count,
    required IconData icon,
  }) {
    return Row(
      children: [
        Icon(icon, size: 18, color: app_color),
        const SizedBox(width: 8),
        Text(
          title,
          style: GoogleFonts.poppins(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: Theme.of(context).colorScheme.onSurface,
          ),
        ),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: app_color.withOpacity(0.08),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            "$count",
            style: GoogleFonts.poppins(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: app_color,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSerialList() {
    final visibleSerials = _showAllSerials ? myData : myData.take(3).toList();

    return Column(
      children: [
        ...visibleSerials.map((item) {
          final bool isSelected = item == _selectedserial;
          final serialText = item['serial_no']?.toString() ?? '';

          final bool isDark = Theme.of(context).brightness == Brightness.dark;
          final Color unselectedBorder = isDark
              ? Theme.of(context).dividerColor.withOpacity(0.55)
              : Colors.grey.shade300;
          final Color unselectedBackground = isDark
              ? Theme.of(context).cardColor.withOpacity(0.38)
              : Colors.white;
          final Color unselectedIconBackground = isDark
              ? Theme.of(context).scaffoldBackgroundColor.withOpacity(0.5)
              : Colors.grey.shade50;

          return InkWell(
            borderRadius: BorderRadius.circular(18),
            onTap: () async {
              await _selectSerialItem(item);
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 220),
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: isSelected
                    ? app_color.withOpacity(isDark ? 0.14 : 0.08)
                    : unselectedBackground,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                  color: isSelected ? app_color : unselectedBorder,
                  width: isSelected ? 1.5 : 1,
                ),
              ),
              child: Row(
                children: [
                  Container(
                    height: 38,
                    width: 38,
                    decoration: BoxDecoration(
                      color: isSelected ? app_color : unselectedIconBackground,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: isSelected ? app_color : unselectedBorder,
                      ),
                    ),
                    child: Icon(
                      Icons.qr_code_2_rounded,
                      size: 20,
                      color: isSelected
                          ? Colors.white
                          : Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      serialText,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.poppins(
                        fontSize: 14,
                        fontWeight: isSelected
                            ? FontWeight.w700
                            : FontWeight.w500,
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                    ),
                  ),
                  if (isSelected)
                    Icon(
                      Icons.check_circle_rounded,
                      color: app_color,
                      size: 21,
                    ),
                ],
              ),
            ),
          );
        }).toList(),

        if (myData.length > 3)
          _buildViewMoreButton(
            expanded: _showAllSerials,
            onTap: () {
              setState(() {
                _showAllSerials = !_showAllSerials;
              });
            },
          ),
      ],
    );
  }

  Widget _buildCompanyList() {
    final visibleCompanies = _showAllCompanies
        ? myData_company
        : myData_company.take(3).toList();

    return Column(
      children: [
        ...visibleCompanies.map((item) {
          final companyName = item['company_name']?.toString() ?? '';
          final firstLetters = companyName.length >= 2
              ? companyName.substring(0, 2).toUpperCase()
              : companyName.toUpperCase();

          /*final syncData = companySyncInfo[companyName];
           final lastSync = syncData?['lastSync'] ?? "Loading...";
           final trn = syncData?['trn'] ?? "";*/

          return InkWell(
            borderRadius: BorderRadius.circular(18),
            onTap: () async {
              await _continueWithCompanyDirect(item);
            },
            child: Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Theme.of(context).cardColor,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: Theme.of(context).dividerColor),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,

                children: [
                  Container(
                    height: 42,
                    width: 42,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: app_color.withOpacity(0.09),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Text(
                      firstLetters,
                      style: GoogleFonts.poppins(
                        color: app_color,
                        fontWeight: FontWeight.w700,
                        fontSize: 12,
                      ),
                    ),
                  ),

                  const SizedBox(width: 12),

                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          companyName,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.poppins(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w700,
                            color: Theme.of(context).colorScheme.onSurface,
                          ),
                        ),

                        /*const SizedBox(height: 8),

                         Row(
                           children: [
                             Icon(
                               Icons.sync_rounded,
                               size: 15,
                               color: lastSync == "Loading..."
                                   ? Colors.orange
                                   : Colors.green,
                             ),
                             const SizedBox(width: 5),
                             Expanded(
                               child: Text(
                                 "Last Sync: $lastSync",
                                 maxLines: 1,
                                 overflow: TextOverflow.ellipsis,
                                 style: GoogleFonts.poppins(
                                   fontSize: 11.5,
                                   fontWeight: FontWeight.w500,
                                   color: Theme.of(context).colorScheme.onSurfaceVariant,
                                 ),
                               ),
                             ),
                           ],
                         ),*/

                        /*if (trn.isNotEmpty &&
                             trn != "Not Available" &&
                             trn != "null") ...[
                           const SizedBox(height: 5),
                           Row(
                             children: [
                               Icon(
                                 Icons.receipt_long_outlined,
                                 size: 14,
                                 color: Theme.of(context).colorScheme.onSurfaceVariant,
                               ),
                               const SizedBox(width: 5),
                               Expanded(
                                 child: Text(
                                   "TRN: $trn",
                                   maxLines: 1,
                                   overflow: TextOverflow.ellipsis,
                                   style: GoogleFonts.poppins(
                                     fontSize: 11.3,
                                     fontWeight: FontWeight.w500,
                                     color: Theme.of(context).colorScheme.onSurfaceVariant,
                                   ),
                                 ),
                               ),
                             ],
                           ),
                         ],*/
                      ],
                    ),
                  ),

                  const SizedBox(width: 8),

                  Icon(
                    Icons.arrow_forward_ios_rounded,
                    size: 15,
                    color: app_color,
                  ),
                ],
              ),
            ),
          );
        }).toList(),

        if (myData_company.length > 3)
          _buildViewMoreButton(
            expanded: _showAllCompanies,
            onTap: () {
              setState(() {
                _showAllCompanies = !_showAllCompanies;
              });
            },
          ),
      ],
    );
  }

  Future<void> _selectSerialItem(dynamic value) async {
    setState(() {
      _selectedserial = value;
      _showAllCompanies = false;

      if (_selectedserial['spectra_allocations'] != null) {
        prefs.setString(
          'spectra_allocations',
          jsonEncode(_selectedserial['spectra_allocations']),
        );
      } else {
        prefs.remove('spectra_allocations');
      }

      _isLoading = true;
    });

    Map<String, dynamic> selectedData = _selectedserial;

    serial_no = selectedData['serial_no'] as String;
    role_id = selectedData['role_id'].toString();
    hostname = selectedData['website_url'] as String;
    token = selectedData['token'].toString();

    secbtnaccess = role_id == "0" ? "True" : "False";

    prefs.setString("hostname", hostname);
    prefs.setString("secbtnaccess", secbtnaccess);
    prefs.setString("serial_no", serial_no);

    await getadmindata(serial_no);
  }

  Future<void> _continueWithCompanyDirect(dynamic companyItem) async {
    _selectcompany = companyItem;

    final companyName = _selectcompany['company_name'].toString();

    final syncData =
        companySyncInfo[companyName] ??
        await getCompanyLastSync(context, companyName, serial_no);

    startfrom = _selectcompany['startfrom'].toString();
    currency = _selectcompany['base_currency'].toString();

    prefs.setString("company_name", normalizeCompany(companyName));
    prefs.setString("startfrom", startfrom);
    prefs.setString("serial_no", serial_no);
    prefs.setString("base_currency", currency);

    prefs.setString("company_trn", syncData['trn'] ?? "");
    prefs.setString("company_address", syncData['address'] ?? "");
    prefs.setString("company_emirate", syncData['emirate'] ?? "");
    prefs.setString("company_country", syncData['country'] ?? "");

    if (secbtnaccess == "True") {
      for (String key in [
        "salesdash",
        "purchasedash",
        "barchartdash",
        "linechartdash",
        "piechartdash",
        "salesentry",
        "receiptentry",
        "salesorderentry",
        "outstandingreceivabledash",
        "outstandingpayabledash",
        "cashdash",
        "receiptsdash",
        "paymentsdash",
        "allitems",
        "activeitems",
        "inactiveitems",
        "rate",
        "item_amount",
        "item_sales",
        "item_purchase",
        "salesparty",
        "purchaseparty",
        "creditnoteparty",
        "journalparty",
        "payableparty",
        "pendingpurchaseorderparty",
        "receiptparty",
        "paymentparty",
        "debitnoteparty",
        "receivableparty",
        "pendingsalesorderparty",
        "party_suppliers",
        "party_customers",
        "ledgerentries",
        "inventoryentries",
        "postdatedtransactions",
        "billsentries",
        "costcentreentries",
        "vanallocation",
        "deliverynoteentry",
      ]) {
        prefs.setString(key, "True");
      }

      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => Dashboard()),
      );
    } else {
      await getroledata(context, serial_no, role_id);
    }
  }

  Widget _buildViewMoreButton({
    required bool expanded,
    required VoidCallback onTap,
  }) {
    return Align(
      alignment: Alignment.center,
      child: TextButton.icon(
        onPressed: onTap,
        icon: Icon(
          expanded
              ? Icons.keyboard_arrow_up_rounded
              : Icons.keyboard_arrow_down_rounded,
          color: app_color,
        ),
        label: Text(
          expanded ? "View less" : "View more",
          style: GoogleFonts.poppins(
            color: app_color,
            fontWeight: FontWeight.w600,
            fontSize: 13,
          ),
        ),
      ),
    );
  }

  Future<void> fetchSerial() async {
    prefs = await SharedPreferences.getInstance();
    String? jsonString = prefs.getString('login_list');
    if (jsonString != null) {
      setState(() {
        myData = jsonDecode(jsonString);
        _selectedserial = myData.first;

        print('serial -> $_selectedserial');
      });

      Map<String, dynamic> selected_data = _selectedserial;

      // ✅ Save spectra allocations if available
      if (_selectedserial['spectra_allocations'] != null) {
        prefs.setString(
          'spectra_allocations',
          jsonEncode(_selectedserial['spectra_allocations']),
        );

        print(
          'spectra allocations -> ${prefs.getString('spectra_allocations')}',
        );
      } else {
        prefs.remove('spectra_allocations');
      }

      serial_no = selected_data['serial_no'] as String;
      role_id = selected_data['role_id'].toString();
      hostname = selected_data['website_url'] as String;
      token = selected_data['token'].toString();

      if (role_id == "0") {
        secbtnaccess = "True";
      } else {
        secbtnaccess = "False";
      }
      prefs = await SharedPreferences.getInstance();

      prefs.setString("hostname", hostname);
      prefs.setString("secbtnaccess", secbtnaccess);

      setState(() {
        _isLoading = true;
      });

      await getadmindata(serial_no);
    }
  }

  Future<void> getroledata(
    BuildContext context,
    String serialno,
    String roleid,
  ) async {
    setState(() {
      _isLoading = true;
    });
    final url = Uri.parse('$BASE_URL_config/api/roles/get');

    Map<String, String> headers = {
      'Authorization': 'Bearer $authTokenBase',
      "Content-Type": "application/json",
    };

    var body = jsonEncode({'serialno': serialno, 'roleid': roleid});

    final response = await http.post(url, body: body, headers: headers);

    if (response.statusCode == 200) {
      final role_data = jsonDecode(response.body);
      if (role_data != null) {
        if (mounted) {
          setState(() {
            myData_role = role_data;
            _selectedrole = myData_role;
          });
        } else {
          myData_role = role_data;
          _selectedrole = myData_role;
        }
        SalesDashHolder = _selectedrole[0]["isSaleDash"];
        BarChartDashHolder = _selectedrole[0]["isBarChartDash"];
        LineChartDashHolder = _selectedrole[0]["isLineChartDash"];
        PieChartDashHolder = _selectedrole[0]["isPieChartDash"];
        SalesEntryHolder = _selectedrole[0]["isSalesEntry"];
        ReceiptEntryHolder = _selectedrole[0]["isReceiptsEntry"];
        SalesOrderEntryHolder = _selectedrole[0]["isSalesOrderEntry"];

        ReceiptsDashHolder = _selectedrole[0]["isReceiptsDash"];
        PurchaseDashHolder = _selectedrole[0]["isPurchaseDash"];
        PaymentsDashHolder = _selectedrole[0]["isPaymentsDash"];
        OutstandingReceivablesDashHolder =
            _selectedrole[0]["isOutstandingReceivableDash"];
        OutstandingPayablesDashHolder =
            _selectedrole[0]["isOutstandingPayableDash"];
        CashDashHolder = _selectedrole[0]["isCashDash"];
        AllitemsHolder = _selectedrole[0]["isAllItems"];
        InActiveitemsHolder = _selectedrole[0]["isInactiveItems"];
        ActiveitemsHolder = _selectedrole[0]["isActiveItems"];
        RateHolder = _selectedrole[0]["isRate"];
        AmountHolder = _selectedrole[0]["isItemAmount"];
        ItemSalesHolder = _selectedrole[0]["isItemSales"];
        ItemPurchaseHolder = _selectedrole[0]["isItemPurchase"];
        SalesPartyHolder = _selectedrole[0]["isSalesParty"];
        ReceiptPartyHolder = _selectedrole[0]["isReceiptParty"];
        PurchasePartyHolder = _selectedrole[0]["isPurchaseParty"];
        PaymentPartyHolder = _selectedrole[0]["isPaymentParty"];
        CreditNotePartyHolder = _selectedrole[0]["isCreditNoteParty"];
        DebitNotePartyHolder = _selectedrole[0]["isDebitNoteParty"];
        JournalPartyHolder = _selectedrole[0]["isJournalParty"];
        ReceivablePartyHolder = _selectedrole[0]["isReceivableParty"];
        PayablePartyHolder = _selectedrole[0]["isPayableParty"];
        PendingSalesOrderPartyHolder =
            _selectedrole[0]["isPendingSalesOrderParty"];
        PendingPurchaseOrderPartyHolder =
            _selectedrole[0]["isPendingPurchaseOrderParty"];
        PartySuppliersHolder = _selectedrole[0]["isParty_Suppliers"];
        PartyCustomersHolder = _selectedrole[0]["isParty_Customers"];
        LedgerEntriesHolder = _selectedrole[0]["isLedgerEntries"];
        BillsEntriesHolder = _selectedrole[0]["isBillsEntries"];
        InventoryEntriesHolder = _selectedrole[0]["isInventoryEntries"];
        CostCentreEntriesHolder = _selectedrole[0]["isCostCentreEntries"];
        PostDatedTransactionsHolder =
            _selectedrole[0]["isPostDatedTransactions"] ?? "True";

        VanAllocationHolder =
            _selectedrole[0]["isVanAllocationSetup"] ?? "True";
        DeliveryNoteEntryHolder =
            _selectedrole[0]["isDeliveryNoteEntry"] ?? "True";

        prefs.setString("vanallocation", VanAllocationHolder);
        prefs.setString("deliverynoteentry", DeliveryNoteEntryHolder);

        prefs.setString(
          "settings_currency",
          _selectedrole[0]["is_Settings_Currency"] ?? "False",
        );
        prefs.setString(
          "settings_amtdecimals",
          _selectedrole[0]["is_Settings_AmtDecimals"] ?? "False",
        );
        prefs.setString(
          "settings_vatperc",
          _selectedrole[0]["is_Settings_VatPerc"] ?? "False",
        );
        prefs.setString(
          "settings_inactivepdays",
          _selectedrole[0]["is_Settings_InactivePDays"] ?? "False",
        );
        prefs.setString(
          "settings_sorttype",
          _selectedrole[0]["is_Settings_SortType"] ?? "False",
        );
        prefs.setString(
          "settings_defdaterange",
          _selectedrole[0]["is_Settings_DefDateRange"] ?? "False",
        );
        prefs.setString(
          "settings_ageingconfig",
          _selectedrole[0]["is_Settings_AgeingCnfig"] ?? "False",
        );
        prefs.setString(
          "settings_fastslowinactiveitem",
          _selectedrole[0]["is_Settings_FastSlowInactiveItem"] ?? "False",
        );

        prefs.setString("salesdash", SalesDashHolder);
        prefs.setString("purchasedash", PurchaseDashHolder);
        prefs.setString("barchartdash", BarChartDashHolder);
        prefs.setString("linechartdash", LineChartDashHolder);
        prefs.setString("piechartdash", PieChartDashHolder);
        prefs.setString("salesentry", SalesEntryHolder);
        prefs.setString("receiptentry", ReceiptEntryHolder);
        prefs.setString("salesorderentry", SalesOrderEntryHolder);
        prefs.setString(
          "outstandingreceivabledash",
          OutstandingReceivablesDashHolder,
        );
        prefs.setString(
          "outstandingpayabledash",
          OutstandingPayablesDashHolder,
        );
        prefs.setString("cashdash", CashDashHolder);
        prefs.setString("receiptsdash", ReceiptsDashHolder);
        prefs.setString("paymentsdash", PaymentsDashHolder);
        prefs.setString("allitems", AllitemsHolder);
        prefs.setString("activeitems", ActiveitemsHolder);
        prefs.setString("inactiveitems", InActiveitemsHolder);
        prefs.setString("rate", RateHolder);
        prefs.setString("item_amount", AmountHolder);
        prefs.setString("item_sales", ItemSalesHolder);
        prefs.setString("item_purchase", ItemPurchaseHolder);
        prefs.setString("salesparty", SalesPartyHolder);
        prefs.setString("purchaseparty", PurchasePartyHolder);
        prefs.setString("creditnoteparty", CreditNotePartyHolder);
        prefs.setString("journalparty", JournalPartyHolder);
        prefs.setString("payableparty", PayablePartyHolder);
        prefs.setString(
          "pendingpurchaseorderparty",
          PendingPurchaseOrderPartyHolder,
        );
        prefs.setString("receiptparty", ReceiptPartyHolder);
        prefs.setString("paymentparty", PaymentPartyHolder);
        prefs.setString("debitnoteparty", DebitNotePartyHolder);
        prefs.setString("receivableparty", ReceivablePartyHolder);
        prefs.setString("pendingsalesorderparty", PendingSalesOrderPartyHolder);
        prefs.setString("party_suppliers", PartySuppliersHolder);
        prefs.setString("party_customers", PartyCustomersHolder);
        prefs.setString("ledgerentries", LedgerEntriesHolder);
        prefs.setString("inventoryentries", InventoryEntriesHolder);
        prefs.setString("postdatedtransactions", PostDatedTransactionsHolder);
        prefs.setString("billsentries", BillsEntriesHolder);
        prefs.setString("costcentreentries", CostCentreEntriesHolder);

        /*Fluttertoast.showToast(
          msg: "Auto-login to $company_name (Serial: $serial_no)",
          backgroundColor: Theme.of(context).colorScheme.onSurface,
          textColor: Colors.white,
          fontSize: 14.0,
        );*/

        // ✅ Fade transition to Dashboard
        if (mounted) {
          Navigator.of(context).pushReplacement(
            PageRouteBuilder(
              transitionDuration: const Duration(milliseconds: 700),
              pageBuilder: (context, animation, secondaryAnimation) =>
                  const Dashboard(),
              transitionsBuilder:
                  (context, animation, secondaryAnimation, child) {
                    return FadeTransition(opacity: animation, child: child);
                  },
            ),
          );
        }
      } else {
        throw Exception('Failed to fetch data');
      }
    } else {
      Map<String, dynamic> data = json.decode(response.body);
      String error = '';

      if (data.containsKey('error')) {
        setState(() {
          error = data['error'];
        });
      } else {
        error = 'Something went wrong!!!';
      }

      Fluttertoast.showToast(msg: error);
    }

    setState(() {
      _isLoading = false;
    });
  }

  Future<void> getadmindata(String selectedserial) async {
    setState(() {
      _isLoading = true;
    });
    final url = Uri.parse('$BASE_URL_config/api/admin/getConfig');

    Map<String, String> headers = {
      'Authorization': 'Bearer $authTokenBase',
      "Content-Type": "application/json",
    };

    var body = jsonEncode({'serialno': selectedserial});

    final response = await http.post(url, body: body, headers: headers);

    if (response.statusCode == 200) {
      final admin_data = jsonDecode(response.body);
      if (admin_data != null) {
        myData_admin = admin_data;
        _selectedadmin = myData_admin;
        admin_email = _selectedadmin[0]['email'];
        allowed_user = _selectedadmin[0]['allowed_user'].toString();
        if (allowed_user != null || allowed_user != "null") {
          int allowed_userr = 0;
          allowed_userr = int.parse(allowed_user);
          allowed_userr += 1;

          allowed_user = "$allowed_userr";
        } else {
          allowed_user = "0";
        }
        license_expiry = _selectedadmin[0]['license_expiry'].toString();

        if (license_expiry != "null" || license_expiry != "") {
          DateTime today = DateTime.now();
          DateTime expiry = DateTime.parse(license_expiry);

          DateTime todayDate = DateTime(today.year, today.month, today.day);
          DateTime expiryDate = DateTime(expiry.year, expiry.month, expiry.day);

          if (token != null &&
              token != "" &&
              token.isNotEmpty &&
              token != 'null') // checking if token is not empty
          {
            myData_company.clear();
            prefs.setString("token", token);

            if (!todayDate.isAfter(expiryDate)) {
              await fetchAllowedCompany(serial_no, username_prefs!);

              DateTime dt1 = DateTime.parse(license_expiry);
              license_expiry_text = DateFormat('dd-MMM-yyyy').format(dt1);
              checkExpiryDate(license_expiry, serial_no);
            } else {
              _showExpiredLicenseDialog(context, serial_no, license_expiry);

              setState(() {
                _isVisibleCompany = false;
                _isLoading = false;
              });
            }

            DateTime dt1 = DateTime.parse(license_expiry);
            license_expiry_text = DateFormat('dd-MMM-yyyy').format(dt1);
            prefs.setString("license_expiry", license_expiry);
          } else {
            setState(() {
              _isVisibleCompany = false;
              _isLoading = false;
            });
            prefs.remove(
              "token",
            ); // removing token from internal memory incase token is empty, null or not available
            Fluttertoast.showToast(
              msg: 'Authorization Error. Contact your administrator',
            );
          }
        }
      } else {
        throw Exception('Failed to fetch data');
      }
    } else {
      Map<String, dynamic> data = json.decode(response.body);
      String error = '';

      if (data.containsKey('error')) {
        setState(() {
          error = data['error'];
        });
      } else {
        error = 'Something went wrong!!!';
      }

      Fluttertoast.showToast(msg: error);
      setState(() {
        _isVisibleCompany = false;
      });
    }

    setState(() {
      _isLoading = false;
    });
  }

  Future<void> fetchCompany(String selectedserial) async {
    setState(() {
      _isLoading = true;
    });

    final url = Uri.parse('$BASE_URL_config/api/admin/getCompany');

    Map<String, String> headers = {
      'Authorization': 'Bearer $authTokenBase',
      "Content-Type": "application/json",
    };

    var body = jsonEncode({'serialno': selectedserial});
    final response = await http.post(url, body: body, headers: headers);

    myData_company.clear();
    if (response.statusCode == 200) {
      final company_data = jsonDecode(response.body);

      debugPrint('company_data -> $company_data');
      if (company_data != null) {
        setState(() {
          _isVisibleCompany = true;
          myData_company = company_data;

          _selectcompany = myData_company.first;
        });
        // await loadCompanySyncInfo();

        // ✅ Auto-navigate when single serial + single company
        if (myData.length == 1 && myData_company.length == 1) {
          final company_name = myData_company.first['company_name'].toString();
          startfrom = myData_company.first['startfrom'].toString();
          currency = myData_company.first['base_currency'].toString();

          Map<String, String> result = await getCompanyLastSync(
            context,
            company_name,
            serial_no,
          );

          prefs.setString("company_name", normalizeCompany(company_name));
          prefs.setString("startfrom", startfrom);
          prefs.setString("serial_no", serial_no);
          prefs.setString("base_currency", currency);
          prefs.setString("company_trn", result['trn'] ?? "");
          prefs.setString("company_address", result['address'] ?? "");
          prefs.setString("company_emirate", result['emirate'] ?? "");
          prefs.setString("company_country", result['country'] ?? "");

          if (secbtnaccess == "True") {
            for (String key in [
              "salesdash",
              "purchasedash",
              "barchartdash",
              "linechartdash",
              "piechartdash",
              "salesentry",
              "receiptentry",
              "salesorderentry",
              "outstandingreceivabledash",
              "outstandingpayabledash",
              "cashdash",
              "receiptsdash",
              "paymentsdash",
              "allitems",
              "activeitems",
              "inactiveitems",
              "rate",
              "item_amount",
              "item_sales",
              "item_purchase",
              "salesparty",
              "purchaseparty",
              "creditnoteparty",
              "journalparty",
              "payableparty",
              "pendingpurchaseorderparty",
              "receiptparty",
              "paymentparty",
              "debitnoteparty",
              "receivableparty",
              "pendingsalesorderparty",
              "party_suppliers",
              "party_customers",
              "ledgerentries",
              "inventoryentries",
              "postdatedtransactions",
              "billsentries",
              "costcentreentries",
              "vanallocation",
              "deliverynoteentry",
              "settings_currency",
              "settings_amtdecimals",
              "settings_vatperc",
              "settings_inactivepdays",
              "settings_sorttype",
              "settings_defdaterange",
              "settings_ageingconfig",
              "settings_fastslowinactiveitem",
            ]) {
              prefs.setString(key, "True");
            }

            // ✅ Fade transition to Dashboard
            if (mounted) {
              Navigator.of(context).pushReplacement(
                PageRouteBuilder(
                  transitionDuration: const Duration(milliseconds: 700),
                  pageBuilder: (context, animation, secondaryAnimation) =>
                      const Dashboard(),
                  transitionsBuilder:
                      (context, animation, secondaryAnimation, child) {
                        return FadeTransition(opacity: animation, child: child);
                      },
                ),
              );
            }
          } else {
            if (mounted) {
              setState(() {
                _isLoading = true;
              });
            }
            await getroledata(context, serial_no, role_id);
          }
        } else {
          // More than 1 serial or company — reveal the selection UI
          if (mounted) setState(() => _silentMode = false);
        }
      } else {
        setState(() {
          _isVisibleCompany = false;
        });
        throw Exception('Failed to fetch data');
      }

      setState(() => _isLoading = false);
    } else {
      Map<String, dynamic> data = json.decode(response.body);
      String error = data['error'] ?? 'Something went wrong!!!';
      Fluttertoast.showToast(msg: error);
    }
    setState(() {
      _isLoading = false;
    });
  }

  Future<void> fetchAllowedCompany(String selectedserial, String email) async {
    setState(() {
      _isLoading = true;
    });
    myData_company.clear();
    final url = Uri.parse(
      '$BASE_URL_config/api/roles/allowed_companies?user_name=$email&serial_no=$selectedserial',
    );

    Map<String, String> headers = {
      'Authorization': 'Bearer $authTokenBase',
      "Content-Type": "application/json",
    };

    final response = await http.get(url, headers: headers);

    if (response.statusCode == 200) {
      final company_data = jsonDecode(response.body);

      if (company_data != null) {
        myData_company = company_data;

        if (myData_company.isEmpty) {
          await fetchCompany(serial_no);
        } else {
          setState(() {
            _isVisibleCompany = true;
            _selectcompany = myData_company.first;
          });

          // await loadCompanySyncInfo();

          // ✅ Auto-prompt to Dashboard if only one serial + one company
          if (myData.length == 1 && myData_company.length == 1) {
            final company_name = myData_company.first['company_name']
                .toString();
            startfrom = myData_company.first['startfrom'].toString();
            currency = myData_company.first['base_currency'].toString();

            Map<String, String> result = await getCompanyLastSync(
              context,
              company_name,
              serial_no,
            );

            prefs.setString("company_name", normalizeCompany(company_name));
            prefs.setString("startfrom", startfrom);
            prefs.setString("serial_no", serial_no);
            prefs.setString("base_currency", currency);
            prefs.setString("company_trn", result['trn'] ?? "");
            prefs.setString("company_address", result['address'] ?? "");
            prefs.setString("company_emirate", result['emirate'] ?? "");
            prefs.setString("company_country", result['country'] ?? "");

            if (secbtnaccess == "True") {
              for (String key in [
                "salesdash",
                "purchasedash",
                "barchartdash",
                "linechartdash",
                "piechartdash",
                "salesentry",
                "receiptentry",
                "salesorderentry",
                "outstandingreceivabledash",
                "outstandingpayabledash",
                "cashdash",
                "receiptsdash",
                "paymentsdash",
                "allitems",
                "activeitems",
                "inactiveitems",
                "rate",
                "item_amount",
                "item_sales",
                "item_purchase",
                "salesparty",
                "purchaseparty",
                "creditnoteparty",
                "journalparty",
                "payableparty",
                "pendingpurchaseorderparty",
                "receiptparty",
                "paymentparty",
                "debitnoteparty",
                "receivableparty",
                "pendingsalesorderparty",
                "party_suppliers",
                "party_customers",
                "ledgerentries",
                "inventoryentries",
                "postdatedtransactions",
                "billsentries",
                "costcentreentries",
                "vanallocation",
                "deliverynoteentry",
              ]) {
                prefs.setString(key, "True");
              }

              // ✅ Fade transition to Dashboard
              if (mounted) {
                Navigator.of(context).pushReplacement(
                  PageRouteBuilder(
                    transitionDuration: const Duration(milliseconds: 700),
                    pageBuilder: (context, animation, secondaryAnimation) =>
                        const Dashboard(),
                    transitionsBuilder:
                        (context, animation, secondaryAnimation, child) {
                          return FadeTransition(
                            opacity: animation,
                            child: child,
                          );
                        },
                  ),
                );
              }
            } else {
              if (mounted) {
                setState(() {
                  _isLoading = true;
                });
              }
              getroledata(context, serial_no, role_id);
            }
          } else {
            // More than 1 serial or company — reveal the selection UI
            if (mounted) setState(() => _silentMode = false);
          }
        }
      } else {
        setState(() {
          _isVisibleCompany = false;
          _isLoading = false;
        });
        throw Exception('Failed to fetch data');
      }
    } else {
      Map<String, dynamic> data = json.decode(response.body);
      String error = data['error'] ?? 'Something went wrong!!!';
      Fluttertoast.showToast(msg: error);
    }

    setState(() {
      _isLoading = false;
    });
  }
}
