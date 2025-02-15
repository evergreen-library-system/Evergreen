import { ComponentFixture, TestBed } from '@angular/core/testing';
import { RecordDisplayEntryComponent } from './record-display-entry.component';
import { MockGenerators } from 'test_data/mock_generators';
import { PcrudService } from '@eg/core/pcrud.service';

describe('RecordDisplayEntryComponent', () => {
    let component: RecordDisplayEntryComponent;
    let fixture: ComponentFixture<RecordDisplayEntryComponent>;

    beforeEach(async () => {
        await TestBed.configureTestingModule({
            imports: [ RecordDisplayEntryComponent ],
            providers: [{provide: PcrudService, useValue: MockGenerators.pcrudService({})}]
        })
            .compileComponents();

        fixture = TestBed.createComponent(RecordDisplayEntryComponent);
        component = fixture.componentInstance;
        component.data = MockGenerators.idlObject({
            content_type: 'field',
            page_col: 1,
            col_pos: 3,
            field: MockGenerators.idlObject({
                name: 'subject',
                label: 'Subject'
            }),
            value_limit: 5,
            character_limit: 100,
            display_as_link: false
        });
        fixture.detectChanges();
    });

    it('contains table cells', () => {
        expect(fixture.nativeElement.querySelector('td')).toBeTruthy();
    });

    it('displays the position', () => {
        expect(fixture.nativeElement.textContent).toContain('3');
    });

    it('displays the content type', () => {
        expect(fixture.nativeElement.textContent).toContain('Field');
    });

    it('displays the field name', () => {
        expect(fixture.nativeElement.textContent).toContain('Subject');
    });

    it('has no buttons', () => {
        const buttons = fixture.nativeElement.querySelectorAll('button');
        expect(buttons.length).toEqual(0);
    });

    it('says that there is a limit', () => {
        expect(fixture.nativeElement.textContent).toContain('Yes');
    });

    describe('when permissions are true', () => {
        beforeEach(() => {
            component.hasPermissions = true;
            fixture.detectChanges();
        });
        it('has buttons to delete, edit, and move', () => {
            const buttons = fixture.nativeElement.querySelectorAll('button');
            expect(buttons[0].getAttribute('aria-label')).toEqual('Delete section 1 entry 3');
            expect(buttons[1].getAttribute('aria-label')).toEqual('Edit section 1 entry 3');
            expect(buttons[2].getAttribute('aria-label')).toEqual('Move section 1 entry 3');
        });
    });
});
