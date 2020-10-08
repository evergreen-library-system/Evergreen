import {Component, OnInit, Input, Output} from '@angular/core';
import {Router, ActivatedRoute, ParamMap} from '@angular/router';
import {empty} from 'rxjs';
import {Pager} from '@eg/share/util/pager';
import {IdlObject} from '@eg/core/idl.service';
import {GridDataSource} from '@eg/share/grid/grid';
import {PcrudService} from '@eg/core/pcrud.service';

@Component({
  templateUrl: 'history.component.html',
  selector: 'eg-lineitem-history'
})
export class LineitemHistoryComponent implements OnInit {

    lineitemId: number;
    dataSource: GridDataSource = new GridDataSource();

    constructor(
        private route: ActivatedRoute,
        private pcrud: PcrudService
    ) {}

    ngOnInit() {

        this.dataSource.getRows = (pager: Pager, sort: any) =>
            this.getHistory(pager, sort);

        this.route.paramMap.subscribe((params: ParamMap) => {
            this.lineitemId = +params.get('lineitemId');
        });
   }

    getHistory(pager: Pager, sort: any) {
        if (!this.lineitemId) { return empty(); }

        const orderBy: any = {acqlih: 'edit_time DESC'};
        if (sort.length) {
            orderBy.acqlih = sort[0].name + ' ' + sort[0].dir;
        }

        return this.pcrud.search('acqlih', {id: this.lineitemId}, {
            offset: pager.offset,
            limit: pager.limit,
            order_by: orderBy,
            flesh: 1,
            flesh_fields: {
                acqlih: ['creator', 'editor', 'provider', 'cancel_reason']
            }
        });
    }
}

