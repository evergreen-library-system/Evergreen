import {Component, Input, OnInit, ViewChild} from '@angular/core';
import {Observable, EMPTY, from, switchMap} from 'rxjs';
import {Pager} from '@eg/share/util/pager';
import {NetService} from '@eg/core/net.service';
import {PcrudService} from '@eg/core/pcrud.service';
import {OrgService} from '@eg/core/org.service';
import {GridComponent} from '@eg/share/grid/grid.component';
import {GridDataSource, GridCellTextGenerator} from '@eg/share/grid/grid';


/* Grid of bib records and associated actions. */

@Component({
    templateUrl: 'bib-list.component.html',
    selector: 'eg-bib-list'
})
export class BibListComponent implements OnInit {

    // Static source of bib record IDs
    @Input() bibIds: number[];
    // Dynamic source of bib record IDs
    @Input() bibIdSource: (pager: Pager, sort: any) => Promise<number[]>;
    @Input() gridPersistKey: string;

    dataSource: GridDataSource;
    cellTextGenerator: GridCellTextGenerator;

    @ViewChild('grid', {static: false}) grid: GridComponent;

    constructor(
        private net: NetService,
        private org: OrgService,
        private pcrud: PcrudService
    ) {
    }

    ngOnInit() {
        this.dataSource = new GridDataSource();

        this.dataSource.getRows = (pager: Pager, sort: any): Observable<any> => {

            if (this.bibIds || this.bibIdSource) {
                return this.loadIds(pager, sort);
            }

            return EMPTY;
        };

        this.cellTextGenerator = {
            title: row => row.title
        };
    }

    loadIds(pager: Pager, sort: any): Observable<any> {

        let promise: Promise<number[]>;

        if (this.bibIdSource) {
            promise = this.bibIdSource(pager, sort);

        } else if (this.bibIds && this.bibIds.length > 0) {
            promise = Promise.resolve(
                this.bibIds.slice(pager.offset, pager.offset + pager.limit));

        } else {
            return EMPTY;
        }

        // ID is the currently only supported sort column.  If other
        // columns are added, callers providing a bibIdSource will need
        // to implement the new columns as well.
        const orderBy = {rmsr: 'id'};
        if (sort.length && sort[0].name === 'id') {
            orderBy.rmsr = orderBy.rmsr + ' ' + sort[0].dir;
        }

        return from(promise).pipe(switchMap(bibIds => {

            if (bibIds.length === 0) { return EMPTY; }

            return this.pcrud.search('rmsr', {id: bibIds}, {
                order_by: orderBy,
                flesh: 2,
                flesh_fields: {
                    rmsr: ['biblio_record'],
                    bre: ['creator', 'editor']
                }
            });
        }));
    }
}


