import { ComponentFixture, TestBed } from '@angular/core/testing';

import { HoldGroupUsersComponent } from './hold-group-users.component';
import { GridDataSource } from '@eg/share/grid/grid';
import { Pager } from '@eg/share/util/pager';
import {of} from 'rxjs';

describe('HoldGroupUsersComponent', () => {
    let component: HoldGroupUsersComponent;
    let fixture: ComponentFixture<HoldGroupUsersComponent>;

    beforeEach(async () => {
        await TestBed.configureTestingModule({
            imports: [HoldGroupUsersComponent]
        })
            .compileComponents();

        fixture = TestBed.createComponent(HoldGroupUsersComponent);
        component = fixture.componentInstance;
        fixture.detectChanges();
    });

    it('should create', () => {
        expect(component).toBeTruthy();
    });

    fit('should disable the actions if no rows are selected', () => {
        expect(component.grid).toBeTruthy();

        const dataSource = new GridDataSource();
        dataSource.getRows = (pager: Pager, sort) => {
            return of([]);
        };
        component.grid.dataSource = dataSource;
        component.grid.context.initData();


    });
});
