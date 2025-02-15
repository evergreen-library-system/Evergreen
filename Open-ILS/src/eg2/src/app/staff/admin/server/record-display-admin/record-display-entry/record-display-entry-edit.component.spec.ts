import { ComponentFixture, TestBed } from '@angular/core/testing';
import { RecordDisplayEntryEditComponent } from './record-display-entry-edit.component';
import { OrgService } from '@eg/core/org.service';
import { MockGenerators } from 'test_data/mock_generators';
import { IdlService } from '@eg/core/idl.service';
import { StoreService } from '@eg/core/store.service';
import { PcrudService } from '@eg/core/pcrud.service';
import { AfterViewInit, ChangeDetectorRef, Component, inject, input, viewChild } from '@angular/core';
import { CommonModule } from '@angular/common';

let mockPcrud;
const mockIdl = jasmine.createSpyObj<IdlService>(['create', 'getClassSelector'], {classes: {cmf: {pkey: 'id'}, cmc: {pkey: 'name'}}});
mockIdl.create.and.returnValue(MockGenerators.idlObject({id: 123}));

@Component({
    imports: [RecordDisplayEntryEditComponent, CommonModule],
    template: `
        <ng-container *ngTemplateOutlet="editor.dialogContent">
        </ng-container>
      <eg-record-display-entry-edit #editor [mode]="mode()" [data]="data()">
      </eg-record-display-entry-edit>
    `
})
class MockModalComponent implements AfterViewInit {
    editor = viewChild<RecordDisplayEntryEditComponent>('editor');
    private cdr = inject(ChangeDetectorRef);

    data = input();
    mode = input();

    ngAfterViewInit() {
        this.cdr.detectChanges();
    }
}

describe('RecordDisplayEntryEditComponent', () => {
    let component: RecordDisplayEntryEditComponent;
    let fixture: ComponentFixture<MockModalComponent>;

    beforeEach(async () => {
        mockPcrud = MockGenerators.pcrudService({create: []});
        await TestBed.configureTestingModule({
            imports: [ MockModalComponent, RecordDisplayEntryEditComponent ],
            providers: [
                {provide: OrgService, useValue: {}},
                {provide: StoreService, useValue: {}},
                {provide: IdlService, useValue: mockIdl},
                {provide: PcrudService, useValue: mockPcrud}
            ]
        }).compileComponents();

        fixture = TestBed.createComponent(MockModalComponent);
        fixture.detectChanges();
        component = fixture.componentInstance.editor();
    });

    it('has a dropdown that includes the different types of entry content when in create mode', () => {
        fixture.componentRef.setInput('mode', 'create');
        fixture.detectChanges();

        const dropdown = fixture.nativeElement.querySelector('select');
        expect(dropdown).toBeTruthy();

        const dropdownOptions = [...dropdown.querySelectorAll('option')].map(element => element.textContent);
        expect(dropdownOptions).toContain('Field');
        expect(dropdownOptions).toContain('Formats and editions');
        expect(dropdownOptions).toContain('Hold counts');
        expect(dropdownOptions).toContain('Item counts');
    });

    it('does not allow changing the entry type when in edit mode', () => {
    // Different entry types have very different options, it's less confusing
    // for the user to delete the existing entry and create a new one
        fixture.componentRef.setInput('mode', 'edit');
        fixture.detectChanges();

        const dropdown = fixture.nativeElement.querySelector('select');
        expect(dropdown).toBeFalsy();
    });

    it('shows character limit option if content type is field', () => {
        fixture.componentRef.setInput('mode', 'create');
        fixture.detectChanges();

        const contentTypeSelect = fixture.nativeElement.querySelector('select');
        contentTypeSelect.value = 'field';
        contentTypeSelect.dispatchEvent(new Event('change'));
        fixture.detectChanges();
        expect(fixture.nativeElement.querySelector('#character_limit')).toBeTruthy();
    });

    it('does not show character limit option if content type is hold counts', () => {
        fixture.componentRef.setInput('mode', 'create');
        fixture.detectChanges();

        const contentTypeSelect = fixture.nativeElement.querySelector('select');
        contentTypeSelect.value = 'hold_counts';
        contentTypeSelect.dispatchEvent(new Event('change'));
        fixture.detectChanges();
        expect(fixture.nativeElement.querySelector('#character_limit')).toBeFalsy();
    });

    it('shows value limit option if content type is field', () => {
        fixture.componentRef.setInput('mode', 'create');
        fixture.detectChanges();

        const contentTypeSelect = fixture.nativeElement.querySelector('select');
        contentTypeSelect.value = 'field';
        contentTypeSelect.dispatchEvent(new Event('change'));
        fixture.detectChanges();
        expect(fixture.nativeElement.querySelector('#value_limit')).toBeTruthy();
    });

    it('shows display_as_link option if content type is field', () => {
        fixture.componentRef.setInput('mode', 'create');
        fixture.detectChanges();

        const contentTypeSelect = fixture.nativeElement.querySelector('select');
        contentTypeSelect.value = 'field';
        contentTypeSelect.dispatchEvent(new Event('change'));
        fixture.detectChanges();
        expect(fixture.nativeElement.querySelector('#display_as_link')).toBeTruthy();
    });

    it('does not show value limit option if content type is hold counts', () => {
        fixture.componentRef.setInput('mode', 'create');
        fixture.detectChanges();

        const contentTypeSelect = fixture.nativeElement.querySelector('select');
        contentTypeSelect.value = 'hold_counts';
        contentTypeSelect.dispatchEvent(new Event('change'));
        fixture.detectChanges();
        expect(fixture.nativeElement.querySelector('#value_limit')).toBeFalsy();
    });

    it('has a cancel button and a save button when creating a new entry', () => {
        fixture.componentRef.setInput('mode', 'create');
        fixture.detectChanges();

        const buttons = fixture.nativeElement.querySelectorAll('form button');
        expect(buttons.length).toEqual(2);
        expect(buttons[0].innerText).toContain('Cancel');
        expect(buttons[1].innerText).toContain('Save');
    });

    it('has a cancel button, a delete button, and a save button when editing an existing entry', () => {
        fixture.componentRef.setInput('mode', 'edit');
        fixture.detectChanges();

        const buttons = fixture.nativeElement.querySelectorAll('form button');
        expect(buttons.length).toEqual(3);
        expect(buttons[0].innerText).toContain('Delete');
        expect(buttons[1].innerText).toContain('Cancel');
        expect(buttons[2].innerText).toContain('Save');
    });

    describe('applyDefaults', () => {
        it('defaults to values from the provided data', () => {
            fixture.componentRef.setInput('mode', 'edit');
            fixture.componentRef.setInput('data', MockGenerators.idlObject({
                content_type: 'field',
                field: null,
                value_limit: null,
                character_limit: 80,
                display_as_link: false
            }));
            component.applyDefaults();
            fixture.detectChanges();

            const values =
                (Array.from(fixture.nativeElement.querySelectorAll('select,input')) as HTMLSelectElement[]|HTMLInputElement[])
                    .map(el => el.value);

            expect(values).toContain('80');
        });
    });
});
