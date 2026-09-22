import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../PartyClickedSoldPurchaseClicked.dart';
import '../api/ledger_repository.dart';
import '../api/voucher_type_repository.dart';
import '../api/monthly_bucket_helper.dart' show parseMoneyField, parseCompactDate;

/// Riverpod migration of `PartyClickedSoldPurchaseClicked.dart`'s
/// `_PartyClickedSoldPurchaseClickedPageState`. Fetches via
/// `LedgerRepository.ledgerReportPage(view: 'normal', ...)`, scoped to both
/// this ledger and this item server-side, with real incremental scroll-
/// pagination - see `items_drill_down_notifier.dart`/
/// `party_total_clicked_rest_notifier.dart` for the general pattern.
class PartyClickedSoldPurchaseClickedArgs {
  final String startDateString;
  final String endDateString;
  final String type;
  final String ledger;
  final String item;
  final int? ledgerMasterId;
  final int? itemMasterId;

  const PartyClickedSoldPurchaseClickedArgs({
    required this.startDateString,
    required this.endDateString,
    required this.type,
    required this.ledger,
    required this.item,
    this.ledgerMasterId,
    this.itemMasterId,
  });

  @override
  bool operator ==(Object other) =>
      other is PartyClickedSoldPurchaseClickedArgs &&
      other.startDateString == startDateString &&
      other.endDateString == endDateString &&
      other.type == type &&
      other.ledger == ledger &&
      other.item == item &&
      other.ledgerMasterId == ledgerMasterId &&
      other.itemMasterId == itemMasterId;

  @override
  int get hashCode => Object.hash(
        startDateString,
        endDateString,
        type,
        ledger,
        item,
        ledgerMasterId,
        itemMasterId,
      );
}

const kPartyClickedSoldPurchaseClickedSortOptions = [
  'Default',
  'Newest to Oldest',
  'Oldest to Newest',
  'A->Z',
  'Z->A',
];

class PartyClickedSoldPurchaseClickedState {
  final bool isLoading;
  final bool isLoadingMore;
  final bool isListVisible;
  final bool isSortVisible;
  final bool isVisibleNoDataFound;
  final bool isSearchViewVisible;
  final List<Data> itemList;
  final List<Data> filteredItems;
  final String selectedSortOption;
  final String company;
  final String currencySymbol;
  final String currencyCode;

  const PartyClickedSoldPurchaseClickedState({
    this.isLoading = false,
    this.isLoadingMore = false,
    this.isListVisible = false,
    this.isSortVisible = false,
    this.isVisibleNoDataFound = false,
    this.isSearchViewVisible = false,
    this.itemList = const [],
    this.filteredItems = const [],
    this.selectedSortOption = 'Default',
    this.company = '',
    this.currencySymbol = '',
    this.currencyCode = 'AED',
  });

  PartyClickedSoldPurchaseClickedState copyWith({
    bool? isLoading,
    bool? isLoadingMore,
    bool? isListVisible,
    bool? isSortVisible,
    bool? isVisibleNoDataFound,
    bool? isSearchViewVisible,
    List<Data>? itemList,
    List<Data>? filteredItems,
    String? selectedSortOption,
    String? company,
    String? currencySymbol,
    String? currencyCode,
  }) {
    return PartyClickedSoldPurchaseClickedState(
      isLoading: isLoading ?? this.isLoading,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
      isListVisible: isListVisible ?? this.isListVisible,
      isSortVisible: isSortVisible ?? this.isSortVisible,
      isVisibleNoDataFound: isVisibleNoDataFound ?? this.isVisibleNoDataFound,
      isSearchViewVisible: isSearchViewVisible ?? this.isSearchViewVisible,
      itemList: itemList ?? this.itemList,
      filteredItems: filteredItems ?? this.filteredItems,
      selectedSortOption: selectedSortOption ?? this.selectedSortOption,
      company: company ?? this.company,
      currencySymbol: currencySymbol ?? this.currencySymbol,
      currencyCode: currencyCode ?? this.currencyCode,
    );
  }
}

class PartyClickedSoldPurchaseClickedNotifier
    extends StateNotifier<PartyClickedSoldPurchaseClickedState> {
  final PartyClickedSoldPurchaseClickedArgs args;

  int _page = 1;
  bool _hasMore = true;
  int? _typeMasterId;

  PartyClickedSoldPurchaseClickedNotifier(this.args)
      : super(const PartyClickedSoldPurchaseClickedState()) {
    _init();
  }

  void toggleSearchView() {
    final next = !state.isSearchViewVisible;
    state = state.copyWith(
      isSearchViewVisible: next,
      filteredItems: state.itemList,
    );
  }

  void filter(String query) {
    if (query.isEmpty) {
      state = state.copyWith(filteredItems: state.itemList);
    } else {
      final lower = query.toLowerCase();
      state = state.copyWith(
        filteredItems: state.itemList
            .where((i) => i.vchno.toLowerCase().contains(lower))
            .toList(),
      );
    }
  }

  void _applySort(String option) {
    final sorted = List<Data>.from(state.filteredItems);
    switch (option) {
      case 'A->Z':
        sorted.sort((a, b) => a.vchno.compareTo(b.vchno));
        break;
      case 'Z->A':
        sorted.sort((a, b) => b.vchno.compareTo(a.vchno));
        break;
      case 'Oldest to Newest':
        sorted.sort((a, b) => a.vchdate.compareTo(b.vchdate));
        break;
      case 'Newest to Oldest':
        sorted.sort((a, b) => b.vchdate.compareTo(a.vchdate));
        break;
      case 'Default':
      default:
        state = state.copyWith(
          selectedSortOption: option,
          filteredItems: List.from(state.itemList),
        );
        return;
    }
    state = state.copyWith(selectedSortOption: option, filteredItems: sorted);
  }

  /// Returns true if sorting had rows to reorder, so the widget knows
  /// whether to scroll the list back to the top.
  bool selectSortOption(String option) {
    if (state.filteredItems.isEmpty) return false;
    _applySort(option);
    return true;
  }

  Future<void> _init() async {
    final prefs = await SharedPreferences.getInstance();
    final company = prefs.getString('company_name') ?? '';

    final currencyCode = prefs.getString('currencycode') ?? 'AED';
    var currencySymbol = '';
    try {
      if (currencyCode == 'INR' ||
          currencyCode == 'EUR' ||
          currencyCode == 'USD' ||
          currencyCode == 'PKR') {
        final format = NumberFormat.simpleCurrency(
          locale: 'en',
          name: currencyCode,
        );
        currencySymbol = format.currencySymbol;
      } else {
        final format = NumberFormat.currency(
          locale: 'en',
          name: currencyCode,
        );
        currencySymbol = format.currencySymbol;
      }
    } catch (e) {
      final format = NumberFormat.currency(locale: 'en', name: currencyCode);
      currencySymbol = format.currencySymbol;
    }

    var selectedSortOption = prefs.getString('sort') ?? 'Default';
    if (!kPartyClickedSoldPurchaseClickedSortOptions.contains(
      selectedSortOption,
    )) {
      selectedSortOption = 'Default';
    }

    state = state.copyWith(
      company: company,
      currencySymbol: currencySymbol,
      currencyCode: currencyCode,
      selectedSortOption: selectedSortOption,
    );

    _typeMasterId = await _resolveTypeMasterId();
    await fetchData();
  }

  Future<int?> _resolveTypeMasterId() async {
    final reservedName = args.type == 'Sales' ? 'SALES' : 'PURCHASE';
    final matches =
        await VoucherTypeRepository.instance.byReservedName(reservedName);
    return matches.isNotEmpty ? matches.first['masterId'] as int? : null;
  }

  Future<void> fetchData() async {
    _page = 1;
    _hasMore = true;
    state = state.copyWith(
      itemList: const [],
      filteredItems: const [],
      isListVisible: true,
      isSortVisible: false,
    );
    await _fetchPage(append: false);
  }

  /// Called by the widget's scroll-near-bottom listener.
  Future<void> loadMore() async {
    if (state.isLoadingMore || state.isLoading || !_hasMore) return;
    await _fetchPage(append: true);
  }

  /// tally-api path: `LedgerRepository.ledgerReportPage(view: 'normal', ...)`
  /// scoped server-side to both this ledger and this item, then reads the
  /// matching inventory entry's qty/rate straight off each row - this is
  /// exactly the per-invoice history legacy's `getTotalAmount`
  /// (`select: 'true'`) returned, now genuinely paginated instead of
  /// fetching every voucher in the company up front.
  Future<void> _fetchPage({required bool append}) async {
    if (args.ledgerMasterId == null) {
      state = state.copyWith(isLoading: false, isVisibleNoDataFound: true);
      return;
    }

    state = state.copyWith(isLoading: !append, isLoadingMore: append);

    try {
      final from = parseCompactDate(args.startDateString);
      final to = parseCompactDate(args.endDateString);
      final nextPage = append ? _page + 1 : 1;
      final result = await LedgerRepository.instance.ledgerReportPage(
        view: 'normal',
        page: nextPage,
        limit: 30,
        ledgerMasterId: args.ledgerMasterId,
        stockItemMasterId: args.itemMasterId,
        voucherTypeMasterId: _typeMasterId,
        from: from,
        to: to,
      );
      _page = nextPage;
      _hasMore = result.hasMore;

      final rows = <Data>[];
      for (final row in result.items) {
        final inventoryEntries =
            (row['inventoryEntries'] as List?)?.cast<Map<String, dynamic>>() ??
            const [];
        // Match by the authoritative stockItemMasterId the backend already
        // scoped this query to, not the display name - a name-string
        // comparison here is fragile (whitespace/casing drift between the
        // two separate report endpoints that produce each side of the
        // comparison) and was silently dropping every row.
        final matching = args.itemMasterId != null
            ? inventoryEntries.where(
                (e) => e['stockItemMasterId'] == args.itemMasterId,
              )
            : inventoryEntries.where((e) => e['stockItemName'] == args.item);
        for (final entry in matching) {
          rows.add(
            Data.fromJson({
              'vchno': row['voucherNumber'] ?? '',
              'vchdate': row['date'] ?? '',
              'rate': parseMoneyField(entry['rate']),
              'qty': parseMoneyField(entry['quantity']),
            }),
          );
        }
      }
      final items = append ? [...state.itemList, ...rows] : rows;

      state = state.copyWith(
        itemList: items,
        filteredItems: items,
        isVisibleNoDataFound: items.isEmpty,
        isSortVisible: items.isNotEmpty,
        isLoading: false,
        isLoadingMore: false,
      );
      if (items.isNotEmpty) {
        _applySort(state.selectedSortOption);
      }
    } catch (e) {
      state = state.copyWith(isLoading: false, isLoadingMore: false);
    }
  }
}

final partyClickedSoldPurchaseClickedNotifierProvider =
    StateNotifierProvider.autoDispose.family<
        PartyClickedSoldPurchaseClickedNotifier,
        PartyClickedSoldPurchaseClickedState,
        PartyClickedSoldPurchaseClickedArgs>(
  (ref, args) => PartyClickedSoldPurchaseClickedNotifier(args),
);
