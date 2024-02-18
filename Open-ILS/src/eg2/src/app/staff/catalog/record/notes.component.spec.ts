import { PcrudService } from '@eg/core/pcrud.service';
import { NotesComponent } from './notes.component';
import { of } from 'rxjs';
import { PermService } from '@eg/core/perm.service';
import { GridComponent } from '@eg/share/grid/grid.component';
import { waitForAsync } from '@angular/core/testing';
import { EventEmitter } from '@angular/core';
import { Pager } from '@eg/share/util/pager';
import { NetService } from '@eg/core/net.service';
import { AuthService } from '@eg/core/auth.service';

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

            const component = new NotesComponent(null, mockPcrud, mockPerm, mockNet, jasmine.createSpyObj<AuthService>(['token']));
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
