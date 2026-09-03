import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../van_allocation_data.dart';

/// Riverpod migration of `addVanAllocations.dart`'s
/// `_VanAllocationScreenState`. Backend fetch/save (`VanAllocationData`,
/// already tally-api-backed) is ported verbatim; only the form state
/// container moves into a [StateNotifier].
class VanAllocationState {
  final bool isLoading;
  final bool isSaving;
  final List<CompanyUserOption> users;
  final List<MasterOption> locations;
  final List<MasterOption> deliveryNoteVchTypes;
  final List<MasterOption> salesVchTypes;
  final List<MasterOption> receiptVchTypes;
  final List<MasterOption> salesLedgers;
  final List<MasterOption> cashLedgers;
  final CompanyUserOption? selectedUser;
  final MasterOption? selectedLocation;
  final MasterOption? selectedDeliveryNoteVchType;
  final MasterOption? selectedSalesVchType;
  final MasterOption? selectedReceiptVchType;
  final MasterOption? selectedSalesLedger;
  final MasterOption? selectedCashLedger;
  // Kept as a local-only, unsaved UI control: master-restrictions has no
  // backend field for "is_bulk" (that concept - is_bulk/meter-reading - is
  // out of scope for this data-layer migration and still driven by the
  // legacy "spectra_allocations" SharedPreferences cache read at login,
  // untouched by this screen). Toggling it here does nothing.
  final bool isBulkAllocation;
  final int formResetKey;

  const VanAllocationState({
    this.isLoading = true,
    this.isSaving = false,
    this.users = const [],
    this.locations = const [],
    this.deliveryNoteVchTypes = const [],
    this.salesVchTypes = const [],
    this.receiptVchTypes = const [],
    this.salesLedgers = const [],
    this.cashLedgers = const [],
    this.selectedUser,
    this.selectedLocation,
    this.selectedDeliveryNoteVchType,
    this.selectedSalesVchType,
    this.selectedReceiptVchType,
    this.selectedSalesLedger,
    this.selectedCashLedger,
    this.isBulkAllocation = false,
    this.formResetKey = 0,
  });

  // Sales/Cash ledger are optional (legacy fields, but not every deployment
  // needs a van-sales default set) - not part of form validity.
  bool get isFormValid =>
      selectedUser != null &&
      selectedLocation != null &&
      selectedDeliveryNoteVchType != null &&
      selectedSalesVchType != null &&
      selectedReceiptVchType != null;

  VanAllocationState copyWith({
    bool? isLoading,
    bool? isSaving,
    List<CompanyUserOption>? users,
    List<MasterOption>? locations,
    List<MasterOption>? deliveryNoteVchTypes,
    List<MasterOption>? salesVchTypes,
    List<MasterOption>? receiptVchTypes,
    List<MasterOption>? salesLedgers,
    List<MasterOption>? cashLedgers,
    CompanyUserOption? selectedUser,
    MasterOption? selectedLocation,
    MasterOption? selectedDeliveryNoteVchType,
    MasterOption? selectedSalesVchType,
    MasterOption? selectedReceiptVchType,
    MasterOption? selectedSalesLedger,
    MasterOption? selectedCashLedger,
    bool clearSelections = false,
    bool? isBulkAllocation,
    int? formResetKey,
  }) {
    return VanAllocationState(
      isLoading: isLoading ?? this.isLoading,
      isSaving: isSaving ?? this.isSaving,
      users: users ?? this.users,
      locations: locations ?? this.locations,
      deliveryNoteVchTypes: deliveryNoteVchTypes ?? this.deliveryNoteVchTypes,
      salesVchTypes: salesVchTypes ?? this.salesVchTypes,
      receiptVchTypes: receiptVchTypes ?? this.receiptVchTypes,
      salesLedgers: salesLedgers ?? this.salesLedgers,
      cashLedgers: cashLedgers ?? this.cashLedgers,
      selectedUser:
          clearSelections ? null : (selectedUser ?? this.selectedUser),
      selectedLocation: clearSelections
          ? null
          : (selectedLocation ?? this.selectedLocation),
      selectedDeliveryNoteVchType: clearSelections
          ? null
          : (selectedDeliveryNoteVchType ?? this.selectedDeliveryNoteVchType),
      selectedSalesVchType: clearSelections
          ? null
          : (selectedSalesVchType ?? this.selectedSalesVchType),
      selectedReceiptVchType: clearSelections
          ? null
          : (selectedReceiptVchType ?? this.selectedReceiptVchType),
      selectedSalesLedger: clearSelections
          ? null
          : (selectedSalesLedger ?? this.selectedSalesLedger),
      selectedCashLedger: clearSelections
          ? null
          : (selectedCashLedger ?? this.selectedCashLedger),
      isBulkAllocation: clearSelections
          ? false
          : (isBulkAllocation ?? this.isBulkAllocation),
      formResetKey: formResetKey ?? this.formResetKey,
    );
  }
}

class VanAllocationNotifier extends StateNotifier<VanAllocationState> {
  VanAllocationNotifier() : super(const VanAllocationState()) {
    fetchInitialData();
  }

  Future<void> fetchInitialData() async {
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
      final allUsers = results[0] as List<CompanyUserOption>;
      final locations = results[1] as List<MasterOption>;
      final deliveryNoteVchTypes = results[2] as List<MasterOption>;
      final salesVchTypes = results[3] as List<MasterOption>;
      final receiptVchTypes = results[4] as List<MasterOption>;
      final salesLedgers = results[5] as List<MasterOption>;
      final cashLedgers = results[6] as List<MasterOption>;

      // Only offer company-users who don't already have a vehicle (GODOWN
      // restriction) assigned - mirrors the legacy screen's "already
      // allocated" exclusion from the user picker.
      final unallocated = <CompanyUserOption>[];
      for (final user in allUsers) {
        final existing = await VanAllocationData.currentGodownMasterId(
          user.id,
        );
        if (existing == null) unallocated.add(user);
      }

      state = state.copyWith(
        isLoading: false,
        users: unallocated,
        locations: locations,
        deliveryNoteVchTypes: deliveryNoteVchTypes,
        salesVchTypes: salesVchTypes,
        receiptVchTypes: receiptVchTypes,
        salesLedgers: salesLedgers,
        cashLedgers: cashLedgers,
        selectedUser: unallocated.isEmpty ? null : state.selectedUser,
        clearSelections: unallocated.isEmpty,
      );
    } catch (e) {
      state = state.copyWith(isLoading: false);
    }
  }

  void selectUser(CompanyUserOption? value) {
    state = VanAllocationState(
      isLoading: state.isLoading,
      isSaving: state.isSaving,
      users: state.users,
      locations: state.locations,
      deliveryNoteVchTypes: state.deliveryNoteVchTypes,
      salesVchTypes: state.salesVchTypes,
      receiptVchTypes: state.receiptVchTypes,
      salesLedgers: state.salesLedgers,
      cashLedgers: state.cashLedgers,
      selectedUser: value,
      selectedLocation: state.selectedLocation,
      selectedDeliveryNoteVchType: state.selectedDeliveryNoteVchType,
      selectedSalesVchType: state.selectedSalesVchType,
      selectedReceiptVchType: state.selectedReceiptVchType,
      selectedSalesLedger: state.selectedSalesLedger,
      selectedCashLedger: state.selectedCashLedger,
      isBulkAllocation: state.isBulkAllocation,
      formResetKey: state.formResetKey,
    );
  }

  void selectLocation(MasterOption? value) {
    state = VanAllocationState(
      isLoading: state.isLoading,
      isSaving: state.isSaving,
      users: state.users,
      locations: state.locations,
      deliveryNoteVchTypes: state.deliveryNoteVchTypes,
      salesVchTypes: state.salesVchTypes,
      receiptVchTypes: state.receiptVchTypes,
      salesLedgers: state.salesLedgers,
      cashLedgers: state.cashLedgers,
      selectedUser: state.selectedUser,
      selectedLocation: value,
      selectedDeliveryNoteVchType: state.selectedDeliveryNoteVchType,
      selectedSalesVchType: state.selectedSalesVchType,
      selectedReceiptVchType: state.selectedReceiptVchType,
      selectedSalesLedger: state.selectedSalesLedger,
      selectedCashLedger: state.selectedCashLedger,
      isBulkAllocation: state.isBulkAllocation,
      formResetKey: state.formResetKey,
    );
  }

  void selectDeliveryNoteVchType(MasterOption? value) {
    state = VanAllocationState(
      isLoading: state.isLoading,
      isSaving: state.isSaving,
      users: state.users,
      locations: state.locations,
      deliveryNoteVchTypes: state.deliveryNoteVchTypes,
      salesVchTypes: state.salesVchTypes,
      receiptVchTypes: state.receiptVchTypes,
      salesLedgers: state.salesLedgers,
      cashLedgers: state.cashLedgers,
      selectedUser: state.selectedUser,
      selectedLocation: state.selectedLocation,
      selectedDeliveryNoteVchType: value,
      selectedSalesVchType: state.selectedSalesVchType,
      selectedReceiptVchType: state.selectedReceiptVchType,
      selectedSalesLedger: state.selectedSalesLedger,
      selectedCashLedger: state.selectedCashLedger,
      isBulkAllocation: state.isBulkAllocation,
      formResetKey: state.formResetKey,
    );
  }

  void selectSalesVchType(MasterOption? value) {
    state = VanAllocationState(
      isLoading: state.isLoading,
      isSaving: state.isSaving,
      users: state.users,
      locations: state.locations,
      deliveryNoteVchTypes: state.deliveryNoteVchTypes,
      salesVchTypes: state.salesVchTypes,
      receiptVchTypes: state.receiptVchTypes,
      salesLedgers: state.salesLedgers,
      cashLedgers: state.cashLedgers,
      selectedUser: state.selectedUser,
      selectedLocation: state.selectedLocation,
      selectedDeliveryNoteVchType: state.selectedDeliveryNoteVchType,
      selectedSalesVchType: value,
      selectedReceiptVchType: state.selectedReceiptVchType,
      selectedSalesLedger: state.selectedSalesLedger,
      selectedCashLedger: state.selectedCashLedger,
      isBulkAllocation: state.isBulkAllocation,
      formResetKey: state.formResetKey,
    );
  }

  void selectReceiptVchType(MasterOption? value) {
    state = VanAllocationState(
      isLoading: state.isLoading,
      isSaving: state.isSaving,
      users: state.users,
      locations: state.locations,
      deliveryNoteVchTypes: state.deliveryNoteVchTypes,
      salesVchTypes: state.salesVchTypes,
      receiptVchTypes: state.receiptVchTypes,
      salesLedgers: state.salesLedgers,
      cashLedgers: state.cashLedgers,
      selectedUser: state.selectedUser,
      selectedLocation: state.selectedLocation,
      selectedDeliveryNoteVchType: state.selectedDeliveryNoteVchType,
      selectedSalesVchType: state.selectedSalesVchType,
      selectedReceiptVchType: value,
      selectedSalesLedger: state.selectedSalesLedger,
      selectedCashLedger: state.selectedCashLedger,
      isBulkAllocation: state.isBulkAllocation,
      formResetKey: state.formResetKey,
    );
  }

  void selectSalesLedger(MasterOption? value) {
    state = VanAllocationState(
      isLoading: state.isLoading,
      isSaving: state.isSaving,
      users: state.users,
      locations: state.locations,
      deliveryNoteVchTypes: state.deliveryNoteVchTypes,
      salesVchTypes: state.salesVchTypes,
      receiptVchTypes: state.receiptVchTypes,
      salesLedgers: state.salesLedgers,
      cashLedgers: state.cashLedgers,
      selectedUser: state.selectedUser,
      selectedLocation: state.selectedLocation,
      selectedDeliveryNoteVchType: state.selectedDeliveryNoteVchType,
      selectedSalesVchType: state.selectedSalesVchType,
      selectedReceiptVchType: state.selectedReceiptVchType,
      selectedSalesLedger: value,
      selectedCashLedger: state.selectedCashLedger,
      isBulkAllocation: state.isBulkAllocation,
      formResetKey: state.formResetKey,
    );
  }

  void selectCashLedger(MasterOption? value) {
    state = VanAllocationState(
      isLoading: state.isLoading,
      isSaving: state.isSaving,
      users: state.users,
      locations: state.locations,
      deliveryNoteVchTypes: state.deliveryNoteVchTypes,
      salesVchTypes: state.salesVchTypes,
      receiptVchTypes: state.receiptVchTypes,
      salesLedgers: state.salesLedgers,
      cashLedgers: state.cashLedgers,
      selectedUser: state.selectedUser,
      selectedLocation: state.selectedLocation,
      selectedDeliveryNoteVchType: state.selectedDeliveryNoteVchType,
      selectedSalesVchType: state.selectedSalesVchType,
      selectedReceiptVchType: state.selectedReceiptVchType,
      selectedSalesLedger: state.selectedSalesLedger,
      selectedCashLedger: value,
      isBulkAllocation: state.isBulkAllocation,
      formResetKey: state.formResetKey,
    );
  }

  void setBulkAllocation(bool value) {
    state = state.copyWith(isBulkAllocation: value);
  }

  void resetForm() {
    state = state.copyWith(
      clearSelections: true,
      formResetKey: state.formResetKey + 1,
    );
  }

  /// Returns null on success, or a user-facing error message.
  Future<String?> saveAllocation() async {
    if (!state.isFormValid) {
      return 'Please fill all fields';
    }

    state = state.copyWith(isSaving: true);
    try {
      final alreadyTaken = await VanAllocationData.isGodownAlreadyAllocated(
        state.selectedLocation!.masterId,
      );
      if (alreadyTaken) {
        return 'This vehicle/location is already allocated to another user';
      }

      await VanAllocationData.saveAllocation(
        companyUserId: state.selectedUser!.id,
        godownMasterId: state.selectedLocation!.masterId,
        voucherTypeMasterIds: [
          state.selectedDeliveryNoteVchType!.masterId,
          state.selectedSalesVchType!.masterId,
          state.selectedReceiptVchType!.masterId,
        ],
        salesLedgerMasterId: state.selectedSalesLedger?.masterId,
        cashLedgerMasterId: state.selectedCashLedger?.masterId,
      );

      await fetchInitialData();
      resetForm();
      return null;
    } catch (e) {
      return 'Error: $e';
    } finally {
      state = state.copyWith(isSaving: false);
    }
  }
}

final vanAllocationNotifierProvider =
    StateNotifierProvider.autoDispose<VanAllocationNotifier, VanAllocationState>(
  (ref) => VanAllocationNotifier(),
);
