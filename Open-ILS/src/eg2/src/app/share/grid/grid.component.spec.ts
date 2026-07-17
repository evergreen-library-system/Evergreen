import { IdlService } from '@eg/core/idl.service';
import { GridComponent } from './grid.component';
import { OrgService } from '@eg/core/org.service';
import { ServerStoreService } from '@eg/core/server-store.service';
import { FormatService } from '@eg/core/format.service';
import { GridDataSource } from './grid';
import { TestBed } from '@angular/core/testing';
import { ChangeDetectorRef, CUSTOM_ELEMENTS_SCHEMA } from '@angular/core';
import { GridBodyComponent } from './grid-body.component';
import { GridHeaderComponent } from './grid-header.component';
import { GridPrintComponent } from './grid-print.component';
import { GridToolbarActionsMenuComponent } from './grid-toolbar-actions-menu.component';
import { GridToolbarComponent } from './grid-toolbar.component';
import { ProgressInlineComponent } from '../dialog/progress-inline.component';

const mockIdl = jasmine.createSpyObj<IdlService>([], {classes: {}});
const mockOrg = jasmine.createSpyObj<OrgService>(['root']);
const mockStore = jasmine.createSpyObj<ServerStoreService>(['getItem', 'setItem']);
const mockFormat = jasmine.createSpyObj<FormatService>(['transform']);
let component: GridComponent;

describe('GridComponent', () => {
    beforeEach(() => {
        TestBed.configureTestingModule({providers: [
            {provide: IdlService, useValue: mockIdl},
            {provide: OrgService, useValue: mockOrg},
            {provide: ServerStoreService, useValue: mockStore},
            {provide: FormatService, useValue: mockFormat},
            {provide: ChangeDetectorRef, useValue: null}
        ]});
        TestBed.overrideComponent(GridComponent, {
            add: {schemas: [CUSTOM_ELEMENTS_SCHEMA]},
            remove: {imports: [GridBodyComponent,
                GridHeaderComponent,
                GridPrintComponent,
                GridToolbarActionsMenuComponent,
                GridToolbarComponent,
                ProgressInlineComponent]}
        });
        component = TestBed.createComponent(GridComponent).componentInstance;
    });
    describe('ngOnInit', () => {
        it('adds initialFilterValues to the context', () => {
            component.initialFilterValues = {deleted: 'f'};
            component.dataSource = new GridDataSource();
            component.ngOnInit();
            expect(component.context.initialFilterValues).toEqual({deleted: 'f'});
        });
    });
});
