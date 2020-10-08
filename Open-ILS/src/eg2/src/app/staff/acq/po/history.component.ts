import {Component, OnInit, Input, Output} from '@angular/core';
import {Router, ActivatedRoute, ParamMap} from '@angular/router';
import {empty} from 'rxjs';
import {Pager} from '@eg/share/util/pager';
import {IdlObject} from '@eg/core/idl.service';
import {GridDataSource} from '@eg/share/grid/grid';
import {PcrudService} from '@eg/core/pcrud.service';

@Component({templateUrl: 'history.component.html'})
export class PoHistoryComponent implements OnInit {

    poId: number;
    dataSource: GridDataSource = new GridDataSource();

    constructor(
        private route: ActivatedRoute,
        private pcrud: PcrudService
    ) {}

    ngOnInit() {
        this.dataSource.getRows = (pager: Pager, sort: any) =>
            this.getHistory(pager, sort);

        this.route.parent.paramMap.subscribe((params: ParamMap) => {
            this.poId = +params.get('poId');
        });
   }

    getHistory(pager: Pager, sort: any) {
        if (!this.poId) { return empty(); }

        const orderBy: any = {acqpoh: 'edit_time DESC'};
        if (sort.length) {
            orderBy.acqpoh = sort[0].name + ' ' + sort[0].dir;
        }

        return this.pcrud.search('acqpoh', {id: this.poId}, {
            offset: pager.offset,
            limit: pager.limit,
            order_by: orderBy,
            flesh: 1,
            flesh_fields: {
                acqpoh: ['owner', 'creator', 'editor', 'provider', 'cancel_reason']
            }
        });
    }
}

