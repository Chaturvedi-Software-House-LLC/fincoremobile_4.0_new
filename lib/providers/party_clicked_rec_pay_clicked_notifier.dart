import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../PartyClickedRecPayClicked.dart';
import '../api/monthly_bucket_helper.dart';
import 'repository_providers.dart';

class PartyClickedRecPayClickedArgs {
  final String startDateString;
  final String endDateString;
  final String type;
  final String variable;
  final String variabletype;
  final int? ledgerMasterId;

  const PartyClickedRecPayClickedArgs({
    required this.startDateString,
    required this.endDateString,
    required this.type,
    required this.variable,
    required this.variabletype,
    this.ledgerMasterId,
  });

  @override
  bool operator ==(Object other) =>
      other is PartyClickedRecPayClickedArgs &&
      other.startDateString == startDateString &&
      other.endDateString == endDateString &&
      other.type == type &&
      other.variable == variable &&
      other.variabletype == variabletype &&
      other.ledgerMasterId == ledgerMasterId;

  @override
  int get hashCode => Object.hash(
        startDateString,
        endDateString,
        type,
        variable,
        variabletype,
        ledgerMasterId,
      );
}

class PartyClickedRecPayClickedState {
  final bool isLoading;
  final bool isListVisible;
  final bool isSortVisible;
  final bool isVisibleNoDataFound;
  final bool isSearchViewVisible;
  final bool isVisibleDays;
  final List<Data> itemList;
  final List<Data> filteredItems;
  final String selectedSortOption;
  final String company;
  final String currencySymbol;
  final String currencyCode;
  final String creditLimit;
  final String creditPeriod;
  final String overdueValue;
  final String endDateText;
  final List<int> ageingThresholds;
  final String? selectedAgeingBucket;

  const PartyClickedRecPayClickedState({
    this.isLoading = false,
    this.isListVisible = true,
    this.isSortVisible = false,
    this.isVisibleNoDataFound = false,
    this.isSearchViewVisible = false,
    this.isVisibleDays = false,
    this.itemList = const [],
    this.filteredItems = const [],
    this.selectedSortOption = 'Default',
    this.company = '',
    this.currencySymbol = '',
    this.currencyCode = 'AED',
    this.creditLimit = '0',
    this.creditPeriod = '0',
    this.overdueValue = '',
    this.endDateText = '',
    this.ageingThresholds = const [30, 60, 90, 120, 180],
    this.selectedAgeingBucket,
  });

  List<String> get ageingBuckets {
    final t = ageingThresholds;
    return [
      '0-${t[0]}',
      '${t[0]}-${t[1]}',
      '${t[1]}-${t[2]}',
      '${t[2]}-${t[3]}',
      '${t[3]}-${t[4]}',
      '${t[4]}+',
    ];
  }

  PartyClickedRecPayClickedState copyWith({
    bool? isLoading,
    bool? isListVisible,
    bool? isSortVisible,
    bool? isVisibleNoDataFound,
    bool? isSearchViewVisible,
    bool? isVisibleDays,
    List<Data>? itemList,
    List<Data>? filteredItems,
    String? selectedSortOption,
    String? company,
    String? currencySymbol,
    String? currencyCode,
    String? creditLimit,
    String? creditPeriod,
    String? overdueValue,
    String? endDateText,
    List<int>? ageingThresholds,
    String? selectedAgeingBucket,
    bool clearSelectedAgeingBucket = false,
  }) {
    return PartyClickedRecPayClickedState(
      isLoading: isLoading ?? this.isLoading,
      isListVisible: isListVisible ?? this.isListVisible,
      isSortVisible: isSortVisible ?? this.isSortVisible,
      isVisibleNoDataFound: isVisibleNoDataFound ?? this.isVisibleNoDataFound,
      isSearchViewVisible: isSearchViewVisible ?? this.isSearchViewVisible,
      isVisibleDays: isVisibleDays ?? this.isVisibleDays,
      itemList: itemList ?? this.itemList,
      filteredItems: filteredItems ?? this.filteredItems,
      selectedSortOption: selectedSortOption ?? this.selectedSortOption,
      company: company ?? this.company,
      currencySymbol: currencySymbol ?? this.currencySymbol,
      currencyCode: currencyCode ?? this.currencyCode,
      creditLimit: creditLimit ?? this.creditLimit,
      creditPeriod: creditPeriod ?? this.creditPeriod,
      overdueValue: overdueValue ?? this.overdueValue,
      endDateText: endDateText ?? this.endDateText,
      ageingThresholds: ageingThresholds ?? this.ageingThresholds,
      selectedAgeingBucket: clearSelectedAgeingBucket
          ? null
          : (selectedAgeingBucket ?? this.selectedAgeingBucket),
    );
  }
}

class PartyClickedRecPayClickedNotifier
    extends StateNotifier<PartyClickedRecPayClickedState> {
  final Ref _ref;
  final PartyClickedRecPayClickedArgs args;
  String _searchQuery = '';

  PartyClickedRecPayClickedNotifier(this._ref, this.args)
      : super(const PartyClickedRecPayClickedState()) {
    _init();
  }

  String convertDateFormat(String dateStr) {
    if (dateStr == '' || dateStr == 'null') return '';
    final date = DateTime.parse(dateStr);
    return DateFormat('dd-MMM-yyyy').format(date);
  }

  String _bucketFor(String overdueRaw) {
    final days = int.tryParse(overdueRaw) ?? 0;
    final t = state.ageingThresholds;
    final buckets = state.ageingBuckets;
    if (days <= t[0]) return buckets[0];
    if (days <= t[1]) return buckets[1];
    if (days <= t[2]) return buckets[2];
    if (days <= t[3]) return buckets[3];
    if (days <= t[4]) return buckets[4];
    return buckets[5];
  }

  Map<String, List<Data>> itemsByBucket() {
    final map = {for (final b in state.ageingBuckets) b: <Data>[]};
    for (final item in state.itemList) {
      map[_bucketFor(item.overdue)]!.add(item);
    }
    return map;
  }

  void toggleSearchView() {
    state = state.copyWith(isSearchViewVisible: !state.isSearchViewVisible);
  }

  void selectAgeingBucket(String? bucket) {
    if (bucket == null || state.selectedAgeingBucket == bucket) {
      state = state.copyWith(clearSelectedAgeingBucket: true);
    } else {
      state = state.copyWith(selectedAgeingBucket: bucket);
    }
    _applyItemFilters();
  }

  void filter(String query) {
    _searchQuery = query;
    _applyItemFilters();
  }

  // Re-applies both the active search text and the active ageing-bucket
  // filter together, so the two work in combination rather than one
  // silently overriding the other.
  void _applyItemFilters() {
    Iterable<Data> items = state.itemList;

    final bucket = state.selectedAgeingBucket;
    if (bucket != null) {
      items = items.where((i) => _bucketFor(i.overdue) == bucket);
    }

    final query = _searchQuery.trim().toLowerCase();
    if (query.isNotEmpty) {
      items = items.where((i) => i.billno.toLowerCase().contains(query));
    }

    state = state.copyWith(filteredItems: items.toList());
  }

  void _applySort(String option) {
    final sorted = List<Data>.from(state.filteredItems);
    switch (option) {
      case 'Oldest to Newest':
        sorted.sort((a, b) => a.billdate.compareTo(b.billdate));
        break;
      case 'Newest to Oldest':
        sorted.sort((a, b) => b.billdate.compareTo(a.billdate));
        break;
      case 'A->Z':
        sorted.sort((a, b) => a.billno.compareTo(b.billno));
        break;
      case 'Z->A':
        sorted.sort((a, b) => b.billno.compareTo(a.billno));
        break;
      case 'Amount Low to High':
        if (args.type == 'Receivable') {
          sorted.sort((a, b) => b.outstanding.compareTo(a.outstanding));
        } else {
          sorted.sort((a, b) => a.outstanding.compareTo(b.outstanding));
        }
        break;
      case 'Amount High to Low':
        if (args.type == 'Receivable') {
          sorted.sort((a, b) => a.outstanding.compareTo(b.outstanding));
        } else {
          sorted.sort((a, b) => b.outstanding.compareTo(a.outstanding));
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

  bool selectSortOption(String option) {
    if (state.filteredItems.isEmpty) return false;
    _applySort(option);
    return true;
  }

  Future<void> _loadAgeingThresholds() async {
    final prefs = await SharedPreferences.getInstance();
    final t = [
      int.tryParse(prefs.getString('heading1') ?? '') ?? 30,
      int.tryParse(prefs.getString('heading2') ?? '') ?? 60,
      int.tryParse(prefs.getString('heading3') ?? '') ?? 90,
      int.tryParse(prefs.getString('heading4') ?? '') ?? 120,
      int.tryParse(prefs.getString('heading5') ?? '') ?? 180,
    ];
    state = state.copyWith(ageingThresholds: t);
  }

  /// `creditLimit`/`creditPeriod` are already columns on the base
  /// `/ledgers` list row - no separate endpoint like legacy's `getLedger`
  /// is needed.
  Future<void> fetchCreditLimit() async {
    try {
      final ledgerMasterId = args.ledgerMasterId;
      final ledgers = await _ref.read(ledgerRepositoryProvider).listLedgers();
      final match = ledgers.firstWhere(
        (l) => l['masterId'] == ledgerMasterId,
        orElse: () => const {},
      );

      final creditLimitValue = parseMoneyField(match['creditLimit']);
      final creditPeriodRaw = match['creditPeriod']?.toString();
      String creditPeriod;
      bool isVisibleDays;
      if (creditPeriodRaw == null || creditPeriodRaw.isEmpty) {
        creditPeriod = '0';
        isVisibleDays = state.isVisibleDays;
      } else if (creditPeriodRaw.contains('Days')) {
        isVisibleDays = false;
        creditPeriod = creditPeriodRaw;
      } else {
        isVisibleDays = true;
        creditPeriod = creditPeriodRaw;
      }

      state = state.copyWith(
        creditLimit: creditLimitValue.toString(),
        creditPeriod: creditPeriod,
        isVisibleDays: isVisibleDays,
      );
    } catch (e) {
      // Matches original behavior: a failure here just leaves credit
      // limit/period at their defaults, no user-facing error.
    }
  }

  /// `reports/ledgers/outstanding-bills` already returns every open bill
  /// for this ledger with a server-computed `overdueDays` - no separate
  /// "showAll"/ageing-bucket param needed, since the ageing bucket split
  /// happens entirely client-side in this screen already
  /// (`ageingBuckets`/`selectedAgeingBucket`). `isDebit == 'true'` (set by
  /// the caller for the Receivable tile) keeps only bills with a positive
  /// balance; the Payable tile (isDebit == '') keeps the rest - matching
  /// `DashboardClicked.dart`'s `_fetchReceivablePayableTallyApi` convention.
  Future<void> fetchData(String isDebit) async {
    state = state.copyWith(
      isLoading: true,
      isListVisible: true,
      isSortVisible: false,
      clearSelectedAgeingBucket: true,
    );

    try {
      final bills = await _ref
          .read(ledgerRepositoryProvider)
          .outstandingBills(ledgerMasterId: args.ledgerMasterId!);

      final rows = bills.where((bill) {
        final balance = parseMoneyField(bill['finalBalance']);
        return isDebit == 'true' ? balance > 0 : balance <= 0;
      }).map((bill) {
        return Data.fromJson({
          'billno': bill['name'] ?? '',
          'overdue': bill['overdueDays']?.toString() ?? '0',
          'outstanding': parseMoneyField(bill['finalBalance']).abs(),
          'billdate': bill['date'] ?? '',
          'duedate': bill['dueDate'] ?? 'null',
        });
      }).toList();

      state = state.copyWith(
        itemList: rows,
        filteredItems: rows,
        isVisibleNoDataFound: false,
      );
    } catch (e) {
      state = state.copyWith(isLoading: false);
      return;
    }

    if (state.itemList.isEmpty) {
      state = state.copyWith(
        isVisibleNoDataFound: true,
        isSortVisible: false,
        isLoading: false,
      );
    } else {
      state = state.copyWith(isSortVisible: true, isLoading: false);
      _applySort(state.selectedSortOption);
    }
  }

  Future<void> _init() async {
    await _loadAgeingThresholds();

    final prefs = await SharedPreferences.getInstance();
    final company = prefs.getString('company_name') ?? '';
    final currencyCode = prefs.getString('currencycode') ?? '';

    String currencySymbol;
    try {
      final format = NumberFormat.simpleCurrency(
        locale: 'en',
        name: currencyCode,
      );
      currencySymbol = format.currencySymbol;
    } catch (e) {
      currencySymbol =
          NumberFormat.currency(locale: 'en', name: currencyCode)
              .currencySymbol;
    }

    var selectedSortOption = prefs.getString('sort') ?? 'Default';

    final endDateText = convertDateFormat(args.endDateString);
    final overdueValue = args.variable + args.variabletype;

    state = state.copyWith(
      company: company,
      currencyCode: currencyCode.isEmpty ? 'AED' : currencyCode,
      currencySymbol: currencySymbol,
      selectedSortOption: selectedSortOption,
      endDateText: endDateText,
      overdueValue: overdueValue,
    );

    await fetchCreditLimit();

    String isDebit = '';
    if (args.type == 'Payable') {
      isDebit = '';
    } else if (args.type == 'Receivable') {
      isDebit = 'true';
    }
    await fetchData(isDebit);
  }
}

final partyClickedRecPayClickedNotifierProvider = StateNotifierProvider
    .autoDispose
    .family<PartyClickedRecPayClickedNotifier, PartyClickedRecPayClickedState,
        PartyClickedRecPayClickedArgs>(
  (ref, args) => PartyClickedRecPayClickedNotifier(ref, args),
);
