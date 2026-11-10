import { ComponentFixture, TestBed } from '@angular/core/testing';
import { RecordDisplayAdminComponent } from './record-display-admin.component';
import { MockGenerators } from 'test_data/mock_generators';
import { PcrudService } from '@eg/core/pcrud.service';
import { PermService } from '@eg/core/perm.service';
import { BibRecordService } from '@eg/share/catalog/bib-record.service';
import { OrgService } from '@eg/core/org.service';
import { EMPTY, of } from 'rxjs';
import { BibFieldService } from '@eg/share/catalog/bib-field.service';

const mockPcrud = MockGenerators.pcrudService({search: [MockGenerators.idlObject({
    id: 3,
    col_pos: 1,
    content_type: 'item_counts',
    field: null,
    value_limit: null,
    character_limit: null,
    page_col: 1,
    display_as_link: null,
})]});

const bibRecordService = jasmine.createSpyObj<BibRecordService>(['getBibSummary']);
bibRecordService.getBibSummary.and.returnValue(EMPTY);

describe('RecordDisplayAdminComponent', () => {
    let component: RecordDisplayAdminComponent;
    let fixture: ComponentFixture<RecordDisplayAdminComponent>;

    beforeEach(() => {
        TestBed.configureTestingModule({
            imports: [ RecordDisplayAdminComponent ],
            providers: [
                {provide: OrgService, useValue: null},
                {provide: PcrudService, useValue: mockPcrud},
                {provide: PermService, useValue: MockGenerators.permService({})},
                {provide: BibFieldService, useValue: {displayFields: of([]), recordDisplayEntries: () => of([])}}
            ]
        // Angular seems to ignore the BibRecordService mock unless it is in overrideProvider??
        }).overrideProvider(BibRecordService, {useValue: bibRecordService});

        fixture = TestBed.createComponent(RecordDisplayAdminComponent);
        component = fixture.componentInstance;
        fixture.detectChanges();
    });

    it('should create', () => {
        expect(component).toBeTruthy();
    });

    it('lets you edit 1 columns when in staff view mode', () => {
        component.interfaceToEdit.setValue('search_result');
        fixture.detectChanges();
        expect(fixture.nativeElement.querySelectorAll('eg-record-display-admin-column').length).toEqual(1);
    });

    it('lets you edit 3 columns when in staff view mode', () => {
        component.interfaceToEdit.setValue('staff_view');
        fixture.detectChanges();
        expect(fixture.nativeElement.querySelectorAll('eg-record-display-admin-column').length).toEqual(3);
    });
});
