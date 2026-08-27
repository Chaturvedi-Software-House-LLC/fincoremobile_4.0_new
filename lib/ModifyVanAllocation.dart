import 'dart:io';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'constants.dart';
import 'package:FincoreGo/widgets/app_bottom_nav.dart';
import 'van_allocation_data.dart';
import 'viewVanAllocations.dart';
import 'widgets/entry_widgets.dart';
import 'widgets/searchable_selector.dart';

/// Modify an existing Van Allocation. `widget.allocation` is one entry from
/// `ViewVanAllocationScreen`'s list - see that screen for its shape
/// (`{companyUserId, name, username, godownMasterId, godownName,
/// voucherTypeMasterIds, voucherTypeNames, deliveryNote/sales/receipt
/// MasterOption}`), built there from the same GODOWN/VOUCHER_TYPE
/// master-restriction reads this screen re-fetches fresh options for.
///
/// DATA LAYER: see `addVanAllocations.dart`'s doc-comment - same
/// master-restrictions-based design, "update" here means a full-replace PUT
/// of both restriction sets (master-restrictions has no partial-update
/// semantics).
class ModifyVanAllocationScreen extends StatefulWidget {
  final Map<String, dynamic> allocation;

  const ModifyVanAllocationScreen({super.key, required this.allocation});

  @override
  State<ModifyVanAllocationScreen> createState() => _ModifyVanAllocationScreenState();
}

class _ModifyVanAllocationScreenState extends State<ModifyVanAllocationScreen> {
  final Color primaryColor = app_color;
  final Color textColor = const Color(0xFF1F2937);

  bool isLoading = true;
  bool isSaving = false;

  late final String companyUserId = widget.allocation['companyUserId'] as String;

  MasterOption? selectedLocation;
  MasterOption? selectedDeliveryNoteVchType;
  MasterOption? selectedSalesVchType;
  MasterOption? selectedReceiptVchType;
  // Kept as a local-only, unsaved UI control - see addVanAllocations.dart's
  // doc-comment; master-restrictions has no "is_bulk" field.
  bool isBulkAllocation = false;

  List<MasterOption> locations = [];
  List<MasterOption> deliveryNoteVchTypes = [];
  List<MasterOption> salesVchTypes = [];
  List<MasterOption> receiptVchTypes = [];

  @override
  void initState() {
    super.initState();
    initialize();
  }

  Future<void> initialize() async {
    try {
      final results = await Future.wait([
        VanAllocationData.listAllGodowns(),
        VanAllocationData.listVoucherTypesByReservedName('DELIVERY_NOTE'),
        VanAllocationData.listVoucherTypesByReservedName('SALES'),
        VanAllocationData.listVoucherTypesByReservedName('RECEIPT'),
      ]);
      locations = results[0];
      deliveryNoteVchTypes = results[1];
      salesVchTypes = results[2];
      receiptVchTypes = results[3];

      final godownId = widget.allocation['godownMasterId'] as int?;
      selectedLocation = godownId == null ? null : _findByMasterId(locations, godownId);

      final vchIds = ((widget.allocation['voucherTypeMasterIds'] as List?) ?? const [])
          .cast<int>()
          .toSet();
      selectedDeliveryNoteVchType = _findByMasterIds(deliveryNoteVchTypes, vchIds);
      selectedSalesVchType = _findByMasterIds(salesVchTypes, vchIds);
      selectedReceiptVchType = _findByMasterIds(receiptVchTypes, vchIds);
    } catch (e) {
      debugPrint('Modify Van Allocation initialize error: $e');
    } finally {
      setState(() => isLoading = false);
    }
  }

  MasterOption? _findByMasterId(List<MasterOption> options, int masterId) {
    for (final o in options) {
      if (o.masterId == masterId) return o;
    }
    return null;
  }

  MasterOption? _findByMasterIds(List<MasterOption> options, Set<int> masterIds) {
    for (final o in options) {
      if (masterIds.contains(o.masterId)) return o;
    }
    return null;
  }

  bool get isFormValid =>
      selectedLocation != null &&
      selectedDeliveryNoteVchType != null &&
      selectedSalesVchType != null &&
      selectedReceiptVchType != null;

  Future<void> updateAllocation() async {
    if (!isFormValid) return;
    setState(() => isSaving = true);
    try {
      final alreadyTaken = await VanAllocationData.isGodownAlreadyAllocated(
        selectedLocation!.masterId,
        excludingCompanyUserId: companyUserId,
      );
      if (alreadyTaken) {
        showAppMessage(
          context,
          'This vehicle/location is already allocated to another user',
        );
        return;
      }

      await VanAllocationData.saveAllocation(
        companyUserId: companyUserId,
        godownMasterId: selectedLocation!.masterId,
        voucherTypeMasterIds: [
          selectedDeliveryNoteVchType!.masterId,
          selectedSalesVchType!.masterId,
          selectedReceiptVchType!.masterId,
        ],
      );

      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const ViewVanAllocationScreen()),
      );
    } catch (e) {
      debugPrint(e.toString());
      showAppMessage(context, 'Error: $e');
    } finally {
      if (mounted) setState(() => isSaving = false);
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
        centerTitle: true,
        backgroundColor: primaryColor,
        automaticallyImplyLeading: false,
        leading: IconButton(
          onPressed: () {
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(builder: (_) => const ViewVanAllocationScreen()),
            );
          },
          icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
        ),
        actions: const [],
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.15),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.edit_outlined, color: Colors.white, size: 20),
            ),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Modify Allocation',
                  style: GoogleFonts.poppins(fontSize: 17, fontWeight: FontWeight.w700, color: Colors.white),
                ),
                Text(
                  'Update allocation details',
                  style: GoogleFonts.poppins(fontSize: 11, color: Colors.white.withOpacity(0.8)),
                ),
              ],
            ),
          ],
        ),
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator.adaptive())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Container(
                padding: const EdgeInsets.all(18),
                decoration: _cardDecoration(),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _sectionTitle(),
                    const SizedBox(height: 24),
                    SearchableSelectorField<MasterOption>(
                      value: selectedLocation,
                      items: locations,
                      itemLabel: (v) => v.name,
                      label: 'Location',
                      icon: Icons.location_on_outlined,
                      hintText: 'Search and select location',
                      onChanged: (val) => setState(() => selectedLocation = val),
                    ),
                    const SizedBox(height: 16),
                    SearchableSelectorField<MasterOption>(
                      value: selectedDeliveryNoteVchType,
                      items: deliveryNoteVchTypes,
                      itemLabel: (v) => v.name,
                      label: 'Delivery Note Voucher Type',
                      icon: Icons.receipt_long_outlined,
                      hintText: 'Search and select delivery note voucher type',
                      onChanged: (val) => setState(() => selectedDeliveryNoteVchType = val),
                    ),
                    const SizedBox(height: 16),
                    SearchableSelectorField<MasterOption>(
                      value: selectedSalesVchType,
                      items: salesVchTypes,
                      itemLabel: (v) => v.name,
                      label: 'Sales Voucher Type',
                      icon: Icons.point_of_sale_outlined,
                      hintText: 'Search and select sales voucher type',
                      onChanged: (val) => setState(() => selectedSalesVchType = val),
                    ),
                    const SizedBox(height: 16),
                    SearchableSelectorField<MasterOption>(
                      value: selectedReceiptVchType,
                      items: receiptVchTypes,
                      itemLabel: (v) => v.name,
                      label: 'Receipt Voucher Type',
                      icon: Icons.receipt_outlined,
                      hintText: 'Search and select receipt voucher type',
                      onChanged: (val) => setState(() => selectedReceiptVchType = val),
                    ),
                    const SizedBox(height: 16),
                    _bulkAllocationToggle(),
                    const SizedBox(height: 28),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: isSaving ? null : updateAllocation,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: primaryColor,
                          elevation: 0,
                          padding: const EdgeInsets.symmetric(vertical: 15),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        ),
                        icon: isSaving
                            ? SizedBox(
                                height: 18,
                                width: 18,
                                child: Platform.isIOS
                                    ? const CupertinoActivityIndicator(color: Colors.white, radius: 10)
                                    : const CircularProgressIndicator(
                                        strokeWidth: 2.2,
                                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                      ),
                              )
                            : const Icon(Icons.save_outlined, color: Colors.white),
                        label: Text(
                          isSaving ? "Updating..." : "Update Allocation",
                          style: GoogleFonts.poppins(color: Colors.white, fontWeight: FontWeight.w600),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
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
          'Not yet saved anywhere - kept as a UI placeholder only.',
          style: GoogleFonts.poppins(fontSize: 11, color: textColor.withOpacity(0.6)),
        ),
      ),
    );
  }

  Widget _sectionTitle() {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(color: primaryColor.withOpacity(0.1), borderRadius: BorderRadius.circular(12)),
          child: Icon(Icons.settings_outlined, color: primaryColor),
        ),
        const SizedBox(width: 10),
        Text(
          'Allocation Details',
          style: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.w700, color: Theme.of(context).colorScheme.onSurface),
        ),
      ],
    );
  }

  BoxDecoration _cardDecoration() {
    return BoxDecoration(
      color: Theme.of(context).cardColor,
      borderRadius: BorderRadius.circular(24),
      border: Theme.of(context).brightness == Brightness.dark
          ? Border.all(color: Colors.white.withOpacity(0.10), width: 1)
          : null,
      boxShadow: [
        BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 18, offset: const Offset(0, 8)),
      ],
    );
  }
}
