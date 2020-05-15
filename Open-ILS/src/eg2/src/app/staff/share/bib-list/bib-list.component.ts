import {Component, Input, OnInit, ViewChild} from '@angular/core';
import {Observable, empty} from 'rxjs';
import {map, switchMap} from 'rxjs/operators';
import {IdlObject} from '@eg/core/idl.service';
import {Pager} from '@eg/share/util/pager';
import {NetService} from '@eg/core/net.service';
import {PcrudService} from '@eg/core/pcrud.service';
import {OrgService} from '@eg/core/org.service';
import {GridComponent} from '@eg/share/grid/grid.component';
import {GridContext, GridDataSource, GridCellTextGenerator} from '@eg/share/grid/grid';
import {ComboboxEntry} from '@eg/share/combobox/combobox.component';


/* Grid of bib records and associated actions. */

@Component({
  templateUrl: 'bib-list.component.html',
  selector: 'eg-bib-list'
})
export class BibListComponent implements OnInit {

    // Display bibs linked to this authority record.
    @Input() bibIds: number[];
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

            if (this.bibIds) {
                return this.loadIds(pager, sort);
            }

            return empty();
        };

        this.cellTextGenerator = {
            title: row => row.title
        };
    }

    loadIds(pager: Pager, sort: any): Observable<any> {
        if (this.bibIds.length === 0) {
            return empty();
        }

        const orderBy: any = {rmsr: 'title'};
        if (sort.length) {
            orderBy.rmsr = sort[0].name + ' ' + sort[0].dir;
        }

        return this.pcrud.search('rmsr', {id: this.bibIds}, {
            order_by: orderBy,
            limit: pager.limit,
            offset: pager.offset,
            flesh: 2,
            flesh_fields: {
                rmsr: ['biblio_record'],
                bre: ['creator', 'editor']
            }
        });
    }
}


