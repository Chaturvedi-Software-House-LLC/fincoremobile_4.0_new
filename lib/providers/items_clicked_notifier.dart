import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../ItemsClicked.dart';
import '../api/monthly_bucket_helper.dart';
import 'repository_providers.dart';

class ItemsClickedArgs {
  final String itemDesc;
  final String itemLastSaleDate;
  final String itemLastPurchDate;
  final String itemRate;
  final String lastPurcRate;
  final String alias;
  final int? stockItemMasterId;

  const ItemsClickedArgs({
    required this.itemDesc,
    required this.itemLastSaleDate,
    required this.itemLastPurchDate,
    required this.itemRate,
    required this.lastPurcRate,
    required this.alias,
    this.stockItemMasterId,
  });

  @override
  bool operator ==(Object other) =>
      other is ItemsClickedArgs &&
      other.itemDesc == itemDesc &&
      other.itemLastSaleDate == itemLastSaleDate &&
      other.itemLastPurchDate == itemLastPurchDate &&
      other.itemRate == itemRate &&
      other.lastPurcRate == lastPurcRate &&
      other.alias == alias &&
      other.stockItemMasterId == stockItemMasterId;

  @override
  int get hashCode => Object.hash(
        itemDesc,
        itemLastSaleDate,
        itemLastPurchDate,
        itemRate,
        lastPurcRate,
        alias,
        stockItemMasterId,
      );
}

class ItemsClickedState {
  final bool isLoading;
  final bool isDateVisible;
  final bool salesSummaryVisible;
  final bool purchaseSummaryVisible;
  final bool isSalesClickableCard;
  final bool isPurchaseClickableCard;
  final bool isVisibleSalesList;
  final bool isClickedSalesIcon;
  final bool isVisiblePurchaseList;
  final bool isClickedPurchaseIcon;
  final List<Sale_Purc> listSale;
  final List<Sale_Purc> listPurchase;
  final String salesTotalNetSales;
  final String salesLastSaleDate;
  final String salesLastSalePrice;
  final String salesTotalSalesQty;
  final String salesMinRate;
  final String salesMaxRate;
  final String salesNoOfInvoices;
  final String purchaseTotalNetPurchase;
  final String purchaseLastPurchaseDate;
  final String purchaseLastPurchasePrice;
  final String purchaseTotalPurchaseQty;
  final String purchaseMinRate;
  final String purchaseMaxRate;
  final String purchaseNoOfInvoices;
  final String startDateString;
  final String endDateString;
  final String startDateText;
  final String endDateText;
  final String selectedDate;
  final bool isTextEnabled;
  final bool isItemDescVisible;
  final bool isItemAliasVisible;
  final String company;
  final int decimal;
  final String currencySymbol;
  final String currencyCode;
  final String? startFrom;

  const ItemsClickedState({
    this.isLoading = false,
    this.isDateVisible = true,
    this.salesSummaryVisible = false,
    this.purchaseSummaryVisible = false,
    this.isSalesClickableCard = false,
    this.isPurchaseClickableCard = false,
    this.isVisibleSalesList = false,
    this.isClickedSalesIcon = false,
    this.isVisiblePurchaseList = false,
    this.isClickedPurchaseIcon = false,
    this.listSale = const [],
    this.listPurchase = const [],
    this.salesTotalNetSales = '0',
    this.salesLastSaleDate = 'Not Available',
    this.salesLastSalePrice = 'Not Available',
    this.salesTotalSalesQty = 'Not Available',
    this.salesMinRate = 'Not Available',
    this.salesMaxRate = 'Not Available',
    this.salesNoOfInvoices = 'Not Available',
    this.purchaseTotalNetPurchase = 'Not Available',
    this.purchaseLastPurchaseDate = 'Not Available',
    this.purchaseLastPurchasePrice = 'Not Available',
    this.purchaseTotalPurchaseQty = 'Not Available',
    this.purchaseMinRate = 'Not Available',
    this.purchaseMaxRate = 'Not Available',
    this.purchaseNoOfInvoices = 'Not Available',
    this.startDateString = '',
    this.endDateString = '',
    this.startDateText = '',
    this.endDateText = '',
    this.selectedDate = 'Today',
    this.isTextEnabled = true,
    this.isItemDescVisible = false,
    this.isItemAliasVisible = false,
    this.company = '',
    this.decimal = 2,
    this.currencySymbol = '',
    this.currencyCode = 'AED',
    this.startFrom,
  });

  ItemsClickedState copyWith({
    bool? isLoading,
    bool? isDateVisible,
    bool? salesSummaryVisible,
    bool? purchaseSummaryVisible,
    bool? isSalesClickableCard,
    bool? isPurchaseClickableCard,
    bool? isVisibleSalesList,
    bool? isClickedSalesIcon,
    bool? isVisiblePurchaseList,
    bool? isClickedPurchaseIcon,
    List<Sale_Purc>? listSale,
    List<Sale_Purc>? listPurchase,
    String? salesTotalNetSales,
    String? salesLastSaleDate,
    String? salesLastSalePrice,
    String? salesTotalSalesQty,
    String? salesMinRate,
    String? salesMaxRate,
    String? salesNoOfInvoices,
    String? purchaseTotalNetPurchase,
    String? purchaseLastPurchaseDate,
    String? purchaseLastPurchasePrice,
    String? purchaseTotalPurchaseQty,
    String? purchaseMinRate,
    String? purchaseMaxRate,
    String? purchaseNoOfInvoices,
    String? startDateString,
    String? endDateString,
    String? startDateText,
    String? endDateText,
    String? selectedDate,
    bool? isTextEnabled,
    bool? isItemDescVisible,
    bool? isItemAliasVisible,
    String? company,
    int? decimal,
    String? currencySymbol,
    String? currencyCode,
    String? startFrom,
  }) {
    return ItemsClickedState(
      isLoading: isLoading ?? this.isLoading,
      isDateVisible: isDateVisible ?? this.isDateVisible,
      salesSummaryVisible: salesSummaryVisible ?? this.salesSummaryVisible,
      purchaseSummaryVisible:
          purchaseSummaryVisible ?? this.purchaseSummaryVisible,
      isSalesClickableCard: isSalesClickableCard ?? this.isSalesClickableCard,
      isPurchaseClickableCard:
          isPurchaseClickableCard ?? this.isPurchaseClickableCard,
      isVisibleSalesList: isVisibleSalesList ?? this.isVisibleSalesList,
      isClickedSalesIcon: isClickedSalesIcon ?? this.isClickedSalesIcon,
      isVisiblePurchaseList:
          isVisiblePurchaseList ?? this.isVisiblePurchaseList,
      isClickedPurchaseIcon:
          isClickedPurchaseIcon ?? this.isClickedPurchaseIcon,
      listSale: listSale ?? this.listSale,
      listPurchase: listPurchase ?? this.listPurchase,
      salesTotalNetSales: salesTotalNetSales ?? this.salesTotalNetSales,
      salesLastSaleDate: salesLastSaleDate ?? this.salesLastSaleDate,
      salesLastSalePrice: salesLastSalePrice ?? this.salesLastSalePrice,
      salesTotalSalesQty: salesTotalSalesQty ?? this.salesTotalSalesQty,
      salesMinRate: salesMinRate ?? this.salesMinRate,
      salesMaxRate: salesMaxRate ?? this.salesMaxRate,
      salesNoOfInvoices: salesNoOfInvoices ?? this.salesNoOfInvoices,
      purchaseTotalNetPurchase:
          purchaseTotalNetPurchase ?? this.purchaseTotalNetPurchase,
      purchaseLastPurchaseDate:
          purchaseLastPurchaseDate ?? this.purchaseLastPurchaseDate,
      purchaseLastPurchasePrice:
          purchaseLastPurchasePrice ?? this.purchaseLastPurchasePrice,
      purchaseTotalPurchaseQty:
          purchaseTotalPurchaseQty ?? this.purchaseTotalPurchaseQty,
      purchaseMinRate: purchaseMinRate ?? this.purchaseMinRate,
      purchaseMaxRate: purchaseMaxRate ?? this.purchaseMaxRate,
      purchaseNoOfInvoices: purchaseNoOfInvoices ?? this.purchaseNoOfInvoices,
      startDateString: startDateString ?? this.startDateString,
      endDateString: endDateString ?? this.endDateString,
      startDateText: startDateText ?? this.startDateText,
      endDateText: endDateText ?? this.endDateText,
      selectedDate: selectedDate ?? this.selectedDate,
      isTextEnabled: isTextEnabled ?? this.isTextEnabled,
      isItemDescVisible: isItemDescVisible ?? this.isItemDescVisible,
      isItemAliasVisible: isItemAliasVisible ?? this.isItemAliasVisible,
      company: company ?? this.company,
      decimal: decimal ?? this.decimal,
      currencySymbol: currencySymbol ?? this.currencySymbol,
      currencyCode: currencyCode ?? this.currencyCode,
      startFrom: startFrom ?? this.startFrom,
    );
  }
}

class ItemsClickedNotifier extends StateNotifier<ItemsClickedState> {
  final Ref _ref;
  final ItemsClickedArgs args;

  ItemsClickedNotifier(this._ref, this.args)
      : super(const ItemsClickedState()) {
    _init();
  }

  String formatRate(String value, {int decimals = 2}) {
    try {
      final numberOnly = value.split('/').first.trim();
      final parsed = double.parse(numberOnly);
      return parsed.toStringAsFixed(decimals);
    } catch (e) {
      return value;
    }
  }

  String formatBackendValue(String value, {int decimals = 2}) {
    try {
      final parts = value.split('/');
      final numberPart = parts.first.trim();
      final unitPart = parts.length > 1 ? parts.last.trim() : '';
      final parsed = double.parse(numberPart);
      final formattedNumber = parsed.toStringAsFixed(decimals);
      return '$formattedNumber/$unitPart';
    } catch (e) {
      return value;
    }
  }

  String convertDateFormat(String dateStr) {
    final date = DateTime.parse(dateStr);
    return DateFormat('dd-MMM-yyyy').format(date);
  }

  String formatTotal(dynamic amount, {int decimals = 2}) {
    try {
      final parsed = double.parse(amount.toString());
      final absValue = parsed.abs();
      final formatter = NumberFormat.currency(
        locale: 'en',
        symbol: '',
        decimalDigits: decimals,
      );
      final formatted = formatter.format(absValue).trim();
      return parsed < 0 ? '$formatted DR' : '$formatted CR';
    } catch (e) {
      return amount.toString();
    }
  }

  Future<void> _init() async {
    final prefs = await SharedPreferences.getInstance();
    final company = prefs.getString('company_name') ?? '';
    final decimal = prefs.getInt('decimalplace') ?? 2;
    final currencyCode = prefs.getString('currencycode') ?? 'AED';
    String currencySymbol;
    try {
      final format = NumberFormat.simpleCurrency(
        locale: 'en',
        name: currencyCode,
      );
      currencySymbol = format.currencySymbol;
    } catch (e) {
      currencySymbol = NumberFormat.currency(locale: 'en', name: currencyCode)
          .currencySymbol;
    }

    final itemSales = prefs.getString('item_sales') ?? 'False';
    final itemPurchase = prefs.getString('item_purchase') ?? 'False';
    final startFrom = prefs.getString('startfrom');

    final isItemDescVisible = args.itemDesc != 'null' && args.itemDesc.isNotEmpty;
    final isItemAliasVisible = args.alias != 'null' && args.alias.isNotEmpty;

    state = state.copyWith(
      company: company,
      decimal: decimal,
      currencyCode: currencyCode,
      currencySymbol: currencySymbol,
      salesSummaryVisible: itemSales == 'True',
      purchaseSummaryVisible: itemPurchase == 'True',
      startFrom: startFrom,
      isItemDescVisible: isItemDescVisible,
      isItemAliasVisible: isItemAliasVisible,
    );

    await handleDate(state.selectedDate);
  }

  /// Fetches sales/purchase summary data via the tally-api backend.
  /// `lastsaledate`/`lastsaleprice` (and their purchase equivalents) are
  /// deliberately left untouched here, sourced instead from the widget's
  /// constructor params (already fetched by Items.dart) rather than the
  /// summary response.
  Future<void> fetchMainData(String startDateStr, String endDateStr) async {
    final stockItemMasterId = args.stockItemMasterId;
    if (stockItemMasterId == null ||
        !(state.salesSummaryVisible || state.purchaseSummaryVisible)) {
      state = state.copyWith(isDateVisible: false);
      return;
    }

    state = state.copyWith(
      isDateVisible: true,
      isLoading: true,
      isPurchaseClickableCard: false,
      isSalesClickableCard: false,
      isVisibleSalesList: false,
      isClickedSalesIcon: false,
      isVisiblePurchaseList: false,
      isClickedPurchaseIcon: false,
      listSale: const [],
      listPurchase: const [],
      salesNoOfInvoices: 'Not Available',
      salesTotalNetSales: '0',
      salesTotalSalesQty: 'Not Available',
      salesMinRate: 'Not Available',
      salesMaxRate: 'Not Available',
      purchaseNoOfInvoices: 'Not Available',
      purchaseTotalNetPurchase: '0',
      purchaseTotalPurchaseQty: 'Not Available',
      purchaseMinRate: 'Not Available',
      purchaseMaxRate: 'Not Available',
    );

    final decimal = state.decimal;
    final listSale = <Sale_Purc>[];
    final listPurchase = <Sale_Purc>[];
    var isSalesClickableCard = false;
    var isPurchaseClickableCard = false;
    var salesNoOfInvoices = 'Not Available';
    var salesTotalNetSales = '0';
    var salesLastSaleDate = state.salesLastSaleDate;
    var salesLastSalePrice = state.salesLastSalePrice;
    var salesTotalSalesQty = 'Not Available';
    var salesMinRate = 'Not Available';
    var salesMaxRate = 'Not Available';
    var purchaseNoOfInvoices = 'Not Available';
    var purchaseTotalNetPurchase = '0';
    var purchaseLastPurchaseDate = state.purchaseLastPurchaseDate;
    var purchaseLastPurchasePrice = state.purchaseLastPurchasePrice;
    var purchaseTotalPurchaseQty = 'Not Available';
    var purchaseMinRate = 'Not Available';
    var purchaseMaxRate = 'Not Available';

    try {
      final from = parseCompactDate(startDateStr);
      final to = parseCompactDate(endDateStr);
      final repo = _ref.read(stockRepositoryProvider);

      final rows = await repo.stockItemSummary(
        stockItemMasterId,
        from: from,
        to: to,
      );

      Future<void> bucketMonths(
        List<Sale_Purc> target,
        int voucherTypeMasterId,
      ) async {
        final movement = await repo.stockItemMovement(
          stockItemMasterId,
          from: from,
          to: to,
          voucherTypeMasterId: voucherTypeMasterId,
        );
        final buckets = bucketByMonth(
          movement,
          dateOf: (r) => DateTime.parse(r['date'] as String),
          amountOf: (r) => parseMoneyField(r['amount']).abs(),
        );
        target.addAll([
          for (final b in buckets)
            Sale_Purc(month: b.label, amount: b.total.toString()),
        ]);
      }

      for (final row in rows) {
        final vchtype = (row['voucherTypeName'] as String? ?? '');
        final voucherTypeMasterId = row['voucherTypeMasterId'] as int?;

        if (vchtype == 'Sales') {
          isSalesClickableCard = true;
          salesNoOfInvoices = (row['invoiceCount'] ?? 0).toString();
          salesTotalNetSales = formatTotal(row['totalAmount'], decimals: decimal);
          salesLastSaleDate = convertDateFormat(args.itemLastSaleDate);
          salesLastSalePrice = formatBackendValue(args.itemRate, decimals: decimal);
          salesTotalSalesQty = (row['totalQuantity'] ?? '0').toString();
          salesMinRate = formatRate((row['minRate'] ?? '0').toString(), decimals: decimal);
          salesMaxRate = formatRate((row['maxRate'] ?? '0').toString(), decimals: decimal);
          if (voucherTypeMasterId != null) {
            await bucketMonths(listSale, voucherTypeMasterId);
          }
        } else if (vchtype == 'Purchase') {
          isPurchaseClickableCard = true;
          purchaseNoOfInvoices = (row['invoiceCount'] ?? 0).toString();
          purchaseTotalNetPurchase =
              formatTotal(row['totalAmount'], decimals: decimal);
          purchaseLastPurchaseDate = convertDateFormat(args.itemLastPurchDate);
          purchaseLastPurchasePrice =
              formatBackendValue(args.lastPurcRate, decimals: decimal);
          purchaseTotalPurchaseQty = (row['totalQuantity'] ?? '0').toString();
          purchaseMinRate = formatRate((row['minRate'] ?? '0').toString(), decimals: decimal);
          purchaseMaxRate = formatRate((row['maxRate'] ?? '0').toString(), decimals: decimal);
          if (voucherTypeMasterId != null) {
            await bucketMonths(listPurchase, voucherTypeMasterId);
          }
        }
      }

      state = state.copyWith(
        isLoading: false,
        listSale: listSale,
        listPurchase: listPurchase,
        isSalesClickableCard: isSalesClickableCard,
        isPurchaseClickableCard: isPurchaseClickableCard,
        salesNoOfInvoices: salesNoOfInvoices,
        salesTotalNetSales: salesTotalNetSales,
        salesLastSaleDate: salesLastSaleDate,
        salesLastSalePrice: salesLastSalePrice,
        salesTotalSalesQty: salesTotalSalesQty,
        salesMinRate: salesMinRate,
        salesMaxRate: salesMaxRate,
        purchaseNoOfInvoices: purchaseNoOfInvoices,
        purchaseTotalNetPurchase: purchaseTotalNetPurchase,
        purchaseLastPurchaseDate: purchaseLastPurchaseDate,
        purchaseLastPurchasePrice: purchaseLastPurchasePrice,
        purchaseTotalPurchaseQty: purchaseTotalPurchaseQty,
        purchaseMinRate: purchaseMinRate,
        purchaseMaxRate: purchaseMaxRate,
      );
    } catch (e) {
      state = state.copyWith(isLoading: false);
      debugPrint('ItemsClicked tally-api summary fetch failed: $e');
    }
  }

  void toggleSalesExpanded() {
    state = state.copyWith(
      isClickedSalesIcon: !state.isClickedSalesIcon,
      isVisibleSalesList: !state.isVisibleSalesList,
    );
  }

  void togglePurchaseExpanded() {
    state = state.copyWith(
      isClickedPurchaseIcon: !state.isClickedPurchaseIcon,
      isVisiblePurchaseList: !state.isVisiblePurchaseList,
    );
  }

  void setCustomDateRange(DateTime start, DateTime end) {
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
    final startDateText = '$startDay-$startMonth-$startYear';
    final endDateText = '$endDay-$endMonth-$endYear';

    state = state.copyWith(
      startDateString: startDateString,
      endDateString: endDateString,
      startDateText: startDateText,
      endDateText: endDateText,
    );
    fetchMainData(startDateString, endDateString);
  }

  Future<void> handleDate(String value) async {
    state = state.copyWith(selectedDate: value);

    DateTime start;
    DateTime end;
    var isTextEnabled = false;

    switch (value) {
      case 'Today':
        start = DateTime.now();
        end = start;
        break;
      case 'Yesterday':
        start = DateTime.now().subtract(const Duration(days: 1));
        end = start;
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
        final now = DateTime.now();
        start = DateTime(now.year, 1, 1);
        end = DateTime(now.year, 12, 31);
        break;
      case 'Last Year':
        final now = DateTime.now();
        start = DateTime(now.year - 1, 1, 1);
        end = DateTime(now.year - 1, 12, 31);
        break;
      case 'Year To Date':
        final now = DateTime.now();
        start = DateTime(now.year, 1, 1);
        end = DateTime(now.year, now.month, now.day);
        break;
      case 'Custom Date':
      default:
        state = state.copyWith(isTextEnabled: true);
        return;
    }

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
    final startDateText = '$startDay-$startMonth-$startYear';
    final endDateText = '$endDay-$endMonth-$endYear';

    state = state.copyWith(
      startDateString: startDateString,
      endDateString: endDateString,
      startDateText: startDateText,
      endDateText: endDateText,
      isTextEnabled: isTextEnabled,
    );

    await fetchMainData(startDateString, endDateString);
  }
}

final itemsClickedNotifierProvider = StateNotifierProvider.autoDispose
    .family<ItemsClickedNotifier, ItemsClickedState, ItemsClickedArgs>(
  (ref, args) => ItemsClickedNotifier(ref, args),
);
