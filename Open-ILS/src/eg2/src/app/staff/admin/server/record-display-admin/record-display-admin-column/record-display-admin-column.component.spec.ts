import { ComponentFixture, TestBed } from '@angular/core/testing';
import { RecordDisplayAdminColumnComponent } from './record-display-admin-column.component';
import { MockGenerators } from 'test_data/mock_generators';
import { PcrudService } from '@eg/core/pcrud.service';

const mockPcrud = MockGenerators.pcrudService({search: [MockGenerators.idlObject({
    id: 3,
    col_pos: 1,
    content_type: 'item_counts',
    field: null,
    value_limit: null,
    character_limit: null,
    page_col: 1,
    display_as_link: 't'
})]});

describe('RecordDisplayAdminColumnComponent', () => {
    let component: RecordDisplayAdminColumnComponent;
    let fixture: ComponentFixture<RecordDisplayAdminColumnComponent>;

    beforeEach(async () => {
        await TestBed.configureTestingModule({
            imports: [ RecordDisplayAdminColumnComponent ],
            providers: [
                {provide: PcrudService, useValue: mockPcrud}
            ]
        })
            .compileComponents();

        fixture = TestBed.createComponent(RecordDisplayAdminColumnComponent);
        component = fixture.componentInstance;
        fixture.detectChanges();
    });

    it('should create', () => {
        expect(component).toBeTruthy();
    });

    describe('handleDrop()', () => {
        it('reorders everything', () => {
            component.data = [
                MockGenerators.idlObject({
                    id: 3,
                    col_pos: 1,
                    page_col: 1,
                    content_type: 'item_counts',
                    field: null,
                    value_limit: null,
                    character_limit: null,
                    display_as_link: null,
                }),
                MockGenerators.idlObject({
                    id: 4,
                    col_pos: 2,
                    page_col: 1,
                    content_type: 'field',
                    field: 3,
                    value_limit: null,
                    character_limit: 50,
                })
            ];
            component.registerDraggedEntry(component.data[1]);
            component.registerDropTarget(component.data[0]);

            component.handleDrop();

            expect(component.data[0].content_type()).toEqual('field'); // item_counts used to be first
            expect(component.data[1].content_type()).toEqual('item_counts'); // field used to be second
            expect(component.data[0].col_pos()).toEqual(1);
            expect(component.data[1].col_pos()).toEqual(2);

            // We are no longer in the middle of a drop action
            expect(component.dropTarget).toBeNull();
        });
    });
});
