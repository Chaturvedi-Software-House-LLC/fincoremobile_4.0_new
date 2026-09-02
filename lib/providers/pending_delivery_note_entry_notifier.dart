import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../PendingDeliveryNoteEntry.dart';
import '../api/api_exception.dart';
import '../api/voucher_entry_repository.dart';
import '../api/voucher_type_repository.dart';

/// Riverpod migration of `PendingDeliveryNoteEntry.dart`'s
/// `_PendingDeliveryNoteEntryPageState` - same shape as the other Pending*
/// screens (plain fetch/filter/delete list), moved entirely to a
/// StateNotifier.
///
/// Dead fields dropped rather than ported (same pattern as the other
/// Pending* screens): `isDashEnable`, `isUserEnable`, `isRolesEnable`,
/// `isRolesVisible`, `isUserVisible`, `rolename_fetched`, `hostname`,
/// `company`, `company_lowercase`, `username`, `HttpURL`,
/// `SecuritybtnAcessHolder`, `name`, `email`. Only `serial_no` (read by
/// `build()`'s `canActOnCard` check) is a real session field.
class PendingDeliveryNoteEntryState {
  final List<SalesModel> deliveryNoteEntries;
  final List<SalesModel> filteredDeliveryNoteEntries;
  final bool isVisibleNoDeliveryNoteEntryFound;
  final bool isLoading;
  final String? serialNo;
  final DateTime? selectedSingleDate;
  final DateTimeRange? selectedDateRange;

  const PendingDeliveryNoteEntryState({
    required this.deliveryNoteEntries,
    required this.filteredDeliveryNoteEntries,
    required this.isVisibleNoDeliveryNoteEntryFound,
    required this.isLoading,
    required this.serialNo,
    required this.selectedSingleDate,
    required this.selectedDateRange,
  });
}

class PendingDeliveryNoteEntryNotifier
    extends StateNotifier<PendingDeliveryNoteEntryState> {
  PendingDeliveryNoteEntryNotifier()
    : super(
        const PendingDeliveryNoteEntryState(
          deliveryNoteEntries: [],
          filteredDeliveryNoteEntries: [],
          isVisibleNoDeliveryNoteEntryFound: false,
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

  PendingDeliveryNoteEntryState _snapshot() => PendingDeliveryNoteEntryState(
    deliveryNoteEntries: List.unmodifiable(deliverynoteentries),
    filteredDeliveryNoteEntries: List.unmodifiable(
      filteredDeliveryNoteEntries,
    ),
    isVisibleNoDeliveryNoteEntryFound: isVisibleNoDeliveryNoteEntryFound,
    isLoading: _isLoading,
    serialNo: serial_no,
    selectedSingleDate: _selectedSingleDate,
    selectedDateRange: _selectedDateRange,
  );

  // ---- verbatim-ported mutable fields (same names as the original State) ----

  final List<SalesModel> deliverynoteentries = [];
  List<SalesModel> filteredDeliveryNoteEntries = [];
  bool isVisibleNoDeliveryNoteEntryFound = false;
  bool _isLoading = false;
  String? serial_no = '';

  String _searchQuery = '';
  DateTime? _selectedSingleDate;
  DateTimeRange? _selectedDateRange;

  /// Verbatim port of `entrydelete`, minus the `showAppMessage`/context
  /// calls.
  Future<String?> entrydelete(String entryId) async {
    _commit(() => _isLoading = true);
    String? error;
    try {
      await VoucherEntryRepository.instance.remove(entryId);
      await fetchDeliveryNoteEntries();
      return null;
    } on ApiException catch (e) {
      error = e.message;
    } catch (e) {
      error = 'Server Error!!!';
    }
    _commit(() => _isLoading = false);
    return error;
  }

  /// Verbatim port of `fetchDeliveryNoteEntries`, minus the
  /// `showAppMessage` context call and the `_searchController.clear()`/
  /// `FocusManager` widget-local resets.
  Future<String?> fetchDeliveryNoteEntries() async {
    _commit(() => _isLoading = true);

    String? error;
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
          voucherTypeName = spectraAllocations.first['voucher_type'];
        }
      }

      final deliveryNoteVoucherTypes = await VoucherTypeRepository.instance
          .byReservedName('DELIVERY_NOTE');

      final Set<int> deliveryNoteVoucherTypeMasterIds =
          deliveryNoteVoucherTypes
              .map<int>((v) => (v['masterId'] as num).toInt())
              .toSet();

      final allEntries = await VoucherEntryRepository.instance.listAll();

      final bool hasVoucherTypeNameFilter =
          voucherTypeName != null && voucherTypeName.trim().isNotEmpty;

      final mapped = allEntries
          .where(
            (json) => deliveryNoteVoucherTypeMasterIds.contains(
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

      deliverynoteentries.clear();
      filteredDeliveryNoteEntries.clear();

      isVisibleNoDeliveryNoteEntryFound = false;

      deliverynoteentries.addAll(mapped);

      deliverynoteentries.sort((a, b) {
        DateTime dateA = DateTime.parse(a.data['DATE'].toString());
        DateTime dateB = DateTime.parse(b.data['DATE'].toString());
        if (dateA != dateB) return dateB.compareTo(dateA);
        final vchA =
            int.tryParse((a.data['VOUCHERNUMBER'] ?? '').toString()) ?? 0;
        final vchB =
            int.tryParse((b.data['VOUCHERNUMBER'] ?? '').toString()) ?? 0;
        return vchB.compareTo(vchA);
      });

      filteredDeliveryNoteEntries = List.from(deliverynoteentries);

      _commit(() {
        _searchQuery = '';
        _selectedSingleDate = null;
        _selectedDateRange = null;

        if (filteredDeliveryNoteEntries.isEmpty) {
          isVisibleNoDeliveryNoteEntryFound = true;
        }

        _isLoading = false;
      });
      return null;
    } on ApiException catch (e) {
      error = e.message;
      _commit(() {
        if (filteredDeliveryNoteEntries.isEmpty) {
          isVisibleNoDeliveryNoteEntryFound = true;
        }
        _isLoading = false;
      });
    } catch (e) {
      _commit(() => _isLoading = false);
    }
    return error;
  }

  void searchSales(String query) {
    _searchQuery = query.trim().toLowerCase();
    _applyFilters();
  }

  void _applyFilters() {
    final query = _searchQuery;

    _commit(() {
      filteredDeliveryNoteEntries = deliverynoteentries.where((entry) {
        final data = entry.data;

        final party = (data['PARTYLEDGERNAME'] ?? '').toString().toLowerCase();
        final vchno = (data['VOUCHERNUMBER'] ?? '').toString().toLowerCase();
        final vchtype = (data['VOUCHERTYPENAME'] ?? '')
            .toString()
            .toLowerCase();

        final bool matchesSearch =
            query.isEmpty ||
            party.contains(query) ||
            vchno.contains(query) ||
            vchtype.contains(query);

        final bool matchesDate = _matchesDateFilter(entry);

        return matchesSearch && matchesDate;
      }).toList();

      isVisibleNoDeliveryNoteEntryFound = filteredDeliveryNoteEntries.isEmpty;
    });
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
    await fetchDeliveryNoteEntries();
  }
}

final pendingDeliveryNoteEntryNotifierProvider = StateNotifierProvider
    .autoDispose<
      PendingDeliveryNoteEntryNotifier,
      PendingDeliveryNoteEntryState
    >((ref) => PendingDeliveryNoteEntryNotifier());
