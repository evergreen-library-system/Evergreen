import {Component, ViewChild} from '@angular/core';
import {Observable, of} from 'rxjs';
import {map} from 'rxjs/operators';
import {Router, ActivatedRoute, ParamMap} from '@angular/router';
import {Pager} from '@eg/share/util/pager';
import {IdlObject} from '@eg/core/idl.service';
import {EventService} from '@eg/core/event.service';
import {PcrudService} from '@eg/core/pcrud.service';
import {NetService} from '@eg/core/net.service';
import {AuthService} from '@eg/core/auth.service';
import {GridComponent} from '@eg/share/grid/grid.component';
import {GridDataSource, GridColumn, GridCellTextGenerator} from '@eg/share/grid/grid';
import {ConfirmDialogComponent} from '@eg/share/dialog/confirm.component';
import {ProgressDialogComponent} from '@eg/share/dialog/progress.component';

@Component({
    templateUrl: 'background-import.component.html'
})
export class BackgroundImportComponent {

    import_type_param: string = null;
    jobsToDelete: any[] = [];
    jobSource: GridDataSource;

    @ViewChild('confirmDelDlg', { static: false }) confirmDelDlg: ConfirmDialogComponent;
    @ViewChild('progressDlg', { static: true }) progressDlg: ProgressDialogComponent;
    @ViewChild('jobGrid', { static: false }) jobGrid: GridComponent;

    cellTextGenerator: GridCellTextGenerator;

    constructor(
        private router: Router,
        private route: ActivatedRoute,
        private pcrud: PcrudService,
        private evt: EventService,
        private net: NetService,
        private auth: AuthService) {

        this.route.queryParamMap.subscribe((params: ParamMap) => {
            this.import_type_param = params.get('type');
        });

        this.cellTextGenerator = {
            queue: row => row.queue(),
            stats: row => row.queueSummary
        };

        this.jobSource = new GridDataSource();
        this.jobSource.sort = [{name: 'request_time', dir: 'desc'}];
        this.jobSource.getRows = (pager: Pager, sort: any[]) => {
            const orderBy: any = {};

            if (sort.length) {
                orderBy['vbi'] = sort[0].name + ' ' + sort[0].dir;
            }

            const searchOps = {
                offset: pager.offset,
                limit: pager.limit,
                order_by: orderBy
            };

            // In this UI, only show my own jobs, and all of them, paged.
            const search = { owner: this.auth.user().id() };
            if (this.import_type_param) {
                search['import_type'] = this.import_type_param;
            }

            return this.pcrud.search(
                'vbi', search, searchOps, {fleshSelectors: true}
            ).pipe(map(b => { if (b.queue()) {this.loadQueueSummary(b);} return b; }));
        };
    }

    qtypeShort(b): string {
        return b.import_type().match(/auth/) ? 'auth' : 'bib';
    }

    loadQueueSummary(b): Promise<any> {
        const method =
            `open-ils.vandelay.${this.qtypeShort(b)}_queue.summary.retrieve`;

        return this.net.request(
            'open-ils.vandelay', method, this.auth.token(), b.queue())
            .toPromise().then(sum => b.queueSummary = sum);
    }

    queueLinkType(type) {
        if (type === 'auth') {
            return 'authority';
        }
        return 'bib';
    }

    rowActivated(row: any) {
        if (row.queue()) {
            const url = `/staff/cat/vandelay/queue/${row.import_type()}/${row.queue()}`;
            this.router.navigate([url]);
        }
    }

    deleteJobs(rows) {
        this.jobsToDelete = [...rows];

        this.confirmDelDlg.open().subscribe(confirmed => {
            if (!confirmed) { return; }

            this.progressDlg.open();
            this.pcrud.remove(this.jobsToDelete).toPromise().then(
                resp => {
                    const e = this.evt.parse(resp);
                    if (e) { return new Error(e.toString()); }
                    this.jobGrid.reload();
                },
                err => console.error('job deletion failed!', err)
            ).finally(() => { this.jobsToDelete = []; this.progressDlg.close(); });
        });
    }
}

