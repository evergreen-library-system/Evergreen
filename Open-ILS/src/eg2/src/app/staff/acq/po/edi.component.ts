import { Component, OnInit, inject } from '@angular/core';
import {ActivatedRoute, ParamMap} from '@angular/router';
import {empty} from 'rxjs';
import {Pager} from '@eg/share/util/pager';
import {GridDataSource} from '@eg/share/grid/grid';
import {PcrudService} from '@eg/core/pcrud.service';
import { GridModule } from '@eg/share/grid/grid.module';

@Component({
    templateUrl: 'edi.component.html',
    imports: [GridModule]
})
export class PoEdiMessagesComponent implements OnInit {
    private route = inject(ActivatedRoute);
    private pcrud = inject(PcrudService);


    poId: number;
    dataSource: GridDataSource = new GridDataSource();

    ngOnInit() {
        this.dataSource.getRows = (pager: Pager, sort: any) =>
            this.getEdiMessages(pager, sort);

        this.route.parent.paramMap.subscribe((params: ParamMap) => {
            this.poId = +params.get('poId');
        });
    }

    getEdiMessages(pager: Pager, sort: any) {
        if (!this.poId) { return empty(); }

        const orderBy: any = {acqedim: 'create_time DESC'};
        if (sort.length) {
            orderBy.acqedim = sort[0].name + ' ' + sort[0].dir;
        }

        return this.pcrud.search('acqedim', {purchase_order: this.poId}, {
            offset: pager.offset,
            limit: pager.limit,
            order_by: orderBy,
            flesh: 1,
            flesh_fields: {acqedim: ['account', 'purchase_order']}
        });
    }
}

