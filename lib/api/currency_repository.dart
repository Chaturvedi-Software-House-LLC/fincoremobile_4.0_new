import 'pagination_helper.dart';
import 'tally_api_client.dart';

/// `tally-data/companies/:companyId/currencies` - used by the
/// entry-registration screens to resolve the `currencyMasterId` a
/// [VoucherEntryRepository.create] call needs, matched against the
/// company's own currency `symbol`/`isoCurrencyCode`.
class CurrencyRepository {
  CurrencyRepository._();
  static final CurrencyRepository instance = CurrencyRepository._();

  final TallyApiClient _client = TallyApiClient();

  Future<List<Map<String, dynamic>>> listAll() => fetchAllPages(
        (page) => _client.getForCompany('/currencies?page=$page&limit=100'),
      );
}
