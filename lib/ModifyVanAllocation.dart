import 'dart:convert';
import 'dart:io';
import 'package:FincoreGo/viewVanAllocations.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'constants.dart';
import 'package:FincoreGo/widgets/app_bottom_nav.dart';
import 'widgets/entry_widgets.dart';

class ModifyVanAllocationScreen extends StatefulWidget {
  final Map<String, dynamic> allocation;

  const ModifyVanAllocationScreen({super.key, required this.allocation});

  @override
  State<ModifyVanAllocationScreen> createState() =>
      _ModifyVanAllocationScreenState();
}

class _ModifyVanAllocationScreenState extends State<ModifyVanAllocationScreen> {
  final Color primaryColor = app_color;
  final Color backgroundColor = const Color(0xFFF5F7FA);
  final Color textColor = const Color(0xFF1F2937);

  bool isLoading = true;
  bool isSaving = false;

  String token = "";
  String serial_no = "";

  String? selectedLocation;
  String? selectedDeliveryNoteVchType;
  String? selectedSalesVchType;
  String? selectedReceiptVchType;
  String? selectedSalesLedger;
  String? selectedCashLedger;
  // Whether this allocation is for bulk (tanker) gas delivery - saved as
  // "is_bulk" and read back from the "spectra_allocations" login response
  // to drive UniGas's bulk-vs-non-bulk delivery note flow without asking
  // the user each time in DeliveryNoteRegistration.dart.
  bool isBulkAllocation = false;

  List<String> locations = [];
  List<String> deliveryNoteVchTypes = [];
  List<String> salesVchTypes = [];
  List<String> receiptVchTypes = [];
  List<String> salesLedgers = [];
  List<String> cashLedgers = [];

  String? hostname = "",
      company = "",
      company_lowercase = "",
      username = "",
      base_currency = "";

  Widget _searchableDropdownField({
    required String title,
    required String? value,
    required List<String> items,
    required IconData icon,
    required String hint,
    required Function(String?) onSelected,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: GoogleFonts.poppins(
            fontSize: 12.5,
            fontWeight: FontWeight.w600,
            color: Theme.of(context).colorScheme.onSurface,
          ),
        ),

        const SizedBox(height: 8),

        Autocomplete<String>(
          optionsBuilder: (TextEditingValue textEditingValue) {
            if (textEditingValue.text.isEmpty) {
              return items;
            }

            return items.where(
              (item) => item.toLowerCase().contains(
                textEditingValue.text.toLowerCase(),
              ),
            );
          },

          initialValue: TextEditingValue(text: value ?? ''),

          onSelected: onSelected,

          fieldViewBuilder:
              (context, controller, focusNode, onEditingComplete) {
                controller.text = value ?? controller.text;

                return TextField(
                  controller: controller,
                  focusNode: focusNode,

                  style: GoogleFonts.poppins(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),

                  decoration: InputDecoration(
                    hintText: hint,

                    hintStyle: GoogleFonts.poppins(
                      fontSize: 12.5,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),

                    prefixIcon: Icon(icon, color: primaryColor, size: 20),

                    suffixIcon: (controller.text.isNotEmpty || value != null)
                        ? IconButton(
                            icon: Icon(
                              Icons.close_rounded,
                              color: Theme.of(
                                context,
                              ).colorScheme.onSurfaceVariant,
                              size: 20,
                            ),
                            onPressed: () {
                              controller.clear();

                              onSelected(null);

                              setState(() {});
                            },
                          )
                        : null,

                    filled: true,
                    fillColor: Theme.of(context).brightness == Brightness.dark
                        ? Theme.of(
                            context,
                          ).colorScheme.surfaceContainerHighest.withOpacity(0.5)
                        : const Color(0xFFF5F7FA),

                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 15,
                    ),

                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: BorderSide.none,
                    ),

                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: BorderSide(
                        color: Theme.of(context).dividerColor,
                      ),
                    ),

                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: BorderSide(color: primaryColor, width: 1.4),
                    ),
                  ),
                );
              },

          optionsViewBuilder: (context, onSelected, options) {
            return Align(
              alignment: Alignment.topLeft,

              child: Material(
                color: Colors.transparent,

                child: Container(
                  margin: const EdgeInsets.only(top: 8),

                  constraints: const BoxConstraints(maxHeight: 260),

                  width: MediaQuery.of(context).size.width * 0.9,

                  decoration: BoxDecoration(
                    color: Theme.of(context).cardColor,
                    borderRadius: BorderRadius.circular(18),

                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.08),
                        blurRadius: 18,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),

                  child: ListView.builder(
                    padding: const EdgeInsets.all(10),

                    shrinkWrap: true,

                    itemCount: options.length,

                    itemBuilder: (context, index) {
                      final option = options.elementAt(index);

                      return InkWell(
                        borderRadius: BorderRadius.circular(14),

                        onTap: () => onSelected(option),

                        child: Container(
                          margin: const EdgeInsets.only(bottom: 8),

                          padding: const EdgeInsets.all(12),

                          decoration: BoxDecoration(
                            color:
                                Theme.of(context).brightness == Brightness.dark
                                ? Theme.of(context)
                                      .colorScheme
                                      .surfaceContainerHighest
                                      .withOpacity(0.5)
                                : const Color(0xFFF5F7FA),
                            borderRadius: BorderRadius.circular(14),
                          ),

                          child: Row(
                            children: [
                              Container(
                                height: 40,
                                width: 40,

                                decoration: BoxDecoration(
                                  color: primaryColor.withOpacity(0.12),

                                  borderRadius: BorderRadius.circular(12),
                                ),

                                child: Icon(
                                  icon,
                                  color: primaryColor,
                                  size: 20,
                                ),
                              ),

                              const SizedBox(width: 12),

                              Expanded(
                                child: Text(
                                  option,

                                  style: GoogleFonts.poppins(
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w600,
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.onSurface,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
            );
          },
        ),
      ],
    );
  }

  @override
  void initState() {
    super.initState();
    initialize();
  }

  Future<void> initialize() async {
    final prefs = await SharedPreferences.getInstance();

    token = prefs.getString('token') ?? '';
    serial_no = prefs.getString('serial_no') ?? '';

    selectedLocation = widget.allocation['godown_name'];

    selectedDeliveryNoteVchType = widget.allocation['voucher_type_name'];

    hostname = prefs.getString('hostname');
    company = prefs.getString('company_name');
    company_lowercase = company!.replaceAll(' ', '').toLowerCase();
    selectedSalesVchType = widget.allocation['sales_voucher_type'];

    selectedReceiptVchType = widget.allocation['receipt_voucher_type'];

    selectedSalesLedger = widget.allocation['sales_ledger'];

    selectedCashLedger = widget.allocation['cash_ledger'];

    isBulkAllocation = parseBoolFlag(widget.allocation['is_bulk']);

    await fetchDropdownData();
  }

  Future<void> fetchDropdownData() async {
    try {
      final response = await http.post(
        Uri.parse('$hostname/api/entry/getSpectra/$company/$serial_no'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({}),
      );

      debugPrint("MODIFY DROPDOWN RESPONSE: ${response.body}");

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);

        final allocationsUrl =
            Uri.parse('$BASE_URL_config/api/spectra/Allocations').replace(
              queryParameters: {
                'serial_no': serial_no,
                'company_name': company,
              },
            );

        final allocationResponse = await http.get(
          allocationsUrl,
          headers: {
            'Authorization': 'Bearer $authTokenBase',
            'Content-Type': 'application/json',
          },
        );

        debugPrint("ALLOCATION STATUS: ${allocationResponse.statusCode}");
        debugPrint("ALLOCATION RESPONSE: ${allocationResponse.body}");

        final Set<String> allocatedLocations = {};
        final Set<String> allocatedDeliveryNoteVchTypes = {};
        final Set<String> allocatedSalesVchTypes = {};
        final Set<String> allocatedReceiptVchTypes = {};

        final currentLocation = widget.allocation['godown_name']
            ?.toString()
            .trim()
            .toLowerCase();

        final currentDeliveryNoteVchType = widget
            .allocation['voucher_type_name']
            ?.toString()
            .trim()
            .toLowerCase();

        final currentSalesVchType = widget.allocation['sales_voucher_type']
            ?.toString()
            .trim()
            .toLowerCase();

        final currentReceiptVchType = widget.allocation['receipt_voucher_type']
            ?.toString()
            .trim()
            .toLowerCase();

        if (allocationResponse.statusCode == 200) {
          final List<dynamic> allocationJsonList = jsonDecode(
            allocationResponse.body,
          );

          for (final item in allocationJsonList) {
            final map = item as Map<String, dynamic>;

            final serialNo = map['serial_no']?.toString().trim();

            if (serialNo == serial_no) {
              final location = map['godown_name']
                  ?.toString()
                  .trim()
                  .toLowerCase();

              final deliveryNoteVchType = map['voucher_type_name']
                  ?.toString()
                  .trim()
                  .toLowerCase();

              final salesVchType = map['sales_voucher_type']
                  ?.toString()
                  .trim()
                  .toLowerCase();

              final receiptVchType = map['receipt_voucher_type']
                  ?.toString()
                  .trim()
                  .toLowerCase();

              if (location != null &&
                  location.isNotEmpty &&
                  location != currentLocation) {
                allocatedLocations.add(location);
              }

              if (deliveryNoteVchType != null &&
                  deliveryNoteVchType.isNotEmpty &&
                  deliveryNoteVchType != currentDeliveryNoteVchType) {
                allocatedDeliveryNoteVchTypes.add(deliveryNoteVchType);
              }

              if (salesVchType != null &&
                  salesVchType.isNotEmpty &&
                  salesVchType != currentSalesVchType) {
                allocatedSalesVchTypes.add(salesVchType);
              }

              if (receiptVchType != null &&
                  receiptVchType.isNotEmpty &&
                  receiptVchType != currentReceiptVchType) {
                allocatedReceiptVchTypes.add(receiptVchType);
              }
            }
          }
        }

        debugPrint("Modify Allocated Locations: $allocatedLocations");
        debugPrint(
          "Modify Allocated Delivery Note: $allocatedDeliveryNoteVchTypes",
        );
        debugPrint("Modify Allocated Sales: $allocatedSalesVchTypes");
        debugPrint("Modify Allocated Receipt: $allocatedReceiptVchTypes");

        final List<dynamic> apiVchTypes = data['vchTypes'] ?? [];

        List<String> getVchTypesByParent(String parentName) {
          for (final item in apiVchTypes) {
            final map = item as Map<String, dynamic>;

            final parent = map['parent']?.toString().trim().toLowerCase() ?? '';

            if (parent == parentName.toLowerCase()) {
              return List<String>.from(map['name'] ?? [])
                  .where((vch) => vch.toString().trim().isNotEmpty)
                  .toSet()
                  .toList();
            }
          }

          return [];
        }

        locations = List<String>.from(data['locations'] ?? [])
            .where((location) {
              final locationName = location.toString().trim().toLowerCase();

              return locationName.isNotEmpty &&
                  !allocatedLocations.contains(locationName);
            })
            .toSet()
            .toList();

        deliveryNoteVchTypes = getVchTypesByParent('delivery note').where((
          vch,
        ) {
          final vchName = vch.toString().trim().toLowerCase();

          return !allocatedDeliveryNoteVchTypes.contains(vchName);
        }).toList();

        salesVchTypes = getVchTypesByParent('sales').where((vch) {
          final vchName = vch.toString().trim().toLowerCase();

          return !allocatedSalesVchTypes.contains(vchName);
        }).toList();

        receiptVchTypes = getVchTypesByParent('receipt').where((vch) {
          final vchName = vch.toString().trim().toLowerCase();

          return !allocatedReceiptVchTypes.contains(vchName);
        }).toList();

        salesLedgers = List<String>.from(data['salesLedgers'] ?? []);

        cashLedgers = List<String>.from(data['cashLedgers'] ?? []);
      }
    } catch (e) {
      debugPrint(e.toString());
    } finally {
      setState(() {
        isLoading = false;
      });
    }
  }

  Future<void> updateAllocation() async {
    try {
      setState(() {
        isSaving = true;
      });

      dynamic body = jsonEncode({
        "user_name": widget.allocation['user_name'],

        "serial_no": widget.allocation['serial_no'],

        "company_name": widget.allocation['company_name'],

        "godown_name": selectedLocation,

        "voucher_type_name": selectedDeliveryNoteVchType,

        "sales_voucher_type": selectedSalesVchType,

        "receipt_voucher_type": selectedReceiptVchType,

        "sales_ledger": selectedSalesLedger,

        "cash_ledger": selectedCashLedger,

        "is_bulk": isBulkAllocation,
      });

      final response = await http.put(
        Uri.parse('$BASE_URL_config/api/spectra/Allocations'),

        headers: {
          'Authorization': 'Bearer $authTokenBase',
          'Content-Type': 'application/json',
        },

        body: body,
      );

      debugPrint("UPDATE RESPONSE BODY: ${body}");
      debugPrint("UPDATE RESPONSE: ${response.body}");

      if (response.statusCode == 200) {
        /*showAppMessage(context, 'Allocation updated successfully');*/

        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => ViewVanAllocationScreen()),
        );
      } else {
        showAppMessage(context, response.body);
      }
    } catch (e) {
      debugPrint(e.toString());
    } finally {
      setState(() {
        isSaving = false;
      });
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
              MaterialPageRoute(
                builder: (_) => const ViewVanAllocationScreen(),
              ),
            );
          },
          icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
        ),

        actions: [],

        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.15),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(
                Icons.edit_outlined,
                color: Colors.white,
                size: 20,
              ),
            ),

            const SizedBox(width: 12),

            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Modify Allocation',
                  style: GoogleFonts.poppins(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),

                Text(
                  'Update allocation details',
                  style: GoogleFonts.poppins(
                    fontSize: 11,
                    color: Colors.white.withOpacity(0.8),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),

      body: isLoading
          ? Center(child: CircularProgressIndicator.adaptive())
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

                    _searchableDropdownField(
                      title: 'Location',
                      value: selectedLocation,
                      items: locations,
                      icon: Icons.location_on_outlined,
                      hint: 'Search and select location',
                      onSelected: (val) {
                        setState(() {
                          selectedLocation = val;
                        });
                      },
                    ),

                    const SizedBox(height: 16),

                    _searchableDropdownField(
                      title: 'Delivery Note Voucher Type',
                      value: selectedDeliveryNoteVchType,
                      items: deliveryNoteVchTypes,
                      icon: Icons.receipt_long_outlined,
                      hint: 'Search and select delivery note voucher type',
                      onSelected: (val) {
                        setState(() {
                          selectedDeliveryNoteVchType = val;
                        });
                      },
                    ),

                    const SizedBox(height: 16),

                    _searchableDropdownField(
                      title: 'Sales Voucher Type',
                      value: selectedSalesVchType,
                      items: salesVchTypes,
                      icon: Icons.point_of_sale_outlined,
                      hint: 'Search and select sales voucher type',
                      onSelected: (val) {
                        setState(() {
                          selectedSalesVchType = val;
                        });
                      },
                    ),

                    const SizedBox(height: 16),

                    _searchableDropdownField(
                      title: 'Receipt Voucher Type',
                      value: selectedReceiptVchType,
                      items: receiptVchTypes,
                      icon: Icons.receipt_outlined,
                      hint: 'Search and select receipt voucher type',
                      onSelected: (val) {
                        setState(() {
                          selectedReceiptVchType = val;
                        });
                      },
                    ),

                    const SizedBox(height: 16),

                    _searchableDropdownField(
                      title: 'Sales Ledger',
                      value: selectedSalesLedger,
                      items: salesLedgers,
                      icon: Icons.account_balance_wallet_outlined,
                      hint: 'Search and select sales ledger',
                      onSelected: (val) {
                        setState(() {
                          selectedSalesLedger = val;
                        });
                      },
                    ),

                    const SizedBox(height: 16),

                    _searchableDropdownField(
                      title: 'Cash Ledger',
                      value: selectedCashLedger,
                      items: cashLedgers,
                      icon: Icons.payments_outlined,
                      hint: 'Search and select cash ledger',
                      onSelected: (val) {
                        setState(() {
                          selectedCashLedger = val;
                        });
                      },
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
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),

                        icon: isSaving
                            ? SizedBox(
                                height: 18,
                                width: 18,
                                child: Platform.isIOS
                                    ? CupertinoActivityIndicator(
                                        color: Colors.white,
                                        radius: 10,
                                      )
                                    : CircularProgressIndicator(
                                        strokeWidth: 2.2,
                                        valueColor:
                                            AlwaysStoppedAnimation<Color>(
                                              Colors.white,
                                            ),
                                      ),
                              )
                            : const Icon(
                                Icons.save_outlined,
                                color: Colors.white,
                              ),

                        label: Text(
                          isSaving ? "Updating..." : "Update Allocation",
                          style: GoogleFonts.poppins(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _dropdownField({
    required String title,
    required String? value,
    required List<String> items,
    required IconData icon,
    required Function(String?) onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: GoogleFonts.poppins(
            fontSize: 12.5,
            fontWeight: FontWeight.w600,
            color: Theme.of(context).colorScheme.onSurface,
          ),
        ),

        const SizedBox(height: 8),

        DropdownButtonFormField<String>(
          value: value,
          isExpanded: true,

          icon: Icon(Icons.keyboard_arrow_down, color: primaryColor),

          style: GoogleFonts.poppins(
            color: Theme.of(context).colorScheme.onSurface,
          ),

          decoration: InputDecoration(
            hintText: 'Select $title',

            prefixIcon: Icon(icon, color: primaryColor),

            filled: true,
            fillColor: Theme.of(context).brightness == Brightness.dark
                ? Theme.of(
                    context,
                  ).colorScheme.surfaceContainerHighest.withOpacity(0.5)
                : const Color(0xFFF5F7FA),

            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide.none,
            ),

            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide(color: Theme.of(context).dividerColor),
            ),

            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide(color: primaryColor, width: 1.4),
            ),
          ),

          items: items.map((e) {
            return DropdownMenuItem(value: e, child: Text(e));
          }).toList(),

          onChanged: onChanged,
        ),
      ],
    );
  }

  Widget _bulkAllocationToggle() {
    // Container color/border react to the current value so OFF reads as
    // clearly "off" (neutral grey) rather than just a dim copy of ON, and
    // an explicit ON/OFF badge removes any ambiguity from the switch alone.
    final Color stateColor = isBulkAllocation ? primaryColor : Colors.grey;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: BoxDecoration(
        color: isBulkAllocation
            ? primaryColor.withOpacity(0.08)
            : Colors.grey.withOpacity(0.08),
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
            Text(
              'Bulk (Tanker) Delivery',
              style: GoogleFonts.poppins(
                fontWeight: FontWeight.w600,
                fontSize: 14,
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: stateColor.withOpacity(0.15),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                isBulkAllocation ? 'ON' : 'OFF',
                style: GoogleFonts.poppins(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: stateColor,
                ),
              ),
            ),
          ],
        ),
        subtitle: Text(
          'Enable if this allocation is for bulk gas delivery instead of '
          'cylinder delivery',
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
          decoration: BoxDecoration(
            color: primaryColor.withOpacity(0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(Icons.settings_outlined, color: primaryColor),
        ),

        const SizedBox(width: 10),

        Text(
          'Allocation Details',
          style: GoogleFonts.poppins(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: Theme.of(context).colorScheme.onSurface,
          ),
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
        BoxShadow(
          color: Colors.black.withOpacity(0.04),
          blurRadius: 18,
          offset: const Offset(0, 8),
        ),
      ],
    );
  }
}
