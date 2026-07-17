import { PcrudService } from '@eg/core/pcrud.service';
import { NotesComponent } from './notes.component';
import { of } from 'rxjs';
import { PermService } from '@eg/core/perm.service';
import { GridComponent } from '@eg/share/grid/grid.component';
import { TestBed, waitForAsync } from '@angular/core/testing';
import { CUSTOM_ELEMENTS_SCHEMA, EventEmitter } from '@angular/core';
import { Pager } from '@eg/share/util/pager';
import { NetService } from '@eg/core/net.service';
import { AuthService } from '@eg/core/auth.service';
import { IdlService } from '@eg/core/idl.service';
import { GridModule } from '@eg/share/grid/grid.module';
import { FmRecordEditorComponent } from '@eg/share/fm-editor/fm-editor.component';
import { StaffCommonModule } from '@eg/staff/common.module';

describe('NotesComponent', () => {
    describe('grid data source', () => {
        it('emits an event with the current number of notes', waitForAsync(() => {
            const mockPcrud = jasmine.createSpyObj<PcrudService>(['search']);
            mockPcrud.search.and.returnValue(of(
                {id: '123'},
                {id: '234'}
            ));

            const mockNet = jasmine.createSpyObj<NetService>(['request']);
            mockNet.request.and.returnValue(of(8));

            const mockPerm = jasmine.createSpyObj<PermService>(['hasWorkPermHere']);
            mockPerm.hasWorkPermHere.and.resolveTo(null);

            TestBed.configureTestingModule({providers: [
                {provide: IdlService, useValue: null},
                {provide: PcrudService, useValue: mockPcrud},
                {provide: PermService, useValue: mockPerm},
                {provide: NetService, useValue: mockNet},
                {provide: AuthService, useValue: jasmine.createSpyObj<AuthService>(['token'])}
            ]});
            TestBed.overrideComponent(NotesComponent, {
                add: {schemas: [CUSTOM_ELEMENTS_SCHEMA]},
                remove: {imports: [FmRecordEditorComponent, GridModule, StaffCommonModule]}
            });

            const component = TestBed.createComponent(NotesComponent).componentInstance;
            component.notesGrid = jasmine.createSpyObj<GridComponent>('GridComponent', [], {onRowActivate: new EventEmitter()});

            spyOn(component.noteCountUpdated, 'emit');
            component.ngOnInit();

            component.gridDataSource.getRows(new Pager(), []).subscribe({
                complete: () => {
                    expect(component.noteCountUpdated.emit).toHaveBeenCalledOnceWith(8);
                }
            });
        }));
    });
});
