import { EMPTY, of } from 'rxjs';
import { GridContext, GridDataSource } from './grid';
import { Pager } from '../util/pager';
import { GridToolbarComponent } from './grid-toolbar.component';
import { ComponentFixture, fakeAsync, TestBed, tick, waitForAsync } from '@angular/core/testing';
import { CUSTOM_ELEMENTS_SCHEMA } from '@angular/core';

describe('GridToolbarComponent', () => {
    let component: GridToolbarComponent;
    let fixture: ComponentFixture<GridToolbarComponent>;

    beforeEach(waitForAsync(() => {
        TestBed.configureTestingModule({
            declarations: [GridToolbarComponent],
            schemas: [CUSTOM_ELEMENTS_SCHEMA]
        });
    }));
    beforeEach(() => {
        fixture = TestBed.createComponent(GridToolbarComponent);
        component = fixture.componentInstance;
        component.gridContext = new GridContext(null, null, null, null, null);
        component.gridContext.init();
    });
    describe('when there are no items in the grid', () => {
        it('disables the CSV download link', fakeAsync(() => {
            // Set up a data source that returns no rows
            component.gridContext.dataSource = new GridDataSource();
            component.gridContext.dataSource.getRows = (pager, sort) => EMPTY;
            component.gridContext.dataSource.getPageOfRows(new Pager());
            component.gridContext.initData();
            tick();
            fixture.detectChanges();

            const links: HTMLAnchorElement[] = Array.from(fixture.nativeElement.querySelectorAll('a'));
            const csvLink = links.find((link) => link.innerText.includes('CSV'));
            expect(csvLink.classList).toContain('disabled');
        }));
    });

    describe('when there are some items in the grid', () => {
        it('does not disable the CSV download link', fakeAsync(() => {
            // Set up a data source that returns a row
            component.gridContext.dataSource = new GridDataSource();
            component.gridContext.dataSource.getRows = (pager, sort) => of({title: 'My book', author: 'Such a cool author'});
            component.gridContext.dataSource.getPageOfRows(new Pager());
            component.gridContext.initData();
            tick();
            fixture.detectChanges();

            const links: HTMLAnchorElement[] = Array.from(fixture.nativeElement.querySelectorAll('a'));
            const csvLink = links.find((link) => link.innerText.includes('CSV'));
            expect(csvLink.classList).not.toContain('disabled');
        }));
    });
});
