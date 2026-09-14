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
/// `secbtnaccess` (the admin/"security button" visibility flag gating the
/// Roles/Users management menu items - see app_bottom_nav.dart) isn't set
/// here at all - it has no equivalent in this permission catalog, and is
/// deliberately based on a straight "is this company-user's role the
/// system Admin role" check instead (`CompanyUser.role.isSystem`, from
/// `GET /company-user/:id`), not on any granted-permission string - see
/// [CompanySelectNotifier.selectCompany] where it's set. Previously this
/// was hardcoded to `"True"` unconditionally (a real bug - every
/// company-user, including a generic/Spectra non-admin one, saw
/// "Roles"/"Users" in their menu regardless of login), now fixed to
/// reflect the actual admin/non-admin login.
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
  'vanallocation_add': 'VAN_ALLOCATION:CREATE',
  'vanallocation_modify': 'VAN_ALLOCATION:UPDATE',
  'vanallocation_delete': 'VAN_ALLOCATION:DELETE',

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

/// Sets every legacy screen-visibility/enable SharedPreferences key from a
/// decoded company-user JWT `permissions` claim
/// ([AuthRepository.currentCompanyUserPermissions]).
///
/// [permissions] `null` means the claim couldn't be read at all (no active
/// company-user session, an undecodable token, or a token that doesn't
/// carry the claim yet - e.g. an older tally-oauth deployment still
/// mid-rollout) - deliberately handled the same as a real empty list.
/// Product decision made here: an unreadable/absent claim defaults every
/// flag here to `"False"`, not `"True"` - fail closed rather than
/// silently granting the old "everything True" full-access default, since
/// a missing/broken claim is not itself evidence the account should see
/// everything. If this default needs revisiting (e.g. because it turns
/// out real accounts hit the null case often during rollout), that's a
/// product call for whoever reviews this.
///
/// Does not touch `secbtnaccess` - see the doc comment above
/// [legacyFlagToPermission] for why that one is set separately, from an
/// admin/non-admin role check rather than a permission string.
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
}
