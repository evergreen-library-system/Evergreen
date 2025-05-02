import { NgbModal } from '@ng-bootstrap/ng-bootstrap';
import { OrgService } from '@eg/core/org.service';
import { OuSettingHistoryDialogComponent } from './org-unit-setting-history-dialog.component';
import { ComponentFixture, TestBed } from '@angular/core/testing';
import { NO_ERRORS_SCHEMA } from '@angular/core';

describe('OuSettingHistoryDialogComponent', () => {
    const mockOrg = {
        a: [],
        classname: 'acp',
        _isfieldmapper: true,
        id: () => 22
    };

    let component: OuSettingHistoryDialogComponent;
    let fixture: ComponentFixture<OuSettingHistoryDialogComponent>;


    const orgServiceSpy = jasmine.createSpyObj<OrgService>(['get']);
    const modalSpy = jasmine.createSpyObj<NgbModal>(['open']);
    orgServiceSpy.get.and.returnValue(mockOrg);

    beforeEach(() => {
        TestBed.configureTestingModule({
            providers: [
                {provide: OrgService, useValue: orgServiceSpy},
                {provide: NgbModal, useValue: modalSpy}
            ],
            schemas: [NO_ERRORS_SCHEMA],
        }).compileComponents();
        fixture = TestBed.createComponent(OuSettingHistoryDialogComponent);
        component = fixture.componentInstance;
    });

    it('can revert a change back to a null value', () => {
        const mockLog = {
            original_value: null,
            org: 22
        };
        const mockSetting = {
            name: 'my.setting'
        };
        spyOn(component, 'close');
        component.entry = mockSetting;
        component.revert(mockLog);
        expect(component.close).toHaveBeenCalledWith({
            setting: {'my.setting': null},
            context: mockOrg,
            revert: true
        });
    });
});
