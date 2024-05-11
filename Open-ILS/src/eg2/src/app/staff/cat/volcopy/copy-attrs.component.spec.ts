import { IdlService, IdlObject } from './../../../core/idl.service';
import { QueryList } from '@angular/core';
import { waitForAsync } from '@angular/core/testing';
import { AuthService } from '@eg/core/auth.service';
import { FormatService } from '@eg/core/format.service';
import { OrgService } from '@eg/core/org.service';
import { StoreService } from '@eg/core/store.service';
import { ComboboxComponent } from '@eg/share/combobox/combobox.component';
import { ToastService } from '@eg/share/toast/toast.service';
import { FileExportService } from '@eg/share/util/file-export.service';
import { CopyAttrsComponent } from './copy-attrs.component';
import { VolCopyContext } from './volcopy';
import { VolCopyService } from './volcopy.service';

describe('CopyAttrsComponent', () => {
    let component: CopyAttrsComponent;
    const idlMock = jasmine.createSpyObj<IdlService>(['clone']);
    const orgMock = jasmine.createSpyObj<OrgService>(['get']);
    const authServiceMock = jasmine.createSpyObj<AuthService>(['user']);
    const formatServiceMock = jasmine.createSpyObj<FormatService>(['transform']);
    const storeServiceMock = jasmine.createSpyObj<StoreService>(['setLocalItem']);
    const fileExportServiceMock = jasmine.createSpyObj<FileExportService>(['exportFile']);
    const toastServiceMock = jasmine.createSpyObj<ToastService>(['success']);
    const volCopyServiceMock = jasmine.createSpyObj<VolCopyService>(['copyStatIsMagic']);

    beforeEach(() => {
        component = new CopyAttrsComponent(idlMock, orgMock, authServiceMock,
            null, formatServiceMock, storeServiceMock, fileExportServiceMock,
            toastServiceMock, volCopyServiceMock);
        component.copyTemplateCbox = jasmine.createSpyObj<ComboboxComponent>(['entries']);
        component.copyTemplateCbox.selected = {id: 0};
    });
    describe('#applyTemplate', () => {
        describe('status field', () => {
            it('does not apply a magic status to an item', waitForAsync(() => {
                const template = { 'status': 1 };
                volCopyServiceMock.templates = [template];
                volCopyServiceMock.copyStatIsMagic.and.returnValue(true);
                component.batchAttrs = new QueryList();

                spyOn(component, 'applyTemplate').and.callThrough();
                spyOn(component, 'applyCopyValue').and.callThrough();

                component.applyTemplate();
                expect(component.applyCopyValue).not.toHaveBeenCalled();
            }));
        });
    });
    describe('#applyCopyValue', () => {
        it('does not override a magic status', () => {
            volCopyServiceMock.copyStatIsMagic.and.returnValue(true);
            // eslint-disable-next-line no-unused-expressions
            const item = jasmine.createSpyObj<IdlObject>(['ischanged'], {'status': () => {1;}});
            const contextMock = jasmine.createSpyObj<VolCopyContext>(['copyList']);
            contextMock.copyList.and.returnValue([item]);
            component.context = contextMock;
            spyOn(component, 'emitSaveChange');

            component.applyCopyValue('status', 0);
            expect(item.ischanged).not.toHaveBeenCalled();
        });
    });
});
