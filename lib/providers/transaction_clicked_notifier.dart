import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../TransactionClicked.dart';
import '../api/api_exception.dart';
import 'repository_providers.dart';

class TransactionClickedState {
  final bool isLoading;
  final bool isVisibleLedgerEntry;
  final bool isVisibleBills;
  final bool isVisibleInventoryEntry;
  final bool isVisibleCostCenter;
  final bool isInventoryExpanded;
  final bool isCostCenterExpanded;
  final int visibleInventoryCount;
  final int visibleCostCenterCount;
  final List<LedgerEntries> ledgerEntriesList;
  final List<Bills> billsList;
  final List<InventoryEntries> inventoryEntriesList;
  final List<CostCenter> costCenterList;
  final String company;
  final String? errorMessage;

  const TransactionClickedState({
    this.isLoading = false,
    this.isVisibleLedgerEntry = false,
    this.isVisibleBills = false,
    this.isVisibleInventoryEntry = false,
    this.isVisibleCostCenter = false,
    this.isInventoryExpanded = false,
    this.isCostCenterExpanded = false,
    this.visibleInventoryCount = 3,
    this.visibleCostCenterCount = 3,
    this.ledgerEntriesList = const [],
    this.billsList = const [],
    this.inventoryEntriesList = const [],
    this.costCenterList = const [],
    this.company = '',
    this.errorMessage,
  });

  TransactionClickedState copyWith({
    bool? isLoading,
    bool? isVisibleLedgerEntry,
    bool? isVisibleBills,
    bool? isVisibleInventoryEntry,
    bool? isVisibleCostCenter,
    bool? isInventoryExpanded,
    bool? isCostCenterExpanded,
    int? visibleInventoryCount,
    int? visibleCostCenterCount,
    List<LedgerEntries>? ledgerEntriesList,
    List<Bills>? billsList,
    List<InventoryEntries>? inventoryEntriesList,
    List<CostCenter>? costCenterList,
    String? company,
    String? errorMessage,
    bool clearError = false,
  }) {
    return TransactionClickedState(
      isLoading: isLoading ?? this.isLoading,
      isVisibleLedgerEntry: isVisibleLedgerEntry ?? this.isVisibleLedgerEntry,
      isVisibleBills: isVisibleBills ?? this.isVisibleBills,
      isVisibleInventoryEntry:
          isVisibleInventoryEntry ?? this.isVisibleInventoryEntry,
      isVisibleCostCenter: isVisibleCostCenter ?? this.isVisibleCostCenter,
      isInventoryExpanded: isInventoryExpanded ?? this.isInventoryExpanded,
      isCostCenterExpanded: isCostCenterExpanded ?? this.isCostCenterExpanded,
      visibleInventoryCount:
          visibleInventoryCount ?? this.visibleInventoryCount,
      visibleCostCenterCount:
          visibleCostCenterCount ?? this.visibleCostCenterCount,
      ledgerEntriesList: ledgerEntriesList ?? this.ledgerEntriesList,
      billsList: billsList ?? this.billsList,
      inventoryEntriesList: inventoryEntriesList ?? this.inventoryEntriesList,
      costCenterList: costCenterList ?? this.costCenterList,
      company: company ?? this.company,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    );
  }
}

class TransactionClickedNotifier extends StateNotifier<TransactionClickedState> {
  final Ref _ref;

  TransactionClickedNotifier(this._ref)
      : super(const TransactionClickedState());

  void clearError() => state = state.copyWith(clearError: true);

  Future<void> init(String masterid) async {
    final prefs = await SharedPreferences.getInstance();
    state = state.copyWith(company: prefs.getString('company_name') ?? '');
    await fetchData(masterid);
  }

  void toggleInventoryExpanded() {
    if (state.isInventoryExpanded) {
      state = state.copyWith(
        isInventoryExpanded: false,
        visibleInventoryCount: 3,
      );
    } else {
      state = state.copyWith(
        isInventoryExpanded: true,
        visibleInventoryCount: state.inventoryEntriesList.length,
      );
    }
  }

  void toggleCostCenterExpanded() {
    if (state.isCostCenterExpanded) {
      state = state.copyWith(
        isCostCenterExpanded: false,
        visibleCostCenterCount: 3,
      );
    } else {
      state = state.copyWith(
        isCostCenterExpanded: true,
        visibleCostCenterCount: state.costCenterList.length,
      );
    }
  }

  /// A single `GET vouchers/:masterId` call returns ledger/inventory/
  /// cost-centre entries together (see `VoucherRepository`) - bill
  /// allocations included, read off each ledger entry's own
  /// `billAllocations` array rather than a separate bills collection call.
  Future<void> fetchData(String masterid) async {
    state = state.copyWith(
      isVisibleLedgerEntry: false,
      isVisibleBills: false,
      isVisibleInventoryEntry: false,
      isVisibleCostCenter: false,
      isLoading: true,
    );

    try {
      final voucherId = int.tryParse(masterid);
      if (voucherId == null) {
        throw Exception('Missing voucher masterId');
      }
      final voucher =
          await _ref.read(voucherRepositoryProvider).getByMasterId(voucherId);

      final ledgerRows =
          (voucher['ledgerEntries'] as List?)?.cast<Map<String, dynamic>>() ??
              const [];
      final inventoryRows =
          (voucher['inventoryEntries'] as List?)
                  ?.cast<Map<String, dynamic>>() ??
              const [];
      final costCentreRows =
          (voucher['costCentreAllocations'] as List?)
                  ?.cast<Map<String, dynamic>>() ??
              const [];

      final ledgerEntriesList = ledgerRows
          .map(
            (row) => LedgerEntries(
              ledger: (row['ledgerName'] ?? '').toString(),
              amount: (row['amount'] ?? '0').toString(),
            ),
          )
          .toList();

      final inventoryEntriesList = inventoryRows
          .map(
            (row) => InventoryEntries(
              item: (row['stockItemName'] ?? '').toString(),
              qty: (row['quantity'] ?? '0').toString(),
              rate: (row['rate'] ?? '0').toString(),
              discount: (row['discountPercentage'] ?? '0').toString(),
              amount: (row['amount'] ?? '0').toString(),
              godown: (row['godownName'] ?? 'null').toString(),
            ),
          )
          .toList();

      final costCenterList = costCentreRows
          .map(
            (row) => CostCenter(
              costcentre: (row['costCentreName'] ?? '').toString(),
              amount: (row['amount'] ?? '0').toString(),
            ),
          )
          .toList();

      // Bill allocations live as a JSON array directly on each ledger
      // entry (`voucherLedgerEntryRowSchema.billAllocations`), not as a
      // separate endpoint - `{billId, billName, billType, amount}` per
      // entry. No `dueDate`/`billDate` field exists on this blob (that's
      // only tracked on the standalone `Bill` master, not on the voucher's
      // own bill-allocation record), so those show as "Not Available"
      // rather than being fabricated.
      final billsList = [
        for (final row in ledgerRows)
          for (final bill
              in (row['billAllocations'] as List?)
                      ?.cast<Map<String, dynamic>>() ??
                  const [])
            Bills(
              billno: (bill['billName'] ?? '').toString(),
              amount: (bill['amount'] ?? '0').toString(),
              billtype: (bill['billType'] ?? '').toString(),
              duedate: 'null',
              billdate: 'null',
              ledger: (row['ledgerName'] ?? '').toString(),
            ),
      ];

      state = state.copyWith(
        ledgerEntriesList: ledgerEntriesList,
        billsList: billsList,
        inventoryEntriesList: inventoryEntriesList,
        costCenterList: costCenterList,
        isVisibleLedgerEntry: ledgerEntriesList.isNotEmpty,
        isVisibleBills: billsList.isNotEmpty,
        isVisibleInventoryEntry: inventoryEntriesList.isNotEmpty,
        isVisibleCostCenter: costCenterList.isNotEmpty,
        isLoading: false,
      );
    } on ApiException catch (e) {
      state = state.copyWith(
        isVisibleLedgerEntry: false,
        isVisibleBills: false,
        isVisibleInventoryEntry: false,
        isVisibleCostCenter: false,
        isLoading: false,
        errorMessage: e.message,
      );
    } catch (e) {
      state = state.copyWith(
        isVisibleLedgerEntry: false,
        isVisibleBills: false,
        isVisibleInventoryEntry: false,
        isVisibleCostCenter: false,
        isLoading: false,
        errorMessage: 'Could not reach the server. Please try again.',
      );
    }
  }
}

final transactionClickedNotifierProvider = StateNotifierProvider.autoDispose
    .family<TransactionClickedNotifier, TransactionClickedState, String>(
  (ref, masterid) {
    final notifier = TransactionClickedNotifier(ref);
    notifier.init(masterid);
    return notifier;
  },
);
