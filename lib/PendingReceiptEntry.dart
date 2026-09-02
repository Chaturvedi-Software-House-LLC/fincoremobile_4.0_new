import 'package:FincoreGo/Dashboard.dart';
import 'package:FincoreGo/ReceiptRegistration.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'constants.dart';
import 'widgets/entry_widgets.dart';
import 'ModifyReceiptEntry.dart';
import 'package:FincoreGo/widgets/app_bottom_nav.dart';
import 'package:FincoreGo/widgets/app_navigation.dart';
import 'providers/pending_receipt_entry_notifier.dart';

/// A row from tally-api's `VoucherEntry` family (see
/// `voucher_entry_repository.dart`), reshaped to the same
/// id/data/type/isSynced/message shape this screen already used for the
/// legacy backend so the rest of the widget tree (search, date filters,
/// card rendering, edit/delete) needed no changes.
///
/// **"Pending" mapping**: the legacy `getEntries` endpoint returned only
/// this company/serial's not-yet-synced receipt entries. tally-api's
/// `VoucherEntry` table has no outbound-push-to-Tally job yet (see this
/// repo's `voucher_entry_repository.dart` doc-comment), so every
/// `VoucherEntry` is, by definition, still pending - there is no
/// `syncedAt`/`syncError` filter to apply here. [isSynced] is therefore
/// always `0` (unsynced) and [message] always `null`; every entry stays
/// actionable (edit/delete), matching "pending == not yet pushed to
/// Tally" for this backend.
class ReceiptModel {
  final String id;
  final Map<String, dynamic> data;
  final String type;
  final int isSynced;
  final String? message;

  ReceiptModel({
    required this.id,
    required this.data,
    required this.type,
    required this.isSynced,
    this.message,
  });
}

class PendingReceiptEntry extends ConsumerStatefulWidget {
  const PendingReceiptEntry({Key? key}) : super(key: key);
  @override
  ConsumerState<PendingReceiptEntry> createState() =>
      _PendingReceiptEntryPageState();
}

class _PendingReceiptEntryPageState
    extends ConsumerState<PendingReceiptEntry>
    with TickerProviderStateMixin {
  PendingReceiptEntryNotifier get _notifier =>
      ref.read(pendingReceiptEntryNotifierProvider.notifier);
  PendingReceiptEntryState get _s => ref.read(pendingReceiptEntryNotifierProvider);

  final Set<String> expandedCards = {};

  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  TextEditingController _searchController = TextEditingController();

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


  Future<void> entrydelete(String id) async {
    final error = await _notifier.entrydelete(id);
    if (error != null) showAppMessage(context, error);
  }

  /// The party ledger entry among a voucher entry's `ledgerEntries` - kept
  /// widget-local too (pure function, also called directly by `build()`).
  Map<String, dynamic>? _partyLedgerEntry(Map<String, dynamic> data) {
    final List<dynamic> ledgerEntries =
        (data['ledgerEntries'] as List<dynamic>?) ?? const [];
    for (final entry in ledgerEntries) {
      if (entry is Map<String, dynamic> && entry['isPartyLedger'] == true) {
        return entry;
      }
    }
    return ledgerEntries.isNotEmpty
        ? ledgerEntries.first as Map<String, dynamic>
        : null;
  }

  /// Widget-side wrapper - the fetch/filter/sort logic moved verbatim into
  /// `PendingReceiptEntryNotifier.fetchReceiptEntries`.
  Future<void> fetchReceiptEntries() async {
    final error = await _notifier.fetchReceiptEntries();
    if (error != null) showAppMessage(context, error);
    FocusManager.instance.primaryFocus?.unfocus();
    _searchController.clear();
  }

  void searchReceipt(String query) {
    _notifier.searchReceipt(query);
  }

  Future<void> _pickSingleDate() async {
    FocusManager.instance.primaryFocus?.unfocus();

    final pickedDate = await showDatePicker(
      context: context,
      initialDate: _s.selectedSingleDate ?? DateTime.now(),
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
      _notifier.setSingleDateFilter(pickedDate);
    }
  }

  Future<void> _pickDateRange() async {
    FocusManager.instance.primaryFocus?.unfocus();

    final pickedRange = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
      initialDateRange: _s.selectedDateRange,
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
      _notifier.setDateRangeFilter(pickedRange);
    }
  }

  void _clearDateFilter() {
    _notifier.clearDateFilter();
  }

  String _getDateFilterText() {
    final selectedSingleDate = _s.selectedSingleDate;
    final selectedDateRange = _s.selectedDateRange;
    if (selectedSingleDate != null) {
      return DateFormat("dd-MMM-yyyy").format(selectedSingleDate);
    }

    if (selectedDateRange != null) {
      final start = DateFormat("dd-MMM").format(selectedDateRange.start);
      final end = DateFormat("dd-MMM-yyyy").format(selectedDateRange.end);
      return "$start to $end";
    }

    return "All Dates";
  }

  Widget _buildDateFilterSection() {
    final selectedSingleDate = _s.selectedSingleDate;
    final selectedDateRange = _s.selectedDateRange;
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

  @override
  void initState() {
    super.initState();
    // Trigger provider creation (and its _init()) eagerly, matching the
    // original's initState-time kickoff.
    _notifier;
  }

  Future<void> _refresh() async {
    setState(() {
      fetchReceiptEntries();
    });
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(pendingReceiptEntryNotifierProvider);
    final vm = _s;
    final receiptentries = vm.receiptEntries;
    final filteredReceiptEntries = vm.filteredReceiptEntries;
    final isVisibleNoReceiptEntryFound = vm.isVisibleNoReceiptEntryFound;
    final _isLoading = vm.isLoading;
    final serial_no = vm.serialNo;
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
          activeEntryType: AppEntryType.receipt,
        ),
        key: _scaffoldKey,
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        appBar: entryAppBar(
          context: context,
          title: "Receipt Entries",
          onBack: () => AppNavigation.backOrDashboard(context),
        ),
        body: RefreshIndicator(
          onRefresh: _refresh,
          child: Column(
            children: [
              if (receiptentries.isNotEmpty)
                EntrySearchBar(
                  controller: _searchController,
                  onChanged: searchReceipt,
                  hintText: "Search receipt entries...",
                ),
              if (receiptentries.isNotEmpty) _buildDateFilterSection(),
              Expanded(
                child: Stack(
                  children: [
                    if (isVisibleNoReceiptEntryFound)
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
                                'No Receipt Entry Found',
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

                    if (!isVisibleNoReceiptEntryFound)
                      ListView.builder(
                        padding: const EdgeInsets.fromLTRB(0, 8, 0, 100),
                        itemCount: filteredReceiptEntries.length,
                        itemBuilder: (context, index) {
                          final card = filteredReceiptEntries[index];
                          final partyEntry = _partyLedgerEntry(card.data);
                          final partyLedger = partyEntry?['ledgerName'];
                          final dateStr = card.data['date'];
                          final vchno = card.data['voucherNumber'];
                          final vchtype =
                              card.data['voucherTypeName'] ?? 'N/A';
                          final totalAmount = partyEntry?['amount'];
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
                            errorMessage:
                                (card.isSynced == 2 && card.message != null)
                                ? card.message
                                : null,
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
                                        builder: (context) =>
                                            ModifyReceiptEntry(
                                              voucherEntryId: card.id,
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
                                      card.id,
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
                              builder: (context) => ReceiptRegistration(),
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

  Color _getValueColor(BuildContext context) {
    if (label.toLowerCase().contains('amount')) {
      if (value.toLowerCase().contains("dr") || value.startsWith("-")) {
        return Colors.red.shade700;
      } else {
        return Colors.green.shade700;
      }
    }
    return Theme.of(context).colorScheme.onSurface;
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
