import { NgbModal } from '@ng-bootstrap/ng-bootstrap';
import { OrgService } from '@eg/core/org.service';
import { OuSettingHistoryDialogComponent } from './org-unit-setting-history-dialog.component';

describe('OuSettingHistoryDialogComponent', () => {
    const mockOrg = {
        a: [],
        classname: 'acp',
        _isfieldmapper: true,
        id: () => 22
    };

    const orgServiceSpy = jasmine.createSpyObj<OrgService>(['get']);
    const modalSpy = jasmine.createSpyObj<NgbModal>(['open']);
    orgServiceSpy.get.and.returnValue(mockOrg);
    const component = new OuSettingHistoryDialogComponent(orgServiceSpy, modalSpy);

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
