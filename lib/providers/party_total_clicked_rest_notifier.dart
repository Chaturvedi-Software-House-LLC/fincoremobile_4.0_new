import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../PartyTotalClickedRest.dart';
import '../api/ledger_repository.dart';
import '../api/voucher_type_repository.dart';
import '../api/monthly_bucket_helper.dart'
    show parseCompactDate, parseMoneyField;

/// Riverpod migration of `PartyTotalClickedRest.dart`'s
/// `_PartyTotalClickedRestPageState`. Fetches via
/// `LedgerRepository.ledgerReportPage(view: 'normal', ...)` - ledger-scoped
/// and genuinely paginated (30 rows/page, loaded incrementally as the user
/// scrolls), replacing the previous company-wide `fetchDrilldownVouchers`
/// fetch. This screen is a flat, ungrouped voucher list (no further
/// drill-down from a row), so unlike `ItemsDrillDown.dart`/
/// `PartyDrillDown.dart` there's only ever the one "Bills"-shaped view -
/// see those files for the general pattern this mirrors.
class PartyTotalClickedRestArgs {
  final String startDateString;
  final String endDateString;
  final String type;
  final String ledger;
  final String total;
  final int? ledgerMasterId;

  const PartyTotalClickedRestArgs({
    required this.startDateString,
    required this.endDateString,
    required this.type,
    required this.ledger,
    required this.total,
    this.ledgerMasterId,
  });

  @override
  bool operator ==(Object other) =>
      other is PartyTotalClickedRestArgs &&
      other.startDateString == startDateString &&
      other.endDateString == endDateString &&
      other.type == type &&
      other.ledger == ledger &&
      other.total == total &&
      other.ledgerMasterId == ledgerMasterId;

  @override
  int get hashCode => Object.hash(
        startDateString,
        endDateString,
        type,
        ledger,
        total,
        ledgerMasterId,
      );
}

const kPartyTotalClickedRestSortOptions = [
  'Default',
  'Newest to Oldest',
  'Oldest to Newest',
  'A->Z',
  'Z->A',
  'Amount High to Low',
  'Amount Low to High',
];

class PartyTotalClickedRestState {
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

  const PartyTotalClickedRestState({
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
  });

  PartyTotalClickedRestState copyWith({
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
  }) {
    return PartyTotalClickedRestState(
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
    );
  }
}

class PartyTotalClickedRestNotifier
    extends StateNotifier<PartyTotalClickedRestState> {
  final PartyTotalClickedRestArgs args;

  int _page = 1;
  bool _hasMore = true;
  int? _typeMasterId;

  PartyTotalClickedRestNotifier(this.args)
      : super(const PartyTotalClickedRestState()) {
    _init();
  }

  void toggleSearchView() {
    state = state.copyWith(isSearchViewVisible: !state.isSearchViewVisible);
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
      case 'Amount Low to High':
        sorted.sort((a, b) => a.amount.compareTo(b.amount));
        break;
      case 'Amount High to Low':
        sorted.sort((a, b) => b.amount.compareTo(a.amount));
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

    var selectedSortOption = prefs.getString('sort') ?? 'Default';
    if (!kPartyTotalClickedRestSortOptions.contains(selectedSortOption)) {
      selectedSortOption = 'Default';
    }

    state = state.copyWith(
      company: company,
      selectedSortOption: selectedSortOption,
    );

    _typeMasterId = await _resolveTypeMasterId();
    await fetchData();
  }

  /// `args.type` only ever arrives as a display name (`'Receipt'`/
  /// `'Payment'`/`'Journal'` for this screen) - resolved to a
  /// `voucherTypeMasterId` once here so the paginated fetch below can
  /// filter server-side, same approach as
  /// `items_drill_down_notifier.dart`'s identical lookup.
  Future<int?> _resolveTypeMasterId() async {
    const reservedNames = {
      'Sales': 'SALES',
      'Purchase': 'PURCHASE',
      'Receipt': 'RECEIPT',
      'Payment': 'PAYMENT',
      'CreditNote': 'CREDIT_NOTE',
      'DebitNote': 'DEBIT_NOTE',
      'Journal': 'JOURNAL',
    };
    final reservedName = reservedNames[args.type];
    if (reservedName == null) return null;
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

  Future<void> _fetchPage({required bool append}) async {
    if (args.ledgerMasterId == null) {
      state = state.copyWith(isLoading: false, isVisibleNoDataFound: true);
      return;
    }

    state = state.copyWith(
      isLoading: !append,
      isLoadingMore: append,
    );

    try {
      final from = parseCompactDate(args.startDateString);
      final to = parseCompactDate(args.endDateString);
      final nextPage = append ? _page + 1 : 1;
      final result = await LedgerRepository.instance.ledgerReportPage(
        view: 'normal',
        page: nextPage,
        limit: 30,
        ledgerMasterId: args.ledgerMasterId,
        voucherTypeMasterId: _typeMasterId,
        from: from,
        to: to,
      );
      _page = nextPage;
      _hasMore = result.hasMore;

      final page = result.items
          .map((j) {
            // `amount` is an unsigned magnitude; `isDebit` is the separate
            // direction flag - debit negative/credit positive, same
            // convention already applied to the identical `normal` view
            // in party_drill_down_notifier.dart's Bills mapping. Without
            // this every Receipt/Payment/Journal row here always showed
            // "CR" regardless of the real direction.
            final rawAmount = parseMoneyField(j['amount']);
            final signedAmount = j['isDebit'] == true ? -rawAmount : rawAmount;
            return Data.fromJson({
              'vchno': j['voucherNumber'] ?? '',
              'vchdate': j['date'] ?? '',
              'amount': signedAmount,
              // `Data.ispostdated`/`isoptional` are checked against the
              // literal string '1' downstream (a legacy boolean-flag
              // convention) - `isoptional` is always '0' since the
              // ledger-report query already filters out optional vouchers
              // entirely.
              'ispostdated': j['isPostDated'] == true ? '1' : '0',
              'isoptional': '0',
            });
          })
          .toList();
      final items = append ? [...state.itemList, ...page] : page;

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

final partyTotalClickedRestNotifierProvider = StateNotifierProvider.autoDispose
    .family<PartyTotalClickedRestNotifier, PartyTotalClickedRestState,
        PartyTotalClickedRestArgs>(
  (ref, args) => PartyTotalClickedRestNotifier(args),
);
