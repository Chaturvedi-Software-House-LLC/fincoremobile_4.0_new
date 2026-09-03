import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../van_allocation_data.dart';

/// Riverpod migration of `ModifyVanAllocation.dart`'s
/// `_ModifyVanAllocationScreenState`. Backend fetch/save
/// (`VanAllocationData`, already tally-api-backed) is ported verbatim;
/// only the form state container moves into a [StateNotifier]. Closest
/// sibling: `van_allocation_notifier.dart` (same fields, minus the
/// company-user picker since the user is fixed here).
class ModifyVanAllocationArgs {
  final String companyUserId;
  final int? godownMasterId;
  final Set<int> voucherTypeMasterIds;
  final int? salesLedgerMasterId;
  final int? cashLedgerMasterId;

  const ModifyVanAllocationArgs({
    required this.companyUserId,
    this.godownMasterId,
    this.voucherTypeMasterIds = const {},
    this.salesLedgerMasterId,
    this.cashLedgerMasterId,
  });

  @override
  bool operator ==(Object other) =>
      other is ModifyVanAllocationArgs && other.companyUserId == companyUserId;

  @override
  int get hashCode => companyUserId.hashCode;
}

class ModifyVanAllocationState {
  final bool isLoading;
  final bool isSaving;
  final List<MasterOption> locations;
  final List<MasterOption> deliveryNoteVchTypes;
  final List<MasterOption> salesVchTypes;
  final List<MasterOption> receiptVchTypes;
  final List<MasterOption> salesLedgers;
  final List<MasterOption> cashLedgers;
  final MasterOption? selectedLocation;
  final MasterOption? selectedDeliveryNoteVchType;
  final MasterOption? selectedSalesVchType;
  final MasterOption? selectedReceiptVchType;
  final MasterOption? selectedSalesLedger;
  final MasterOption? selectedCashLedger;
  // Kept as a local-only, unsaved UI control - see addVanAllocations.dart's
  // doc-comment; master-restrictions has no "is_bulk" field.
  final bool isBulkAllocation;

  const ModifyVanAllocationState({
    this.isLoading = true,
    this.isSaving = false,
    this.locations = const [],
    this.deliveryNoteVchTypes = const [],
    this.salesVchTypes = const [],
    this.receiptVchTypes = const [],
    this.salesLedgers = const [],
    this.cashLedgers = const [],
    this.selectedLocation,
    this.selectedDeliveryNoteVchType,
    this.selectedSalesVchType,
    this.selectedReceiptVchType,
    this.selectedSalesLedger,
    this.selectedCashLedger,
    this.isBulkAllocation = false,
  });

  bool get isFormValid =>
      selectedLocation != null &&
      selectedDeliveryNoteVchType != null &&
      selectedSalesVchType != null &&
      selectedReceiptVchType != null;
}

class ModifyVanAllocationNotifier
    extends StateNotifier<ModifyVanAllocationState> {
  final ModifyVanAllocationArgs args;

  ModifyVanAllocationNotifier(this.args)
      : super(const ModifyVanAllocationState()) {
    _init();
  }

  MasterOption? _findByMasterId(List<MasterOption> options, int masterId) {
    for (final o in options) {
      if (o.masterId == masterId) return o;
    }
    return null;
  }

  MasterOption? _findByMasterIds(List<MasterOption> options, Set<int> ids) {
    for (final o in options) {
      if (ids.contains(o.masterId)) return o;
    }
    return null;
  }

  Future<void> _init() async {
    try {
      final results = await Future.wait([
        VanAllocationData.listAllGodowns(),
        VanAllocationData.listVoucherTypesByReservedName('DELIVERY_NOTE'),
        VanAllocationData.listVoucherTypesByReservedName('SALES'),
        VanAllocationData.listVoucherTypesByReservedName('RECEIPT'),
        VanAllocationData.listSalesLedgers(),
        VanAllocationData.listCashLedgers(),
      ]);
      final locations = results[0];
      final deliveryNoteVchTypes = results[1];
      final salesVchTypes = results[2];
      final receiptVchTypes = results[3];
      final salesLedgers = results[4];
      final cashLedgers = results[5];

      final godownId = args.godownMasterId;
      final selectedLocation =
          godownId == null ? null : _findByMasterId(locations, godownId);

      final vchIds = args.voucherTypeMasterIds;
      final salesLedgerId = args.salesLedgerMasterId;
      final cashLedgerId = args.cashLedgerMasterId;
      state = ModifyVanAllocationState(
        isLoading: false,
        locations: locations,
        deliveryNoteVchTypes: deliveryNoteVchTypes,
        salesVchTypes: salesVchTypes,
        receiptVchTypes: receiptVchTypes,
        salesLedgers: salesLedgers,
        cashLedgers: cashLedgers,
        selectedLocation: selectedLocation,
        selectedDeliveryNoteVchType: _findByMasterIds(
          deliveryNoteVchTypes,
          vchIds,
        ),
        selectedSalesVchType: _findByMasterIds(salesVchTypes, vchIds),
        selectedReceiptVchType: _findByMasterIds(receiptVchTypes, vchIds),
        selectedSalesLedger: salesLedgerId == null
            ? null
            : _findByMasterId(salesLedgers, salesLedgerId),
        selectedCashLedger: cashLedgerId == null
            ? null
            : _findByMasterId(cashLedgers, cashLedgerId),
      );
    } catch (e) {
      state = ModifyVanAllocationState(isLoading: false);
    }
  }

  void selectLocation(MasterOption? value) {
    state = _copy(selectedLocation: value, setLocation: true);
  }

  void selectDeliveryNoteVchType(MasterOption? value) {
    state = _copy(selectedDeliveryNoteVchType: value, setDeliveryNote: true);
  }

  void selectSalesVchType(MasterOption? value) {
    state = _copy(selectedSalesVchType: value, setSalesVch: true);
  }

  void selectReceiptVchType(MasterOption? value) {
    state = _copy(selectedReceiptVchType: value, setReceiptVch: true);
  }

  void selectSalesLedger(MasterOption? value) {
    state = _copy(selectedSalesLedger: value, setSalesLedger: true);
  }

  void selectCashLedger(MasterOption? value) {
    state = _copy(selectedCashLedger: value, setCashLedger: true);
  }

  void setBulkAllocation(bool value) {
    state = _copy(isBulkAllocation: value);
  }

  // Manual copy (not a plain `copyWith`) so a field can be explicitly reset
  // to null - each `set*` flag says whether its paired `selected*` argument
  // should replace the current value (even with null) or be ignored.
  ModifyVanAllocationState _copy({
    bool? isSaving,
    MasterOption? selectedLocation,
    bool setLocation = false,
    MasterOption? selectedDeliveryNoteVchType,
    bool setDeliveryNote = false,
    MasterOption? selectedSalesVchType,
    bool setSalesVch = false,
    MasterOption? selectedReceiptVchType,
    bool setReceiptVch = false,
    MasterOption? selectedSalesLedger,
    bool setSalesLedger = false,
    MasterOption? selectedCashLedger,
    bool setCashLedger = false,
    bool? isBulkAllocation,
  }) {
    return ModifyVanAllocationState(
      isLoading: state.isLoading,
      isSaving: isSaving ?? state.isSaving,
      locations: state.locations,
      deliveryNoteVchTypes: state.deliveryNoteVchTypes,
      salesVchTypes: state.salesVchTypes,
      receiptVchTypes: state.receiptVchTypes,
      salesLedgers: state.salesLedgers,
      cashLedgers: state.cashLedgers,
      selectedLocation:
          setLocation ? selectedLocation : state.selectedLocation,
      selectedDeliveryNoteVchType: setDeliveryNote
          ? selectedDeliveryNoteVchType
          : state.selectedDeliveryNoteVchType,
      selectedSalesVchType:
          setSalesVch ? selectedSalesVchType : state.selectedSalesVchType,
      selectedReceiptVchType: setReceiptVch
          ? selectedReceiptVchType
          : state.selectedReceiptVchType,
      selectedSalesLedger:
          setSalesLedger ? selectedSalesLedger : state.selectedSalesLedger,
      selectedCashLedger:
          setCashLedger ? selectedCashLedger : state.selectedCashLedger,
      isBulkAllocation: isBulkAllocation ?? state.isBulkAllocation,
    );
  }

  /// Returns null on success, or a user-facing error message.
  Future<String?> updateAllocation() async {
    if (!state.isFormValid) return null;

    state = _copy(isSaving: true);
    try {
      final alreadyTaken = await VanAllocationData.isGodownAlreadyAllocated(
        state.selectedLocation!.masterId,
        excludingCompanyUserId: args.companyUserId,
      );
      if (alreadyTaken) {
        return 'This vehicle/location is already allocated to another user';
      }

      await VanAllocationData.saveAllocation(
        companyUserId: args.companyUserId,
        godownMasterId: state.selectedLocation!.masterId,
        voucherTypeMasterIds: [
          state.selectedDeliveryNoteVchType!.masterId,
          state.selectedSalesVchType!.masterId,
          state.selectedReceiptVchType!.masterId,
        ],
        salesLedgerMasterId: state.selectedSalesLedger?.masterId,
        cashLedgerMasterId: state.selectedCashLedger?.masterId,
      );
      return null;
    } catch (e) {
      return 'Error: $e';
    } finally {
      state = _copy(isSaving: false);
    }
  }
}

final modifyVanAllocationNotifierProvider = StateNotifierProvider.autoDispose
    .family<ModifyVanAllocationNotifier, ModifyVanAllocationState,
        ModifyVanAllocationArgs>(
  (ref, args) => ModifyVanAllocationNotifier(args),
);
