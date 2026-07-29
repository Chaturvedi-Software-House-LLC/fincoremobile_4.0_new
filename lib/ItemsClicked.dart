import 'dart:convert';
import 'dart:io';
import 'package:FincoreGo/ItemsDrillDown.dart';
import 'package:FincoreGo/currencyFormat.dart';
import 'package:csv/csv.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'SerialSelect.dart';
import 'package:http/http.dart' as http;
import 'constants.dart';
import 'package:FincoreGo/widgets/app_bottom_nav.dart';
import 'package:FincoreGo/widgets/app_navigation.dart';
import 'package:FincoreGo/widgets/entry_widgets.dart';

class Sale_Purc {
  final String month, amount;

  Sale_Purc({required this.month, required this.amount});

  factory Sale_Purc.fromJson(Map<String, dynamic> json) {
    return Sale_Purc(
      month: json['mname'].toString(),
      amount: json['amount'].toString(),
    );
  }
}

class ItemsClicked extends StatefulWidget {
  final String itemname,
      unit,
      item_desc,
      item_lastsaledate,
      item_lastpurchdate,
      item_rate,
      inventory_closing,
      lastpurcrate,
      alias;
  const ItemsClicked({
    required this.itemname,
    required this.unit,
    required this.item_desc,
    required this.item_lastsaledate,
    required this.item_lastpurchdate,
    required this.item_rate,
    required this.inventory_closing,
    required this.lastpurcrate,
    required this.alias,
  });
  @override
  _ItemsClickedPageState createState() => _ItemsClickedPageState(
    itemname: itemname,
    unit: unit,
    item_desc: item_desc,
    item_lastsaledate: item_lastsaledate,
    item_lastpurchdate: item_lastpurchdate,
    item_rate: item_rate,
    inventory_closing: inventory_closing,
    lastpurcrate: lastpurcrate,
    alias: alias,
  );
}

class _ItemsClickedPageState extends State<ItemsClicked>
    with TickerProviderStateMixin {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  String itemname = "",
      unit = "",
      item_desc = "",
      item_lastsaledate = "",
      item_lastpurchdate = "",
      item_rate = "",
      inventory_closing = "",
      lastpurcrate = "",
      alias = "",
      token = '';
  String startDateString = "", endDateString = "";
  String totalsales = "", HttpURL_Main = "", HttpURL_months_sales = "";
  String vchtypes = "purchase" + "," + "sales";
  bool isVisibleNoAccess = false;
  bool isItemDescVisible = false,
      isItemAliasVisible = false,
      isVisibleSalesList = false,
      isClicked_Salesicon = false,
      isVisiblePurchaseList = false,
      isClicked_Purchaseicon = false;
  int counter = 0;
  bool isDateVisible = true;
  bool salesummary_visible = false, purchasesummary_visible = false;
  String sales_totalnetsales = "0",
      sales_lastsaledate = "Not Available",
      sales_lastsaleprice = "Not Available",
      sales_totalsalesqty = "Not Available",
      sales_minrate = "Not Available",
      sales_maxrate = "Not Available",
      sales_noofinvoices = "Not Available";
  bool isSalesClickableCard = false, isPurchaseClickableCard = false;
  String purchase_totalnetpurchase = "Not Available",
      purchase_lastpurchasedate = "Not Available",
      purchase_lastpurchaseprice = "Not Available",
      purchase_totalpurchaseqty = "Not Available",
      purchase_minrate = "Not Available",
      purchase_maxrate = "Not Available",
      purchase_noofinvoices = "Not Available";
  dynamic _selecteddate;

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
  List<Sale_Purc> list_sale =
      []; // Initialize an empty list to hold the filtered items
  List<Sale_Purc> list_purchase =
      []; // Initialize an empty list to hold the filtered items

  _ItemsClickedPageState({
    required this.itemname,
    required this.unit,
    required this.item_desc,
    required this.item_lastsaledate,
    required this.item_lastpurchdate,
    required this.item_rate,
    required this.inventory_closing,
    required this.lastpurcrate,
    required this.alias,
  });

  String? SecuritybtnAcessHolder;
  bool isDashEnable = true,
      isRolesEnable = true,
      isUserEnable = true,
      isRolesVisible = true,
      isUserVisible = true;
  String email = "";
  String name = "";
  String? opening_value = "0", openingheading = "";
  TextEditingController searchController = TextEditingController();
  bool isVisibleNoDataFound = false;
  late GlobalKey<ScaffoldMessengerState> _scaffoldMessengerKey;
  late SharedPreferences prefs;
  late String startdate_text = "", enddate_text = "";
  DateTime _startDate = DateTime.now();
  DateTime _endDate = DateTime.now().add(Duration(days: 7));
  String? datetype;
  late String? startdate_pref;
  String HttpURL = "";
  String? hostname = "",
      company = "",
      serial_no = "",
      company_lowercase = "",
      username = "";
  List<dynamic> myData = [];
  bool _isLoading = false;
  List<String> spinner_list = [];
  bool _isTextEnabled = true;
  late int? decimal;
  late NumberFormat currencyFormat;
  late String currencysymbol = '';
  String _currencyCode = 'AED';

  bool _isDashVisible = true,
      _isEnddateVisible = true,
      _IsSizeboxVisible = true;

  String formatRate(String value, {int decimals = 2}) {
    try {
      String numberOnly = value.split('/').first.trim();
      double parsed = double.parse(numberOnly);
      return parsed.toStringAsFixed(decimals);
    } catch (e) {
      return value; // agar parsing fail ho jaye to raw value return karega
    }
  }

  String formatBackendValue(String value, {int decimals = 2}) {
    try {
      List<String> parts = value.split('/');
      String numberPart = parts.first.trim();
      String unitPart = parts.length > 1 ? parts.last.trim() : "";

      double parsed = double.parse(numberPart);
      String formattedNumber = parsed.toStringAsFixed(decimals);

      return "$formattedNumber/$unitPart";
    } catch (e) {
      return value; // fallback if parsing fails
    }
  }

  String convertDateFormat(String dateStr) {
    // Parse the input date string
    DateTime date = DateTime.parse(dateStr);
    // Format the date to the desired output format
    String formattedDate = DateFormat("dd-MMM-yyyy").format(date);
    return formattedDate;
  }

  String formatTotal(dynamic amount, {int decimals = 2}) {
    try {
      // Convert to double
      double parsed = double.parse(amount.toString());

      // Get absolute value for formatting
      double absValue = parsed.abs();

      // Format with commas + decimals
      final formatter = NumberFormat.currency(
        locale: 'en',
        symbol:
            '', // 👈 keep symbol empty, since you already have one in string
        decimalDigits: decimals,
      );

      String formatted = formatter.format(absValue).trim();

      // Append CR/DR
      if (parsed < 0) {
        return "$formatted DR";
      } else {
        return "$formatted CR";
      }
    } catch (e) {
      return amount.toString();
    }
  }

  Future<void> fetchMainData(
    String vchtypes,
    String item_name,
    String startdate_string,
    String enddate_string,
    String groupby,
  ) async {
    if (salesummary_visible || purchasesummary_visible) {
      isDateVisible = true;
      list_sale.clear();
      list_purchase.clear();

      setState(() {
        _isLoading = true;
        isPurchaseClickableCard = false;
        isSalesClickableCard = false;
        isVisibleSalesList = false;
        isClicked_Salesicon = false;
        isVisiblePurchaseList = false;
        isClicked_Purchaseicon = false;
      });

      sales_noofinvoices = 'Not Available';
      sales_totalnetsales = '0';
      sales_lastsaledate = 'Not Available';
      sales_lastsaleprice = 'Not Available';
      sales_totalsalesqty = 'Not Available';
      sales_minrate = 'Not Available';
      sales_maxrate = 'Not Available';

      purchase_noofinvoices = 'Not Available';
      purchase_totalnetpurchase = '0';
      purchase_lastpurchasedate = 'Not Available';
      purchase_lastpurchaseprice = 'Not Available';
      purchase_totalpurchaseqty = 'Not Available';
      purchase_minrate = 'Not Available';
      purchase_maxrate = 'Not Available';
      try {
        final url = Uri.parse(HttpURL_Main);

        Map<String, String> headers = {
          'Authorization': 'Bearer $token',
          "Content-Type": "application/json",
        };

        var body = jsonEncode({
          'vchtypes': vchtypes,
          'item': item_name,
          'startdate': startdate_string,
          'enddate': enddate_string,
          'groupby': groupby,
        });

        final response = await http.post(url, body: body, headers: headers);
        if (response.statusCode == 200) {
          String responsee = response.body;
          if (responsee == "Connection Failed!!") {
            isPurchaseClickableCard = false;
            isSalesClickableCard = false;

            isVisibleSalesList = false;
            isClicked_Salesicon = false;

            isVisiblePurchaseList = false;
            isClicked_Purchaseicon = false;
            sales_noofinvoices = 'Not Available';
            sales_totalnetsales = '0';
            sales_lastsaledate = 'Not Available';
            sales_lastsaleprice = 'Not Available';
            sales_totalsalesqty = 'Not Available';
            sales_minrate = 'Not Available';
            sales_maxrate = 'Not Available';

            purchase_noofinvoices = 'Not Available';
            purchase_totalnetpurchase = '0';
            purchase_lastpurchasedate = 'Not Available';
            purchase_lastpurchaseprice = 'Not Available';
            purchase_totalpurchaseqty = 'Not Available';
            purchase_minrate = 'Not Available';
            purchase_maxrate = 'Not Available';
          } else if (responsee == '[]') {
            isPurchaseClickableCard = false;
            isSalesClickableCard = false;
            isVisibleSalesList = false;
            isClicked_Salesicon = false;
            isVisiblePurchaseList = false;
            isClicked_Purchaseicon = false;
            sales_noofinvoices = 'Not Available';
            sales_totalnetsales = '0';
            sales_lastsaledate = 'Not Available';
            sales_lastsaleprice = 'Not Available';
            sales_totalsalesqty = 'Not Available';
            sales_minrate = 'Not Available';
            sales_maxrate = 'Not Available';

            purchase_noofinvoices = 'Not Available';
            purchase_totalnetpurchase = '0';
            purchase_lastpurchasedate = 'Not Available';
            purchase_lastpurchaseprice = 'Not Available';
            purchase_totalpurchaseqty = 'Not Available';
            purchase_minrate = 'Not Available';
            purchase_maxrate = 'Not Available';
          } else {
            final List<dynamic> data_list = jsonDecode(responsee);

            if (data_list != null) {
              for (var entry in data_list.asMap().entries) {
                dynamic item = entry.value;

                String vchtype = item['vchtype'].toString();

                if (vchtype == 'Sales') {
                  isSalesClickableCard = true;
                  sales_noofinvoices = item['noofinvoice'].toString();
                  sales_totalnetsales = formatTotal(
                    item['totalAmount'],
                    decimals: decimal!,
                  );

                  sales_lastsaledate = convertDateFormat(item_lastsaledate);
                  sales_lastsaleprice = formatBackendValue(
                    item_rate,
                    decimals: decimal!,
                  );
                  sales_totalsalesqty = item['totalQty'].toString();
                  sales_minrate = formatRate(
                    item['minRate'].toString(),
                    decimals: decimal!,
                  );
                  sales_maxrate = formatRate(
                    item['maxRate'].toString(),
                    decimals: decimal!,
                  );

                  final url_sales = Uri.parse(HttpURL_months_sales);

                  Map<String, String> headers_month_sales = {
                    'Authorization': 'Bearer $token',
                    "Content-Type": "application/json",
                  };

                  var body_month_sales = jsonEncode({
                    'vchtype': 'sales',
                    'startdate': startdate_string,
                    'enddate': enddate_string,
                    'item': item_name,
                    'groupby': 'mname',
                    'orderby': 'v.vchdate',
                  });

                  final response_month_sales = await http.post(
                    url_sales,
                    body: body_month_sales,
                    headers: headers_month_sales,
                  );

                  if (response_month_sales.statusCode == 200) {
                    final List<dynamic> sales_months_list = jsonDecode(
                      response_month_sales.body,
                    );
                    if (sales_months_list != null) {
                      for (var entry in sales_months_list.asMap().entries) {
                        int index = entry.key;

                        list_sale.add(
                          Sale_Purc.fromJson(sales_months_list[index]),
                        );
                      }
                    }
                  }
                } else if (vchtype == 'Purchase') {
                  isPurchaseClickableCard = true;
                  purchase_noofinvoices = item['noofinvoice'].toString();
                  purchase_totalnetpurchase = formatTotal(
                    item['totalAmount'].toString(),
                    decimals: decimal!,
                  );
                  purchase_lastpurchasedate = convertDateFormat(
                    item_lastpurchdate,
                  );
                  purchase_lastpurchaseprice = formatBackendValue(
                    lastpurcrate,
                    decimals: decimal!,
                  );
                  purchase_totalpurchaseqty = item['totalQty'].toString();
                  purchase_minrate = formatRate(
                    item['minRate'].toString(),
                    decimals: decimal!,
                  );
                  purchase_maxrate = formatRate(
                    item['maxRate'].toString(),
                    decimals: decimal!,
                  );

                  final url_purchase = Uri.parse(HttpURL_months_sales);

                  Map<String, String> headers_month_purchase = {
                    'Authorization': 'Bearer $token',
                    "Content-Type": "application/json",
                  };

                  var body_month_purchase = jsonEncode({
                    'vchtype': 'purchase',
                    'startdate': startdate_string,
                    'enddate': enddate_string,
                    'item': item_name,
                    'groupby': 'mname',
                    'orderby': 'v.vchdate',
                  });

                  final response_month_purchase = await http.post(
                    url_purchase,
                    body: body_month_purchase,
                    headers: headers_month_purchase,
                  );

                  if (response_month_purchase.statusCode == 200) {
                    final List<dynamic> purchase_months_list = jsonDecode(
                      response_month_purchase.body,
                    );
                    if (purchase_months_list != null) {
                      for (var entry in purchase_months_list.asMap().entries) {
                        int index = entry.key;
                        dynamic item = entry.value;

                        list_purchase.add(
                          Sale_Purc.fromJson(purchase_months_list[index]),
                        );
                      }
                    }
                  }
                } else {}
              }
            }
          }
        }

        setState(() {
          _isLoading = false;
        });
      } catch (e) {
        setState(() {
          _isLoading = false;
        });
        print(e);
      }
    } else {
      isDateVisible = false;
    }
  }

  Future<void> _initSharedPreferences() async {
    prefs = await SharedPreferences.getInstance();

    hostname = prefs.getString('hostname');
    company = prefs.getString('company_name');
    company_lowercase = company!.replaceAll(' ', '').toLowerCase();
    serial_no = prefs.getString('serial_no');
    username = prefs.getString('username');
    token = prefs.getString('token')!;
    _selecteddate = prefs.getString('datetype') ?? date_range.first;

    decimal = prefs.getInt('decimalplace') ?? 2;

    currencyFormat = new NumberFormat();

    String? currencyCode = '';

    currencyCode = prefs.getString('currencycode') ?? "AED";

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

    if (_selecteddate == 'Custom Date') {
      _startDate = DateTime.parse(prefs.getString('startdate')!);
      _endDate = DateTime.parse(prefs.getString('enddate')!);

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

      startdate_text = startDay + "-" + startMonth + "-" + startYear.toString();
      enddate_text = endDay + "-" + endMonth + "-" + endYear.toString();
    }

    String item_sales = prefs.getString("item_sales") ?? 'False';
    String item_purchase = prefs.getString("item_purchase") ?? 'False';

    if (item_sales == 'True') {
      salesummary_visible = true;
    } else {
      salesummary_visible = false;
    }

    if (item_purchase == 'True') {
      purchasesummary_visible = true;
    } else {
      purchasesummary_visible = false;
    }

    SecuritybtnAcessHolder = prefs.getString('secbtnaccess');

    HttpURL_Main =
        '$hostname/api/item/getSummary/$company_lowercase/$serial_no';
    HttpURL_months_sales =
        '$hostname/api/item/getTotalAmount/$company_lowercase/$serial_no';

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
    }
    if (SecuritybtnAcessHolder == "True") {
      isRolesVisible = true;
      isUserVisible = true;
    } else {
      isRolesVisible = false;
      isUserVisible = false;
    }

    _handleDate(_selecteddate);

    if (item_desc == 'null' || itemname == '') {
      isItemDescVisible = false;
    } else {
      isItemDescVisible = true;
    }
    if (alias == 'null' || alias == '') {
      isItemAliasVisible = false;
    } else {
      isItemAliasVisible = true;
    }
  }

  Future<void> _selectDateRange(BuildContext context) async {
    if (_isTextEnabled) {
      final initialDateRange = DateTimeRange(start: _startDate, end: _endDate);
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
                rangeSelectionBackgroundColor: app_color.withOpacity(
                  0.15,
                ), // 🔹 light shade of your app_color
                rangeSelectionOverlayColor: MaterialStatePropertyAll(
                  app_color.withOpacity(0.15),
                ),
              ),
            ),
            child: child!,
          );
        },
      );

      if (selectedDateRange != null) {
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
        });
        fetchMainData(
          vchtypes,
          itemname,
          startDateString,
          endDateString,
          "vchtype",
        );
      }
    }
  }

  Future<void> _selectDateRange_auto(BuildContext context) async {
    print('auto');
    if (_isTextEnabled) {
      final initialDateRange = DateTimeRange(start: _startDate, end: _endDate);
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
                rangeSelectionBackgroundColor: app_color.withOpacity(
                  0.15,
                ), // 🔹 light shade of your app_color
                rangeSelectionOverlayColor: MaterialStatePropertyAll(
                  app_color.withOpacity(0.15),
                ),
              ),
            ),
            child: child!,
          );
        },
      );

      setState(() {
        _startDate = selectedDateRange!.start;
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
      });
      fetchMainData(
        vchtypes,
        itemname,
        startDateString,
        endDateString,
        "vchtype",
      );
    }
  }

  void _handleDate(String value) {
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

      fetchMainData(
        vchtypes,
        itemname,
        startDateString,
        endDateString,
        "vchtype",
      );

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

      fetchMainData(
        vchtypes,
        itemname,
        startDateString,
        endDateString,
        "vchtype",
      );

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

      fetchMainData(
        vchtypes,
        itemname,
        startDateString,
        endDateString,
        "vchtype",
      );

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

      fetchMainData(
        vchtypes,
        itemname,
        startDateString,
        endDateString,
        "vchtype",
      );

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

      fetchMainData(
        vchtypes,
        itemname,
        startDateString,
        endDateString,
        "vchtype",
      );

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

      fetchMainData(
        vchtypes,
        itemname,
        startDateString,
        endDateString,
        "vchtype",
      );

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

      fetchMainData(
        vchtypes,
        itemname,
        startDateString,
        endDateString,
        "vchtype",
      );

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
  }

  void showToast(String message) {
    showAppMessage(context, message);
  }

  Future<void> generateAndShareCSV_ItemDetail() async {
    final List<List<dynamic>> csvData = [];
    csvData.add(['Item Name', itemname]);
    // alias/inventory_closing can come back as the literal string "null"
    // from the API (not Dart null) - isItemAliasVisible already guards
    // against that for alias; inventory_closing gets the same guard here.
    if (isItemAliasVisible) csvData.add(['Alias', alias]);
    csvData.add([
      'Inventory Closing',
      inventory_closing == 'null' ? '0' : inventory_closing,
    ]);
    csvData.add([]);

    if (salesummary_visible && list_sale.isNotEmpty) {
      csvData.add(['Sales Summary']);
      csvData.add(['Month', 'Amount']);
      for (final row in list_sale) {
        csvData.add([row.month, formatAmount(row.amount)]);
      }
      csvData.add([]);
    }

    if (purchasesummary_visible && list_purchase.isNotEmpty) {
      csvData.add(['Purchase Summary']);
      csvData.add(['Month', 'Amount']);
      for (final row in list_purchase) {
        csvData.add([row.month, formatAmount(row.amount)]);
      }
    }

    final csvString = const ListToCsvConverter().convert(csvData);
    final tempDir = await Directory.systemTemp.createTemp();
    final tempFilePath = '${tempDir.path}/${itemname}_Detail.csv';
    final file = File(tempFilePath);
    await file.writeAsString(csvString);

    await SharePlus.instance.share(
      ShareParams(
        text: 'Sharing $itemname Detail Report of ${company ?? ''}',
        files: [XFile(tempFilePath)],
      ),
    );
  }

  Future<void> generateAndSharePDF_ItemDetail() async {
    final font = pw.Font.ttf(
      await rootBundle.load("assets/fonts/NotoSans.ttf"),
    );
    final pdf = pw.Document();
    final companyName = company ?? '';

    pw.Widget buildSummaryTable(String title, List<Sale_Purc> list) {
      return pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.SizedBox(height: 14),
          pw.Text(
            title,
            style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold, font: font),
          ),
          pw.SizedBox(height: 6),
          pw.Table.fromTextArray(
            border: pw.TableBorder.all(width: 1),
            headerDecoration: pw.BoxDecoration(
              borderRadius: pw.BorderRadius.circular(2),
              color: PdfColors.grey300,
            ),
            headerHeight: 26,
            cellAlignment: pw.Alignment.center,
            cellPadding: const pw.EdgeInsets.all(5),
            headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, font: font),
            cellStyle: pw.TextStyle(fontSize: 11, font: font),
            headers: ['Month', 'Amount'],
            data: list
                .map((row) => [row.month, formatAmount(row.amount)])
                .toList(),
          ),
        ],
      );
    }

    pdf.addPage(
      pw.Page(
        build: (context) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Center(
              child: pw.Text(
                companyName,
                style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold, font: font),
              ),
            ),
            pw.SizedBox(height: 10),
            pw.Center(
              child: pw.Text(
                itemname,
                style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold, font: font),
              ),
            ),
            if (isItemAliasVisible)
              pw.Center(
                child: pw.Text(
                  alias,
                  style: pw.TextStyle(fontSize: 11, font: font),
                ),
              ),
            pw.SizedBox(height: 4),
            pw.Text(
              'Inventory Closing: ${inventory_closing == 'null' ? '0' : inventory_closing}',
              style: pw.TextStyle(fontSize: 11, font: font),
            ),
            if (salesummary_visible && list_sale.isNotEmpty)
              buildSummaryTable('Sales Summary', list_sale),
            if (purchasesummary_visible && list_purchase.isNotEmpty)
              buildSummaryTable('Purchase Summary', list_purchase),
          ],
        ),
      ),
    );

    final pdfData = await pdf.save();
    final tempDir = await getTemporaryDirectory();
    final tempFilePath = '${tempDir.path}/${itemname}_Detail.pdf';
    final file = File(tempFilePath);
    await file.writeAsBytes(pdfData);

    await SharePlus.instance.share(
      ShareParams(
        text: 'Sharing $itemname Detail Report of ${company ?? ''}',
        files: [XFile(tempFilePath)],
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    _scaffoldMessengerKey = GlobalKey<ScaffoldMessengerState>();
    _initSharedPreferences();
  }

  @override
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      bottomNavigationBar: const AppBottomNav(activeTab: AppBottomNavTab.items),
      key: _scaffoldKey,
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: PreferredSize(
        preferredSize: Size.fromHeight(44),
        child: AppBar(
          backgroundColor: app_color,
          elevation: 2,
          automaticallyImplyLeading: false,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(bottom: Radius.circular(16)),
          ),
          leading: IconButton(
            icon: Icon(Icons.arrow_back, color: Colors.white, size: 20),
            onPressed: () {
              AppNavigation.backOrDashboard(context);
            },
          ),
          title: GestureDetector(
            onTap: () {
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(builder: (context) => SerialSelect()),
              );
            },
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: Text(
                    company ?? '',
                    style: GoogleFonts.poppins(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                SizedBox(width: 2),
                Icon(Icons.arrow_drop_down, color: Colors.white, size: 20),
              ],
            ),
          ),
          centerTitle: true,
          actions: [
            IconButton(
              icon: Icon(Icons.share_outlined, color: Colors.white, size: 24),
              onPressed: () {
                final RenderBox button =
                    context.findRenderObject() as RenderBox;
                final RenderBox overlay =
                    Overlay.of(context).context.findRenderObject()
                        as RenderBox;
                final Offset buttonPosition = button.localToGlobal(
                  Offset.zero,
                  ancestor: overlay,
                );

                showMenu(
                  context: context,
                  position: RelativeRect.fromLTRB(
                    overlay.size.width - buttonPosition.dx,
                    buttonPosition.dy - button.size.height,
                    overlay.size.width - buttonPosition.dx,
                    buttonPosition.dy,
                  ),
                  items: <PopupMenuEntry<String>>[
                    PopupMenuItem<String>(
                      child: GestureDetector(
                        onTap: () {
                          Navigator.pop(context);
                          if (list_sale.isNotEmpty || list_purchase.isNotEmpty) {
                            generateAndSharePDF_ItemDetail();
                          } else {
                            showToast('Data Not Found');
                          }
                        },
                        child: Row(
                          children: [
                            Icon(
                              Icons.picture_as_pdf,
                              size: 16,
                              color: Color(0xFF26ADA3),
                            ),
                            SizedBox(width: 5),
                            Text(
                              'Share as PDF',
                              style: TextStyle(
                                fontWeight: FontWeight.normal,
                                color: Color(0xFF26ADA3),
                                fontSize: 16,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    PopupMenuItem<String>(
                      child: GestureDetector(
                        onTap: () {
                          Navigator.pop(context);
                          if (list_sale.isNotEmpty || list_purchase.isNotEmpty) {
                            generateAndShareCSV_ItemDetail();
                          } else {
                            showToast('Data Not Found');
                          }
                        },
                        child: Row(
                          children: [
                            Icon(
                              Icons.add_chart_outlined,
                              size: 16,
                              color: Color(0xFF26ADA3),
                            ),
                            SizedBox(width: 5),
                            Text(
                              'Share as CSV',
                              style: TextStyle(
                                fontWeight: FontWeight.normal,
                                color: Color(0xFF26ADA3),
                                fontSize: 16,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
      body: _isLoading
          ? Center(child: AppLogoLoader())
          : ListView(
              padding: EdgeInsets.only(left: 16, right: 16, bottom: 12, top: 8),
              children: [
                if (isDateVisible) _buildDateSelector(context),
                if (isDateVisible) SizedBox(height: 8),

                _buildItemOverviewCard(),

                if (salesummary_visible || purchasesummary_visible)
                  SizedBox(height: 8),
                if (salesummary_visible)
                  _buildSummaryCard(context, isSales: true),
                if (purchasesummary_visible)
                  _buildSummaryCard(context, isSales: false),
              ],
            ),
    );
  }

  Widget _buildItemOverviewCard() {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 0),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(18),
        border: Theme.of(context).brightness == Brightness.dark
            ? Border.all(color: Colors.white.withOpacity(0.10), width: 1)
            : null,
        boxShadow: [
          BoxShadow(
            color: Colors.black12.withOpacity(0.08),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18.0, vertical: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            /// 🔹 Item Name
            Row(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Colors.blue.shade400, Colors.cyan.shade600],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.blue.withOpacity(0.3),
                        blurRadius: 6,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.shopping_bag_rounded,
                    color: Colors.white,
                    size: 18,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    itemname,
                    style: GoogleFonts.poppins(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 12),

            /// 🔹 Alias
            if (isItemAliasVisible) ...[
              Container(
                margin: const EdgeInsets.symmetric(vertical: 4),
                padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 2),
                decoration: BoxDecoration(
                  color: Theme.of(context).brightness == Brightness.dark
                      ? Colors.transparent
                      : Colors.grey.shade50.withOpacity(0.6),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Row(
                  children: [
                    // 🔹 Gradient Icon Badge
                    Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            Colors.indigo.shade400,
                            Colors.deepPurple.shade600,
                          ],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.indigo.withOpacity(0.3),
                            blurRadius: 6,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.badge_rounded,
                        color: Colors.white,
                        size: 18,
                      ),
                    ),

                    const SizedBox(width: 14),

                    // 🔹 Alias Value
                    Expanded(
                      child: Text(
                        alias,
                        style: GoogleFonts.poppins(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: Theme.of(context).colorScheme.onSurface,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],

            /// 🔹 Inventory
            Container(
              margin: const EdgeInsets.symmetric(vertical: 4),
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 2),
              decoration: BoxDecoration(
                color: Theme.of(context).brightness == Brightness.dark
                    ? Colors.transparent
                    : Colors.grey.shade50.withOpacity(0.6),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                children: [
                  // 🔹 Gradient Icon Badge
                  Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          Colors.orangeAccent.shade200,
                          Colors.deepOrange.shade400,
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.orangeAccent.withOpacity(0.3),
                          blurRadius: 6,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.inventory_2_rounded,
                      color: Colors.white,
                      size: 18,
                    ),
                  ),
                  const SizedBox(width: 14),

                  // 🔹 Label
                  Expanded(
                    child: Text(
                      "Inventory Closing",
                      style: GoogleFonts.poppins(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),

                  // 🔹 Value
                  Text(
                    inventory_closing == 'null' ? '0' : inventory_closing,
                    style: GoogleFonts.poppins(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                ],
              ),
            ),

            /// 🔹 Description
            if (isItemDescVisible) ...[
              const Divider(height: 28, thickness: 0.5),

              // 🔹 Title Row with Gradient Badge
              Container(
                margin: const EdgeInsets.symmetric(vertical: 2),
                padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 2),
                decoration: BoxDecoration(
                  color: Theme.of(context).brightness == Brightness.dark
                      ? Colors.transparent
                      : Colors.grey.shade50.withOpacity(0.6),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            Colors.blueGrey.shade400,
                            Colors.blueGrey.shade700,
                          ],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.blueGrey.withOpacity(0.3),
                            blurRadius: 6,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.description_rounded,
                        color: Colors.white,
                        size: 18,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Text(
                      "Description",
                      style: GoogleFonts.poppins(
                        fontWeight: FontWeight.w600,
                        fontSize: 15,
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 8),

              // 🔹 Description Text
              Text(
                item_desc,
                style: GoogleFonts.poppins(
                  fontSize: 14,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  height: 1.4,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildDateSelector(BuildContext context) {
    final tintColor = Theme.of(context).brightness == Brightness.dark
        ? Colors.white.withOpacity(0.06)
        : Colors.grey.shade100;
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(14),
        border: Theme.of(context).brightness == Brightness.dark
            ? Border.all(color: Colors.white.withOpacity(0.10), width: 1)
            : null,
        boxShadow: [
          BoxShadow(
            color: Colors.black12.withOpacity(0.06),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        children: [
          /// Dropdown
          Container(
            width: double.infinity,
            height: 38,
            padding: EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(
              color: tintColor,
              borderRadius: BorderRadius.circular(12),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                isExpanded: true,
                isDense: true,
                value: _selecteddate,
                icon: Icon(
                  Icons.expand_more,
                  size: 18,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
                style: GoogleFonts.poppins(
                  color: Theme.of(context).colorScheme.onSurface,
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                ),
                dropdownColor: Theme.of(context).colorScheme.surface,
                onChanged: (String? val) {
                  if (val != null) _handleDate(val);
                },
                items: date_range.map((e) {
                  return DropdownMenuItem<String>(value: e, child: Text(e));
                }).toList(),
              ),
            ),
          ),

          SizedBox(height: 8),

          /// Date Range Display (Clickable)
          InkWell(
            onTap: () => _selectDateRange(context),
            borderRadius: BorderRadius.circular(12),
            child: Container(
              width: double.infinity,
              padding: EdgeInsets.symmetric(horizontal: 10, vertical: 9),
              decoration: BoxDecoration(
                color: tintColor,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.calendar_month_rounded, size: 15, color: app_color),
                  SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      "$startdate_text → $enddate_text",
                      textAlign: TextAlign.center,
                      style: GoogleFonts.poppins(
                        fontWeight: FontWeight.w600,
                        fontSize: 12.5,
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                      softWrap: true,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMonthlyList(
    BuildContext context,
    List<Sale_Purc> list,
    bool isSales,
  ) {
    return Column(
      children: list
          .map((card) {
            final month = card.month;
            final parsedAmount = double.tryParse(card.amount);
            DateTime? parsedDate;
            try {
              parsedDate = DateFormat('MMMM yyyy').parse(month);
            } catch (_) {
              parsedDate = null;
            }
            // Skip entries the backend sent with an unparseable amount/month
            // instead of throwing and crashing the whole list.
            if (parsedAmount == null || parsedDate == null) {
              return const SizedBox.shrink();
            }
            final amount = parsedAmount.toStringAsFixed(decimal!);
            final date = parsedDate;
            final startOfMonth = DateFormat(
          'yyyyMMdd',
        ).format(DateTime(date.year, date.month, 1));
        final endOfMonth = DateFormat(
          'yyyyMMdd',
        ).format(DateTime(date.year, date.month + 1, 0));
        final vchtype = isSales ? 'Sales' : 'Purchase';

        return InkWell(
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => ItemsDrillDown(
                  startdate_string: startOfMonth,
                  enddate_string: endOfMonth,
                  type: vchtype,
                  total: amount,
                  item_name: itemname,
                ),
              ),
            );
          },
          borderRadius: BorderRadius.circular(12),
          child: Container(
            margin: EdgeInsets.symmetric(vertical: 6),
            padding: EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: Theme.of(context).cardColor,

              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: Colors.orange.withOpacity(0.3),
                width: 1,
              ),
            ),
            child: Row(
              children: [
                // 🔹 Gradient Icon Badge
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Colors.orange.withOpacity(0.6), Colors.orange],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.orange.withOpacity(0.25),
                        blurRadius: 6,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.calendar_month_rounded,
                    color: Colors.white,
                    size: 18,
                  ),
                ),

                const SizedBox(width: 14),

                // 🔹 Month Name
                Expanded(
                  child: Text(
                    month,
                    style: GoogleFonts.poppins(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w500,
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                ),

                // 🔹 Amount with arrow
                currencyAmountText(
                  currencyCode: _currencyCode,
                  symbol: currencysymbol,
                  amountText: formatTotal(amount, decimals: decimal!),
                  style: GoogleFonts.poppins(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w600,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),

                Icon(
                  Icons.chevron_right_rounded,
                  size: 20,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget buildSectionTitle(IconData icon, String title) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [app_color.withOpacity(0.7), app_color],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: app_color.withOpacity(0.3),
                  blurRadius: 6,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: Icon(icon, size: 20, color: Colors.white),
          ),
          const SizedBox(width: 10),
          Text(
            title,
            style: GoogleFonts.poppins(
              fontSize: 17,
              fontWeight: FontWeight.bold,
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
        ],
      ),
    );
  }

  // Matches _buildSummaryMetric's value Text style (fontSize 14, w700,
  // onSurface) so the Dirham glyph swap-in is visually seamless.
  Widget _summaryCurrencyValue(String amountText) {
    return currencyAmountText(
      currencyCode: _currencyCode,
      symbol: currencysymbol,
      amountText: amountText,
      style: GoogleFonts.poppins(
        fontSize: 14,
        fontWeight: FontWeight.w700,
        color: Theme.of(context).colorScheme.onSurface,
      ),
    );
  }

  Widget _buildSummaryMetric(String label, String value, {Widget? valueWidget}) {
    IconData icon = Icons.info;
    LinearGradient gradient = LinearGradient(
      colors: [Colors.grey.shade400, Colors.grey.shade600],
    );

    final labelLower = label.toLowerCase();

    if (labelLower.contains('total net')) {
      icon = Icons.attach_money_rounded;
      gradient = LinearGradient(
        colors: [Colors.green.shade400, Colors.green.shade700],
      );
    } else if (labelLower.contains('last') && labelLower.contains('date')) {
      icon = Icons.event;
      gradient = LinearGradient(
        colors: [Colors.indigo.shade400, Colors.indigo.shade700],
      );
    } else if (labelLower.contains('last') && labelLower.contains('price')) {
      icon = Icons.price_change_rounded;
      gradient = LinearGradient(
        colors: [Colors.orange.shade400, Colors.deepOrange.shade600],
      );
    } else if (labelLower.contains('qty')) {
      icon = Icons.numbers_rounded;
      gradient = LinearGradient(
        colors: [Colors.blueGrey.shade400, Colors.blueGrey.shade700],
      );
    } else if (labelLower.contains('min rate')) {
      icon = Icons.trending_down_rounded;
      gradient = LinearGradient(
        colors: [Colors.red.shade400, Colors.red.shade700],
      );
    } else if (labelLower.contains('max rate')) {
      icon = Icons.trending_up_rounded;
      gradient = LinearGradient(
        colors: [Colors.teal.shade400, Colors.teal.shade700],
      );
    } else if (labelLower.contains('invoices')) {
      icon = Icons.receipt_long_rounded;
      gradient = LinearGradient(
        colors: [Colors.deepPurple.shade400, Colors.deepPurple.shade700],
      );
    }

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 2),
      decoration: BoxDecoration(
        color: Theme.of(context).brightness == Brightness.dark
            ? Colors.transparent
            : Colors.grey.shade50.withOpacity(0.6),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          // 🔹 Icon Badge with gradient
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              gradient: gradient,
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: Colors.black12.withOpacity(0.2),
                  blurRadius: 8,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Icon(icon, color: Colors.white, size: 18),
          ),
          const SizedBox(width: 14),

          // 🔹 Label
          Expanded(
            child: Text(
              label,
              style: GoogleFonts.poppins(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),

          // 🔹 Value
          valueWidget ??
              Text(
                value,
                style: GoogleFonts.poppins(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
        ],
      ),
    );
  }

  Widget _buildSummaryCard(BuildContext context, {required bool isSales}) {
    final title = isSales ? 'SALES SUMMARY' : 'PURCHASE SUMMARY';
    final icon = isSales
        ? Icons.trending_up_rounded
        : Icons.shopping_cart_outlined;
    final total = _formatIntValue(
      isSales ? sales_totalnetsales : purchase_totalnetpurchase,
    );
    final lastDate = _formatValue(
      isSales ? sales_lastsaledate : purchase_lastpurchasedate,
    );
    final lastPrice = _formatIntValue(
      isSales ? sales_lastsaleprice : purchase_lastpurchaseprice,
    );

    print('last $isSales price $lastPrice');
    final qty = _formatValue(
      isSales ? sales_totalsalesqty : purchase_totalpurchaseqty,
    );
    final minRate = _formatIntValue(isSales ? sales_minrate : purchase_minrate);
    final maxRate = _formatIntValue(isSales ? sales_maxrate : purchase_maxrate);
    final invoices = _formatValue(
      isSales ? sales_noofinvoices : purchase_noofinvoices,
    );
    final listData = isSales ? list_sale : list_purchase;
    final isClickable = isSales
        ? isSalesClickableCard
        : isPurchaseClickableCard;
    final isExpanded = isSales ? isClicked_Salesicon : isClicked_Purchaseicon;
    final isVisible = isSales ? isVisibleSalesList : isVisiblePurchaseList;
    final hasData =
        (isSales ? sales_noofinvoices : purchase_noofinvoices) !=
        'Not Available';

    if (!hasData) {
      return _buildSummaryEmptyState(title, icon, isSales);
    }

    return Container(
      margin: EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(20),
        border: Theme.of(context).brightness == Brightness.dark
            ? Border.all(color: Colors.white.withOpacity(0.10), width: 1)
            : null,
        boxShadow: [
          BoxShadow(
            color: Colors.black12.withOpacity(0.08),
            blurRadius: 12,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            /// Title Row
            buildSectionTitle(Icons.analytics_rounded, title),

            SizedBox(height: 16),

            /// Data Rows
            _buildSummaryMetric(
              'Total Net ${isSales ? 'Sales' : 'Purchase'}',
              '',
              valueWidget: _summaryCurrencyValue(total),
            ),
            _buildSummaryMetric(
              'Last ${isSales ? 'Sale' : 'Purchase'} Date',
              lastDate,
            ),
            _buildSummaryMetric(
              'Last ${isSales ? 'Sale' : 'Purchase'} Price',
              '',
              valueWidget: _summaryCurrencyValue(lastPrice),
            ),
            _buildSummaryMetric(
              'Total ${isSales ? 'Sale' : 'Purchase'} Qty',
              qty,
            ),
            _buildSummaryMetric(
              'Min Rate',
              '',
              valueWidget: _summaryCurrencyValue(minRate),
            ),
            _buildSummaryMetric(
              'Max Rate',
              '',
              valueWidget: _summaryCurrencyValue(maxRate),
            ),
            _buildSummaryMetric('No of Invoices', invoices),

            Divider(height: 18),

            /// Expand Section Header
            InkWell(
              onTap: () {
                if (isClickable) {
                  setState(() {
                    if (isSales) {
                      isClicked_Salesicon = !isClicked_Salesicon;
                      isVisibleSalesList = !isVisibleSalesList;
                    } else {
                      isClicked_Purchaseicon = !isClicked_Purchaseicon;
                      isVisiblePurchaseList = !isVisiblePurchaseList;
                    }
                  });
                }
              },
              borderRadius: BorderRadius.circular(12),
              child: Container(
                padding: EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                decoration: BoxDecoration(
                  color: Colors.orange.withOpacity(0.05),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: Colors.orange.withOpacity(0.3),
                    width: 0.5,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.orange.withOpacity(0.05),
                      blurRadius: 8,
                      offset: Offset(0, 3),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    // 🔹 Gradient Icon Badge
                    Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            Colors.orange.withOpacity(0.6),
                            Colors.orange,
                          ],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.orange.withOpacity(0.25),
                            blurRadius: 6,
                            offset: const Offset(0, 3),
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.calendar_month_rounded,
                        color: Colors.white,
                        size: 18,
                      ),
                    ),

                    const SizedBox(width: 14),

                    // 🔹 Title
                    Expanded(
                      child: Text(
                        'Month Wise ${isSales ? 'Sales' : 'Purchase'}',
                        style: GoogleFonts.poppins(
                          fontWeight: FontWeight.w600,
                          fontSize: 15,
                          color: Theme.of(context).colorScheme.onSurface,
                        ),
                      ),
                    ),

                    SizedBox(width: 4),

                    // 🔹 Total value
                    currencyAmountText(
                      currencyCode: _currencyCode,
                      symbol: currencysymbol,
                      amountText: total,
                      style: GoogleFonts.poppins(
                        fontWeight: FontWeight.w700,
                        fontSize: 14.5,
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                    ),
                    const SizedBox(width: 8),

                    // 🔹 Expand/Collapse Icon with subtle bg
                    Icon(
                      isExpanded ? Icons.expand_less : Icons.expand_more,
                      size: 18,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ],
                ),
              ),
            ),

            /// Expanded Monthly List
            if (isVisible)
              AnimatedContainer(
                duration: Duration(milliseconds: 300),
                curve: Curves.easeInOut,
                child: Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: _buildMonthlyList(context, listData, isSales),
                ),
              ),
          ],
        ),
      ),
    );
  }

  // 🔹 Shown instead of the full metrics list when there's no Sales/Purchase
  // data for the selected period, so the card doesn't fill up with
  // meaningless "0"/"Not Available" rows.
  Widget _buildSummaryEmptyState(String title, IconData icon, bool isSales) {
    return Container(
      margin: EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(20),
        border: Theme.of(context).brightness == Brightness.dark
            ? Border.all(color: Colors.white.withOpacity(0.10), width: 1)
            : null,
        boxShadow: [
          BoxShadow(
            color: Colors.black12.withOpacity(0.08),
            blurRadius: 12,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            buildSectionTitle(icon, title),
            SizedBox(height: 16),
            Center(
              child: Column(
                children: [
                  Icon(
                    Icons.inbox_outlined,
                    size: 32,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'No ${isSales ? 'sales' : 'purchase'} recorded for this period',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.poppins(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w500,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
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

  String _formatIntValue(String? value) {
    if (value == null || value.trim().toLowerCase() == 'not available') {
      return '0';
    }
    return value;
  }

  String _formatValue(String? value) {
    if (value == null || value.trim().toLowerCase() == 'not available') {
      return 'N/A';
    }
    return value;
  }
}
