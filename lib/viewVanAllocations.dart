import 'dart:convert';
import 'package:FincoreGo/addVanAllocations.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'constants.dart';
import 'ModifyVanAllocation.dart';
import 'package:FincoreGo/widgets/app_bottom_nav.dart';
import 'widgets/entry_widgets.dart';

class ViewVanAllocationScreen extends StatefulWidget {
  const ViewVanAllocationScreen({super.key});

  @override
  State<ViewVanAllocationScreen> createState() =>
      _ViewVanAllocationScreenState();
}

class _ViewVanAllocationScreenState extends State<ViewVanAllocationScreen> {
  final Color primaryColor = app_color;
  final Color backgroundColor = const Color(0xFFF5F7FA);
  final Color textColor = const Color(0xFF1F2937);

  bool isLoading = true;

  String hostname = "";
  String token = "";

  final TextEditingController searchController = TextEditingController();

  List<Map<String, dynamic>> allocations = [];
  List<Map<String, dynamic>> filteredAllocations = [];

  dynamic serial_no = "", company = "", company_lowercase = "";

  Set<int> expandedCards = {};

  @override
  void initState() {
    super.initState();
    initialize();
  }

  Future<void> initialize() async {
    final prefs = await SharedPreferences.getInstance();

    hostname = prefs.getString('hostname') ?? '';
    token = prefs.getString('token') ?? '';
    serial_no = prefs.getString('serial_no');
    company = prefs.getString('company_name');
    company_lowercase = company!.replaceAll(' ', '').toLowerCase();
    await fetchAllocations();
  }

  Future<void> fetchAllocations() async {
    try {
      setState(() {
        isLoading = true;
      });

      var url = Uri.parse(
        '$BASE_URL_config/api/spectra/allocations?serial_no=$serial_no&company_name=$company',
      );
      final response = await http.get(
        url,
        headers: {
          'Authorization': 'Bearer $authTokenBase',
          'Content-Type': 'application/json',
        },
      );

      debugPrint("VIEW ALLOCATION URL: ${url}");
      debugPrint("VIEW ALLOCATION RESPONSE: ${response.body}");

      if (response.statusCode == 200) {
        final data = jsonDecode(utf8.decode(response.bodyBytes));

        allocations = List<Map<String, dynamic>>.from(data);

        filteredAllocations = allocations;
      }
    } catch (e) {
      debugPrint("VIEW ALLOCATION ERROR: $e");
    } finally {
      setState(() {
        isLoading = false;
      });
    }
  }

  void filterAllocations(String query) {
    if (query.isEmpty) {
      filteredAllocations = allocations;
    } else {
      filteredAllocations = allocations.where((allocation) {
        return allocation.toString().toLowerCase().contains(
          query.toLowerCase(),
        );
      }).toList();
    }

    setState(() {});
  }

  Future<void> deleteAllocation(Map<String, dynamic> allocation) async {
    try {
      final response = await http.delete(
        Uri.parse('$BASE_URL_config/api/spectra/Allocations'),

        headers: {
          'Authorization': 'Bearer $authTokenBase',
          'Content-Type': 'application/json',
        },

        body: jsonEncode({
          "user_name": allocation['user_name'],
          "serial_no": allocation['serial_no'],
          "company_name": allocation['company_name'],
        }),
      );

      debugPrint("DELETE RESPONSE: ${response.body}");

      if (response.statusCode == 200) {
        /*showAppMessage(context, 'Allocation deleted successfully', isError: false);*/

        fetchAllocations();
      } else {
        showAppMessage(context, 'Delete failed: ${response.body}');
      }
    } catch (e) {
      debugPrint("DELETE ERROR: $e");

      showAppMessage(context, 'Error: $e');
    }
  }

  void showDeleteDialog(Map<String, dynamic> allocation) {
    showDialog(
      context: context,
      builder: (_) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(22),
          ),

          title: Text(
            "Delete Allocation",
            style: GoogleFonts.poppins(fontWeight: FontWeight.w700),
          ),

          content: Text(
            "Are you sure you want to delete this allocation?",
            style: GoogleFonts.poppins(),
          ),

          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(context);
              },
              child: Text(
                "Cancel",
                style: GoogleFonts.poppins(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ),

            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),

              onPressed: () {
                Navigator.pop(context);

                deleteAllocation(allocation);
              },

              child: Text(
                "Delete",
                style: GoogleFonts.poppins(color: Colors.white),
              ),
            ),
          ],
        );
      },
    );
  }

  // Skeleton stand-in for the header + allocation list while the initial
  // fetch is in flight - replaces the old centered spinner so the loading
  // state reads as "content incoming" instead of a blank page. Generic
  // (icon badge + 2 text lines + trailing value) rather than mirroring the
  // exact allocation card variants, since the shape is close enough for
  // the transition to feel seamless.
  Widget _buildSkeletonList() {
    return ShimmerLoading(
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Theme.of(context).cardColor,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.black12.withOpacity(0.08),
                  blurRadius: 8,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: const ShimmerBox(height: 38, borderRadius: 12),
          ),
          for (int i = 0; i < 6; i++)
            Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Theme.of(context).cardColor,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black12.withOpacity(0.08),
                    blurRadius: 8,
                    offset: const Offset(0, 3),
                  ),
                ],
                border: Border.all(
                  color: Theme.of(context).dividerColor.withOpacity(0.55),
                ),
              ),
              child: Row(
                children: [
                  const ShimmerBox(width: 38, height: 38, borderRadius: 12),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: const [
                        ShimmerBox(height: 13, width: 140),
                        SizedBox(height: 6),
                        ShimmerBox(height: 11, width: 90),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  const ShimmerBox(height: 15, width: 70),
                ],
              ),
            ),
        ],
      ),
    );
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
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [],
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Theme.of(context).cardColor.withOpacity(0.15),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(
                Icons.visibility_outlined,
                color: Colors.white,
                size: 20,
              ),
            ),

            const SizedBox(width: 12),

            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'View Allocations',
                  style: GoogleFonts.poppins(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
                Text(
                  'Manage allocations',

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
          ? _buildSkeletonList()
          : RefreshIndicator(
              color: primaryColor,
              onRefresh: fetchAllocations,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  return SingleChildScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.all(16),
                    child: filteredAllocations.isEmpty
                        ? ConstrainedBox(
                            constraints: BoxConstraints(
                              minHeight: constraints.maxHeight - 32,
                            ),
                            child: IntrinsicHeight(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  _buildSearchBar(),

                                  const SizedBox(height: 18),

                                  _buildStatsRow(),

                                  const SizedBox(height: 18),

                                  Expanded(child: _emptyState()),
                                ],
                              ),
                            ),
                          )
                        : Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _buildSearchBar(),

                              const SizedBox(height: 18),

                              _buildStatsRow(),

                              const SizedBox(height: 18),

                              ListView.separated(
                                shrinkWrap: true,
                                physics: const NeverScrollableScrollPhysics(),
                                itemCount: filteredAllocations.length,
                                separatorBuilder: (_, __) =>
                                    const SizedBox(height: 14),
                                itemBuilder: (context, index) {
                                  final allocation = filteredAllocations[index];
                                  print(allocation);
                                  return _allocationCard(allocation, index);
                                },
                              ),

                              const SizedBox(height: 90),
                            ],
                          ),
                  );
                },
              ),
            ),

      floatingActionButton: filteredAllocations.isEmpty
          ? null
          : FloatingActionButton.extended(
              backgroundColor: primaryColor,
              elevation: 6,
              onPressed: () {
                Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const VanAllocationScreen(),
                  ),
                );
              },
              icon: const Icon(Icons.add, color: Colors.white),
              label: Text(
                "Create Allocation",
                style: GoogleFonts.poppins(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
    );
  }

  Widget _buildSearchBar() {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        color: Theme.of(context).cardColor,
        boxShadow: [
          BoxShadow(
            color: primaryColor.withOpacity(0.08),
            blurRadius: 22,
            offset: const Offset(0, 10),
          ),
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
        border: Border.all(color: primaryColor.withOpacity(0.14), width: 1.3),
      ),
      child: TextField(
        controller: searchController,
        onChanged: filterAllocations,
        style: GoogleFonts.poppins(
          fontSize: 13.5,
          fontWeight: FontWeight.w500,
          color: Theme.of(context).colorScheme.onSurface,
        ),
        decoration: InputDecoration(
          hintText: 'Search allocations...',
          hintStyle: GoogleFonts.poppins(
            fontSize: 12.8,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
            fontWeight: FontWeight.w400,
          ),

          prefixIcon: Container(
            margin: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: primaryColor.withOpacity(0.10),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(Icons.search_rounded, color: primaryColor, size: 22),
          ),

          suffixIcon: searchController.text.isNotEmpty
              ? IconButton(
                  splashRadius: 20,
                  onPressed: () {
                    searchController.clear();
                    filterAllocations('');
                  },
                  icon: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: Theme.of(context).brightness == Brightness.dark
                          ? Theme.of(
                              context,
                            ).colorScheme.surfaceContainerHighest
                          : Colors.grey.shade100,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.close_rounded,
                      size: 18,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                )
              : null,

          filled: true,
          fillColor: Colors.transparent,

          contentPadding: const EdgeInsets.symmetric(
            horizontal: 20,
            vertical: 20,
          ),

          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(28),
            borderSide: BorderSide.none,
          ),

          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(28),
            borderSide: BorderSide(
              color: primaryColor.withOpacity(0.10),
              width: 1.2,
            ),
          ),

          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(28),
            borderSide: BorderSide(color: primaryColor, width: 1.5),
          ),
        ),
      ),
    );
  }

  Widget _buildStatsRow() {
    return Row(
      children: [
        /*Expanded(
          child: _statCard(
            'Total',
            allocations.length.toString(),
            Icons.list_alt_outlined,
          ),
        ),

        const SizedBox(width: 12),*/
        Expanded(
          child: _statCard(
            "Vehicle's",
            allocations.map((e) => e['godown_name']).toSet().length.toString(),
            Icons.location_on_outlined,
          ),
        ),

        const SizedBox(width: 12),

        Expanded(
          child: _statCard(
            'Users',
            allocations.map((e) => e['user_name']).toSet().length.toString(),
            Icons.people_outline,
          ),
        ),
      ],
    );
  }

  Widget _statCard(String title, String value, IconData icon) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _cardDecoration(),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: primaryColor.withOpacity(0.1),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: primaryColor),
          ),

          const SizedBox(height: 10),

          Text(
            value,
            style: GoogleFonts.poppins(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),

          const SizedBox(height: 4),

          Text(
            title,
            style: GoogleFonts.poppins(
              fontSize: 11,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  Widget _allocationCard(Map<String, dynamic> allocation, int index) {
    final bool isExpanded = expandedCards.contains(index);

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: _cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 24,
                backgroundColor: primaryColor.withOpacity(0.12),
                child: Icon(Icons.person_outline, color: primaryColor),
              ),

              const SizedBox(width: 14),

              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      allocation['name'] ?? '',
                      style: GoogleFonts.poppins(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                    ),

                    const SizedBox(height: 4),

                    Text(
                      allocation['user_name'] ?? '',
                      style: GoogleFonts.poppins(
                        fontSize: 11.5,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),

              PopupMenuButton<String>(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                onSelected: (value) {
                  if (value == 'delete') {
                    showDeleteDialog(allocation);
                  }

                  if (value == 'edit') {
                    Navigator.pushReplacement(
                      context,
                      MaterialPageRoute(
                        builder: (_) =>
                            ModifyVanAllocationScreen(allocation: allocation),
                      ),
                    );
                  }
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'edit', child: Text('Modify')),
                  PopupMenuItem(value: 'delete', child: Text('Delete')),
                ],
              ),
            ],
          ),

          const SizedBox(height: 16),

          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _infoChip(
                Icons.location_on_outlined,
                "Vehicle",
                allocation['godown_name'] ?? '',
              ),
              _infoChip(
                Icons.receipt_long_outlined,
                'D/O Voucher',
                allocation['voucher_type_name'] ?? '',
              ),
              _infoChip(
                Icons.local_shipping_outlined,
                'Bulk',
                parseBoolFlag(allocation['is_bulk']) ? 'Yes' : 'No',
              ),
            ],
          ),

          AnimatedCrossFade(
            firstChild: const SizedBox.shrink(),
            secondChild: Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  _infoChip(
                    Icons.point_of_sale_outlined,
                    'Sales Voucher',
                    allocation['sales_voucher_type'] ?? '',
                  ),
                  _infoChip(
                    Icons.receipt_outlined,
                    'Receipt Voucher',
                    allocation['receipt_voucher_type'] ?? '',
                  ),
                  _infoChip(
                    Icons.account_balance_wallet_outlined,
                    'Sales Ledger',
                    allocation['sales_ledger'] ?? '',
                  ),
                  _infoChip(
                    Icons.payments_outlined,
                    'Cash Ledger',
                    allocation['cash_ledger'] ?? '',
                  ),
                ],
              ),
            ),
            crossFadeState: isExpanded
                ? CrossFadeState.showSecond
                : CrossFadeState.showFirst,
            duration: const Duration(milliseconds: 220),
          ),

          const SizedBox(height: 12),

          Center(
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () {
                setState(() {
                  if (isExpanded) {
                    expandedCards.remove(index);
                  } else {
                    expandedCards.add(index);
                  }
                });
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      isExpanded ? 'View Less' : 'View More',
                      style: GoogleFonts.poppins(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: primaryColor,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Icon(
                      isExpanded
                          ? Icons.keyboard_arrow_up_rounded
                          : Icons.keyboard_arrow_down_rounded,
                      color: primaryColor,
                      size: 20,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _actionButton(
    String title,
    IconData icon,
    Color color, {
    VoidCallback? onTap,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: color, size: 18),

            const SizedBox(width: 6),

            Text(
              title,
              style: GoogleFonts.poppins(
                color: color,
                fontWeight: FontWeight.w600,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _infoChip(IconData icon, String label, String value) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: isDark
            ? Theme.of(
                context,
              ).colorScheme.surfaceContainerHighest.withOpacity(0.5)
            : const Color(0xFFF5F7FA),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: primaryColor),
          const SizedBox(width: 6),
          Text(
            '$label: ',
            style: GoogleFonts.poppins(
              fontSize: 10.5,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w500,
            ),
          ),
          Text(
            value.isEmpty ? '-' : value,
            style: GoogleFonts.poppins(
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
        ],
      ),
    );
  }

  Widget _emptyState() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: _cardDecoration(),
      child: Center(
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                height: 82,
                width: 82,
                decoration: BoxDecoration(
                  color: primaryColor.withOpacity(0.08),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.inbox_outlined,
                  size: 40,
                  color: primaryColor,
                ),
              ),

              const SizedBox(height: 20),

              Text(
                "No Allocations Found",
                textAlign: TextAlign.center,
                style: GoogleFonts.poppins(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),

              const SizedBox(height: 10),

              Text(
                "There are currently no allocations available. Tap the button below to create a new allocation.",
                textAlign: TextAlign.center,
                style: GoogleFonts.poppins(
                  fontSize: 13,
                  height: 1.5,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),

              const SizedBox(height: 24),

              ElevatedButton.icon(
                onPressed: () {
                  Navigator.pushReplacement(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const VanAllocationScreen(),
                    ),
                  );
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: primaryColor,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 14,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                icon: const Icon(Icons.add_rounded, color: Colors.white),
                label: Text(
                  "Create Allocation",
                  style: GoogleFonts.poppins(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
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
