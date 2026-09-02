import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../Dashboard.dart' show data, months_chart, piechartsaleslist, piechartpurchaselist;
import '../api/api_exception.dart';
import '../api/monthly_bucket_helper.dart' show parseMoneyField;
import '../utils/number_formatter.dart';
import 'repository_providers.dart';

/// Everything `Dashboard.dart`'s `_MyHomePageState` used to mutate via
/// `setState()` and actually read back in `build()`/its `_build*` helpers.
/// A handful of legacy prefs-derived flags (`isDashEnable`/`isRolesEnable`/
/// `isUserEnable`/`isRolesVisible`/`isUserVisible`/`SecuritybtnAcessHolder`,
/// the `isVisibleItemBtn`/`isVisiblePartyBtn`/`isVisibleTransactionBtn`/
/// `isVisibleEntriesBtn` quartet and all the party/entries prefs feeding
/// them, `allitems_visibility`/`fastmovingitems_visibility`/
/// `inactiveitems_visibility`, `isChartsVisible`, `_isDashVisible`/
/// `_isEnddateVisible`/`_IsSizeboxVisible`, `apiResponseTime`) were dropped
/// - confirmed via grep that every read site was either the commented-out
/// `Sidebar`/floating-tile block in `build()` or nowhere at all. `vchtype`
/// was dropped too - it was only ever assigned immediately before a
/// `Navigator.push` that used it, so the KPI-tile taps now pass the literal
/// voucher-type string straight through instead of round-tripping it via a
/// field.
class DashboardState {
  final String company;
  final String name;
  final String? serialNo;
  final String? licenseExpiry;
  final bool isExpired;
  final bool initialized;

  final String startdateText;
  final String enddateText;
  final String startDateString;
  final String endDateString;
  final String selectedDate;
  final bool isTextEnabled;
  final bool isLoading;
  final bool isRefreshing;

  final int decimal;
  final NumberScale selectedScale;
  final String currencySymbol;
  final String currencyCode;

  final double salesValue;
  final double purchaseValue;
  final double receiptValue;
  final double paymentValue;
  final double outstandingReceivableValue;
  final double outstandingPayableValue;
  final double cashValue;

  final bool salesVisibility;
  final bool purchaseVisibility;
  final bool receiptVisibility;
  final bool paymentVisibility;
  final bool receivableVisibility;
  final bool payableVisibility;
  final bool cashVisibility;
  final bool isVisibleNoAccess;
  final bool isVisibleDate;

  final bool isBarChartVisible;
  final bool isVisibleLineChart;
  final bool isPieChartVisible;
  final bool isSalesPieChartVisible;
  final bool isPurchasePieChartVisible;
  final List<double> salesDataList;
  final List<double> recDataList;

  final bool isSalesEntryVisible;
  final bool isReceiptEntryVisible;
  final bool isSalesOrderEntryVisible;
  final bool isDeliveryNoteEntryVisible;

  final String? errorMessage;

  const DashboardState({
    this.company = '',
    this.name = '',
    this.serialNo,
    this.licenseExpiry,
    this.isExpired = false,
    this.initialized = false,
    this.startdateText = '',
    this.enddateText = '',
    this.startDateString = '',
    this.endDateString = '',
    this.selectedDate = 'Today',
    this.isTextEnabled = true,
    this.isLoading = false,
    this.isRefreshing = false,
    this.decimal = 2,
    this.selectedScale = NumberScale.thousand,
    this.currencySymbol = '',
    this.currencyCode = 'AED',
    this.salesValue = 0.0,
    this.purchaseValue = 0.0,
    this.receiptValue = 0.0,
    this.paymentValue = 0.0,
    this.outstandingReceivableValue = 0.0,
    this.outstandingPayableValue = 0.0,
    this.cashValue = 0.0,
    this.salesVisibility = false,
    this.purchaseVisibility = false,
    this.receiptVisibility = false,
    this.paymentVisibility = false,
    this.receivableVisibility = false,
    this.payableVisibility = false,
    this.cashVisibility = false,
    this.isVisibleNoAccess = false,
    this.isVisibleDate = false,
    this.isBarChartVisible = false,
    this.isVisibleLineChart = false,
    this.isPieChartVisible = false,
    this.isSalesPieChartVisible = false,
    this.isPurchasePieChartVisible = false,
    this.salesDataList = const [],
    this.recDataList = const [],
    this.isSalesEntryVisible = false,
    this.isReceiptEntryVisible = false,
    this.isSalesOrderEntryVisible = false,
    this.isDeliveryNoteEntryVisible = false,
    this.errorMessage,
  });

  DashboardState copyWith({
    String? company,
    String? name,
    String? serialNo,
    String? licenseExpiry,
    bool? isExpired,
    bool? initialized,
    String? startdateText,
    String? enddateText,
    String? startDateString,
    String? endDateString,
    String? selectedDate,
    bool? isTextEnabled,
    bool? isLoading,
    bool? isRefreshing,
    int? decimal,
    NumberScale? selectedScale,
    String? currencySymbol,
    String? currencyCode,
    double? salesValue,
    double? purchaseValue,
    double? receiptValue,
    double? paymentValue,
    double? outstandingReceivableValue,
    double? outstandingPayableValue,
    double? cashValue,
    bool? salesVisibility,
    bool? purchaseVisibility,
    bool? receiptVisibility,
    bool? paymentVisibility,
    bool? receivableVisibility,
    bool? payableVisibility,
    bool? cashVisibility,
    bool? isVisibleNoAccess,
    bool? isVisibleDate,
    bool? isBarChartVisible,
    bool? isVisibleLineChart,
    bool? isPieChartVisible,
    bool? isSalesPieChartVisible,
    bool? isPurchasePieChartVisible,
    List<double>? salesDataList,
    List<double>? recDataList,
    bool? isSalesEntryVisible,
    bool? isReceiptEntryVisible,
    bool? isSalesOrderEntryVisible,
    bool? isDeliveryNoteEntryVisible,
    String? errorMessage,
    bool clearError = false,
  }) {
    return DashboardState(
      company: company ?? this.company,
      name: name ?? this.name,
      serialNo: serialNo ?? this.serialNo,
      licenseExpiry: licenseExpiry ?? this.licenseExpiry,
      isExpired: isExpired ?? this.isExpired,
      initialized: initialized ?? this.initialized,
      startdateText: startdateText ?? this.startdateText,
      enddateText: enddateText ?? this.enddateText,
      startDateString: startDateString ?? this.startDateString,
      endDateString: endDateString ?? this.endDateString,
      selectedDate: selectedDate ?? this.selectedDate,
      isTextEnabled: isTextEnabled ?? this.isTextEnabled,
      isLoading: isLoading ?? this.isLoading,
      isRefreshing: isRefreshing ?? this.isRefreshing,
      decimal: decimal ?? this.decimal,
      selectedScale: selectedScale ?? this.selectedScale,
      currencySymbol: currencySymbol ?? this.currencySymbol,
      currencyCode: currencyCode ?? this.currencyCode,
      salesValue: salesValue ?? this.salesValue,
      purchaseValue: purchaseValue ?? this.purchaseValue,
      receiptValue: receiptValue ?? this.receiptValue,
      paymentValue: paymentValue ?? this.paymentValue,
      outstandingReceivableValue:
          outstandingReceivableValue ?? this.outstandingReceivableValue,
      outstandingPayableValue:
          outstandingPayableValue ?? this.outstandingPayableValue,
      cashValue: cashValue ?? this.cashValue,
      salesVisibility: salesVisibility ?? this.salesVisibility,
      purchaseVisibility: purchaseVisibility ?? this.purchaseVisibility,
      receiptVisibility: receiptVisibility ?? this.receiptVisibility,
      paymentVisibility: paymentVisibility ?? this.paymentVisibility,
      receivableVisibility: receivableVisibility ?? this.receivableVisibility,
      payableVisibility: payableVisibility ?? this.payableVisibility,
      cashVisibility: cashVisibility ?? this.cashVisibility,
      isVisibleNoAccess: isVisibleNoAccess ?? this.isVisibleNoAccess,
      isVisibleDate: isVisibleDate ?? this.isVisibleDate,
      isBarChartVisible: isBarChartVisible ?? this.isBarChartVisible,
      isVisibleLineChart: isVisibleLineChart ?? this.isVisibleLineChart,
      isPieChartVisible: isPieChartVisible ?? this.isPieChartVisible,
      isSalesPieChartVisible:
          isSalesPieChartVisible ?? this.isSalesPieChartVisible,
      isPurchasePieChartVisible:
          isPurchasePieChartVisible ?? this.isPurchasePieChartVisible,
      salesDataList: salesDataList ?? this.salesDataList,
      recDataList: recDataList ?? this.recDataList,
      isSalesEntryVisible: isSalesEntryVisible ?? this.isSalesEntryVisible,
      isReceiptEntryVisible:
          isReceiptEntryVisible ?? this.isReceiptEntryVisible,
      isSalesOrderEntryVisible:
          isSalesOrderEntryVisible ?? this.isSalesOrderEntryVisible,
      isDeliveryNoteEntryVisible:
          isDeliveryNoteEntryVisible ?? this.isDeliveryNoteEntryVisible,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    );
  }
}

class DashboardNotifier extends StateNotifier<DashboardState> {
  final Ref _ref;
  late SharedPreferences _prefs;
  bool _prefsReady = false;

  DashboardNotifier(this._ref) : super(const DashboardState()) {
    _init();
  }

  void clearError() => state = state.copyWith(clearError: true);

  /// Widget-owned date-range-picker flows (`_selectDateRange*` in
  /// Dashboard.dart) still need raw prefs access for a couple of one-off
  /// reads/writes that don't otherwise belong on `DashboardState` (the
  /// cached `startdate`/`enddate`/`startfrom` values used only to seed a
  /// `showDateRangePicker` call) - exposed as thin passthroughs rather than
  /// duplicating a whole SharedPreferences instance in the widget.
  String? getPref(String key) => _prefsReady ? _prefs.getString(key) : null;
  Future<void> setPref(String key, String value) async {
    if (_prefsReady) await _prefs.setString(key, value);
  }

  // Stashed for the widget's post-frame license-dialog callback (it needs
  // both `state.isExpired` and this day count for the "expiring soon"
  // dialog's message).
  int? _daysUntilExpiry;
  int? get daysUntilExpiry => _daysUntilExpiry;

  String? _barchartdashprefs;
  String? _linechartdashprefs;
  String? _piechartdashprefs;

  NumberScale _numberScaleFromString(String? scale) {
    switch (scale) {
      case 'full':
        return NumberScale.full;
      case 'million':
        return NumberScale.million;
      case 'billion':
        return NumberScale.billion;
      case 'thousand':
      default:
        return NumberScale.thousand;
    }
  }

  String _numberScaleToString(NumberScale scale) {
    switch (scale) {
      case NumberScale.full:
        return 'full';
      case NumberScale.million:
        return 'million';
      case NumberScale.billion:
        return 'billion';
      case NumberScale.thousand:
        return 'thousand';
    }
  }

  Future<void> saveNumberScale(NumberScale scale) async {
    state = state.copyWith(selectedScale: scale);
    await _prefs.setString('number_scale', _numberScaleToString(scale));
  }

  Future<void> _init() async {
    _prefs = await SharedPreferences.getInstance();
    _prefsReady = true;

    final company = _prefs.getString('company_name') ?? '';
    final serialNo = _prefs.getString('serial_no');
    final licenseExpiry = _prefs.getString('license_expiry');
    final baseCurrency = _prefs.getString('base_currency') ?? '';
    print('base_currency -> $baseCurrency');

    final selectedScale =
        _numberScaleFromString(_prefs.getString('number_scale'));

    final salesEntryHolder = _prefs.getString('salesentry') ?? 'False';
    final receiptEntryHolder = _prefs.getString('receiptentry') ?? 'False';
    final salesOrderEntryHolder =
        _prefs.getString('salesorderentry') ?? 'True';
    final deliveryNoteEntryHolder =
        _prefs.getString('deliverynoteentry') ?? 'True';

    final selectedDate = _prefs.getString('dateRangeOption') ?? 'Today';
    print('selected date option -> $selectedDate');

    final decimal = _prefs.getInt('decimalplace') ?? 2;

    DateTime? expireDate;
    try {
      expireDate = licenseExpiry == null || licenseExpiry.isEmpty
          ? null
          : DateTime.parse(licenseExpiry);
    } catch (_) {
      expireDate = null;
    }

    bool isExpired;
    int? daysUntilExpiry;
    if (expireDate != null) {
      final today = DateTime.now();
      final todayDate = DateTime(today.year, today.month, today.day);
      final expiryDate =
          DateTime(expireDate.year, expireDate.month, expireDate.day);
      isExpired = todayDate.isAfter(expiryDate);
      daysUntilExpiry = expiryDate.difference(todayDate).inDays;
    } else {
      isExpired = true;
    }

    String currencyCode = _prefs.getString('currencycode') ?? 'AED';
    String currencySymbol;
    try {
      if (currencyCode == 'INR' ||
          currencyCode == 'EUR' ||
          currencyCode == 'USD' ||
          currencyCode == 'PKR') {
        final format =
            NumberFormat.simpleCurrency(locale: 'en', name: currencyCode);
        currencySymbol = format.currencySymbol;
      } else {
        final format =
            NumberFormat.currency(locale: 'en', name: currencyCode);
        currencySymbol = format.currencySymbol;
      }
    } catch (e) {
      final format = NumberFormat.currency(locale: 'en', name: currencyCode);
      currencySymbol = format.currencySymbol;
    }

    _barchartdashprefs = _prefs.getString('barchartdash') ?? 'False';
    _linechartdashprefs = _prefs.getString('linechartdash') ?? 'False';
    _piechartdashprefs = _prefs.getString('piechartdash') ?? 'False';

    final salesVisibility =
        (_prefs.getString('salesdash') ?? 'False') == 'True';
    final purchaseVisibility =
        (_prefs.getString('purchasedash') ?? 'False') == 'True';
    final receiptVisibility =
        (_prefs.getString('receiptsdash') ?? 'False') == 'True';
    final paymentVisibility =
        (_prefs.getString('paymentsdash') ?? 'False') == 'True';
    final receivableVisibility =
        (_prefs.getString('outstandingreceivabledash') ?? 'False') == 'True';
    final payableVisibility =
        (_prefs.getString('outstandingpayabledash') ?? 'False') == 'True';
    final cashVisibility =
        (_prefs.getString('cashdash') ?? 'False') == 'True';

    // Chart-visibility flags haven't been fetched yet at init time (they
    // only become true after fetchDashData's chart calls resolve), same as
    // the original _initSharedPreferences reading the still-default
    // isBarChartVisible/isVisibleLineChart/isPieChartVisible fields here.
    final bool isVisibleNoAccess = !salesVisibility &&
        !purchaseVisibility &&
        !receiptVisibility &&
        !paymentVisibility &&
        !receivableVisibility &&
        !payableVisibility &&
        !cashVisibility &&
        !state.isBarChartVisible &&
        !state.isVisibleLineChart &&
        !state.isPieChartVisible;

    final name =
        _prefs.getString('name_nav') ?? _prefs.getString('name') ?? '';

    state = state.copyWith(
      company: company,
      serialNo: serialNo,
      licenseExpiry: licenseExpiry,
      isExpired: isExpired,
      decimal: decimal,
      selectedScale: selectedScale,
      currencySymbol: currencySymbol,
      currencyCode: currencyCode,
      salesVisibility: salesVisibility,
      purchaseVisibility: purchaseVisibility,
      receiptVisibility: receiptVisibility,
      paymentVisibility: paymentVisibility,
      receivableVisibility: receivableVisibility,
      payableVisibility: payableVisibility,
      cashVisibility: cashVisibility,
      isVisibleNoAccess: isVisibleNoAccess,
      isVisibleDate: !isVisibleNoAccess,
      isSalesEntryVisible: salesEntryHolder == 'True',
      isReceiptEntryVisible: receiptEntryHolder == 'True',
      isSalesOrderEntryVisible: salesOrderEntryHolder == 'True',
      isDeliveryNoteEntryVisible: deliveryNoteEntryHolder == 'True',
      name: name,
      selectedDate: selectedDate,
    );

    _daysUntilExpiry = daysUntilExpiry;
    state = state.copyWith(initialized: true);

    final datetype = _prefs.getString('datetype');
    await applyDatePreset(datetype ?? selectedDate);
  }

  DateTime _parseYyyyMMdd(String value) => DateTime(
        int.parse(value.substring(0, 4)),
        int.parse(value.substring(4, 6)),
        int.parse(value.substring(6, 8)),
      );

  void _generateMonthsList() {
    months_chart.clear();
    DateTime startDate = DateTime.parse(state.startDateString);
    DateTime endDate = DateTime.parse(state.endDateString);
    while (
        startDate.isBefore(endDate) || startDate.isAtSameMomentAs(endDate)) {
      months_chart.add(DateFormat('MMM-yy').format(startDate));
      startDate =
          DateTime(startDate.year, startDate.month + 1, startDate.day);
    }
  }

  /// Mirrors `Dashboard.dart`'s `fetchDashData` (see its own doc-comment
  /// for why this hits `reports/dashboard/*` directly instead of the
  /// client-side full-voucher-fetch workaround it replaced). Errors are
  /// surfaced via `state.errorMessage` for the widget's `ref.listen` bridge
  /// instead of a direct `showAppMessage(context, ...)` call, and (per the
  /// RolesView/ChangePassword precedent for a notifier with no
  /// `BuildContext`) a non-`ApiException` failure gets a plain hardcoded
  /// fallback string rather than the original's localized
  /// `AppLocalizations.of(context).errorFetchingData`/`errorSomethingWentWrong`.
  Future<void> fetchDashData(String startdate, String enddate) async {
    if (state.isVisibleNoAccess) return;

    state = state.copyWith(isLoading: true);

    final from = _parseYyyyMMdd(startdate);
    final to = _parseYyyyMMdd(enddate);

    try {
      final summary = await _ref
          .read(dashboardRepositoryProvider)
          .summary(from: from, to: to);

      final salesValue = parseMoneyField(summary['sales']);
      final purchaseValue = parseMoneyField(summary['purchase']);
      final receiptValue = parseMoneyField(summary['receipt']);
      final paymentValue = parseMoneyField(summary['payment']);
      final cashValue = parseMoneyField(summary['cash']);
      final receivableValue = parseMoneyField(summary['receivable']);
      final payableValue = parseMoneyField(summary['payable']);

      state = state.copyWith(
        salesValue: salesValue,
        purchaseValue: purchaseValue,
        receiptValue: receiptValue,
        paymentValue: paymentValue,
        cashValue: cashValue,
        outstandingReceivableValue: receivableValue,
        outstandingPayableValue: payableValue,
      );

      await _prefs.setDouble('sales', salesValue);
      await _prefs.setDouble('purchase', purchaseValue);
      await _prefs.setDouble('receipt', receiptValue);
      await _prefs.setDouble('payment', paymentValue);
      await _prefs.setDouble('receivable', receivableValue);
      await _prefs.setDouble('payable', payableValue);
      await _prefs.setDouble('cash', cashValue);
    } on ApiException catch (e) {
      state = state.copyWith(errorMessage: e.message);
    } catch (e) {
      state = state.copyWith(
        errorMessage: 'Could not load dashboard data. Please try again.',
      );
    }

    try {
      if (_linechartdashprefs == 'True' ||
          _barchartdashprefs == 'True' ||
          _piechartdashprefs == 'True') {
        if (_linechartdashprefs == 'True' || _barchartdashprefs == 'True') {
          try {
            // `sales-chart` returns one flat period list (no year
            // grouping) - the multi-year line-overlay mode can't be
            // reconstructed from this shape, so it stays dropped
            // (`isVisibleLineChart` always false) regardless of the
            // `linechartdash` preference, same as before.
            final chartRows = await _ref
                .read(dashboardRepositoryProvider)
                .salesChart(from: from, to: to, groupBy: 'month');

            if (chartRows.isEmpty) {
              state = state.copyWith(
                isBarChartVisible: false,
                isVisibleLineChart: false,
                isLoading: false,
              );
            } else {
              data.clear();
              final salesDataList = <double>[];
              final recDataList = <double>[];
              for (final row in chartRows) {
                final sales = parseMoneyField(row['sales']);
                final receipt = parseMoneyField(row['receipt']);
                salesDataList.add(-sales);
                recDataList.add(receipt);
              }
              state = state.copyWith(
                isVisibleLineChart: false,
                isBarChartVisible: _barchartdashprefs == 'True',
                salesDataList: salesDataList,
                recDataList: recDataList,
              );
            }

            _generateMonthsList();
          } on ApiException catch (e) {
            state = state.copyWith(
              isVisibleLineChart: false,
              isBarChartVisible: false,
              errorMessage: e.message,
            );
          } catch (e) {
            state = state.copyWith(
              isVisibleLineChart: false,
              isBarChartVisible: false,
              errorMessage: 'Something went wrong. Please try again.',
            );
          }
        } else {
          state = state.copyWith(
            isVisibleLineChart: false,
            isBarChartVisible: false,
          );
        }

        if (_piechartdashprefs == 'True') {
          try {
            // `voucher-type-breakdown` already returns exactly this shape
            // server-side (grouped by voucherTypeMasterId/voucherTypeName
            // with `sales`/`purchase` pre-summed) - no client-side grouping
            // needed.
            final breakdownRows = await _ref
                .read(dashboardRepositoryProvider)
                .voucherTypeBreakdown(from: from, to: to);

            final salesSlices = breakdownRows
                .where((row) => parseMoneyField(row['sales']).abs() > 0)
                .map((row) => {
                      'name': row['voucherTypeName'] ?? 'Unknown',
                      'amount': parseMoneyField(row['sales']),
                    })
                .toList();
            final purchaseSlices = breakdownRows
                .where((row) => parseMoneyField(row['purchase']).abs() > 0)
                .map((row) => {
                      'name': row['voucherTypeName'] ?? 'Unknown',
                      'amount': parseMoneyField(row['purchase']),
                    })
                .toList();

            piechartsaleslist
              ..clear()
              ..addAll(salesSlices);
            piechartpurchaselist
              ..clear()
              ..addAll(purchaseSlices);

            if (piechartsaleslist.isEmpty && piechartpurchaselist.isEmpty) {
              state = state.copyWith(
                isPieChartVisible: false,
                isSalesPieChartVisible: false,
                isPurchasePieChartVisible: false,
              );
            } else {
              state = state.copyWith(
                isPieChartVisible: true,
                isSalesPieChartVisible: piechartsaleslist.isNotEmpty,
                isPurchasePieChartVisible: piechartpurchaselist.isNotEmpty,
              );
            }
          } on ApiException catch (e) {
            state = state.copyWith(
              isPieChartVisible: false,
              isPurchasePieChartVisible: false,
              isSalesPieChartVisible: false,
              errorMessage: e.message,
            );
          } catch (e) {
            state = state.copyWith(
              isPieChartVisible: false,
              isPurchasePieChartVisible: false,
              isSalesPieChartVisible: false,
              errorMessage: 'Something went wrong. Please try again.',
            );
          }
        }
      }
    } catch (e) {
      state = state.copyWith(errorMessage: e.toString());
    }

    state = state.copyWith(isLoading: false);
  }

  /// One shared implementation for every preset in `date_range`
  /// (`Today`/`Yesterday`/`This Month`/.../`Year To Date`) - the original
  /// `_handleDate`/`_handleRefresh`/`_selectDateRange_refresh`'s per-preset
  /// branches were byte-for-byte identical date arithmetic, just repeated
  /// per call site. `'Custom Date'` sets `isTextEnabled` and returns
  /// without fetching - the widget follows up with its own
  /// `showDateRangePicker` call (needs `BuildContext`), same as before.
  Future<void> applyDatePreset(String preset) async {
    state = state.copyWith(selectedDate: preset);

    if (preset == 'Custom Date') {
      state = state.copyWith(isTextEnabled: true);
      await _prefs.setString('datetype', preset);
      return;
    }

    DateTime start;
    DateTime end;
    switch (preset) {
      case 'Yesterday':
        start = end = DateTime.now().subtract(const Duration(days: 1));
        break;
      case 'This Month':
        final now = DateTime.now();
        start = DateTime(now.year, now.month, 1);
        end = DateTime(now.year, now.month + 1, 0);
        break;
      case 'Last Month':
        final now = DateTime.now();
        start = DateTime(now.year, now.month - 1, 1);
        end = DateTime(start.year, start.month + 1, 0);
        break;
      case 'This Year':
        final today = DateTime.now();
        start = DateTime(today.year, 1, 1);
        end = DateTime(today.year, 12, 31);
        break;
      case 'Last Year':
        final today = DateTime.now();
        start = DateTime(today.year - 1, 1, 1);
        end = DateTime(today.year - 1, 12, 31);
        break;
      case 'Year To Date':
        final now = DateTime.now();
        start = DateTime(now.year, 1, 1);
        end = DateTime(now.year, now.month, now.day);
        break;
      case 'Today':
      default:
        start = end = DateTime.now();
        break;
    }

    state = state.copyWith(isTextEnabled: false);
    await _applyRange(start, end);
    await _prefs.setString('datetype', preset);
  }

  /// Shared date-string/text computation + prefs persistence + fetch,
  /// reused by `applyDatePreset` and by the widget-driven custom-range
  /// pickers via [applyPickedRange].
  Future<void> _applyRange(DateTime start, DateTime end) async {
    final startMonth = DateFormat('MMM').format(start);
    final sdf = DateFormat('MM').format(start);
    final startDay = DateFormat('dd').format(start);
    final startYear = start.year;

    final endMonth = DateFormat('MMM').format(end);
    final sdfEnd = DateFormat('MM').format(end);
    final endDay = DateFormat('dd').format(end);
    final endYear = end.year;

    final startDateString = '$startYear$sdf$startDay';
    final endDateString = '$endYear$sdfEnd$endDay';
    final startdateText = '$startDay-$startMonth-$startYear';
    final enddateText = '$endDay-$endMonth-$endYear';

    state = state.copyWith(
      startDateString: startDateString,
      endDateString: endDateString,
      startdateText: startdateText,
      enddateText: enddateText,
    );

    await fetchDashData(startDateString, endDateString);
  }

  /// Used by the widget's `_selectDateRange`/`_selectDateRangeAuto`/
  /// `_selectDateRangeRefresh` once `showDateRangePicker` resolves.
  Future<void> applyPickedRange(DateTime start, DateTime end) async {
    await _applyRange(start, end);
    await _prefs.setString('startdate', state.startDateString);
    await _prefs.setString('enddate', state.endDateString);
  }

  /// Mirrors `_handleRefresh`'s pull-to-refresh flow: re-read the
  /// persisted `datetype` (falling back to whatever's already selected)
  /// and re-apply it. Returns `true` when the resolved preset is
  /// `'Custom Date'`, so the widget knows to open its own date-range
  /// picker afterward (same as the original always showing the picker on
  /// refresh's `'Custom Date'` branch, rather than only the first time).
  Future<bool> refresh() async {
    state = state.copyWith(isRefreshing: true);

    final datetype = _prefs.getString('datetype');
    final preset = datetype ?? state.selectedDate;
    await applyDatePreset(preset);

    final isCustom = preset == 'Custom Date';
    // Left true through a Custom Date resolution - the widget still has to
    // drive its own date-range picker in that case (see
    // `_selectDateRangeRefresh`), and that flow's "swipe down to refresh"
    // message check (`!isRefreshing`) depends on the flag staying true
    // until that picker interaction is done, same as the original
    // `_handleRefresh` only flipping `_isRefreshing` back to false at the
    // very end. Call [finishRefresh] once that's settled.
    if (!isCustom) {
      state = state.copyWith(isRefreshing: false);
    }
    return isCustom;
  }

  void finishRefresh() => state = state.copyWith(isRefreshing: false);
}

final dashboardNotifierProvider =
    StateNotifierProvider.autoDispose<DashboardNotifier, DashboardState>(
  (ref) => DashboardNotifier(ref),
);
