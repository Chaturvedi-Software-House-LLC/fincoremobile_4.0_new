import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/auth_repository.dart';
import '../api/batch_repository.dart';
import '../api/currency_repository.dart';
import '../api/dashboard_repository.dart';
import '../api/godown_repository.dart';
import '../api/group_repository.dart';
import '../api/identity_repository.dart';
import '../api/ledger_repository.dart';
import '../api/master_restrictions_repository.dart';
import '../api/price_level_repository.dart';
import '../api/stock_category_repository.dart';
import '../api/stock_repository.dart';
import '../api/token_store.dart';
import '../api/unit_repository.dart';
import '../api/voucher_entry_dropdowns_repository.dart';
import '../api/voucher_entry_repository.dart';
import '../api/voucher_repository.dart';
import '../api/voucher_type_repository.dart';

/// Thin `Provider` wrappers around the existing `*Repository.instance`
/// singletons in `lib/api/`, so screen notifiers depend on `ref.read(...)`
/// rather than reaching for the singletons directly. The repositories
/// themselves are untouched.
final authRepositoryProvider = Provider<AuthRepository>(
  (ref) => AuthRepository.instance,
);

final batchRepositoryProvider = Provider<BatchRepository>(
  (ref) => BatchRepository.instance,
);

final currencyRepositoryProvider = Provider<CurrencyRepository>(
  (ref) => CurrencyRepository.instance,
);

final dashboardRepositoryProvider = Provider<DashboardRepository>(
  (ref) => DashboardRepository.instance,
);

final godownRepositoryProvider = Provider<GodownRepository>(
  (ref) => GodownRepository.instance,
);

final groupRepositoryProvider = Provider<GroupRepository>(
  (ref) => GroupRepository.instance,
);

final identityRepositoryProvider = Provider<IdentityRepository>(
  (ref) => IdentityRepository.instance,
);

final ledgerRepositoryProvider = Provider<LedgerRepository>(
  (ref) => LedgerRepository.instance,
);

final masterRestrictionsRepositoryProvider =
    Provider<MasterRestrictionsRepository>(
      (ref) => MasterRestrictionsRepository.instance,
    );

final priceLevelRepositoryProvider = Provider<PriceLevelRepository>(
  (ref) => PriceLevelRepository.instance,
);

final stockCategoryRepositoryProvider = Provider<StockCategoryRepository>(
  (ref) => StockCategoryRepository.instance,
);

final stockRepositoryProvider = Provider<StockRepository>(
  (ref) => StockRepository.instance,
);

final tokenStoreProvider = Provider<TokenStore>(
  (ref) => TokenStore.instance,
);

final unitRepositoryProvider = Provider<UnitRepository>(
  (ref) => UnitRepository.instance,
);

final voucherEntryDropdownsRepositoryProvider =
    Provider<VoucherEntryDropdownsRepository>(
      (ref) => VoucherEntryDropdownsRepository.instance,
    );

final voucherEntryRepositoryProvider = Provider<VoucherEntryRepository>(
  (ref) => VoucherEntryRepository.instance,
);

final voucherRepositoryProvider = Provider<VoucherRepository>(
  (ref) => VoucherRepository.instance,
);

final voucherTypeRepositoryProvider = Provider<VoucherTypeRepository>(
  (ref) => VoucherTypeRepository.instance,
);
