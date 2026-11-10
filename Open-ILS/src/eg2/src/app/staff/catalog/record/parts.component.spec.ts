import { TestBed } from '@angular/core/testing';
import { NetService } from '@eg/core/net.service';
import { MockGenerators } from 'test_data/mock_generators';
import { of } from 'rxjs';
import { PcrudService } from '@eg/core/pcrud.service';
import { AuthService } from '@eg/core/auth.service';
import { PermService } from '@eg/core/perm.service';
import { PartsComponent } from './parts.component';
import { CUSTOM_ELEMENTS_SCHEMA, EventEmitter } from '@angular/core';
import { GridComponent } from '@eg/share/grid/grid.component';
import { Pager } from '@eg/share/util/pager';

describe('PartsComponent', () => {
    describe('grid data source', () => {
        it('emits an event with the current number of parts', (done) => {
            TestBed.configureTestingModule({providers: [
                {provide: NetService, useValue: MockGenerators.netService({
                    'open-ils.search.biblio.parts_count': of(27)
                })},
                {provide: PcrudService, useValue: MockGenerators.pcrudService({})},
                {provide: AuthService, useValue: MockGenerators.authService()},
                {provide: PermService, useValue: MockGenerators.permService({})}
            ]}).overrideComponent(PartsComponent, {
                set: {imports: [], schemas: [CUSTOM_ELEMENTS_SCHEMA]}
            });

            const component = TestBed.createComponent(PartsComponent).componentInstance;
            component.partsGrid = jasmine.createSpyObj<GridComponent>('GridComponent', [], {onRowActivate: new EventEmitter()});

            spyOn(component.partsCountUpdated, 'emit');
            component.ngOnInit();

            component.gridDataSource.getRows(new Pager(), []).subscribe({
                complete: () => {
                    expect(component.partsCountUpdated.emit).toHaveBeenCalledOnceWith(27);
                    done();
                }
            });
        });
    });
});
