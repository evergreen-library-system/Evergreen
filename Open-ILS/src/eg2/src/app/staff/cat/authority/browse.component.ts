import {Component, OnInit, ViewChild} from '@angular/core';
import {Observable, EMPTY} from 'rxjs';
import {Pager} from '@eg/share/util/pager';
import {NetService} from '@eg/core/net.service';
import {PcrudService} from '@eg/core/pcrud.service';
import {OrgService} from '@eg/core/org.service';
import {GridComponent} from '@eg/share/grid/grid.component';
import {GridDataSource, GridCellTextGenerator,
    GridRowFlairEntry} from '@eg/share/grid/grid';
import {ComboboxEntry, ComboboxComponent} from '@eg/share/combobox/combobox.component';
import {BrowseService} from './browse.service';
import {StringComponent} from '@eg/share/string/string.component';
import {AuthorityMergeDialogComponent} from './merge-dialog.component';

/* Find, merge, and edit authority records */

@Component({
    templateUrl: 'browse.component.html',
    styles: ['#offset-input { width: 4em; }']
})
export class BrowseAuthorityComponent implements OnInit {

    authorityAxis: ComboboxEntry;
    dataSource: GridDataSource;
    cellTextGenerator: GridCellTextGenerator;

    rowFlairCallback: (row: any) => GridRowFlairEntry;

    @ViewChild('grid', {static: false}) grid: GridComponent;
    @ViewChild('axisCbox', {static: false}) axisCbox: ComboboxComponent;
    @ViewChild('rowSelected', {static: false}) rowSelected: StringComponent;
    @ViewChild('mergeDialog', {static: false})
        mergeDialog: AuthorityMergeDialogComponent;

    constructor(
        private net: NetService,
        private org: OrgService,
        private pcrud: PcrudService,
        public browse: BrowseService
    ) {}

    ngOnInit() {
        this.browse.fetchAxes();
        this.setupGrid();
    }

    setupGrid() {
        this.dataSource = new GridDataSource();

        this.dataSource.getRows =
            (pager: Pager, sort: any): Observable<any> => {

                if (this.authorityAxis) {
                    this.browse.authorityAxis = this.authorityAxis.id;

                } else {
                // Our browse service may have cached search params
                    if (this.browse.authorityAxis) {
                        this.axisCbox.selectedId = this.browse.authorityAxis;
                        this.authorityAxis = this.axisCbox.selected;
                    } else {
                        return EMPTY;
                    }
                }

                return this.browse.loadAuthorities();
            };

        this.cellTextGenerator = {
            heading: row => row.heading
        };

        this.rowFlairCallback = (row: any): GridRowFlairEntry => {
            const flair = {icon: null, title: null};
            if (this.browse.markedForMerge[row.authority.id()]) {
                flair.icon = 'merge_type';
                flair.title = this.rowSelected.text;
            }
            return flair;
        };
    }


    markForMerge(rows: any[]) {
        rows.forEach(row =>
            this.browse.markedForMerge[row.authority.id()] = row);
    }

    unMarkForMerge(rows: any[]) {
        rows.forEach(row =>
            delete this.browse.markedForMerge[row.authority.id()]);
    }

    clearMergeSelection() {
        this.browse.markedForMerge = {};
    }

    search(offset?: number, isNew?: boolean) {
        if (offset) {
            this.browse.searchOffset += offset;
        } else if (isNew) {
            this.browse.searchOffset = 0;
        }
        this.grid.reload();
    }

    openMergeDialog() {
        const rows = Object.values(this.browse.markedForMerge);
        if (rows.length > 0) {
            this.mergeDialog.authData = rows;
            this.mergeDialog.open({size: 'lg'}).subscribe(success => {
                if (success) {
                    this.clearMergeSelection();
                    this.search();
                }
            });
        }
    }
}


