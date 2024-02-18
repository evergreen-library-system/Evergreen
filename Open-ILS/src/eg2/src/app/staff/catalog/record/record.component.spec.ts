import { ComponentFixture, TestBed, waitForAsync } from '@angular/core/testing';
import { RecordComponent } from './record.component';
import { ActivatedRoute, Router, convertToParamMap } from '@angular/router';
import { AuthService } from '@eg/core/auth.service';
import { BibRecordService, BibRecordSummary } from '@eg/share/catalog/bib-record.service';
import { of } from 'rxjs';
import { StaffCatalogService } from '../catalog.service';
import { HoldingsService } from '@eg/staff/share/holdings/holdings.service';
import { StoreService } from '@eg/core/store.service';
import { ServerStoreService } from '@eg/core/server-store.service';
import { IdlObject } from '@eg/core/idl.service';
import { CUSTOM_ELEMENTS_SCHEMA } from '@angular/core';
import { NgbNavModule } from '@ng-bootstrap/ng-bootstrap';
import { TitleComponent } from '@eg/share/title/title.component';

describe('RecordComponent', () => {
    let fixture: ComponentFixture<RecordComponent>;
    const mockBibIdlObject = jasmine.createSpyObj<IdlObject>(['id', 'tcn_value']);
    mockBibIdlObject.id.and.returnValue(12);
    mockBibIdlObject.tcn_value.and.returnValue('ocn12345');
    const summary = new BibRecordSummary(mockBibIdlObject, 123);
    summary.recordNoteCount = 8;
    summary.displayHighlights = {fake: 'data'};
    summary.display = {title: 'My book'};
    const mockBibService = jasmine.createSpyObj<BibRecordService>(['getBibSummary']);
    mockBibService.getBibSummary.and.returnValue(of(summary));
    const mockStaffCatService = {searchContext: {
        searchOrg: { id: () => 4 },
        isStaff: true
    }};
    const mockStoreService = jasmine.createSpyObj<StoreService>(['getLocalItem', 'setLocalItem']);

    beforeEach(waitForAsync(() => {
        TestBed.configureTestingModule({
            declarations: [RecordComponent, TitleComponent],
            schemas: [CUSTOM_ELEMENTS_SCHEMA],
            imports: [ NgbNavModule ],
            providers: [
                { provide: Router, useValue: null},
                { provide: ActivatedRoute, useValue: { paramMap: of(convertToParamMap({id: 1})) }},
                { provide: AuthService, useValue: null },
                { provide: BibRecordService, useValue: mockBibService},
                { provide: StaffCatalogService, useValue: mockStaffCatService },
                { provide: HoldingsService, useValue: null },
                { provide: StoreService, useValue: mockStoreService },
                { provide: ServerStoreService, useValue: {getItemBatch: () => Promise.resolve([])} }
            ]}).compileComponents();
        fixture = TestBed.createComponent(RecordComponent);
        fixture.detectChanges();
    }));

    it('displays the number of record notes in the tab', () => {
        fixture.detectChanges();
        expect(fixture.nativeElement.innerText).toContain('Record Notes (8)');
    });

});
