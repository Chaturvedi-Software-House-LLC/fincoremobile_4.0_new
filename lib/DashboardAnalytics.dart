import 'dart:math';

import 'package:FincoreGo/utils/number_formatter.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'constants.dart';
import 'currencyFormat.dart';
import 'package:FincoreGo/widgets/app_bottom_nav.dart';
import 'package:FincoreGo/widgets/app_navigation.dart';

class AnalyticsScreen extends StatefulWidget {
  final List<Map<String, dynamic>> lineChartData;
  final List<String> months;
  final Map<int, Color> yearColors;
  final List<Map<String, dynamic>> pieSalesList;
  final List<Map<String, dynamic>> piePurchaseList;
  final bool isVisibleLineChart;
  final bool isVisiblePieChart;
  final bool isSalesPieChartVisible;
  final bool isPurchasePieChartVisible;
  final int decimalPlaces;
  final bool isBarChartVisible;
  final List<double> salesDataList;
  final List<double> recDataList;
  final NumberScale selectedScale;
  final String startDateString;
  final String endDateString;

  const AnalyticsScreen({
    super.key,
    required this.lineChartData,
    required this.months,
    required this.yearColors,
    required this.pieSalesList,
    required this.piePurchaseList,
    required this.isVisibleLineChart,
    required this.isVisiblePieChart,
    required this.isSalesPieChartVisible,
    required this.isPurchasePieChartVisible,
    required this.decimalPlaces,
    required this.isBarChartVisible,
    required this.salesDataList,
    required this.recDataList,
    required this.selectedScale,
    required this.startDateString,
    required this.endDateString,
  });

  @override
  State<AnalyticsScreen> createState() => _AnalyticsScreenState();
}

class _AnalyticsScreenState extends State<AnalyticsScreen> {
  late NumberScale selectedScale;
  bool showPercentage = false;

  String? company = "";
  String? companyLowercase = "";
  String? serialNo = "";
  String? username = "";
  String? securityButtonAccessHolder = "";
  SharedPreferences? prefs;

  static final List<Color> _chartPalette = [
    app_color,
    const Color(0xFFFF8A3D),
    const Color(0xFF00A6A6),
    const Color(0xFF6C63FF),
    const Color(0xFFEF476F),
    const Color(0xFF2D9CDB),
    const Color(0xFF8BC34A),
    const Color(0xFFFFC857),
    const Color(0xFF7B61FF),
    const Color(0xFF455A64),
  ];

  @override
  void initState() {
    super.initState();
    selectedScale = widget.selectedScale;
    _initSharedPreferences();
  }

  Future<void> _initSharedPreferences() async {
    debugPrint("pieSalesList => ${widget.pieSalesList}");
    debugPrint("lineChartData => ${widget.lineChartData}");
    debugPrint("salesDataList => ${widget.salesDataList}");
    final loadedPrefs = await SharedPreferences.getInstance();
    final scale = loadedPrefs.getString("number_scale");

    if (!mounted) return;
    setState(() {
      prefs = loadedPrefs;
      company = loadedPrefs.getString('company_name') ?? "";
      companyLowercase = company!.replaceAll(' ', '').toLowerCase();
      serialNo = loadedPrefs.getString('serial_no') ?? "";
      username = loadedPrefs.getString('username') ?? "";
      securityButtonAccessHolder = loadedPrefs.getString('secbtnaccess') ?? "";
      selectedScale = _numberScaleFromString(scale) ?? widget.selectedScale;
    });
  }

  Widget _buildPieSalesRawData() {
    final data = _cleanPieData(widget.pieSalesList);

    if (data.isEmpty) {
      return const _EmptyState(
        icon: Icons.info_outline_rounded,
        title: "No pie sales data",
        message: "pieSalesList is empty for this period.",
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          "Pie Sales Data",
          style: GoogleFonts.poppins(
            fontSize: 14,
            fontWeight: FontWeight.w800,
            color: Theme.of(context).colorScheme.onSurface,
          ),
        ),
        const SizedBox(height: 10),
        ...data.map((item) {
          final name = item['name']?.toString() ?? "";
          final amount = _asDouble(item['amount']).abs();

          return Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Theme.of(context).brightness == Brightness.dark
                  ? Theme.of(context).colorScheme.surfaceContainerHighest
                  : const Color(0xFFF7F9FC),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    name,
                    style: GoogleFonts.poppins(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                currencyAmountText(
                  currencyCode: CurrencyFormatter.getCurrencyCode(),
                  symbol: CurrencyFormatter.formatCurrencyParts(amount).symbol,
                  amountText: CurrencyFormatter.formatCurrencyParts(
                    amount,
                  ).number,
                  style: GoogleFonts.poppins(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
              ],
            ),
          );
        }),
      ],
    );
  }

  NumberScale? _numberScaleFromString(String? value) {
    switch (value) {
      case "thousand":
        return NumberScale.thousand;
      case "million":
        return NumberScale.million;
      case "billion":
        return NumberScale.billion;
      case "full":
        return NumberScale.full;
      default:
        return null;
    }
  }

  List<_MonthBarEntry> get _barEntries {
    final count = max(widget.salesDataList.length, widget.recDataList.length);
    final labels = _preferredMonthLabels(count);
    final entries = <_MonthBarEntry>[];

    for (var i = 0; i < count; i++) {
      final sales = i < widget.salesDataList.length
          ? widget.salesDataList[i]
          : 0.0;
      final receipt = i < widget.recDataList.length
          ? widget.recDataList[i]
          : 0.0;
      final label = i < labels.length ? labels[i] : "M${i + 1}";

      if (_hasValue(sales) || _hasValue(receipt)) {
        entries.add(
          _MonthBarEntry(label: label, sales: sales, receipt: receipt),
        );
      }
    }

    return entries;
  }

  List<String> get _lineMonths {
    final monthsFromData = <String>[];
    for (final yearData in widget.lineChartData) {
      final values = yearData['value'];
      if (values is! Iterable) continue;

      for (final item in values) {
        if (item is! Map) continue;
        final month = item['month']?.toString();
        final sales = _asDouble(item['sales']);

        if (month != null &&
            month.isNotEmpty &&
            _hasValue(sales) &&
            !monthsFromData.contains(month)) {
          monthsFromData.add(month);
        }
      }
    }

    return monthsFromData;
  }

  List<String> _preferredMonthLabels(int expectedCount) {
    final dateRangeMonths = <DateTime>[];
    try {
      var startDate = DateTime.parse(widget.startDateString);
      final endDate = DateTime.parse(widget.endDateString);

      while (startDate.isBefore(endDate) ||
          startDate.isAtSameMomentAs(endDate)) {
        dateRangeMonths.add(startDate);
        startDate = DateTime(startDate.year, startDate.month + 1, 1);
      }
    } catch (e) {
      debugPrint("Error generating fallback months list: $e");
    }

    if (dateRangeMonths.isNotEmpty) {
      final labels = dateRangeMonths
          .map((date) => DateFormat('MMM-yy').format(date))
          .toList(growable: false);

      if (labels.length == expectedCount || widget.months.isEmpty) {
        return labels;
      }
    }

    return widget.months
        .where((month) => month.trim().isNotEmpty)
        .map(_normalizeMonthLabel)
        .toList(growable: false);
  }

  String _normalizeMonthLabel(String label) {
    final trimmed = label.trim();
    if (trimmed.isEmpty) return trimmed;
    if (RegExp(r"\d").hasMatch(trimmed)) return trimmed;

    try {
      final startDate = DateTime.parse(widget.startDateString);
      return "$trimmed-${DateFormat('yy').format(startDate)}";
    } catch (_) {
      return trimmed;
    }
  }

  bool _hasValue(double value) {
    return value.isFinite && value.abs() > 0.000001;
  }

  double _asDouble(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? "") ?? 0.0;
  }

  double get _barTotalSales {
    return _barEntries.fold<double>(0, (sum, item) => sum + item.sales.abs());
  }

  double get _barTotalReceipts {
    return _barEntries.fold<double>(0, (sum, item) => sum + item.receipt.abs());
  }

  double get _totalSales {
    final pieSalesTotal = _amountListTotal(widget.pieSalesList);
    if (!_hasValue(_barTotalSales) && _hasValue(pieSalesTotal)) {
      return pieSalesTotal;
    }
    return _barTotalSales;
  }

  double get _totalReceipts {
    return _barTotalReceipts;
  }

  double _amountListTotal(List<Map<String, dynamic>> data) {
    return data.fold<double>(
      0,
      (sum, item) => sum + _asDouble(item['amount']).abs(),
    );
  }

  String _formatCompact(double value) {
    return formatNumberAbbreviation(
      value,
      scale: selectedScale,
      decimalPlaces: widget.decimalPlaces,
      showSuffix: false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final barEntries = _barEntries;
    final lineMonths = _lineMonths;
    final hasAnyChart =
        widget.isBarChartVisible ||
        widget.isVisibleLineChart ||
        widget.isVisiblePieChart;

    return Scaffold(
      bottomNavigationBar: const AppBottomNav(
        activeTab: AppBottomNavTab.dashboard,
        activeMoreItem: AppMoreItem.dashboard,
      ),
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: app_color,
        elevation: 0,
        automaticallyImplyLeading: false,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
          onPressed: () => AppNavigation.backOrDashboard(context),
        ),
        title: Text(
          "Analytics",
          style: GoogleFonts.poppins(
            fontSize: 19,
            fontWeight: FontWeight.w700,
            color: Colors.white,
          ),
        ),
        centerTitle: true,
        actions: [],
      ),
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(child: _buildHeader(theme)),
            if (!hasAnyChart)
              SliverFillRemaining(
                hasScrollBody: false,
                child: _EmptyState(
                  icon: Icons.analytics_outlined,
                  title: "No analytics enabled",
                  message:
                      "Select at least one chart to view your business insights.",
                ),
              ),
            if (widget.isBarChartVisible)
              SliverToBoxAdapter(
                child: _AnalyticsCard(
                  margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                  title: "Sales vs Receipts",
                  subtitle: "Only months with activity are shown",
                  icon: Icons.bar_chart_rounded,
                  accentColor: app_color,
                  trailing: _MetricPill(
                    label: "${barEntries.length}",
                    caption: barEntries.length == 1 ? "month" : "months",
                  ),
                  child: barEntries.isEmpty
                      ? const _EmptyState(
                          icon: Icons.calendar_month_outlined,
                          title: "No monthly activity",
                          message:
                              "There is no sales or receipt value for this period.",
                        )
                      : Column(
                          children: [
                            /*Row(
                        children: [
                          Expanded(
                            child: _SummaryTile(
                              label: "Sales",
                              value:
                              CurrencyFormatter.formatCurrency_double(
                                _barTotalSales,
                              ),
                              color: app_color,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: _SummaryTile(
                              label: "Receipts",
                              value:
                              CurrencyFormatter.formatCurrency_double(
                                _barTotalReceipts,
                              ),
                              color: const Color(0xFFFF8A3D),
                            ),
                          ),
                        ],
                      ),*/
                            const SizedBox(height: 9),
                            LayoutBuilder(
                              builder: (context, constraints) {
                                final shouldScroll = barEntries.length > 3;
                                final chart = SizedBox(
                                  width: shouldScroll
                                      ? _chartWidth(context, barEntries.length)
                                      : constraints.maxWidth,
                                  height: 250,
                                  child: BarChartWidget(
                                    entries: barEntries,
                                    selectedScale: selectedScale,
                                    decimalPlaces: widget.decimalPlaces,
                                  ),
                                );

                                if (!shouldScroll) return chart;

                                return SingleChildScrollView(
                                  scrollDirection: Axis.horizontal,
                                  child: chart,
                                );
                              },
                            ),
                            const SizedBox(height: 14),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                _LegendDot(color: app_color, label: "Sales"),
                                const SizedBox(width: 18),
                                const _LegendDot(
                                  color: Color(0xFFFF8A3D),
                                  label: "Receipts",
                                ),
                              ],
                            ),
                          ],
                        ),
                ),
              ),
            if (widget.isVisibleLineChart)
              SliverToBoxAdapter(
                child: _AnalyticsCard(
                  margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                  title: "Monthly Sales Trend",
                  subtitle: "Comparison by year",
                  icon: Icons.show_chart_rounded,
                  accentColor: const Color(0xFF00A6A6),
                  child: lineMonths.isEmpty
                      ? const _EmptyState(
                          icon: Icons.timeline_outlined,
                          title: "No trend data",
                          message:
                              "There are no sales values to plot for this period.",
                        )
                      : Column(
                          children: [
                            SizedBox(
                              height: 280,
                              child: SingleChildScrollView(
                                scrollDirection: Axis.horizontal,
                                child: SizedBox(
                                  width: _chartWidth(
                                    context,
                                    lineMonths.length,
                                  ),
                                  child: _buildLineChart(lineMonths),
                                ),
                              ),
                            ),
                            const SizedBox(height: 12),
                            _buildYearLegend(),
                          ],
                        ),
                ),
              ),
            if (widget.isVisiblePieChart)
              SliverToBoxAdapter(
                child: _AnalyticsCard(
                  margin: const EdgeInsets.fromLTRB(16, 12, 16, 22),
                  title: "Category Breakdown",
                  subtitle: showPercentage
                      ? "Viewing percentage share"
                      : "Viewing amount share",
                  icon: Icons.donut_large_rounded,
                  accentColor: const Color(0xFF6C63FF),
                  trailing: _SegmentedToggle(
                    showPercentage: showPercentage,
                    onChanged: (value) =>
                        setState(() => showPercentage = value),
                  ),
                  child: Column(
                    children: [
                      //  _buildPieSalesRawData(),
                      // const SizedBox(height: 18),
                      if (widget.isSalesPieChartVisible)
                        _PieBreakdownSection(
                          title: "Sales",
                          data: _cleanPieData(widget.pieSalesList),
                          colors: _colorsFor(widget.pieSalesList.length),
                          showPercentage: showPercentage,
                          selectedScale: selectedScale,
                          decimalPlaces: widget.decimalPlaces,
                        ),
                      if (widget.isSalesPieChartVisible &&
                          widget.isPurchasePieChartVisible)
                        const SizedBox(height: 18),
                      if (widget.isPurchasePieChartVisible)
                        _PieBreakdownSection(
                          title: "Purchase",
                          data: _cleanPieData(widget.piePurchaseList),
                          colors: _colorsFor(
                            widget.piePurchaseList.length,
                            offset: 3,
                          ),
                          showPercentage: showPercentage,
                          selectedScale: selectedScale,
                          decimalPlaces: widget.decimalPlaces,
                        ),
                      if (!widget.isSalesPieChartVisible &&
                          !widget.isPurchasePieChartVisible)
                        const _EmptyState(
                          icon: Icons.pie_chart_outline_rounded,
                          title: "No breakdown selected",
                          message:
                              "Enable sales or purchase breakdown to view category share.",
                        ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(ThemeData theme) {
    final rangeLabel = _dateRangeLabel();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 10),
      decoration: BoxDecoration(
        color: app_color,
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(26)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            "Business overview",
            style: GoogleFonts.poppins(
              color: Colors.white,
              fontSize: 24,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            rangeLabel,
            style: GoogleFonts.poppins(
              color: Colors.white.withOpacity(0.82),
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _HeaderMetric(
                  label: "Sales",
                  value: '',
                  valueWidget: currencyAmountText(
                    currencyCode: CurrencyFormatter.getCurrencyCode(),
                    symbol: CurrencyFormatter.formatCurrencyParts(
                      _totalSales,
                    ).symbol,
                    amountText: CurrencyFormatter.formatCurrencyParts(
                      _totalSales,
                    ).number,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.poppins(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  icon: Icons.trending_up_rounded,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _HeaderMetric(
                  label: "Receipts",
                  value: '',
                  valueWidget: currencyAmountText(
                    currencyCode: CurrencyFormatter.getCurrencyCode(),
                    symbol: CurrencyFormatter.formatCurrencyParts(
                      _totalReceipts,
                    ).symbol,
                    amountText: CurrencyFormatter.formatCurrencyParts(
                      _totalReceipts,
                    ).number,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.poppins(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  icon: Icons.account_balance_wallet_rounded,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _dateRangeLabel() {
    try {
      final start = DateTime.parse(widget.startDateString);
      final end = DateTime.parse(widget.endDateString);
      return "${DateFormat('dd MMM yyyy').format(start)} - ${DateFormat('dd MMM yyyy').format(end)}";
    } catch (_) {
      return "Selected period";
    }
  }

  double _chartWidth(BuildContext context, int itemCount) {
    final screenWidth = MediaQuery.of(context).size.width - 64;
    final calculatedWidth = max(itemCount * 92.0, screenWidth);
    return calculatedWidth;
  }

  Widget _buildLineChart(List<String> months) {
    final maxY = _niceChartMax(_lineMaxY(months));
    final interval = maxY / 5;

    return Padding(
      padding: const EdgeInsets.only(top: 18, right: 14),
      child: LineChart(
        LineChartData(
          minX: months.length > 1 ? -0.15 : -0.5,
          maxX: months.length > 1 ? months.length - 0.85 : 0.5,
          minY: 0,
          maxY: maxY,
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            horizontalInterval: interval,
            getDrawingHorizontalLine: (value) =>
                FlLine(color: Theme.of(context).dividerColor, strokeWidth: 1),
          ),
          borderData: FlBorderData(show: false),
          titlesData: FlTitlesData(
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 62,
                interval: interval,
                getTitlesWidget: (value, meta) => Padding(
                  padding: const EdgeInsets.only(right: 10),
                  child: Text(
                    _formatCompact(value),
                    style: GoogleFonts.poppins(
                      fontSize: 11,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 44,
                interval: 1,
                getTitlesWidget: (value, meta) {
                  final index = value.round();
                  if ((value - index).abs() > 0.01) {
                    return const SizedBox.shrink();
                  }
                  if (index < 0 || index >= months.length)
                    return const SizedBox.shrink();
                  return Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: Text(
                      months[index],
                      style: GoogleFonts.poppins(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  );
                },
              ),
            ),
            rightTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
            topTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
          ),
          lineTouchData: LineTouchData(
            enabled: true,
            touchTooltipData: LineTouchTooltipData(
              getTooltipItems: (spots) {
                return spots.map((spot) {
                  return LineTooltipItem(
                    _formatCompact(spot.y),
                    GoogleFonts.poppins(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                      fontSize: 12,
                    ),
                  );
                }).toList();
              },
            ),
          ),
          lineBarsData: _lineBars(months),
        ),
      ),
    );
  }

  double _lineMaxY(List<String> months) {
    var maxValue = 0.0;

    for (final yearData in widget.lineChartData) {
      final values = yearData['value'];
      if (values is! Iterable) continue;

      for (final item in values) {
        if (item is! Map) continue;
        final month = item['month']?.toString();
        if (!months.contains(month)) continue;

        maxValue = max(maxValue, _asDouble(item['sales']).abs());
      }
    }

    return maxValue;
  }

  double _niceChartMax(double rawMax) {
    if (rawMax <= 0 || !rawMax.isFinite) return 1;

    final paddedMax = rawMax * 1.15;
    final exponent = (log(paddedMax) / ln10).floor();
    final magnitude = pow(10, exponent).toDouble();
    final normalized = paddedMax / magnitude;

    final niceNormalized = normalized <= 1
        ? 1
        : normalized <= 2
        ? 2
        : normalized <= 2.5
        ? 2.5
        : normalized <= 5
        ? 5
        : 10;

    return niceNormalized * magnitude;
  }

  List<LineChartBarData> _lineBars(List<String> months) {
    final bars = <LineChartBarData>[];

    for (
      var yearIndex = 0;
      yearIndex < widget.lineChartData.length;
      yearIndex++
    ) {
      final yearData = widget.lineChartData[yearIndex];
      final values = yearData['value'];
      if (values is! Iterable) continue;

      final spots = <FlSpot>[];
      for (final item in values) {
        if (item is! Map) continue;
        final month = item['month']?.toString();
        final monthIndex = months.indexOf(month ?? "");
        final sales = _asDouble(item['sales']).abs();

        if (monthIndex >= 0 && _hasValue(sales)) {
          spots.add(FlSpot(monthIndex.toDouble(), sales));
        }
      }

      if (spots.isEmpty) continue;

      final color =
          widget.yearColors[yearIndex] ??
          _chartPalette[yearIndex % _chartPalette.length];
      bars.add(
        LineChartBarData(
          spots: spots,
          isCurved: true,
          curveSmoothness: 0.24,
          color: color,
          barWidth: 3,
          isStrokeCapRound: true,
          dotData: FlDotData(
            show: true,
            getDotPainter: (spot, percent, barData, index) =>
                FlDotCirclePainter(
                  radius: 4,
                  color: Colors.white,
                  strokeWidth: 2,
                  strokeColor: color,
                ),
          ),
          belowBarData: BarAreaData(
            show: true,
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [color.withOpacity(0.22), color.withOpacity(0.02)],
            ),
          ),
        ),
      );
    }

    return bars;
  }

  Widget _buildYearLegend() {
    final items = <Widget>[];

    for (var i = 0; i < widget.lineChartData.length; i++) {
      final year = widget.lineChartData[i]['year']?.toString() ?? "";
      if (year.isEmpty) continue;
      final color =
          widget.yearColors[i] ?? _chartPalette[i % _chartPalette.length];
      items.add(_LegendDot(color: color, label: year));
    }

    if (items.isEmpty) return const SizedBox.shrink();

    return Wrap(
      spacing: 14,
      runSpacing: 8,
      alignment: WrapAlignment.center,
      children: items,
    );
  }

  List<Map<String, dynamic>> _cleanPieData(List<Map<String, dynamic>> rawData) {
    return rawData
        .where((item) {
          final amount = _asDouble(item['amount']).abs();
          return item['name'] != null && _hasValue(amount);
        })
        .toList(growable: false);
  }

  List<Color> _colorsFor(int count, {int offset = 0}) {
    return List.generate(
      count,
      (index) => _chartPalette[(index + offset) % _chartPalette.length],
    );
  }
}

class _MonthBarEntry {
  final String label;
  final double sales;
  final double receipt;

  const _MonthBarEntry({
    required this.label,
    required this.sales,
    required this.receipt,
  });
}

class _AnalyticsCard extends StatelessWidget {
  final EdgeInsetsGeometry margin;
  final String title;
  final String subtitle;
  final IconData icon;
  final Color accentColor;
  final Widget child;
  final Widget? trailing;

  const _AnalyticsCard({
    required this.margin,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.accentColor,
    required this.child,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: margin,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Theme.of(context).dividerColor),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: accentColor.withOpacity(0.11),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, color: accentColor, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: GoogleFonts.poppins(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: GoogleFonts.poppins(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              if (trailing != null) trailing!,
            ],
          ),
          const SizedBox(height: 18),
          child,
        ],
      ),
    );
  }
}

class _HeaderMetric extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Widget? valueWidget;

  const _HeaderMetric({
    required this.label,
    required this.value,
    required this.icon,
    this.valueWidget,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor.withOpacity(0.13),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: Colors.white, size: 20),
          const SizedBox(height: 10),
          valueWidget ??
              Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.poppins(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                ),
              ),
          const SizedBox(height: 2),
          Text(
            label,
            style: GoogleFonts.poppins(
              color: Colors.white.withOpacity(0.74),
              fontSize: 11,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

class _SummaryTile extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _SummaryTile({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: GoogleFonts.poppins(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.poppins(
              fontSize: 14,
              fontWeight: FontWeight.w800,
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
        ],
      ),
    );
  }
}

class _MetricPill extends StatelessWidget {
  final String label;
  final String caption;

  const _MetricPill({required this.label, required this.caption});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).brightness == Brightness.dark
            ? Theme.of(context).colorScheme.surfaceContainerHighest
            : const Color(0xFFF1F4F9),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: GoogleFonts.poppins(
              fontSize: 13,
              fontWeight: FontWeight.w800,
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
          const SizedBox(width: 4),
          Text(
            caption,
            style: GoogleFonts.poppins(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _SegmentedToggle extends StatelessWidget {
  final bool showPercentage;
  final ValueChanged<bool> onChanged;

  const _SegmentedToggle({
    required this.showPercentage,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: Theme.of(context).brightness == Brightness.dark
            ? Theme.of(context).colorScheme.surfaceContainerHighest
            : const Color(0xFFF1F4F9),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _ToggleButton(
            label: "123",
            active: !showPercentage,
            onTap: () => onChanged(false),
          ),
          _ToggleButton(
            label: "%",
            active: showPercentage,
            onTap: () => onChanged(true),
          ),
        ],
      ),
    );
  }
}

class _ToggleButton extends StatelessWidget {
  final String label;
  final bool active;
  final VoidCallback onTap;

  const _ToggleButton({
    required this.label,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: active ? app_color : Colors.transparent,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          label,
          style: GoogleFonts.poppins(
            fontSize: 12,
            fontWeight: FontWeight.w800,
            color: active
                ? Colors.white
                : Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}

class _PieBreakdownSection extends StatelessWidget {
  final String title;
  final List<Map<String, dynamic>> data;
  final List<Color> colors;
  final bool showPercentage;
  final NumberScale selectedScale;
  final int decimalPlaces;

  const _PieBreakdownSection({
    required this.title,
    required this.data,
    required this.colors,
    required this.showPercentage,
    required this.selectedScale,
    required this.decimalPlaces,
  });

  double get total {
    return data.fold<double>(0, (sum, item) {
      final amount = (item['amount'] is num)
          ? (item['amount'] as num).toDouble()
          : double.tryParse(item['amount']?.toString() ?? "") ?? 0.0;
      return sum + amount.abs();
    });
  }

  @override
  Widget build(BuildContext context) {
    if (data.isEmpty || total <= 0) {
      return _EmptyState(
        icon: Icons.pie_chart_outline_rounded,
        title: "No $title data",
        message: "There is no amount to display in this breakdown.",
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: GoogleFonts.poppins(
            fontSize: 15,
            fontWeight: FontWeight.w800,
            color: Theme.of(context).colorScheme.onSurface,
          ),
        ),
        const SizedBox(height: 12),
        LayoutBuilder(
          builder: (context, constraints) {
            final isPhoneWidth = constraints.maxWidth < 520;
            final chartSize = isPhoneWidth
                ? min(230.0, constraints.maxWidth - 24)
                : min(190.0, constraints.maxWidth * 0.42);
            final chart = Center(
              child: Container(
                width: chartSize,
                height: chartSize * 0.78,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.16),
                      blurRadius: 24,
                      offset: const Offset(0, 14),
                    ),
                  ],
                ),
                child: Transform(
                  alignment: Alignment.center,
                  transform: Matrix4.identity()
                    ..setEntry(3, 2, 0.0012)
                    ..rotateX(0.88),
                  child: Stack(
                    clipBehavior: Clip.none,
                    alignment: Alignment.center,
                    children: [
                      Transform.translate(
                        offset: Offset(0, chartSize * 0.11),
                        child: PieChart(
                          PieChartData(
                            centerSpaceRadius: chartSize * 0.24,
                            sectionsSpace: 2.8,
                            startDegreeOffset: -90,
                            borderData: FlBorderData(show: false),
                            sections: _sections(chartSize, depthLayer: true),
                          ),
                        ),
                      ),
                      PieChart(
                        PieChartData(
                          centerSpaceRadius: chartSize * 0.24,
                          sectionsSpace: 2.8,
                          startDegreeOffset: -90,
                          borderData: FlBorderData(show: false),
                          sections: _sections(chartSize),
                        ),
                      ),
                      IgnorePointer(
                        child: Container(
                          width: chartSize * 0.86,
                          height: chartSize * 0.86,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: RadialGradient(
                              center: const Alignment(-0.45, -0.55),
                              radius: 0.95,
                              colors: [
                                Colors.white.withOpacity(
                                  Theme.of(context).brightness ==
                                          Brightness.dark
                                      ? 0.08
                                      : 0.30,
                                ),
                                Colors.white.withOpacity(
                                  Theme.of(context).brightness ==
                                          Brightness.dark
                                      ? 0.02
                                      : 0.07,
                                ),
                                Colors.transparent,
                              ],
                              stops: const [0.0, 0.34, 0.72],
                            ),
                          ),
                        ),
                      ),
                      Container(
                        width: chartSize * 0.42,
                        height: chartSize * 0.42,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Theme.of(context).cardColor,
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.12),
                              blurRadius: 18,
                              offset: const Offset(0, 10),
                            ),
                            BoxShadow(
                              color:
                                  Theme.of(context).brightness ==
                                      Brightness.dark
                                  ? Colors.transparent
                                  : Colors.white.withOpacity(0.8),
                              blurRadius: 10,
                              offset: const Offset(-4, -5),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );

            final legend = _PieLegend(
              data: data,
              colors: colors,
              total: total,
              showPercentage: showPercentage,
            );

            if (isPhoneWidth) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [chart, const SizedBox(height: 14), legend],
              );
            }

            return Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(child: chart),
                const SizedBox(width: 14),
                Expanded(child: legend),
              ],
            );
          },
        ),
      ],
    );
  }

  List<PieChartSectionData> _sections(
    double chartSize, {
    bool depthLayer = false,
  }) {
    return List.generate(data.length, (index) {
      final item = data[index];
      final amount = (item['amount'] is num)
          ? (item['amount'] as num).toDouble().abs()
          : (double.tryParse(item['amount']?.toString() ?? "") ?? 0.0).abs();
      final ratio = total == 0 ? 0.0 : amount / total;
      final color = colors[index % colors.length];
      final sectionColor = depthLayer ? _darken(color, 0.34) : color;

      return PieChartSectionData(
        value: amount,
        radius: chartSize * 0.31,
        title: depthLayer
            ? ""
            : ratio >= 0.14
            ? showPercentage
                  ? "${(ratio * 100).toStringAsFixed(1)}%"
                  : formatNumberAbbreviation(
                      amount,
                      scale: selectedScale,
                      decimalPlaces: decimalPlaces,
                      showSuffix: false,
                    )
            : "",
        titleStyle: GoogleFonts.poppins(
          fontSize: 10,
          fontWeight: FontWeight.w800,
          color: Colors.white,
        ),
        color: sectionColor,
        gradient: depthLayer
            ? null
            : LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [_lighten(color, 0.20), color, _darken(color, 0.18)],
                stops: const [0.0, 0.56, 1.0],
              ),
      );
    });
  }

  Color _darken(Color color, double amount) {
    final hsl = HSLColor.fromColor(color);
    return hsl
        .withLightness((hsl.lightness - amount).clamp(0.0, 1.0))
        .toColor();
  }

  Color _lighten(Color color, double amount) {
    final hsl = HSLColor.fromColor(color);
    return hsl
        .withLightness((hsl.lightness + amount).clamp(0.0, 1.0))
        .toColor();
  }
}

class _PieLegend extends StatelessWidget {
  final List<Map<String, dynamic>> data;
  final List<Color> colors;
  final double total;
  final bool showPercentage;

  const _PieLegend({
    required this.data,
    required this.colors,
    required this.total,
    required this.showPercentage,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: List.generate(data.length, (index) {
        final item = data[index];
        final name = item['name']?.toString() ?? "";
        final amount = (item['amount'] is num)
            ? (item['amount'] as num).toDouble().abs()
            : (double.tryParse(item['amount']?.toString() ?? "") ?? 0.0).abs();
        final color = colors[index % colors.length];
        final value = showPercentage
            ? "${(total == 0 ? 0 : amount / total * 100).toStringAsFixed(1)}%"
            : null;
        final valueStyle = GoogleFonts.poppins(
          fontSize: 11,
          fontWeight: FontWeight.w800,
          color: Theme.of(context).colorScheme.onSurface,
        );

        return Container(
          margin: EdgeInsets.only(bottom: index == data.length - 1 ? 0 : 8),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: Theme.of(context).brightness == Brightness.dark
                ? Theme.of(context).colorScheme.surfaceContainerHighest
                : const Color(0xFFF7F9FC),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.poppins(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              value != null
                  ? Text(value, style: valueStyle)
                  : currencyAmountText(
                      currencyCode: CurrencyFormatter.getCurrencyCode(),
                      symbol: CurrencyFormatter.formatCurrencyParts(
                        amount,
                      ).symbol,
                      amountText: CurrencyFormatter.formatCurrencyParts(
                        amount,
                      ).number,
                      style: valueStyle,
                    ),
            ],
          ),
        );
      }),
    );
  }
}

class _LegendDot extends StatelessWidget {
  final Color color;
  final String label;

  const _LegendDot({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: GoogleFonts.poppins(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

class _EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;

  const _EmptyState({
    required this.icon,
    required this.title,
    required this.message,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 30),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: Theme.of(context).brightness == Brightness.dark
                    ? Theme.of(context).colorScheme.surfaceContainerHighest
                    : const Color(0xFFF1F4F9),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(
                icon,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              title,
              textAlign: TextAlign.center,
              style: GoogleFonts.poppins(
                fontSize: 15,
                fontWeight: FontWeight.w800,
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              message,
              textAlign: TextAlign.center,
              style: GoogleFonts.poppins(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class BarChartWidget extends StatelessWidget {
  final List<_MonthBarEntry> entries;
  final NumberScale selectedScale;
  final int decimalPlaces;

  const BarChartWidget({
    super.key,
    required this.entries,
    required this.selectedScale,
    required this.decimalPlaces,
  });

  @override
  Widget build(BuildContext context) {
    final maxValue = _maxValue();

    return BarChart(
      BarChartData(
        alignment: entries.length <= 2
            ? BarChartAlignment.center
            : BarChartAlignment.spaceAround,
        maxY: maxValue == 0 ? 1 : maxValue * 1.18,
        groupsSpace: entries.length <= 2 ? 28 : 18,
        barGroups: _barGroups(context, maxValue),
        barTouchData: BarTouchData(
          enabled: true,
          touchTooltipData: BarTouchTooltipData(
            tooltipPadding: const EdgeInsets.symmetric(
              horizontal: 10,
              vertical: 8,
            ),
            tooltipMargin: 8,
            getTooltipItem: (group, groupIndex, rod, rodIndex) {
              final label = rodIndex == 0 ? "Sales" : "Receipt";
              return BarTooltipItem(
                "$label\n${formatNumberAbbreviation(rod.toY, scale: selectedScale, decimalPlaces: decimalPlaces, showSuffix: false)}",
                GoogleFonts.poppins(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                ),
              );
            },
          ),
        ),
        titlesData: FlTitlesData(
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 42,
              interval: 1,
              getTitlesWidget: (value, meta) {
                final index = value.toInt();
                if (index < 0 || index >= entries.length)
                  return const SizedBox.shrink();
                return Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Text(
                    entries[index].label,
                    style: GoogleFonts.poppins(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                );
              },
            ),
          ),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 58,
              maxIncluded: false,
              getTitlesWidget: (value, meta) {
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Text(
                    formatNumberAbbreviation(
                      value,
                      scale: selectedScale,
                      decimalPlaces: decimalPlaces,
                      showSuffix: false,
                    ),
                    style: GoogleFonts.poppins(
                      fontSize: 11,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                );
              },
            ),
          ),
          topTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          rightTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
        ),
        borderData: FlBorderData(show: false),
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          getDrawingHorizontalLine: (value) =>
              FlLine(color: Theme.of(context).dividerColor, strokeWidth: 1),
        ),
      ),
    );
  }

  double _maxValue() {
    final values = <double>[];
    for (final entry in entries) {
      if (entry.sales.isFinite) values.add(entry.sales.abs());
      if (entry.receipt.isFinite) values.add(entry.receipt.abs());
    }
    if (values.isEmpty) return 0;
    return values.reduce(max);
  }

  List<BarChartGroupData> _barGroups(BuildContext context, double maxValue) {
    final backgroundRodColor = Theme.of(context).brightness == Brightness.dark
        ? Theme.of(context).colorScheme.surfaceContainerHighest
        : const Color(0xFFF1F4F9);
    return List.generate(entries.length, (index) {
      final entry = entries[index];
      return BarChartGroupData(
        x: index,
        barsSpace: 7,
        barRods: [
          BarChartRodData(
            fromY: 0,
            toY: entry.sales.abs(),
            width: 13,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
            color: app_color,
            backDrawRodData: BackgroundBarChartRodData(
              show: true,
              toY: maxValue == 0 ? 1 : maxValue * 1.12,
              color: backgroundRodColor,
            ),
          ),
          BarChartRodData(
            fromY: 0,
            toY: entry.receipt.abs(),
            width: 13,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
            color: const Color(0xFFFF8A3D),
            backDrawRodData: BackgroundBarChartRodData(
              show: true,
              toY: maxValue == 0 ? 1 : maxValue * 1.12,
              color: backgroundRodColor,
            ),
          ),
        ],
      );
    });
  }
}
