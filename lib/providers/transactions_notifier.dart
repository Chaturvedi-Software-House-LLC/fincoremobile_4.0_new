import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../Transactions.dart';
import '../api/api_exception.dart';
import '../api/monthly_bucket_helper.dart';
import '../api/pagination_helper.dart';
import '../api/tally_api_client.dart';
import '../api/voucher_repository.dart';
import 'repository_providers.dart';

/// Riverpod migration of `Transactions.dart`'s `_TransactionsPageState`.
///
/// Same verbatim-port `_commit`/`_snapshot` strategy as
/// `party_clicked_notifier.dart`/`dashboard_clicked_notifier.dart`. This
/// screen was deliberately deferred during the original migration batch
/// because of `_txRequestGen`: a request-generation guard that discards a
/// stale in-flight page fetch if a newer date-range/voucher-type selection
/// has since started (see the field's doc comment on `_txRequestGen` below).
/// That guard is pure synchronous field comparison - moving the fields it
/// compares into a notifier doesn't change its correctness, so the fetch/
/// paging methods here are ported byte-for-byte, only `setState` -> `_commit`.
///
/// NOT ported here (stay widget-local, unchanged, in `Transactions.dart`):
/// - `TextEditingController` (`searchController`), `ScrollController`s
///   (`_scrollFabController`; `_scrollController_transactions` was already
///   dead code pre-migration - declared but never attached to any
///   scrollable, so its `animateTo` calls were permanent no-ops - dropped
///   entirely rather than ported), `GlobalKey`s.
/// - `_selectDateRange`/`_showSelectionWindow` - need `BuildContext`.
/// - The PDF/CSV export methods and `_fullTransactionsForExport` - read-only,
///   converted via the alias-variable pattern instead.
/// - `convertDateFormat`/`formatledger_report`/`formatAlias` - pure
///   render-time helpers with no persisted state.
///
/// Dead fields confirmed unused anywhere in `build()` and dropped rather
/// than ported (same legacy-session-flag pattern as the other two
/// notifiers): `SecuritybtnAcessHolder`, `isDashEnable`, `isRolesEnable`,
/// `isUserEnable`, `isRolesVisible`, `isUserVisible`, `email`, `name`,
/// `datetype`, `username`, `_isDashVisible`, `_isEnddateVisible`,
/// `_IsSizeboxVisible`, `isVisibleAlias`, `counter`/`_isSearchViewVisible`
/// (only referenced by a commented-out block), `_isAllList`,
/// `isClicked_transaction`, `ledgroups` (passed to `fetchParentData` but
/// that parameter is itself unused - `_fetchParentDataTallyApi` ignores it).
class TransactionsState {
  final String selectedSortOption;
  final String startDateText;
  final String endDateText;
  final String startDateString;
  final String endDateString;
  final bool isTextEnabled;
  final dynamic selectedDate;
  final List<transactions> filteredItemsTransactions;
  final String transactionsCount;
  final dynamic selectedTransaction;
  final List<String> spinnerList;
  final List<transactions> transactionsList;
  final bool isVisibleNoDataFound;
  final bool isSortVisible;
  final bool isLoading;
  final bool isLoadingMoreTx;
  final bool isTrendTabSelected;
  final String quickFilter;
  final String currencySymbol;
  final String currencyCode;
  final int decimal;
  final String? company;

  const TransactionsState({
    required this.selectedSortOption,
    required this.startDateText,
    required this.endDateText,
    required this.startDateString,
    required this.endDateString,
    required this.isTextEnabled,
    required this.selectedDate,
    required this.filteredItemsTransactions,
    required this.transactionsCount,
    required this.selectedTransaction,
    required this.spinnerList,
    required this.transactionsList,
    required this.isVisibleNoDataFound,
    required this.isSortVisible,
    required this.isLoading,
    required this.isLoadingMoreTx,
    required this.isTrendTabSelected,
    required this.quickFilter,
    required this.currencySymbol,
    required this.currencyCode,
    required this.decimal,
    required this.company,
  });
}

class TransactionsNotifier extends StateNotifier<TransactionsState> {
  final Ref _ref;

  TransactionsNotifier(this._ref)
    : super(
        const TransactionsState(
          selectedSortOption: '',
          startDateText: '',
          endDateText: '',
          startDateString: '',
          endDateString: '',
          isTextEnabled: true,
          selectedDate: null,
          filteredItemsTransactions: [],
          transactionsCount: '0',
          selectedTransaction: 'All Transactions',
          spinnerList: ['All Transactions'],
          transactionsList: [],
          isVisibleNoDataFound: false,
          isSortVisible: false,
          isLoading: false,
          isLoadingMoreTx: false,
          isTrendTabSelected: false,
          quickFilter: 'All',
          currencySymbol: '',
          currencyCode: 'AED',
          decimal: 2,
          company: '',
        ),
      ) {
    _init();
  }

  void _commit(void Function() fn) {
    fn();
    state = _snapshot();
  }

  TransactionsState _snapshot() => TransactionsState(
    selectedSortOption: selectedSortOption,
    startDateText: startdate_text,
    endDateText: enddate_text,
    startDateString: startDateString,
    endDateString: endDateString,
    isTextEnabled: _isTextEnabled,
    selectedDate: _selecteddate,
    filteredItemsTransactions: List.unmodifiable(filteredItems_transactions),
    transactionsCount: transactions_count,
    selectedTransaction: _selectedtransaction,
    spinnerList: List.unmodifiable(spinner_list),
    transactionsList: List.unmodifiable(transactions_list),
    isVisibleNoDataFound: isVisibleNoDataFound,
    isSortVisible: isSortVisible,
    isLoading: _isLoading,
    isLoadingMoreTx: _isLoadingMoreTx,
    isTrendTabSelected: _isTrendTabSelected,
    quickFilter: _quickFilter,
    currencySymbol: currencysymbol,
    currencyCode: _currencyCode,
    decimal: decimal ?? 2,
    company: company,
  );

  // ---- verbatim-ported mutable fields (same names as the original State) ----

  String selectedSortOption = '';
  late String startdate_text = "", enddate_text = "";
  String startDateString = "", endDateString = "";
  bool _isTextEnabled = true;
  dynamic _selecteddate;
  List<transactions> filteredItems_transactions = [];
  String transactions_count = "0";
  dynamic _selectedtransaction = "All Transactions";
  List<String> spinner_list = ["All Transactions"];
  final Map<String, int> _voucherTypeMasterIdByName = {};
  List<transactions> transactions_list = [];
  bool isVisibleNoDataFound = false;
  bool isSortVisible = false;
  bool _isLoading = false;
  bool _isLoadingMoreTx = false;
  bool _isTrendTabSelected = false;
  String _quickFilter = 'All';
  bool isVisiblePostdatedTransaction = false;
  late String PostDatedTransactionsHolder;

  DateTime _startDate = DateTime.now();
  DateTime _endDate = DateTime.now().add(const Duration(days: 7));

  late SharedPreferences prefs;
  late NumberFormat currencyFormat;
  late String currencysymbol = '';
  String _currencyCode = 'AED';
  String? company = "";
  late int? decimal;

  static const int _txPageLimit = 30;
  int _txTotalPages = 1;
  int? _txCursor;
  DateTime? _txFrom, _txTo;
  int? _txVoucherTypeMasterId;
  int _txRequestGen = 0;

  List<transactions> _chartTransactionsList = [];
  bool _isChartDataStale = true;

  bool _isAutoSearchLoading = false;

  VoucherRepository get _voucherRepository =>
      _ref.read(voucherRepositoryProvider);

  DateTime get startDate => _startDate;
  DateTime get endDate => _endDate;

  void filterPostDatedTransactions() {
    if (!isVisiblePostdatedTransaction) {
      transactions_list = transactions_list
          .where((transaction) => transaction.ispostdated == '0')
          .toList();
    }
  }

  Future<void> _autoLoadPagesForSearch(String Function() currentQuery) async {
    if (_isAutoSearchLoading) return;
    _isAutoSearchLoading = true;
    try {
      while (true) {
        final query = currentQuery().trim().toLowerCase();
        if (query.isEmpty || _txCursor == null) break;
        final hasMatch = transactions_list.any(
          (t) => t.vchno.toLowerCase().contains(query),
        );
        if (hasMatch) break;

        await loadNextTransactionsPage(currentQuery, silent: true);

        final stillQuery = currentQuery().trim().toLowerCase();
        if (stillQuery.isEmpty) break;
        final matches = transactions_list.where(
          (t) => t.vchno.toLowerCase().contains(stillQuery),
        );
        _commit(() {
          filteredItems_transactions = matches.toList();
          transactions_count = filteredItems_transactions.length.toString();
          isVisibleNoDataFound =
              filteredItems_transactions.isEmpty && _txCursor == null;
        });
      }
    } finally {
      _isAutoSearchLoading = false;
    }
  }

  /// `searchQuery`/`applyQuickFilter` come from the widget's live
  /// `TextEditingController`/quick-filter-chip tap - passed in explicitly
  /// (rather than the notifier owning a `TextEditingController`) since
  /// controllers stay widget-local, mirroring `getCurrentSearchQuery` below.
  void applyTransactionFilters(String Function() getCurrentSearchQuery) {
    Iterable<transactions> items = transactions_list;

    if (_quickFilter == 'Postdated') {
      items = items.where((t) => t.ispostdated == '1');
    } else if (_quickFilter == 'Optional') {
      items = items.where((t) => t.isoptional == '1');
    }

    final query = getCurrentSearchQuery().trim().toLowerCase();
    if (query.isNotEmpty) {
      items = items.where((t) => t.vchno.toLowerCase().contains(query));
    }

    _commit(() {
      filteredItems_transactions = items.toList();
      transactions_count = filteredItems_transactions.length.toString();
    });

    if (query.isNotEmpty &&
        filteredItems_transactions.isEmpty &&
        _txCursor != null) {
      _autoLoadPagesForSearch(getCurrentSearchQuery);
    }
  }

  void setQuickFilter(String label, String Function() getCurrentSearchQuery) {
    _quickFilter = label;
    applyTransactionFilters(getCurrentSearchQuery);
  }

  void sortByDefault() {
    _commit(() {
      if (filteredItems_transactions.isNotEmpty) {
        filteredItems_transactions = List.from(transactions_list);
        transactions_count = filteredItems_transactions.length.toString();
      }
    });
  }

  void sortByAlphabetAtoZ() {
    _commit(() {
      if (filteredItems_transactions.isNotEmpty) {
        filteredItems_transactions.sort(
          (a, b) => a.vchname.compareTo(b.vchname),
        );
        transactions_count = filteredItems_transactions.length.toString();
      }
    });
  }

  void sortByAlphabetZtoA() {
    _commit(() {
      if (filteredItems_transactions.isNotEmpty) {
        filteredItems_transactions.sort(
          (a, b) => b.vchname.compareTo(a.vchname),
        );
        transactions_count = filteredItems_transactions.length.toString();
      }
    });
  }

  void sortByDateLowtoHigh() {
    _commit(() {
      if (filteredItems_transactions.isNotEmpty) {
        filteredItems_transactions.sort(
          (a, b) => a.vchdate.compareTo(b.vchdate),
        );
        transactions_count = filteredItems_transactions.length.toString();
      }
    });
  }

  void sortByDateHightoLow() {
    _commit(() {
      if (filteredItems_transactions.isNotEmpty) {
        filteredItems_transactions.sort(
          (a, b) => b.vchdate.compareTo(a.vchdate),
        );
        transactions_count = filteredItems_transactions.length.toString();
      }
    });
  }

  void sortByAmountLowtoHigh() {
    _commit(() {
      if (filteredItems_transactions.isNotEmpty) {
        filteredItems_transactions.sort(
          (a, b) => a.amount.compareTo(b.amount),
        );
        transactions_count = filteredItems_transactions.length.toString();
      }
    });
  }

  void sortByAmountHightoLow() {
    _commit(() {
      if (filteredItems_transactions.isNotEmpty) {
        filteredItems_transactions.sort(
          (a, b) => b.amount.compareTo(a.amount),
        );
        transactions_count = filteredItems_transactions.length.toString();
      }
    });
  }

  /// Verbatim port of the sort-menu tap dispatch.
  void applySortOption(String option) {
    _commit(() => selectedSortOption = option);
    _applySelectedSort();
  }

  void _applySelectedSort() {
    switch (selectedSortOption) {
      case 'Default':
        sortByDefault();
        break;
      case 'Newest to Oldest':
        sortByDateHightoLow();
        break;
      case 'Oldest to Newest':
        sortByDateLowtoHigh();
        break;
      case 'A->Z':
        sortByAlphabetAtoZ();
        break;
      case 'Z->A':
        sortByAlphabetZtoA();
        break;
      case 'Amount High to Low':
        sortByAmountHightoLow();
        break;
      case 'Amount Low to High':
        sortByAmountLowtoHigh();
        break;
    }
  }

  void _reapplyTransactionDisplay(String Function() getCurrentSearchQuery) {
    applyTransactionFilters(getCurrentSearchQuery);
    _applySelectedSort();
  }

  List<transactions> _mapVouchersToTransactions(
    List<Map<String, dynamic>> vouchers,
  ) {
    final rows = <transactions>[];
    for (final voucher in vouchers) {
      final entries =
          (voucher['ledgerEntries'] as List?)?.cast<Map<String, dynamic>>() ??
          const [];
      if (entries.isEmpty) continue;

      final debitTotal = entries
          .where((e) => e['isDebit'] == true)
          .fold<double>(0, (sum, e) => sum + parseMoneyField(e['amount']));

      rows.add(
        transactions.fromJson({
          'ledger': entries.first['ledgerName'] ?? '',
          'vchname': voucher['voucherTypeName'] ?? '',
          'vchno': voucher['number'] ?? '',
          'amount': debitTotal,
          'vchdate': voucher['date'] ?? '',
          'isoptional': voucher['isOptional'] ?? false,
          'ispostdated': voucher['isPostDated'] ?? false,
          'refno': voucher['reference'] ?? '',
          'refdate': voucher['referenceDate'] ?? '',
          'masterid': voucher['masterId'] ?? '',
        }),
      );
    }
    return rows;
  }

  List<transactions> _filterMapVoucherPage(
    List<Map<String, dynamic>> rawVouchers,
    DateTime from,
    DateTime to,
  ) {
    final inRange = rawVouchers.where((v) {
      final date = DateTime.tryParse(v['date'] as String? ?? '');
      if (date == null) return false;
      return !date.isBefore(DateTime(from.year, from.month, from.day)) &&
          !date.isAfter(DateTime(to.year, to.month, to.day, 23, 59, 59));
    });
    return _mapVouchersToTransactions(inRange.toList());
  }

  Future<List<transactions>> fullTransactionsForExport() async {
    if (_txFrom == null || _txTo == null) return transactions_list;
    final vouchers = await _voucherRepository.listInRange(
      from: _txFrom!,
      to: _txTo!,
      voucherTypeMasterId: _txVoucherTypeMasterId,
    );
    return _mapVouchersToTransactions(vouchers);
  }

  void fetchMainData(String Function() getCurrentSearchQuery) {
    if (_selectedtransaction == "All Transactions") {
      fetchall_transactions(
        startDateString,
        endDateString,
        "",
        getCurrentSearchQuery,
      );
    } else {
      fetchall_transactions(
        startDateString,
        endDateString,
        _selectedtransaction,
        getCurrentSearchQuery,
      );
    }
  }

  void fetchtransactionsData(String Function() getCurrentSearchQuery) {
    _handleDate(_selecteddate, getCurrentSearchQuery);
  }

  Future<void> fetchall_transactions(
    final String startdate,
    final String enddate,
    final String vchname,
    String Function() getCurrentSearchQuery,
  ) async {
    _commit(() {
      transactions_count = "0";
      _isLoading = true;
      isVisibleNoDataFound = false;
      isSortVisible = false;
    });

    filteredItems_transactions.clear();
    _quickFilter = 'All';
    transactions_list.clear();

    int myGen = _txRequestGen;
    try {
      myGen = await _fetchAllTransactionsTallyApi(
        startdate,
        enddate,
        vchname,
        getCurrentSearchQuery,
      );
    } catch (e) {
      if (myGen == _txRequestGen) {
        _commit(() {
          _isLoading = false;
        });
      }
    }

    if (myGen != _txRequestGen) return;

    _commit(() {
      if (transactions_list.isEmpty) {
        transactions_count = "0";
        isVisibleNoDataFound = true;
        isSortVisible = false;
      } else {
        isSortVisible = true;
        _applySelectedSort();
      }
      _isLoading = false;
    });
  }

  Future<int> _fetchAllTransactionsTallyApi(
    final String startdate,
    final String enddate,
    final String vchname,
    String Function() getCurrentSearchQuery,
  ) async {
    final myGen = ++_txRequestGen;
    final from = parseCompactDate(startdate);
    final to = parseCompactDate(enddate);
    final voucherTypeMasterId = (vchname.isEmpty || vchname == 'All Transactions')
        ? null
        : _voucherTypeMasterIdByName[vchname];

    _txFrom = from;
    _txTo = to;
    _txVoucherTypeMasterId = voucherTypeMasterId;
    _isChartDataStale = true;

    final first = await _voucherRepository.listPage(
      page: 1,
      limit: _txPageLimit,
      voucherTypeMasterId: voucherTypeMasterId,
      from: from,
      to: to,
    );
    if (myGen != _txRequestGen) return myGen; // superseded while awaiting

    _txTotalPages = first.totalPages;
    transactions_list.addAll(_filterMapVoucherPage(first.items, from, to));
    _txCursor = _txTotalPages > 1 ? 2 : null;

    isVisibleNoDataFound = false;
    filterPostDatedTransactions();
    _reapplyTransactionDisplay(getCurrentSearchQuery);

    _commit(() {
      transactions_count = filteredItems_transactions.length.toString();
      _isLoading = false;
    });
    return myGen;
  }

  Future<void> loadNextTransactionsPage(
    String Function() getCurrentSearchQuery, {
    bool silent = false,
  }) async {
    if (_isLoadingMoreTx) return;
    final myGen = _txRequestGen;
    final page = _txCursor;
    if (page == null || page > _txTotalPages) {
      _txCursor = null;
      return;
    }

    if (!silent) _commit(() => _isLoadingMoreTx = true);
    try {
      final result = await _voucherRepository.listPage(
        page: page,
        limit: _txPageLimit,
        voucherTypeMasterId: _txVoucherTypeMasterId,
        from: _txFrom,
        to: _txTo,
      );
      if (myGen != _txRequestGen) {
        if (!silent) _commit(() => _isLoadingMoreTx = false);
        return;
      }

      transactions_list.addAll(
        _filterMapVoucherPage(result.items, _txFrom!, _txTo!),
      );
      _txCursor = page + 1 <= _txTotalPages ? page + 1 : null;

      if (!silent) {
        filterPostDatedTransactions();
        _reapplyTransactionDisplay(getCurrentSearchQuery);
        _commit(() {
          _isLoadingMoreTx = false;
          transactions_count = filteredItems_transactions.length.toString();
          isVisibleNoDataFound = transactions_list.isEmpty && _txCursor == null;
        });
      }
    } catch (e) {
      if (!silent && myGen == _txRequestGen) {
        _commit(() => _isLoadingMoreTx = false);
      }
    }
  }

  bool get canLoadMore => _txCursor != null;

  void setTrendTabSelected(bool selected) {
    _commit(() => _isTrendTabSelected = selected);
  }

  Future<void> ensureChartData() async {
    if (!_isChartDataStale) return;
    if (_txFrom == null || _txTo == null) return;

    _commit(() => _isLoading = true);
    try {
      final vouchers = await _voucherRepository.listInRange(
        from: _txFrom!,
        to: _txTo!,
        voucherTypeMasterId: _txVoucherTypeMasterId,
      );
      _commit(() {
        _chartTransactionsList = _mapVouchersToTransactions(vouchers);
        _isChartDataStale = false;
        _isLoading = false;
      });
    } catch (e) {
      _commit(() => _isLoading = false);
    }
  }

  Map<String, Map<String, double>> buildVoucherStackedTotals() {
    final totalsByTypeAndMonth = <String, Map<String, double>>{};
    for (final t in _chartTransactionsList) {
      final date = DateTime.tryParse(t.vchdate);
      if (date == null) continue;
      final monthLabel = DateFormat('MMMM yyyy').format(date);
      final byMonth = totalsByTypeAndMonth.putIfAbsent(t.vchname, () => {});
      byMonth[monthLabel] = (byMonth[monthLabel] ?? 0) + t.amount.abs();
    }
    return totalsByTypeAndMonth;
  }

  Map<String, int> buildVoucherMonthCounts() {
    final countByMonth = <String, int>{};
    for (final t in _chartTransactionsList) {
      final date = DateTime.tryParse(t.vchdate);
      if (date == null) continue;
      final monthLabel = DateFormat('MMMM yyyy').format(date);
      countByMonth[monthLabel] = (countByMonth[monthLabel] ?? 0) + 1;
    }
    return countByMonth;
  }

  Future<void> fetchParentData(String Function() getCurrentSearchQuery) {
    return _fetchParentDataTallyApi(getCurrentSearchQuery);
  }

  Future<void> _fetchParentDataTallyApi(
    String Function() getCurrentSearchQuery,
  ) async {
    _commit(() {
      _isLoading = true;
    });

    try {
      final voucherTypes = await fetchAllPages(
        (page) => TallyApiClient().getForCompany(
          '/voucher-types?page=$page&limit=100',
        ),
      );
      _voucherTypeMasterIdByName.clear();
      for (final row in voucherTypes) {
        final name = row['name']?.toString();
        if (name != null && name.isNotEmpty && !spinner_list.contains(name)) {
          spinner_list.add(name);
          final masterId = row['masterId'];
          if (masterId is int) _voucherTypeMasterIdByName[name] = masterId;
        }
      }
      _commit(() {
        _selectedtransaction = spinner_list[0];
      });
      fetchtransactionsData(getCurrentSearchQuery);
    } on ApiException catch (e) {
      _commit(() {
        _isLoading = false;
      });
    } catch (e) {
      _commit(() {
        _isLoading = false;
      });
    }
  }

  void selectTransactionType(
    String newValue,
    String Function() getCurrentSearchQuery,
  ) {
    _commit(() => _selectedtransaction = newValue);
    fetchtransactionsData(getCurrentSearchQuery);
  }

  static const _monthNames = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];

  String _formatDdMmmYyyy(DateTime d) {
    final day = d.day.toString().padLeft(2, '0');
    return '$day-${_monthNames[d.month - 1]}-${d.year}';
  }

  /// Verbatim port of `_handleDate` - every branch's business logic
  /// (date-string computation + `fetchMainData`) is unchanged; only the
  /// original inline `DateFormat('MMM')`/`DateFormat('dd')` calls were
  /// replaced with the shared `_formatDdMmmYyyy` helper for brevity, since
  /// they always formatted the exact same `dd-MMM-yyyy` shape.
  void _handleDate(dynamic value, String Function() getCurrentSearchQuery) {
    _commit(() => _selecteddate = value);

    if (_selecteddate == "Today") {
      final now = DateTime.now();
      startDateString = _compactDate(now);
      endDateString = _compactDate(now);
      startdate_text = _formatDdMmmYyyy(now);
      enddate_text = _formatDdMmmYyyy(now);
      fetchMainData(getCurrentSearchQuery);
      _commit(() => _isTextEnabled = false);
    } else if (_selecteddate == "Year To Date") {
      final now = DateTime.now();
      final start = DateTime(now.year, 1, 1);
      final end = DateTime(now.year, now.month, now.day);
      startDateString = _compactDate(start);
      endDateString = _compactDate(end);
      startdate_text = _formatDdMmmYyyy(start);
      enddate_text = _formatDdMmmYyyy(end);
      fetchMainData(getCurrentSearchQuery);
      _commit(() => _isTextEnabled = false);
    } else if (_selecteddate == "Yesterday") {
      final yesterday = DateTime.now().subtract(const Duration(days: 1));
      startDateString = _compactDate(yesterday);
      endDateString = _compactDate(yesterday);
      startdate_text = _formatDdMmmYyyy(yesterday);
      enddate_text = _formatDdMmmYyyy(yesterday);
      fetchMainData(getCurrentSearchQuery);
      _commit(() => _isTextEnabled = false);
    } else if (_selecteddate == "This Month") {
      final now = DateTime.now();
      final start = DateTime(now.year, now.month, 1);
      final end = DateTime(now.year, now.month + 1, 0);
      startDateString = _compactDate(start);
      endDateString = _compactDate(end);
      startdate_text = _formatDdMmmYyyy(start);
      enddate_text = _formatDdMmmYyyy(end);
      fetchMainData(getCurrentSearchQuery);
      _commit(() => _isTextEnabled = false);
    } else if (_selecteddate == "Last Month") {
      var start = DateTime.now();
      start = DateTime(start.year, start.month - 1, 1);
      final end = DateTime(start.year, start.month + 1, 0);
      startDateString = _compactDate(start);
      endDateString = _compactDate(end);
      startdate_text = _formatDdMmmYyyy(start);
      enddate_text = _formatDdMmmYyyy(end);
      fetchMainData(getCurrentSearchQuery);
      _commit(() => _isTextEnabled = false);
    } else if (_selecteddate == "This Year") {
      final today = DateTime.now();
      final start = DateTime(today.year, 1, 1);
      final end = DateTime(today.year, 12, 31);
      startDateString = _compactDate(start);
      endDateString = _compactDate(end);
      startdate_text = _formatDdMmmYyyy(start);
      enddate_text = _formatDdMmmYyyy(end);
      fetchMainData(getCurrentSearchQuery);
      _commit(() => _isTextEnabled = false);
    } else if (_selecteddate == "Last Year") {
      final today = DateTime.now();
      final start = DateTime(today.year - 1, 1, 1);
      final end = DateTime(today.year - 1, 12, 31);
      startDateString = _compactDate(start);
      endDateString = _compactDate(end);
      startdate_text = _formatDdMmmYyyy(start);
      enddate_text = _formatDdMmmYyyy(end);
      fetchMainData(getCurrentSearchQuery);
      _commit(() => _isTextEnabled = false);
    } else if (_selecteddate == "Custom Date") {
      _commit(() {
        _isTextEnabled = true;
        startDateString = _compactDate(_startDate);
        endDateString = _compactDate(_endDate);
        startdate_text = _formatDdMmmYyyy(_startDate);
        enddate_text = _formatDdMmmYyyy(_endDate);
      });
      fetchMainData(getCurrentSearchQuery);
    }
  }

  String _compactDate(DateTime d) {
    final mm = d.month.toString().padLeft(2, '0');
    final dd = d.day.toString().padLeft(2, '0');
    return '${d.year}$mm$dd';
  }

  /// Applies a newly-picked custom date range - called by the widget after
  /// `showDateRangePicker` resolves (the picker itself needs `BuildContext`,
  /// so it stays widget-side).
  void setCustomDateRange(
    DateTime start,
    DateTime end,
    String Function() getCurrentSearchQuery,
  ) {
    _startDate = start;
    _endDate = end;
    _commit(() {
      startDateString = _compactDate(start);
      endDateString = _compactDate(end);
      startdate_text = _formatDdMmmYyyy(start);
      enddate_text = _formatDdMmmYyyy(end);
    });
    fetchMainData(getCurrentSearchQuery);
  }

  void handleDate(dynamic value, String Function() getCurrentSearchQuery) {
    _handleDate(value, getCurrentSearchQuery);
  }

  Future<void> _init() async {
    prefs = await SharedPreferences.getInstance();

    company = prefs.getString('company_name') ?? '';
    final datetype = prefs.getString('datetype') ?? 'Today';
    decimal = prefs.getInt('decimalplace') ?? 2;

    String? currencyCode = prefs.getString('currencycode') ?? 'AED';

    currencyFormat = NumberFormat();
    try {
      if (currencyCode == 'INR' ||
          currencyCode == 'EUR' ||
          currencyCode == 'USD' ||
          currencyCode == 'PKR') {
        currencyFormat = NumberFormat('#,##0');
        final format = NumberFormat.simpleCurrency(
          locale: 'en',
          name: currencyCode,
        );
        currencysymbol = format.currencySymbol;
      } else {
        final format = NumberFormat.currency(locale: 'en', name: currencyCode);
        currencysymbol = format.currencySymbol;
        currencyFormat = NumberFormat('#,##0');
      }
    } catch (e) {
      final format = NumberFormat.currency(locale: 'en', name: currencyCode);
      currencysymbol = format.currencySymbol;
      currencyFormat = NumberFormat('#,##0');
    }
    _currencyCode = currencyCode;

    PostDatedTransactionsHolder =
        prefs.getString("postdatedtransactions") ?? "True";
    isVisiblePostdatedTransaction = PostDatedTransactionsHolder == "True";

    _selecteddate = datetype;

    if (_selecteddate == 'Custom Date') {
      _startDate =
          DateTime.tryParse(prefs.getString('startdate') ?? '') ??
          DateTime.now().subtract(const Duration(days: 30));
      _endDate =
          DateTime.tryParse(prefs.getString('enddate') ?? '') ?? DateTime.now();

      startDateString = _compactDate(_startDate);
      endDateString = _compactDate(_endDate);
      startdate_text = _formatDdMmmYyyy(_startDate);
      enddate_text = _formatDdMmmYyyy(_endDate);
    }

    _commit(() {});

    try {
      selectedSortOption = prefs.getString('sort') ?? 'Default';
      if (selectedSortOption == 'null') selectedSortOption = 'Default';
    } catch (e) {
      selectedSortOption = 'Default';
    }

    fetchParentData(() => '');
  }
}

final transactionsNotifierProvider =
    StateNotifierProvider.autoDispose<TransactionsNotifier, TransactionsState>(
      (ref) => TransactionsNotifier(ref),
    );
