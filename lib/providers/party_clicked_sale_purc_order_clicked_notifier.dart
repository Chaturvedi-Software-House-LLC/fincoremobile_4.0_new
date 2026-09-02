import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../PartyClickedSalePurcOrder.dart';
import '../PartyClickedSalePurcOrderClicked.dart';
import '../api/monthly_bucket_helper.dart';
import 'repository_providers.dart';

class PartyClickedSalePurcOrderClickedArgs {
  final String startDateString;
  final String endDateString;
  final String vchtype;
  final String item;
  final List<Data> dropdownItems;
  final int ledgerMasterId;
  final int stockItemMasterId;

  const PartyClickedSalePurcOrderClickedArgs({
    required this.startDateString,
    required this.endDateString,
    required this.vchtype,
    required this.item,
    required this.dropdownItems,
    required this.ledgerMasterId,
    required this.stockItemMasterId,
  });

  @override
  bool operator ==(Object other) =>
      other is PartyClickedSalePurcOrderClickedArgs &&
      other.startDateString == startDateString &&
      other.endDateString == endDateString &&
      other.vchtype == vchtype &&
      other.item == item &&
      other.ledgerMasterId == ledgerMasterId &&
      other.stockItemMasterId == stockItemMasterId;

  @override
  int get hashCode => Object.hash(
        startDateString,
        endDateString,
        vchtype,
        item,
        ledgerMasterId,
        stockItemMasterId,
      );
}

class PartyClickedSalePurcOrderClickedState {
  final bool isLoading;
  final bool isListVisible;
  final bool isSortVisible;
  final bool isVisibleNoDataFound;
  final bool isSearchViewVisible;
  final List<Data_List> itemList;
  final List<Data_List> filteredItems;
  final Data? selectedTopValue;
  final String selectedSortOption;
  final String company;

  const PartyClickedSalePurcOrderClickedState({
    this.isLoading = false,
    this.isListVisible = false,
    this.isSortVisible = false,
    this.isVisibleNoDataFound = false,
    this.isSearchViewVisible = false,
    this.itemList = const [],
    this.filteredItems = const [],
    this.selectedTopValue,
    this.selectedSortOption = 'Default',
    this.company = '',
  });

  PartyClickedSalePurcOrderClickedState copyWith({
    bool? isLoading,
    bool? isListVisible,
    bool? isSortVisible,
    bool? isVisibleNoDataFound,
    bool? isSearchViewVisible,
    List<Data_List>? itemList,
    List<Data_List>? filteredItems,
    Data? selectedTopValue,
    String? selectedSortOption,
    String? company,
  }) {
    return PartyClickedSalePurcOrderClickedState(
      isLoading: isLoading ?? this.isLoading,
      isListVisible: isListVisible ?? this.isListVisible,
      isSortVisible: isSortVisible ?? this.isSortVisible,
      isVisibleNoDataFound: isVisibleNoDataFound ?? this.isVisibleNoDataFound,
      isSearchViewVisible: isSearchViewVisible ?? this.isSearchViewVisible,
      itemList: itemList ?? this.itemList,
      filteredItems: filteredItems ?? this.filteredItems,
      selectedTopValue: selectedTopValue ?? this.selectedTopValue,
      selectedSortOption: selectedSortOption ?? this.selectedSortOption,
      company: company ?? this.company,
    );
  }
}

class PartyClickedSalePurcOrderClickedNotifier
    extends StateNotifier<PartyClickedSalePurcOrderClickedState> {
  final Ref _ref;
  final PartyClickedSalePurcOrderClickedArgs args;

  PartyClickedSalePurcOrderClickedNotifier(this._ref, this.args)
      : super(const PartyClickedSalePurcOrderClickedState()) {
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
            .where((i) => i.orderno.toLowerCase().contains(lower))
            .toList(),
      );
    }
  }

  void _applySort(String option) {
    final sorted = List<Data_List>.from(state.filteredItems);
    switch (option) {
      case 'Oldest to Newest':
        sorted.sort((a, b) => a.vchdate.compareTo(b.vchdate));
        break;
      case 'Newest to Oldest':
        sorted.sort((a, b) => b.vchdate.compareTo(a.vchdate));
        break;
      case 'Amount High to Low':
        if (args.vchtype == 'sales') {
          sorted.sort((a, b) => b.pendingAmount.compareTo(a.pendingAmount));
        } else if (args.vchtype == 'purchase') {
          sorted.sort((a, b) => a.pendingAmount.compareTo(b.pendingAmount));
        }
        break;
      case 'Amount Low to High':
        if (args.vchtype == 'sales') {
          sorted.sort((a, b) => a.pendingAmount.compareTo(b.pendingAmount));
        } else if (args.vchtype == 'purchase') {
          sorted.sort((a, b) => b.pendingAmount.compareTo(a.pendingAmount));
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

  /// Returns true if sorting had rows to reorder, so the widget knows
  /// whether to scroll the list back to the top.
  bool selectSortOption(String option) {
    if (state.filteredItems.isEmpty) return false;
    _applySort(option);
    return true;
  }

  void selectTopValue(Data value) {
    state = state.copyWith(selectedTopValue: value);
    fetchOrderDetail(value.stockItemMasterId);
  }

  Future<void> _init() async {
    final prefs = await SharedPreferences.getInstance();
    final company = prefs.getString('company_name') ?? '';

    var selectedSortOption = prefs.getString('sort') ?? 'Default';
    const itemList = [
      'Default',
      'Newest to Oldest',
      'Oldest to Newest',
      'Amount High to Low',
      'Amount Low to High',
    ];
    if (!itemList.contains(selectedSortOption)) {
      selectedSortOption = 'Default';
    }

    Data? selectedValue;
    try {
      selectedValue =
          args.dropdownItems.firstWhere((item) => item.item == args.item);
    } catch (e) {
      selectedValue = null;
    }

    state = state.copyWith(
      company: company,
      selectedSortOption: selectedSortOption,
      selectedTopValue: selectedValue,
    );

    await fetchOrderDetail(
      selectedValue?.stockItemMasterId ?? args.stockItemMasterId,
    );
  }

  /// Replaces legacy's `getOrderSummary`-with-item-filter call.
  /// [stockItemMasterId] drives the request; `args.item`'s name-string
  /// param is legacy-shaped but no longer used to select data (the
  /// dropdown/initial value resolve their own `stockItemMasterId` via
  /// [Data.stockItemMasterId] instead).
  Future<void> fetchOrderDetail(int stockItemMasterId) async {
    state = state.copyWith(
      isLoading: true,
      isListVisible: true,
      isSortVisible: false,
      isVisibleNoDataFound: false,
    );

    try {
      final from = parseCompactDate(args.startDateString);
      final to = parseCompactDate(args.endDateString);
      final rows =
          await _ref.read(ledgerRepositoryProvider).pendingOrdersByVoucher(
                args.ledgerMasterId,
                stockItemMasterId,
                isSales: args.vchtype == 'sales',
                from: from,
                to: to,
              );

      final items = [
        for (final row in rows)
          Data_List(
            orderno: (row['voucherNumber'] ?? '').toString(),
            pendingQty: parseMoneyField(row['pendingQuantity']).toString(),
            pendingAmount: parseMoneyField(row['pendingAmount']),
            vchdate: (row['date'] ?? '').toString(),
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

final partyClickedSalePurcOrderClickedNotifierProvider =
    StateNotifierProvider.autoDispose.family<
        PartyClickedSalePurcOrderClickedNotifier,
        PartyClickedSalePurcOrderClickedState,
        PartyClickedSalePurcOrderClickedArgs>(
  (ref, args) => PartyClickedSalePurcOrderClickedNotifier(ref, args),
);
