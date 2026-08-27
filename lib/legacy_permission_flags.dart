import 'package:shared_preferences/shared_preferences.dart';

/// Maps every legacy SharedPreferences screen-visibility/enable flag key -
/// still read directly by Dashboard.dart/Party.dart/Items.dart/the entry
/// registration screens/Settings.dart/app_bottom_nav.dart, exactly as they
/// are today (see SerialSelect.dart's `getroledata()`, ~lines 2120-2260,
/// for the original source of every one of these keys for a legacy-paired
/// login) - to its tally-oauth permission-catalog equivalent, so
/// [CompanySelectTallyOauth] can translate a decoded company-user JWT's
/// `permissions` claim into the flags those screens already read, with no
/// per-screen changes needed.
///
/// IMPORTANT: the values here are `RESOURCE:ACTION` strings (e.g.
/// `'DASHBOARD_SALES:READ'`), matching exactly what the company-user JWT's
/// `permissions` claim actually contains at runtime (confirmed by decoding
/// a real token) - `company-user-auth.service.ts` embeds each granted
/// permission as its `resource`+`:`+`action` columns, NOT the catalog's
/// dotted `name` field (`dashboard.sales:read`). An earlier version of
/// this file used the `name`-shaped strings, which never matched the real
/// claim and would have silently failed every permission check (fail-closed
/// meant everything defaulted to hidden) - caught via live-decoding an
/// actual issued JWT, not by static review, so if this mapping is ever
/// touched again, verify against a real decoded token, not just the
/// permission catalog's `name` column.
///
/// One legacy key, `secbtnaccess` (the admin/"security button" visibility
/// flag - see Settings.dart/Dashboard.dart/CreateUser.dart etc.), is
/// deliberately left out of this map: there is no 1:1 entry for it among
/// the 48 new app-functionality permissions, so [applyPermissionFlags]
/// keeps defaulting it to `"True"` exactly as the old hardcoded block did,
/// rather than gating it against a permission string that doesn't exist.
const Map<String, String> legacyFlagToPermission = {
  // Dashboard
  'salesdash': 'DASHBOARD_SALES:READ',
  'purchasedash': 'DASHBOARD_PURCHASE:READ',
  'receiptsdash': 'DASHBOARD_RECEIPTS:READ',
  'paymentsdash': 'DASHBOARD_PAYMENTS:READ',
  'outstandingreceivabledash': 'DASHBOARD_OUTSTANDING_RECEIVABLE:READ',
  'outstandingpayabledash': 'DASHBOARD_OUTSTANDING_PAYABLE:READ',
  'cashdash': 'DASHBOARD_CASH:READ',
  'barchartdash': 'DASHBOARD_BAR_CHART:READ',
  'linechartdash': 'DASHBOARD_LINE_CHART:READ',
  'piechartdash': 'DASHBOARD_PIE_CHART:READ',

  // Entry registration screens
  'salesentry': 'ENTRY_SALES:CREATE',
  'receiptentry': 'ENTRY_RECEIPT:CREATE',
  'salesorderentry': 'ENTRY_SALES_ORDER:CREATE',
  'deliverynoteentry': 'ENTRY_DELIVERY_NOTE:CREATE',
  'ledgerentries': 'ENTRY_LEDGER:READ',
  'billsentries': 'ENTRY_BILLS:READ',
  'inventoryentries': 'ENTRY_INVENTORY:READ',
  'costcentreentries': 'ENTRY_COST_CENTRE:READ',
  'postdatedtransactions': 'ENTRY_POST_DATED:READ',

  // Items
  'allitems': 'ITEM_ALL:READ',
  'activeitems': 'ITEM_ACTIVE:READ',
  'inactiveitems': 'ITEM_INACTIVE:READ',
  'rate': 'ITEM_RATE:READ',
  'item_amount': 'ITEM_AMOUNT:READ',
  'item_sales': 'ITEM_SALES:READ',
  'item_purchase': 'ITEM_PURCHASE:READ',

  // Party
  'salesparty': 'PARTY_SALES:READ',
  'purchaseparty': 'PARTY_PURCHASE:READ',
  'receiptparty': 'PARTY_RECEIPT:READ',
  'paymentparty': 'PARTY_PAYMENT:READ',
  'creditnoteparty': 'PARTY_CREDIT_NOTE:READ',
  'debitnoteparty': 'PARTY_DEBIT_NOTE:READ',
  'journalparty': 'PARTY_JOURNAL:READ',
  'receivableparty': 'PARTY_RECEIVABLE:READ',
  'payableparty': 'PARTY_PAYABLE:READ',
  'pendingsalesorderparty': 'PARTY_PENDING_SALES_ORDER:READ',
  'pendingpurchaseorderparty': 'PARTY_PENDING_PURCHASE_ORDER:READ',
  'party_suppliers': 'PARTY_SUPPLIERS:READ',
  'party_customers': 'PARTY_CUSTOMERS:READ',

  // Van allocation
  'vanallocation': 'VAN_ALLOCATION:READ',

  // Settings
  'settings_currency': 'SETTINGS_CURRENCY:UPDATE',
  'settings_amtdecimals': 'SETTINGS_AMOUNT_DECIMALS:UPDATE',
  'settings_vatperc': 'SETTINGS_VAT_PERCENTAGE:UPDATE',
  'settings_inactivepdays': 'SETTINGS_INACTIVE_DAYS:UPDATE',
  'settings_sorttype': 'SETTINGS_SORT_TYPE:UPDATE',
  'settings_defdaterange': 'SETTINGS_DEFAULT_DATE_RANGE:UPDATE',
  'settings_ageingconfig': 'SETTINGS_AGEING_CONFIG:UPDATE',
  'settings_fastslowinactiveitem': 'SETTINGS_FAST_SLOW_INACTIVE_ITEM:UPDATE',
};

/// Legacy flags with no equivalent in the new 40-entry permission catalog.
/// Kept defaulted to `"True"` by [applyPermissionFlags] rather than
/// permission-gated - see the doc comment on [legacyFlagToPermission] for
/// why `secbtnaccess` specifically is here.
const List<String> unmappedLegacyFlags = ['secbtnaccess'];

/// Sets every legacy screen-visibility/enable SharedPreferences key from a
/// decoded company-user JWT `permissions` claim
/// ([AuthRepository.currentCompanyUserPermissions]).
///
/// - [permissions] `null` means the claim couldn't be read at all (no
///   active company-user session, an undecodable token, or a token that
///   doesn't carry the claim yet - e.g. an older tally-oauth deployment
///   still mid-rollout) - deliberately handled the same as a real empty
///   list. Product decision made here: an unreadable/absent claim defaults
///   every *mapped* flag to `"False"`, not `"True"` - fail closed rather
///   than silently granting the old "everything True" full-access
///   default, since a missing/broken claim is not itself evidence the
///   account should see everything. If this default needs revisiting
///   (e.g. because it turns out real accounts hit the null case often
///   during rollout), that's a product call for whoever reviews this.
/// - `secbtnaccess` is excluded from that fail-closed behavior - it keeps
///   its own unconditional `"True"` default regardless of [permissions],
///   same as before, since it isn't part of the new permission catalog at
///   all yet.
Future<void> applyPermissionFlags(
  SharedPreferences prefs,
  List<String>? permissions,
) async {
  final granted = permissions?.toSet() ?? const <String>{};
  for (final entry in legacyFlagToPermission.entries) {
    await prefs.setString(
      entry.key,
      granted.contains(entry.value) ? 'True' : 'False',
    );
  }
  for (final key in unmappedLegacyFlags) {
    await prefs.setString(key, 'True');
  }
}
