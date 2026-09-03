import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../PartyTotalClickedRest.dart';
import '../api/voucher_drilldown_helper.dart';
import '../api/monthly_bucket_helper.dart' show parseMoneyField, parseCompactDate;

/// Riverpod migration of `PartyTotalClickedRest.dart`'s
/// `_PartyTotalClickedRestPageState`. Closest sibling: the tally-api
/// drilldown fetch this screen already used (`_fetchDataTallyApi`, backed
/// by [fetchDrilldownVouchers]) is ported verbatim; only the state
/// container and sorting are moved into a [StateNotifier], following the
/// same shape as `party_clicked_sale_purc_order_clicked_notifier.dart`.
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

    await fetchData();
  }

  Future<void> fetchData() async {
    if (args.ledgerMasterId == null) {
      state = state.copyWith(isLoading: false, isVisibleNoDataFound: true);
      return;
    }

    state = state.copyWith(
      isLoading: true,
      isListVisible: true,
      isSortVisible: false,
    );

    try {
      final from = parseCompactDate(args.startDateString);
      final to = parseCompactDate(args.endDateString);
      final vouchers = await fetchDrilldownVouchers(
        from: from,
        to: to,
        partyLedgerName: args.ledger,
        voucherTypeName: args.type,
      );

      final items = vouchers.map((voucher) {
        final entries =
            (voucher['ledgerEntries'] as List?)
                ?.cast<Map<String, dynamic>>() ??
            const [];
        final ledgerEntry = entries.firstWhere(
          (e) => e['ledgerName'] == args.ledger,
          orElse: () => entries.isNotEmpty ? entries.first : const {},
        );
        return Data.fromJson({
          'vchno': voucher['number'] ?? '',
          'vchdate': voucher['date'] ?? '',
          'amount': parseMoneyField(ledgerEntry['amount']),
          'ispostdated': voucher['isPostDated'] ?? false,
          'isoptional': voucher['isOptional'] ?? false,
        });
      }).toList();

      state = state.copyWith(
        itemList: items,
        filteredItems: items,
        isVisibleNoDataFound: items.isEmpty,
        isSortVisible: items.isNotEmpty,
        isLoading: false,
      );
      if (items.isNotEmpty) {
        _applySort(state.selectedSortOption);
      }
    } catch (e) {
      state = state.copyWith(isLoading: false);
    }
  }
}

final partyTotalClickedRestNotifierProvider = StateNotifierProvider.autoDispose
    .family<PartyTotalClickedRestNotifier, PartyTotalClickedRestState,
        PartyTotalClickedRestArgs>(
  (ref, args) => PartyTotalClickedRestNotifier(args),
);
