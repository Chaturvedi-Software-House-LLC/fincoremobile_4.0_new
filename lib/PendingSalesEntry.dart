import 'dart:convert';
import 'package:FincoreGo/Dashboard.dart';
import 'package:FincoreGo/ModifySalesEntry.dart';
import 'package:FincoreGo/SalesRegistration.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'constants.dart';
import 'widgets/entry_widgets.dart';
import 'currencyFormat.dart';
import 'package:FincoreGo/widgets/app_bottom_nav.dart';
import 'package:FincoreGo/widgets/app_navigation.dart';
import 'api/api_exception.dart';
import 'api/voucher_entry_repository.dart';
import 'api/voucher_type_repository.dart';

/// One row of `VoucherEntryRepository.instance.listAll()`, shaped for this
/// screen. tally-api's `VoucherEntry` primary key is a String UUID (not the
/// legacy backend's int autoincrement id) - [entryId] carries that real id
/// for repository calls (delete), while [id] is a synthetic, stable-per-row
/// int (derived from [entryId]) kept only because both this screen's
/// `expandedCards` Set<int> and ModifySalesEntry's current (not yet
/// migrated as of this pass) constructor still expect an int id. [data]
/// carries the full tally-api VoucherEntry map plus the legacy-named
/// display keys ('DATE'/'VOUCHERNUMBER'/'PARTYLEDGERNAME'/'totalAmount'/
/// 'VOUCHERTYPENAME') this screen's own rendering code reads.
///
/// tally-api has no outbound-push-to-Tally job yet (see
/// `voucher_entry_repository.dart`'s doc-comment), so `syncedAt` is always
/// null today - every entry is therefore "pending" by definition, matching
/// this screen's original "pending sales entries" purpose. [isSynced] is
/// still derived from `syncedAt` (rather than hardcoded) so this keeps
/// working once that job ships. There is no "sync error" status distinct
/// from "unsynced" in the new backend (no 3rd state like the legacy `2`) -
/// [message] (from `syncError`) is shown whenever present, regardless of
/// [isSynced].
class SalesModel {
  final String entryId;
  final int id;
  final Map<String, dynamic> data;
  final String type;
  final int isSynced;
  final String? message;

  SalesModel({
    required this.entryId,
    required this.id,
    required this.data,
    required this.type,
    required this.isSynced,
    this.message,
  });

  factory SalesModel.fromVoucherEntry(Map<String, dynamic> json) {
    final String entryId = json['id'].toString();

    final List<dynamic> ledgerEntries =
        (json['ledgerEntries'] as List<dynamic>?) ?? const [];

    Map<String, dynamic>? partyLedgerEntry;
    for (final e in ledgerEntries) {
      if (e is Map && e['isPartyLedger'] == true) {
        partyLedgerEntry = Map<String, dynamic>.from(e);
        break;
      }
    }

    final String partyLedgerName =
        (partyLedgerEntry?['ledgerName'] ?? '').toString();

    final num totalAmount = partyLedgerEntry != null
        ? (num.tryParse(partyLedgerEntry['amount'].toString()) ?? 0).abs()
        : 0;

    final data = Map<String, dynamic>.from(json);
    data['DATE'] = json['date'];
    data['VOUCHERNUMBER'] = json['voucherNumber'] ?? '';
    data['VOUCHERTYPENAME'] = json['voucherTypeName'] ?? '';
    data['PARTYLEDGERNAME'] = partyLedgerName;
    data['totalAmount'] = totalAmount;

    return SalesModel(
      entryId: entryId,
      id: entryId.hashCode,
      data: data,
      type: 'sales',
      isSynced: json['syncedAt'] != null ? 1 : 0,
      message: json['syncError']?.toString(),
    );
  }
}

class PendingSalesEntry extends StatefulWidget {
  const PendingSalesEntry({Key? key}) : super(key: key);
  @override
  _PendingSalesEntryPageState createState() => _PendingSalesEntryPageState();
}

class _PendingSalesEntryPageState extends State<PendingSalesEntry>
    with TickerProviderStateMixin {
  bool isDashEnable = true,
      isRolesVisible = true,
      isUserEnable = true,
      isUserVisible = true,
      isRolesEnable = true,
      _isLoading = false,
      isVisibleNoSalesEntryFound = false;

  String rolename_fetched = "";

  final List<SalesModel> salesentries = [];
  DateTime? selectedSingleDate;
  DateTimeRange? selectedDateRange;

  TextEditingController _searchController = TextEditingController();

  List<SalesModel> filteredSalesEntries = [];

  String name = "", email = "";

  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  late SharedPreferences prefs;

  String? hostname = "",
      company = "",
      company_lowercase = "",
      serial_no = "",
      username = "",
      HttpURL = "",
      SecuritybtnAcessHolder = "";

  final Set<int> expandedCards = {};

  bool get isVanSalesSerial {
    final currentSerial = serial_no?.trim().toLowerCase();

    if (currentSerial == null || currentSerial.isEmpty) {
      return false;
    }

    return vanSalesSerialNo.any((s) => s.trim().toLowerCase() == currentSerial);
  }

  Future<void> _initSharedPreferences() async {
    prefs = await SharedPreferences.getInstance();

    setState(() {
      hostname = prefs.getString('hostname');
      company = prefs.getString('company_name');
      company_lowercase = company!.replaceAll(' ', '').toLowerCase();
      serial_no = prefs.getString('serial_no');
      username = prefs.getString('username');

      SecuritybtnAcessHolder = prefs.getString('secbtnaccess');

      String? email_nav = prefs.getString('email_nav');
      String? name_nav = prefs.getString('name_nav');

      if (email_nav != null && name_nav != null) {
        name = name_nav;

        email = email_nav;
      }

      if (SecuritybtnAcessHolder == "True") {
        isRolesVisible = true;
        isUserVisible = true;
      } else {
        isRolesVisible = false;
        isUserVisible = false;
      }
    });
    fetchSalesEntries();
  }

  Future<void> _showConfirmationDialogAndNavigate(
    BuildContext context,
    String id,
  ) async {
    await showGeneralDialog(
      context: context,
      barrierDismissible: false,
      barrierLabel: '',
      transitionDuration: const Duration(milliseconds: 300),
      pageBuilder: (ctx, anim1, anim2) {
        return const SizedBox.shrink(); // required
      },
      transitionBuilder: (ctx, anim1, anim2, child) {
        final curvedValue = Curves.easeInOut.transform(anim1.value);

        return Transform.scale(
          scale: curvedValue,
          child: AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(22),
            ),
            backgroundColor: Theme.of(context).scaffoldBackgroundColor,
            elevation: 8,
            titlePadding: const EdgeInsets.fromLTRB(20, 20, 20, 10),
            contentPadding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
            actionsPadding: const EdgeInsets.only(bottom: 12, right: 12),

            title: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Colors.red.shade400, Colors.red.shade700],
                    ),
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.red.withOpacity(0.25),
                        blurRadius: 6,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.delete_outline,
                    color: Colors.white,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  "Confirm Deletion",
                  style: GoogleFonts.poppins(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
              ],
            ),

            content: Text(
              "Do you really want to delete this entry?",
              style: GoogleFonts.poppins(
                fontSize: 14,
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),

            actions: [
              // ❌ Cancel Button
              TextButton(
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 10,
                  ),
                ),
                onPressed: () => Navigator.of(context).pop(),
                child: Text(
                  "No",
                  style: GoogleFonts.poppins(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ),

              // ✅ Confirm Button
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 10,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  elevation: 0,
                  backgroundColor: Colors.red,
                ),
                onPressed: () {
                  Navigator.of(context).pop();
                  entrydelete(id);
                },
                child: Text(
                  "Yes",
                  style: GoogleFonts.poppins(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> entrydelete(String entryId) async {
    setState(() {
      _isLoading = true;
    });

    try {
      await VoucherEntryRepository.instance.remove(entryId);
      showAppMessage(context, "Entry deleted successfully");
      await fetchSalesEntries();
    } on ApiException catch (e) {
      showAppMessage(context, e.message);
      setState(() {
        _isLoading = false;
      });
    } catch (e) {
      showAppMessage(context, 'Server Error!!!');
      setState(() {
        _isLoading = false;
      });
    }
  }

  // Pulls every voucher entry for the active company from tally-api
  // (`VoucherEntryRepository.listAll()`), then filters client-side to the
  // Sales voucher type(s) (matched on `reservedName == 'SALES'`, the same
  // stable-identifier rationale tally-api's own report queries use - see
  // its CLAUDE.md) rather than a `type=sales` query param, since tally-api
  // has no such filter on `voucher-entries`. If a company-specific Sales
  // voucher type NAME is configured (the legacy `spectra_allocations` ->
  // `sales_voucher_type` override, previously sent as `vchName=`), that
  // name is applied as an extra client-side filter, same as before.
  //
  // "Pending" in the legacy backend meant "not yet pushed to Tally"
  // (`isSynced`/`vchName` query params). tally-api has no outbound-push-to-
  // -Tally job yet (see `voucher_entry_repository.dart`), so `syncedAt` is
  // always null and every entry returned here is, today, pending by
  // definition - there is no separate "pending only" filter to apply.
  Future<void> fetchSalesEntries() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final prefs = await SharedPreferences.getInstance();

      String? voucherTypeName;

      final String? spectraAllocationsString = prefs.getString(
        'spectra_allocations',
      );

      if (spectraAllocationsString != null &&
          spectraAllocationsString.isNotEmpty) {
        final List<dynamic> spectraAllocations = jsonDecode(
          spectraAllocationsString,
        );

        if (spectraAllocations.isNotEmpty) {
          voucherTypeName = spectraAllocations.first['sales_voucher_type'];
        }
      }

      final salesVoucherTypes = await VoucherTypeRepository.instance
          .byReservedName('SALES');

      final Set<int> salesVoucherTypeMasterIds = salesVoucherTypes
          .map<int>((v) => (v['masterId'] as num).toInt())
          .toSet();

      final allEntries = await VoucherEntryRepository.instance.listAll();

      final bool hasVoucherTypeNameFilter =
          voucherTypeName != null && voucherTypeName.trim().isNotEmpty;

      final mapped = allEntries
          .where(
            (json) => salesVoucherTypeMasterIds.contains(
              json['voucherTypeMasterId'],
            ),
          )
          .map((json) => SalesModel.fromVoucherEntry(json))
          .where(
            (m) =>
                !hasVoucherTypeNameFilter ||
                (m.data['VOUCHERTYPENAME'] ?? '').toString() ==
                    voucherTypeName,
          )
          .toList();

      salesentries.clear();
      filteredSalesEntries.clear();

      isVisibleNoSalesEntryFound = false;

      salesentries.addAll(mapped);

      salesentries.sort((a, b) {
        DateTime dateA = DateTime.parse(a.data['DATE'].toString());
        DateTime dateB = DateTime.parse(b.data['DATE'].toString());
        if (dateA != dateB) return dateB.compareTo(dateA);
        final vchA =
            int.tryParse((a.data['VOUCHERNUMBER'] ?? '').toString()) ?? 0;
        final vchB =
            int.tryParse((b.data['VOUCHERNUMBER'] ?? '').toString()) ?? 0;
        return vchB.compareTo(vchA);
      });

      filteredSalesEntries = List.from(salesentries);

      setState(() {
        FocusManager.instance.primaryFocus?.unfocus();
        _searchController.clear();
        selectedSingleDate = null;
        selectedDateRange = null;

        if (filteredSalesEntries.isEmpty) {
          isVisibleNoSalesEntryFound = true;
        }

        _isLoading = false;
      });
    } on ApiException catch (e) {
      showAppMessage(context, e.message);

      setState(() {
        if (filteredSalesEntries.isEmpty) {
          isVisibleNoSalesEntryFound = true;
        }

        _isLoading = false;
      });
    } catch (e) {
      print(e);

      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  void initState() {
    super.initState();
    _initSharedPreferences();
  }

  void searchSales(String query) {
    _applyFilters();
  }

  void _applyFilters() {
    final query = _searchController.text.trim().toLowerCase();

    setState(() {
      filteredSalesEntries = salesentries.where((entry) {
        final data = entry.data;

        final party = (data['PARTYLEDGERNAME'] ?? '').toString().toLowerCase();
        final vchno = (data['VOUCHERNUMBER'] ?? '').toString().toLowerCase();
        final vchtype = (data['VOUCHERTYPENAME'] ?? '')
            .toString()
            .toLowerCase();
        final amount = (data['totalAmount'] ?? '').toString().toLowerCase();

        final bool matchesSearch =
            query.isEmpty ||
            party.contains(query) ||
            vchno.contains(query) ||
            vchtype.contains(query) ||
            amount.contains(query);

        final bool matchesDate = _matchesDateFilter(entry);

        return matchesSearch && matchesDate;
      }).toList();

      isVisibleNoSalesEntryFound = filteredSalesEntries.isEmpty;
    });
  }

  Future<void> _pickSingleDate() async {
    FocusManager.instance.primaryFocus?.unfocus();

    final pickedDate = await showDatePicker(
      context: context,
      initialDate: selectedSingleDate ?? DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
      builder: (context, child) {
        final isDark = Theme.of(context).brightness == Brightness.dark;
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: isDark
                ? ColorScheme.dark(
                    primary: app_color,
                    onPrimary: Colors.white,
                    surface: const Color(0xFF1F2937),
                    onSurface: Theme.of(context).colorScheme.onSurface,
                  )
                : ColorScheme.light(
                    primary: app_color,
                    onPrimary: Colors.white,
                    onSurface: Theme.of(context).colorScheme.onSurface,
                  ),
            textButtonTheme: TextButtonThemeData(
              style: TextButton.styleFrom(foregroundColor: app_color),
            ),
          ),
          child: child!,
        );
      },
    );

    if (pickedDate != null) {
      setState(() {
        selectedSingleDate = pickedDate;
        selectedDateRange = null;
      });

      _applyFilters();
    }
  }

  Future<void> _pickDateRange() async {
    FocusManager.instance.primaryFocus?.unfocus();

    final pickedRange = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
      initialDateRange: selectedDateRange,
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: ColorScheme.light(
              primary: app_color,
              onPrimary: Colors.white,
              surface: Theme.of(context).colorScheme.surface,
              onSurface: Theme.of(context).colorScheme.onSurface,
            ),
            datePickerTheme: DatePickerThemeData(
              backgroundColor: Theme.of(context).scaffoldBackgroundColor,
              headerBackgroundColor: app_color,
              headerForegroundColor: Colors.white,
              rangeSelectionBackgroundColor: app_color.withOpacity(0.14),
              dayShape: WidgetStateProperty.resolveWith<OutlinedBorder?>((
                states,
              ) {
                if (states.contains(WidgetState.selected)) {
                  return const CircleBorder();
                }
                return null;
              }),
              dayForegroundColor: WidgetStateProperty.resolveWith<Color?>((
                states,
              ) {
                if (states.contains(WidgetState.selected)) {
                  return Colors.white;
                }
                if (states.contains(WidgetState.disabled)) {
                  return Colors.grey.shade400;
                }
                return Theme.of(context).colorScheme.onSurface;
              }),
              dayBackgroundColor: WidgetStateProperty.resolveWith<Color?>((
                states,
              ) {
                if (states.contains(WidgetState.selected)) {
                  return app_color;
                }
                return null;
              }),
              todayForegroundColor: WidgetStateProperty.resolveWith<Color?>((
                states,
              ) {
                if (states.contains(WidgetState.selected)) {
                  return Colors.white;
                }
                return app_color;
              }),
              todayBackgroundColor: WidgetStateProperty.resolveWith<Color?>((
                states,
              ) {
                if (states.contains(WidgetState.selected)) {
                  return app_color;
                }
                return Colors.transparent;
              }),
            ),
            textButtonTheme: TextButtonThemeData(
              style: TextButton.styleFrom(foregroundColor: app_color),
            ),
          ),
          child: child!,
        );
      },
    );

    if (pickedRange != null) {
      setState(() {
        selectedDateRange = pickedRange;
        selectedSingleDate = null;
      });

      _applyFilters();
    }
  }

  void _clearDateFilter() {
    setState(() {
      selectedSingleDate = null;
      selectedDateRange = null;
    });

    _applyFilters();
  }

  String _getDateFilterText() {
    if (selectedSingleDate != null) {
      return DateFormat("dd-MMM-yyyy").format(selectedSingleDate!);
    }

    if (selectedDateRange != null) {
      final start = DateFormat("dd-MMM").format(selectedDateRange!.start);
      final end = DateFormat("dd-MMM-yyyy").format(selectedDateRange!.end);
      return "$start to $end";
    }

    return "All Dates";
  }

  bool _matchesDateFilter(SalesModel entry) {
    final dateValue = entry.data['DATE'];

    if (dateValue == null) return false;

    final entryDate = DateTime.tryParse(dateValue.toString());

    if (entryDate == null) return false;

    final onlyEntryDate = DateTime(
      entryDate.year,
      entryDate.month,
      entryDate.day,
    );

    if (selectedSingleDate != null) {
      final selected = DateTime(
        selectedSingleDate!.year,
        selectedSingleDate!.month,
        selectedSingleDate!.day,
      );

      return onlyEntryDate == selected;
    }

    if (selectedDateRange != null) {
      final start = DateTime(
        selectedDateRange!.start.year,
        selectedDateRange!.start.month,
        selectedDateRange!.start.day,
      );

      final end = DateTime(
        selectedDateRange!.end.year,
        selectedDateRange!.end.month,
        selectedDateRange!.end.day,
      );

      return onlyEntryDate.isAtSameMomentAs(start) ||
          onlyEntryDate.isAtSameMomentAs(end) ||
          (onlyEntryDate.isAfter(start) && onlyEntryDate.isBefore(end));
    }

    return true;
  }

  Widget _buildDateFilterSection() {
    final bool hasDateFilter =
        selectedSingleDate != null || selectedDateRange != null;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: Theme.of(context).dividerColor),
          boxShadow: [
            BoxShadow(
              color: isDark
                  ? Colors.black.withValues(alpha: 0.3)
                  : Colors.black.withValues(alpha: 0.06),
              blurRadius: 16,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [app_color.withValues(alpha: 0.8), app_color],
                    ),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.calendar_month_rounded,
                    color: Colors.white,
                    size: 18,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    _getDateFilterText(),
                    style: GoogleFonts.poppins(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                ),
                if (hasDateFilter)
                  GestureDetector(
                    onTap: _clearDateFilter,
                    child: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: Colors.red.withValues(alpha: 0.1),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.close_rounded,
                        size: 16,
                        color: Colors.red.shade600,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _buildFilterButton(
                    icon: Icons.today_rounded,
                    text: "Single Date",
                    isSelected: selectedSingleDate != null,
                    onTap: _pickSingleDate,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _buildFilterButton(
                    icon: Icons.date_range_rounded,
                    text: "Date Range",
                    isSelected: selectedDateRange != null,
                    onTap: _pickDateRange,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterButton({
    required IconData icon,
    required String text,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 11),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          gradient: isSelected
              ? LinearGradient(
                  colors: [app_color.withValues(alpha: 0.85), app_color],
                )
              : null,
          color: isSelected
              ? null
              : (Theme.of(context).brightness == Brightness.dark
                    ? Theme.of(context).colorScheme.surfaceContainerHighest
                    : Colors.grey.shade50),
          border: Border.all(
            color: isSelected ? app_color : Colors.grey.shade200,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 17, color: isSelected ? Colors.white : app_color),
            const SizedBox(width: 7),
            Flexible(
              child: Text(
                text,
                style: GoogleFonts.poppins(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: isSelected
                      ? Colors.white
                      : Theme.of(context).colorScheme.onSurface,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _refresh() async {
    setState(() {
      fetchSalesEntries();
    });
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => Dashboard()),
        );
        return true;
      },
      child: Scaffold(
        bottomNavigationBar: const AppBottomNav(
          activeTab: AppBottomNavTab.entries,
          activeEntryType: AppEntryType.sales,
        ),
        key: _scaffoldKey,
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        appBar: entryAppBar(
          context: context,
          title: "Sales Entries",
          onBack: () => AppNavigation.backOrDashboard(context),
        ),
        body: RefreshIndicator(
          onRefresh: _refresh,
          child: Column(
            children: [
              if (salesentries.isNotEmpty)
                EntrySearchBar(
                  controller: _searchController,
                  onChanged: searchSales,
                  hintText: "Search sales entries...",
                ),
              if (salesentries.isNotEmpty) _buildDateFilterSection(),
              Expanded(
                child: Stack(
                  children: [
                    if (isVisibleNoSalesEntryFound)
                      Center(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.receipt_long,
                                size: 64,
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurfaceVariant,
                              ),
                              const SizedBox(height: 16),
                              Text(
                                'No Sales Entry Found',
                                textAlign: TextAlign.center,
                                style: GoogleFonts.poppins(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w500,
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),

                    if (!isVisibleNoSalesEntryFound)
                      ListView.builder(
                        padding: const EdgeInsets.fromLTRB(0, 8, 0, 100),
                        itemCount: filteredSalesEntries.length,
                        itemBuilder: (context, index) {
                          final card = filteredSalesEntries[index];
                          final partyLedger = card.data['PARTYLEDGERNAME'];
                          final dateStr = card.data['DATE'];
                          final totalAmount = card.data['totalAmount'];
                          final vchno = card.data['VOUCHERNUMBER'];
                          final vchtype = card.data['VOUCHERTYPENAME'] ?? 'N/A';
                          final bool isExpanded = expandedCards.contains(
                            card.id,
                          );

                          DateTime date = DateTime.parse(dateStr);
                          String formattedDate = DateFormat(
                            "dd-MMM-yyyy",
                          ).format(date);

                          final bool canActOnCard =
                              card.isSynced != 1 &&
                              (serial_no != uniGasSerialNumber);

                          return PendingEntryCard(
                            voucherNo: '$vchno',
                            date: formattedDate,
                            partyName: partyLedger,
                            amount: totalAmount.toString(),
                            isSynced: card.isSynced == 1,
                            errorMessage: card.message,
                            isExpanded: isExpanded,
                            onTap: () {
                              setState(() {
                                isExpanded
                                    ? expandedCards.remove(card.id)
                                    : expandedCards.add(card.id);
                              });
                            },
                            onEdit: canActOnCard
                                ? () {
                                    Navigator.pushReplacement(
                                      context,
                                      MaterialPageRoute(
                                        builder: (context) => ModifySalesEntry(
                                          type: card.type,
                                          id: card.entryId,
                                          isSynced: card.isSynced,
                                          data: card.data,
                                        ),
                                      ),
                                    );
                                  }
                                : null,
                            onDelete: canActOnCard
                                ? () {
                                    _showConfirmationDialogAndNavigate(
                                      context,
                                      card.entryId,
                                    );
                                  }
                                : null,
                            expandedContent: [
                              DetailRowTile(
                                label: "Voucher Type",
                                value: vchtype,
                              ),
                            ],
                          );
                        },
                      ),

                    // Loading spinner
                    if (_isLoading)
                      Positioned.fill(
                        child: Container(
                          color: Theme.of(context).scaffoldBackgroundColor,
                          child: _buildSkeletonList(),
                        ),
                      ),

                    // Floating Action Button
                    Positioned(
                      bottom: 40,
                      right: 30,
                      child: GestureDetector(
                        onTap: () {
                          Navigator.pushReplacement(
                            context,
                            MaterialPageRoute(
                              builder: (context) => SalesRegistration(),
                            ),
                          );
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 22,
                            vertical: 14,
                          ),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(16),
                            gradient: LinearGradient(
                              colors: [
                                app_color.withValues(alpha: 0.9),
                                app_color,
                              ],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: app_color.withValues(alpha: 0.4),
                                blurRadius: 12,
                                offset: const Offset(0, 6),
                              ),
                            ],
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.add_rounded,
                                color: Colors.white,
                                size: 26,
                              ),
                              const SizedBox(width: 10),
                              Text(
                                "Create",
                                style: GoogleFonts.poppins(
                                  color: Colors.white,
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                  letterSpacing: 0.5,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // Skeleton stand-in for the pending entry list while the initial fetch is
  // in flight - mirrors the PendingEntryCard row shape (badge + voucher/party
  // lines + date/amount) so the loading state reads as "content incoming".
  Widget _buildSkeletonList() {
    return ShimmerLoading(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 100),
        children: [
          for (int i = 0; i < 7; i++)
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
                      children: [
                        const ShimmerBox(height: 13, width: 150),
                        const SizedBox(height: 6),
                        const ShimmerBox(height: 11, width: 100),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      const ShimmerBox(height: 13, width: 70),
                      const SizedBox(height: 6),
                      const ShimmerBox(height: 11, width: 50),
                    ],
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class DetailRowTile extends StatelessWidget {
  final String label;
  final String value;
  final VoidCallback? onTap;

  const DetailRowTile({
    required this.label,
    required this.value,
    this.onTap,
    super.key,
  });

  // Gradient chooser
  LinearGradient _getGradient(String label) {
    final lower = label.toLowerCase();
    if (lower.contains('date')) {
      return LinearGradient(
        colors: [Colors.indigo.shade400, Colors.indigo.shade700],
      );
    } else if (lower.contains('voucher')) {
      return LinearGradient(
        colors: [Colors.orange.shade400, Colors.deepOrange.shade600],
      );
    } else if (lower.contains('amount')) {
      return LinearGradient(
        colors: [Colors.green.shade400, Colors.green.shade700],
      );
    } else if (lower.contains('party')) {
      return LinearGradient(
        colors: [Colors.blue.shade400, Colors.blue.shade700],
      );
    }
    return LinearGradient(colors: [Colors.grey.shade400, Colors.grey.shade600]);
  }

  // Icon chooser
  IconData _getIcon(String label) {
    final lower = label.toLowerCase();
    if (lower.contains('date')) {
      return Icons.calendar_today_rounded;
    } else if (lower.contains('voucher')) {
      return Icons.receipt_long_rounded;
    } else if (lower.contains('amount')) {
      return Icons.attach_money_rounded;
    } else if (lower.contains('party')) {
      return Icons.person_outline;
    }
    return Icons.info_outline;
  }

  // Amount color logic
  Color _getValueColor(BuildContext context) {
    if (label.toLowerCase().contains('amount')) {
      if (value.toLowerCase().contains("dr") || value.startsWith("-")) {
        return Colors.red.shade700; // Debit
      } else {
        return Colors.green.shade700; // Credit
      }
    }
    return Theme.of(context).colorScheme.onSurface; // Normal
  }

  @override
  Widget build(BuildContext context) {
    final gradient = _getGradient(label);
    final icon = _getIcon(label);

    final row = Container(
      margin: const EdgeInsets.symmetric(vertical: 2, horizontal: 8),
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
      decoration: BoxDecoration(
        color: Theme.of(context).brightness == Brightness.dark
            ? const Color(0xFF1F2937)
            : Colors.grey.shade50,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // 🔹 Gradient Icon
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              gradient: gradient,
              borderRadius: BorderRadius.circular(10),
              boxShadow: [
                BoxShadow(
                  color: gradient.colors.last.withOpacity(0.25),
                  blurRadius: 6,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: Icon(icon, size: 16, color: Colors.white),
          ),
          const SizedBox(width: 12),

          // 🔹 Label (Left Half)
          Expanded(
            flex: 1,
            child: Text(
              label,
              style: GoogleFonts.poppins(
                fontSize: 13.5,
                color: Theme.of(context).colorScheme.onSurface,
              ),
              softWrap: true,
              overflow: TextOverflow.visible,
            ),
          ),

          // 🔹 Value (Right Half)
          Expanded(
            flex: 1,
            child: Text(
              value,
              style: GoogleFonts.poppins(
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
                color: _getValueColor(context),
              ),
              textAlign: TextAlign.right,
              softWrap: true,
              overflow: TextOverflow.visible,
            ),
          ),
        ],
      ),
    );

    return onTap != null ? GestureDetector(onTap: onTap, child: row) : row;
  }
}
