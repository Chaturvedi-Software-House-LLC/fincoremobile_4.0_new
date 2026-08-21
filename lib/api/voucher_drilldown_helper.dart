import 'voucher_repository.dart';

/// Shared filtering for the Party/Items drill-down screens
/// (`PartyDrillDown`, `ItemsDrillDown`, `PartyTotalClickedRest`,
/// `PartyClickedSoldPurchaseClicked`) - each of these used to call legacy's
/// `getTotalAmount`/similar collection endpoints, which took a combination
/// of party ledger name / item name / voucher type name / cost-centre name
/// filters server-side. tally-api has no equivalent filtered endpoint, so
/// this fetches the full voucher list for the date range
/// ([VoucherRepository.listInRange]) and applies the same filters
/// client-side; callers then aggregate/group the result themselves
/// (grouping shape differs per screen).
///
/// Matches by name (not masterId) throughout, same as the legacy endpoints
/// did - fine for the common case, but two ledgers/items with the exact
/// same display name would be conflated. A known, pre-existing-style
/// simplification (matches `DashboardClicked.dart`'s "first ledger entry"
/// simplification elsewhere in this migration).
Future<List<Map<String, dynamic>>> fetchDrilldownVouchers({
  required DateTime from,
  required DateTime to,
  String? partyLedgerName,
  String? itemName,
  String? voucherTypeName,
  String? costCentreName,
}) async {
  final vouchers = await VoucherRepository.instance.listInRange(
    from: from,
    to: to,
  );

  return vouchers.where((voucher) {
    if (voucherTypeName != null &&
        voucher['voucherTypeName'] != voucherTypeName) {
      return false;
    }

    final ledgerEntries =
        (voucher['ledgerEntries'] as List?)?.cast<Map<String, dynamic>>() ??
        const [];
    if (partyLedgerName != null &&
        !ledgerEntries.any((e) => e['ledgerName'] == partyLedgerName)) {
      return false;
    }

    if (itemName != null) {
      final inventoryEntries =
          (voucher['inventoryEntries'] as List?)
              ?.cast<Map<String, dynamic>>() ??
          const [];
      if (!inventoryEntries.any((e) => e['stockItemName'] == itemName)) {
        return false;
      }
    }

    if (costCentreName != null) {
      final costCentreEntries =
          (voucher['costCentreAllocations'] as List?)
              ?.cast<Map<String, dynamic>>() ??
          const [];
      if (costCentreName == 'null') {
        // Legacy's "*Not Applicable" bucket - vouchers with no cost-centre
        // allocation at all.
        if (costCentreEntries.isNotEmpty) return false;
      } else if (!costCentreEntries.any(
        (e) => e['costCentreName'] == costCentreName,
      )) {
        return false;
      }
    }

    return true;
  }).toList();
}
