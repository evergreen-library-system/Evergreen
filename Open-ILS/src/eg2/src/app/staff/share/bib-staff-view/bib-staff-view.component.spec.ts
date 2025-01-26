import { MockGenerators } from 'test_data/mock_generators';
import { BibStaffViewComponent } from './bib-staff-view.component';
import { BibRecordService } from '@eg/share/catalog/bib-record.service';
import { of } from 'rxjs';
import { CatalogSearchContext } from '@eg/share/catalog/search-context';

describe('BibStaffViewComponent', () => {
    describe('loadSummary()', () => {
        const mockBibNetService = MockGenerators.netService({
            'open-ils.search.biblio.record.catalog_summary.staff': of({
                record: MockGenerators.idlObject({id: 248, deleted: false}),
                urls: [],
                copy_counts: [
                    {
                        'count': 18,
                        'available': 18,
                        'unshadow': 8,
                        'org_unit': 1,
                        'depth': 0,
                        'transcendant': null
                    }
                ]
            })
        });

        it('can fetch a summary', async () => {
            const context = new CatalogSearchContext();
            context.searchOrg = MockGenerators.idlObject({id: 35});
            const component = new BibStaffViewComponent(
                new BibRecordService(
                    mockBibNetService,
                    null,
                    MockGenerators.permService({PLACE_UNFILLABLE_HOLD: true})
                ),
                null,
                null,
                null,
                MockGenerators.staffCatService(context)
            );
            component.recordId = 123;

            await component.loadSummary();

            expect(component.summary.holdingsSummary[0].available).toEqual(18);
        });
        it('can fetch a summary with a lasso', async () => {
            const context = new CatalogSearchContext();
            context.searchOrg = MockGenerators.idlObject({id: 35});
            context.termSearch.locationGroupOrLasso = 'lasso(18)';

            const component = new BibStaffViewComponent(
                new BibRecordService(
                    mockBibNetService,
                    null,
                    MockGenerators.permService({PLACE_UNFILLABLE_HOLD: true})
                ),
                null,
                null,
                null,
                MockGenerators.staffCatService(context)
            );
            component.recordId = 123;

            await component.loadSummary();

            expect(mockBibNetService.request).toHaveBeenCalledWith(
                'open-ils.search',
                'open-ils.search.biblio.record.catalog_summary.staff',
                35,
                [123],
                {library_group: 18}
            );
        });
    });
});
