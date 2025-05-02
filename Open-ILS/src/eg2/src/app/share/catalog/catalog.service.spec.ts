import { MockGenerators } from 'test_data/mock_generators';
import { CatalogService } from './catalog.service';
import { of } from 'rxjs';
import { CatalogSearchContext } from './search-context';
import { BibRecordService } from './bib-record.service';

describe('CatalogService', () => {
    describe('fetchBibSummaries', () => {
        it('passes library group information to the record service', async () => {
            const mockBibNetService = MockGenerators.netService({
                'open-ils.search.biblio.record.catalog_summary': of({
                    record: MockGenerators.idlObject({id: 248, deleted: false}),
                    urls: []
                })
            });
            const service = new CatalogService(
                MockGenerators.netService({
                    'open-ils.search.staff.location_groups_with_lassos': of(true)
                }),
                null,
                null,
                new BibRecordService(
                    mockBibNetService,
                    null,
                    MockGenerators.permService({PLACE_UNFILLABLE_HOLD: true})
                ),
                null,
                MockGenerators.serverStoreService(true)
            );
            const context = new CatalogSearchContext();
            context.searchOrg = MockGenerators.idlObject({
                id: 300,
                ou_type: MockGenerators.idlObject({
                    depth: 2
                })
            });
            context.termSearch.locationGroupOrLasso = 'lasso(18)';
            context.resultIds = [248];
            context.pager.resultCount = 1;
            context.pager.limit = 10;
            context.prefOu = 300;

            await service.fetchBibSummaries(context);

            expect(mockBibNetService.request).toHaveBeenCalledWith(
                'open-ils.search',
                'open-ils.search.biblio.record.catalog_summary',
                300, // org id
                [248], // bib record ids
                {library_group: 18, pref_ou: 300}
            );
        });
    });
});
