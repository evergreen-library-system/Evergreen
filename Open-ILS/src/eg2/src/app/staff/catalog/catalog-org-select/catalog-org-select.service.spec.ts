import { TestBed, waitForAsync } from '@angular/core/testing';
import { CatalogOrgSelectService } from './catalog-org-select.service';
import { NetService } from '@eg/core/net.service';
import { MockGenerators } from 'test_data/mock_generators';
import { concat, count, of } from 'rxjs';

describe('CatalogOrgSelectService', () => {
    describe('location_groups_with_orgs', () => {
        it('returns true if the net request returns true', waitForAsync(() => {
            const mockNetService = MockGenerators.netService({'open-ils.search.staff.location_groups_with_orgs': of(true)});
            TestBed.configureTestingModule({
                providers: [{provide: NetService, useValue: mockNetService}]
            });
            const service = TestBed.inject(CatalogOrgSelectService);

            service.shouldIncludeLocationGroups().subscribe(result => {
                expect(result).toBeTrue();
            });
        }));

        it('returns false if the net request returns false', waitForAsync(() => {
            const mockNetService = MockGenerators.netService({'open-ils.search.staff.location_groups_with_orgs': of(false)});
            TestBed.configureTestingModule({
                providers: [{provide: NetService, useValue: mockNetService}]
            });
            const service = TestBed.inject(CatalogOrgSelectService);

            service.shouldIncludeLocationGroups().subscribe(result => {
                expect(result).toBeFalse();
            });
        }));

        it('does not make multiple NetService calls if it has already fetched the value', waitForAsync(() => {
            const mockNetService = MockGenerators.netService({'open-ils.search.staff.location_groups_with_orgs': of(true)});
            TestBed.configureTestingModule({
                providers: [{provide: NetService, useValue: mockNetService}]
            });
            const service = TestBed.inject(CatalogOrgSelectService);

            expect(mockNetService.request).toHaveBeenCalledTimes(0);

            service.shouldIncludeLocationGroups().subscribe(result => {
                expect(result).toBeTrue();
            });
            expect(mockNetService.request).toHaveBeenCalledTimes(1);

            // Call the method a second time
            service.shouldIncludeLocationGroups().subscribe(result => {
                expect(result).toBeTrue();
            });
            // There has still been only one network call
            expect(mockNetService.request).toHaveBeenCalledTimes(1);
        }));
    });
});
