import { MockGenerators } from 'test_data/mock_generators';
import { CatalogService } from './catalog.service';
import { of } from 'rxjs';
import { CatalogSearchContext } from './search-context';
import { BibRecordService } from './bib-record.service';
import { TestBed } from '@angular/core/testing';
import { NetService } from '@eg/core/net.service';
import { PermService } from '@eg/core/perm.service';
import { OrgService } from '@eg/core/org.service';
import { PcrudService } from '@eg/core/pcrud.service';
import { BasketService } from './basket.service';
import { ServerStoreService } from '@eg/core/server-store.service';

describe('CatalogService', () => {
    describe('fetchBibSummaries', () => {
        const mockBibNetService = MockGenerators.netService({
            'open-ils.search.biblio.record.catalog_summary': of({
                record: MockGenerators.idlObject({id: 248, deleted: false}),
                urls: []
            }),
            'open-ils.search.staff.location_groups_with_lassos': of(true)
        });
        beforeEach(() => {
            TestBed.configureTestingModule({providers: [
                {provide: NetService, useValue: mockBibNetService},
                {provide: OrgService, useValue: null},
                {provide: PermService, useValue: MockGenerators.permService({PLACE_UNFILLABLE_HOLD: true})},
                {provide: PcrudService, useValue: null},
                {provide: BasketService, useValue: null},
                {provide: ServerStoreService, useValue: MockGenerators.serverStoreService(true)},
                BibRecordService,
                CatalogService
            ]});
        });
        it('passes library group information to the record service', async () => {
            const service = TestBed.inject(CatalogService);
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
