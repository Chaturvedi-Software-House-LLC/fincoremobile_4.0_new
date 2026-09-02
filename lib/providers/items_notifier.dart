import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../Items.dart';
import '../api/api_exception.dart';
import 'repository_providers.dart';

class ItemsState {
  final bool isClicked_allitems;
  final bool isClicked_fastmoving;
  final bool isClicked_inactiveitems;
  final bool isClicked_slowmoving;
  final bool isClicked_movingsummary;
  final bool isClicked_stockvaluation;
  final bool isClicked_itemageing;

  final List<items> filteredItems_inactive_items;
  final List<items> filteredItems_all_items;
  final List<items> filteredItems_active_items;

  final List<items> fastMovingSummaryList;
  final List<items> slowMovingSummaryList;
  final String? movingSummaryDrilldown;
  final List<items> movingSummaryFilteredDrilldown;

  final List<items> stockValuationList;
  final List<items> stockValuationFiltered;

  final List<ItemAgeingBucket> itemAgeingBuckets;
  final ItemAgeingBucket? selectedItemAgeingBucket;
  final List<items> itemAgeingFilteredDrilldown;

  final String fastmovingdays;
  final String fastmovingqty;
  final String slowmovingdays;
  final String slowmovingqty;
  final String inactivedays;

  final bool allitems_visibility;
  final bool fastmovingitems_visibility;
  final bool inactiveitems_visibility;
  final bool rate_visibility;
  final bool amount_visibility;

  final bool isVisibleParent;
  final String company;
  final bool isLoading;
  final String? selectedItem;
  final List<String> spinner_list;

  final List<items> all_items_list;
  final List<items> inactive_items_list;
  final List<items> active_items_list;

  final int itemsPage;
  final int itemsTotalPages;
  final bool isLoadingMoreItems;

  final bool isVisibleNoDataFound;
  final bool isVisibleFilterby;
  final String? selectedFilter;

  final String currencysymbol;
  final String currencyCode;
  final int? decimal;

  final bool isAllList;
  final bool isActiveList;
  final bool isInactiveList;

  final String? errorMessage;

  const ItemsState({
    this.isClicked_allitems = true,
    this.isClicked_fastmoving = false,
    this.isClicked_inactiveitems = false,
    this.isClicked_slowmoving = false,
    this.isClicked_movingsummary = false,
    this.isClicked_stockvaluation = false,
    this.isClicked_itemageing = false,
    this.filteredItems_inactive_items = const [],
    this.filteredItems_all_items = const [],
    this.filteredItems_active_items = const [],
    this.fastMovingSummaryList = const [],
    this.slowMovingSummaryList = const [],
    this.movingSummaryDrilldown,
    this.movingSummaryFilteredDrilldown = const [],
    this.stockValuationList = const [],
    this.stockValuationFiltered = const [],
    this.itemAgeingBuckets = const [],
    this.selectedItemAgeingBucket,
    this.itemAgeingFilteredDrilldown = const [],
    this.fastmovingdays = '',
    this.fastmovingqty = '',
    this.slowmovingdays = '',
    this.slowmovingqty = '',
    this.inactivedays = '',
    this.allitems_visibility = false,
    this.fastmovingitems_visibility = false,
    this.inactiveitems_visibility = false,
    this.rate_visibility = false,
    this.amount_visibility = false,
    this.isVisibleParent = false,
    this.company = '',
    this.isLoading = false,
    this.selectedItem = '',
    this.spinner_list = const [],
    this.all_items_list = const [],
    this.inactive_items_list = const [],
    this.active_items_list = const [],
    this.itemsPage = 1,
    this.itemsTotalPages = 1,
    this.isLoadingMoreItems = false,
    this.isVisibleNoDataFound = false,
    this.isVisibleFilterby = false,
    this.selectedFilter = 'qty',
    this.currencysymbol = '',
    this.currencyCode = 'AED',
    this.decimal = 2,
    this.isAllList = false,
    this.isActiveList = false,
    this.isInactiveList = false,
    this.errorMessage,
  });

  ItemsState copyWith({
    bool? isClicked_allitems,
    bool? isClicked_fastmoving,
    bool? isClicked_inactiveitems,
    bool? isClicked_slowmoving,
    bool? isClicked_movingsummary,
    bool? isClicked_stockvaluation,
    bool? isClicked_itemageing,
    List<items>? filteredItems_inactive_items,
    List<items>? filteredItems_all_items,
    List<items>? filteredItems_active_items,
    List<items>? fastMovingSummaryList,
    List<items>? slowMovingSummaryList,
    String? movingSummaryDrilldown,
    bool clearMovingSummaryDrilldown = false,
    List<items>? movingSummaryFilteredDrilldown,
    List<items>? stockValuationList,
    List<items>? stockValuationFiltered,
    List<ItemAgeingBucket>? itemAgeingBuckets,
    ItemAgeingBucket? selectedItemAgeingBucket,
    bool clearSelectedItemAgeingBucket = false,
    List<items>? itemAgeingFilteredDrilldown,
    String? fastmovingdays,
    String? fastmovingqty,
    String? slowmovingdays,
    String? slowmovingqty,
    String? inactivedays,
    bool? allitems_visibility,
    bool? fastmovingitems_visibility,
    bool? inactiveitems_visibility,
    bool? rate_visibility,
    bool? amount_visibility,
    bool? isVisibleParent,
    String? company,
    bool? isLoading,
    String? selectedItem,
    List<String>? spinner_list,
    List<items>? all_items_list,
    List<items>? inactive_items_list,
    List<items>? active_items_list,
    int? itemsPage,
    int? itemsTotalPages,
    bool? isLoadingMoreItems,
    bool? isVisibleNoDataFound,
    bool? isVisibleFilterby,
    String? selectedFilter,
    String? currencysymbol,
    String? currencyCode,
    int? decimal,
    bool? isAllList,
    bool? isActiveList,
    bool? isInactiveList,
    String? errorMessage,
    bool clearError = false,
  }) {
    return ItemsState(
      isClicked_allitems: isClicked_allitems ?? this.isClicked_allitems,
      isClicked_fastmoving: isClicked_fastmoving ?? this.isClicked_fastmoving,
      isClicked_inactiveitems:
          isClicked_inactiveitems ?? this.isClicked_inactiveitems,
      isClicked_slowmoving: isClicked_slowmoving ?? this.isClicked_slowmoving,
      isClicked_movingsummary:
          isClicked_movingsummary ?? this.isClicked_movingsummary,
      isClicked_stockvaluation:
          isClicked_stockvaluation ?? this.isClicked_stockvaluation,
      isClicked_itemageing: isClicked_itemageing ?? this.isClicked_itemageing,
      filteredItems_inactive_items:
          filteredItems_inactive_items ?? this.filteredItems_inactive_items,
      filteredItems_all_items:
          filteredItems_all_items ?? this.filteredItems_all_items,
      filteredItems_active_items:
          filteredItems_active_items ?? this.filteredItems_active_items,
      fastMovingSummaryList:
          fastMovingSummaryList ?? this.fastMovingSummaryList,
      slowMovingSummaryList:
          slowMovingSummaryList ?? this.slowMovingSummaryList,
      movingSummaryDrilldown: clearMovingSummaryDrilldown
          ? null
          : (movingSummaryDrilldown ?? this.movingSummaryDrilldown),
      movingSummaryFilteredDrilldown:
          movingSummaryFilteredDrilldown ?? this.movingSummaryFilteredDrilldown,
      stockValuationList: stockValuationList ?? this.stockValuationList,
      stockValuationFiltered:
          stockValuationFiltered ?? this.stockValuationFiltered,
      itemAgeingBuckets: itemAgeingBuckets ?? this.itemAgeingBuckets,
      selectedItemAgeingBucket: clearSelectedItemAgeingBucket
          ? null
          : (selectedItemAgeingBucket ?? this.selectedItemAgeingBucket),
      itemAgeingFilteredDrilldown:
          itemAgeingFilteredDrilldown ?? this.itemAgeingFilteredDrilldown,
      fastmovingdays: fastmovingdays ?? this.fastmovingdays,
      fastmovingqty: fastmovingqty ?? this.fastmovingqty,
      slowmovingdays: slowmovingdays ?? this.slowmovingdays,
      slowmovingqty: slowmovingqty ?? this.slowmovingqty,
      inactivedays: inactivedays ?? this.inactivedays,
      allitems_visibility: allitems_visibility ?? this.allitems_visibility,
      fastmovingitems_visibility:
          fastmovingitems_visibility ?? this.fastmovingitems_visibility,
      inactiveitems_visibility:
          inactiveitems_visibility ?? this.inactiveitems_visibility,
      rate_visibility: rate_visibility ?? this.rate_visibility,
      amount_visibility: amount_visibility ?? this.amount_visibility,
      isVisibleParent: isVisibleParent ?? this.isVisibleParent,
      company: company ?? this.company,
      isLoading: isLoading ?? this.isLoading,
      selectedItem: selectedItem ?? this.selectedItem,
      spinner_list: spinner_list ?? this.spinner_list,
      all_items_list: all_items_list ?? this.all_items_list,
      inactive_items_list: inactive_items_list ?? this.inactive_items_list,
      active_items_list: active_items_list ?? this.active_items_list,
      itemsPage: itemsPage ?? this.itemsPage,
      itemsTotalPages: itemsTotalPages ?? this.itemsTotalPages,
      isLoadingMoreItems: isLoadingMoreItems ?? this.isLoadingMoreItems,
      isVisibleNoDataFound: isVisibleNoDataFound ?? this.isVisibleNoDataFound,
      isVisibleFilterby: isVisibleFilterby ?? this.isVisibleFilterby,
      selectedFilter: selectedFilter ?? this.selectedFilter,
      currencysymbol: currencysymbol ?? this.currencysymbol,
      currencyCode: currencyCode ?? this.currencyCode,
      decimal: decimal ?? this.decimal,
      isAllList: isAllList ?? this.isAllList,
      isActiveList: isActiveList ?? this.isActiveList,
      isInactiveList: isInactiveList ?? this.isInactiveList,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    );
  }
}

class ItemsNotifier extends StateNotifier<ItemsState> {
  final Ref _ref;

  ItemsNotifier(this._ref) : super(const ItemsState()) {
    _init();
  }

  final Map<String, int> _groupMasterIdByName = {};

  static const int _itemsPageLimit = 30;

  // Bumped every time fetchall_items (re)starts - see the doc comment on
  // the equivalent field in the pre-migration Items.dart State class /
  // Transactions.dart's `_txRequestGen` for the rationale: discards a
  // still-in-flight older group's page load once a newer one has begun.
  int _itemsRequestGen = 0;
  bool _isAutoSearchLoadingItems = false;

  void clearError() {
    state = state.copyWith(clearError: true);
  }

  Future<void> _init() async {
    final prefs = await SharedPreferences.getInstance();

    final decimal = prefs.getInt('decimalplace') ?? 2;
    final currencyCode = prefs.getString('currencycode') ?? 'AED';

    String currencysymbol;
    try {
      if (currencyCode == 'INR' ||
          currencyCode == 'EUR' ||
          currencyCode == 'USD' ||
          currencyCode == 'PKR') {
        final format = NumberFormat.simpleCurrency(
          locale: 'en',
          name: currencyCode,
        );
        currencysymbol = format.currencySymbol;
      } else {
        final format = NumberFormat.currency(locale: 'en', name: currencyCode);
        currencysymbol = format.currencySymbol;
      }
    } catch (e) {
      final format = NumberFormat.currency(locale: 'en', name: currencyCode);
      currencysymbol = format.currencySymbol;
    }

    final company = prefs.getString('company_name') ?? '';

    final fastmovingdays = prefs.getString('fastmovingdays') ?? '180';
    final fastmovingqty = prefs.getString('fastmovingqty') ?? '1000';

    final slowmovingdays = prefs.getString('slowmovingdays') ?? '181';
    final slowmovingqty = prefs.getString('slowmovingqty') ?? '1000';

    final inactivedays = prefs.getString('inactivedays') ?? '182';

    final allitemsaccess = prefs.getString('allitems') ?? 'False';
    final fastmovingitemsaccess = prefs.getString('activeitems') ?? 'False';
    final inactiveitemsaccess = prefs.getString('inactiveitems') ?? 'False';
    final rateaccess = prefs.getString('rate') ?? 'False';
    final amountaccess = prefs.getString('item_amount') ?? 'False';

    final allitemsVisibility = allitemsaccess == 'True';
    final fastmovingitemsVisibility = fastmovingitemsaccess == 'True';
    final inactiveitemsVisibility = inactiveitemsaccess == 'True';
    final rateVisibility = rateaccess == 'True';
    final amountVisibility = amountaccess == 'True';

    state = state.copyWith(
      decimal: decimal,
      currencyCode: currencyCode,
      currencysymbol: currencysymbol,
      company: company,
      fastmovingdays: fastmovingdays,
      fastmovingqty: fastmovingqty,
      slowmovingdays: slowmovingdays,
      slowmovingqty: slowmovingqty,
      inactivedays: inactivedays,
      allitems_visibility: allitemsVisibility,
      fastmovingitems_visibility: fastmovingitemsVisibility,
      inactiveitems_visibility: inactiveitemsVisibility,
      rate_visibility: rateVisibility,
      amount_visibility: amountVisibility,
      isVisibleParent:
          allitemsVisibility || fastmovingitemsVisibility || inactiveitemsVisibility,
    );

    if (allitemsVisibility || fastmovingitemsVisibility || inactiveitemsVisibility) {
      await fetchParentData();
    }
  }

  Future<void> fetchParentData() async {
    state = state.copyWith(isLoading: true);

    final spinnerList = <String>[];
    _groupMasterIdByName.clear();

    try {
      final groups = await _ref.read(stockRepositoryProvider).listStockGroups();
      spinnerList.add('All Items');
      for (final group in groups) {
        final name = group['name'] as String;
        _groupMasterIdByName[name] = group['masterId'] as int;
        spinnerList.add(name);
      }

      final selected = spinnerList[0];
      state = state.copyWith(spinner_list: spinnerList, selectedItem: selected);

      if (state.allitems_visibility) {
        await fetchItemData('All Items', selected);
      } else if (state.fastmovingitems_visibility) {
        await fetchMovingSummary(selected);
      } else if (state.inactiveitems_visibility) {
        await fetchItemData('InactiveItems', selected);
      }
    } on ApiException catch (e) {
      state = state.copyWith(isLoading: false, errorMessage: e.message);
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        errorMessage: 'Could not reach the server. Please try again.',
      );
    }
  }

  Future<void> fetchItemData(String itemType, String? item) async {
    var resolved = item;
    if (resolved == 'All Items') {
      resolved = '';
    }
    if (itemType == 'All Items') {
      await fetchall_items(resolved ?? '');
    } else if (itemType == 'FastMovingItems') {
      await fetchactive_items(resolved ?? '', state.selectedFilter!);
    } else if (itemType == 'SlowMovingItems') {
      await fetchslow_items(resolved ?? '', state.selectedFilter!);
    } else if (itemType == 'InactiveItems') {
      await fetchinactive_items(resolved ?? '');
    }
  }

  void selectItem(String? value) {
    state = state.copyWith(selectedItem: value);
  }

  void selectFilter(String? value) {
    state = state.copyWith(selectedFilter: value);
  }

  /// Shared by fetchall_items/fetchStockValuation/fetchItemAgeing - all
  /// three read the exact same underlying list, just process it
  /// differently (raw / sorted-by-amount / bucketed-by-date).
  Future<List<items>> _fetchStockItemsList(String parent) async {
    final groupMasterId = parent.isEmpty ? null : _groupMasterIdByName[parent];
    final rows = await _ref.read(stockRepositoryProvider).listStockItems(
      stockGroupMasterId: groupMasterId,
    );
    return rows.map(items.fromJson).toList();
  }

  /// Fetches the full, unpaginated "All Items" list on demand for PDF/CSV
  /// export - see the doc comment on the pre-migration equivalent.
  Future<List<items>> fullAllItemsForExport(String searchQuery) async {
    final selected = state.selectedItem;
    final parent = selected == 'All Items' ? '' : (selected ?? '');
    final all = await _fetchStockItemsList(parent);
    final query = searchQuery.toLowerCase();
    return query.isEmpty
        ? all
        : all.where((e) => e.itemname.toLowerCase().contains(query)).toList();
  }

  /// Starts (or restarts, e.g. on parent-group change) incremental paging
  /// of the "All Items" tab and loads its first page.
  Future<void> fetchall_items(String parent) async {
    _itemsRequestGen++;
    state = state.copyWith(
      isLoading: true,
      isAllList: false,
      isInactiveList: false,
      isActiveList: false,
      isClicked_allitems: true,
      isClicked_fastmoving: false,
      isClicked_slowmoving: false,
      isClicked_inactiveitems: false,
      isClicked_movingsummary: false,
      isClicked_stockvaluation: false,
      isClicked_itemageing: false,
      isVisibleNoDataFound: false,
      isVisibleFilterby: false,
      filteredItems_all_items: const [],
      all_items_list: const [],
      itemsPage: 1,
      itemsTotalPages: 1,
    );

    await _loadNextItemsPage(parent: parent, searchQuery: '');
  }

  /// Loads one more page (30 rows) of the "All Items" tab into
  /// `all_items_list`. [parent] only needs to be passed for the first page.
  Future<void> _loadNextItemsPage({String? parent, required String searchQuery}) async {
    if (state.isLoadingMoreItems) return;
    if (parent == null && state.itemsPage > state.itemsTotalPages) return;

    final myGen = _itemsRequestGen;
    state = state.copyWith(isLoadingMoreItems: true);

    try {
      final resolvedParent = parent ??
          (state.selectedItem == 'All Items' ? '' : (state.selectedItem ?? ''));
      final groupMasterId =
          resolvedParent.isEmpty ? null : _groupMasterIdByName[resolvedParent];
      final result = await _ref.read(stockRepositoryProvider).listStockItemsPage(
        page: state.itemsPage,
        limit: _itemsPageLimit,
        stockGroupMasterId: groupMasterId,
      );
      if (myGen != _itemsRequestGen) {
        // Superseded while awaiting - a newer group selection already
        // cleared/restarted the list; don't apply this stale page.
        state = state.copyWith(isLoadingMoreItems: false);
        return;
      }
      final newAllItems = [
        ...state.all_items_list,
        ...result.items.map(items.fromJson),
      ];

      final filtered = _filterByQuery(newAllItems, searchQuery);

      state = state.copyWith(
        all_items_list: newAllItems,
        itemsTotalPages: result.totalPages,
        itemsPage: state.itemsPage + 1,
        isInactiveList: false,
        isActiveList: false,
        isAllList: true,
        filteredItems_all_items: filtered,
        isLoadingMoreItems: false,
        isLoading: false,
        isVisibleNoDataFound: newAllItems.isEmpty,
      );
    } on ApiException catch (e) {
      state = state.copyWith(
        errorMessage: e.message,
        isInactiveList: false,
        isAllList: state.all_items_list.isNotEmpty,
        isActiveList: false,
        isLoading: false,
        isLoadingMoreItems: false,
      );
    } catch (e) {
      state = state.copyWith(
        errorMessage: 'Could not reach the server. Please try again.',
        isInactiveList: false,
        isAllList: state.all_items_list.isNotEmpty,
        isActiveList: false,
        isLoading: false,
        isLoadingMoreItems: false,
      );
    }
  }

  Future<void> loadMoreItemsIfNeeded(String searchQuery) =>
      _loadNextItemsPage(searchQuery: searchQuery);

  List<items> _filterByQuery(List<items> source, String query) {
    if (query.isEmpty) return source;
    final lower = query.toLowerCase();
    return source.where((e) => e.itemname.toLowerCase().contains(lower)).toList();
  }

  Future<void> fetchactive_items(String parent, String filter) async {
    state = state.copyWith(
      isClicked_allitems: false,
      isClicked_fastmoving: true,
      isClicked_slowmoving: false,
      isClicked_inactiveitems: false,
      isClicked_movingsummary: false,
      isClicked_stockvaluation: false,
      isClicked_itemageing: false,
      isLoading: true,
      isAllList: false,
      isInactiveList: false,
      isActiveList: false,
      isVisibleNoDataFound: false,
      isVisibleFilterby: true,
      filteredItems_active_items: const [],
      active_items_list: const [],
    );

    List<items> parsed = const [];
    String? error;
    try {
      parsed = await _fetchMovingList(parent, filter, 'FAST');
    } on ApiException catch (e) {
      error = e.message;
    } catch (e) {
      error = 'Could not reach the server. Please try again.';
    }

    if (error != null) {
      state = state.copyWith(
        errorMessage: error,
        isInactiveList: false,
        isAllList: false,
        isActiveList: false,
        isLoading: false,
      );
      return;
    }

    final isEmpty = parsed.isEmpty;
    state = state.copyWith(
      active_items_list: parsed,
      filteredItems_active_items: parsed,
      isInactiveList: false,
      isAllList: false,
      isActiveList: !isEmpty,
      isVisibleNoDataFound: isEmpty,
      isLoading: false,
    );
  }

  Future<void> fetchslow_items(String parent, String filter) async {
    state = state.copyWith(
      isClicked_allitems: false,
      isClicked_fastmoving: false,
      isClicked_slowmoving: true,
      isClicked_inactiveitems: false,
      isClicked_movingsummary: false,
      isClicked_stockvaluation: false,
      isClicked_itemageing: false,
      isLoading: true,
      isAllList: false,
      isInactiveList: false,
      isActiveList: false,
      isVisibleNoDataFound: false,
      isVisibleFilterby: true,
      filteredItems_active_items: const [],
      active_items_list: const [],
    );

    List<items> parsed = const [];
    String? error;
    try {
      parsed = await _fetchMovingList(parent, filter, 'SLOW');
    } on ApiException catch (e) {
      error = e.message;
    } catch (e) {
      error = 'Could not reach the server. Please try again.';
    }

    if (error != null) {
      state = state.copyWith(
        errorMessage: error,
        isInactiveList: false,
        isAllList: false,
        isActiveList: false,
        isLoading: false,
      );
      return;
    }

    final isEmpty = parsed.isEmpty;
    state = state.copyWith(
      active_items_list: parsed,
      filteredItems_active_items: parsed,
      isInactiveList: false,
      isAllList: false,
      isActiveList: !isEmpty,
      isVisibleNoDataFound: isEmpty,
      isLoading: false,
    );
  }

  /// `reports/stock-items/movement-analysis` only accepts a single
  /// quantity threshold - see the doc comment on the pre-migration
  /// equivalent for why a "value" filter mode is unsupported server-side.
  Future<List<items>> _fetchMovingList(
    String parent,
    String filter,
    String status,
  ) async {
    String qtyStr = '';
    int days = 0;
    switch (status) {
      case 'FAST':
        qtyStr = filter == 'qty' ? state.fastmovingqty : '';
        days = int.tryParse(state.fastmovingdays) ?? 0;
        break;
      case 'SLOW':
        qtyStr = filter == 'qty' ? state.slowmovingqty : '';
        days = int.tryParse(state.slowmovingdays) ?? 0;
        break;
      default: // INACTIVE
        days = int.tryParse(state.inactivedays) ?? 0;
    }

    final asOf = DateTime.now().subtract(Duration(days: days));
    final groupMasterId = parent.isEmpty ? null : _groupMasterIdByName[parent];

    final rows = await _ref.read(stockRepositoryProvider).movementAnalysis(
      status: status,
      asOf: asOf,
      threshold: double.tryParse(qtyStr),
      stockGroupMasterId: groupMasterId,
    );
    return rows.map(items.fromJson).toList();
  }

  Future<void> fetchMovingSummary(String parent) async {
    state = state.copyWith(
      isClicked_allitems: false,
      isClicked_fastmoving: false,
      isClicked_slowmoving: false,
      isClicked_inactiveitems: false,
      isClicked_movingsummary: true,
      isClicked_stockvaluation: false,
      isClicked_itemageing: false,
      isAllList: false,
      isInactiveList: false,
      isActiveList: false,
      isVisibleNoDataFound: false,
      isVisibleFilterby: true,
      clearMovingSummaryDrilldown: true,
      fastMovingSummaryList: const [],
      slowMovingSummaryList: const [],
      movingSummaryFilteredDrilldown: const [],
      isLoading: true,
    );

    final resolvedParent = parent == 'All Items' ? '' : parent;

    try {
      final filter = state.selectedFilter!;
      final results = await Future.wait([
        _fetchMovingList(resolvedParent, filter, 'FAST'),
        _fetchMovingList(resolvedParent, filter, 'SLOW'),
      ]);

      state = state.copyWith(
        fastMovingSummaryList: results[0],
        slowMovingSummaryList: results[1],
        isLoading: false,
        isVisibleNoDataFound: results[0].isEmpty && results[1].isEmpty,
      );
    } catch (e) {
      state = state.copyWith(
        fastMovingSummaryList: const [],
        slowMovingSummaryList: const [],
        isLoading: false,
        isVisibleNoDataFound: true,
      );
    }
  }

  void setMovingSummaryDrilldown(String? value) {
    state = state.copyWith(
      movingSummaryDrilldown: value,
      clearMovingSummaryDrilldown: value == null,
      movingSummaryFilteredDrilldown: const [],
    );
  }

  void onMovingSummarySearchChanged(String value) {
    if (state.movingSummaryDrilldown == null) return;
    final query = value.toLowerCase();
    final source = state.movingSummaryDrilldown == 'fast'
        ? state.fastMovingSummaryList
        : state.slowMovingSummaryList;
    state = state.copyWith(
      movingSummaryFilteredDrilldown:
          source.where((e) => e.itemname.toLowerCase().contains(query)).toList(),
    );
  }

  void onStockValuationSearchChanged(String value) {
    final query = value.toLowerCase();
    state = state.copyWith(
      stockValuationFiltered: state.stockValuationList
          .where((e) => e.itemname.toLowerCase().contains(query))
          .toList(),
    );
  }

  Future<void> fetchStockValuation(String parent) async {
    state = state.copyWith(
      isClicked_allitems: false,
      isClicked_fastmoving: false,
      isClicked_slowmoving: false,
      isClicked_inactiveitems: false,
      isClicked_movingsummary: false,
      isClicked_stockvaluation: true,
      isClicked_itemageing: false,
      isAllList: false,
      isInactiveList: false,
      isActiveList: false,
      isVisibleNoDataFound: false,
      isVisibleFilterby: false,
      stockValuationList: const [],
      stockValuationFiltered: const [],
      isLoading: true,
    );

    final resolvedParent = parent == 'All Items' ? '' : parent;

    try {
      final parsed = await _fetchStockItemsList(resolvedParent)
        ..sort(
          (a, b) => (double.tryParse(b.c_amount) ?? 0.0).compareTo(
            double.tryParse(a.c_amount) ?? 0.0,
          ),
        );

      state = state.copyWith(
        stockValuationList: parsed,
        isVisibleNoDataFound: parsed.isEmpty,
        isLoading: false,
      );
    } on ApiException catch (e) {
      state = state.copyWith(
        errorMessage: e.message,
        stockValuationList: const [],
        isVisibleNoDataFound: true,
        isLoading: false,
      );
    } catch (e) {
      state = state.copyWith(
        errorMessage: 'Could not reach the server. Please try again.',
        stockValuationList: const [],
        isVisibleNoDataFound: true,
        isLoading: false,
      );
    }
  }

  DateTime? _parseItemDateSafe(String value) {
    if (value == 'null' || value.isEmpty) return null;
    try {
      return DateTime.parse(value);
    } catch (_) {
      return null;
    }
  }

  void setSelectedItemAgeingBucket(ItemAgeingBucket? bucket) {
    state = state.copyWith(
      selectedItemAgeingBucket: bucket,
      clearSelectedItemAgeingBucket: bucket == null,
      itemAgeingFilteredDrilldown: const [],
    );
  }

  void onItemAgeingSearchChanged(String value) {
    if (state.selectedItemAgeingBucket == null) return;
    final query = value.toLowerCase();
    state = state.copyWith(
      itemAgeingFilteredDrilldown: state.selectedItemAgeingBucket!.itemsList
          .where((e) => e.itemname.toLowerCase().contains(query))
          .toList(),
    );
  }

  Future<void> fetchItemAgeing(String parent) async {
    state = state.copyWith(
      isClicked_allitems: false,
      isClicked_fastmoving: false,
      isClicked_slowmoving: false,
      isClicked_inactiveitems: false,
      isClicked_movingsummary: false,
      isClicked_stockvaluation: false,
      isClicked_itemageing: true,
      isAllList: false,
      isInactiveList: false,
      isActiveList: false,
      isVisibleNoDataFound: false,
      isVisibleFilterby: false,
      itemAgeingBuckets: const [],
      clearSelectedItemAgeingBucket: true,
      itemAgeingFilteredDrilldown: const [],
      isLoading: true,
    );

    final resolvedParent = parent == 'All Items' ? '' : parent;

    try {
      final parsedItems = await _fetchStockItemsList(resolvedParent);

      // Same configurable thresholds as the voucher Ageing Report
      // (AgeingConfig.dart), so both reports stay in sync from one
      // settings screen.
      final ageingPrefs = await SharedPreferences.getInstance();
      final h1 = int.tryParse(ageingPrefs.getString('heading1') ?? '30') ?? 30;
      final h2 = int.tryParse(ageingPrefs.getString('heading2') ?? '60') ?? 60;
      final h3 = int.tryParse(ageingPrefs.getString('heading3') ?? '90') ?? 90;
      final h4 = int.tryParse(ageingPrefs.getString('heading4') ?? '120') ?? 120;
      final h5 = int.tryParse(ageingPrefs.getString('heading5') ?? '180') ?? 180;

      final b1 = ItemAgeingBucket('0-$h1 Days');
      final b2 = ItemAgeingBucket('$h1-$h2 Days');
      final b3 = ItemAgeingBucket('$h2-$h3 Days');
      final b4 = ItemAgeingBucket('$h3-$h4 Days');
      final b5 = ItemAgeingBucket('$h4-$h5 Days');
      final b6 = ItemAgeingBucket('$h5+ Days');
      final noMovement = ItemAgeingBucket('No Sales/Purchase Data');

      final today = DateTime.now();
      final todayDate = DateTime(today.year, today.month, today.day);

      for (final item in parsedItems) {
        final saleDate = _parseItemDateSafe(item.lastsale);
        final purcDate = _parseItemDateSafe(item.lastpurc);

        DateTime? lastMovement;
        if (saleDate != null && purcDate != null) {
          lastMovement = saleDate.isAfter(purcDate) ? saleDate : purcDate;
        } else {
          lastMovement = saleDate ?? purcDate;
        }

        final amount = double.tryParse(item.c_amount)?.abs() ?? 0.0;

        if (lastMovement == null) {
          noMovement.count++;
          noMovement.value += amount;
          noMovement.itemsList.add(item);
          continue;
        }

        final daysSince = todayDate
            .difference(
              DateTime(lastMovement.year, lastMovement.month, lastMovement.day),
            )
            .inDays;

        ItemAgeingBucket bucket;
        if (daysSince <= h1) {
          bucket = b1;
        } else if (daysSince <= h2) {
          bucket = b2;
        } else if (daysSince <= h3) {
          bucket = b3;
        } else if (daysSince <= h4) {
          bucket = b4;
        } else if (daysSince <= h5) {
          bucket = b5;
        } else {
          bucket = b6;
        }

        bucket.count++;
        bucket.value += amount;
        bucket.itemsList.add(item);
      }

      final buckets = [b1, b2, b3, b4, b5, b6, noMovement]
          .where((b) => b.count > 0)
          .toList();

      state = state.copyWith(
        itemAgeingBuckets: buckets,
        isVisibleNoDataFound: parsedItems.isEmpty,
        isLoading: false,
      );
    } on ApiException catch (e) {
      state = state.copyWith(
        errorMessage: e.message,
        itemAgeingBuckets: const [],
        isVisibleNoDataFound: true,
        isLoading: false,
      );
    } catch (e) {
      state = state.copyWith(
        errorMessage: 'Could not reach the server. Please try again.',
        itemAgeingBuckets: const [],
        isVisibleNoDataFound: true,
        isLoading: false,
      );
    }
  }

  Future<void> fetchinactive_items(String parent) async {
    state = state.copyWith(
      isLoading: true,
      isAllList: false,
      isActiveList: false,
      isInactiveList: false,
      isVisibleNoDataFound: false,
      isClicked_allitems: false,
      isClicked_fastmoving: false,
      isClicked_slowmoving: false,
      isClicked_movingsummary: false,
      isClicked_stockvaluation: false,
      isClicked_itemageing: false,
      isVisibleFilterby: false,
      isClicked_inactiveitems: true,
      filteredItems_inactive_items: const [],
      inactive_items_list: const [],
    );

    List<items> parsed = const [];
    String? error;
    try {
      parsed = await _fetchMovingList(parent, 'qty', 'INACTIVE');
    } on ApiException catch (e) {
      error = e.message;
    } catch (e) {
      error = 'Could not reach the server. Please try again.';
    }

    if (error != null) {
      state = state.copyWith(
        errorMessage: error,
        isInactiveList: false,
        isAllList: false,
        isActiveList: false,
        isLoading: false,
      );
      return;
    }

    final isEmpty = parsed.isEmpty;
    state = state.copyWith(
      inactive_items_list: parsed,
      filteredItems_inactive_items: parsed,
      isInactiveList: !isEmpty,
      isActiveList: false,
      isAllList: false,
      isVisibleNoDataFound: isEmpty,
      isLoading: false,
    );
  }

  void setInactiveDays(String value) {
    state = state.copyWith(inactivedays: value);
  }

  /// Narrower than before on the "All Items" tab: tally-api's
  /// `/stock-items` list has no server-side name-search query param, so
  /// this only searches pages already loaded by infinite scroll
  /// (`all_items_list`), not the whole company's items. Fast/Slow Moving
  /// and Inactive Items are unaffected - those still load their full
  /// result set up front.
  void onSearchChanged(String value, String Function() currentQuery) {
    final query = value.toLowerCase();
    if (state.isAllList) {
      state = state.copyWith(
        filteredItems_all_items: _filterByQuery(state.all_items_list, query),
      );
    } else if (state.isActiveList) {
      state = state.copyWith(
        filteredItems_active_items:
            _filterByQuery(state.active_items_list, query),
      );
    } else if (state.isInactiveList) {
      state = state.copyWith(
        filteredItems_inactive_items:
            _filterByQuery(state.inactive_items_list, query),
      );
    }

    if (state.isAllList &&
        query.isNotEmpty &&
        state.filteredItems_all_items.isEmpty &&
        state.itemsPage <= state.itemsTotalPages) {
      _autoLoadPagesForItemSearch(currentQuery);
    }
  }

  /// A plain "search what's loaded" filter alone would wrongly report "no
  /// match" for an item that exists but sits on a page not yet scrolled
  /// into view - keeps loading pages in the background while a query has
  /// zero matches so far, same pattern as Transactions.dart's equivalent.
  /// [currentQuery] is re-read live (not closed over) each iteration so a
  /// fast-typing user re-reads the freshest query instead of starving on a
  /// stale one.
  Future<void> _autoLoadPagesForItemSearch(String Function() currentQuery) async {
    if (_isAutoSearchLoadingItems) return;
    _isAutoSearchLoadingItems = true;
    try {
      while (true) {
        final query = currentQuery();
        if (query.isEmpty || state.itemsPage > state.itemsTotalPages) break;
        final hasMatch = state.all_items_list
            .any((e) => e.itemname.toLowerCase().contains(query));
        if (hasMatch) break;

        await _loadNextItemsPage(searchQuery: query);

        final stillQuery = currentQuery();
        if (stillQuery.isEmpty) break;
        final filtered = _filterByQuery(state.all_items_list, stillQuery);
        state = state.copyWith(
          filteredItems_all_items: filtered,
          isVisibleNoDataFound: filtered.isEmpty && state.itemsPage > state.itemsTotalPages,
        );
      }
    } finally {
      _isAutoSearchLoadingItems = false;
    }
  }
}

final itemsNotifierProvider =
    StateNotifierProvider.autoDispose<ItemsNotifier, ItemsState>(
  (ref) => ItemsNotifier(ref),
);
