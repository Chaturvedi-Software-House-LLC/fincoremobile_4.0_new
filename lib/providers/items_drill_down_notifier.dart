import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../ItemsDrillDown.dart';
import '../api/stock_repository.dart';
import '../api/monthly_bucket_helper.dart' show parseMoneyField, parseCompactDate;

/// Riverpod migration of `ItemsDrillDown.dart`'s `_ItemsDrillDownState`.
/// Closest sibling: `party_drill_down_notifier.dart` - same shape (four
/// parallel group lists, sort/search/PDF/CSV, recursive self-navigation),
/// item-scoped instead of ledger-scoped: 'Ledger' replaces 'Items' as the
/// counterparty-grouping dimension.
class ItemsDrillDownArgs {
  final String startDateString;
  final String endDateString;
  final String type;
  final String itemName;
  final int? stockItemMasterId;
  final String? lockedLedger;
  final String? lockedCostcenter;
  final String? lockedVchname;

  const ItemsDrillDownArgs({
    required this.startDateString,
    required this.endDateString,
    required this.type,
    required this.itemName,
    this.stockItemMasterId,
    this.lockedLedger,
    this.lockedCostcenter,
    this.lockedVchname,
  });

  @override
  bool operator ==(Object other) =>
      other is ItemsDrillDownArgs &&
      other.startDateString == startDateString &&
      other.endDateString == endDateString &&
      other.type == type &&
      other.itemName == itemName &&
      other.stockItemMasterId == stockItemMasterId &&
      other.lockedLedger == lockedLedger &&
      other.lockedCostcenter == lockedCostcenter &&
      other.lockedVchname == lockedVchname;

  @override
  int get hashCode => Object.hash(
        startDateString,
        endDateString,
        type,
        itemName,
        stockItemMasterId,
        lockedLedger,
        lockedCostcenter,
        lockedVchname,
      );

  List<String> get availableGroups {
    final all = <String>['Ledger', 'Bills', 'Voucher Type', 'Cost Center'];
    if (lockedLedger != null) all.remove('Ledger');
    if (lockedVchname != null) all.remove('Voucher Type');
    if (lockedCostcenter != null) all.remove('Cost Center');
    return all;
  }
}

class ItemsDrillDownState {
  final bool isLoading;
  final bool isSortVisible;
  final bool showDateSort;
  final bool isVisibleNoDataFound;
  final bool isSearchViewVisible;
  final String selectedGroup;
  final String selectedSortOption;
  final String company;
  final List<DrillLedger> ledgerList;
  final List<DrillLedger> filteredLedger;
  final List<DrillBill> billsList;
  final List<DrillBill> filteredBills;
  final List<DrillVchType> vchtypeList;
  final List<DrillVchType> filteredVchtype;
  final List<DrillCostCenter> costcenterList;
  final List<DrillCostCenter> filteredCostcenter;

  const ItemsDrillDownState({
    this.isLoading = false,
    this.isSortVisible = false,
    this.showDateSort = false,
    this.isVisibleNoDataFound = false,
    this.isSearchViewVisible = false,
    this.selectedGroup = '',
    this.selectedSortOption = 'Default',
    this.company = '',
    this.ledgerList = const [],
    this.filteredLedger = const [],
    this.billsList = const [],
    this.filteredBills = const [],
    this.vchtypeList = const [],
    this.filteredVchtype = const [],
    this.costcenterList = const [],
    this.filteredCostcenter = const [],
  });

  ItemsDrillDownState copyWith({
    bool? isLoading,
    bool? isSortVisible,
    bool? showDateSort,
    bool? isVisibleNoDataFound,
    bool? isSearchViewVisible,
    String? selectedGroup,
    String? selectedSortOption,
    String? company,
    List<DrillLedger>? ledgerList,
    List<DrillLedger>? filteredLedger,
    List<DrillBill>? billsList,
    List<DrillBill>? filteredBills,
    List<DrillVchType>? vchtypeList,
    List<DrillVchType>? filteredVchtype,
    List<DrillCostCenter>? costcenterList,
    List<DrillCostCenter>? filteredCostcenter,
  }) {
    return ItemsDrillDownState(
      isLoading: isLoading ?? this.isLoading,
      isSortVisible: isSortVisible ?? this.isSortVisible,
      showDateSort: showDateSort ?? this.showDateSort,
      isVisibleNoDataFound: isVisibleNoDataFound ?? this.isVisibleNoDataFound,
      isSearchViewVisible: isSearchViewVisible ?? this.isSearchViewVisible,
      selectedGroup: selectedGroup ?? this.selectedGroup,
      selectedSortOption: selectedSortOption ?? this.selectedSortOption,
      company: company ?? this.company,
      ledgerList: ledgerList ?? this.ledgerList,
      filteredLedger: filteredLedger ?? this.filteredLedger,
      billsList: billsList ?? this.billsList,
      filteredBills: filteredBills ?? this.filteredBills,
      vchtypeList: vchtypeList ?? this.vchtypeList,
      filteredVchtype: filteredVchtype ?? this.filteredVchtype,
      costcenterList: costcenterList ?? this.costcenterList,
      filteredCostcenter: filteredCostcenter ?? this.filteredCostcenter,
    );
  }
}

class ItemsDrillDownNotifier extends StateNotifier<ItemsDrillDownState> {
  final ItemsDrillDownArgs args;

  ItemsDrillDownNotifier(this.args)
      : super(ItemsDrillDownState(selectedGroup: args.availableGroups.first)) {
    _init();
  }

  void toggleSearchView() {
    final next = !state.isSearchViewVisible;
    state = state.copyWith(isSearchViewVisible: next);
    if (!next) filter('');
  }

  Future<void> _init() async {
    final prefs = await SharedPreferences.getInstance();
    final company = prefs.getString('company_name') ?? '';
    var selectedSortOption = prefs.getString('sort') ?? 'Default';
    if (selectedSortOption == 'null') selectedSortOption = 'Default';

    state = state.copyWith(company: company, selectedSortOption: selectedSortOption);
    await selectGroup(state.selectedGroup);
  }

  Future<void> selectGroup(String group) async {
    state = state.copyWith(
      isLoading: true,
      selectedGroup: group,
      showDateSort: group == 'Bills',
      selectedSortOption:
          group != 'Bills' &&
                  (state.selectedSortOption == 'Newest to Oldest' ||
                      state.selectedSortOption == 'Oldest to Newest')
              ? 'Default'
              : state.selectedSortOption,
      ledgerList: const [],
      filteredLedger: const [],
      billsList: const [],
      filteredBills: const [],
      vchtypeList: const [],
      filteredVchtype: const [],
      costcenterList: const [],
      filteredCostcenter: const [],
    );

    try {
      // No legacy fallback: tally-oauth-only sessions always carry a
      // stockItemMasterId, so a null one here means a legacy-paired session
      // with no tally-api master id - same "not available" empty-state
      // convention used elsewhere in this migration (see ItemsClicked.dart).
      final List<dynamic> raw = args.stockItemMasterId != null
          ? await _fetchGroupTallyApi(group)
          : const [];

      var ledgerList = state.ledgerList;
      var billsList = state.billsList;
      var vchtypeList = state.vchtypeList;
      var costcenterList = state.costcenterList;

      if (raw.isNotEmpty) {
        switch (group) {
          case 'Ledger':
            ledgerList = raw.map((j) => DrillLedger.fromJson(j)).toList();
            break;
          case 'Bills':
            billsList = raw.map((j) => DrillBill.fromJson(j)).toList();
            break;
          case 'Voucher Type':
            vchtypeList = raw.map((j) => DrillVchType.fromJson(j)).toList();
            break;
          case 'Cost Center':
            costcenterList =
                raw.map((j) => DrillCostCenter.fromJson(j)).toList();
            break;
        }
      }

      final empty =
          ledgerList.isEmpty &&
          billsList.isEmpty &&
          vchtypeList.isEmpty &&
          costcenterList.isEmpty;

      state = state.copyWith(
        isLoading: false,
        ledgerList: ledgerList,
        billsList: billsList,
        vchtypeList: vchtypeList,
        costcenterList: costcenterList,
        isVisibleNoDataFound: empty,
        isSortVisible: !empty,
      );
      _applySortOption(state.selectedSortOption);
    } catch (e) {
      state = state.copyWith(isLoading: false);
    }
  }

  /// tally-api path - `reports/stock-items/item-report` (see
  /// `StockRepository.itemReportDetail`'s doc comment). Unlike the old
  /// `fetchDrilldownVouchers`-based approach, this fetches only rows for
  /// this one item (`stockItemMasterId`-scoped server-side) instead of
  /// every voucher in the company - `lockedLedger`/`lockedCostcenter` still
  /// have to be applied by name client-side since only names (not
  /// masterIds) are threaded through this screen's recursive navigation.
  ///
  /// Rows are per inventory-line, so a voucher with two lines of this same
  /// item comes back as two rows - grouped back to one per-voucher entry
  /// first (summing this item's own qty/amount), matching the old
  /// per-voucher grouping semantics for Ledger/Bills/Voucher Type. Cost
  /// Center stays per-line, since a line's own cost-centre split is scoped
  /// to that line specifically.
  Future<List<Map<String, dynamic>>> _fetchGroupTallyApi(String group) async {
    final from = parseCompactDate(args.startDateString);
    final to = parseCompactDate(args.endDateString);
    final rows = await StockRepository.instance.itemReportDetail(
      stockItemMasterId: args.stockItemMasterId!,
      from: from,
      to: to,
    );

    final voucherTypeName = args.lockedVchname ?? args.type;
    final filteredRows = rows.where((row) {
      if (row['voucherTypeName'] != voucherTypeName) return false;
      if (args.lockedLedger != null) {
        final ledgerEntries =
            (row['ledgerEntries'] as List?)?.cast<Map<String, dynamic>>() ??
            const [];
        if (!ledgerEntries.any((e) => e['ledgerName'] == args.lockedLedger)) {
          return false;
        }
      }
      if (args.lockedCostcenter != null) {
        final costCentreEntries =
            (row['costCentreAllocations'] as List?)
                ?.cast<Map<String, dynamic>>() ??
            const [];
        if (args.lockedCostcenter == 'null') {
          if (costCentreEntries.isNotEmpty) return false;
        } else if (!costCentreEntries.any(
          (e) => e['costCentreName'] == args.lockedCostcenter,
        )) {
          return false;
        }
      }
      return true;
    }).toList();

    // Group rows back to one entry per voucher (summing this item's own
    // qty/amount across that voucher's lines) for the groupings that
    // operate at voucher granularity.
    final byVoucher = <int, Map<String, dynamic>>{};
    for (final row in filteredRows) {
      final voucherMasterId = row['voucherMasterId'] as int;
      final qty = parseMoneyField(row['quantity']);
      final amount = parseMoneyField(row['amount']);
      final existing = byVoucher[voucherMasterId];
      if (existing == null) {
        byVoucher[voucherMasterId] = {
          'voucherNumber': row['voucherNumber'] ?? '',
          'date': row['date'] ?? '',
          'voucherTypeName': row['voucherTypeName'] ?? '',
          'ledgerEntries': row['ledgerEntries'],
          'qty': qty,
          'amount': amount,
        };
      } else {
        existing['qty'] = (existing['qty'] as double) + qty;
        existing['amount'] = (existing['amount'] as double) + amount;
      }
    }
    final vouchers = byVoucher.values.toList();

    switch (group) {
      case 'Ledger':
        final totals = <String, Map<String, double>>{};
        for (final voucher in vouchers) {
          final ledgerEntries =
              (voucher['ledgerEntries'] as List?)
                  ?.cast<Map<String, dynamic>>() ??
              const [];
          for (final entry in ledgerEntries) {
            final name = (entry['ledgerName'] ?? '').toString();
            final bucket = totals.putIfAbsent(
              name,
              () => {'qty': 0, 'amount': 0},
            );
            bucket['qty'] = bucket['qty']! + (voucher['qty'] as double);
            bucket['amount'] =
                bucket['amount']! + (voucher['amount'] as double);
          }
        }
        return [
          for (final entry in totals.entries)
            {
              'Partyledger': entry.key,
              'qty': entry.value['qty'],
              'amount': entry.value['amount'],
            },
        ];

      case 'Bills':
        return [
          for (final voucher in vouchers)
            {
              'vchno': voucher['voucherNumber'],
              'Partyledger': args.lockedLedger ?? '',
              'vchdate': voucher['date'],
              'amount': voucher['amount'],
            },
        ];

      case 'Voucher Type':
        final totals = <String, Map<String, num>>{};
        for (final voucher in vouchers) {
          final name = (voucher['voucherTypeName'] ?? '').toString();
          final bucket = totals.putIfAbsent(
            name,
            () => {'count': 0, 'amount': 0.0},
          );
          bucket['count'] = bucket['count']! + 1;
          bucket['amount'] = bucket['amount']! + (voucher['amount'] as double);
        }
        return [
          for (final entry in totals.entries)
            {
              'vchname': entry.key,
              'qty': entry.value['count'].toString(),
              'amount': entry.value['amount'],
            },
        ];

      case 'Cost Center':
        final totals = <String, Map<String, num>>{};
        for (final row in filteredRows) {
          final costCentreEntries =
              (row['costCentreAllocations'] as List?)
                  ?.cast<Map<String, dynamic>>() ??
              const [];
          if (costCentreEntries.isEmpty) {
            final bucket = totals.putIfAbsent(
              'null',
              () => {'count': 0, 'amount': 0.0},
            );
            bucket['count'] = bucket['count']! + 1;
            bucket['amount'] = bucket['amount']! + parseMoneyField(row['amount']);
          } else {
            for (final entry in costCentreEntries) {
              final name = (entry['costCentreName'] ?? 'null').toString();
              final bucket = totals.putIfAbsent(
                name,
                () => {'count': 0, 'amount': 0.0},
              );
              bucket['count'] = bucket['count']! + 1;
              bucket['amount'] =
                  bucket['amount']! + parseMoneyField(entry['amount']);
            }
          }
        }
        return [
          for (final entry in totals.entries)
            {
              'costcentre': entry.key,
              'qty': entry.value['count'].toString(),
              'amount': entry.value['amount'],
            },
        ];

      default:
        return const [];
    }
  }

  void filter(String query) {
    final q = query.toLowerCase();
    if (query.isEmpty) {
      state = state.copyWith(
        filteredLedger: List.from(state.ledgerList),
        filteredBills: List.from(state.billsList),
        filteredVchtype: List.from(state.vchtypeList),
        filteredCostcenter: List.from(state.costcenterList),
      );
    } else {
      state = state.copyWith(
        filteredLedger: state.ledgerList
            .where((e) => e.Partyledger.toLowerCase().contains(q))
            .toList(),
        filteredBills: state.billsList
            .where((e) => e.vchno.toLowerCase().contains(q))
            .toList(),
        filteredVchtype: state.vchtypeList
            .where((e) => e.vchname.toLowerCase().contains(q))
            .toList(),
        filteredCostcenter: state.costcenterList
            .where((e) => e.costcentre.toLowerCase().contains(q))
            .toList(),
      );
    }
  }

  void selectSortOption(String option) {
    state = state.copyWith(selectedSortOption: option);
    _applySortOption(option);
  }

  void _applySortOption(String option) {
    final isSales = args.type == 'Sales';
    var ledger = List<DrillLedger>.from(state.filteredLedger);
    var bills = List<DrillBill>.from(state.filteredBills);
    var vchtype = List<DrillVchType>.from(state.filteredVchtype);
    var costcenter = List<DrillCostCenter>.from(state.filteredCostcenter);

    switch (option) {
      case 'Default':
        ledger = List.from(state.ledgerList);
        bills = List.from(state.billsList);
        vchtype = List.from(state.vchtypeList);
        costcenter = List.from(state.costcenterList);
        break;
      case 'A->Z':
        ledger.sort((a, b) => a.Partyledger.compareTo(b.Partyledger));
        bills.sort((a, b) => a.Partyledger.compareTo(b.Partyledger));
        vchtype.sort((a, b) => a.vchname.compareTo(b.vchname));
        costcenter.sort((a, b) => a.costcentre.compareTo(b.costcentre));
        break;
      case 'Z->A':
        ledger.sort((a, b) => b.Partyledger.compareTo(a.Partyledger));
        bills.sort((a, b) => b.Partyledger.compareTo(a.Partyledger));
        vchtype.sort((a, b) => b.vchname.compareTo(a.vchname));
        costcenter.sort((a, b) => b.costcentre.compareTo(a.costcentre));
        break;
      case 'Oldest to Newest':
        bills.sort((a, b) => a.vchdate.compareTo(b.vchdate));
        break;
      case 'Newest to Oldest':
        bills.sort((a, b) => b.vchdate.compareTo(a.vchdate));
        break;
      case 'Amount Low to High':
        ledger.sort(
          (a, b) => isSales
              ? a.amount.compareTo(b.amount)
              : b.amount.compareTo(a.amount),
        );
        bills.sort(
          (a, b) => isSales
              ? a.amount.compareTo(b.amount)
              : b.amount.compareTo(a.amount),
        );
        vchtype.sort(
          (a, b) => isSales
              ? a.amount.compareTo(b.amount)
              : b.amount.compareTo(a.amount),
        );
        costcenter.sort(
          (a, b) => isSales
              ? a.amount.compareTo(b.amount)
              : b.amount.compareTo(a.amount),
        );
        break;
      case 'Amount High to Low':
        ledger.sort(
          (a, b) => isSales
              ? b.amount.compareTo(a.amount)
              : a.amount.compareTo(b.amount),
        );
        bills.sort(
          (a, b) => isSales
              ? b.amount.compareTo(a.amount)
              : a.amount.compareTo(b.amount),
        );
        vchtype.sort(
          (a, b) => isSales
              ? b.amount.compareTo(a.amount)
              : a.amount.compareTo(b.amount),
        );
        costcenter.sort(
          (a, b) => isSales
              ? b.amount.compareTo(a.amount)
              : a.amount.compareTo(b.amount),
        );
        break;
    }

    state = state.copyWith(
      filteredLedger: ledger,
      filteredBills: bills,
      filteredVchtype: vchtype,
      filteredCostcenter: costcenter,
    );
  }
}

final itemsDrillDownNotifierProvider = StateNotifierProvider.autoDispose
    .family<ItemsDrillDownNotifier, ItemsDrillDownState, ItemsDrillDownArgs>(
  (ref, args) => ItemsDrillDownNotifier(args),
);
