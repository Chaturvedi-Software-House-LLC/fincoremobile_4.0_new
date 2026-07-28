import 'dart:convert';
import 'dart:io';
import 'dart:ui';
import 'package:FincoreGo/PendingDeliveryNoteEntry.dart';
import 'package:FincoreGo/widgets/app_bottom_nav.dart';
import 'package:flutter/foundation.dart';
import 'package:FincoreGo/DashboardClicked.dart';
import 'package:FincoreGo/PendingReceiptEntry.dart';
import 'package:FincoreGo/PendingSalesEntry.dart';
import 'package:FincoreGo/utils/number_formatter.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'utils/currency_helper.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'DashboardAnalytics.dart';
import 'PendingSalesOrderEntry.dart';
import 'SerialSelect.dart';
import 'constants.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';
import 'widgets/entry_widgets.dart';

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
  double? _salesTrendPercent;
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
  String _currencyCode = 'AED';

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
*/

  late int? decimal = 2;

  NumberScale _selectedScale = NumberScale.thousand;

  void _showEntriesBottomSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      builder: (context) {
        return SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 12, 18, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 42,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 18),
                  decoration: BoxDecoration(
                    color: Theme.of(context).dividerColor,
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),

                Row(
                  children: [
                    Container(
                      width: 46,
                      height: 46,
                      decoration: BoxDecoration(
                        color: app_color.withOpacity(0.10),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Icon(
                        Icons.menu_book_rounded,
                        color: app_color,
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            "Entry Type",
                            style: GoogleFonts.poppins(
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                              color: Theme.of(context).colorScheme.onSurface,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            "Choose the transaction entry you want to continue.",
                            style: GoogleFonts.poppins(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w500,
                              color: Theme.of(
                                context,
                              ).colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      style: IconButton.styleFrom(
                        backgroundColor:
                            Theme.of(context).brightness == Brightness.dark
                            ? Theme.of(
                                context,
                              ).colorScheme.surfaceContainerHighest
                            : const Color(0xFFF1F4F8),
                        foregroundColor: Theme.of(
                          context,
                        ).colorScheme.onSurfaceVariant,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      icon: const Icon(Icons.close_rounded),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
                const SizedBox(height: 18),

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
                        MaterialPageRoute(
                          builder: (_) => PendingReceiptEntry(),
                        ),
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
      borderRadius: BorderRadius.circular(18),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        decoration: BoxDecoration(
          color: Theme.of(context).brightness == Brightness.dark
              ? Theme.of(context).colorScheme.surfaceContainerHighest
              : const Color(0xFFF9FAFC),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: Theme.of(context).dividerColor, width: 1),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.035),
              blurRadius: 12,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: gradient.last.withOpacity(0.11),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: gradient.last, size: 21),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                label,
                style: GoogleFonts.poppins(
                  fontSize: 14.5,
                  fontWeight: FontWeight.w700,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: Theme.of(context).brightness == Brightness.dark
                    ? Theme.of(context).colorScheme.surfaceContainerHighest
                    : const Color(0xFFF1F4F8),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.chevron_right_rounded,
                size: 18,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
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
      /*showProgressDialog_LoadData(context, _isLoading);*/

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

      final dash_data = jsonDecode(response.body);

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
          Map<String, dynamic> data = json.decode(response.body);
          String error = '';

          if (data.containsKey('error')) {
            setState(() {
              error = data['error'];
            });
          } else {
            error = "Error in data fetching!!!";
          }
          showAppMessage(context, error);
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
        showAppMessage(context, error);
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
                /*showProgressDialog_LoadData(context, _isLoading);*/
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

                          /*print(response_charts.body);*/

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

              // Month-over-month trend: only meaningful for ranges anchored
              // to "now" (This Month/This Year/Year To Date), where the last
              // two months in the series really are "this month vs last
              // month". For a fully historical range (Last Year, a past
              // Custom Date range, etc.) the last two months are just some
              // arbitrary past months, and a diff between them isn't what
              // "vs last month" implies to the user - so suppress it there.
              const trendEligibleRanges = {
                'This Month',
                'This Year',
                'Year To Date',
              };
              if (!trendEligibleRanges.contains(_selecteddate)) {
                setState(() {
                  _salesTrendPercent = null;
                });
              } else {
                // salesDataList is stored negated for the chart's bar
                // direction, so undo that before comparing. The selected
                // range can still include a trailing month with no postings
                // yet (the current, still-in-progress month) - blindly
                // diffing the last two array slots against that padding
                // zero produced a bogus "100% down" badge, so skip trailing
                // zero months to find the real latest one.
                int latestIndex = salesDataList.length - 1;
                while (latestIndex >= 0 &&
                    salesDataList[latestIndex].abs() <= 0.0001) {
                  latestIndex--;
                }
                if (latestIndex >= 1) {
                  final latest = salesDataList[latestIndex].abs();
                  final previous = salesDataList[latestIndex - 1].abs();
                  setState(() {
                    _salesTrendPercent = previous > 0.0001
                        ? ((latest - previous) / previous) * 100
                        : null;
                  });
                } else {
                  setState(() {
                    _salesTrendPercent = null;
                  });
                }
              }
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
              showAppMessage(context, error);
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
              showAppMessage(context, error);
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
        showAppMessage(context, e.toString());
      }

      setState(() {
        _isLoading = false;
      });
      /*showProgressDialog_LoadData(context, _isLoading);*/
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
                  surfaceTintColor: Colors.transparent,
                  rangeSelectionBackgroundColor: app_color.withOpacity(0.15),
                  rangeSelectionOverlayColor: MaterialStatePropertyAll(
                    app_color.withOpacity(0.15),
                  ),
                ),
                dialogTheme: DialogThemeData(
                  backgroundColor: Theme.of(context).colorScheme.surface,
                ),
                dialogBackgroundColor: Theme.of(context).colorScheme.surface,
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
          showAppMessage(context, "Swipe Down to Refresh Data");
        }

        /*String? sales = prefs.getString('sales');
        String? purchase = prefs.getString('purchase');
        String? receipt = prefs.getString('receipt');
        String? payment = prefs.getString('payment');
        String? receivable = prefs.getString('receivable');
        String? payable = prefs.getString('payable');
        String? cash = prefs.getString('cash');*/

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

        /*if(sales!=null)
        {
          sales_value = sales;
          purchase_value = purchase!;
          receipt_value = receipt!;
          payment_value = payment!;
          outstandingreceivable_value = receivable!;
          outstandingpayable_value = payable!;
          cash_value = cash!;
        }*/

        fetchDashData(startDateString, endDateString);

        prefs.setString('startdate', startDateString);
        prefs.setString('enddate', endDateString);
      }
    }
  }

  Future<void> _selectDateRange_auto(BuildContext context) async {
    if (!_isTextEnabled) return;

    // Always show the picker when "Custom Date" is chosen, instead of
    // only the very first time ever - the old gate (skip the picker once
    // startdate/enddate already existed in prefs) meant every later
    // "Custom Date" selection silently reused the old cached range with
    // no way to actually pick a new one. And since the fallback branch's
    // prefs.setString calls ran even when the picker was cancelled (using
    // whatever stale/empty startDateString happened to be set), other
    // screens like Transactions could end up reading an empty date and
    // falling back to their own unrelated default range.
    final cachedStart = DateTime.tryParse(prefs.getString('startdate') ?? '');
    final cachedEnd = DateTime.tryParse(prefs.getString('enddate') ?? '');
    final initialDateRange = DateTimeRange(
      start: cachedStart ?? _startDate,
      end: cachedEnd ?? _endDate,
    );
    final startfrom = prefs.getString('startfrom');
    DateTime earliestDate = DateTime.tryParse(startfrom ?? '') ?? DateTime(2000);

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
              surfaceTintColor: Colors.transparent,
              rangeSelectionBackgroundColor: app_color.withOpacity(0.15),
              rangeSelectionOverlayColor: MaterialStatePropertyAll(
                app_color.withOpacity(0.15),
              ),
            ),
            dialogTheme: DialogThemeData(
              backgroundColor: Theme.of(context).colorScheme.surface,
            ),
            dialogBackgroundColor: Theme.of(context).colorScheme.surface,
          ),
          child: child!,
        );
      },
    );

    // Cancelled - leave whatever range was already active alone, don't
    // touch prefs at all (previously this still overwrote startdate/
    // enddate with stale/empty values on cancel).
    if (selectedDateRange == null) return;

    setState(() {
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

    prefs.setString('startdate', startDateString);
    prefs.setString('enddate', endDateString);
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
                  surfaceTintColor: Colors.transparent,
                  rangeSelectionBackgroundColor: app_color.withOpacity(0.15),
                  rangeSelectionOverlayColor: MaterialStatePropertyAll(
                    app_color.withOpacity(0.15),
                  ),
                ),
                dialogTheme: DialogThemeData(
                  backgroundColor: Theme.of(context).colorScheme.surface,
                ),
                dialogBackgroundColor: Theme.of(context).colorScheme.surface,
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
        /*String? sales = prefs.getString('sales');
        String? purchase = prefs.getString('purchase');
        String? receipt = prefs.getString('receipt');
        String? payment = prefs.getString('payment');
        String? receivable = prefs.getString('receivable');
        String? payable = prefs.getString('payable');
        String? cash = prefs.getString('cash');*/

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
                  surfaceTintColor: Colors.transparent,
                  rangeSelectionBackgroundColor: app_color.withOpacity(0.15),
                  rangeSelectionOverlayColor: WidgetStatePropertyAll(
                    app_color.withOpacity(0.15),
                  ),
                ),
                dialogTheme: DialogThemeData(
                  backgroundColor: Theme.of(context).colorScheme.surface,
                ),
                dialogBackgroundColor: Theme.of(context).colorScheme.surface,
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

            /*if(sales!=null)
              {
                sales_value = sales;
                purchase_value = purchase!;
                receipt_value = receipt!;
                payment_value = payment!;
                outstandingreceivable_value = receivable!;
                outstandingpayable_value = payable!;
                cash_value = cash!;
              }*/
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
      final user_data = jsonDecode(response.body);

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
      Map<String, dynamic> data = json.decode(response.body);
      String error = '';

      if (data.containsKey('error')) {
        setState(() {
          error = data['error'];
        });
      } else {
        error = "Something went wrong!!!";
      }
      showAppMessage(context, error);
    }
  }

  // One label+icon+value row for the dialog's info section (e.g. "Serial
  // No: 772976358", "Expires on: 26-Jul-2026") - same shape both dialogs
  // use, just with different icons/colors/values.
  Widget _licenseDialogInfoRow({
    required String label,
    required IconData icon,
    required Color iconColor,
    required String value,
    required Color valueColor,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: GoogleFonts.poppins(
            fontSize: 14.5,
            color: Theme.of(context).colorScheme.onSurface,
          ),
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            Icon(icon, size: 18, color: iconColor),
            const SizedBox(width: 6),
            Text(
              value,
              style: GoogleFonts.poppins(
                fontWeight: FontWeight.w600,
                fontSize: 15,
                color: valueColor,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
      ],
    );
  }

  // Email + website contact chips for renewal - identical to the ones on
  // SerialSelect's expired-license dialog.
  Widget _licenseDialogContactChips() {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        InkWell(
          borderRadius: BorderRadius.circular(30),
          onTap: () async {
            final Uri emailUri = Uri(
              scheme: 'mailto',
              path: 'saadan@ca-eim.com',
              query:
                  'subject=License%20Renewal%20Request&body=Dear%20CSH%20LLC%20Support,%0A%0AMy%20license%20for%20Serial%20No%20$serial_no%20is%20expiring.%20Please%20assist%20with%20renewal.%0A%0ARegards,',
            );
            if (await canLaunchUrl(emailUri)) {
              await launchUrl(emailUri);
            }
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(30),
              border: Border.all(width: 1.3, color: Colors.teal.shade400),
              gradient: LinearGradient(
                colors: [
                  Colors.teal.withValues(alpha: 0.05),
                  Colors.teal.withValues(alpha: 0.1),
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
        InkWell(
          borderRadius: BorderRadius.circular(30),
          onTap: () async {
            const url = "https://cshllc.ae/contact-us/";
            if (await canLaunchUrl(Uri.parse(url))) {
              await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
            }
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(30),
              border: Border.all(width: 1.3, color: Colors.deepPurple.shade400),
              gradient: LinearGradient(
                colors: [
                  Colors.deepPurple.withValues(alpha: 0.05),
                  Colors.deepPurple.withValues(alpha: 0.1),
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
    );
  }

  // Shared layout for both license dialogs - same animated scale-in,
  // gradient header, info rows, divider, message, contact chips and pill
  // button as SerialSelect's expired-license dialog, just parameterized
  // per use (title/icon/colors/message/action differ between "expired"
  // and "expiring soon").
  void _showStyledLicenseDialog({
    required String title,
    required IconData icon,
    required List<Color> gradientColors,
    required List<Widget> infoRows,
    required String message,
    required void Function(BuildContext dialogContext) onGotIt,
    bool barrierDismissible = true,
  }) {
    if (!mounted) return;
    showGeneralDialog(
      context: context,
      barrierDismissible: barrierDismissible,
      barrierLabel: '',
      barrierColor: Colors.black.withValues(alpha: 0.4),
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
              backgroundColor: Theme.of(context).cardColor.withValues(alpha: 0.9),
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
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: gradientColors,
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(24),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(icon, color: Colors.white, size: 28),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        title,
                        style: GoogleFonts.poppins(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                        ),
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
                      ...infoRows,
                      const SizedBox(height: 8),
                      Divider(thickness: 1, color: Colors.grey.shade300),
                      const SizedBox(height: 12),
                      Text(
                        message,
                        style: GoogleFonts.poppins(
                          fontSize: 14.5,
                          color: Theme.of(context).colorScheme.onSurface,
                        ),
                      ),
                      const SizedBox(height: 16),
                      _licenseDialogContactChips(),
                      const SizedBox(height: 26),
                      Align(
                        alignment: Alignment.center,
                        child: ElevatedButton.icon(
                          onPressed: () => onGotIt(context),
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

  // Non-dismissible - a real hard block, matching SerialSelect's own
  // expired-license dialog exactly (red/orange gradient, Serial No +
  // Expired-on rows, contact chips for renewal).
  void _showLicenseExpiredDialog() {
    final String expiryDateText = license_expiry != null
        ? DateFormat('dd-MMM-yyyy').format(DateTime.parse(license_expiry!))
        : 'Unknown';

    _showStyledLicenseDialog(
      title: "License Expired",
      icon: Icons.warning_amber_rounded,
      gradientColors: const [Color(0xFFF83600), Color(0xFFFE8C00)],
      infoRows: [
        _licenseDialogInfoRow(
          label: "Serial No:",
          icon: Icons.confirmation_number_outlined,
          iconColor: Colors.deepOrange,
          value: serial_no ?? '',
          valueColor: Theme.of(context).colorScheme.onSurface,
        ),
        _licenseDialogInfoRow(
          label: "Expired on:",
          icon: Icons.calendar_month,
          iconColor: Colors.redAccent,
          value: expiryDateText,
          valueColor: Colors.redAccent,
        ),
      ],
      message:
          "Your license has expired. To renew your access, please contact our support team below:",
      barrierDismissible: false,
      onGotIt: (dialogContext) {
        Navigator.pop(dialogContext);
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => SerialSelect()),
        );
      },
    );
  }

  // Dismissible (unlike the expired dialog) - just a heads-up so the
  // license doesn't lapse without warning. Shows every Dashboard load
  // while 3 or fewer days remain, same as the hard-block check above.
  // Same layout as the expired dialog, in an amber/orange "warning" tone
  // instead of expired's red/orange, so the two read as related but
  // distinct in severity.
  void _showLicenseExpiringSoonDialog(int daysRemaining) {
    final bool isToday = daysRemaining <= 0;
    final String dayWord = daysRemaining == 1 ? 'day' : 'days';
    final String expiryDateText = license_expiry != null
        ? DateFormat('dd-MMM-yyyy').format(DateTime.parse(license_expiry!))
        : 'Unknown';

    _showStyledLicenseDialog(
      title: isToday ? "License Expires Today" : "License Expiring Soon",
      icon: Icons.hourglass_bottom_rounded,
      gradientColors: const [Colors.orangeAccent, Colors.deepOrange],
      infoRows: [
        _licenseDialogInfoRow(
          label: "Serial No:",
          icon: Icons.confirmation_number_outlined,
          iconColor: Colors.deepOrange,
          value: serial_no ?? '',
          valueColor: Theme.of(context).colorScheme.onSurface,
        ),
        _licenseDialogInfoRow(
          label: isToday ? "Expires:" : "Expires on:",
          icon: Icons.calendar_month,
          iconColor: Colors.orange,
          value: isToday ? "Today" : expiryDateText,
          valueColor: Colors.deepOrange,
        ),
        if (!isToday)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 5,
              ),
              decoration: BoxDecoration(
                color: Colors.deepOrange.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                '$daysRemaining $dayWord left',
                style: GoogleFonts.poppins(
                  color: Colors.deepOrange,
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                ),
              ),
            ),
          ),
      ],
      message: isToday
          ? "Your license expires today. To renew your access, please contact our support team below:"
          : "Your license will expire soon. To renew your access, please contact our support team below:",
      barrierDismissible: true,
      onGotIt: (dialogContext) => Navigator.pop(dialogContext),
    );
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

    /*print('token : $token');
    print('hostname : $hostname');*/

    // license_expiry can be null (fresh install, cleared prefs) - the old
    // `DateTime.parse(license_expiry!)` would throw immediately in that
    // case and break dashboard init entirely.
    try {
      expire_date = license_expiry == null || license_expiry!.isEmpty
          ? null
          : DateTime.parse(license_expiry!);
    } catch (_) {
      expire_date = null;
    }

    int? daysUntilExpiry;

    if (expire_date != null) {
      // Compare calendar dates only (matches SerialSelect's expiry check)
      // - comparing full DateTime.now() against a midnight-valued
      // expire_date treated the license as already expired from the very
      // start of the expiry day itself, a full day earlier than
      // SerialSelect's own check for the same license.
      final DateTime today = DateTime.now();
      final DateTime todayDate = DateTime(today.year, today.month, today.day);
      final DateTime expiryDate = DateTime(
        expire_date!.year,
        expire_date!.month,
        expire_date!.day,
      );
      isExpired = todayDate.isAfter(expiryDate);
      daysUntilExpiry = expiryDate.difference(todayDate).inDays;
    } else {
      // Can't verify a missing/invalid expiry - treat as expired rather
      // than silently granting unrestricted access.
      isExpired = true;
    }

    if (isExpired && mounted) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _showLicenseExpiredDialog();
      });
    } else if (daysUntilExpiry != null &&
        daysUntilExpiry <= 3 &&
        mounted) {
      // Not expired yet, but 3 days or fewer remain - a dismissible
      // heads-up (not a hard block) so the license doesn't lapse as a
      // surprise.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _showLicenseExpiringSoonDialog(daysUntilExpiry!);
      });
    }

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

    _currencyCode = currencyCode ?? 'AED';

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

  NumberScale _numberScaleFromString(String? scale) {
    switch (scale) {
      case "full":
        return NumberScale.full;
      case "million":
        return NumberScale.million;
      case "billion":
        return NumberScale.billion;
      case "thousand":
      default:
        return NumberScale.thousand;
    }
  }

  String _numberScaleToString(NumberScale scale) {
    switch (scale) {
      case NumberScale.full:
        return "full";
      case NumberScale.million:
        return "million";
      case NumberScale.billion:
        return "billion";
      case NumberScale.thousand:
        return "thousand";
    }
  }

  Future<void> _loadNumberScale() async {
    final loadedScale = _numberScaleFromString(prefs.getString("number_scale"));
    if (!mounted) return;

    setState(() {
      _selectedScale = loadedScale;
    });
  }

  Future<void> _saveNumberScale(NumberScale scale) async {
    setState(() {
      _selectedScale = scale;
    });

    await prefs.setString("number_scale", _numberScaleToString(scale));
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
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
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
            leadingWidth: kToolbarHeight,
            /*leading: IconButton(
                icon: Icon(Icons.menu, color: Colors.white),
                onPressed: () {
                  _scaffoldKey.currentState!.openDrawer();
                },
              ),*/
            centerTitle: true,
            title: GestureDetector(
              onTap: () {
                Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(builder: (context) => SerialSelect()),
                );
              },
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth:
                      MediaQuery.of(context).size.width -
                      (kToolbarHeight * 2.4),
                ),
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
            actions: const [],
          ),
        ),

        /*drawer: Sidebar(
              isDashEnable: isDashEnable,
              isRolesVisible: isRolesVisible,
              isRolesEnable: isRolesEnable,
              isUserEnable: isUserEnable,
              isUserVisible: isUserVisible,
              Username: name,
              Email: email,
              tickerProvider: this),*/
        // add the Sidebar widget here
        bottomNavigationBar: const AppBottomNav(
          activeTab: AppBottomNavTab.dashboard,
          activeMoreItem: AppMoreItem.dashboard,
        ),

        body: Stack(
          children: [
            RefreshIndicator(
              onRefresh: _handleRefresh,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                child: Center(
                  child: Column(
                    children: [
                      _buildDashboardHeader(),
                      Container(
                        margin: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                        padding: EdgeInsets.all(0),
                        decoration: BoxDecoration(
                          color: Theme.of(context).cardColor,
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(
                            color: Theme.of(context).dividerColor,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.035),
                              blurRadius: 16,
                              offset: const Offset(0, 8),
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
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
                        gridDelegate:
                            const SliverGridDelegateWithMaxCrossAxisExtent(
                              maxCrossAxisExtent: 220,
                              childAspectRatio: 1.28,
                              crossAxisSpacing: 12,
                              mainAxisSpacing: 12,
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
                                currencysymbol,
                                formatNumberAbbreviation(sales_value, decimalPlaces: decimal!, scale: _selectedScale, showSuffix: true),
                                _currencyCode,
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
                                trendPercent: _salesTrendPercent,
                              ),

                            if (purchase_visibility)
                              _buildDecentCard(
                                context,
                                "Purchase - Debit Note",
                                currencysymbol,
                                formatNumberAbbreviation(purchase_value, decimalPlaces: decimal!, scale: _selectedScale, showSuffix: true),
                                _currencyCode,
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
                                currencysymbol,
                                formatNumberAbbreviation(receipt_value, decimalPlaces: decimal!, scale: _selectedScale, showSuffix: true),
                                _currencyCode,
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
                                currencysymbol,
                                formatNumberAbbreviation(payment_value, decimalPlaces: decimal!, scale: _selectedScale, showSuffix: true),
                                _currencyCode,
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
                                currencysymbol,
                                formatNumberAbbreviation(outstandingreceivable_value, decimalPlaces: decimal!, scale: _selectedScale, showSuffix: true),
                                _currencyCode,
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
                                currencysymbol,
                                formatNumberAbbreviation(outstandingpayable_value, decimalPlaces: decimal!, scale: _selectedScale, showSuffix: true),
                                _currencyCode,
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
                                currencysymbol,
                                formatNumberAbbreviation(cash_value, decimalPlaces: decimal!, scale: _selectedScale, showSuffix: true),
                                _currencyCode,
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
                                    vertical: 10,
                                  ),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                    vertical: 15,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Theme.of(context).cardColor,
                                    borderRadius: BorderRadius.circular(18),
                                    border: Border.all(
                                      color: Theme.of(context).dividerColor,
                                    ),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black.withOpacity(0.035),
                                        blurRadius: 16,
                                        offset: const Offset(0, 8),
                                      ),
                                    ],
                                  ),
                                  child: Row(
                                    children: [
                                      Container(
                                        width: 42,
                                        height: 42,
                                        decoration: BoxDecoration(
                                          color: app_color.withOpacity(0.10),
                                          borderRadius: BorderRadius.circular(
                                            12,
                                          ),
                                        ),
                                        child: Icon(
                                          Icons.analytics_outlined,
                                          color: app_color,
                                          size: 22,
                                        ),
                                      ),
                                      const SizedBox(width: 16),

                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              "Analytics",
                                              style: GoogleFonts.poppins(
                                                fontSize: 15.5,
                                                fontWeight: FontWeight.w700,
                                                color: Theme.of(
                                                  context,
                                                ).colorScheme.onSurface,
                                              ),
                                            ),
                                            const SizedBox(height: 2),
                                            Text(
                                              "Open chart insights and movement trends",
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: GoogleFonts.poppins(
                                                fontSize: 12,
                                                fontWeight: FontWeight.w500,
                                                color: Theme.of(
                                                  context,
                                                ).colorScheme.onSurfaceVariant,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),

                                      Container(
                                        padding: const EdgeInsets.all(6),
                                        decoration: BoxDecoration(
                                          color:
                                              Theme.of(context).brightness ==
                                                  Brightness.dark
                                              ? Theme.of(context)
                                                    .colorScheme
                                                    .surfaceContainerHighest
                                              : const Color(0xFFF1F4F8),
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
                                margin: const EdgeInsets.fromLTRB(
                                  16,
                                  18,
                                  16,
                                  20,
                                ),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 18,
                                  vertical: 24,
                                ),
                                decoration: BoxDecoration(
                                  color: Theme.of(context).cardColor,
                                  borderRadius: BorderRadius.circular(18),
                                  border: Border.all(
                                    color: Theme.of(context).dividerColor,
                                  ),
                                ),
                                child: Center(
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Container(
                                        width: 48,
                                        height: 48,
                                        decoration: BoxDecoration(
                                          color: app_color.withOpacity(0.10),
                                          borderRadius: BorderRadius.circular(
                                            14,
                                          ),
                                        ),
                                        child: Icon(
                                          Icons.lock_outline_rounded,
                                          color: app_color,
                                        ),
                                      ),
                                      const SizedBox(height: 12),
                                      Text(
                                        'No Access to Dashboard',
                                        style: GoogleFonts.poppins(
                                          fontWeight: FontWeight.w700,
                                          color: Theme.of(
                                            context,
                                          ).colorScheme.onSurface,
                                          fontSize: 16.0,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        'Please contact your administrator to enable dashboard access.',
                                        textAlign: TextAlign.center,
                                        style: GoogleFonts.poppins(
                                          fontWeight: FontWeight.w500,
                                          color: Theme.of(
                                            context,
                                          ).colorScheme.onSurfaceVariant,
                                          fontSize: 12.5,
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
                    ],
                  ),
                ),
              ),
            ),

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
                ),*/
            Visibility(
              visible: _isLoading,
              child: Container(
                color: Theme.of(context).brightness == Brightness.dark
                    ? Colors.black.withOpacity(0.58)
                    : Colors.white.withOpacity(0.72),
                child: const Center(child: AppLogoLoader()),
              ),
            ),
          ],
        ),

        floatingActionButton: FloatingActionButton(
          backgroundColor: app_color,
          elevation: 4,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          tooltip: 'Number scale',
          child: const Icon(Icons.tune_rounded, color: Colors.white),
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

            final theme = Theme.of(context);
            final result = await showMenu<NumberScale>(
              color: theme.colorScheme.surface,
              context: context,
              position: position,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(color: theme.dividerColor),
              ),
              items: [
                _buildNumberScaleMenuItem(
                  value: NumberScale.full,
                  icon: Icons.pin,
                  iconColor: Colors.blue,
                  label: "Full Value",
                ),
                _buildNumberScaleMenuItem(
                  value: NumberScale.thousand,
                  icon: Icons.format_list_numbered,
                  iconColor: Colors.blue,
                  label: "Thousands (K)",
                ),
                _buildNumberScaleMenuItem(
                  value: NumberScale.million,
                  icon: Icons.format_list_numbered_rtl,
                  iconColor: Colors.orange,
                  label: "Millions (M)",
                ),
                _buildNumberScaleMenuItem(
                  value: NumberScale.billion,
                  icon: Icons.numbers,
                  iconColor: Colors.purple,
                  label: "Billions (B)",
                ),
              ],
            );

            if (result != null) {
              await _saveNumberScale(result);
            }
          },
        ),
      ),

      // Empty container if the license is still valid
    );
  }

  PopupMenuItem<NumberScale> _buildNumberScaleMenuItem({
    required NumberScale value,
    required IconData icon,
    required Color iconColor,
    required String label,
  }) {
    final theme = Theme.of(context);
    final isSelected = _selectedScale == value;

    return PopupMenuItem<NumberScale>(
      value: value,
      child: Row(
        children: [
          Icon(icon, color: iconColor),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              style: GoogleFonts.poppins(
                color: theme.colorScheme.onSurface,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ),
          if (isSelected)
            Icon(Icons.check_circle_rounded, color: app_color, size: 20),
        ],
      ),
    );
  }

  Widget _buildDashboardHeader() {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: app_color,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: app_color.withOpacity(0.22),
            blurRadius: 18,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: Theme.of(context).cardColor.withOpacity(0.16),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(
              Icons.dashboard_customize_rounded,
              color: Colors.white,
              size: 26,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name.trim().isEmpty ? 'Welcome' : 'Welcome, $name',
                  style: GoogleFonts.poppins(
                    color: Colors.white,
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Your business insights are ready for you',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.poppins(
                    color: Colors.white.withOpacity(0.82),
                    fontSize: 12.5,
                    height: 1.35,
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

  Widget buildDateFilterCard(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: app_color.withOpacity(0.10),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  Icons.date_range_rounded,
                  size: 20,
                  color: app_color,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Report Period',
                      style: GoogleFonts.poppins(
                        fontSize: 14.5,
                        color: Theme.of(context).colorScheme.onSurface,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      "$startdate_text - $enddate_text",
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.poppins(
                        fontSize: 12,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Container(
            decoration: BoxDecoration(
              color: Theme.of(context).brightness == Brightness.dark
                  ? Theme.of(context).colorScheme.surfaceContainerHighest
                  : const Color(0xFFF7F9FC),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Theme.of(context).dividerColor),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<dynamic>(
                value: _selecteddate,
                icon: Icon(
                  Icons.keyboard_arrow_down_rounded,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
                dropdownColor: Theme.of(context).colorScheme.surface,
                borderRadius: BorderRadius.circular(14),
                isExpanded: true,
                style: GoogleFonts.poppins(
                  fontSize: 14,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
                items: date_range.map((item) {
                  return DropdownMenuItem<dynamic>(
                    value: item,
                    child: Text(
                      item,
                      style: GoogleFonts.poppins(
                        fontSize: 14,
                        color: Theme.of(context).colorScheme.onSurface,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  );
                }).toList(),
                onChanged: (value) => _handleDate(value),
              ),
            ),
          ),
          const SizedBox(height: 12),
          InkWell(
            onTap: () => _selectDateRange(context),
            borderRadius: BorderRadius.circular(14),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
              decoration: BoxDecoration(
                color: Theme.of(context).brightness == Brightness.dark
                    ? Theme.of(context).colorScheme.surfaceContainerHighest
                    : const Color(0xFFF7F9FC),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Theme.of(context).dividerColor),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.calendar_today_rounded,
                    size: 18,
                    color: app_color,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      "$startdate_text - $enddate_text",
                      style: GoogleFonts.poppins(
                        fontSize: 13,
                        color: Theme.of(context).colorScheme.onSurface,
                        fontWeight: FontWeight.w600,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Icon(
                    Icons.edit_calendar_rounded,
                    size: 18,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ],
              ),
            ),
          ),
        ],
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
              colors: Theme.of(context).brightness == Brightness.dark
                  ? [
                      Theme.of(context).cardColor,
                      Theme.of(context).colorScheme.surfaceContainerHighest,
                    ]
                  : const [Color(0xFFF1FDFB), Color(0xFFE9F6F3)],
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
  String symbol,
  String amountText,
  String currencyCode,
  String type,
  VoidCallback onTap, {
  double? trendPercent,
}) {
  Color _getColor(String type) {
    switch (type.toLowerCase()) {
      case "sales":
        return const Color(0xFF0F766E);
      case "purchase":
        return const Color(0xFFB45309);
      case "receipt":
        return const Color(0xFF15803D);
      case "payment":
        return const Color(0xFFB42318);
      case "receivable":
        return const Color(0xFF4338CA);
      case "payable":
        return const Color(0xFF7E22CE);
      case "cash":
        return const Color(0xFF0369A1);
      default:
        return const Color(0xFF4B5563);
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

  final Color color = _getColor(type);

  return Material(
    color: Theme.of(context).cardColor,
    borderRadius: BorderRadius.circular(18),
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Ink(
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: Theme.of(context).dividerColor),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.035),
              blurRadius: 16,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        padding: const EdgeInsets.all(14),
        child: LayoutBuilder(
          builder: (context, constraints) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        color: color.withOpacity(0.10),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(_getIcon(type), size: 20, color: color),
                    ),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.all(5),
                      decoration: BoxDecoration(
                        color: Theme.of(context).brightness == Brightness.dark
                            ? Theme.of(
                                context,
                              ).colorScheme.surfaceContainerHighest
                            : const Color(0xFFF1F4F8),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.chevron_right_rounded,
                        size: 17,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
                const Spacer(),
                Text(
                  label,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.poppins(
                    fontSize: 12.2,
                    height: 1.18,
                    fontWeight: FontWeight.w600,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 6),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: currencyAmountText(
                    currencyCode: currencyCode,
                    symbol: symbol,
                    amountText: amountText,
                    maxLines: 1,
                    style: GoogleFonts.poppins(
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                ),
                if (trendPercent != null) ...[
                  const SizedBox(height: 4),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        trendPercent >= 0
                            ? Icons.arrow_upward_rounded
                            : Icons.arrow_downward_rounded,
                        size: 13,
                        color: trendPercent >= 0
                            ? Colors.green.shade600
                            : Colors.red.shade600,
                      ),
                      const SizedBox(width: 2),
                      Text(
                        '${trendPercent.abs().toStringAsFixed(1)}% vs last month',
                        style: GoogleFonts.poppins(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w600,
                          color: trendPercent >= 0
                              ? Colors.green.shade600
                              : Colors.red.shade600,
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            );
          },
        ),
      ),
    ),
  );
}
