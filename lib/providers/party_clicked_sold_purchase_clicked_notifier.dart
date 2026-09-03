import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../PartyClickedSoldPurchaseClicked.dart';
import '../api/voucher_drilldown_helper.dart';
import '../api/monthly_bucket_helper.dart' show parseMoneyField, parseCompactDate;

/// Riverpod migration of `PartyClickedSoldPurchaseClicked.dart`'s
/// `_PartyClickedSoldPurchaseClickedPageState`. Closest sibling:
/// `party_total_clicked_rest_notifier.dart` (same tally-api drilldown
/// fetch and sort-list shape, minus the Amount sort options this screen
/// never had).
class PartyClickedSoldPurchaseClickedArgs {
  final String startDateString;
  final String endDateString;
  final String type;
  final String ledger;
  final String item;
  final int? ledgerMasterId;

  const PartyClickedSoldPurchaseClickedArgs({
    required this.startDateString,
    required this.endDateString,
    required this.type,
    required this.ledger,
    required this.item,
    this.ledgerMasterId,
  });

  @override
  bool operator ==(Object other) =>
      other is PartyClickedSoldPurchaseClickedArgs &&
      other.startDateString == startDateString &&
      other.endDateString == endDateString &&
      other.type == type &&
      other.ledger == ledger &&
      other.item == item &&
      other.ledgerMasterId == ledgerMasterId;

  @override
  int get hashCode => Object.hash(
        startDateString,
        endDateString,
        type,
        ledger,
        item,
        ledgerMasterId,
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

    await fetchData();
  }

  /// tally-api path: filters [VoucherRepository]-backed vouchers to this
  /// ledger + item + voucher type via [fetchDrilldownVouchers], then reads
  /// the matching inventory entry's qty/rate straight off each voucher -
  /// this is exactly the per-invoice history legacy's `getTotalAmount`
  /// (`select: 'true'`) returned.
  Future<void> fetchData() async {
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
        itemName: args.item,
        voucherTypeName: args.type,
      );

      final rows = <Data>[];
      for (final voucher in vouchers) {
        final inventoryEntries =
            (voucher['inventoryEntries'] as List?)
                ?.cast<Map<String, dynamic>>() ??
            const [];
        final matching = inventoryEntries.where(
          (e) => e['stockItemName'] == args.item,
        );
        for (final entry in matching) {
          rows.add(
            Data.fromJson({
              'vchno': voucher['number'] ?? '',
              'vchdate': voucher['date'] ?? '',
              'rate': parseMoneyField(entry['rate']),
              'qty': parseMoneyField(entry['quantity']),
            }),
          );
        }
      }

      state = state.copyWith(
        itemList: rows,
        filteredItems: rows,
        isVisibleNoDataFound: rows.isEmpty,
        isSortVisible: rows.isNotEmpty,
        isLoading: false,
      );
      if (rows.isNotEmpty) {
        _applySort(state.selectedSortOption);
      }
    } catch (e) {
      state = state.copyWith(isLoading: false);
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
