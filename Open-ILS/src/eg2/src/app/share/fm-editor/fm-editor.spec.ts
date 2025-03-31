import { IdlService } from '@eg/core/idl.service';
import { NgbModal } from '@ng-bootstrap/ng-bootstrap';
import { ToastService } from '@eg/share/toast/toast.service';
import { FmRecordEditorComponent } from './fm-editor.component';
import { FormatService } from '@eg/core/format.service';
import { OrgService } from '@eg/core/org.service';
import { PcrudService } from '@eg/core/pcrud.service';
import { TestBed, waitForAsync } from '@angular/core/testing';
import { of } from 'rxjs';
import { NO_ERRORS_SCHEMA } from '@angular/core';

describe('FmRecordEditorComponent', () => {
    let component: FmRecordEditorComponent;
    const mockPcrud = jasmine.createSpyObj<PcrudService>(['retrieve']);
    beforeEach(() => {
        const mockModal = jasmine.createSpyObj<NgbModal>(['open']);
        const mockIdl = jasmine.createSpyObj<IdlService>(['pkeyMatches', 'getClassSelector', 'sortIdlFields'], {classes: {
            'mock': {
                label: 'Mock Class',
                fields: [
                    {datatype: 'link', name: 'linked_field', class: 'linked'}
                ]
            },
            'linked': {pkey: 'id'}
        }});
        mockIdl.pkeyMatches.and.returnValue(true);
        mockIdl.getClassSelector.and.returnValue('label');
        const mockToast = jasmine.createSpyObj<ToastService>(['success']);
        const mockFormat = jasmine.createSpyObj<FormatService>([], {wsOrgTimezone: 'America/Los_Angeles'});
        const mockOrg = jasmine.createSpyObj<OrgService>(['get']);
        mockPcrud.retrieve.and.callFake((fmClass, pkey) => {
            if (fmClass === 'mock') {
                return of({
                    a: [],
                    classname: 'mock',
                    _isfieldmapper: true,
                    'linked_field': () => 456
                });
            } else {
                return of({
                    id: () => 456,
                    label: () => 'My Config Value'
                });
            }
        });

        TestBed.configureTestingModule({
            providers: [
                {provide: NgbModal, useValue: mockModal},
                {provide: IdlService, useValue: mockIdl},
                {provide: ToastService, useValue: mockToast},
                {provide: FormatService, useValue: mockFormat},
                {provide: OrgService, useValue: mockOrg},
                {provide: PcrudService, useValue: mockPcrud}
            ],
            schemas: [NO_ERRORS_SCHEMA],
        }).compileComponents();
        component = TestBed.createComponent(FmRecordEditorComponent).componentInstance;

    });
    describe('hidden fields', () => {
        it('fetches only one row of linked values', waitForAsync(() => {
            component.idlClass = 'mock';
            component.readonlyFields = 'linked_field';
            component.mode = 'update';
            component.displayMode = 'inline';
            component.recordId = 123;
            component.ngOnInit();
            // wait for ngOnInit to do its work
            setTimeout(() => {
                expect(mockPcrud.retrieve).toHaveBeenCalledWith('mock', 123);
                expect(mockPcrud.retrieve).toHaveBeenCalledWith('linked', 456);
            }, 100);
        }));
    });
});
