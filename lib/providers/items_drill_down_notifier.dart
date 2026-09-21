import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../ItemsDrillDown.dart';
import '../api/stock_repository.dart';
import '../api/voucher_type_repository.dart';
import '../api/monthly_bucket_helper.dart' show parseCompactDate;

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
  final int? lockedLedgerMasterId;
  final String? lockedCostcenter;
  final int? lockedCostcenterMasterId;
  final String? lockedVchname;
  final int? lockedVchnameMasterId;

  const ItemsDrillDownArgs({
    required this.startDateString,
    required this.endDateString,
    required this.type,
    required this.itemName,
    this.stockItemMasterId,
    this.lockedLedger,
    this.lockedLedgerMasterId,
    this.lockedCostcenter,
    this.lockedCostcenterMasterId,
    this.lockedVchname,
    this.lockedVchnameMasterId,
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
      other.lockedLedgerMasterId == lockedLedgerMasterId &&
      other.lockedCostcenter == lockedCostcenter &&
      other.lockedCostcenterMasterId == lockedCostcenterMasterId &&
      other.lockedVchname == lockedVchname &&
      other.lockedVchnameMasterId == lockedVchnameMasterId;

  @override
  int get hashCode => Object.hash(
        startDateString,
        endDateString,
        type,
        itemName,
        stockItemMasterId,
        lockedLedger,
        lockedLedgerMasterId,
        lockedCostcenter,
        lockedCostcenterMasterId,
        lockedVchname,
        lockedVchnameMasterId,
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
  final bool isLoadingMore;
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
    this.isLoadingMore = false,
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
    bool? isLoadingMore,
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
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
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

  int _page = 1;
  bool _hasMore = true;
  // The `type` (Sales/Purchase) filter this screen is always scoped to -
  // resolved once, lazily, since only a name is threaded down from
  // `ItemsClicked.dart`'s entry point, not a masterId (see this file's
  // `_resolveTypeMasterId` for why threading one through every external
  // caller wasn't necessary).
  int? _typeMasterId;

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
    _typeMasterId = await _resolveTypeMasterId();
    await selectGroup(state.selectedGroup);
  }

  /// `args.type` ('Sales'/'Purchase') only ever arrives as a display name,
  /// never a masterId - the one lookup this notifier does on its own
  /// (rather than requiring every call site up the navigation chain to
  /// resolve and thread one through) so the grouped/paginated views below
  /// can filter server-side by `voucherTypeMasterId` like every other
  /// dimension. `reservedName` is used (not the user-editable `name`) for
  /// the same stability reason `VoucherTypeRepository` documents; the first
  /// active match is used if a company somehow has more than one voucher
  /// type sharing that reservedName.
  Future<int?> _resolveTypeMasterId() async {
    final reservedName = args.type == 'Sales' ? 'SALES' : 'PURCHASE';
    final matches = await VoucherTypeRepository.instance.byReservedName(reservedName);
    return matches.isNotEmpty ? matches.first['masterId'] as int? : null;
  }

  String _viewFor(String group) {
    switch (group) {
      case 'Ledger':
        return 'by-ledger';
      case 'Voucher Type':
        return 'by-voucher-type';
      case 'Cost Center':
        return 'by-cost-centre';
      default:
        return 'normal';
    }
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
    _page = 1;
    _hasMore = true;
    await _fetchPage(group, append: false);
  }

  /// Called by the widget's scroll-near-bottom listener. No-ops when a load
  /// is already in flight or the active group has no more pages - safe to
  /// call repeatedly as the user keeps scrolling.
  Future<void> loadMoreItems() async {
    if (state.isLoadingMore || state.isLoading || !_hasMore) return;
    await _fetchPage(state.selectedGroup, append: true);
  }

  Future<void> _fetchPage(String group, {required bool append}) async {
    if (append) {
      state = state.copyWith(isLoadingMore: true);
    }

    try {
      // No legacy fallback: tally-oauth-only sessions always carry a
      // stockItemMasterId, so a null one here means a legacy-paired session
      // with no tally-api master id - same "not available" empty-state
      // convention used elsewhere in this migration (see ItemsClicked.dart).
      if (args.stockItemMasterId == null) {
        state = state.copyWith(
          isLoading: false,
          isLoadingMore: false,
          isVisibleNoDataFound: true,
          isSortVisible: false,
        );
        return;
      }

      final from = parseCompactDate(args.startDateString);
      final to = parseCompactDate(args.endDateString);
      final nextPage = append ? _page + 1 : 1;
      final result = await StockRepository.instance.itemReportPage(
        view: _viewFor(group),
        page: nextPage,
        limit: 30,
        stockItemMasterId: args.stockItemMasterId,
        ledgerMasterId: args.lockedLedgerMasterId,
        voucherTypeMasterId: args.lockedVchnameMasterId ?? _typeMasterId,
        costCentreMasterId: args.lockedCostcenterMasterId,
        from: from,
        to: to,
      );
      _page = nextPage;
      _hasMore = result.hasMore;

      var ledgerList = state.ledgerList;
      var billsList = state.billsList;
      var vchtypeList = state.vchtypeList;
      var costcenterList = state.costcenterList;

      switch (group) {
        case 'Ledger':
          final page = result.items
              .map(
                (j) => DrillLedger.fromJson({
                  'Partyledger': j['ledgerName'] ?? '',
                  'qty': j['totalQuantity'],
                  'amount': j['totalAmount'],
                  'ledgerMasterId': j['ledgerMasterId'],
                }),
              )
              .toList();
          ledgerList = append ? [...state.ledgerList, ...page] : page;
          break;
        case 'Bills':
          // `normal` view rows are raw item-report detail rows (one per
          // inventory line, not merged per voucher the way the old
          // eager-fetch-then-group approach did - a voucher with two lines
          // of this same item now shows as two Bills rows instead of one
          // combined row, since merging across a page boundary isn't
          // possible under real pagination). `Partyledger` here is just an
          // echo of the locked ledger filter (as before), not server data.
          final page = result.items
              .map(
                (j) => DrillBill.fromJson({
                  'vchno': j['voucherNumber'],
                  'Partyledger': args.lockedLedger ?? '',
                  'vchdate': j['date'],
                  'amount': j['amount'],
                }),
              )
              .toList();
          billsList = append ? [...state.billsList, ...page] : page;
          break;
        case 'Voucher Type':
          // `qty` here is the voucher/invoice count, not a real item
          // quantity - matches the pre-existing "count of vouchers" meaning
          // this field has always had for the Voucher Type/Cost Center
          // groupings (see `DrillVchType`/`DrillCostCenter`'s usage).
          final page = result.items
              .map(
                (j) => DrillVchType.fromJson({
                  'vchname': j['voucherTypeName'] ?? '',
                  'qty': j['invoiceCount'],
                  'amount': j['totalAmount'],
                  'voucherTypeMasterId': j['voucherTypeMasterId'],
                }),
              )
              .toList();
          vchtypeList = append ? [...state.vchtypeList, ...page] : page;
          break;
        case 'Cost Center':
          final page = result.items
              .map(
                (j) => DrillCostCenter.fromJson({
                  'costcentre': j['costCentreName'] ?? 'null',
                  'qty': j['invoiceCount'],
                  'amount': j['totalAmount'],
                  'costCentreMasterId': j['costCentreMasterId'],
                }),
              )
              .toList();
          costcenterList = append ? [...state.costcenterList, ...page] : page;
          break;
      }

      final empty =
          ledgerList.isEmpty &&
          billsList.isEmpty &&
          vchtypeList.isEmpty &&
          costcenterList.isEmpty;

      state = state.copyWith(
        isLoading: false,
        isLoadingMore: false,
        ledgerList: ledgerList,
        billsList: billsList,
        vchtypeList: vchtypeList,
        costcenterList: costcenterList,
        isVisibleNoDataFound: empty,
        isSortVisible: !empty,
      );
      _applySortOption(state.selectedSortOption);
    } catch (e) {
      state = state.copyWith(isLoading: false, isLoadingMore: false);
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

  /// Sorting only ever reorders what's been loaded so far - the server
  /// already returns groups in ascending name order, which is what
  /// `'Default'`/`'A->Z'` want directly; the other options are a
  /// best-effort re-sort of the loaded prefix rather than a true global
  /// sort, since achieving that would mean fetching every page up front
  /// again (exactly what real pagination here was meant to avoid). Matches
  /// this screen's existing "date sort only applies to Bills" convention.
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
