import { ActivatedRoute, convertToParamMap } from '@angular/router';
import { AdminPageComponent } from './admin-page.component';
import { Location } from '@angular/common';
import { FormatService } from '@eg/core/format.service';
import { IdlService } from '@eg/core/idl.service';
import { OrgService } from '@eg/core/org.service';
import { AuthService } from '@eg/core/auth.service';
import { PcrudService } from '@eg/core/pcrud.service';
import { PermService } from '@eg/core/perm.service';
import { ToastService } from '@eg/share/toast/toast.service';
import { ComponentFixture, TestBed } from '@angular/core/testing';
import { CUSTOM_ELEMENTS_SCHEMA } from '@angular/core';
import { GridModule } from '@eg/share/grid/grid.module';
import { PrintService } from '@eg/share/print/print.service';
import { GridDataSource } from '@eg/share/grid/grid';

describe('AdminPageComponent', () => {
    let component: AdminPageComponent;
    let fixture: ComponentFixture<AdminPageComponent>;

    const routeMock = { snapshot: {queryParamMap: convertToParamMap({id: 1}) }};
    // eslint-disable-next-line max-len
    const idlMock = jasmine.createSpyObj<IdlService>([], {classes: {acpl: {pkey: 'id', fields: [{name: 'id'}, {name: 'isDeleted', datatype: 'bool'}]}}});
    const authMock = jasmine.createSpyObj<AuthService>(['token']);
    const formatMock = jasmine.createSpyObj<FormatService>(['transform']);
    beforeEach(() => {
        TestBed.configureTestingModule({
            providers: [
                {provide: ActivatedRoute, useValue: routeMock},
                {provide: Location, useValue: {}},
                {provide: FormatService, useValue: formatMock},
                {provide: IdlService, useValue: idlMock},
                {provide: OrgService, useValue: {}},
                {provide: AuthService, useValue: authMock},
                {provide: PcrudService, useValue: {}},
                {provide: PermService, useValue: {}},
                {provide: ToastService, useValue: {}},
                {provide: PrintService, useValue: {}}
            ],
            schemas: [CUSTOM_ELEMENTS_SCHEMA],
            declarations: [
                AdminPageComponent,
            ],
            imports: [
                GridModule
            ]
        });
        fixture = TestBed.createComponent(AdminPageComponent);
        component = fixture.componentInstance;
    });

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
        });
        it('returns false (i.e. you _should_ display delete) if no selected rows are deleted', () => {
            const rows = [
                {isdeleted: () => false, deleted: () => 'f', a: [], classname: '', _isfieldmapper: true }
            ];
            expect(component.shouldDisableDelete(rows)).toBe(false);
        });
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
        });
        it('returns false (i.e. you _should_ display undelete) if all selected rows are deleted', () => {
            const rows = [
                {deleted: () => 't', a: [], classname: '', _isfieldmapper: true }
            ];
            expect(component.shouldDisableUndelete(rows)).toBe(false);
        });
    });
    describe('initialFilterValues input', () => {
        it('sets initialFilterValue on grid-column', () => {
            component.idlClass = 'acpl';
            component.initialFilterValues = {isDeleted: 'f'};
            component.dataSource = new GridDataSource();
            component.dataSource.data = [{id: 1, isDeleted: 'true'}];
            fixture.detectChanges();
            expect(component.grid.context.columnSet.columns[1].name).toEqual('isDeleted');
            expect(component.grid.context.columnSet.columns[1].filterValue).toEqual('f');
        });
    });
});
