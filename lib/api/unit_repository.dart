import 'pagination_helper.dart';
import 'tally_api_client.dart';

/// `tally-data/companies/:companyId/units` - Tally's unit-of-measure list
/// (`symbol`, `baseUnitMasterId`/`additionalUnitMasterId` for compound
/// units, `conversion`). Used by the entry-registration screens to build
/// each stock item's unit-selection dropdown and resolve `unitMasterId` for
/// [VoucherEntryRepository.create] inventory entries.
class UnitRepository {
  UnitRepository._();
  static final UnitRepository instance = UnitRepository._();

  final TallyApiClient _client = TallyApiClient();

  Future<List<Map<String, dynamic>>> listAll() => fetchAllPages(
        (page) => _client.getForCompany('/units?page=$page&limit=100'),
      );
}
