import {Router, ActivatedRoute} from '@angular/router';
import {AuthService} from '@eg/core/auth.service';
import {Component, ChangeDetectorRef, OnInit, ViewChild} from '@angular/core';
import {GridComponent} from '@eg/share/grid/grid.component';
import {GridDataSource} from '@eg/share/grid/grid';
import {GridFlatDataService} from '@eg/share/grid/grid-flat-data.service';
import {IdlService} from '@eg/core/idl.service';
import {NetService} from '@eg/core/net.service';
import {Pager} from '@eg/share/util/pager';
import {PcrudService} from '@eg/core/pcrud.service';
import {ProgressDialogComponent} from '@eg/share/dialog/progress.component';

@Component({
    templateUrl: 'urls.component.html'
})
export class LinkCheckerUrlsComponent implements OnInit {

    sessions: number[];
    session_names: string[] = [];
    sessionIdlClass = 'uvs';
    newBatches: number[] = [];
    urlsIdlClass = 'uvu';
    urlsSortField = 'name';
    urlsSessionField = 'session';
    urlsFleshFields = {
        'uvu' : ['item','url_selector'],
        'uvsbrem' : ['target_biblio_record_entry'],
        'bre' : ['simple_record']
    };
    // eslint-disable-next-line no-magic-numbers
    urlsFleshDepth = 3;
    urlsIdlClassDef: any;
    urlsPKeyField: string;

    urlsPermaCrud: any;
    urlsPerms: string;

    alertMessage = '';

    @ViewChild('progress', { static: true }) private progress: ProgressDialogComponent;
    progressText = '';

    @ViewChild('grid', { static: true }) grid: GridComponent;
    dataSource: GridDataSource = new GridDataSource();
    noSelectedRows: boolean;
    oneSelectedRow: boolean;

    constructor(
        private auth: AuthService,
        private flatData: GridFlatDataService,
        private idl: IdlService,
        private net: NetService,
        private pcrud: PcrudService,
        private route: ActivatedRoute,
        private router: Router,
        private cdr: ChangeDetectorRef,
    ) {}

    ngOnInit() {
        this.route.queryParams.subscribe( params => {
            if (params.sessions) {
                this.sessions = JSON.parse( params.sessions );
                this.grid.reload();
                // eslint-disable-next-line rxjs-x/no-nested-subscribe
                this.pcrud.search(this.sessionIdlClass, { id: this.sessions }).subscribe((n) => {
                    this.session_names.push(n.name());
                    this.cdr.detectChanges();
                });
            }
            if (params.alertMessage) {
                this.alertMessage = params.alertMessage;
            }
        });

        this.urlsIdlClassDef = this.idl.classes[this.urlsIdlClass];
        this.urlsPKeyField = this.urlsIdlClassDef.pkey || 'id';

        this.urlsPermaCrud = this.urlsIdlClassDef.permacrud || {};
        if (this.urlsPermaCrud.retrieve) {
            this.urlsPerms = this.urlsPermaCrud.retrieve.perms;
        }

        this.initDataSource();
        this.gridSelectionChange( [] );
        // console.log('phasefx',this);
    }

    gridSelectionChange(keys: string[]) {
        this.noSelectedRows = (keys.length === 0);
        this.oneSelectedRow = (keys.length === 1);
        // var rows = this.grid.context.getSelectedRows();
    }

    initDataSource() {
        this.dataSource.getRows = (pager: Pager, sort: any[]) => {

            const query: any = {};

            if (this.sessions) {
                query[this.urlsSessionField] = this.sessions;
            }

            let query_filters = [];
            Object.keys(this.dataSource.filters).forEach(key => {
                query_filters = query_filters.concat( this.dataSource.filters[key] );
            });

            if (query_filters.length > 0) {
                query['-and'] = query_filters;
            }

            return this.flatData.getRows(
                this.grid.context, query, pager, sort);
        };
    }

    stopProgressMeter() {
        this.progress.close();
        this.progress.reset();
    }

    resetProgressMeter(s: string) {
        this.progressText = s;
        this.progress.reset();
    }

    startProgressMeter(s: string) {
        this.progressText = s;
        this.progress.reset();
        this.progress.open();
    }

    verifyUrlsFilteredForSession(rows: any[], ses_ids: any[]) {
        const ses_id = ses_ids.pop();
        if (ses_id) {
            if (rows === null) {
                this.resetProgressMeter($localize`Verifying all URLs for Session ${ses_id}...`);
            } else {
                this.resetProgressMeter($localize`Verifying selected URLs for Session ${ses_id}...`);
            }
            console.log('Verifying selected URLs for Session ' + ses_id);
            this.net.request(
                'open-ils.url_verify',
                'open-ils.url_verify.session.verify',
                this.auth.token(),
                ses_id,
                rows === null
                    ? null // an empty [] would result in no URLs being processed
                    : rows.filter( url => url.session === ses_id ).map( url => url.id )
            ).subscribe({
                next: (res) => {
                    console.log('res',res);
                    this.progress.update({max: res['url_count'], value: res['total_processed']});
                    if (res['attempt']) { // last response
                        this.newBatches.push(res.attempt.id());
                    }
                },
                error: (err: unknown) => {
                    this.stopProgressMeter();
                    console.log('err',err);
                },
                complete: () => {
                    this.verifyUrlsFilteredForSession(rows,ses_ids);
                }
            });
        } else {
            console.log('go to attempts page');
            this.stopProgressMeter();
            this.router.navigate(['/staff/cat/linkchecker/attempts/'], {
                queryParams: { batches: JSON.stringify( Array.from( new Set( this.newBatches ) ) ) } });
        }
    }

    verifySelectedUrls() {
        const rows = this.grid.context.getSelectedRows();
        const session_ids = Array.from( new Set( rows.map(x => Number(x.session)) ) );
        this.startProgressMeter($localize`Verifying selected URLs for Sessions ${session_ids}...`);
        this.verifyUrlsFilteredForSession(rows,session_ids);
    }

    verifyAllUrls() {
        this.startProgressMeter($localize`Verifying All URLs for Sessions ${this.sessions}...`);
        this.verifyUrlsFilteredForSession(null,this.sessions);
    }
}
