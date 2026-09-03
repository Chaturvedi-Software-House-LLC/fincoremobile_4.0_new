import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../PartyDrillDown.dart';
import '../api/voucher_drilldown_helper.dart';
import '../api/monthly_bucket_helper.dart' show parseMoneyField, parseCompactDate;

/// Riverpod migration of `PartyDrillDown.dart`'s `_PartyDrillDownState`.
/// Closest sibling: `party_total_clicked_rest_notifier.dart` (same
/// tally-api drilldown fetch, `fetchDrilldownVouchers`) - this notifier
/// additionally owns the four parallel group lists (Items/Bills/Voucher
/// Type/Cost Center) and re-fetches whenever the selected group changes,
/// same as the original `_fetchGroup`.
class PartyDrillDownArgs {
  final String startDateString;
  final String endDateString;
  final String type;
  final String ledger;
  final int? ledgerMasterId;
  final String? lockedItem;
  final String? lockedCostcenter;
  final String? lockedVchname;

  const PartyDrillDownArgs({
    required this.startDateString,
    required this.endDateString,
    required this.type,
    required this.ledger,
    this.ledgerMasterId,
    this.lockedItem,
    this.lockedCostcenter,
    this.lockedVchname,
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
      other.lockedCostcenter == lockedCostcenter &&
      other.lockedVchname == lockedVchname;

  @override
  int get hashCode => Object.hash(
        startDateString,
        endDateString,
        type,
        ledger,
        ledgerMasterId,
        lockedItem,
        lockedCostcenter,
        lockedVchname,
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
    await selectGroup(state.selectedGroup);
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

    try {
      // No legacy fallback: tally-oauth-only sessions always carry a
      // ledgerMasterId, so a null one here means a legacy-paired session
      // with no tally-api master id - same "not available" empty-state
      // convention used elsewhere in this migration (see PartyClicked.dart).
      final List<dynamic> raw = args.ledgerMasterId != null
          ? await _fetchGroupTallyApi(group)
          : const [];

      var itemList = state.itemList;
      var billsList = state.billsList;
      var vchtypeList = state.vchtypeList;
      var costcenterList = state.costcenterList;

      if (raw.isNotEmpty) {
        switch (group) {
          case 'Items':
            itemList = raw.map((j) => PItem.fromJson(j)).toList();
            break;
          case 'Bills':
            billsList = raw.map((j) => PBill.fromJson(j)).toList();
            break;
          case 'Voucher Type':
            vchtypeList = raw.map((j) => PVchType.fromJson(j)).toList();
            break;
          case 'Cost Center':
            costcenterList = raw.map((j) => PCostCenter.fromJson(j)).toList();
            break;
        }
      }

      final empty =
          itemList.isEmpty &&
          billsList.isEmpty &&
          vchtypeList.isEmpty &&
          costcenterList.isEmpty;

      state = state.copyWith(
        isLoading: false,
        itemList: itemList,
        billsList: billsList,
        vchtypeList: vchtypeList,
        costcenterList: costcenterList,
        isVisibleNoDataFound: empty,
        isSortVisible: !empty,
      );
      _applySortOption(state.selectedSortOption);
    } catch (e) {
      state = state.copyWith(isLoading: false);
    }
  }

  /// The party ledger's own contribution to [voucher] - the amount summed
  /// for "Bills"/"Voucher Type" groupings. When [args.lockedItem] is set
  /// (viewing a specific item's history), the item's inventory-entry amount
  /// is used instead, since that's what the drill-down is actually about at
  /// that point.
  double _voucherAmount(Map<String, dynamic> voucher) {
    if (args.lockedItem != null) {
      final inventoryEntries =
          (voucher['inventoryEntries'] as List?)
              ?.cast<Map<String, dynamic>>() ??
          const [];
      return inventoryEntries
          .where((e) => e['stockItemName'] == args.lockedItem)
          .fold<double>(0, (sum, e) => sum + parseMoneyField(e['amount']));
    }
    final ledgerEntries =
        (voucher['ledgerEntries'] as List?)?.cast<Map<String, dynamic>>() ??
        const [];
    final entry = ledgerEntries.firstWhere(
      (e) => e['ledgerName'] == args.ledger,
      orElse: () => ledgerEntries.isNotEmpty ? ledgerEntries.first : const {},
    );
    return parseMoneyField(entry['amount']);
  }

  /// tally-api path: filters vouchers via [fetchDrilldownVouchers] to this
  /// party/type/locked dimensions, then aggregates client-side into the
  /// exact legacy JSON shape each `PXxx.fromJson` factory already expects
  /// - the rest of this screen (sorting, search, PDF/CSV export) is
  /// untouched. `Voucher Type` grouping is a known simplification: unlike
  /// legacy Tally, tally-api's `voucherTypeName` has no broader/narrower
  /// hierarchy, so once [args.type] is already fixed this almost always
  /// yields one group rather than several.
  Future<List<Map<String, dynamic>>> _fetchGroupTallyApi(String group) async {
    final from = parseCompactDate(args.startDateString);
    final to = parseCompactDate(args.endDateString);
    final vouchers = await fetchDrilldownVouchers(
      from: from,
      to: to,
      partyLedgerName: args.ledger,
      itemName: args.lockedItem,
      voucherTypeName: args.lockedVchname ?? args.type,
      costCentreName: args.lockedCostcenter,
    );

    switch (group) {
      case 'Items':
        final totals = <String, Map<String, double>>{};
        for (final voucher in vouchers) {
          final inventoryEntries =
              (voucher['inventoryEntries'] as List?)
                  ?.cast<Map<String, dynamic>>() ??
              const [];
          for (final entry in inventoryEntries) {
            final name = (entry['stockItemName'] ?? '').toString();
            final bucket = totals.putIfAbsent(
              name,
              () => {'qty': 0, 'amount': 0},
            );
            bucket['qty'] = bucket['qty']! + parseMoneyField(entry['quantity']);
            bucket['amount'] =
                bucket['amount']! + parseMoneyField(entry['amount']);
          }
        }
        return [
          for (final entry in totals.entries)
            {
              'item': entry.key,
              'qty': entry.value['qty'],
              'amount': entry.value['amount'],
            },
        ];

      case 'Bills':
        return [
          for (final voucher in vouchers)
            {
              'vchno': voucher['number'] ?? '',
              'Partyledger': args.ledger,
              'vchdate': voucher['date'] ?? '',
              'amount': _voucherAmount(voucher),
            },
        ];

      case 'Voucher Type':
        final totals = <String, Map<String, num>>{};
        for (final voucher in vouchers) {
          final name = (voucher['voucherTypeName'] ?? '').toString();
          final bucket = totals.putIfAbsent(
            name,
            () => {'count': 0, 'amount': 0.0},
          );
          bucket['count'] = bucket['count']! + 1;
          bucket['amount'] = bucket['amount']! + _voucherAmount(voucher);
        }
        return [
          for (final entry in totals.entries)
            {
              'vchname': entry.key,
              'qty': entry.value['count'].toString(),
              'amount': entry.value['amount'],
            },
        ];

      case 'Cost Center':
        final totals = <String, Map<String, num>>{};
        for (final voucher in vouchers) {
          final costCentreEntries =
              (voucher['costCentreAllocations'] as List?)
                  ?.cast<Map<String, dynamic>>() ??
              const [];
          if (costCentreEntries.isEmpty) {
            final bucket = totals.putIfAbsent(
              'null',
              () => {'count': 0, 'amount': 0.0},
            );
            bucket['count'] = bucket['count']! + 1;
            bucket['amount'] = bucket['amount']! + _voucherAmount(voucher);
          } else {
            for (final entry in costCentreEntries) {
              final name = (entry['costCentreName'] ?? 'null').toString();
              final bucket = totals.putIfAbsent(
                name,
                () => {'count': 0, 'amount': 0.0},
              );
              bucket['count'] = bucket['count']! + 1;
              bucket['amount'] =
                  bucket['amount']! + parseMoneyField(entry['amount']);
            }
          }
        }
        return [
          for (final entry in totals.entries)
            {
              'costcentre': entry.key,
              'qty': entry.value['count'].toString(),
              'amount': entry.value['amount'],
            },
        ];

      default:
        return const [];
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
