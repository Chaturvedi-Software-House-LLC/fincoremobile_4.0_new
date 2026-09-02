import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../PendingSalesOrderEntry.dart';
import '../api/api_exception.dart';
import '../api/voucher_entry_repository.dart';
import '../api/voucher_type_repository.dart';

/// Riverpod migration of `PendingSalesOrderEntry.dart`'s
/// `_PendingSalesOrderEntryPageState` - same shape as
/// `pending_sales_entry_notifier.dart` (plain fetch/filter/delete list, no
/// accumulator logic), moved entirely to a StateNotifier.
///
/// Dead fields dropped rather than ported (same pattern as
/// `PendingSalesEntry.dart`): `isDashEnable`, `isUserEnable`,
/// `isRolesEnable`, `isRolesVisible`, `isUserVisible`, `rolename_fetched`,
/// `hostname`, `company`, `company_lowercase`, `username`, `HttpURL`,
/// `SecuritybtnAcessHolder`, `name`, `email`, and the never-called
/// `isVanSalesSerial` getter. Only `serial_no` (read by `build()`'s
/// `canActOnCard` check) is a real session field.
class PendingSalesOrderEntryState {
  final List<SalesOrderModel> salesOrderEntries;
  final List<SalesOrderModel> filteredSalesOrderEntries;
  final bool isVisibleNoSalesOrderEntryFound;
  final bool isLoading;
  final String? serialNo;
  final DateTime? selectedSingleDate;
  final DateTimeRange? selectedDateRange;

  const PendingSalesOrderEntryState({
    required this.salesOrderEntries,
    required this.filteredSalesOrderEntries,
    required this.isVisibleNoSalesOrderEntryFound,
    required this.isLoading,
    required this.serialNo,
    required this.selectedSingleDate,
    required this.selectedDateRange,
  });
}

class PendingSalesOrderEntryNotifier
    extends StateNotifier<PendingSalesOrderEntryState> {
  PendingSalesOrderEntryNotifier()
    : super(
        const PendingSalesOrderEntryState(
          salesOrderEntries: [],
          filteredSalesOrderEntries: [],
          isVisibleNoSalesOrderEntryFound: false,
          isLoading: false,
          serialNo: '',
          selectedSingleDate: null,
          selectedDateRange: null,
        ),
      ) {
    _init();
  }

  void _commit(void Function() fn) {
    fn();
    state = _snapshot();
  }

  PendingSalesOrderEntryState _snapshot() => PendingSalesOrderEntryState(
    salesOrderEntries: List.unmodifiable(salesorderentries),
    filteredSalesOrderEntries: List.unmodifiable(filteredSalesOrderEntries),
    isVisibleNoSalesOrderEntryFound: isVisibleNoSalesOrderEntryFound,
    isLoading: _isLoading,
    serialNo: serial_no,
    selectedSingleDate: _selectedSingleDate,
    selectedDateRange: _selectedDateRange,
  );

  // ---- verbatim-ported mutable fields (same names as the original State) ----

  final List<SalesOrderModel> salesorderentries = [];
  List<SalesOrderModel> filteredSalesOrderEntries = [];
  bool isVisibleNoSalesOrderEntryFound = false;
  bool _isLoading = false;
  String? serial_no = '';

  String _searchQuery = '';
  DateTime? _selectedSingleDate;
  DateTimeRange? _selectedDateRange;

  /// Verbatim port of `entrydelete`, minus the `showAppMessage`/context
  /// calls.
  Future<String?> entrydelete(int id) async {
    _commit(() => _isLoading = true);
    String? error;
    try {
      final match = salesorderentries.firstWhere((e) => e.id == id);
      await VoucherEntryRepository.instance.remove(match.entryId);
      await fetchSalesOrderEntries();
      return null;
    } on ApiException catch (e) {
      error = e.message;
    } catch (e) {
      error = 'Could not reach the server. Please try again.';
    }
    _commit(() => _isLoading = false);
    return error;
  }

  /// Verbatim port of `fetchSalesOrderEntries`, minus the `showAppMessage`
  /// context call and the `_searchController.clear()`/`FocusManager`
  /// widget-local resets.
  Future<String?> fetchSalesOrderEntries() async {
    _commit(() => _isLoading = true);
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
        voucherTypeName = spectraAllocations.first['salesorder_voucher_type'];
      }
    }

    String? error;
    try {
      final salesOrderVoucherTypes = await VoucherTypeRepository.instance
          .byReservedName('SALES_ORDER');
      final allowedMasterIds = salesOrderVoucherTypes
          .map((v) => v['masterId'])
          .toSet();

      final entries = await VoucherEntryRepository.instance.listAll();

      final matching = entries.where((e) {
        if (!allowedMasterIds.contains(e['voucherTypeMasterId'])) {
          return false;
        }
        if (voucherTypeName != null && voucherTypeName!.trim().isNotEmpty) {
          return (e['voucherTypeName'] ?? '').toString() == voucherTypeName;
        }
        return true;
      }).toList();

      salesorderentries.clear();
      filteredSalesOrderEntries.clear();

      int seq = 0;
      salesorderentries.addAll(
        matching.map((e) => SalesOrderModel.fromEntry(e, seq++)),
      );

      salesorderentries.sort((a, b) {
        DateTime dateA = DateTime.parse(a.data['DATE']);
        DateTime dateB = DateTime.parse(b.data['DATE']);
        if (dateA != dateB) return dateB.compareTo(dateA);
        final vchA =
            int.tryParse((a.data['VOUCHERNUMBER'] ?? '').toString()) ?? 0;
        final vchB =
            int.tryParse((b.data['VOUCHERNUMBER'] ?? '').toString()) ?? 0;
        return vchB.compareTo(vchA);
      });

      filteredSalesOrderEntries = List.from(salesorderentries);

      _commit(() {
        _searchQuery = '';
        _selectedSingleDate = null;
        _selectedDateRange = null;
        isVisibleNoSalesOrderEntryFound = filteredSalesOrderEntries.isEmpty;
        _isLoading = false;
      });
      return null;
    } on ApiException catch (e) {
      error = e.message;
      _commit(() {
        if (filteredSalesOrderEntries.isEmpty) {
          isVisibleNoSalesOrderEntryFound = true;
        }
        _isLoading = false;
      });
    } catch (e) {
      error = 'Could not reach the server. Please try again.';
      _commit(() {
        if (filteredSalesOrderEntries.isEmpty) {
          isVisibleNoSalesOrderEntryFound = true;
        }
        _isLoading = false;
      });
    }
    return error;
  }

  void searchSalesOrder(String query) {
    _searchQuery = query.trim().toLowerCase();
    _applyFilters();
  }

  void _applyFilters() {
    final query = _searchQuery;

    _commit(() {
      filteredSalesOrderEntries = salesorderentries.where((entry) {
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

      isVisibleNoSalesOrderEntryFound = filteredSalesOrderEntries.isEmpty;
    });
  }

  bool _matchesDateFilter(SalesOrderModel entry) {
    final dateValue = entry.data['DATE'];

    if (dateValue == null) return false;

    final entryDate = DateTime.tryParse(dateValue.toString());

    if (entryDate == null) return false;

    final onlyEntryDate = DateTime(
      entryDate.year,
      entryDate.month,
      entryDate.day,
    );

    if (_selectedSingleDate != null) {
      final selected = DateTime(
        _selectedSingleDate!.year,
        _selectedSingleDate!.month,
        _selectedSingleDate!.day,
      );

      return onlyEntryDate == selected;
    }

    if (_selectedDateRange != null) {
      final start = DateTime(
        _selectedDateRange!.start.year,
        _selectedDateRange!.start.month,
        _selectedDateRange!.start.day,
      );

      final end = DateTime(
        _selectedDateRange!.end.year,
        _selectedDateRange!.end.month,
        _selectedDateRange!.end.day,
      );

      return onlyEntryDate.isAtSameMomentAs(start) ||
          onlyEntryDate.isAtSameMomentAs(end) ||
          (onlyEntryDate.isAfter(start) && onlyEntryDate.isBefore(end));
    }

    return true;
  }

  void setSingleDateFilter(DateTime? date) {
    _selectedSingleDate = date;
    _selectedDateRange = null;
    _applyFilters();
  }

  void setDateRangeFilter(DateTimeRange? range) {
    _selectedDateRange = range;
    _selectedSingleDate = null;
    _applyFilters();
  }

  void clearDateFilter() {
    _selectedSingleDate = null;
    _selectedDateRange = null;
    _applyFilters();
  }

  Future<void> _init() async {
    final prefs = await SharedPreferences.getInstance();
    serial_no = prefs.getString('serial_no');
    _commit(() {});
    await fetchSalesOrderEntries();
  }
}

final pendingSalesOrderEntryNotifierProvider = StateNotifierProvider
    .autoDispose<PendingSalesOrderEntryNotifier, PendingSalesOrderEntryState>(
      (ref) => PendingSalesOrderEntryNotifier(),
    );
