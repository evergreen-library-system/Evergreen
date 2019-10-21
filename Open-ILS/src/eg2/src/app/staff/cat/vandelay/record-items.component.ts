import {Component, Input, ViewChild} from '@angular/core';
import {Pager} from '@eg/share/util/pager';
import {IdlObject} from '@eg/core/idl.service';
import {NetService} from '@eg/core/net.service';
import {PcrudService} from '@eg/core/pcrud.service';
import {AuthService} from '@eg/core/auth.service';
import {GridComponent} from '@eg/share/grid/grid.component';
import {GridDataSource} from '@eg/share/grid/grid';
import {VandelayService} from './vandelay.service';

@Component({
  selector: 'eg-queued-record-items',
  templateUrl: 'record-items.component.html'
})
export class RecordItemsComponent {

    @Input() recordId: number;

    gridSource: GridDataSource;
    @ViewChild('itemsGrid', { static: true }) itemsGrid: GridComponent;

    constructor(
        private net: NetService,
        private auth: AuthService,
        private pcrud: PcrudService,
        private vandelay: VandelayService) {

        this.gridSource = new GridDataSource();

        // queue API does not support sorting
        this.gridSource.getRows = (pager: Pager) => {
            return this.pcrud.search('vii',
                {record: this.recordId}, {order_by: {vii: ['id']}});
        };
    }
}

