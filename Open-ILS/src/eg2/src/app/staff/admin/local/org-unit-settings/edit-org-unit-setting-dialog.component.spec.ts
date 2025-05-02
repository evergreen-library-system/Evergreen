import { NgbModal } from '@ng-bootstrap/ng-bootstrap';
import { EditOuSettingDialogComponent } from './edit-org-unit-setting-dialog.component';
import { ComponentFixture, TestBed, waitForAsync } from '@angular/core/testing';
import { AfterViewInit, CUSTOM_ELEMENTS_SCHEMA, ChangeDetectorRef, Component, TemplateRef, ViewChild } from '@angular/core';

const modal = jasmine.createSpyObj<NgbModal>(['open']);
let fixture: ComponentFixture<EditOuSettingDialogComponent>;
let component: EditOuSettingDialogComponent;

@Component({
    template: `
      <div>
        <ng-container *ngTemplateOutlet="modal"> </ng-container>
      </div>
      <eg-admin-edit-org-unit-setting-dialog #dialog></eg-admin-edit-org-unit-setting-dialog>
    `,
})
class MockModalComponent implements AfterViewInit {
    @ViewChild('dialog') componentRef: EditOuSettingDialogComponent;
    modal: TemplateRef<any>;
    constructor(private cdr: ChangeDetectorRef) {}
    ngAfterViewInit() {
        this.modal = this.componentRef.dialogContent;
        this.cdr.detectChanges();
    }
}

describe('EditOuSettingDialogComponent', () => {
    beforeEach(() => {
        TestBed.configureTestingModule({
            providers: [
                { provide: NgbModal, useValue: modal}
            ], declarations: [
                MockModalComponent,
                EditOuSettingDialogComponent
            ], schemas: [
                CUSTOM_ELEMENTS_SCHEMA
            ]
        }).compileComponents();
        fixture = TestBed.createComponent(EditOuSettingDialogComponent);
        component = fixture.componentInstance;
    });
    describe('inputType()', () => {
        describe('when setting name is lib.timezone', () => {
            it('returns timezone', () => {
                const entry = {
                    name: 'lib.timezone',
                    dataType: 'string'
                };
                component.entry = entry;
                expect(component.inputType()).toEqual('timezone');
            });
        });
        describe('when setting dataType is integer', () => {
            it('returns integer', () => {
                const entry = {
                    dataType: 'integer'
                };
                component.entry = entry;
                expect(component.inputType()).toEqual('integer');
            });
        });
    });
    describe('template', () => {
        it(('displays a timezone select if the entry is lib.timezone'), waitForAsync(() => {
            const mockModalFixture = TestBed.createComponent(MockModalComponent);
            const mockModal = mockModalFixture.debugElement.componentInstance;
            mockModalFixture.detectChanges();
            mockModal.ngAfterViewInit();
            component = mockModal.componentRef;
            const entry = {
                name: 'lib.timezone',
                dataType: 'string'
            };
            component.entry = entry;
            const editElement: HTMLElement = mockModalFixture.nativeElement;
            mockModalFixture.detectChanges();
            expect(editElement.querySelectorAll('eg-timezone-select').length).toEqual(1);
        }));
    });
});
