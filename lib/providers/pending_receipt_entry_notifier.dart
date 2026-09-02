import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../PendingReceiptEntry.dart';
import '../api/api_exception.dart';
import '../api/voucher_entry_repository.dart';
import '../api/voucher_type_repository.dart';

/// Riverpod migration of `PendingReceiptEntry.dart`'s
/// `_PendingReceiptEntryPageState` - same shape as the other Pending*
/// screens (plain fetch/filter/delete list), moved entirely to a
/// StateNotifier.
///
/// Dead fields dropped rather than ported (same pattern as the other
/// Pending* screens): `isDashEnable`, `isUserEnable`, `isRolesEnable`,
/// `isRolesVisible`, `isUserVisible`, `rolename_fetched`, `hostname`,
/// `company`, `company_lowercase`, `username`, `HttpURL`,
/// `SecuritybtnAcessHolder`, `name`, `email`, and the never-called
/// `isVanSalesSerial` getter. Only `serial_no` (read by `build()`'s
/// `canActOnCard` check) is a real session field.
class PendingReceiptEntryState {
  final List<ReceiptModel> receiptEntries;
  final List<ReceiptModel> filteredReceiptEntries;
  final bool isVisibleNoReceiptEntryFound;
  final bool isLoading;
  final String? serialNo;
  final DateTime? selectedSingleDate;
  final DateTimeRange? selectedDateRange;

  const PendingReceiptEntryState({
    required this.receiptEntries,
    required this.filteredReceiptEntries,
    required this.isVisibleNoReceiptEntryFound,
    required this.isLoading,
    required this.serialNo,
    required this.selectedSingleDate,
    required this.selectedDateRange,
  });
}

class PendingReceiptEntryNotifier
    extends StateNotifier<PendingReceiptEntryState> {
  PendingReceiptEntryNotifier()
    : super(
        const PendingReceiptEntryState(
          receiptEntries: [],
          filteredReceiptEntries: [],
          isVisibleNoReceiptEntryFound: false,
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

  PendingReceiptEntryState _snapshot() => PendingReceiptEntryState(
    receiptEntries: List.unmodifiable(receiptentries),
    filteredReceiptEntries: List.unmodifiable(filteredReceiptEntries),
    isVisibleNoReceiptEntryFound: isVisibleNoReceiptEntryFound,
    isLoading: _isLoading,
    serialNo: serial_no,
    selectedSingleDate: _selectedSingleDate,
    selectedDateRange: _selectedDateRange,
  );

  // ---- verbatim-ported mutable fields (same names as the original State) ----

  final List<ReceiptModel> receiptentries = [];
  List<ReceiptModel> filteredReceiptEntries = [];
  bool isVisibleNoReceiptEntryFound = false;
  bool _isLoading = false;
  String? serial_no = '';

  String _searchQuery = '';
  DateTime? _selectedSingleDate;
  DateTimeRange? _selectedDateRange;

  /// Verbatim port of `entrydelete`, minus the `showAppMessage`/context
  /// calls.
  Future<String?> entrydelete(String id) async {
    _commit(() => _isLoading = true);
    String? error;
    try {
      await VoucherEntryRepository.instance.remove(id);
      await fetchReceiptEntries();
      return null;
    } on ApiException catch (e) {
      error = e.message;
    } catch (e) {
      error = 'Could not reach the server. Please try again.';
    }
    _commit(() => _isLoading = false);
    return error;
  }

  /// The party ledger entry among a voucher entry's `ledgerEntries` -
  /// verbatim port of the widget's `_partyLedgerEntry` (also called by
  /// `build()` directly, so that copy stays widget-local too - this is a
  /// pure function with no state, safe to have in both places).
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

  /// Verbatim port of `fetchReceiptEntries`, minus the `showAppMessage`
  /// context call and the `_searchController.clear()`/`FocusManager`
  /// widget-local resets.
  Future<String?> fetchReceiptEntries() async {
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
        voucherTypeName = spectraAllocations.first['receipt_voucher_type'];
      }
    }

    String? error;
    try {
      final receiptVoucherTypes = await VoucherTypeRepository.instance
          .byReservedName('RECEIPT');

      Set<int> allowedVoucherTypeMasterIds = receiptVoucherTypes
          .map((v) => v['masterId'] as int)
          .toSet();

      if (voucherTypeName != null && voucherTypeName.trim().isNotEmpty) {
        final named = receiptVoucherTypes
            .where((v) => v['name'] == voucherTypeName)
            .map((v) => v['masterId'] as int)
            .toSet();
        if (named.isNotEmpty) {
          allowedVoucherTypeMasterIds = named;
        }
      }

      final allEntries = await VoucherEntryRepository.instance.listAll();

      final receiptEntriesRaw = allEntries.where((e) {
        final masterId = e['voucherTypeMasterId'];
        return masterId is int && allowedVoucherTypeMasterIds.contains(masterId);
      }).toList();

      receiptentries.clear();
      filteredReceiptEntries.clear();

      isVisibleNoReceiptEntryFound = false;

      receiptentries.addAll(
        receiptEntriesRaw.map(
          (e) => ReceiptModel(
            id: e['id'].toString(),
            data: e,
            type: (e['voucherTypeName'] ?? 'Receipt').toString(),
            isSynced: 0,
            message: null,
          ),
        ),
      );

      receiptentries.sort((a, b) {
        DateTime dateA = DateTime.parse(a.data['date']);
        DateTime dateB = DateTime.parse(b.data['date']);
        if (dateA != dateB) return dateB.compareTo(dateA);
        final vchA =
            int.tryParse((a.data['voucherNumber'] ?? '').toString()) ?? 0;
        final vchB =
            int.tryParse((b.data['voucherNumber'] ?? '').toString()) ?? 0;
        return vchB.compareTo(vchA);
      });
      filteredReceiptEntries = List.from(receiptentries);

      _commit(() {
        _searchQuery = '';
        _selectedSingleDate = null;
        _selectedDateRange = null;
      });

      _commit(() {
        if (filteredReceiptEntries.isEmpty) {
          isVisibleNoReceiptEntryFound = true;
        }
        _isLoading = false;
      });
      return null;
    } on ApiException catch (e) {
      error = e.message;
      _commit(() => _isLoading = false);
    } catch (e) {
      error = 'Could not reach the server. Please try again.';
      _commit(() => _isLoading = false);
    }

    _commit(() {
      if (filteredReceiptEntries.isEmpty) {
        isVisibleNoReceiptEntryFound = true;
      }
      _isLoading = false;
    });
    return error;
  }

  void searchReceipt(String query) {
    _searchQuery = query.trim().toLowerCase();
    _applyFilters();
  }

  void _applyFilters() {
    final query = _searchQuery;

    _commit(() {
      filteredReceiptEntries = receiptentries.where((entry) {
        final data = entry.data;
        final partyEntry = _partyLedgerEntry(data);

        final party = (partyEntry?['ledgerName'] ?? '')
            .toString()
            .toLowerCase();
        final vchno = (data['voucherNumber'] ?? '').toString().toLowerCase();
        final vchtype = (data['voucherTypeName'] ?? '')
            .toString()
            .toLowerCase();
        final amount = (partyEntry?['amount'] ?? '').toString().toLowerCase();

        final bool matchesSearch =
            query.isEmpty ||
            party.contains(query) ||
            vchno.contains(query) ||
            vchtype.contains(query) ||
            amount.contains(query);

        final bool matchesDate = _matchesDateFilter(entry);

        return matchesSearch && matchesDate;
      }).toList();

      isVisibleNoReceiptEntryFound = filteredReceiptEntries.isEmpty;
    });
  }

  bool _matchesDateFilter(ReceiptModel entry) {
    final dateValue = entry.data['date'];

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
    await fetchReceiptEntries();
  }
}

final pendingReceiptEntryNotifierProvider = StateNotifierProvider.autoDispose<
    PendingReceiptEntryNotifier, PendingReceiptEntryState>(
  (ref) => PendingReceiptEntryNotifier(),
);
