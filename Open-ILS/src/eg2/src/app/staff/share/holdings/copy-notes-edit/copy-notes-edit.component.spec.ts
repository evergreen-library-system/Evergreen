import { CUSTOM_ELEMENTS_SCHEMA } from '@angular/core';
import { ComponentFixture, TestBed } from '@angular/core/testing';

import { CopyNotesEditComponent } from './copy-notes-edit.component';
import { ToastService } from '@eg/share/toast/toast.service';
import { FmRecordEditorComponent } from '@eg/share/fm-editor/fm-editor.component';

describe('CopyNotesEditComponent', () => {
    let component: CopyNotesEditComponent;
    let fixture: ComponentFixture<CopyNotesEditComponent>;

    beforeEach(async () => {
        await TestBed.configureTestingModule({
            imports: [ CopyNotesEditComponent ],
            providers: [{ToastService, useValue: {}}]
        })
            .overrideComponent(CopyNotesEditComponent, {
                add: {schemas: [CUSTOM_ELEMENTS_SCHEMA]},
                remove: {imports: [FmRecordEditorComponent]}
            })
            .compileComponents();
    });

    beforeEach(() => {
        fixture = TestBed.createComponent(CopyNotesEditComponent);
        component = fixture.componentInstance;
        fixture.detectChanges();
    });

    it('should create', () => {
        expect(component).toBeTruthy();
    });
    describe('back button', () => {
        it('emits an event on click', () => {
            spyOn(component.doneWithEdits, 'emit');
            const generatedElement: HTMLElement = fixture.nativeElement;
            const buttonElement: HTMLButtonElement = generatedElement.querySelector('button');
            buttonElement.dispatchEvent(new Event('click'));
            fixture.detectChanges();
            expect(component.doneWithEdits.emit).toHaveBeenCalled();
        });
    });
});
