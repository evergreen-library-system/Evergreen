import { Component, ViewChild, inject } from '@angular/core';
import {Router, ActivatedRoute, ParamMap} from '@angular/router';
import {Pager} from '@eg/share/util/pager';
import {NetService} from '@eg/core/net.service';
import {AuthService} from '@eg/core/auth.service';
import {GridComponent} from '@eg/share/grid/grid.component';
import {GridDataSource} from '@eg/share/grid/grid';
import {VandelayService} from './vandelay.service';
import { StaffCommonModule } from '@eg/staff/common.module';

@Component({
    templateUrl: 'queue-items.component.html',
    imports: [StaffCommonModule]
})
export class QueueItemsComponent {
    private router = inject(Router);
    private route = inject(ActivatedRoute);
    private net = inject(NetService);
    private auth = inject(AuthService);
    private vandelay = inject(VandelayService);


    queueType: string;
    queueId: number;
    filterImportErrors: boolean;

    gridSource: GridDataSource;
    @ViewChild('itemsGrid', { static: true }) itemsGrid: GridComponent;

    constructor() {

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

