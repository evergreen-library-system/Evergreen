import { Component, Input, ViewChild, inject } from '@angular/core';
import {Pager} from '@eg/share/util/pager';
import {NetService} from '@eg/core/net.service';
import {PcrudService} from '@eg/core/pcrud.service';
import {AuthService} from '@eg/core/auth.service';
import {GridComponent} from '@eg/share/grid/grid.component';
import {GridDataSource} from '@eg/share/grid/grid';
import {VandelayService} from './vandelay.service';
import { StaffCommonModule } from '@eg/staff/common.module';

@Component({
    selector: 'eg-queued-record-items',
    templateUrl: 'record-items.component.html',
    imports: [StaffCommonModule]
})
export class RecordItemsComponent {
    private net = inject(NetService);
    private auth = inject(AuthService);
    private pcrud = inject(PcrudService);
    private vandelay = inject(VandelayService);


    @Input() recordId: number;

    gridSource: GridDataSource;
    @ViewChild('itemsGrid', { static: true }) itemsGrid: GridComponent;

    constructor() {

        this.gridSource = new GridDataSource();

        // queue API does not support sorting
        this.gridSource.getRows = (pager: Pager) => {
            return this.pcrud.search('vii',
                {record: this.recordId}, {order_by: {vii: ['id']}});
        };
    }
}

