import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../PartyDrillDown.dart';
import '../api/ledger_repository.dart';
import '../api/voucher_type_repository.dart';
import '../api/monthly_bucket_helper.dart'
    show parseCompactDate, parseMoneyField;

/// Riverpod migration of `PartyDrillDown.dart`'s `_PartyDrillDownState`.
/// Closest sibling: `items_drill_down_notifier.dart` - same shape (four
/// parallel group lists, sort/search/PDF/CSV, recursive self-navigation,
/// real incremental scroll-pagination per active group), ledger-scoped
/// instead of item-scoped: 'Items' replaces 'Ledger' as the
/// counterparty-grouping dimension.
class PartyDrillDownArgs {
  final String startDateString;
  final String endDateString;
  final String type;
  final String ledger;
  final int? ledgerMasterId;
  final String? lockedItem;
  final int? lockedItemMasterId;
  final String? lockedCostcenter;
  final int? lockedCostcenterMasterId;
  final String? lockedVchname;
  final int? lockedVchnameMasterId;

  const PartyDrillDownArgs({
    required this.startDateString,
    required this.endDateString,
    required this.type,
    required this.ledger,
    this.ledgerMasterId,
    this.lockedItem,
    this.lockedItemMasterId,
    this.lockedCostcenter,
    this.lockedCostcenterMasterId,
    this.lockedVchname,
    this.lockedVchnameMasterId,
  });

  @override
  bool operator ==(Object other) =>
      other is PartyDrillDownArgs &&
      other.startDateString == startDateString &&
      other.endDateString == endDateString &&
      other.type == type &&
      other.ledger == ledger &&
      other.ledgerMasterId == ledgerMasterId &&
      other.lockedItem == lockedItem &&
      other.lockedItemMasterId == lockedItemMasterId &&
      other.lockedCostcenter == lockedCostcenter &&
      other.lockedCostcenterMasterId == lockedCostcenterMasterId &&
      other.lockedVchname == lockedVchname &&
      other.lockedVchnameMasterId == lockedVchnameMasterId;

  @override
  int get hashCode => Object.hash(
        startDateString,
        endDateString,
        type,
        ledger,
        ledgerMasterId,
        lockedItem,
        lockedItemMasterId,
        lockedCostcenter,
        lockedCostcenterMasterId,
        lockedVchname,
        lockedVchnameMasterId,
      );

  List<String> get availableGroups {
    final all = <String>['Items', 'Bills', 'Voucher Type', 'Cost Center'];
    if (lockedItem != null) all.remove('Items');
    if (lockedVchname != null) all.remove('Voucher Type');
    if (lockedCostcenter != null) all.remove('Cost Center');
    return all;
  }
}

class PartyDrillDownState {
  final bool isLoading;
  final bool isLoadingMore;
  final bool isSortVisible;
  final bool showDateSort;
  final bool isVisibleNoDataFound;
  final bool isSearchViewVisible;
  final String selectedGroup;
  final String selectedSortOption;
  final String company;
  final List<PItem> itemList;
  final List<PItem> filteredItems;
  final List<PBill> billsList;
  final List<PBill> filteredBills;
  final List<PVchType> vchtypeList;
  final List<PVchType> filteredVchtype;
  final List<PCostCenter> costcenterList;
  final List<PCostCenter> filteredCostcenter;

  const PartyDrillDownState({
    this.isLoading = false,
    this.isLoadingMore = false,
    this.isSortVisible = false,
    this.showDateSort = false,
    this.isVisibleNoDataFound = false,
    this.isSearchViewVisible = false,
    this.selectedGroup = '',
    this.selectedSortOption = 'Default',
    this.company = '',
    this.itemList = const [],
    this.filteredItems = const [],
    this.billsList = const [],
    this.filteredBills = const [],
    this.vchtypeList = const [],
    this.filteredVchtype = const [],
    this.costcenterList = const [],
    this.filteredCostcenter = const [],
  });

  PartyDrillDownState copyWith({
    bool? isLoading,
    bool? isLoadingMore,
    bool? isSortVisible,
    bool? showDateSort,
    bool? isVisibleNoDataFound,
    bool? isSearchViewVisible,
    String? selectedGroup,
    String? selectedSortOption,
    String? company,
    List<PItem>? itemList,
    List<PItem>? filteredItems,
    List<PBill>? billsList,
    List<PBill>? filteredBills,
    List<PVchType>? vchtypeList,
    List<PVchType>? filteredVchtype,
    List<PCostCenter>? costcenterList,
    List<PCostCenter>? filteredCostcenter,
  }) {
    return PartyDrillDownState(
      isLoading: isLoading ?? this.isLoading,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
      isSortVisible: isSortVisible ?? this.isSortVisible,
      showDateSort: showDateSort ?? this.showDateSort,
      isVisibleNoDataFound: isVisibleNoDataFound ?? this.isVisibleNoDataFound,
      isSearchViewVisible: isSearchViewVisible ?? this.isSearchViewVisible,
      selectedGroup: selectedGroup ?? this.selectedGroup,
      selectedSortOption: selectedSortOption ?? this.selectedSortOption,
      company: company ?? this.company,
      itemList: itemList ?? this.itemList,
      filteredItems: filteredItems ?? this.filteredItems,
      billsList: billsList ?? this.billsList,
      filteredBills: filteredBills ?? this.filteredBills,
      vchtypeList: vchtypeList ?? this.vchtypeList,
      filteredVchtype: filteredVchtype ?? this.filteredVchtype,
      costcenterList: costcenterList ?? this.costcenterList,
      filteredCostcenter: filteredCostcenter ?? this.filteredCostcenter,
    );
  }
}

class PartyDrillDownNotifier extends StateNotifier<PartyDrillDownState> {
  final PartyDrillDownArgs args;

  int _page = 1;
  bool _hasMore = true;
  // The `type` (Sales/Purchase) filter this screen is always scoped to -
  // resolved once, lazily, since only a name is threaded down from this
  // screen's entry point, not a masterId - see
  // `items_drill_down_notifier.dart`'s identical `_resolveTypeMasterId` for
  // why threading one through every external caller wasn't necessary.
  int? _typeMasterId;

  PartyDrillDownNotifier(this.args)
      : super(
          PartyDrillDownState(selectedGroup: args.availableGroups.first),
        ) {
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

  // `args.type` reaches this screen as one of PartyClicked.dart's own
  // display names (Sales/Purchase/Credit Note/Debit Note, from both
  // navigateToDetail and the Monthly Breakdown's month-tap) - a plain
  // Sales/else-Purchase ternary silently resolved every non-Sales type
  // (including Credit Note/Debit Note) to the Purchase voucher type,
  // showing that party's Purchase vouchers - or nothing - instead of the
  // type actually tapped.
  static const _reservedNameByType = {
    'Sales': 'SALES',
    'Purchase': 'PURCHASE',
    'Credit Note': 'CREDIT_NOTE',
    'Debit Note': 'DEBIT_NOTE',
    'Journal': 'JOURNAL',
    'Receipt': 'RECEIPT',
    'Payment': 'PAYMENT',
  };

  Future<int?> _resolveTypeMasterId() async {
    final reservedName = _reservedNameByType[args.type];
    if (reservedName == null) return null;
    final matches = await VoucherTypeRepository.instance.byReservedName(reservedName);
    return matches.isNotEmpty ? matches.first['masterId'] as int? : null;
  }

  String _viewFor(String group) {
    switch (group) {
      case 'Items':
        return 'by-item';
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
      itemList: const [],
      filteredItems: const [],
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
  /// is already in flight or the active group has no more pages.
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
      // ledgerMasterId, so a null one here means a legacy-paired session
      // with no tally-api master id - same "not available" empty-state
      // convention used elsewhere in this migration (see PartyClicked.dart).
      if (args.ledgerMasterId == null) {
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
      final result = await LedgerRepository.instance.ledgerReportPage(
        view: _viewFor(group),
        page: nextPage,
        limit: 30,
        ledgerMasterId: args.ledgerMasterId,
        stockItemMasterId: args.lockedItemMasterId,
        voucherTypeMasterId: args.lockedVchnameMasterId ?? _typeMasterId,
        costCentreMasterId: args.lockedCostcenterMasterId,
        from: from,
        to: to,
      );
      _page = nextPage;
      _hasMore = result.hasMore;

      var itemList = state.itemList;
      var billsList = state.billsList;
      var vchtypeList = state.vchtypeList;
      var costcenterList = state.costcenterList;

      switch (group) {
        case 'Items':
          final page = result.items
              .map(
                (j) => PItem.fromJson({
                  'item': j['stockItemName'] ?? '',
                  'qty': j['totalQuantity'],
                  'amount': j['totalAmount'],
                  'stockItemMasterId': j['stockItemMasterId'],
                }),
              )
              .toList();
          itemList = append ? [...state.itemList, ...page] : page;
          break;
        case 'Bills':
          // `normal` view rows are raw ledger-report detail rows (one per
          // ledger entry, not merged per voucher the way the old
          // eager-fetch-then-group approach did - see
          // `items_drill_down_notifier.dart`'s identical Bills note for
          // why merging across a page boundary isn't possible under real
          // pagination). `Partyledger` here is the screen's own ledger
          // name, not per-row server data.
          final page = result.items
              .map((j) {
                // `amount` is an unsigned magnitude; `isDebit` is the
                // separate direction flag - debit negative/credit
                // positive matches the convention already established
                // elsewhere (party_clicked_notifier.dart,
                // ledgerSummary's SQL). Without applying it here every
                // bill row showed as if it were always the same
                // direction regardless of the real transaction.
                final rawAmount = parseMoneyField(j['amount']);
                final signedAmount =
                    j['isDebit'] == true ? -rawAmount : rawAmount;
                return PBill.fromJson({
                  'vchno': j['voucherNumber'],
                  'Partyledger': args.ledger,
                  'vchdate': j['date'],
                  'amount': signedAmount,
                });
              })
              .toList();
          billsList = append ? [...state.billsList, ...page] : page;
          break;
        case 'Voucher Type':
          // `qty` here is the voucher/invoice count, not a real quantity -
          // matches the pre-existing "count of vouchers" meaning this field
          // has always had for the Voucher Type/Cost Center groupings.
          final page = result.items
              .map(
                (j) => PVchType.fromJson({
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
                (j) => PCostCenter.fromJson({
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
          itemList.isEmpty &&
          billsList.isEmpty &&
          vchtypeList.isEmpty &&
          costcenterList.isEmpty;

      state = state.copyWith(
        isLoading: false,
        isLoadingMore: false,
        itemList: itemList,
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
        filteredItems: List.from(state.itemList),
        filteredBills: List.from(state.billsList),
        filteredVchtype: List.from(state.vchtypeList),
        filteredCostcenter: List.from(state.costcenterList),
      );
    } else {
      state = state.copyWith(
        filteredItems:
            state.itemList.where((e) => e.item.toLowerCase().contains(q)).toList(),
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

  /// Sorting only ever reorders what's been loaded so far - see
  /// `items_drill_down_notifier.dart`'s identical note on why a true
  /// global sort isn't attempted under real pagination.
  void _applySortOption(String option) {
    final isSales = args.type == 'Sales';
    var items = List<PItem>.from(state.filteredItems);
    var bills = List<PBill>.from(state.filteredBills);
    var vchtype = List<PVchType>.from(state.filteredVchtype);
    var costcenter = List<PCostCenter>.from(state.filteredCostcenter);

    switch (option) {
      case 'Default':
        items = List.from(state.itemList);
        bills = List.from(state.billsList);
        vchtype = List.from(state.vchtypeList);
        costcenter = List.from(state.costcenterList);
        break;
      case 'A->Z':
        items.sort((a, b) => a.item.compareTo(b.item));
        bills.sort((a, b) => a.Partyledger.compareTo(b.Partyledger));
        vchtype.sort((a, b) => a.vchname.compareTo(b.vchname));
        costcenter.sort((a, b) => a.costcentre.compareTo(b.costcentre));
        break;
      case 'Z->A':
        items.sort((a, b) => b.item.compareTo(a.item));
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
        items.sort(
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
        items.sort(
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
      filteredItems: items,
      filteredBills: bills,
      filteredVchtype: vchtype,
      filteredCostcenter: costcenter,
    );
  }
}

final partyDrillDownNotifierProvider = StateNotifierProvider.autoDispose
    .family<PartyDrillDownNotifier, PartyDrillDownState, PartyDrillDownArgs>(
  (ref, args) => PartyDrillDownNotifier(args),
);
