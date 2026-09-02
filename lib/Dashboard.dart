import 'dart:io';
import 'dart:ui';
import 'package:FincoreGo/PendingDeliveryNoteEntry.dart';
import 'package:FincoreGo/l10n/app_localizations.dart';
import 'package:FincoreGo/widgets/app_bottom_nav.dart';
import 'package:FincoreGo/DashboardClicked.dart';
import 'package:FincoreGo/PendingReceiptEntry.dart';
import 'package:FincoreGo/PendingSalesEntry.dart';
import 'package:FincoreGo/utils/number_formatter.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'utils/currency_helper.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'DashboardAnalytics.dart';
import 'PendingSalesOrderEntry.dart';
import 'CompanySelectTallyOauth.dart';
import 'constants.dart';
import 'package:url_launcher/url_launcher.dart';
import 'widgets/entry_widgets.dart';
import 'providers/dashboard_notifier.dart';

List<String> months_chart = [];
List<String> months_chart_line_graph = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

List<Map<String, dynamic>> data = [];

List<dynamic> piechartsaleslist = [];
List<dynamic> piechartpurchaselist = [];

class Dashboard extends ConsumerStatefulWidget {
  const Dashboard({Key? key}) : super(key: key);
  @override
  ConsumerState<Dashboard> createState() => _MyHomePageState();
}

class _MyHomePageState extends ConsumerState<Dashboard>
    with TickerProviderStateMixin {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  late GlobalKey<ScaffoldMessengerState> _scaffoldMessengerKey;

  // Local UI-only state for the custom date-range pickers - not read by
  // build(), only used as fallback seed values for showDateRangePicker in
  // the _selectDateRange*/refresh/auto helpers below.
  DateTime _startDate = DateTime.now();
  DateTime _endDate = DateTime.now().add(Duration(days: 7));

  DashboardState get _s => ref.read(dashboardNotifierProvider);
  DashboardNotifier get _notifier =>
      ref.read(dashboardNotifierProvider.notifier);

  List<String> date_range = [
    'Today',
    'Yesterday',
    'This Month',
    'Last Month',
    'This Year',
    'Last Year',
    'Year To Date',
    'Custom Date',
  ];

  void _showEntriesBottomSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      builder: (context) {
        return SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 12, 18, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 42,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 18),
                  decoration: BoxDecoration(
                    color: Theme.of(context).dividerColor,
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),

                Row(
                  children: [
                    Container(
                      width: 46,
                      height: 46,
                      decoration: BoxDecoration(
                        color: app_color.withOpacity(0.10),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Icon(
                        Icons.menu_book_rounded,
                        color: app_color,
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            AppLocalizations.of(context).dashEntryTypeTitle,
                            style: GoogleFonts.poppins(
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                              color: Theme.of(context).colorScheme.onSurface,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            AppLocalizations.of(
                              context,
                            ).dashEntryTypeSubtitle,
                            style: GoogleFonts.poppins(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w500,
                              color: Theme.of(
                                context,
                              ).colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      style: IconButton.styleFrom(
                        backgroundColor:
                            Theme.of(context).brightness == Brightness.dark
                            ? Theme.of(
                                context,
                              ).colorScheme.surfaceContainerHighest
                            : const Color(0xFFF1F4F8),
                        foregroundColor: Theme.of(
                          context,
                        ).colorScheme.onSurfaceVariant,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      icon: const Icon(Icons.close_rounded),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
                const SizedBox(height: 18),

                if (_s.isSalesEntryVisible)
                  _buildEntryOption(
                    icon: Icons.point_of_sale,
                    label: AppLocalizations.of(context).dashEntrySales,
                    gradient: [Colors.blue.shade400, Colors.blue.shade700],
                    onTap: () {
                      Navigator.pop(context);
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => PendingSalesEntry()),
                      );
                    },
                  ),

                if (_s.isReceiptEntryVisible)
                  _buildEntryOption(
                    icon: Icons.receipt_long,
                    label: AppLocalizations.of(context).dashEntryReceipts,
                    gradient: [Colors.green.shade400, Colors.green.shade700],
                    onTap: () {
                      Navigator.pop(context);
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => PendingReceiptEntry(),
                        ),
                      );
                    },
                  ),

                if (_s.isSalesOrderEntryVisible)
                  _buildEntryOption(
                    icon: Icons.assignment,
                    label: AppLocalizations.of(context).dashEntrySalesOrder,
                    gradient: [
                      Colors.orange.shade400,
                      Colors.deepOrange.shade600,
                    ],
                    onTap: () {
                      Navigator.pop(context);
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => PendingSalesOrderEntry(),
                        ),
                      );
                    },
                  ),
                if (vanSalesSerialNo.contains(_s.serialNo) &&
                    (_s.isDeliveryNoteEntryVisible))
                  _buildEntryOption(
                    icon: Icons.local_shipping,
                    label: AppLocalizations.of(context).dashEntryDeliveryNote,
                    gradient: [Colors.blue.shade400, Colors.indigo.shade600],
                    onTap: () {
                      Navigator.pop(context);
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => PendingDeliveryNoteEntry(),
                        ),
                      );
                    },
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildEntryOption({
    required IconData icon,
    required String label,
    required List<Color> gradient,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        decoration: BoxDecoration(
          color: Theme.of(context).brightness == Brightness.dark
              ? Theme.of(context).colorScheme.surfaceContainerHighest
              : const Color(0xFFF9FAFC),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: Theme.of(context).dividerColor, width: 1),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.035),
              blurRadius: 12,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: gradient.last.withOpacity(0.11),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: gradient.last, size: 21),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                label,
                style: GoogleFonts.poppins(
                  fontSize: 14.5,
                  fontWeight: FontWeight.w700,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: Theme.of(context).brightness == Brightness.dark
                    ? Theme.of(context).colorScheme.surfaceContainerHighest
                    : const Color(0xFFF1F4F8),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.chevron_right_rounded,
                size: 18,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showConfirmationDialogAndExit(BuildContext context) async {
    await showDialog<void>(
      context: context,
      barrierDismissible: false, // user must tap button to close dialog
      builder: (BuildContext context) {
        return ScaleTransition(
          scale: CurvedAnimation(
            parent: AnimationController(
              duration: const Duration(milliseconds: 500),
              vsync: this,
            )..forward(),
            curve: Curves.fastOutSlowIn,
          ),
          child: AlertDialog(
            title: Text(AppLocalizations.of(context).dashExitTitle),
            content: SingleChildScrollView(
              child: ListBody(
                children: <Widget>[
                  Text(AppLocalizations.of(context).dashExitBody),
                ],
              ),
            ),
            actions: <Widget>[
              TextButton(
                child: Text(
                  AppLocalizations.of(context).commonNo,
                  style: GoogleFonts.poppins(
                    color: app_color, // Change the text color here
                  ),
                ),
                onPressed: () {
                  Navigator.of(context).pop();
                },
              ),
              TextButton(
                child: Text(
                  AppLocalizations.of(context).commonYes,
                  style: GoogleFonts.poppins(
                    color: app_color, // Change the text color here
                  ),
                ),
                onPressed: () async {
                  Navigator.of(context).pop();
                  exit(0);
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _handleRefresh() async {
    final showPicker = await _notifier.refresh();
    if (showPicker) {
      await _selectDateRangeRefresh(context);
    }
    _notifier.finishRefresh();
  }

  Future<void> _handleDate(dynamic value) async {
    await _notifier.applyDatePreset(value as String);
    if (value == 'Custom Date') {
      await _selectDateRangeAuto(context);
    }
  }

  // Shared date-range-picker theming, identical across every
  // showDateRangePicker call site below (was copy-pasted three times in
  // the original).
  Widget _dateRangePickerThemeBuilder(BuildContext context, Widget? child) {
    return Theme(
      data: Theme.of(context).copyWith(
        colorScheme: Theme.of(context).colorScheme.copyWith(
          primary: app_color, // main accent color
          onPrimary: Colors.white,
          surface: Theme.of(context).colorScheme.surface,
          onSurface: Theme.of(context).colorScheme.onSurface,
        ),
        datePickerTheme: DatePickerThemeData(
          backgroundColor: Theme.of(context).scaffoldBackgroundColor,
          surfaceTintColor: Colors.transparent,
          rangeSelectionBackgroundColor: app_color.withOpacity(0.15),
          rangeSelectionOverlayColor: WidgetStatePropertyAll(
            app_color.withOpacity(0.15),
          ),
        ),
        dialogTheme: DialogThemeData(
          backgroundColor: Theme.of(context).colorScheme.surface,
        ),
        dialogBackgroundColor: Theme.of(context).colorScheme.surface,
      ),
      child: child!,
    );
  }

  /// Mirrors the original `_selectDateRange_refresh` (used by pull-to-
  /// refresh's Custom Date branch), including its stale-prefs-write-on-
  /// cancel quirk: when the range picker is cancelled/unchanged, prefs are
  /// still overwritten with whatever `startDateString`/`endDateString`
  /// happen to already be on state at that point.
  Future<void> _selectDateRangeRefresh(BuildContext context) async {
    if (!_s.isTextEnabled) return;

    final startdatePref = _notifier.getPref('startdate');
    final enddatePref = _notifier.getPref('enddate');

    if (startdatePref == null || enddatePref == null || startdatePref == "") {
      final startfrom = _notifier.getPref('startfrom')!;
      final initialDateRange = DateTimeRange(start: _startDate, end: _endDate);
      final earliestDate = DateTime.parse(startfrom);

      final selectedDateRange = await showDateRangePicker(
        context: context,
        initialDateRange: initialDateRange,
        firstDate: earliestDate,
        lastDate: DateTime(2100),
        builder: _dateRangePickerThemeBuilder,
      );

      if (selectedDateRange != null && selectedDateRange != initialDateRange) {
        _startDate = selectedDateRange.start;
        _endDate = selectedDateRange.end;
        await _notifier.applyPickedRange(_startDate, _endDate);
      } else {
        await _notifier.setPref('startdate', _s.startDateString);
        await _notifier.setPref('enddate', _s.endDateString);
      }
    } else {
      if (!_s.isRefreshing) {
        showAppMessage(
          context,
          AppLocalizations.of(context).infoSwipeDownToRefresh,
        );
      }
      final start = DateTime.parse(startdatePref);
      final end = DateTime.parse(enddatePref);
      await _notifier.applyPickedRange(start, end);
    }
  }

  /// Mirrors the original `_selectDateRange_auto` (used when the dropdown
  /// itself is switched to "Custom Date") - always shows the picker, and
  /// leaves the current range untouched (no prefs write) if it's
  /// cancelled.
  Future<void> _selectDateRangeAuto(BuildContext context) async {
    if (!_s.isTextEnabled) return;

    final cachedStart =
        DateTime.tryParse(_notifier.getPref('startdate') ?? '');
    final cachedEnd = DateTime.tryParse(_notifier.getPref('enddate') ?? '');
    final initialDateRange = DateTimeRange(
      start: cachedStart ?? _startDate,
      end: cachedEnd ?? _endDate,
    );
    final startfrom = _notifier.getPref('startfrom');
    final earliestDate =
        DateTime.tryParse(startfrom ?? '') ?? DateTime(2000);

    final selectedDateRange = await showDateRangePicker(
      context: context,
      initialDateRange: initialDateRange,
      firstDate: earliestDate,
      lastDate: DateTime(2100),
      builder: _dateRangePickerThemeBuilder,
    );

    if (selectedDateRange == null) return;

    _startDate = selectedDateRange.start;
    _endDate = selectedDateRange.end;
    await _notifier.applyPickedRange(_startDate, _endDate);
  }

  /// Mirrors the original `_selectDateRange` (tapping the date-range text
  /// row), including the same stale-prefs-write-on-cancel quirk as
  /// `_selectDateRangeRefresh` (this branch never showed the "swipe down
  /// to refresh" message, unlike that one).
  Future<void> _selectDateRange(BuildContext context) async {
    if (!_s.isTextEnabled) return;

    final startdatePref = _notifier.getPref('startdate');
    final enddatePref = _notifier.getPref('enddate');

    if (startdatePref == null || enddatePref == null || startdatePref == "") {
      final startfrom = _notifier.getPref('startfrom')!;
      final initialDateRange = DateTimeRange(start: _startDate, end: _endDate);
      final earliestDate = DateTime.parse(startfrom);

      final selectedDateRange = await showDateRangePicker(
        context: context,
        initialDateRange: initialDateRange,
        firstDate: earliestDate,
        lastDate: DateTime(2100),
        builder: _dateRangePickerThemeBuilder,
      );

      if (selectedDateRange != null && selectedDateRange != initialDateRange) {
        _startDate = selectedDateRange.start;
        _endDate = selectedDateRange.end;
        await _notifier.applyPickedRange(_startDate, _endDate);
      } else {
        await _notifier.setPref('startdate', _s.startDateString);
        await _notifier.setPref('enddate', _s.endDateString);
      }
    } else {
      _startDate = DateTime.parse(startdatePref);
      _endDate = DateTime.parse(enddatePref);
      final initialDateRange = DateTimeRange(start: _startDate, end: _endDate);
      final startfrom = _notifier.getPref('startfrom');
      final earliestDate = DateTime.parse(startfrom!);

      final selectedDateRange = await showDateRangePicker(
        context: context,
        initialDateRange: initialDateRange,
        firstDate: earliestDate,
        lastDate: DateTime(2100),
        builder: _dateRangePickerThemeBuilder,
      );

      if (selectedDateRange != null) {
        _startDate = selectedDateRange.start;
        _endDate = selectedDateRange.end;
        await _notifier.applyPickedRange(_startDate, _endDate);
      } else {
        await _notifier.setPref('startdate', _s.startDateString);
        await _notifier.setPref('enddate', _s.endDateString);
      }
    }
  }

  // One label+icon+value row for the dialog's info section (e.g. "Serial
  // No: 772976358", "Expires on: 26-Jul-2026") - same shape both dialogs
  // use, just with different icons/colors/values.
  Widget _licenseDialogInfoRow({
    required String label,
    required IconData icon,
    required Color iconColor,
    required String value,
    required Color valueColor,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: GoogleFonts.poppins(
            fontSize: 14.5,
            color: Theme.of(context).colorScheme.onSurface,
          ),
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            Icon(icon, size: 18, color: iconColor),
            const SizedBox(width: 6),
            Text(
              value,
              style: GoogleFonts.poppins(
                fontWeight: FontWeight.w600,
                fontSize: 15,
                color: valueColor,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
      ],
    );
  }

  // Email + website contact chips for renewal - identical to the ones on
  // SerialSelect's expired-license dialog.
  Widget _licenseDialogContactChips() {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        InkWell(
          borderRadius: BorderRadius.circular(30),
          onTap: () async {
            final Uri emailUri = Uri(
              scheme: 'mailto',
              path: 'saadan@ca-eim.com',
              query:
                  'subject=License%20Renewal%20Request&body=Dear%20CSH%20LLC%20Support,%0A%0AMy%20license%20for%20Serial%20No%20${_s.serialNo}%20is%20expiring.%20Please%20assist%20with%20renewal.%0A%0ARegards,',
            );
            if (await canLaunchUrl(emailUri)) {
              await launchUrl(emailUri);
            }
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(30),
              border: Border.all(width: 1.3, color: Colors.teal.shade400),
              gradient: LinearGradient(
                colors: [
                  Colors.teal.withValues(alpha: 0.05),
                  Colors.teal.withValues(alpha: 0.1),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.email_outlined,
                  size: 18,
                  color: Colors.teal,
                ),
                const SizedBox(width: 8),
                Text(
                  "saadan@ca-eim.com",
                  style: GoogleFonts.poppins(
                    fontSize: 13.5,
                    color: Colors.teal.shade800,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ),
        InkWell(
          borderRadius: BorderRadius.circular(30),
          onTap: () async {
            const url = "https://cshllc.ae/contact-us/";
            if (await canLaunchUrl(Uri.parse(url))) {
              await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
            }
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(30),
              border: Border.all(width: 1.3, color: Colors.deepPurple.shade400),
              gradient: LinearGradient(
                colors: [
                  Colors.deepPurple.withValues(alpha: 0.05),
                  Colors.deepPurple.withValues(alpha: 0.1),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.language_rounded,
                  size: 18,
                  color: Colors.deepPurple,
                ),
                const SizedBox(width: 8),
                Text(
                  "cshllc.ae/contact-us",
                  style: GoogleFonts.poppins(
                    fontSize: 13.5,
                    color: Colors.deepPurple.shade800,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // Shared layout for both license dialogs - same animated scale-in,
  // gradient header, info rows, divider, message, contact chips and pill
  // button as SerialSelect's expired-license dialog, just parameterized
  // per use (title/icon/colors/message/action differ between "expired"
  // and "expiring soon").
  void _showStyledLicenseDialog({
    required String title,
    required IconData icon,
    required List<Color> gradientColors,
    required List<Widget> infoRows,
    required String message,
    required void Function(BuildContext dialogContext) onGotIt,
    bool barrierDismissible = true,
  }) {
    if (!mounted) return;
    showGeneralDialog(
      context: context,
      barrierDismissible: barrierDismissible,
      barrierLabel: '',
      barrierColor: Colors.black.withValues(alpha: 0.4),
      transitionDuration: const Duration(milliseconds: 400),
      pageBuilder: (context, anim1, anim2) => const SizedBox.shrink(),
      transitionBuilder: (context, anim1, anim2, child) {
        final curvedValue = Curves.easeOutBack.transform(anim1.value);
        return Transform.scale(
          scale: curvedValue,
          child: Opacity(
            opacity: anim1.value,
            child: AlertDialog(
              elevation: 12,
              backgroundColor: Theme.of(context).cardColor.withValues(alpha: 0.9),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(24),
              ),
              contentPadding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
              insetPadding: const EdgeInsets.symmetric(horizontal: 24),
              titlePadding: EdgeInsets.zero,
              title: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  vertical: 16,
                  horizontal: 20,
                ),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: gradientColors,
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(24),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(icon, color: Colors.white, size: 28),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        title,
                        style: GoogleFonts.poppins(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              content: ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 6, sigmaY: 6),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 10),
                      ...infoRows,
                      const SizedBox(height: 8),
                      Divider(thickness: 1, color: Colors.grey.shade300),
                      const SizedBox(height: 12),
                      Text(
                        message,
                        style: GoogleFonts.poppins(
                          fontSize: 14.5,
                          color: Theme.of(context).colorScheme.onSurface,
                        ),
                      ),
                      const SizedBox(height: 16),
                      _licenseDialogContactChips(),
                      const SizedBox(height: 26),
                      Align(
                        alignment: Alignment.center,
                        child: ElevatedButton.icon(
                          onPressed: () => onGotIt(context),
                          icon: const Icon(
                            Icons.check_circle_outline,
                            color: Colors.white,
                          ),
                          label: Text(
                            AppLocalizations.of(context).commonGotIt,
                            style: GoogleFonts.poppins(
                              fontWeight: FontWeight.w500,
                              fontSize: 15,
                              color: Colors.white,
                            ),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: app_color,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(30),
                            ),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 30,
                              vertical: 12,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  // Non-dismissible - a real hard block, matching SerialSelect's own
  // expired-license dialog exactly (red/orange gradient, Serial No +
  // Expired-on rows, contact chips for renewal).
  void _showLicenseExpiredDialog() {
    final String expiryDateText = _s.licenseExpiry != null
        ? DateFormat('dd-MMM-yyyy').format(DateTime.parse(_s.licenseExpiry!))
        : AppLocalizations.of(context).commonUnknown;

    _showStyledLicenseDialog(
      title: AppLocalizations.of(context).licenseExpiredTitle,
      icon: Icons.warning_amber_rounded,
      gradientColors: const [Color(0xFFF83600), Color(0xFFFE8C00)],
      infoRows: [
        _licenseDialogInfoRow(
          label: AppLocalizations.of(context).licenseSerialNo,
          icon: Icons.confirmation_number_outlined,
          iconColor: Colors.deepOrange,
          value: _s.serialNo ?? '',
          valueColor: Theme.of(context).colorScheme.onSurface,
        ),
        _licenseDialogInfoRow(
          label: AppLocalizations.of(context).licenseExpiredOn,
          icon: Icons.calendar_month,
          iconColor: Colors.redAccent,
          value: expiryDateText,
          valueColor: Colors.redAccent,
        ),
      ],
      message: AppLocalizations.of(context).licenseExpiredMessage,
      barrierDismissible: false,
      onGotIt: (dialogContext) {
        Navigator.pop(dialogContext);
        navigateToCompanySwitch(context);
      },
    );
  }

  // Dismissible (unlike the expired dialog) - just a heads-up so the
  // license doesn't lapse without warning. Shows every Dashboard load
  // while 3 or fewer days remain, same as the hard-block check above.
  // Same layout as the expired dialog, in an amber/orange "warning" tone
  // instead of expired's red/orange, so the two read as related but
  // distinct in severity.
  void _showLicenseExpiringSoonDialog(int daysRemaining) {
    final bool isToday = daysRemaining <= 0;
    final String expiryDateText = _s.licenseExpiry != null
        ? DateFormat('dd-MMM-yyyy').format(DateTime.parse(_s.licenseExpiry!))
        : AppLocalizations.of(context).commonUnknown;

    _showStyledLicenseDialog(
      title: isToday
          ? AppLocalizations.of(context).licenseExpiresTodayTitle
          : AppLocalizations.of(context).licenseExpiringSoonTitle,
      icon: Icons.hourglass_bottom_rounded,
      gradientColors: const [Colors.orangeAccent, Colors.deepOrange],
      infoRows: [
        _licenseDialogInfoRow(
          label: AppLocalizations.of(context).licenseSerialNo,
          icon: Icons.confirmation_number_outlined,
          iconColor: Colors.deepOrange,
          value: _s.serialNo ?? '',
          valueColor: Theme.of(context).colorScheme.onSurface,
        ),
        _licenseDialogInfoRow(
          label: isToday
              ? AppLocalizations.of(context).licenseExpiresLabel
              : AppLocalizations.of(context).licenseExpiresOnLabel,
          icon: Icons.calendar_month,
          iconColor: Colors.orange,
          value: isToday
              ? AppLocalizations.of(context).dateRangeToday
              : expiryDateText,
          valueColor: Colors.deepOrange,
        ),
        if (!isToday)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 5,
              ),
              decoration: BoxDecoration(
                color: Colors.deepOrange.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                AppLocalizations.of(context).licenseDaysLeft(daysRemaining),
                style: GoogleFonts.poppins(
                  color: Colors.deepOrange,
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                ),
              ),
            ),
          ),
      ],
      message: isToday
          ? AppLocalizations.of(context).licenseExpiresTodayMessage
          : AppLocalizations.of(context).licenseExpiringSoonMessage,
      barrierDismissible: true,
      onGotIt: (dialogContext) => Navigator.pop(dialogContext),
    );
  }

  bool _licenseDialogShown = false;

  @override
  void initState() {
    super.initState();

    _scaffoldMessengerKey = GlobalKey<ScaffoldMessengerState>();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      checkCurrencyMismatch(context);
    });
  }

  Widget _buildDecentCard(
    BuildContext context,
    String label,
    String symbol,
    String amountText,
    String currencyCode,
    String type,
    VoidCallback onTap,
  ) {
    return _dashboardDecentCard(
      context,
      label,
      symbol,
      amountText,
      currencyCode,
      type,
      onTap,
    );
  }

  @override
  Widget build(BuildContext context) {
    // Establishes the rebuild subscription for the whole synchronous build
    // call - values are then read through the `_s` getter below, same as
    // Login.dart/CompanySelectTallyOauth.dart.
    ref.watch(dashboardNotifierProvider);

    ref.listen<DashboardState>(dashboardNotifierProvider, (previous, next) {
      if (next.errorMessage != null) {
        showAppMessage(context, next.errorMessage!);
        ref.read(dashboardNotifierProvider.notifier).clearError();
      }

      // Fires once, right after the notifier's init finishes computing
      // isExpired/daysUntilExpiry - mirrors the original
      // `_initSharedPreferences`'s own addPostFrameCallback-scheduled
      // dialogs.
      if (!_licenseDialogShown &&
          (previous?.initialized != true) &&
          next.initialized) {
        _licenseDialogShown = true;
        final daysUntilExpiry =
            ref.read(dashboardNotifierProvider.notifier).daysUntilExpiry;
        if (next.isExpired) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _showLicenseExpiredDialog();
          });
        } else if (daysUntilExpiry != null && daysUntilExpiry <= 3) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _showLicenseExpiringSoonDialog(daysUntilExpiry);
          });
        }
      }
    });

    final Map<int, Color> yearColors = {};

    return WillPopScope(
      onWillPop: () async {
        _showConfirmationDialogAndExit(context);
        return true;
      },
      child: Scaffold(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        key: _scaffoldKey,
        appBar: PreferredSize(
          preferredSize: Size.fromHeight(50),
          child: AppBar(
            backgroundColor: app_color,
            elevation: 6,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.vertical(bottom: Radius.circular(20)),
            ),
            automaticallyImplyLeading: false,
            leadingWidth: kToolbarHeight,
            centerTitle: true,
            title: GestureDetector(
              onTap: () => navigateToCompanySwitch(context),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth:
                      MediaQuery.of(context).size.width -
                      (kToolbarHeight * 2.4),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Flexible(
                      child: Text(
                        _s.company,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        softWrap: false,
                        style: GoogleFonts.poppins(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                    const Icon(Icons.arrow_drop_down, color: Colors.white),
                  ],
                ),
              ),
            ),
            actions: const [],
          ),
        ),

        bottomNavigationBar: const AppBottomNav(
          activeTab: AppBottomNavTab.dashboard,
          activeMoreItem: AppMoreItem.dashboard,
        ),

        body: Stack(
          children: [
            RefreshIndicator(
              onRefresh: _handleRefresh,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                child: Center(
                  child: Column(
                    children: [
                      _buildDashboardHeader(),
                      if (_s.isLoading)
                        _buildSkeletonDateCard()
                      else
                        Container(
                          margin: const EdgeInsets.fromLTRB(12, 8, 12, 4),
                          padding: EdgeInsets.all(0),
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
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (_s.isVisibleDate)
                                Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [buildDateFilterCard(context)],
                                ),
                            ],
                          ),
                        ),

                      if (_s.isLoading)
                        _buildSkeletonGrid()
                      else
                      GridView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
                        gridDelegate:
                            const SliverGridDelegateWithMaxCrossAxisExtent(
                              maxCrossAxisExtent: 220,
                              childAspectRatio: 1.28,
                              crossAxisSpacing: 12,
                              mainAxisSpacing: 12,
                            ),
                        itemCount: [
                          if (_s.salesVisibility) 1 else 0,
                          if (_s.purchaseVisibility) 1 else 0,
                          if (_s.receiptVisibility) 1 else 0,
                          if (_s.paymentVisibility) 1 else 0,
                          if (_s.receivableVisibility) 1 else 0,
                          if (_s.payableVisibility) 1 else 0,
                          if (_s.cashVisibility) 1 else 0,
                        ].where((e) => e == 1).length,
                        itemBuilder: (context, index) {
                          final items = <Widget>[
                            if (_s.salesVisibility)
                              _buildDecentCard(
                                context,
                                AppLocalizations.of(context).tileSalesCreditNote,
                                _s.currencySymbol,
                                formatNumberAbbreviation(_s.salesValue, decimalPlaces: _s.decimal, scale: _s.selectedScale, showSuffix: true),
                                _s.currencyCode,
                                "sales", // 👈 type auto handle karega
                                () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (context) => DashboardClicked(
                                        startdate_string: _s.startDateString,
                                        enddate_string: _s.endDateString,
                                        vchtypes: "Sales",
                                      ),
                                    ),
                                  );
                                },
                              ),

                            if (_s.purchaseVisibility)
                              _buildDecentCard(
                                context,
                                AppLocalizations.of(context).tilePurchaseDebitNote,
                                _s.currencySymbol,
                                formatNumberAbbreviation(_s.purchaseValue, decimalPlaces: _s.decimal, scale: _s.selectedScale, showSuffix: true),
                                _s.currencyCode,
                                "purchase",
                                () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (context) => DashboardClicked(
                                        startdate_string: _s.startDateString,
                                        enddate_string: _s.endDateString,
                                        vchtypes: "Purchase",
                                      ),
                                    ),
                                  );
                                },
                              ),

                            if (_s.receiptVisibility)
                              _buildDecentCard(
                                context,
                                AppLocalizations.of(context).tileReceipt,
                                _s.currencySymbol,
                                formatNumberAbbreviation(_s.receiptValue, decimalPlaces: _s.decimal, scale: _s.selectedScale, showSuffix: true),
                                _s.currencyCode,
                                "receipt",
                                () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (context) => DashboardClicked(
                                        startdate_string: _s.startDateString,
                                        enddate_string: _s.endDateString,
                                        vchtypes: "Receipt",
                                      ),
                                    ),
                                  );
                                },
                              ),

                            if (_s.paymentVisibility)
                              _buildDecentCard(
                                context,
                                AppLocalizations.of(context).tilePayment,
                                _s.currencySymbol,
                                formatNumberAbbreviation(_s.paymentValue, decimalPlaces: _s.decimal, scale: _s.selectedScale, showSuffix: true),
                                _s.currencyCode,
                                "payment",
                                () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (context) => DashboardClicked(
                                        startdate_string: _s.startDateString,
                                        enddate_string: _s.endDateString,
                                        vchtypes: "Payment",
                                      ),
                                    ),
                                  );
                                },
                              ),

                            if (_s.receivableVisibility)
                              _buildDecentCard(
                                context,
                                AppLocalizations.of(context).tileOutstandingReceivable,
                                _s.currencySymbol,
                                formatNumberAbbreviation(_s.outstandingReceivableValue, decimalPlaces: _s.decimal, scale: _s.selectedScale, showSuffix: true),
                                _s.currencyCode,
                                "receivable",
                                () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (context) => DashboardClicked(
                                        startdate_string: _s.startDateString,
                                        enddate_string: _s.endDateString,
                                        vchtypes: "Receivable",
                                      ),
                                    ),
                                  );
                                },
                              ),

                            if (_s.payableVisibility)
                              _buildDecentCard(
                                context,
                                AppLocalizations.of(context).tileOutstandingPayable,
                                _s.currencySymbol,
                                formatNumberAbbreviation(_s.outstandingPayableValue, decimalPlaces: _s.decimal, scale: _s.selectedScale, showSuffix: true),
                                _s.currencyCode,
                                "payable",
                                () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (context) => DashboardClicked(
                                        startdate_string: _s.startDateString,
                                        enddate_string: _s.endDateString,
                                        vchtypes: "Payable",
                                      ),
                                    ),
                                  );
                                },
                              ),

                            if (_s.cashVisibility)
                              _buildDecentCard(
                                context,
                                AppLocalizations.of(context).tileCashBankBalance,
                                _s.currencySymbol,
                                formatNumberAbbreviation(_s.cashValue, decimalPlaces: _s.decimal, scale: _s.selectedScale, showSuffix: true),
                                _s.currencyCode,
                                "Cash", // type (for icon + gradient auto handle)
                                () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (context) => DashboardClicked(
                                        startdate_string: _s.startDateString,
                                        enddate_string: _s.endDateString,
                                        vchtypes: "Cash",
                                      ),
                                    ),
                                  );
                                },
                              ),
                          ];

                          return items[index];
                        },
                      ),

                      Align(
                        alignment: Alignment.topLeft,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (_s.isVisibleLineChart || _s.isPieChartVisible)
                              GestureDetector(
                                onTap: () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => AnalyticsScreen(
                                        lineChartData: data,
                                        months: months_chart_line_graph,
                                        yearColors: yearColors,
                                        pieSalesList: piechartsaleslist
                                            .cast<Map<String, dynamic>>(),
                                        piePurchaseList: piechartpurchaselist
                                            .cast<Map<String, dynamic>>(),
                                        isVisibleLineChart: _s.isVisibleLineChart,
                                        decimalPlaces: _s.decimal,
                                        isVisiblePieChart: _s.isPieChartVisible,
                                        isSalesPieChartVisible:
                                            _s.isSalesPieChartVisible,
                                        isPurchasePieChartVisible:
                                            _s.isPurchasePieChartVisible,
                                        isBarChartVisible: _s.isBarChartVisible,
                                        salesDataList: _s.salesDataList,
                                        recDataList: _s.recDataList,
                                        selectedScale: _s.selectedScale,
                                        startDateString: _s.startDateString,
                                        endDateString: _s.endDateString,
                                      ),
                                    ),
                                  );
                                },
                                child: Container(
                                  margin: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                    vertical: 10,
                                  ),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                    vertical: 15,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Theme.of(context).cardColor,
                                    borderRadius: BorderRadius.circular(18),
                                    border: Border.all(
                                      color: Theme.of(context).dividerColor,
                                    ),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black.withOpacity(0.035),
                                        blurRadius: 16,
                                        offset: const Offset(0, 8),
                                      ),
                                    ],
                                  ),
                                  child: Row(
                                    children: [
                                      Container(
                                        width: 42,
                                        height: 42,
                                        decoration: BoxDecoration(
                                          color: app_color.withOpacity(0.10),
                                          borderRadius: BorderRadius.circular(
                                            12,
                                          ),
                                        ),
                                        child: Icon(
                                          Icons.analytics_outlined,
                                          color: app_color,
                                          size: 22,
                                        ),
                                      ),
                                      const SizedBox(width: 16),

                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              AppLocalizations.of(
                                                context,
                                              ).dashAnalyticsTitle,
                                              style: GoogleFonts.poppins(
                                                fontSize: 15.5,
                                                fontWeight: FontWeight.w700,
                                                color: Theme.of(
                                                  context,
                                                ).colorScheme.onSurface,
                                              ),
                                            ),
                                            const SizedBox(height: 2),
                                            Text(
                                              AppLocalizations.of(
                                                context,
                                              ).dashAnalyticsSubtitle,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: GoogleFonts.poppins(
                                                fontSize: 12,
                                                fontWeight: FontWeight.w500,
                                                color: Theme.of(
                                                  context,
                                                ).colorScheme.onSurfaceVariant,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),

                                      Container(
                                        padding: const EdgeInsets.all(6),
                                        decoration: BoxDecoration(
                                          color:
                                              Theme.of(context).brightness ==
                                                  Brightness.dark
                                              ? Theme.of(context)
                                                    .colorScheme
                                                    .surfaceContainerHighest
                                              : const Color(0xFFF1F4F8),
                                          shape: BoxShape.circle,
                                        ),
                                        child: Icon(
                                          Icons.chevron_right_rounded,
                                          color: Theme.of(
                                            context,
                                          ).colorScheme.onSurfaceVariant,
                                          size: 20,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),

                            Visibility(
                              visible: _s.isVisibleNoAccess,
                              child: Container(
                                margin: const EdgeInsets.fromLTRB(
                                  16,
                                  18,
                                  16,
                                  20,
                                ),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 18,
                                  vertical: 24,
                                ),
                                decoration: BoxDecoration(
                                  color: Theme.of(context).cardColor,
                                  borderRadius: BorderRadius.circular(18),
                                  border: Border.all(
                                    color: Theme.of(context).dividerColor,
                                  ),
                                ),
                                child: Center(
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Container(
                                        width: 48,
                                        height: 48,
                                        decoration: BoxDecoration(
                                          color: app_color.withOpacity(0.10),
                                          borderRadius: BorderRadius.circular(
                                            14,
                                          ),
                                        ),
                                        child: Icon(
                                          Icons.lock_outline_rounded,
                                          color: app_color,
                                        ),
                                      ),
                                      const SizedBox(height: 12),
                                      Text(
                                        AppLocalizations.of(
                                          context,
                                        ).dashNoAccessTitle,
                                        style: GoogleFonts.poppins(
                                          fontWeight: FontWeight.w700,
                                          color: Theme.of(
                                            context,
                                          ).colorScheme.onSurface,
                                          fontSize: 16.0,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        AppLocalizations.of(
                                          context,
                                        ).dashNoAccessBody,
                                        textAlign: TextAlign.center,
                                        style: GoogleFonts.poppins(
                                          fontWeight: FontWeight.w500,
                                          color: Theme.of(
                                            context,
                                          ).colorScheme.onSurfaceVariant,
                                          fontSize: 12.5,
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
            ),
          ],
        ),

        floatingActionButton: FloatingActionButton(
          backgroundColor: app_color,
          elevation: 4,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          tooltip: AppLocalizations.of(context).numberScaleTooltip,
          child: const Icon(Icons.tune_rounded, color: Colors.white),
          onPressed: () async {
            final RenderBox button = context.findRenderObject() as RenderBox;
            final RenderBox overlay =
                Overlay.of(context).context.findRenderObject() as RenderBox;

            final RelativeRect position = RelativeRect.fromRect(
              Rect.fromPoints(
                button.localToGlobal(
                  button.size.bottomRight(Offset.zero),
                  ancestor: overlay,
                ),
                button.localToGlobal(
                  button.size.bottomRight(Offset.zero),
                  ancestor: overlay,
                ),
              ),
              Offset.zero & overlay.size,
            );

            final theme = Theme.of(context);
            final result = await showMenu<NumberScale>(
              color: theme.colorScheme.surface,
              context: context,
              position: position,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(color: theme.dividerColor),
              ),
              items: [
                _buildNumberScaleMenuItem(
                  value: NumberScale.full,
                  icon: Icons.pin,
                  iconColor: Colors.blue,
                  label: AppLocalizations.of(context).numberScaleFull,
                ),
                _buildNumberScaleMenuItem(
                  value: NumberScale.thousand,
                  icon: Icons.format_list_numbered,
                  iconColor: Colors.blue,
                  label: AppLocalizations.of(context).numberScaleThousands,
                ),
                _buildNumberScaleMenuItem(
                  value: NumberScale.million,
                  icon: Icons.format_list_numbered_rtl,
                  iconColor: Colors.orange,
                  label: AppLocalizations.of(context).numberScaleMillions,
                ),
                _buildNumberScaleMenuItem(
                  value: NumberScale.billion,
                  icon: Icons.numbers,
                  iconColor: Colors.purple,
                  label: AppLocalizations.of(context).numberScaleBillions,
                ),
              ],
            );

            if (result != null) {
              await _notifier.saveNumberScale(result);
            }
          },
        ),
      ),
    );
  }

  PopupMenuItem<NumberScale> _buildNumberScaleMenuItem({
    required NumberScale value,
    required IconData icon,
    required Color iconColor,
    required String label,
  }) {
    final theme = Theme.of(context);
    final isSelected = _s.selectedScale == value;

    return PopupMenuItem<NumberScale>(
      value: value,
      child: Row(
        children: [
          Icon(icon, color: iconColor),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              style: GoogleFonts.poppins(
                color: theme.colorScheme.onSurface,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ),
          if (isSelected)
            Icon(Icons.check_circle_rounded, color: app_color, size: 20),
        ],
      ),
    );
  }

  Widget _buildDashboardHeader() {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: app_color,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: app_color.withOpacity(0.22),
            blurRadius: 18,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: Theme.of(context).cardColor.withOpacity(0.16),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(
              Icons.dashboard_customize_rounded,
              color: Colors.white,
              size: 26,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _s.name.trim().isEmpty
                      ? AppLocalizations.of(context).dashWelcome
                      : AppLocalizations.of(context).dashWelcomeName(_s.name),
                  style: GoogleFonts.poppins(
                    color: Colors.white,
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  AppLocalizations.of(context).dashHeaderSubtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.poppins(
                    color: Colors.white.withOpacity(0.82),
                    fontSize: 12.5,
                    height: 1.35,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _dateRangeOptionLabel(BuildContext context, String option) {
    final l = AppLocalizations.of(context);
    switch (option) {
      case 'Today':
        return l.dateRangeToday;
      case 'Yesterday':
        return l.dateRangeYesterday;
      case 'This Month':
        return l.dateRangeThisMonth;
      case 'Last Month':
        return l.dateRangeLastMonth;
      case 'This Year':
        return l.dateRangeThisYear;
      case 'Last Year':
        return l.dateRangeLastYear;
      case 'Year To Date':
        return l.dateRangeYearToDate;
      case 'Custom Date':
        return l.dateRangeCustomDate;
      default:
        return option;
    }
  }

  // Skeleton stand-in for the date-filter card while the dashboard's first
  // fetch is in flight - shown instead of the real card (rather than
  // dimming stale/zeroed content under a spinner) so the loading state
  // reads as "content incoming" instead of "something broke".
  Widget _buildSkeletonDateCard() {
    return ShimmerLoading(
      child: Container(
        margin: const EdgeInsets.fromLTRB(12, 8, 12, 4),
        padding: const EdgeInsets.all(10),
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
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const ShimmerBox(width: 34, height: 34, borderRadius: 12),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const ShimmerBox(width: 90, height: 12),
                      const SizedBox(height: 6),
                      ShimmerBox(
                        width: MediaQuery.of(context).size.width * 0.4,
                        height: 10,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            const ShimmerBox(height: 40, borderRadius: 12),
            const SizedBox(height: 8),
            const ShimmerBox(height: 40, borderRadius: 12),
          ],
        ),
      ),
    );
  }

  // Skeleton stand-in for the tile grid (Sales/Purchase/Receipt/... cards)
  // while data is loading - mirrors _buildDecentCard's layout (icon badge,
  // chevron badge, 2-line label, amount line) so the transition into real
  // content doesn't visibly jump.
  Widget _buildSkeletonGrid() {
    return ShimmerLoading(
      child: GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 220,
          childAspectRatio: 1.28,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
        ),
        itemCount: 6,
        itemBuilder: (context, index) {
          return Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Theme.of(context).cardColor,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: Theme.of(context).dividerColor),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const ShimmerBox(width: 32, height: 32, borderRadius: 10),
                    const Spacer(),
                    const ShimmerBox(width: 24, height: 24, borderRadius: 12),
                  ],
                ),
                const Spacer(),
                const ShimmerBox(height: 11, width: 90),
                const SizedBox(height: 4),
                const ShimmerBox(height: 11, width: 60),
                const SizedBox(height: 6),
                const ShimmerBox(height: 16, width: 80),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget buildDateFilterCard(BuildContext context) {
    final tintColor = Theme.of(context).brightness == Brightness.dark
        ? Colors.white.withOpacity(0.06)
        : Colors.grey.shade100;
    return Padding(
      padding: const EdgeInsets.all(10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: app_color.withOpacity(0.10),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  Icons.date_range_rounded,
                  size: 18,
                  color: app_color,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      AppLocalizations.of(context).dashReportPeriod,
                      style: GoogleFonts.poppins(
                        fontSize: 13,
                        color: Theme.of(context).colorScheme.onSurface,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      "${_s.startdateText} - ${_s.enddateText}",
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.poppins(
                        fontSize: 11,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Container(
            height: 40,
            decoration: BoxDecoration(
              color: tintColor,
              borderRadius: BorderRadius.circular(12),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<dynamic>(
                value: _s.selectedDate,
                isDense: true,
                icon: Icon(
                  Icons.expand_more_rounded,
                  size: 18,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
                dropdownColor: Theme.of(context).colorScheme.surface,
                borderRadius: BorderRadius.circular(14),
                isExpanded: true,
                style: GoogleFonts.poppins(
                  fontSize: 13.5,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
                items: date_range.map((item) {
                  return DropdownMenuItem<dynamic>(
                    value: item,
                    child: Text(
                      _dateRangeOptionLabel(context, item),
                      style: GoogleFonts.poppins(
                        fontSize: 13.5,
                        color: Theme.of(context).colorScheme.onSurface,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  );
                }).toList(),
                onChanged: (value) => _handleDate(value),
              ),
            ),
          ),
          const SizedBox(height: 8),
          InkWell(
            onTap: () => _selectDateRange(context),
            borderRadius: BorderRadius.circular(12),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: tintColor,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      "${_s.startdateText} - ${_s.enddateText}",
                      style: GoogleFonts.poppins(
                        fontSize: 12.5,
                        color: Theme.of(context).colorScheme.onSurface,
                        fontWeight: FontWeight.w600,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Icon(
                    Icons.edit_calendar_rounded,
                    size: 16,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget buildButtonTile({
    required String label,
    required String value,
    required IconData icon,
    required bool visible,
    required VoidCallback onTap,
  }) {
    return Visibility(
      visible: visible,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          margin: const EdgeInsets.only(left: 16, right: 16, top: 10),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: Theme.of(context).brightness == Brightness.dark
                  ? [
                      Theme.of(context).cardColor,
                      Theme.of(context).colorScheme.surfaceContainerHighest,
                    ]
                  : const [Color(0xFFF1FDFB), Color(0xFFE9F6F3)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.teal.shade100.withOpacity(0.6)),
            boxShadow: [
              BoxShadow(
                color: Colors.teal.withOpacity(0.08),
                blurRadius: 14,
                offset: Offset(0, 6),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                padding: EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.teal.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, size: 24, color: Colors.teal),
              ),
              SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      value,
                      style: GoogleFonts.poppins(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      label,
                      style: GoogleFonts.poppins(
                        fontSize: 13.5,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                color: Colors.teal.withOpacity(0.5),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

Widget _buildFloatingTile(
  BuildContext context,
  String label,
  IconData icon,
  Color color,
  VoidCallback onTap,
) {
  return Tooltip(
    message: label,
    child: GestureDetector(
      onTap: onTap,
      child: Material(
        shape: const CircleBorder(),
        elevation: 8,
        shadowColor: Colors.black38,
        color: Theme.of(context).cardColor,
        child: Padding(
          padding: const EdgeInsets.all(14.0),
          child: Icon(icon, color: color, size: 28),
        ),
      ),
    ),
  );
}

Widget _dashboardDecentCard(
  BuildContext context,
  String label,
  String symbol,
  String amountText,
  String currencyCode,
  String type,
  VoidCallback onTap,
) {
  Color _getColor(String type) {
    switch (type.toLowerCase()) {
      case "sales":
        return const Color(0xFF0F766E);
      case "purchase":
        return const Color(0xFFB45309);
      case "receipt":
        return const Color(0xFF15803D);
      case "payment":
        return const Color(0xFFB42318);
      case "receivable":
        return const Color(0xFF4338CA);
      case "payable":
        return const Color(0xFF7E22CE);
      case "cash":
        return const Color(0xFF0369A1);
      default:
        return const Color(0xFF4B5563);
    }
  }

  IconData _getIcon(String type) {
    switch (type.toLowerCase()) {
      case "sales":
        return Icons.trending_up;
      case "purchase":
        return Icons.shopping_cart_outlined;
      case "receipt":
        return Icons.receipt_long_outlined;
      case "payment":
        return Icons.payments_outlined;
      case "receivable":
        return Icons.account_balance_wallet_outlined;
      case "payable":
        return Icons.money_off_csred_outlined;
      case "cash":
        return Icons.account_balance_outlined;
      default:
        return Icons.insert_chart_outlined_rounded;
    }
  }

  final Color color = _getColor(type);

  return Material(
    color: Theme.of(context).cardColor,
    borderRadius: BorderRadius.circular(18),
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Ink(
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: Theme.of(context).dividerColor),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.035),
              blurRadius: 16,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        padding: const EdgeInsets.all(12),
        child: LayoutBuilder(
          builder: (context, constraints) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: color.withOpacity(0.10),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(_getIcon(type), size: 17, color: color),
                    ),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: Theme.of(context).brightness == Brightness.dark
                            ? Theme.of(
                                context,
                              ).colorScheme.surfaceContainerHighest
                            : const Color(0xFFF1F4F8),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.chevron_right_rounded,
                        size: 15,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
                const Spacer(),
                Text(
                  label,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.poppins(
                    fontSize: 11.5,
                    height: 1.15,
                    fontWeight: FontWeight.w600,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 4),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: currencyAmountText(
                    currencyCode: currencyCode,
                    symbol: symbol,
                    amountText: amountText,
                    maxLines: 1,
                    style: GoogleFonts.poppins(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    ),
  );
}
