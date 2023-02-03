import { ActivatedRoute } from "@angular/router";
import { AdminPageComponent } from "./admin-page.component";
import { Location } from '@angular/common';
import { FormatService } from "@eg/core/format.service";
import { IdlService } from "@eg/core/idl.service";
import { OrgService } from "@eg/core/org.service";
import { AuthService } from "@eg/core/auth.service";
import { PcrudService } from "@eg/core/pcrud.service";
import { PermService } from "@eg/core/perm.service";
import { ToastService } from "@eg/share/toast/toast.service";

describe('CopyAttrsComponent', () => {
    let component: AdminPageComponent;

    const routeMock = jasmine.createSpyObj<ActivatedRoute>(['snapshot']);
    const locationMock = jasmine.createSpyObj<Location>(['prepareExternalUrl']);
    const formatMock = jasmine.createSpyObj<FormatService>(['transform']);
    const idlMock = jasmine.createSpyObj<IdlService>(['classes']);
    const orgMock = jasmine.createSpyObj<OrgService>(['get']);
    const authMock = jasmine.createSpyObj<AuthService>(['user']);
    const pcrudMock = jasmine.createSpyObj<PcrudService>(['retrieveAll']);
    const permMock = jasmine.createSpyObj<PermService>(['hasWorkPermAt']);
    const toastMock = jasmine.createSpyObj<ToastService>(['success']);
    beforeEach(() => {
        component = new AdminPageComponent(routeMock, locationMock, formatMock,
            idlMock, orgMock, authMock, pcrudMock, permMock, toastMock);
    })

    describe('#shouldDisableDelete', () => {
        it('returns true if one of the rows is already deleted', () => {
            const rows = [
                {isdeleted: () => true, a: [], classname: '', _isfieldmapper: true },
                {isdeleted: () => false, a: [], classname: '', _isfieldmapper: true }
            ];
            expect(component.shouldDisableDelete(rows)).toBe(true);
        });
        it('returns true if no rows selected', () => {
            expect(component.shouldDisableDelete([])).toBe(true);
        })
        it('returns false (i.e. you _should_ display delete) if no selected rows are deleted', () => {
            const rows = [
                {isdeleted: () => false, deleted: () => 'f', a: [], classname: '', _isfieldmapper: true }
            ];
            expect(component.shouldDisableDelete(rows)).toBe(false);
        })
    });
    describe('#shouldDisableUndelete', () => {
        it('returns true if none of the rows are deleted', () => {
            const rows = [
                {isdeleted: () => false, a: [], classname: '', _isfieldmapper: true },
                {deleted: () => 'f', a: [], classname: '', _isfieldmapper: true }
            ];
            expect(component.shouldDisableUndelete(rows)).toBe(true);
        });
        it('returns true if no rows selected', () => {
            expect(component.shouldDisableUndelete([])).toBe(true);
        })
        it('returns false (i.e. you _should_ display undelete) if all selected rows are deleted', () => {
            const rows = [
                {deleted: () => 't', a: [], classname: '', _isfieldmapper: true }
            ];
            expect(component.shouldDisableUndelete(rows)).toBe(false);
        })
    });
});
