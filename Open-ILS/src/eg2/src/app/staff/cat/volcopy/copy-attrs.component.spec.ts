import { QueryList } from "@angular/core";
import { waitForAsync } from "@angular/core/testing";
import { AuthService } from "@eg/core/auth.service";
import { FormatService } from "@eg/core/format.service";
import { IdlService } from "@eg/core/idl.service";
import { OrgService } from "@eg/core/org.service";
import { StoreService } from "@eg/core/store.service";
import { ComboboxComponent } from "@eg/share/combobox/combobox.component";
import { ToastService } from "@eg/share/toast/toast.service";
import { FileExportService } from "@eg/share/util/file-export.service";
import { CopyAttrsComponent } from "./copy-attrs.component";
import { VolCopyService } from "./volcopy.service";

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
            formatServiceMock, storeServiceMock, fileExportServiceMock,
            toastServiceMock, volCopyServiceMock);
        component.copyTemplateCbox = jasmine.createSpyObj<ComboboxComponent>(['entries']);
        component.copyTemplateCbox.selected = {id: 0};
    });
    describe('#applyTemplate', () => {
        describe('status field', () => {
            it('does not apply a magic status to an item', waitForAsync(() => {
                let template = { "status": 1 };
                volCopyServiceMock.templates = [template];
                volCopyServiceMock.copyStatIsMagic.and.returnValue(true);
                component.batchAttrs = new QueryList();

                spyOn(component, 'applyTemplate').and.callThrough();
                spyOn(component, 'applyCopyValue').and.callThrough();

                component.applyTemplate();
                expect(component.applyCopyValue).not.toHaveBeenCalled();
            }));
        });
    })
});
