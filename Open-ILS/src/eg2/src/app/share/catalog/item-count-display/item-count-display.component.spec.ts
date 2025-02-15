import { ComponentFixture, TestBed } from '@angular/core/testing';
import { ItemCountDisplayComponent } from './item-count-display.component';
import { MockGenerators } from 'test_data/mock_generators';
import { BibRecordSummary } from '../bib-record.service';
import { CatalogService } from '../catalog.service';
import { of } from 'rxjs';

const mockCatalogService = jasmine.createSpyObj<CatalogService>(['orgOrLassoName']);
mockCatalogService.orgOrLassoName.and.callFake((itemCount) => {
    if (itemCount.org_unit === 1) {
        return of('Great Consortium');
    }
    return of('Excellent System');
});

describe('ItemCountDisplayComponent', () => {
    let component: ItemCountDisplayComponent;
    let fixture: ComponentFixture<ItemCountDisplayComponent>;

    beforeEach(async () => {
        await TestBed.configureTestingModule({
            imports: [ ItemCountDisplayComponent ],
            providers: [
                {provide: CatalogService, useValue: mockCatalogService}
            ]
        })
            .compileComponents();

        fixture = TestBed.createComponent(ItemCountDisplayComponent);
        component = fixture.componentInstance;
        fixture.detectChanges();
    });

    it('should create', () => {
        expect(component).toBeTruthy();
    });

    it('should display the hold counts from the supplied summary', () => {
        component.summary = new BibRecordSummary(MockGenerators.idlObject({id: 333_333}), 12);
        component.summary.holdingsSummary = [
            {available: 3, count: 5, org_unit: 1, depth: 1, unshadow: 5, transcendant: 0},
            {available: 10, count: 10, org_unit: 5, depth: 2, unshadow: 5, transcendant: 0}
        ];
        fixture.detectChanges();

        expect(fixture.nativeElement.textContent).toContain('3 of 5 copies available at Great Consortium.');
        expect(fixture.nativeElement.textContent).toContain('10 of 10 copies available at Excellent System.');
    });
});
