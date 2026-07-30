/*
import 'dart:convert';
import 'dart:io';
import 'dart:ui';
import 'package:FincoreGo/PendingDeliveryNoteEntry.dart';
import 'package:FincoreGo/widgets/app_bottom_nav.dart';
import 'package:flutter/foundation.dart';
import 'package:FincoreGo/DashboardClicked.dart';
import 'package:FincoreGo/PendingReceiptEntry.dart';
import 'package:FincoreGo/PendingSalesEntry.dart';
import 'package:FincoreGo/Transactions.dart';
import 'package:FincoreGo/utils/number_formatter.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'utils/currency_helper.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'DashboardAnalytics.dart';
import 'Items.dart';
import 'Party.dart';
import 'PendingSalesOrderEntry.dart';
import 'SerialSelect.dart';
import 'Sidebar.dart';
import 'constants.dart';
import 'package:http/http.dart' as http;

List<String> months_chart = [];
List<String> months_chart_line_graph = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

List<Map<String, dynamic>> data = [];

String apiResponseTime = "";

List<dynamic> piechartsaleslist = [];
List<dynamic> piechartpurchaselist = [];

class Dashboard extends StatefulWidget {
  const Dashboard({Key? key}) : super(key: key);
  @override
  _MyHomePageState createState() => _MyHomePageState();
}

class _MyHomePageState extends State<Dashboard> with TickerProviderStateMixin {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  String? SecuritybtnAcessHolder;
  bool isDashEnable = false,
      isRolesEnable = true,
      isUserEnable = true,
      isRolesVisible = true,
      isUserVisible = true;

  bool isSalesEntryVisible = false,
      isReceiptEntryVisible = false,
      isSalesOrderEntryVisible = false,
      isDeliveryNoteEntryVisible = false;

  String SalesEntryHolder = '',
      ReceiptEntryHolder = '',
      SalesOrderEntryHolder = "",
      DeliveryNoteEntryHolder = '';
  String email = "";
  String name = "", token = '';

  late final TickerProvider tickerProvider;

  String vchtype = "";
  DateTime? expire_date;

  String salesparty = '';
  String purchaseparty = '';
  String creditnoteparty = '';
  String journalparty = '';
  String payableparty = '';
  String pendingpurchaseorderparty = '';
  String receiptparty = '';
  String paymentparty = '';
  String debitnoteparty = '';
  String receivableparty = '';
  String pendingsalesorderparty = '';
  String party_suppliers = '';
  String party_customers = '';

  String ledgerentries = '';
  String inventoryentries = '';
  String billsentries = '';
  String costcentreentries = '';

  bool isVisibleItemBtn = false,
      isVisiblePartyBtn = false,
      isVisibleTransactionBtn = false,
      isVisibleEntriesBtn = false;

  List<LineChartBarData> lineBars = [];

  bool sales_visiblity = false,
      purchase_visibility = false,
      receipt_visibility = false,
      payment_visibility = false,
      receivable_visibility = false,
      payable_visibility = false,
      cash_visibility = false,
      isVisibleNoAccess = false,
      isVisibleDate = false;

  bool isChartsVisible = false;

  bool isBarChartVisible = false;

  late NumberFormat currencyFormat;

  late GlobalKey<ScaffoldMessengerState> _scaffoldMessengerKey;
  late SharedPreferences prefs;
  late String startdate_text = "", enddate_text = "";
  bool _isDashVisible = true,
      _isEnddateVisible = true,
      _IsSizeboxVisible = true;

  DateTime _startDate = DateTime.now();

  DateTime _endDate = DateTime.now().add(Duration(days: 7));

  bool _isTextEnabled = true;

  String? datetype;
  bool isVisibleLineChart = false,
      isPieChartVisible = false,
      isSalesPieChartVisible = false,
      isPurchasePieChartVisible = false;

  late double sales_value = 0.0,
      purchase_value = 0.0,
      receipt_value = 0.0,
      payment_value = 0.0,
      outstandingreceivable_value = 0.0,
      outstandingpayable_value = 0.0,
      cash_value = 0.0;

  List<double> salesDataList = [];
  List<double> recDataList = [];
  late String? startdate_pref, enddate_pref;

  String? license_expiry;

  bool allitems_visibility = false,
      fastmovingitems_visibility = false,
      inactiveitems_visibility = false;

  bool isExpired = false;

  String HttpURL = "", HttpURL_charts = "", HttpURL_piecharts = "";

  String startDateString = "", endDateString = "";
  String? hostname = "",
      company = "",
      serial_no = "",
      company_lowercase = "",
      username = "",
      base_currency = "";

  String? barchartdashprefs, linechartdashprefs, piechartdashprefs;

  bool _isLoading = false;

  bool _isRefreshing = false;

  late String currencysymbol = '';

  dynamic _selecteddate = "Today";

  List<String> date_range = [
    'Today',
    'Yesterday',
    'This Month',
    'Last Month',
    'This Year',
    'Last Year',
    'Year To Date',
    'Custom Date',
  ];

  */
/*
  void showProgressDialog_LoadData(BuildContext context, bool _isLoading) {
    ProgressDialog progressDialog;
    progressDialog = ProgressDialog(context,
      isDismissible: true,);
    progressDialog.style(
      message: 'Loading...', // Message displayed in the dialog
      messageGoogleFonts.poppins: GoogleFonts.poppins(fontWeight: FontWeight.bold,),
    );
    if (_isLoading)
    {
      progressDialog.show();
    } else
    {
      progressDialog.hide();
    }
  }
*//*


  late int? decimal = 2;

  NumberScale _selectedScale = NumberScale.thousand;

  void _showEntriesBottomSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      builder: (context) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 40),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 🔹 Drag Handle
              Container(
                width: 40,
                height: 5,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(10),
                ),
              ),

              // 🔹 Centered Heading with Icon Above
              Column(
                children: [
                  Container(
                    width: 50,
                    height: 50,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [app_color.withOpacity(0.9), app_color],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: app_color.withOpacity(0.3),
                          blurRadius: 8,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.menu_book_rounded,
                      color: Colors.white,
                      size: 28,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    "Entry Type",
                    style: GoogleFonts.poppins(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Divider(thickness: 1, color: Colors.grey.shade300),
                ],
              ),
              const SizedBox(height: 20),

              // 🔹 Entry Options
              if (isSalesEntryVisible)
                _buildEntryOption(
                  icon: Icons.point_of_sale,
                  label: "Sales",
                  gradient: [Colors.blue.shade400, Colors.blue.shade700],
                  onTap: () {
                    Navigator.pop(context);
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => PendingSalesEntry()),
                    );
                  },
                ),

              if (isReceiptEntryVisible)
                _buildEntryOption(
                  icon: Icons.receipt_long,
                  label: "Receipts",
                  gradient: [Colors.green.shade400, Colors.green.shade700],
                  onTap: () {
                    Navigator.pop(context);
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => PendingReceiptEntry()),
                    );
                  },
                ),

              if (isSalesOrderEntryVisible)
                _buildEntryOption(
                  icon: Icons.assignment,
                  label: "Sales Order",
                  gradient: [
                    Colors.orange.shade400,
                    Colors.deepOrange.shade600,
                  ],
                  onTap: () {
                    Navigator.pop(context);
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => PendingSalesOrderEntry(),
                      ),
                    );
                  },
                ),
              if (vanSalesSerialNo.contains(serial_no) &&
                  (isDeliveryNoteEntryVisible))
                _buildEntryOption(
                  icon: Icons.local_shipping,
                  label: "Delivery Note",
                  gradient: [Colors.blue.shade400, Colors.indigo.shade600],
                  onTap: () {
                    Navigator.pop(context);
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => PendingDeliveryNoteEntry(),
                      ),
                    );
                  },
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildEntryOption({
    required IconData icon,
    required String label,
    required List<Color> gradient,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        margin: const EdgeInsets.only(bottom: 14),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: gradient.last.withOpacity(0.5), width: 1.2),
          boxShadow: [
            BoxShadow(
              color: gradient.last.withOpacity(0.15),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                gradient: LinearGradient(colors: gradient),
                borderRadius: BorderRadius.circular(10),
                boxShadow: [
                  BoxShadow(
                    color: gradient.last.withOpacity(0.25),
                    blurRadius: 6,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: Icon(icon, color: Colors.white, size: 20),
            ),
            const SizedBox(width: 14),
            Text(
              label,
              style: GoogleFonts.poppins(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
            const Spacer(),
            Icon(
              Icons.arrow_forward_ios_rounded,
              size: 18,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ],
        ),
      ),
    );
  }

  void generateMonthsList() {
    months_chart.clear();

    DateTime startDate = DateTime.parse(startDateString);
    DateTime endDate = DateTime.parse(endDateString);
    while (startDate.isBefore(endDate) || startDate.isAtSameMomentAs(endDate)) {
      String month = DateFormat('MMM-yy').format(startDate);
      months_chart.add(month);
      startDate = DateTime(startDate.year, startDate.month + 1, startDate.day);
    }
  }

  double calculateContainerWidthBarGraph() {
    int totalMonths = months_chart.length; // Total number of months
    double averageLabelWidth = 60.0; // Adjust as needed

    double screensize = MediaQuery.of(context).size.width - 20.0;

    // Calculate the total width needed for all month labels
    double totalLabelWidth = totalMonths * averageLabelWidth;

    // Add extra width for margins, padding, and other elements
    double extraWidth = 100.0;

    // Calculate the final container width
    double containerWidth = totalLabelWidth + extraWidth;
    if (containerWidth < screensize) {
      containerWidth = screensize;
    }

    return containerWidth;
  }

  double calculateContainerWidthLineGraph() {
    int totalMonths = months_chart_line_graph.length; // Total number of months
    double averageLabelWidth = 60.0; // Adjust as needed

    double screensize = MediaQuery.of(context).size.width - 20.0;

    // Calculate the total width needed for all month labels
    double totalLabelWidth = totalMonths * averageLabelWidth;

    // Add extra width for margins, padding, and other elements
    double extraWidth = 100.0; // Adjust as needed
    // Calculate the final container width
    double containerWidth = totalLabelWidth + extraWidth;
    if (containerWidth < screensize) {
      containerWidth = screensize;
    }
    return containerWidth;
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

  Future<void> _handleRefresh() async {
    setState(() {
      _isRefreshing = true;
    });

    // Do your refresh work here.
    datetype = prefs.getString('datetype');
    if (datetype != null) {
      _selecteddate = datetype;
      if (_selecteddate == "Today") {
        DateTime currentDate = DateTime.now();
        String startMonth = DateFormat('MMM').format(currentDate);
        String sdf = DateFormat(
          'MM',
        ).format(currentDate); // converting month into string

        String startDay = DateFormat('dd').format(currentDate);
        int startYear = currentDate.year;

        String endMonth = DateFormat('MMM').format(currentDate);
        String sdfEnd = DateFormat('MM').format(currentDate);

        String endDay = DateFormat('dd').format(currentDate);
        int endYear = currentDate.year;

        startDateString = "$startYear$sdf$startDay";
        endDateString = "$endYear$sdfEnd$endDay";
        print(startDateString);
        print(endDateString);

        fetchDashData(startDateString, endDateString);

        setState(() {
          _isTextEnabled = false;
          _isDashVisible = false;
          _isEnddateVisible = false;
          _IsSizeboxVisible = false;
        });

        startdate_text =
            startDay + "-" + startMonth + "-" + startYear.toString();
        enddate_text = endDay + "-" + endMonth + "-" + endYear.toString();
      } else if (_selecteddate == "Year To Date") {
        DateTime now = DateTime.now();
        DateTime startDate = DateTime(
          now.year,
          1,
          1,
        ); // Start of the current year
        DateTime endDate = DateTime(
          now.year,
          now.month,
          now.day,
        ); // Today's date

        DateFormat dateFormat = DateFormat("dd-MMM-yyyy");

        String startMonth = dateFormat.format(startDate).substring(3, 6);
        String sdf = DateFormat('MM').format(startDate);

        String startDay = dateFormat.format(startDate).substring(0, 2);
        int startYear = startDate.year;

        String endMonth = dateFormat.format(endDate).substring(3, 6);
        String sdfEnd = DateFormat('MM').format(endDate);

        String endDay = dateFormat.format(endDate).substring(0, 2);
        int endYear = endDate.year;

        startDateString = "$startYear$sdf$startDay";
        endDateString = "$endYear$sdfEnd$endDay";
        print(startDateString);
        print(endDateString);

        startdate_text =
            startDay + "-" + startMonth + "-" + startYear.toString();
        enddate_text = endDay + "-" + endMonth + "-" + endYear.toString();

        fetchDashData(startDateString, endDateString);

        setState(() {
          _isTextEnabled = false;
          _isDashVisible = true;
          _isEnddateVisible = true;
          _IsSizeboxVisible = true;
        });
      } else if (_selecteddate == "Yesterday") {
        DateTime yesterday = DateTime.now().subtract(Duration(days: 1));
        DateFormat dateFormat = DateFormat("dd-MMM-yyyy");

        String startMonth = dateFormat.format(yesterday).substring(3, 6);
        String sdf = DateFormat(
          'MM',
        ).format(yesterday); // converting month into string

        String startDay = dateFormat.format(yesterday).substring(0, 2);
        int startYear = yesterday.year;

        String endMonth = dateFormat.format(yesterday).substring(3, 6);
        String sdfEnd = DateFormat('MM').format(yesterday);

        String endDay = dateFormat.format(yesterday).substring(0, 2);
        int endYear = yesterday.year;

        startDateString = "$startYear$sdf$startDay";
        endDateString = "$endYear$sdfEnd$endDay";
        print(startDateString);
        print(endDateString);

        startdate_text =
            startDay + "-" + startMonth + "-" + startYear.toString();
        enddate_text = endDay + "-" + endMonth + "-" + endYear.toString();

        fetchDashData(startDateString, endDateString);

        setState(() {
          _isTextEnabled = false;
          _isDashVisible = false;
          _isEnddateVisible = false;
          _IsSizeboxVisible = false;
        });
      } else if (_selecteddate == "This Month") {
        DateTime now = DateTime.now();
        DateTime startOfMonth = DateTime(now.year, now.month, 1);
        DateTime endOfMonth = DateTime(now.year, now.month + 1, 0);

        String startMonth = DateFormat('MMM').format(startOfMonth);
        String sdf = DateFormat(
          'MM',
        ).format(startOfMonth); // converting month into string
        String startDay = DateFormat('dd').format(startOfMonth);
        int startYear = startOfMonth.year;

        String endMonth = DateFormat('MMM').format(endOfMonth);
        String sdfEnd = DateFormat('MM').format(endOfMonth);
        String endDay = DateFormat('dd').format(endOfMonth);
        int endYear = endOfMonth.year;

        startDateString = '$startYear$sdf$startDay';
        endDateString = '$endYear$sdfEnd$endDay';

        startdate_text =
            startDay + "-" + startMonth + "-" + startYear.toString();
        enddate_text = endDay + "-" + endMonth + "-" + endYear.toString();

        print(startDateString);
        print(endDateString);

        fetchDashData(startDateString, endDateString);

        setState(() {
          _isTextEnabled = false;

          _isDashVisible = true;
          _isEnddateVisible = true;
          _IsSizeboxVisible = true;
        });
      } else if (_selecteddate == "Last Month") {
        var calendarLastMonthStart = DateTime.now();
        var calendarLastMonthEnd = DateTime.now();

        calendarLastMonthStart = DateTime(
          calendarLastMonthStart.year,
          calendarLastMonthStart.month - 1,
          1,
        );

        calendarLastMonthStart = DateTime(
          calendarLastMonthStart.year,
          calendarLastMonthStart.month,
          1,
        );
        calendarLastMonthEnd = DateTime(
          calendarLastMonthStart.year,
          calendarLastMonthStart.month + 1,
          0,
        );

        var startMonth = DateFormat('MMM').format(calendarLastMonthStart);
        var sdf = DateFormat('MM').format(calendarLastMonthStart);
        var startDay = DateFormat('dd').format(calendarLastMonthStart);
        var startYear = calendarLastMonthStart.year;

        var endMonth = DateFormat('MMM').format(calendarLastMonthEnd);
        var sdfEnd = DateFormat('MM').format(calendarLastMonthEnd);
        var endDay = DateFormat('dd').format(calendarLastMonthEnd);
        var endYear = calendarLastMonthEnd.year;

        startDateString = '$startYear$sdf$startDay';
        endDateString = '$endYear$sdfEnd$endDay';

        startdate_text =
            startDay + "-" + startMonth + "-" + startYear.toString();
        enddate_text = endDay + "-" + endMonth + "-" + endYear.toString();

        print(startDateString);
        print(endDateString);

        fetchDashData(startDateString, endDateString);

        setState(() {
          _isTextEnabled = false;

          _isDashVisible = true;
          _isEnddateVisible = true;
          _IsSizeboxVisible = true;
        });
      } else if (_selecteddate == "This Year") {
        DateTime today = DateTime.now();
        DateTime yearStart = DateTime(today.year, 1, 1);
        DateTime yearEnd = DateTime(today.year, 12, 31);

        String startMonth = DateFormat('MMM').format(yearStart);
        String sdf = DateFormat(
          'MM',
        ).format(yearStart); // converting month into string
        String startDay = DateFormat('dd').format(yearStart);
        String startYear = DateFormat('yyyy').format(yearStart);

        String endMonth = DateFormat('MMM').format(yearEnd);
        String sdfEnd = DateFormat('MM').format(yearEnd);
        String endDay = DateFormat('dd').format(yearEnd);
        String endYear = DateFormat('yyyy').format(yearEnd);

        startDateString = '$startYear$sdf$startDay';
        endDateString = '$endYear$sdfEnd$endDay';

        startdate_text =
            startDay + "-" + startMonth + "-" + startYear.toString();
        enddate_text = endDay + "-" + endMonth + "-" + endYear.toString();

        print(startDateString);
        print(endDateString);

        fetchDashData(startDateString, endDateString);

        setState(() {
          _isTextEnabled = false;

          _isDashVisible = true;
          _isEnddateVisible = true;
          _IsSizeboxVisible = true;
        });
      } else if (_selecteddate == "Last Year") {
        DateTime today = DateTime.now();
        DateTime yearStart = DateTime(today.year - 1, 1, 1);
        DateTime yearEnd = DateTime(today.year - 1, 12, 31);

        String startMonth = DateFormat('MMM').format(yearStart);
        String sdf = DateFormat(
          'MM',
        ).format(yearStart); // converting month into string
        String startDay = DateFormat('dd').format(yearStart);
        String startYear = DateFormat('yyyy').format(yearStart);

        String endMonth = DateFormat('MMM').format(yearEnd);
        String sdfEnd = DateFormat('MM').format(yearEnd);
        String endDay = DateFormat('dd').format(yearEnd);
        String endYear = DateFormat('yyyy').format(yearEnd);

        startdate_text =
            startDay + "-" + startMonth + "-" + startYear.toString();
        enddate_text = endDay + "-" + endMonth + "-" + endYear.toString();

        startDateString = '$startYear$sdf$startDay';
        endDateString = '$endYear$sdfEnd$endDay';

        print(startDateString);
        print(endDateString);

        fetchDashData(startDateString, endDateString);

        setState(() {
          _isTextEnabled = false;

          _isDashVisible = true;
          _isEnddateVisible = true;
          _IsSizeboxVisible = true;
        });
      } else if (_selecteddate == "Custom Date") {
        setState(() {
          _isTextEnabled = true;

          _isDashVisible = true;
          _isEnddateVisible = true;
          _IsSizeboxVisible = true;
        });

        _selectDateRange_refresh(context);
      }
      prefs.setString('datetype', _selecteddate);
    } else {
      if (_selecteddate == "Today") {
        DateTime currentDate = DateTime.now();
        String startMonth = DateFormat('MMM').format(currentDate);
        String sdf = DateFormat(
          'MM',
        ).format(currentDate); // converting month into string

        String startDay = DateFormat('dd').format(currentDate);
        int startYear = currentDate.year;

        String endMonth = DateFormat('MMM').format(currentDate);
        String sdfEnd = DateFormat('MM').format(currentDate);

        String endDay = DateFormat('dd').format(currentDate);
        int endYear = currentDate.year;

        startDateString = "$startYear$sdf$startDay";
        endDateString = "$endYear$sdfEnd$endDay";
        print(startDateString);
        print(endDateString);

        fetchDashData(startDateString, endDateString);

        setState(() {
          _isTextEnabled = false;
          _isDashVisible = false;
          _isEnddateVisible = false;
          _IsSizeboxVisible = false;
        });

        startdate_text =
            startDay + "-" + startMonth + "-" + startYear.toString();
        enddate_text = endDay + "-" + endMonth + "-" + endYear.toString();
      } else if (_selecteddate == "Year To Date") {
        DateTime now = DateTime.now();
        DateTime startDate = DateTime(
          now.year,
          1,
          1,
        ); // Start of the current year
        DateTime endDate = DateTime(
          now.year,
          now.month,
          now.day,
        ); // Today's date

        DateFormat dateFormat = DateFormat("dd-MMM-yyyy");

        String startMonth = dateFormat.format(startDate).substring(3, 6);
        String sdf = DateFormat('MM').format(startDate);

        String startDay = dateFormat.format(startDate).substring(0, 2);
        int startYear = startDate.year;

        String endMonth = dateFormat.format(endDate).substring(3, 6);
        String sdfEnd = DateFormat('MM').format(endDate);

        String endDay = dateFormat.format(endDate).substring(0, 2);
        int endYear = endDate.year;

        startDateString = "$startYear$sdf$startDay";
        endDateString = "$endYear$sdfEnd$endDay";
        print(startDateString);
        print(endDateString);

        startdate_text =
            startDay + "-" + startMonth + "-" + startYear.toString();
        enddate_text = endDay + "-" + endMonth + "-" + endYear.toString();

        fetchDashData(startDateString, endDateString);

        setState(() {
          _isTextEnabled = false;

          _isDashVisible = true;
          _isEnddateVisible = true;
          _IsSizeboxVisible = true;
        });
      } else if (_selecteddate == "Yesterday") {
        DateTime yesterday = DateTime.now().subtract(Duration(days: 1));
        DateFormat dateFormat = DateFormat("dd-MMM-yyyy");

        String startMonth = dateFormat.format(yesterday).substring(3, 6);
        String sdf = DateFormat(
          'MM',
        ).format(yesterday); // converting month into string

        String startDay = dateFormat.format(yesterday).substring(0, 2);
        int startYear = yesterday.year;

        String endMonth = dateFormat.format(yesterday).substring(3, 6);
        String sdfEnd = DateFormat('MM').format(yesterday);

        String endDay = dateFormat.format(yesterday).substring(0, 2);
        int endYear = yesterday.year;

        startDateString = "$startYear$sdf$startDay";
        endDateString = "$endYear$sdfEnd$endDay";
        print(startDateString);
        print(endDateString);

        startdate_text =
            startDay + "-" + startMonth + "-" + startYear.toString();
        enddate_text = endDay + "-" + endMonth + "-" + endYear.toString();

        fetchDashData(startDateString, endDateString);

        setState(() {
          _isTextEnabled = false;
          _isDashVisible = false;
          _isEnddateVisible = false;
          _IsSizeboxVisible = false;
        });
      } else if (_selecteddate == "This Month") {
        DateTime now = DateTime.now();
        DateTime startOfMonth = DateTime(now.year, now.month, 1);
        DateTime endOfMonth = DateTime(now.year, now.month + 1, 0);

        String startMonth = DateFormat('MMM').format(startOfMonth);
        String sdf = DateFormat(
          'MM',
        ).format(startOfMonth); // converting month into string
        String startDay = DateFormat('dd').format(startOfMonth);
        int startYear = startOfMonth.year;

        String endMonth = DateFormat('MMM').format(endOfMonth);
        String sdfEnd = DateFormat('MM').format(endOfMonth);
        String endDay = DateFormat('dd').format(endOfMonth);
        int endYear = endOfMonth.year;

        startDateString = '$startYear$sdf$startDay';
        endDateString = '$endYear$sdfEnd$endDay';

        startdate_text =
            startDay + "-" + startMonth + "-" + startYear.toString();
        enddate_text = endDay + "-" + endMonth + "-" + endYear.toString();

        print(startDateString);
        print(endDateString);

        fetchDashData(startDateString, endDateString);

        setState(() {
          _isTextEnabled = false;
          _isDashVisible = true;
          _isEnddateVisible = true;
          _IsSizeboxVisible = true;
        });
      } else if (_selecteddate == "Last Month") {
        var calendarLastMonthStart = DateTime.now();
        var calendarLastMonthEnd = DateTime.now();

        calendarLastMonthStart = DateTime(
          calendarLastMonthStart.year,
          calendarLastMonthStart.month - 1,
          1,
        );

        calendarLastMonthStart = DateTime(
          calendarLastMonthStart.year,
          calendarLastMonthStart.month,
          1,
        );
        calendarLastMonthEnd = DateTime(
          calendarLastMonthStart.year,
          calendarLastMonthStart.month + 1,
          0,
        );

        var startMonth = DateFormat('MMM').format(calendarLastMonthStart);
        var sdf = DateFormat('MM').format(calendarLastMonthStart);
        var startDay = DateFormat('dd').format(calendarLastMonthStart);
        var startYear = calendarLastMonthStart.year;

        var endMonth = DateFormat('MMM').format(calendarLastMonthEnd);
        var sdfEnd = DateFormat('MM').format(calendarLastMonthEnd);
        var endDay = DateFormat('dd').format(calendarLastMonthEnd);
        var endYear = calendarLastMonthEnd.year;

        startDateString = '$startYear$sdf$startDay';
        endDateString = '$endYear$sdfEnd$endDay';

        startdate_text =
            startDay + "-" + startMonth + "-" + startYear.toString();
        enddate_text = endDay + "-" + endMonth + "-" + endYear.toString();

        print(startDateString);
        print(endDateString);

        fetchDashData(startDateString, endDateString);

        setState(() {
          _isTextEnabled = false;

          _isDashVisible = true;
          _isEnddateVisible = true;
          _IsSizeboxVisible = true;
        });
      } else if (_selecteddate == "This Year") {
        DateTime today = DateTime.now();
        DateTime yearStart = DateTime(today.year, 1, 1);
        DateTime yearEnd = DateTime(today.year, 12, 31);

        String startMonth = DateFormat('MMM').format(yearStart);
        String sdf = DateFormat(
          'MM',
        ).format(yearStart); // converting month into string
        String startDay = DateFormat('dd').format(yearStart);
        String startYear = DateFormat('yyyy').format(yearStart);

        String endMonth = DateFormat('MMM').format(yearEnd);
        String sdfEnd = DateFormat('MM').format(yearEnd);
        String endDay = DateFormat('dd').format(yearEnd);
        String endYear = DateFormat('yyyy').format(yearEnd);

        startDateString = '$startYear$sdf$startDay';
        endDateString = '$endYear$sdfEnd$endDay';

        startdate_text =
            startDay + "-" + startMonth + "-" + startYear.toString();
        enddate_text = endDay + "-" + endMonth + "-" + endYear.toString();

        print(startDateString);
        print(endDateString);

        fetchDashData(startDateString, endDateString);

        setState(() {
          _isTextEnabled = false;

          _isDashVisible = true;
          _isEnddateVisible = true;
          _IsSizeboxVisible = true;
        });
      } else if (_selecteddate == "Last Year") {
        DateTime today = DateTime.now();
        DateTime yearStart = DateTime(today.year - 1, 1, 1);
        DateTime yearEnd = DateTime(today.year - 1, 12, 31);

        String startMonth = DateFormat('MMM').format(yearStart);
        String sdf = DateFormat(
          'MM',
        ).format(yearStart); // converting month into string
        String startDay = DateFormat('dd').format(yearStart);
        String startYear = DateFormat('yyyy').format(yearStart);

        String endMonth = DateFormat('MMM').format(yearEnd);
        String sdfEnd = DateFormat('MM').format(yearEnd);
        String endDay = DateFormat('dd').format(yearEnd);
        String endYear = DateFormat('yyyy').format(yearEnd);

        startdate_text =
            startDay + "-" + startMonth + "-" + startYear.toString();
        enddate_text = endDay + "-" + endMonth + "-" + endYear.toString();

        startDateString = '$startYear$sdf$startDay';
        endDateString = '$endYear$sdfEnd$endDay';

        print(startDateString);
        print(endDateString);

        fetchDashData(startDateString, endDateString);

        setState(() {
          _isTextEnabled = false;

          _isDashVisible = true;
          _isEnddateVisible = true;
          _IsSizeboxVisible = true;
        });
      } else if (_selecteddate == "Custom Date") {
        setState(() {
          _isTextEnabled = true;

          _isDashVisible = true;
          _isEnddateVisible = true;
          _IsSizeboxVisible = true;
        });

        _selectDateRange_refresh(context);
      }
      prefs.setString('datetype', _selecteddate);
    }

    // Set the isRefreshing variable to false.
    setState(() {
      _isRefreshing = false;
    });
  }

  Future<void> fetchDashData(String startdate, String enddate) async {
    if (!isVisibleNoAccess) {
      setState(() {
        _isLoading = true;
      });
      */
/*showProgressDialog_LoadData(context, _isLoading);*//*


      final url = Uri.parse(HttpURL);

      Map<String, String> headers = {
        'Authorization': 'Bearer $token',
        "Content-Type": "application/json",
      };

      var body = jsonEncode({'startdate': startdate, 'enddate': enddate});
      final stopwatch = Stopwatch()..start();

      final response = await http.post(url, body: body, headers: headers);

      stopwatch.stop();

      setState(() {
        apiResponseTime = "${stopwatch.elapsedMilliseconds} ms";
      });

      print(' response time -> $apiResponseTime');
      print(' dash response -> ${response.body}');

      final dash_data = jsonDecode(utf8.decode(response.bodyBytes));

      try {
        if (response.statusCode == 200) {
          print(dash_data);

          if (dash_data != null) {
            sales_value =
                double.tryParse(dash_data['sales']?.toString() ?? "0") ?? 0.0;
            purchase_value =
                double.tryParse(dash_data['purchase']?.toString() ?? "0") ??
                0.0;
            receipt_value =
                double.tryParse(dash_data['receipt']?.toString() ?? "0") ?? 0.0;
            payment_value =
                double.tryParse(dash_data['payment']?.toString() ?? "0") ?? 0.0;
            cash_value =
                double.tryParse(dash_data['cash']?.toString() ?? "0") ?? 0.0;
            outstandingreceivable_value =
                double.tryParse(dash_data['receivable']?.toString() ?? "0") ??
                0.0;
            outstandingpayable_value =
                double.tryParse(dash_data['payable']?.toString() ?? "0") ?? 0.0;

            prefs.setDouble('sales', sales_value);
            prefs.setDouble('purchase', purchase_value);
            prefs.setDouble('receipt', receipt_value);
            prefs.setDouble('payment', payment_value);
            prefs.setDouble('receivable', outstandingreceivable_value);
            prefs.setDouble('payable', outstandingpayable_value);
            prefs.setDouble('cash', cash_value);
          } else {
            prefs.remove('sales');
            prefs.remove('purchase');
            prefs.remove('receipt');
            prefs.remove('payment');
            prefs.remove('receivable');
            prefs.remove('payable');
            prefs.remove('cash');
            throw Exception('Failed to fetch data');
          }
        } else {
          Map<String, dynamic> data = json.decode(utf8.decode(response.bodyBytes));
          String error = '';

          if (data.containsKey('error')) {
            setState(() {
              error = data['error'];
            });
          } else {
            error = "Error in data fetching!!!";
          }
          Fluttertoast.showToast(msg: error);
        }
      } catch (e) {
        String error = '';

        if (dash_data.containsKey('error')) {
          setState(() {
            error = dash_data['error'];
          });
        } else {
          error = "Error in data fetching!!!";
        }
        Fluttertoast.showToast(msg: error);
      }

      try {
        if (linechartdashprefs == 'True' ||
            barchartdashprefs == 'True' ||
            piechartdashprefs == 'True') {
          if (linechartdashprefs == 'True' || barchartdashprefs == 'True') {
            final url_charts = Uri.parse(HttpURL_charts);

            Map<String, String> headers_charts = {
              'Authorization': 'Bearer $token',
              "Content-Type": "application/json",
            };

            var body_charts = jsonEncode({
              "startdate": startdate,
              "enddate": enddate,
              "groupBy": "month",
            });

            final response_charts = await http.post(
              url_charts,
              body: body_charts,
              headers: headers_charts,
            );

            if (response_charts.statusCode == 200) {
              if (response_charts.body == '[]') {
                setState(() {
                  isBarChartVisible = false;
                  isVisibleLineChart = false;
                  _isLoading = false;
                });
                */
/*showProgressDialog_LoadData(context, _isLoading);*//*

              } else {
                lineBars.clear();
                salesDataList.clear();
                recDataList.clear();
                data.clear();
                Map<String, dynamic> responseJson = json.decode(
                  response_charts.body,
                );

                try {
                  List<dynamic> successArray = responseJson['success'];

                  setState(() {
                    data.addAll(successArray.cast<Map<String, dynamic>>());

                    for (var yearData in data) {
                      var value = yearData['value'];

                      int monthCount = value.length;
                      if (monthCount == 1) {
                        setState(() {
                          isVisibleLineChart = false;
                        });
                        for (var monthData in value) {
                          double sales = double.parse(
                            monthData['sales'].toString(),
                          );
                          double receipt = double.parse(
                            monthData['receipt'].toString(),
                          );

                          */
/*print(response_charts.body);*//*


                          salesDataList.add(-sales);
                          recDataList.add(receipt);
                          if (barchartdashprefs == 'True') {
                            isBarChartVisible = true;
                          } else {
                            isBarChartVisible = false;
                          }
                        }
                      } else {
                        setState(() {
                          if (linechartdashprefs == 'True') {
                            isVisibleLineChart = true;
                          } else {
                            isVisibleLineChart = false;
                          }
                        });
                        for (var monthData in value) {
                          double sales = double.parse(
                            monthData['sales'].toString(),
                          );
                          double receipt = double.parse(
                            monthData['receipt'].toString(),
                          );

                          salesDataList.add(-sales);
                          recDataList.add(receipt);

                          if (barchartdashprefs == 'True') {
                            isBarChartVisible = true;
                          } else {
                            isBarChartVisible = false;
                          }
                        }
                      }
                    }
                  });
                } catch (f) {
                  print(f);
                  setState(() {
                    isVisibleLineChart = false;
                    isBarChartVisible = false;
                  });
                }
              }

              generateMonthsList();
            } else {
              Map<String, dynamic> data = json.decode(response_charts.body);
              String error = '';

              if (data.containsKey('error')) {
                setState(() {
                  error = data['error'];
                });
              } else {
                error = "Something went wrong!!!";
              }
              Fluttertoast.showToast(msg: error);
            }
          } else {
            setState(() {
              isVisibleLineChart = false;
              isBarChartVisible = false;
            });
          }

          if (piechartdashprefs == 'True') {
            final url_piecharts = Uri.parse(HttpURL_piecharts);

            Map<String, String> headers_piecharts = {
              'Authorization': 'Bearer $token',
              "Content-Type": "application/json",
            };

            var body_piecharts = jsonEncode({
              "startdate": startdate,
              "enddate": enddate,
            });

            final response_piecharts = await http.post(
              url_piecharts,
              body: body_piecharts,
              headers: headers_piecharts,
            );

            if (response_piecharts.statusCode == 200) {
              Map<String, dynamic> pieChartData = json.decode(
                response_piecharts.body,
              );
              piechartsaleslist = pieChartData['sales'];
              piechartpurchaselist = pieChartData['purchase'];

              if (piechartsaleslist.isEmpty && piechartpurchaselist.isEmpty) {
                setState(() {
                  isPieChartVisible = false;
                  isSalesPieChartVisible = false;
                  isPurchasePieChartVisible = false;
                });
              } else {
                setState(() {
                  isPieChartVisible = true;
                });
                if (piechartsaleslist.isEmpty) {
                  setState(() {
                    isSalesPieChartVisible = false;
                  });
                } else {
                  setState(() {
                    isSalesPieChartVisible = true;
                  });
                }
                if (piechartpurchaselist.isEmpty) {
                  setState(() {
                    isPurchasePieChartVisible = false;
                  });
                } else {
                  setState(() {
                    isPurchasePieChartVisible = true;
                  });
                }
              }
            } else {
              setState(() {
                isPieChartVisible = false;
                isPurchasePieChartVisible = false;
                isSalesPieChartVisible = false;
              });
              Map<String, dynamic> data = json.decode(response_piecharts.body);
              String error = '';

              if (data.containsKey('error')) {
                setState(() {
                  error = data['error'];
                });
              } else {
                error = "Something went wrong!!!";
              }
              Fluttertoast.showToast(msg: error);
            }
          }
          setState(() {
            isChartsVisible = true;
          });
        } else {
          setState(() {
            isChartsVisible = false;
          });
        }
      } catch (e) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.toString())));
      }

      setState(() {
        _isLoading = false;
      });
      */
/*showProgressDialog_LoadData(context, _isLoading);*//*

    }
  }

  Future<void> _selectDateRange_refresh(BuildContext context) async {
    if (_isTextEnabled) {
      startdate_pref = prefs.getString('startdate');
      enddate_pref = prefs.getString('enddate');

      if (startdate_pref == null ||
          enddate_pref == null ||
          startdate_pref == "") {
        startdate_pref = prefs.getString('startfrom')!;

        final initialDateRange = DateTimeRange(
          start: _startDate,
          end: _endDate,
        );
        String? startfrom = startdate_pref;
        DateTime earliestDate = DateTime.parse(startfrom!);

        DateTimeRange? selectedDateRange = await showDateRangePicker(
          context: context,
          initialDateRange: initialDateRange,
          firstDate: earliestDate,
          lastDate: DateTime(2100),
          builder: (BuildContext context, Widget? child) {
            return Theme(
              data: Theme.of(context).copyWith(
                colorScheme: Theme.of(context).colorScheme.copyWith(
                  primary: app_color, // main accent color
                  onPrimary: Colors.white,

                  surface: Theme.of(context).colorScheme.surface,
                  onSurface: Theme.of(context).colorScheme.onSurface,
                ), // 🔹 important
                datePickerTheme: DatePickerThemeData(
                  backgroundColor: Theme.of(
                    context,
                  ).scaffoldBackgroundColor, // 🔹 THIS fixes the picker bg
                  surfaceTintColor:
                      Colors.white, // 🔹 prevents grey tint (Material 3)
                  rangeSelectionBackgroundColor: app_color.withOpacity(0.15),
                  rangeSelectionOverlayColor: MaterialStatePropertyAll(
                    app_color.withOpacity(0.15),
                  ),
                ),
                dialogTheme: DialogThemeData(
                  backgroundColor: Theme.of(context).colorScheme.surface,
                ),
                dialogBackgroundColor: Colors.white, // 🔹 important
              ),
              child: child!,
            );
          },
        );

        if (selectedDateRange != null &&
            selectedDateRange != initialDateRange) {
          setState(() async {
            _startDate = selectedDateRange.start;
            _endDate = selectedDateRange.end;

            DateTime start = _startDate;
            DateTime end = _endDate;

            String startMonth = DateFormat('MMM').format(start);
            String sdf = DateFormat(
              'MM',
            ).format(start); // converting month into string
            String startDay = DateFormat('dd').format(start);
            int startYear = start.year;

            String endMonth = DateFormat('MMM').format(end);
            String sdfEnd = DateFormat('MM').format(end);
            String endDay = DateFormat('dd').format(end);
            int endYear = end.year;

            startDateString = '$startYear$sdf$startDay';
            endDateString = '$endYear$sdfEnd$endDay';

            startdate_text =
                startDay + "-" + startMonth + "-" + startYear.toString();
            enddate_text = endDay + "-" + endMonth + "-" + endYear.toString();

            print(startDateString);
            print(endDateString);

            fetchDashData(startDateString, endDateString);
          });
        }

        prefs.setString('startdate', startDateString);
        prefs.setString('enddate', endDateString);
      } else {
        if (!_isRefreshing) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text("Swipe Down to Refresh Data")));
        }

        */
/*String? sales = prefs.getString('sales');
        String? purchase = prefs.getString('purchase');
        String? receipt = prefs.getString('receipt');
        String? payment = prefs.getString('payment');
        String? receivable = prefs.getString('receivable');
        String? payable = prefs.getString('payable');
        String? cash = prefs.getString('cash');*//*


        DateTime start = DateTime.parse(startdate_pref!);
        DateTime end = DateTime.parse(enddate_pref!);

        String startMonth = DateFormat('MMM').format(start);
        String sdf = DateFormat(
          'MM',
        ).format(start); // converting month into string
        String startDay = DateFormat('dd').format(start);
        int startYear = start.year;

        String endMonth = DateFormat('MMM').format(end);
        String sdfEnd = DateFormat('MM').format(end);
        String endDay = DateFormat('dd').format(end);
        int endYear = end.year;

        startDateString = '$startYear$sdf$startDay';
        endDateString = '$endYear$sdfEnd$endDay';

        startdate_text =
            startDay + "-" + startMonth + "-" + startYear.toString();
        enddate_text = endDay + "-" + endMonth + "-" + endYear.toString();

        print(startDateString);
        print(endDateString);

        */
/*if(sales!=null)
        {
          sales_value = sales;
          purchase_value = purchase!;
          receipt_value = receipt!;
          payment_value = payment!;
          outstandingreceivable_value = receivable!;
          outstandingpayable_value = payable!;
          cash_value = cash!;
        }*//*


        fetchDashData(startDateString, endDateString);

        prefs.setString('startdate', startDateString);
        prefs.setString('enddate', endDateString);
      }
    }
  }

  Future<void> _selectDateRange_auto(BuildContext context) async {
    if (_isTextEnabled) {
      startdate_pref = prefs.getString('startdate');
      enddate_pref = prefs.getString('enddate');

      if (startdate_pref == null ||
          enddate_pref == null ||
          startdate_pref == "") {
        startdate_pref = prefs.getString('startfrom')!;

        final initialDateRange = DateTimeRange(
          start: _startDate,
          end: _endDate,
        );
        String? startfrom = startdate_pref;
        DateTime earliestDate = DateTime.parse(startfrom!);

        DateTimeRange? selectedDateRange = await showDateRangePicker(
          context: context,
          initialDateRange: initialDateRange,
          firstDate: earliestDate,
          lastDate: DateTime(2100),
          builder: (BuildContext context, Widget? child) {
            return Theme(
              data: Theme.of(context).copyWith(
                colorScheme: Theme.of(context).colorScheme.copyWith(
                  primary: app_color, // main accent color
                  onPrimary: Colors.white,
                  surface: Theme.of(context).colorScheme.surface,
                  onSurface: Theme.of(context).colorScheme.onSurface,
                ),

                datePickerTheme: DatePickerThemeData(
                  backgroundColor: Theme.of(
                    context,
                  ).scaffoldBackgroundColor, // 🔹 THIS fixes the picker bg
                  surfaceTintColor:
                      Colors.white, // 🔹 prevents grey tint (Material 3)
                  rangeSelectionBackgroundColor: app_color.withOpacity(0.15),
                  rangeSelectionOverlayColor: MaterialStatePropertyAll(
                    app_color.withOpacity(0.15),
                  ),
                ),
                dialogTheme: DialogThemeData(
                  backgroundColor: Theme.of(context).colorScheme.surface,
                ),
                dialogBackgroundColor: Colors.white, // 🔹 important
              ),
              child: child!,
            );
          },
        );

        if (selectedDateRange != null &&
            selectedDateRange != initialDateRange) {
          setState(() async {
            _startDate = selectedDateRange.start;
            _endDate = selectedDateRange.end;

            DateTime start = _startDate;
            DateTime end = _endDate;

            String startMonth = DateFormat('MMM').format(start);
            String sdf = DateFormat(
              'MM',
            ).format(start); // converting month into string
            String startDay = DateFormat('dd').format(start);
            int startYear = start.year;

            String endMonth = DateFormat('MMM').format(end);
            String sdfEnd = DateFormat('MM').format(end);
            String endDay = DateFormat('dd').format(end);
            int endYear = end.year;

            startDateString = '$startYear$sdf$startDay';
            endDateString = '$endYear$sdfEnd$endDay';

            startdate_text =
                startDay + "-" + startMonth + "-" + startYear.toString();
            enddate_text = endDay + "-" + endMonth + "-" + endYear.toString();

            print(startDateString);
            print(endDateString);

            fetchDashData(startDateString, endDateString);
          });
        }

        prefs.setString('startdate', startDateString);
        prefs.setString('enddate', endDateString);
      } else {
        if (!_isRefreshing) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text("Swipe Down to Refresh Data")));
        }

        double? sales = prefs.getDouble('sales');
        double? purchase = prefs.getDouble('purchase');
        double? receipt = prefs.getDouble('receipt');
        double? payment = prefs.getDouble('payment');
        double? receivable = prefs.getDouble('receivable');
        double? payable = prefs.getDouble('payable');
        double? cash = prefs.getDouble('cash');

        DateTime start = DateTime.parse(startdate_pref!);
        DateTime end = DateTime.parse(enddate_pref!);

        String startMonth = DateFormat('MMM').format(start);
        String sdf = DateFormat(
          'MM',
        ).format(start); // converting month into string
        String startDay = DateFormat('dd').format(start);
        int startYear = start.year;

        String endMonth = DateFormat('MMM').format(end);
        String sdfEnd = DateFormat('MM').format(end);
        String endDay = DateFormat('dd').format(end);
        int endYear = end.year;

        startDateString = '$startYear$sdf$startDay';
        endDateString = '$endYear$sdfEnd$endDay';

        startdate_text =
            startDay + "-" + startMonth + "-" + startYear.toString();
        enddate_text = endDay + "-" + endMonth + "-" + endYear.toString();

        print(startDateString);
        print(endDateString);

        if (sales != null) {
          sales_value = sales;
          purchase_value = purchase!;
          receipt_value = receipt!;
          payment_value = payment!;
          outstandingreceivable_value = receivable!;
          outstandingpayable_value = payable!;
          cash_value = cash!;
        }
        */
/*fetchDashData(startDateString,endDateString);*//*


        prefs.setString('startdate', startDateString);
        prefs.setString('enddate', endDateString);
      }
    }
  }

  Future<void> _selectDateRange(BuildContext context) async {
    if (_isTextEnabled) {
      startdate_pref = prefs.getString('startdate');
      enddate_pref = prefs.getString('enddate');

      if (startdate_pref == null ||
          enddate_pref == null ||
          startdate_pref == "") {
        startdate_pref = prefs.getString('startfrom')!;

        final initialDateRange = DateTimeRange(
          start: _startDate,
          end: _endDate,
        );
        String? startfrom = startdate_pref;
        DateTime earliestDate = DateTime.parse(startfrom!);

        DateTimeRange? selectedDateRange = await showDateRangePicker(
          context: context,
          initialDateRange: initialDateRange,
          firstDate: earliestDate,
          lastDate: DateTime(2100),
          builder: (BuildContext context, Widget? child) {
            return Theme(
              data: Theme.of(context).copyWith(
                colorScheme: Theme.of(context).colorScheme.copyWith(
                  primary: app_color, // main accent color
                  onPrimary: Colors.white,
                  surface: Theme.of(context).colorScheme.surface,
                  onSurface: Theme.of(context).colorScheme.onSurface,
                ),
                datePickerTheme: DatePickerThemeData(
                  backgroundColor: Theme.of(
                    context,
                  ).scaffoldBackgroundColor, // 🔹 THIS fixes the picker bg
                  surfaceTintColor:
                      Colors.white, // 🔹 prevents grey tint (Material 3)
                  rangeSelectionBackgroundColor: app_color.withOpacity(0.15),
                  rangeSelectionOverlayColor: MaterialStatePropertyAll(
                    app_color.withOpacity(0.15),
                  ),
                ),
                dialogTheme: DialogThemeData(
                  backgroundColor: Theme.of(context).colorScheme.surface,
                ),
                dialogBackgroundColor: Colors.white, // 🔹 important
              ),
              child: child!,
            );
          },
        );

        if (selectedDateRange != null &&
            selectedDateRange != initialDateRange) {
          setState(() async {
            _startDate = selectedDateRange.start;
            _endDate = selectedDateRange.end;

            DateTime start = _startDate;
            DateTime end = _endDate;

            String startMonth = DateFormat('MMM').format(start);
            String sdf = DateFormat(
              'MM',
            ).format(start); // converting month into string
            String startDay = DateFormat('dd').format(start);
            int startYear = start.year;

            String endMonth = DateFormat('MMM').format(end);
            String sdfEnd = DateFormat('MM').format(end);
            String endDay = DateFormat('dd').format(end);
            int endYear = end.year;

            startDateString = '$startYear$sdf$startDay';
            endDateString = '$endYear$sdfEnd$endDay';

            startdate_text =
                startDay + "-" + startMonth + "-" + startYear.toString();
            enddate_text = endDay + "-" + endMonth + "-" + endYear.toString();

            print(startDateString);
            print(endDateString);

            fetchDashData(startDateString, endDateString);
          });
        }

        prefs.setString('startdate', startDateString);
        prefs.setString('enddate', endDateString);
      } else {
        */
/*String? sales = prefs.getString('sales');
        String? purchase = prefs.getString('purchase');
        String? receipt = prefs.getString('receipt');
        String? payment = prefs.getString('payment');
        String? receivable = prefs.getString('receivable');
        String? payable = prefs.getString('payable');
        String? cash = prefs.getString('cash');*//*


        _startDate = DateTime.parse(startdate_pref!);
        _endDate = DateTime.parse(enddate_pref!);
        final initialDateRange = DateTimeRange(
          start: _startDate,
          end: _endDate,
        );
        String? startfrom = prefs.getString('startfrom');
        DateTime earliestDate = DateTime.parse(startfrom!);

        DateTimeRange? selectedDateRange = await showDateRangePicker(
          context: context,
          initialDateRange: initialDateRange,
          firstDate: earliestDate,
          lastDate: DateTime(2100),
          builder: (BuildContext context, Widget? child) {
            return Theme(
              data: Theme.of(context).copyWith(
                colorScheme: Theme.of(context).colorScheme.copyWith(
                  primary: app_color, // main accent color
                  onPrimary: Colors.white,
                  surface: Theme.of(context).colorScheme.surface,
                  onSurface: Theme.of(context).colorScheme.onSurface,
                ),
                datePickerTheme: DatePickerThemeData(
                  backgroundColor: Theme.of(
                    context,
                  ).scaffoldBackgroundColor, // 🔹 THIS fixes the picker bg
                  surfaceTintColor:
                      Colors.white, // 🔹 prevents grey tint (Material 3)
                  rangeSelectionBackgroundColor: app_color.withOpacity(0.15),
                  rangeSelectionOverlayColor: WidgetStatePropertyAll(
                    app_color.withOpacity(0.15),
                  ),
                ),
                dialogTheme: DialogThemeData(
                  backgroundColor: Theme.of(context).colorScheme.surface,
                ),
                dialogBackgroundColor: Colors.white, // 🔹 important
              ),
              child: child!,
            );
          },
        );

        if (selectedDateRange != null) {
          setState(() async {
            _startDate = selectedDateRange.start;
            _endDate = selectedDateRange.end;

            DateTime start = _startDate;
            DateTime end = _endDate;

            String startMonth = DateFormat('MMM').format(start);
            String sdf = DateFormat(
              'MM',
            ).format(start); // converting month into string
            String startDay = DateFormat('dd').format(start);
            int startYear = start.year;

            String endMonth = DateFormat('MMM').format(end);
            String sdfEnd = DateFormat('MM').format(end);
            String endDay = DateFormat('dd').format(end);
            int endYear = end.year;

            startDateString = '$startYear$sdf$startDay';
            endDateString = '$endYear$sdfEnd$endDay';

            startdate_text =
                startDay + "-" + startMonth + "-" + startYear.toString();
            enddate_text = endDay + "-" + endMonth + "-" + endYear.toString();

            */
/*if(sales!=null)
              {
                sales_value = sales;
                purchase_value = purchase!;
                receipt_value = receipt!;
                payment_value = payment!;
                outstandingreceivable_value = receivable!;
                outstandingpayable_value = payable!;
                cash_value = cash!;
              }*//*

            fetchDashData(startDateString, endDateString);
          });
        }

        prefs.setString('startdate', startDateString);
        prefs.setString('enddate', endDateString);
      }
    }
  }

  Future<void> fetchUserData(
    String username,
    String serial_no,
    String secbtn,
  ) async {
    final url = Uri.parse('$BASE_URL_config/api/login/get');

    Map<String, String> headers = {
      'Authorization': 'Bearer $authTokenBase',
      "Content-Type": "application/json",
    };

    var body = jsonEncode({
      'serialno': serial_no,
      'username': username,
      'admin': secbtn,
    });

    final response = await http.post(url, body: body, headers: headers);

    if (response.statusCode == 200) {
      final user_data = jsonDecode(utf8.decode(response.bodyBytes));

      if (user_data != null) {
        List<dynamic> myArray = user_data;

        for (int i = 0; i < myArray.length; i++) {
          if (SecuritybtnAcessHolder == "True") {
            setState(() {
              email = myArray[i]['email'];
              name = myArray[i]['name'];
            });
          } else if (SecuritybtnAcessHolder == "False") {
            setState(() {
              name = myArray[i]["customer_name"];
              email = myArray[i]["user_name"];
            });
          }
        }
        prefs.setString('name_nav', name);
        prefs.setString('email_nav', email);
      } else {
        prefs.remove('name_nav');
        prefs.remove('email_nav');
        throw Exception('Failed to fetch data');
      }
    } else {
      Map<String, dynamic> data = json.decode(utf8.decode(response.bodyBytes));
      String error = '';

      if (data.containsKey('error')) {
        setState(() {
          error = data['error'];
        });
      } else {
        error = "Something went wrong!!!";
      }
      Fluttertoast.showToast(msg: error);
    }
  }

  Future<void> _initSharedPreferences() async {
    prefs = await SharedPreferences.getInstance();

    hostname = prefs.getString('hostname');
    company = prefs.getString('company_name');
    company_lowercase = company!.replaceAll(' ', '').toLowerCase();
    serial_no = prefs.getString('serial_no');
    username = prefs.getString('username');
    license_expiry = prefs.getString('license_expiry');
    token = prefs.getString('token')!;
    base_currency = prefs.getString('base_currency')!;

    _loadNumberScale();

    print('base_currency -> $base_currency');
    SalesEntryHolder = prefs.getString('salesentry') ?? "False";
    ReceiptEntryHolder = prefs.getString('receiptentry') ?? "False";
    SalesOrderEntryHolder = prefs.getString('salesorderentry') ?? "True";
    DeliveryNoteEntryHolder = prefs.getString('deliverynoteentry') ?? "True";

    _selecteddate = prefs.getString('dateRangeOption') ?? 'Today';

    print('selected date option -> $_selecteddate');

    decimal = prefs.getInt('decimalplace') ?? 2;

    if (SalesEntryHolder == 'False') {
      isSalesEntryVisible = false;
    } else if (SalesEntryHolder == 'True') {
      isSalesEntryVisible = true;
    }

    if (ReceiptEntryHolder == 'False') {
      isReceiptEntryVisible = false;
    } else if (ReceiptEntryHolder == 'True') {
      isReceiptEntryVisible = true;
    }

    if (SalesOrderEntryHolder == 'False') {
      isSalesOrderEntryVisible = false;
    } else if (SalesOrderEntryHolder == 'True') {
      isSalesOrderEntryVisible = true;
    }
    if (DeliveryNoteEntryHolder == 'False') {
      isDeliveryNoteEntryVisible = false;
    } else if (DeliveryNoteEntryHolder == 'True') {
      isDeliveryNoteEntryVisible = true;
    }

    */
/*print('token : $token');
    print('hostname : $hostname');*//*


    expire_date = DateTime.parse(license_expiry!);
    isExpired = DateTime.now().isAfter(expire_date!);

    tickerProvider = this;

    String? currencyCode = '';

    String? salesdash = prefs.getString("salesdash") ?? 'False';
    String? purchasedash = prefs.getString("purchasedash") ?? 'False';
    barchartdashprefs = prefs.getString("barchartdash") ?? 'False';
    linechartdashprefs = prefs.getString("linechartdash") ?? 'False';
    piechartdashprefs = prefs.getString("piechartdash") ?? 'False';

    String? receivabledash =
        prefs.getString("outstandingreceivabledash") ?? 'False';
    String? payabledash = prefs.getString("outstandingpayabledash") ?? 'False';
    String? cashdash = prefs.getString("cashdash") ?? 'False';
    String? receiptdash = prefs.getString("receiptsdash") ?? 'False';
    String? paymentdash = prefs.getString("paymentsdash") ?? 'False';

    String allitemsaccess = prefs.getString("allitems") ?? 'False';
    String fastmovingitemsaccess = prefs.getString("activeitems") ?? 'False';
    String inactiveitemsaccess = prefs.getString("inactiveitems") ?? 'False';

    salesparty = prefs.getString("salesparty") ?? 'False';
    purchaseparty = prefs.getString("purchaseparty") ?? 'False';
    creditnoteparty = prefs.getString("creditnoteparty") ?? 'False';
    journalparty = prefs.getString("journalparty") ?? 'False';
    payableparty = prefs.getString("payableparty") ?? 'False';
    pendingpurchaseorderparty =
        prefs.getString("pendingpurchaseorderparty") ?? 'False';
    receiptparty = prefs.getString("receiptparty") ?? 'False';
    paymentparty = prefs.getString("paymentparty") ?? 'False';
    debitnoteparty = prefs.getString("debitnoteparty") ?? 'False';
    receivableparty = prefs.getString("receivableparty") ?? 'False';
    pendingsalesorderparty =
        prefs.getString("pendingsalesorderparty") ?? 'False';
    party_suppliers = prefs.getString("party_suppliers") ?? 'False';
    party_customers = prefs.getString("party_customers") ?? 'False';

    ledgerentries = prefs.getString("ledgerentries") ?? 'False';
    inventoryentries = prefs.getString("inventoryentries") ?? 'False';
    billsentries = prefs.getString("billsentries") ?? 'False';
    costcentreentries = prefs.getString("costcentreentries") ?? 'False';

    if (ledgerentries == 'False' &&
        inventoryentries == 'False' &&
        billsentries == 'False' &&
        costcentreentries == 'False') {
      isVisibleTransactionBtn = false;
    } else {
      isVisibleTransactionBtn = true;
    }

    if (!isReceiptEntryVisible &&
        !isSalesEntryVisible &&
        !isSalesOrderEntryVisible) {
      isVisibleEntriesBtn = false;
    } else {
      isVisibleEntriesBtn = true;
    }

    if (party_suppliers == 'False' && party_customers == 'False') {
      isVisiblePartyBtn = false;
    } else {
      if (salesparty == 'False' &&
          purchaseparty == 'False' &&
          receiptparty == 'False' &&
          paymentparty == 'False' &&
          creditnoteparty == 'False' &&
          debitnoteparty == 'False' &&
          journalparty == 'False' &&
          receivableparty == 'False' &&
          payableparty == 'False' &&
          pendingsalesorderparty == 'False' &&
          pendingpurchaseorderparty == 'False') {
        isVisiblePartyBtn = false;
      } else {
        isVisiblePartyBtn = true;
      }
    }

    if (allitemsaccess == 'True' ||
        fastmovingitemsaccess == 'True' ||
        inactiveitemsaccess == 'True') {
      isVisibleItemBtn = true;
    } else {
      isVisibleItemBtn = false;
    }

    if (salesdash == 'True') {
      sales_visiblity = true;
    } else {
      sales_visiblity = false;
    }

    if (purchasedash == 'True') {
      purchase_visibility = true;
    } else {
      purchase_visibility = false;
    }
    if (receiptdash == 'True') {
      receipt_visibility = true;
    } else {
      receipt_visibility = false;
    }
    if (paymentdash == 'True') {
      payment_visibility = true;
    } else {
      payment_visibility = false;
    }
    if (receivabledash == 'True') {
      receivable_visibility = true;
    } else {
      receivable_visibility = false;
    }
    if (payabledash == 'True') {
      payable_visibility = true;
    } else {
      payable_visibility = false;
    }
    if (cashdash == 'True') {
      cash_visibility = true;
    } else {
      cash_visibility = false;
    }

    if (!sales_visiblity &&
        !purchase_visibility &&
        !receipt_visibility &&
        !payment_visibility &&
        !receivable_visibility &&
        !payable_visibility &&
        !cash_visibility &&
        !isBarChartVisible &&
        !isVisibleLineChart &&
        !isPieChartVisible) {
      isVisibleNoAccess = true;
      isVisibleDate = false;
    } else {
      isVisibleNoAccess = false;
      isVisibleDate = true;
    }

    try {
      currencyCode = prefs.getString('currencycode') ?? "AED";
    } catch (e) {
      if (currencyCode == null) {
        currencyCode = 'AED';
      }
    }
    currencyFormat = new NumberFormat();

    try {
      if (currencyCode == 'INR' ||
          currencyCode == 'EUR' ||
          currencyCode == 'USD' ||
          currencyCode == 'PKR') {
        currencyFormat = NumberFormat('#,##0');
        NumberFormat format = NumberFormat.simpleCurrency(
          locale: 'en',
          name: currencyCode,
        );
        currencysymbol = format.currencySymbol;
      } else {
        NumberFormat format = NumberFormat.currency(
          locale: 'en',
          name: currencyCode,
        );
        currencysymbol = format.currencySymbol;
        currencyFormat = NumberFormat('#,##0');
      }
    } catch (e) {
      NumberFormat format = NumberFormat.currency(
        locale: 'en',
        name: currencyCode,
      );
      currencysymbol = format.currencySymbol;
      currencyFormat = NumberFormat('#,##0');
    }

    // String default_value = currencyFormat.format(0) + " CR";
    sales_value = 0.0;
    purchase_value = 0.0;
    receipt_value = 0.0;
    payment_value = 0.0;
    outstandingpayable_value = 0.0;
    outstandingreceivable_value = 0.0;
    cash_value = 0.0;

    HttpURL =
        hostname! +
        "/api/dashboard/home/" +
        company_lowercase! +
        "/" +
        serial_no!;
    HttpURL_charts =
        hostname! +
        "/api/dashboard/chart/" +
        company_lowercase! +
        "/" +
        serial_no!;
    HttpURL_piecharts =
        hostname! +
        "/api/dashboard/piechart/" +
        company_lowercase! +
        "/" +
        serial_no!;

    SecuritybtnAcessHolder = prefs.getString('secbtnaccess');

    String? email_nav = prefs.getString('email_nav');
    String? name_nav = prefs.getString('name_nav');

    if (email_nav != null && name_nav != null) {
      name = name_nav;
      email = email_nav;
    } else {
      String val = "";
      if (SecuritybtnAcessHolder == "True") {
        val = SecuritybtnAcessHolder!;
      } else if (SecuritybtnAcessHolder == "False") {
        val = "";
      }
      fetchUserData(username!, serial_no!, val);
    }
    if (SecuritybtnAcessHolder == "True") {
      isRolesVisible = true;
      isUserVisible = true;
    } else {
      isRolesVisible = false;
      isUserVisible = false;
    }
    datetype = prefs.getString('datetype');
    if (datetype != null) {
      _handleDate(datetype!);
    } else {
      _handleDate(_selecteddate);
    }
  }

  void _handleDate(String value) async {
    setState(() {
      _selecteddate = value;
    });

    if (_selecteddate == "Today") {
      DateTime currentDate = DateTime.now();
      String startMonth = DateFormat('MMM').format(currentDate);
      String sdf = DateFormat(
        'MM',
      ).format(currentDate); // converting month into string

      String startDay = DateFormat('dd').format(currentDate);
      int startYear = currentDate.year;

      String endMonth = DateFormat('MMM').format(currentDate);
      String sdfEnd = DateFormat('MM').format(currentDate);

      String endDay = DateFormat('dd').format(currentDate);
      int endYear = currentDate.year;

      startDateString = "$startYear$sdf$startDay";
      endDateString = "$endYear$sdfEnd$endDay";
      print(startDateString);
      print(endDateString);

      fetchDashData(startDateString, endDateString);

      setState(() {
        _isTextEnabled = false;
        _isDashVisible = false;
        _isEnddateVisible = false;
        _IsSizeboxVisible = false;
      });

      startdate_text = startDay + "-" + startMonth + "-" + startYear.toString();
      enddate_text = endDay + "-" + endMonth + "-" + endYear.toString();
    } else if (_selecteddate == "Year To Date") {
      DateTime now = DateTime.now();
      DateTime startDate = DateTime(
        now.year,
        1,
        1,
      ); // Start of the current year
      DateTime endDate = DateTime(now.year, now.month, now.day); // Today's date

      DateFormat dateFormat = DateFormat("dd-MMM-yyyy");

      String startMonth = dateFormat.format(startDate).substring(3, 6);
      String sdf = DateFormat('MM').format(startDate);

      String startDay = dateFormat.format(startDate).substring(0, 2);
      int startYear = startDate.year;

      String endMonth = dateFormat.format(endDate).substring(3, 6);
      String sdfEnd = DateFormat('MM').format(endDate);

      String endDay = dateFormat.format(endDate).substring(0, 2);
      int endYear = endDate.year;

      startDateString = "$startYear$sdf$startDay";
      endDateString = "$endYear$sdfEnd$endDay";
      print(startDateString);
      print(endDateString);

      startdate_text = startDay + "-" + startMonth + "-" + startYear.toString();
      enddate_text = endDay + "-" + endMonth + "-" + endYear.toString();

      fetchDashData(startDateString, endDateString);

      setState(() {
        _isTextEnabled = false;

        _isDashVisible = true;
        _isEnddateVisible = true;
        _IsSizeboxVisible = true;
      });
    } else if (_selecteddate == "Yesterday") {
      DateTime yesterday = DateTime.now().subtract(Duration(days: 1));
      DateFormat dateFormat = DateFormat("dd-MMM-yyyy");

      String startMonth = dateFormat.format(yesterday).substring(3, 6);
      String sdf = DateFormat(
        'MM',
      ).format(yesterday); // converting month into string

      String startDay = dateFormat.format(yesterday).substring(0, 2);
      int startYear = yesterday.year;

      String endMonth = dateFormat.format(yesterday).substring(3, 6);
      String sdfEnd = DateFormat('MM').format(yesterday);

      String endDay = dateFormat.format(yesterday).substring(0, 2);
      int endYear = yesterday.year;

      startDateString = "$startYear$sdf$startDay";
      endDateString = "$endYear$sdfEnd$endDay";
      print(startDateString);
      print(endDateString);

      startdate_text = startDay + "-" + startMonth + "-" + startYear.toString();
      enddate_text = endDay + "-" + endMonth + "-" + endYear.toString();

      fetchDashData(startDateString, endDateString);

      setState(() {
        _isTextEnabled = false;
        _isDashVisible = false;
        _isEnddateVisible = false;
        _IsSizeboxVisible = false;
      });
    } else if (_selecteddate == "This Month") {
      DateTime now = DateTime.now();
      DateTime startOfMonth = DateTime(now.year, now.month, 1);
      DateTime endOfMonth = DateTime(now.year, now.month + 1, 0);

      String startMonth = DateFormat('MMM').format(startOfMonth);
      String sdf = DateFormat(
        'MM',
      ).format(startOfMonth); // converting month into string
      String startDay = DateFormat('dd').format(startOfMonth);
      int startYear = startOfMonth.year;

      String endMonth = DateFormat('MMM').format(endOfMonth);
      String sdfEnd = DateFormat('MM').format(endOfMonth);
      String endDay = DateFormat('dd').format(endOfMonth);
      int endYear = endOfMonth.year;

      startDateString = '$startYear$sdf$startDay';
      endDateString = '$endYear$sdfEnd$endDay';

      startdate_text = startDay + "-" + startMonth + "-" + startYear.toString();
      enddate_text = endDay + "-" + endMonth + "-" + endYear.toString();

      print(startDateString);
      print(endDateString);

      fetchDashData(startDateString, endDateString);

      setState(() {
        _isTextEnabled = false;
        _isDashVisible = true;
        _isEnddateVisible = true;
        _IsSizeboxVisible = true;
      });
    } else if (_selecteddate == "Last Month") {
      var calendarLastMonthStart = DateTime.now();
      var calendarLastMonthEnd = DateTime.now();

      calendarLastMonthStart = DateTime(
        calendarLastMonthStart.year,
        calendarLastMonthStart.month - 1,
        1,
      );

      calendarLastMonthStart = DateTime(
        calendarLastMonthStart.year,
        calendarLastMonthStart.month,
        1,
      );
      calendarLastMonthEnd = DateTime(
        calendarLastMonthStart.year,
        calendarLastMonthStart.month + 1,
        0,
      );

      var startMonth = DateFormat('MMM').format(calendarLastMonthStart);
      var sdf = DateFormat('MM').format(calendarLastMonthStart);
      var startDay = DateFormat('dd').format(calendarLastMonthStart);
      var startYear = calendarLastMonthStart.year;

      var endMonth = DateFormat('MMM').format(calendarLastMonthEnd);
      var sdfEnd = DateFormat('MM').format(calendarLastMonthEnd);
      var endDay = DateFormat('dd').format(calendarLastMonthEnd);
      var endYear = calendarLastMonthEnd.year;

      startDateString = '$startYear$sdf$startDay';
      endDateString = '$endYear$sdfEnd$endDay';

      startdate_text = startDay + "-" + startMonth + "-" + startYear.toString();
      enddate_text = endDay + "-" + endMonth + "-" + endYear.toString();

      print(startDateString);
      print(endDateString);

      fetchDashData(startDateString, endDateString);

      setState(() {
        _isTextEnabled = false;

        _isDashVisible = true;
        _isEnddateVisible = true;
        _IsSizeboxVisible = true;
      });
    } else if (_selecteddate == "This Year") {
      DateTime today = DateTime.now();
      DateTime yearStart = DateTime(today.year, 1, 1);
      DateTime yearEnd = DateTime(today.year, 12, 31);

      String startMonth = DateFormat('MMM').format(yearStart);
      String sdf = DateFormat(
        'MM',
      ).format(yearStart); // converting month into string
      String startDay = DateFormat('dd').format(yearStart);
      String startYear = DateFormat('yyyy').format(yearStart);

      String endMonth = DateFormat('MMM').format(yearEnd);
      String sdfEnd = DateFormat('MM').format(yearEnd);
      String endDay = DateFormat('dd').format(yearEnd);
      String endYear = DateFormat('yyyy').format(yearEnd);

      startDateString = '$startYear$sdf$startDay';
      endDateString = '$endYear$sdfEnd$endDay';

      startdate_text = startDay + "-" + startMonth + "-" + startYear.toString();
      enddate_text = endDay + "-" + endMonth + "-" + endYear.toString();

      print(startDateString);
      print(endDateString);

      fetchDashData(startDateString, endDateString);

      setState(() {
        _isTextEnabled = false;

        _isDashVisible = true;
        _isEnddateVisible = true;
        _IsSizeboxVisible = true;
      });
    } else if (_selecteddate == "Last Year") {
      DateTime today = DateTime.now();
      DateTime yearStart = DateTime(today.year - 1, 1, 1);
      DateTime yearEnd = DateTime(today.year - 1, 12, 31);

      String startMonth = DateFormat('MMM').format(yearStart);
      String sdf = DateFormat(
        'MM',
      ).format(yearStart); // converting month into string
      String startDay = DateFormat('dd').format(yearStart);
      String startYear = DateFormat('yyyy').format(yearStart);

      String endMonth = DateFormat('MMM').format(yearEnd);
      String sdfEnd = DateFormat('MM').format(yearEnd);
      String endDay = DateFormat('dd').format(yearEnd);
      String endYear = DateFormat('yyyy').format(yearEnd);

      startdate_text = startDay + "-" + startMonth + "-" + startYear.toString();
      enddate_text = endDay + "-" + endMonth + "-" + endYear.toString();

      startDateString = '$startYear$sdf$startDay';
      endDateString = '$endYear$sdfEnd$endDay';

      print(startDateString);
      print(endDateString);

      fetchDashData(startDateString, endDateString);

      setState(() {
        _isTextEnabled = false;

        _isDashVisible = true;
        _isEnddateVisible = true;
        _IsSizeboxVisible = true;
      });
    } else if (_selecteddate == "Custom Date") {
      setState(() {
        _isTextEnabled = true;

        _isDashVisible = true;
        _isEnddateVisible = true;
        _IsSizeboxVisible = true;
      });

      _selectDateRange_auto(context);
    }
    prefs.setString('datetype', _selecteddate);
  }

  @override
  void initState() {
    super.initState();

    _scaffoldMessengerKey = GlobalKey<ScaffoldMessengerState>();

    _initSharedPreferences();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      checkCurrencyMismatch(context);
    });
  }

  Future<void> _loadNumberScale() async {
    String? scale = prefs.getString("number_scale");
    if (scale != null) {
      switch (scale) {
        case "thousand":
          _selectedScale = NumberScale.thousand;
          break;
        case "million":
          _selectedScale = NumberScale.million;
          break;
        case "billion":
          _selectedScale = NumberScale.billion;
          break;
        case "full":
          _selectedScale = NumberScale.full;
          break;

        default:
          _selectedScale = NumberScale.thousand;
      }
    }
    setState(() {});
  }

  Future<void> _saveNumberScale(NumberScale scale) async {
    _selectedScale = scale;
    switch (scale) {
      case NumberScale.thousand:
        prefs.setString("number_scale", "thousand");
        break;
      case NumberScale.million:
        prefs.setString("number_scale", "million");
        break;
      case NumberScale.billion:
        prefs.setString("number_scale", "billion");
        break;
      case NumberScale.full:
        prefs.setString("number_scale", "full");
        break;
      default:
        prefs.setString("number_scale", "thousand");
    }
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final Map<int, Color> yearColors = {};

    return WillPopScope(
      onWillPop: () async {
        _showConfirmationDialogAndExit(context);
        return true;
      },
      child: Scaffold(
        backgroundColor: Theme.of(context).cardColor,
        key: _scaffoldKey,
        appBar: PreferredSize(
          preferredSize: Size.fromHeight(50),
          child: AppBar(
            backgroundColor: app_color,
            elevation: 6,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.vertical(bottom: Radius.circular(20)),
            ),
            automaticallyImplyLeading: false,
            */
/*leading: IconButton(
                icon: Icon(Icons.menu, color: Colors.white),
                onPressed: () {
                  _scaffoldKey.currentState!.openDrawer();
                },
              ),*//*

            centerTitle: true,
            title: GestureDetector(
              onTap: () {
                Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(builder: (context) => SerialSelect()),
                );
              },
              child: Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Flexible(
                    child: Text(
                      company ?? '',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      softWrap: false,
                      style: GoogleFonts.poppins(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  const Icon(Icons.arrow_drop_down, color: Colors.white),
                ],
              ),
            ),
          ),
        ),

        */
/*drawer: Sidebar(
              isDashEnable: isDashEnable,
              isRolesVisible: isRolesVisible,
              isRolesEnable: isRolesEnable,
              isUserEnable: isUserEnable,
              isUserVisible: isUserVisible,
              Username: name,
              Email: email,
              tickerProvider: this),*//*

        // add the Sidebar widget here
        bottomNavigationBar: const AppBottomNav(
          activeTab: AppBottomNavTab.dashboard,
          activeMoreItem: AppMoreItem.dashboard,
        ),

        body: Stack(
          children: [
            SingleChildScrollView(
              child: RefreshIndicator(
                onRefresh: _handleRefresh,
                child: Center(
                  child: Column(
                    children: [
                      Container(
                        margin: EdgeInsets.only(
                          left: 16,
                          right: 16,
                          bottom: 0,
                          top: 10,
                        ),
                        padding: EdgeInsets.all(0),
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
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (isVisibleDate)
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [buildDateFilterCard(context)],
                              ),
                          ],
                        ),
                      ),

                      GridView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        gridDelegate:
                            const SliverGridDelegateWithMaxCrossAxisExtent(
                              maxCrossAxisExtent: 220,
                              childAspectRatio: 1.3,
                              crossAxisSpacing: 8,
                              mainAxisSpacing: 8,
                            ),
                        itemCount: [
                          if (sales_visiblity) 1 else 0,
                          if (purchase_visibility) 1 else 0,
                          if (receipt_visibility) 1 else 0,
                          if (payment_visibility) 1 else 0,
                          if (receivable_visibility) 1 else 0,
                          if (payable_visibility) 1 else 0,
                          if (cash_visibility) 1 else 0,
                        ].where((e) => e == 1).length,
                        itemBuilder: (context, index) {
                          final items = <Widget>[
                            if (sales_visiblity)
                              _buildDecentCard(
                                context,
                                "Sales - Credit Note",
                                "$currencysymbol ${formatNumberAbbreviation(sales_value, decimalPlaces: decimal!, scale: _selectedScale, showSuffix: true)}",
                                "sales", // 👈 type auto handle karega
                                () {
                                  vchtype = "Sales";
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (context) => DashboardClicked(
                                        startdate_string: startDateString,
                                        enddate_string: endDateString,
                                        vchtypes: vchtype,
                                      ),
                                    ),
                                  );
                                },
                              ),

                            if (purchase_visibility)
                              _buildDecentCard(
                                context,
                                "Purchase - Debit Note",
                                "$currencysymbol ${formatNumberAbbreviation(purchase_value, decimalPlaces: decimal!, scale: _selectedScale, showSuffix: true)}",
                                "purchase",
                                () {
                                  vchtype = "Purchase";
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (context) => DashboardClicked(
                                        startdate_string: startDateString,
                                        enddate_string: endDateString,
                                        vchtypes: vchtype,
                                      ),
                                    ),
                                  );
                                },
                              ),

                            if (receipt_visibility)
                              _buildDecentCard(
                                context,
                                "Receipt",
                                "$currencysymbol ${formatNumberAbbreviation(receipt_value, decimalPlaces: decimal!, scale: _selectedScale, showSuffix: true)}",
                                "receipt",
                                () {
                                  vchtype = "Receipt";
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (context) => DashboardClicked(
                                        startdate_string: startDateString,
                                        enddate_string: endDateString,
                                        vchtypes: vchtype,
                                      ),
                                    ),
                                  );
                                },
                              ),

                            if (payment_visibility)
                              _buildDecentCard(
                                context,
                                "Payment",
                                "$currencysymbol ${formatNumberAbbreviation(payment_value, decimalPlaces: decimal!, scale: _selectedScale, showSuffix: true)}",
                                "payment",
                                () {
                                  vchtype = "Payment";
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (context) => DashboardClicked(
                                        startdate_string: startDateString,
                                        enddate_string: endDateString,
                                        vchtypes: vchtype,
                                      ),
                                    ),
                                  );
                                },
                              ),

                            if (receivable_visibility)
                              _buildDecentCard(
                                context,
                                "Outstanding Receivable",
                                "$currencysymbol ${formatNumberAbbreviation(outstandingreceivable_value, decimalPlaces: decimal!, scale: _selectedScale, showSuffix: true)}",
                                "receivable",
                                () {
                                  vchtype = "Receivable";
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (context) => DashboardClicked(
                                        startdate_string: startDateString,
                                        enddate_string: endDateString,
                                        vchtypes: vchtype,
                                      ),
                                    ),
                                  );
                                },
                              ),

                            if (payable_visibility)
                              _buildDecentCard(
                                context,
                                "Outstanding Payable",
                                "$currencysymbol ${formatNumberAbbreviation(outstandingpayable_value, decimalPlaces: decimal!, scale: _selectedScale, showSuffix: true)}",
                                "payable",
                                () {
                                  vchtype = "Payable";
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (context) => DashboardClicked(
                                        startdate_string: startDateString,
                                        enddate_string: endDateString,
                                        vchtypes: vchtype,
                                      ),
                                    ),
                                  );
                                },
                              ),

                            if (cash_visibility)
                              _buildDecentCard(
                                context,
                                "Cash / Bank Balance",
                                "$currencysymbol ${formatNumberAbbreviation(cash_value, decimalPlaces: decimal!, scale: _selectedScale, showSuffix: true)}",
                                "Cash", // type (for icon + gradient auto handle)
                                () {
                                  vchtype = "Cash";
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (context) => DashboardClicked(
                                        startdate_string: startDateString,
                                        enddate_string: endDateString,
                                        vchtypes: vchtype,
                                      ),
                                    ),
                                  );
                                },
                              ),
                          ];

                          return items[index];
                        },
                      ),

                      Align(
                        alignment: Alignment.topLeft,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (isVisibleLineChart || isPieChartVisible)
                              GestureDetector(
                                onTap: () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => AnalyticsScreen(
                                        lineChartData: data,
                                        months: months_chart_line_graph,
                                        yearColors: yearColors,
                                        pieSalesList: piechartsaleslist
                                            .cast<Map<String, dynamic>>(),
                                        piePurchaseList: piechartpurchaselist
                                            .cast<Map<String, dynamic>>(),
                                        isVisibleLineChart: isVisibleLineChart,
                                        decimalPlaces: decimal!,
                                        isVisiblePieChart: isPieChartVisible,
                                        isSalesPieChartVisible:
                                            isSalesPieChartVisible,
                                        isPurchasePieChartVisible:
                                            isPurchasePieChartVisible,
                                        isBarChartVisible: isBarChartVisible,
                                        salesDataList: salesDataList,
                                        recDataList: recDataList,
                                        selectedScale: _selectedScale,
                                        startDateString: startDateString,
                                        endDateString: endDateString,
                                      ),
                                    ),
                                  );
                                },
                                child: Container(
                                  margin: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                    vertical: 8,
                                  ),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 18,
                                    vertical: 16,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Theme.of(context).cardColor,
                                    borderRadius: BorderRadius.circular(18),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black.withOpacity(0.06),
                                        blurRadius: 10,
                                        offset: const Offset(0, 4),
                                      ),
                                    ],
                                  ),
                                  child: Row(
                                    children: [
                                      // 🔹 Gradient Icon Badge
                                      Container(
                                        width: 40,
                                        height: 40,
                                        decoration: BoxDecoration(
                                          gradient: LinearGradient(
                                            colors: [
                                              Colors.red.shade400,
                                              Colors.red.shade700,
                                            ],
                                            begin: Alignment.topLeft,
                                            end: Alignment.bottomRight,
                                          ),
                                          borderRadius: BorderRadius.circular(
                                            12,
                                          ),
                                          boxShadow: [
                                            BoxShadow(
                                              color: Colors.red.withOpacity(
                                                0.2,
                                              ),
                                              blurRadius: 6,
                                              offset: const Offset(0, 3),
                                            ),
                                          ],
                                        ),
                                        child: const Icon(
                                          Icons.analytics_outlined,
                                          color: Colors.white,
                                          size: 22,
                                        ),
                                      ),
                                      const SizedBox(width: 16),

                                      // 🔹 Title
                                      Expanded(
                                        child: Text(
                                          "Analytics",
                                          style: GoogleFonts.poppins(
                                            fontSize: 17,
                                            fontWeight: FontWeight.w600,
                                            color: Theme.of(
                                              context,
                                            ).colorScheme.onSurface,
                                          ),
                                        ),
                                      ),

                                      // 🔹 Arrow
                                      Container(
                                        padding: const EdgeInsets.all(4),
                                        decoration: BoxDecoration(
                                          color:
                                              Theme.of(context).brightness ==
                                                  Brightness.dark
                                              ? Theme.of(context)
                                                    .colorScheme
                                                    .surfaceContainerHighest
                                              : Colors.grey.shade200,
                                          shape: BoxShape.circle,
                                        ),
                                        child: Icon(
                                          Icons.chevron_right_rounded,
                                          color: Theme.of(
                                            context,
                                          ).colorScheme.onSurfaceVariant,
                                          size: 20,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),

                            Visibility(
                              visible: isVisibleNoAccess,
                              child: Container(
                                color: Colors.white,
                                padding: EdgeInsets.only(top: 20.0),
                                child: Center(
                                  child: Text(
                                    'No Access to Dashboard',
                                    style: GoogleFonts.poppins(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 18.0,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

            */
/*Align(
                  alignment: Alignment.centerRight, // stick to right center
                  child: Padding(
                    padding: const EdgeInsets.only(right: 16.0), // distance from right edge
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      mainAxisAlignment: MainAxisAlignment.center, // center vertically
                      children: [
                        if (isVisibleItemBtn)
                          _buildFloatingTile(context, "Items", Icons.inventory_outlined, Colors.blue, () {
                            Navigator.push(context, MaterialPageRoute(builder: (_) => Items()));
                          }),
                        const SizedBox(height: 16),

                        if (isVisiblePartyBtn)
                          _buildFloatingTile(context, "Parties",Icons.groups_outlined, Colors.green, () {
                            Navigator.push(context, MaterialPageRoute(builder: (_) => Party()));
                          }),
                        const SizedBox(height: 16),

                        if (isVisibleTransactionBtn)
                          _buildFloatingTile(context, "Register",Icons.payment_outlined, Colors.orange, () {
                            Navigator.push(context, MaterialPageRoute(builder: (_) => Transactions()));
                          }),
                        const SizedBox(height: 16),

                        if (isVisibleEntriesBtn)
                          _buildFloatingTile(context, "Entries",Icons.receipt_long, Colors.red, () {
                            _showEntriesBottomSheet(context);
                          }),
                      ],
                    ),
                  ),
                ),*//*

            if (isExpired)
              AlertDialog(
                title: Text('License Expired'),
                content: Text('Your license has expired.'),
                actions: <Widget>[
                  TextButton(
                    child: Text('OK'),
                    onPressed: () {
                      // Navigate to another screen when the OK button is pressed
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (context) => SerialSelect()),
                      );
                    },
                  ),
                ],
              ),
            Visibility(
              visible: _isLoading,
              child: Center(child: AppLogoLoader()),
            ),
          ],
        ),

        floatingActionButton: FloatingActionButton(
          backgroundColor: app_color,
          child: const Icon(Icons.tune, color: Colors.white),
          onPressed: () async {
            final RenderBox button = context.findRenderObject() as RenderBox;
            final RenderBox overlay =
                Overlay.of(context).context.findRenderObject() as RenderBox;

            final RelativeRect position = RelativeRect.fromRect(
              Rect.fromPoints(
                button.localToGlobal(
                  button.size.bottomRight(Offset.zero),
                  ancestor: overlay,
                ),
                button.localToGlobal(
                  button.size.bottomRight(Offset.zero),
                  ancestor: overlay,
                ),
              ),
              Offset.zero & overlay.size,
            );

            final result = await showMenu<NumberScale>(
              color: Colors.white,
              context: context,
              position: position,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              items: [
                PopupMenuItem(
                  value: NumberScale.full,
                  child: Row(
                    children: [
                      const Icon(Icons.pin, color: Colors.blue),
                      const SizedBox(width: 8),
                      const Text("Full Value"),
                      if (_selectedScale == NumberScale.full) const Spacer(),
                      if (_selectedScale == NumberScale.full)
                        const Icon(Icons.check, color: Colors.green),
                    ],
                  ),
                ),
                PopupMenuItem(
                  value: NumberScale.thousand,
                  child: Row(
                    children: [
                      const Icon(
                        Icons.format_list_numbered,
                        color: Colors.blue,
                      ),
                      const SizedBox(width: 8),
                      const Text("Thousands (K)"),
                      if (_selectedScale == NumberScale.thousand)
                        const Spacer(),
                      if (_selectedScale == NumberScale.thousand)
                        const Icon(Icons.check, color: Colors.green),
                    ],
                  ),
                ),
                PopupMenuItem(
                  value: NumberScale.million,
                  child: Row(
                    children: [
                      const Icon(
                        Icons.format_list_numbered_rtl,
                        color: Colors.orange,
                      ),
                      const SizedBox(width: 8),
                      const Text("Millions (M)"),
                      if (_selectedScale == NumberScale.million) const Spacer(),
                      if (_selectedScale == NumberScale.million)
                        const Icon(Icons.check, color: Colors.green),
                    ],
                  ),
                ),
                PopupMenuItem(
                  value: NumberScale.billion,
                  child: Row(
                    children: [
                      const Icon(Icons.numbers, color: Colors.purple),
                      const SizedBox(width: 8),
                      const Text("Billions (B)"),
                      if (_selectedScale == NumberScale.billion) const Spacer(),
                      if (_selectedScale == NumberScale.billion)
                        const Icon(Icons.check, color: Colors.green),
                    ],
                  ),
                ),
              ],
            );

            if (result != null) {
              _saveNumberScale(result);
            }
          },
        ),
      ),

      // Empty container if the license is still valid
    );
  }

  Widget buildDateFilterCard(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 4, sigmaY: 4),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 20),

          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              /// Dropdown: Date Range Type
              Container(
                decoration: BoxDecoration(
                  color: Theme.of(context).cardColor.withOpacity(0.7),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Theme.of(context).dividerColor),
                ),
                padding: EdgeInsets.symmetric(horizontal: 14),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<dynamic>(
                    value: _selecteddate,
                    icon: Icon(
                      Icons.arrow_drop_down_rounded,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                    dropdownColor: Theme.of(context)
                        .colorScheme
                        .surface, // 👈 Set dropdown menu background to white
                    borderRadius: BorderRadius.circular(
                      14,
                    ), // 👈 Rounded corners for menu

                    isExpanded: true,
                    style: GoogleFonts.poppins(
                      fontSize: 15,
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                    items: date_range.map((item) {
                      return DropdownMenuItem<dynamic>(
                        value: item,
                        child: Text(
                          item,
                          style: GoogleFonts.poppins(
                            // 👈 Apply Poppins style to menu items
                            fontSize: 15,
                            color: Theme.of(context).colorScheme.onSurface,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      );
                    }).toList(),
                    onChanged: (value) => setState(() => _handleDate(value)),
                  ),
                ),
              ),
              SizedBox(height: 16),

              /// Date Range Picker
              InkWell(
                onTap: () => _selectDateRange(context),
                borderRadius: BorderRadius.circular(14),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 14,
                  ),
                  decoration: BoxDecoration(
                    color: Theme.of(context).cardColor.withOpacity(0.7),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: Theme.of(context).dividerColor),
                  ),
                  child: Row(
                    mainAxisAlignment:
                        MainAxisAlignment.spaceBetween, // equal spacing
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.calendar_today_rounded,
                        size: 18,
                        color: app_color,
                      ),

                      /// Centered Text
                      Expanded(
                        child: Center(
                          child: Text(
                            "$startdate_text - $enddate_text",
                            style: GoogleFonts.poppins(
                              fontSize: 13,
                              color: Theme.of(context).colorScheme.onSurface,
                              fontWeight: FontWeight.w500,
                            ),
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ),

                      Icon(
                        Icons.calendar_today_rounded,
                        size: 18,
                        color: app_color,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget buildButtonTile({
    required String label,
    required String value,
    required IconData icon,
    required bool visible,
    required VoidCallback onTap,
  }) {
    return Visibility(
      visible: visible,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          margin: const EdgeInsets.only(left: 16, right: 16, top: 10),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFFF1FDFB), Color(0xFFE9F6F3)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.teal.shade100.withOpacity(0.6)),
            boxShadow: [
              BoxShadow(
                color: Colors.teal.withOpacity(0.08),
                blurRadius: 14,
                offset: Offset(0, 6),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                padding: EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.teal.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, size: 24, color: Colors.teal),
              ),
              SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      value,
                      style: GoogleFonts.poppins(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      label,
                      style: GoogleFonts.poppins(
                        fontSize: 13.5,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                color: Colors.teal.withOpacity(0.5),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

Widget _buildFloatingTile(
  BuildContext context,
  String label,
  IconData icon,
  Color color,
  VoidCallback onTap,
) {
  return Tooltip(
    message: label,
    child: GestureDetector(
      onTap: onTap,
      child: Material(
        shape: const CircleBorder(),
        elevation: 8,
        shadowColor: Colors.black38,
        color: Theme.of(context).cardColor,
        child: Padding(
          padding: const EdgeInsets.all(14.0),
          child: Icon(icon, color: color, size: 28),
        ),
      ),
    ),
  );
}

Widget _buildDecentCard(
  BuildContext context,
  String label,
  String value,
  String type,
  VoidCallback onTap,
) {
  LinearGradient _getGradient(String type) {
    switch (type.toLowerCase()) {
      case "sales":
        return LinearGradient(
          colors: [Colors.teal.shade400, Colors.teal.shade700],
        );
      case "purchase":
        return LinearGradient(
          colors: [Colors.deepOrange.shade400, Colors.deepOrange.shade700],
        );
      case "receipt":
        return LinearGradient(
          colors: [Colors.green.shade400, Colors.green.shade700],
        );
      case "payment":
        return LinearGradient(
          colors: [Colors.red.shade400, Colors.red.shade700],
        );
      case "receivable":
        return LinearGradient(
          colors: [Colors.indigo.shade400, Colors.indigo.shade700],
        );
      case "payable":
        return LinearGradient(
          colors: [Colors.purple.shade400, Colors.purple.shade700],
        );
      case "cash":
        return LinearGradient(
          colors: [Colors.blueGrey.shade400, Colors.blueGrey.shade700],
        );
      default:
        return LinearGradient(
          colors: [Colors.grey.shade400, Colors.grey.shade600],
        );
    }
  }

  IconData _getIcon(String type) {
    switch (type.toLowerCase()) {
      case "sales":
        return Icons.trending_up;
      case "purchase":
        return Icons.shopping_cart_outlined;
      case "receipt":
        return Icons.receipt_long_outlined;
      case "payment":
        return Icons.payments_outlined;
      case "receivable":
        return Icons.account_balance_wallet_outlined;
      case "payable":
        return Icons.money_off_csred_outlined;
      case "cash":
        return Icons.account_balance_outlined;
      default:
        return Icons.insert_chart_outlined_rounded;
    }
  }

  return GestureDetector(
    onTap: onTap,
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeInOut,
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black12.withOpacity(0.05),
            blurRadius: 6,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 🔹 Gradient Icon
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              gradient: _getGradient(type),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(_getIcon(type), size: 18, color: Colors.white),
          ),
          const Spacer(),
          Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
        ],
      ),
    ),
  );
}
*/
