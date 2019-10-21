import {Component, OnInit, ViewChild} from '@angular/core';
import {Observable} from 'rxjs';
import {map} from 'rxjs/operators';
import {Router, ActivatedRoute, ParamMap} from '@angular/router';
import {Pager} from '@eg/share/util/pager';
import {IdlObject} from '@eg/core/idl.service';
import {NetService} from '@eg/core/net.service';
import {AuthService} from '@eg/core/auth.service';
import {GridComponent} from '@eg/share/grid/grid.component';
import {GridDataSource} from '@eg/share/grid/grid';
import {VandelayService} from './vandelay.service';

@Component({
  templateUrl: 'queue-items.component.html'
})
export class QueueItemsComponent {

    queueType: string;
    queueId: number;
    filterImportErrors: boolean;

    gridSource: GridDataSource;
    @ViewChild('itemsGrid', { static: true }) itemsGrid: GridComponent;

    constructor(
        private router: Router,
        private route: ActivatedRoute,
        private net: NetService,
        private auth: AuthService,
        private vandelay: VandelayService) {

        this.route.paramMap.subscribe((params: ParamMap) => {
            this.queueId = +params.get('id');
            this.queueType = params.get('qtype');
        });

        this.gridSource = new GridDataSource();

        // queue API does not support sorting
        this.gridSource.getRows = (pager: Pager) => {
            return this.net.request(
                'open-ils.vandelay',
                'open-ils.vandelay.import_item.queue.retrieve',
                this.auth.token(), this.queueId, {
                    with_import_error: this.filterImportErrors,
                    offset: pager.offset,
                    limit: pager.limit
                }
            );
        };
    }

    limitToImportErrors(checked: boolean) {
        this.filterImportErrors = checked;
        this.itemsGrid.reload();
    }

}

