import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../van_allocation_data.dart';

/// Riverpod migration of `viewVanAllocations.dart`'s
/// `_ViewVanAllocationScreenState`. Backend fetch (`VanAllocationData`,
/// already tally-api-backed) is ported verbatim; only the state container
/// and search/expand/delete actions move into a [StateNotifier].
class ViewVanAllocationState {
  final bool isLoading;
  final List<Map<String, dynamic>> allocations;
  final List<Map<String, dynamic>> filteredAllocations;
  final Set<int> expandedCards;

  const ViewVanAllocationState({
    this.isLoading = true,
    this.allocations = const [],
    this.filteredAllocations = const [],
    this.expandedCards = const {},
  });

  ViewVanAllocationState copyWith({
    bool? isLoading,
    List<Map<String, dynamic>>? allocations,
    List<Map<String, dynamic>>? filteredAllocations,
    Set<int>? expandedCards,
  }) {
    return ViewVanAllocationState(
      isLoading: isLoading ?? this.isLoading,
      allocations: allocations ?? this.allocations,
      filteredAllocations: filteredAllocations ?? this.filteredAllocations,
      expandedCards: expandedCards ?? this.expandedCards,
    );
  }
}

class ViewVanAllocationNotifier extends StateNotifier<ViewVanAllocationState> {
  ViewVanAllocationNotifier() : super(const ViewVanAllocationState()) {
    fetchAllocations();
  }

  Future<void> fetchAllocations() async {
    state = state.copyWith(isLoading: true);
    try {
      final results = await Future.wait([
        VanAllocationData.listCompanyUsers(),
        VanAllocationData.listAllGodowns(),
        VanAllocationData.listVoucherTypesByReservedName('DELIVERY_NOTE'),
        VanAllocationData.listVoucherTypesByReservedName('SALES'),
        VanAllocationData.listVoucherTypesByReservedName('RECEIPT'),
        VanAllocationData.listSalesLedgers(),
        VanAllocationData.listCashLedgers(),
      ]);
      final users = results[0] as List<CompanyUserOption>;
      final godowns = results[1] as List<MasterOption>;
      final godownNameById = {for (final g in godowns) g.masterId: g.name};
      final vchNameById = <int, String>{
        for (final v in results[2] as List<MasterOption>) v.masterId: v.name,
        for (final v in results[3] as List<MasterOption>) v.masterId: v.name,
        for (final v in results[4] as List<MasterOption>) v.masterId: v.name,
      };
      final deliveryIds =
          (results[2] as List<MasterOption>).map((v) => v.masterId).toSet();
      final salesIds =
          (results[3] as List<MasterOption>).map((v) => v.masterId).toSet();
      final receiptIds =
          (results[4] as List<MasterOption>).map((v) => v.masterId).toSet();
      final salesLedgerNameById = {
        for (final l in results[5] as List<MasterOption>) l.masterId: l.name,
      };
      final cashLedgerNameById = {
        for (final l in results[6] as List<MasterOption>) l.masterId: l.name,
      };

      final built = <Map<String, dynamic>>[];
      for (final user in users) {
        final godownId = await VanAllocationData.currentGodownMasterId(
          user.id,
        );
        if (godownId == null) continue; // unrestricted/none -> not "allocated"

        final vchIds = await VanAllocationData.currentVoucherTypeMasterIds(
          user.id,
        );
        String? nameFor(Set<int> group) {
          for (final id in vchIds) {
            if (group.contains(id)) return vchNameById[id];
          }
          return null;
        }

        final ledgerSelection = await VanAllocationData.currentLedgerSelection(
          user.id,
        );

        built.add({
          'companyUserId': user.id,
          'name': user.name,
          'user_name': user.username,
          'godownMasterId': godownId,
          'godown_name': godownNameById[godownId] ?? '',
          'voucherTypeMasterIds': vchIds,
          'voucher_type_name': nameFor(deliveryIds) ?? '',
          'sales_voucher_type': nameFor(salesIds) ?? '',
          'receipt_voucher_type': nameFor(receiptIds) ?? '',
          'salesLedgerMasterId': ledgerSelection.salesLedgerMasterId,
          'cashLedgerMasterId': ledgerSelection.cashLedgerMasterId,
          'sales_ledger_name':
              salesLedgerNameById[ledgerSelection.salesLedgerMasterId] ?? '',
          'cash_ledger_name':
              cashLedgerNameById[ledgerSelection.cashLedgerMasterId] ?? '',
        });
      }

      state = state.copyWith(
        isLoading: false,
        allocations: built,
        filteredAllocations: built,
      );
    } catch (e) {
      state = state.copyWith(isLoading: false);
    }
  }

  void filter(String query) {
    if (query.isEmpty) {
      state = state.copyWith(filteredAllocations: state.allocations);
    } else {
      final lower = query.toLowerCase();
      state = state.copyWith(
        filteredAllocations: state.allocations
            .where((a) => a.toString().toLowerCase().contains(lower))
            .toList(),
      );
    }
  }

  void toggleExpanded(int index) {
    final next = Set<int>.from(state.expandedCards);
    if (next.contains(index)) {
      next.remove(index);
    } else {
      next.add(index);
    }
    state = state.copyWith(expandedCards: next);
  }

  Future<void> deleteAllocation(Map<String, dynamic> allocation) async {
    await VanAllocationData.clearAllocation(
      allocation['companyUserId'] as String,
    );
    await fetchAllocations();
  }
}

final viewVanAllocationNotifierProvider = StateNotifierProvider.autoDispose<
    ViewVanAllocationNotifier, ViewVanAllocationState>(
  (ref) => ViewVanAllocationNotifier(),
);
