import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../PartyClickedSalePurcOrder.dart';
import '../api/monthly_bucket_helper.dart';
import 'repository_providers.dart';

class PartyClickedSalePurcOrderArgs {
  final String startDateString;
  final String endDateString;
  final String type;
  final String ledger;
  final String vchtype;
  final int? ledgerMasterId;

  const PartyClickedSalePurcOrderArgs({
    required this.startDateString,
    required this.endDateString,
    required this.type,
    required this.ledger,
    required this.vchtype,
    this.ledgerMasterId,
  });

  @override
  bool operator ==(Object other) =>
      other is PartyClickedSalePurcOrderArgs &&
      other.startDateString == startDateString &&
      other.endDateString == endDateString &&
      other.type == type &&
      other.ledger == ledger &&
      other.vchtype == vchtype &&
      other.ledgerMasterId == ledgerMasterId;

  @override
  int get hashCode => Object.hash(
        startDateString,
        endDateString,
        type,
        ledger,
        vchtype,
        ledgerMasterId,
      );
}

class PartyClickedSalePurcOrderState {
  final bool isLoading;
  final bool isListVisible;
  final bool isSortVisible;
  final bool isVisibleNoDataFound;
  final bool isSearchViewVisible;
  final List<Data> itemList;
  final List<Data> filteredItems;
  final List<Data_Top> dropdownItems;
  final Data_Top? selectedTopValue;
  final String selectedSortOption;
  final String company;

  const PartyClickedSalePurcOrderState({
    this.isLoading = false,
    this.isListVisible = false,
    this.isSortVisible = false,
    this.isVisibleNoDataFound = false,
    this.isSearchViewVisible = false,
    this.itemList = const [],
    this.filteredItems = const [],
    this.dropdownItems = const [],
    this.selectedTopValue,
    this.selectedSortOption = 'Default',
    this.company = '',
  });

  PartyClickedSalePurcOrderState copyWith({
    bool? isLoading,
    bool? isListVisible,
    bool? isSortVisible,
    bool? isVisibleNoDataFound,
    bool? isSearchViewVisible,
    List<Data>? itemList,
    List<Data>? filteredItems,
    List<Data_Top>? dropdownItems,
    Data_Top? selectedTopValue,
    String? selectedSortOption,
    String? company,
  }) {
    return PartyClickedSalePurcOrderState(
      isLoading: isLoading ?? this.isLoading,
      isListVisible: isListVisible ?? this.isListVisible,
      isSortVisible: isSortVisible ?? this.isSortVisible,
      isVisibleNoDataFound: isVisibleNoDataFound ?? this.isVisibleNoDataFound,
      isSearchViewVisible: isSearchViewVisible ?? this.isSearchViewVisible,
      itemList: itemList ?? this.itemList,
      filteredItems: filteredItems ?? this.filteredItems,
      dropdownItems: dropdownItems ?? this.dropdownItems,
      selectedTopValue: selectedTopValue ?? this.selectedTopValue,
      selectedSortOption: selectedSortOption ?? this.selectedSortOption,
      company: company ?? this.company,
    );
  }
}

class PartyClickedSalePurcOrderNotifier
    extends StateNotifier<PartyClickedSalePurcOrderState> {
  final Ref _ref;
  final PartyClickedSalePurcOrderArgs args;

  PartyClickedSalePurcOrderNotifier(this._ref, this.args)
      : super(const PartyClickedSalePurcOrderState()) {
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
        filteredItems:
            state.itemList.where((i) => i.item.toLowerCase().contains(lower)).toList(),
      );
    }
  }

  void _applySort(String option) {
    final sorted = List<Data>.from(state.filteredItems);
    switch (option) {
      case 'A->Z':
        sorted.sort((a, b) => a.item.compareTo(b.item));
        break;
      case 'Z->A':
        sorted.sort((a, b) => b.item.compareTo(a.item));
        break;
      case 'Amount High to Low':
        if (args.vchtype == 'sales') {
          sorted.sort((a, b) => b.totalAmount.compareTo(a.totalAmount));
        } else if (args.vchtype == 'purchase') {
          sorted.sort((a, b) => a.totalAmount.compareTo(b.totalAmount));
        }
        break;
      case 'Amount Low to High':
        if (args.vchtype == 'sales') {
          sorted.sort((a, b) => a.totalAmount.compareTo(b.totalAmount));
        } else if (args.vchtype == 'purchase') {
          sorted.sort((a, b) => b.totalAmount.compareTo(a.totalAmount));
        }
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

  /// Returns true if the sort actually changed the visible order, so the
  /// widget knows whether to scroll the list back to the top (mirrors the
  /// legacy behavior of always scrolling on a sort action).
  bool selectSortOption(String option) {
    if (state.filteredItems.isEmpty) return false;
    _applySort(option);
    return true;
  }

  void selectTopValue(Data_Top value) {
    state = state.copyWith(selectedTopValue: value);
    fetchOrders();
  }

  Future<void> _init() async {
    final prefs = await SharedPreferences.getInstance();
    final company = prefs.getString('company_name') ?? '';

    var selectedSortOption = prefs.getString('sort') ?? 'Default';
    const itemList = [
      'Default',
      'A->Z',
      'Z->A',
      'Amount High to Low',
      'Amount Low to High',
    ];
    if (!itemList.contains(selectedSortOption)) {
      selectedSortOption = 'Default';
    }

    // See `Data_Top`'s doc-comment - a single no-op entry for the current
    // party, replacing legacy's multi-party dropdown fetch.
    final dropdownItems = [Data_Top(Partyledger: args.ledger)];

    state = state.copyWith(
      company: company,
      selectedSortOption: selectedSortOption,
      dropdownItems: dropdownItems,
      selectedTopValue: dropdownItems.first,
    );

    await fetchOrders();
  }

  /// Legacy's "party-switching" dropdown (`getOrderSummary`'s `Partyledger`
  /// doc-comment) - this just seeds `dropdownItems`/`selectedTopValue` with
  /// the single current party, then fetches this party's pending orders via
  /// `LedgerRepository.pendingOrdersByItem`.
  Future<void> fetchOrders() async {
    final ledgerMasterId = args.ledgerMasterId;
    if (ledgerMasterId == null) {
      state = state.copyWith(isLoading: false, isVisibleNoDataFound: true);
      return;
    }

    state = state.copyWith(
      isLoading: true,
      isListVisible: true,
      isSortVisible: false,
      isVisibleNoDataFound: false,
    );

    try {
      final from = parseCompactDate(args.startDateString);
      final to = parseCompactDate(args.endDateString);
      final rows = await _ref.read(ledgerRepositoryProvider).pendingOrdersByItem(
            ledgerMasterId,
            isSales: args.vchtype == 'sales',
            from: from,
            to: to,
          );

      final items = [
        for (final row in rows)
          Data(
            item: (row['stockItemName'] ?? '').toString(),
            stockItemMasterId: row['stockItemMasterId'] as int,
            totalQty: parseMoneyField(row['pendingQuantity']).toString(),
            totalAmount: parseMoneyField(row['pendingAmount']),
          ),
      ];

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

final partyClickedSalePurcOrderNotifierProvider = StateNotifierProvider
    .autoDispose
    .family<PartyClickedSalePurcOrderNotifier, PartyClickedSalePurcOrderState,
        PartyClickedSalePurcOrderArgs>(
  (ref, args) => PartyClickedSalePurcOrderNotifier(ref, args),
);
