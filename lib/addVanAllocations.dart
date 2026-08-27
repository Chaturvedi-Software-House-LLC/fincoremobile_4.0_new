import 'dart:io';
import 'package:FincoreGo/viewVanAllocations.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'constants.dart';
import 'package:FincoreGo/widgets/app_bottom_nav.dart';
import 'van_allocation_data.dart';
import 'widgets/entry_widgets.dart';
import 'widgets/searchable_selector.dart';

/// Van Allocation ("Spectra") - vehicle/voucher-type assignment screen.
///
/// DATA LAYER: this used to call the legacy `/api/spectra/Allocations`
/// endpoint. It now reads/writes tally-api's `master-restrictions` feature
/// instead (see `lib/van_allocation_data.dart` and
/// `lib/api/master_restrictions_repository.dart`):
///   - "Vehicle" = a company-user's `GODOWN` restriction set to exactly one
///     masterId.
///   - The Delivery Note / Sales / Receipt voucher types a company-user may
///     use = their `VOUCHER_TYPE` restriction.
/// Sales Ledger / Cash Ledger are intentionally no longer configured here -
/// master-restrictions has no per-user storage for them (using a LEDGER
/// restriction was explicitly rejected, since it would also hide every
/// customer/party ledger from that user elsewhere in the app). The
/// registration screens now derive a sales/cash ledger default themselves,
/// company-wide, from Group.reservedName - see `SalesRegistration.dart`.
class VanAllocationScreen extends StatefulWidget {
  const VanAllocationScreen({super.key});

  @override
  State<VanAllocationScreen> createState() => _VanAllocationScreenState();
}

class _VanAllocationScreenState extends State<VanAllocationScreen> {
  final Color primaryColor = app_color;
  final Color textColor = const Color(0xFF1F2937);

  CompanyUserOption? selectedUser;
  MasterOption? selectedLocation;
  MasterOption? selectedDeliveryNoteVchType;
  MasterOption? selectedSalesVchType;
  MasterOption? selectedReceiptVchType;

  List<CompanyUserOption> users = [];
  List<MasterOption> locations = [];
  List<MasterOption> deliveryNoteVchTypes = [];
  List<MasterOption> salesVchTypes = [];
  List<MasterOption> receiptVchTypes = [];

  bool isSaving = false;
  bool isLoading = true;
  // Kept as a local-only, unsaved UI control: master-restrictions has no
  // backend field for "is_bulk" (that concept - is_bulk/meter-reading - is
  // out of scope for this data-layer migration and still driven by the
  // legacy "spectra_allocations" SharedPreferences cache read at login,
  // untouched by this screen). Toggling it here does nothing.
  bool isBulkAllocation = false;
  int formResetKey = 0;

  @override
  void initState() {
    super.initState();
    fetchInitialData();
  }

  Future<void> fetchInitialData() async {
    setState(() => isLoading = true);
    try {
      final results = await Future.wait([
        VanAllocationData.listCompanyUsers(),
        VanAllocationData.listAllGodowns(),
        VanAllocationData.listVoucherTypesByReservedName('DELIVERY_NOTE'),
        VanAllocationData.listVoucherTypesByReservedName('SALES'),
        VanAllocationData.listVoucherTypesByReservedName('RECEIPT'),
      ]);
      final allUsers = results[0] as List<CompanyUserOption>;
      locations = results[1] as List<MasterOption>;
      deliveryNoteVchTypes = results[2] as List<MasterOption>;
      salesVchTypes = results[3] as List<MasterOption>;
      receiptVchTypes = results[4] as List<MasterOption>;

      // Only offer company-users who don't already have a vehicle (GODOWN
      // restriction) assigned - mirrors the legacy screen's "already
      // allocated" exclusion from the user picker.
      final unallocated = <CompanyUserOption>[];
      for (final user in allUsers) {
        final existing = await VanAllocationData.currentGodownMasterId(user.id);
        if (existing == null) unallocated.add(user);
      }
      users = unallocated;
      if (users.isEmpty) selectedUser = null;
    } catch (e) {
      debugPrint('Van Allocation fetchInitialData error: $e');
    } finally {
      setState(() => isLoading = false);
    }
  }

  bool get isFormValid =>
      selectedUser != null &&
      selectedLocation != null &&
      selectedDeliveryNoteVchType != null &&
      selectedSalesVchType != null &&
      selectedReceiptVchType != null;

  void _resetForm() {
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      selectedUser = null;
      selectedLocation = null;
      selectedDeliveryNoteVchType = null;
      selectedSalesVchType = null;
      selectedReceiptVchType = null;
      isBulkAllocation = false;
      formResetKey++;
      if (users.isEmpty) selectedUser = null;
    });
  }

  Future<void> _saveAllocation() async {
    if (!isFormValid) {
      showAppMessage(context, 'Please fill all fields');
      return;
    }

    setState(() => isSaving = true);
    try {
      final alreadyTaken = await VanAllocationData.isGodownAlreadyAllocated(
        selectedLocation!.masterId,
      );
      if (alreadyTaken) {
        showAppMessage(
          context,
          'This vehicle/location is already allocated to another user',
        );
        return;
      }

      await VanAllocationData.saveAllocation(
        companyUserId: selectedUser!.id,
        godownMasterId: selectedLocation!.masterId,
        voucherTypeMasterIds: [
          selectedDeliveryNoteVchType!.masterId,
          selectedSalesVchType!.masterId,
          selectedReceiptVchType!.masterId,
        ],
      );

      await fetchInitialData();
      _resetForm();
    } catch (e) {
      debugPrint('SAVE ALLOCATION ERROR: $e');
      showAppMessage(context, 'Error: $e');
    } finally {
      setState(() => isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      bottomNavigationBar: const AppBottomNav(
        activeTab: AppBottomNavTab.more,
        activeMoreItem: AppMoreItem.vanAllocation,
      ),
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: primaryColor,
        centerTitle: true,
        automaticallyImplyLeading: false,
        leadingWidth: 70,
        leading: Center(
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: () {
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(builder: (_) => const ViewVanAllocationScreen()),
              );
            },
            child: const Icon(Icons.arrow_back_rounded, color: Colors.white, size: 22),
          ),
        ),
        actions: const [],
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Theme.of(context).cardColor.withOpacity(0.15),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.local_shipping_outlined, color: Colors.white, size: 20),
            ),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Van Allocation',
                  style: GoogleFonts.poppins(fontSize: 17, fontWeight: FontWeight.w700, color: Colors.white),
                ),
                Text(
                  'Add user allocations',
                  style: GoogleFonts.poppins(fontSize: 11, color: Colors.white.withOpacity(0.8)),
                ),
              ],
            ),
          ],
        ),
      ),
      body: isLoading
          ? _buildSkeletonForm()
          : LayoutBuilder(
              builder: (context, constraints) {
                final bool isMobile = constraints.maxWidth < 700;
                return Column(
                  children: [
                    Expanded(
                      child: SingleChildScrollView(
                        padding: EdgeInsets.all(isMobile ? 14 : 22),
                        child: Center(
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 1180),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _buildAllocationForm(isMobile),
                                const SizedBox(height: 30),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
    );
  }

  Widget _buildSkeletonForm() {
    return ShimmerLoading(
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: _cardDecoration(),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const ShimmerBox(height: 18, width: 180),
                const SizedBox(height: 18),
                for (int i = 0; i < 5; i++)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: const [
                        ShimmerBox(height: 12, width: 120),
                        SizedBox(height: 8),
                        ShimmerBox(height: 52, borderRadius: 22),
                      ],
                    ),
                  ),
                const ShimmerBox(height: 48, borderRadius: 22),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAllocationForm(bool isMobile) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionTitle(Icons.settings_outlined, 'Allocation Configuration'),
          const SizedBox(height: 18),
          _responsiveWrap(
            isMobile: isMobile,
            children: [
              SearchableSelectorField<CompanyUserOption>(
                key: ValueKey('user_$formResetKey'),
                value: selectedUser,
                items: users,
                itemLabel: (u) => u.username.isNotEmpty ? '${u.name} (${u.username})' : u.name,
                label: 'User Name',
                icon: Icons.person_search_outlined,
                hintText: users.isEmpty ? 'No user available' : 'Search and select user',
                onChanged: (val) => setState(() => selectedUser = val),
              ),
              SearchableSelectorField<MasterOption>(
                key: ValueKey('location_$formResetKey'),
                value: selectedLocation,
                items: locations,
                itemLabel: (v) => v.name,
                label: 'Location',
                icon: Icons.location_on_outlined,
                hintText: 'Search and select location',
                onChanged: (val) => setState(() => selectedLocation = val),
              ),
              SearchableSelectorField<MasterOption>(
                key: ValueKey('dn_$formResetKey'),
                value: selectedDeliveryNoteVchType,
                items: deliveryNoteVchTypes,
                itemLabel: (v) => v.name,
                label: 'Delivery Note Voucher Type',
                icon: Icons.receipt_long_outlined,
                hintText: 'Search and select delivery note voucher type',
                onChanged: (val) => setState(() => selectedDeliveryNoteVchType = val),
              ),
              SearchableSelectorField<MasterOption>(
                key: ValueKey('sales_$formResetKey'),
                value: selectedSalesVchType,
                items: salesVchTypes,
                itemLabel: (v) => v.name,
                label: 'Sales Voucher Type',
                icon: Icons.point_of_sale_outlined,
                hintText: 'Search and select sales voucher type',
                onChanged: (val) => setState(() => selectedSalesVchType = val),
              ),
              SearchableSelectorField<MasterOption>(
                key: ValueKey('receipt_$formResetKey'),
                value: selectedReceiptVchType,
                items: receiptVchTypes,
                itemLabel: (v) => v.name,
                label: 'Receipt Voucher Type',
                icon: Icons.payments_outlined,
                hintText: 'Search and select receipt voucher type',
                onChanged: (val) => setState(() => selectedReceiptVchType = val),
              ),
            ],
          ),
          const SizedBox(height: 18),
          _bulkAllocationToggle(),
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _resetForm,
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 15),
                    side: BorderSide(color: primaryColor),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  child: Text('Reset', style: GoogleFonts.poppins(color: primaryColor, fontWeight: FontWeight.w600)),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: ElevatedButton(
                  onPressed: isSaving ? null : _saveAllocation,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: primaryColor,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(vertical: 15),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  child: isSaving
                      ? Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            SizedBox(
                              height: 18,
                              width: 18,
                              child: Platform.isIOS
                                  ? const CupertinoActivityIndicator(color: Colors.white, radius: 10)
                                  : const CircularProgressIndicator(
                                      strokeWidth: 2.2,
                                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                    ),
                            ),
                            const SizedBox(width: 12),
                            Text('Saving...', style: GoogleFonts.poppins(color: Colors.white, fontWeight: FontWeight.w600)),
                          ],
                        )
                      : Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.save_outlined, color: Colors.white, size: 20),
                            const SizedBox(width: 8),
                            Text('Save Allocation', style: GoogleFonts.poppins(color: Colors.white, fontWeight: FontWeight.w600)),
                          ],
                        ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _responsiveWrap({required bool isMobile, required List<Widget> children}) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final double itemWidth = isMobile ? constraints.maxWidth : (constraints.maxWidth - 18) / 2;
        return Wrap(
          spacing: 18,
          runSpacing: 16,
          children: children.map((child) => SizedBox(width: itemWidth, child: child)).toList(),
        );
      },
    );
  }

  Widget _bulkAllocationToggle() {
    final Color stateColor = isBulkAllocation ? primaryColor : Colors.grey;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: BoxDecoration(
        color: isBulkAllocation ? primaryColor.withOpacity(0.08) : Colors.grey.withOpacity(0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: stateColor.withOpacity(0.45), width: 1.2),
      ),
      child: SwitchListTile(
        contentPadding: EdgeInsets.zero,
        activeColor: primaryColor,
        inactiveThumbColor: Colors.grey.shade500,
        inactiveTrackColor: Colors.grey.shade300,
        value: isBulkAllocation,
        onChanged: (val) => setState(() => isBulkAllocation = val),
        title: Row(
          children: [
            Text('Bulk (Tanker) Delivery', style: GoogleFonts.poppins(fontWeight: FontWeight.w600, fontSize: 14)),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(color: stateColor.withOpacity(0.15), borderRadius: BorderRadius.circular(20)),
              child: Text(
                isBulkAllocation ? 'ON' : 'OFF',
                style: GoogleFonts.poppins(fontSize: 10, fontWeight: FontWeight.w700, color: stateColor),
              ),
            ),
          ],
        ),
        subtitle: Text(
          'Not yet saved anywhere - kept as a UI placeholder only '
          '(is_bulk/meter-reading is out of scope for this migration).',
          style: GoogleFonts.poppins(fontSize: 11, color: textColor.withOpacity(0.6)),
        ),
      ),
    );
  }

  Widget _sectionTitle(IconData icon, String title) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(color: primaryColor.withOpacity(0.1), borderRadius: BorderRadius.circular(12)),
          child: Icon(icon, color: primaryColor, size: 20),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            title,
            style: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.w700, color: Theme.of(context).colorScheme.onSurface),
          ),
        ),
      ],
    );
  }

  BoxDecoration _cardDecoration({double radius = 22}) {
    return BoxDecoration(
      color: Theme.of(context).cardColor,
      borderRadius: BorderRadius.circular(radius),
      border: Theme.of(context).brightness == Brightness.dark
          ? Border.all(color: Colors.white.withOpacity(0.10), width: 1)
          : null,
      boxShadow: [
        BoxShadow(color: Colors.black.withOpacity(0.045), blurRadius: 14, offset: const Offset(0, 5)),
      ],
    );
  }
}
