import {Router, ActivatedRoute} from '@angular/router';
import {AuthService} from '@eg/core/auth.service';
import {Component, OnInit, ViewChild} from '@angular/core';
import {ConfirmDialogComponent} from '@eg/share/dialog/confirm.component';
import {NewSessionDialogComponent} from './new-session-dialog.component';
import {GridComponent} from '@eg/share/grid/grid.component';
import {GridDataSource} from '@eg/share/grid/grid';
import {GridFlatDataService} from '@eg/share/grid/grid-flat-data.service';
import {IdlService, IdlObject} from '@eg/core/idl.service';
import {NetService} from '@eg/core/net.service';
import {OrgFamily} from '@eg/share/org-family-select/org-family-select.component';
import {OrgService} from '@eg/core/org.service';
import {Pager} from '@eg/share/util/pager';
import {PermService} from '@eg/core/perm.service';
import {StringComponent} from '@eg/share/string/string.component';

@Component({
    templateUrl: 'linkchecker.component.html'
})
export class LinkCheckerComponent implements OnInit {

    viewIdlClass = 'uvsa';
    viewSortField = 'name';
    viewOrgField = 'owning_lib';
    viewFleshFields = { 'uvsa' : ['creator','owning_lib','container','usr'] };
    viewFleshDepth = 1;
    viewIdlClassDef: any;
    viewPKeyField: string;

    sessionIdlClass = 'uvs';
    sessionIdlClassDef: any;

    batchIdlClass = 'uvva';
    batchIdlClassDef: any;

    canCreateSession: boolean;
    canCreateBatch: boolean;
    viewPermaCrud: any;

    dataSource: GridDataSource = new GridDataSource();
    contextOrg: IdlObject;
    searchOrgs: OrgFamily;
    viewPerms: string;

    @ViewChild('grid', { static: true }) grid: GridComponent;
    noSelectedRows: boolean;
    oneSelectedRow: boolean;
    onlyBatchesSelected: boolean;

    @ViewChild('newSessionDialog', { static: true }) newSessionDialog: NewSessionDialogComponent;
    @ViewChild('createSuccessString', { static: false }) createSuccessString: StringComponent;
    @ViewChild('createFailedString', { static: false }) createFailedString: StringComponent;
    @ViewChild('deleteSessionConfirmDialog', { static: true }) deleteSessionConfirmDialog: ConfirmDialogComponent;

    constructor(
        private auth: AuthService,
        private flatData: GridFlatDataService,
        private idl: IdlService,
        private net: NetService,
        private org: OrgService,
        private perm: PermService,
        private route: ActivatedRoute,
        private router: Router,
    ) {}

    ngOnInit() {

        this.sessionIdlClassDef = this.idl.classes[this.sessionIdlClass];
        this.batchIdlClassDef = this.idl.classes[this.batchIdlClass];
        this.viewIdlClassDef = this.idl.classes[this.viewIdlClass];
        this.viewPKeyField = this.viewIdlClassDef.pkey || 'id';

        this.viewPermaCrud = this.viewIdlClassDef.permacrud || {};
        if (this.viewPermaCrud.retrieve) {
            this.viewPerms = this.viewPermaCrud.retrieve.perms;
        }

        const contextOrg = this.route.snapshot.queryParamMap.get('contextOrg');
        this.applyOrgValues(Number(contextOrg));

        this.checkCreateSessionPerms();
        this.checkCreateBatchPerms();

        this.initDataSource();
        this.gridSelectionChange( [] );
    }

    viewSessionUrls() {
        const rows = this.grid.context.getSelectedRows();
        const ids = Array.from( new Set( rows.map(x => Number(x.session_id)) ) );
        this.router.navigate(['/staff/cat/linkchecker/urls/'], { queryParams: { sessions: JSON.stringify(ids) } });
    }

    viewSessionAttempts() {
        const rows = this.grid.context.getSelectedRows();
        const ids = Array.from( new Set( rows.map(x => Number(x.session_id)) ) );
        this.router.navigate(['/staff/cat/linkchecker/attempts/'], { queryParams: { sessions: JSON.stringify(ids) } });
    }

    viewBatchAttempts() {
        const rows = this.grid.context.getSelectedRows();
        const ids = Array.from( new Set( rows.map(x => Number(x.batch_id)) ) );
        this.router.navigate(['/staff/cat/linkchecker/attempts/'], { queryParams: { batches: JSON.stringify(ids) } });
    }

    applyOrgValues(orgId?: number) {
        this.contextOrg = this.org.get(orgId) || this.org.get(this.auth.user().ws_ou()) || this.org.root();
        this.searchOrgs = {primaryOrgId: this.contextOrg.id()};
    }

    gridSelectionChange(keys: string[]) {
        const rows = this.grid.context.getSelectedRows();
        console.log('keys.length = ' + keys.length + ', rows.length = ' + rows.length);

        this.noSelectedRows = (rows.length === 0);
        this.oneSelectedRow = (rows.length === 1);
        this.onlyBatchesSelected = ! this.noSelectedRows;

        rows.forEach(row => {
            if (!row.batch_id) {
                this.onlyBatchesSelected = false;
            }
        });
    }

    checkCreateSessionPerms() {
        this.canCreateSession = false;
        const pc = this.sessionIdlClassDef.permacrud || {};
        const perms = pc.create ? pc.create.perms : [];
        if (perms.length === 0) { return; }

        this.perm.hasWorkPermAt(perms, true).then(permMap => {
            Object.keys(permMap).forEach(key => {
                if (permMap[key].length > 0) {
                    this.canCreateSession = true;
                }
            });
        });
    }

    checkCreateBatchPerms() {
        this.canCreateBatch = false;
        const pc = this.batchIdlClassDef.permacrud || {};
        const perms = pc.create ? pc.create.perms : [];
        if (perms.length === 0) { return; }

        this.perm.hasWorkPermAt(perms, true).then(permMap => {
            Object.keys(permMap).forEach(key => {
                if (permMap[key].length > 0) {
                    this.canCreateBatch = true;
                }
            });
        });
    }

    newSessionWrapper(optionalSessionToClone?: any) {
        this.newSessionDialog.sessionToClone = optionalSessionToClone;
        this.newSessionDialog.open({size: 'lg'}).subscribe( (res) => {
            let alertMessage = '';
            console.log('new dialog res', res);
            if (res['sessionId']) {
                alertMessage =
                      $localize`Session ID = ` + res['sessionId'] + '\n'
                    + $localize`Title Hits = ` + res['number_of_hits'] + '\n'
                    + $localize`URLs Extracted = ` + res['urls_extracted'] + '\n'
                    + $localize`URLs Verified = ` + res['verified_total_processed'] + '\n';
                // window.alert(alertMessage);
            }
            if (res && res['sessionId']) {
                if (res['viewURLs'] && res['urls_extracted'] > 0) {
                    this.router.navigate(['/staff/cat/linkchecker/urls/'],
                        { queryParams: { alertMessage: alertMessage, sessions: JSON.stringify([ Number(res['sessionId']) ]) } });
                } else if (res['viewAttempts'] && res['verified_total_processed'] > 0) {
                    this.router.navigate(['/staff/cat/linkchecker/attempts/'],
                        { queryParams: { alertMessage: alertMessage, sessions: JSON.stringify([ Number(res['sessionId']) ]) } });
                } else {
                    this.grid.reload();
                }
            }
        });
    }

    cloneSelectedSession() {
        const rows = this.grid.context.getSelectedRows();
        if (rows.length !== 1) { return; }
        this.newSessionWrapper(rows[0]);
    }

    deleteSelectedSessions() {
        const rows = this.grid.context.getSelectedRows();
        if (rows.length === 0) { return; }

        this.deleteSessionConfirmDialog.open().subscribe(doIt => {
            if (!doIt) { return; }

            const session_ids = rows.map(r => r.session_id );

            const that = this;
            function delete_next(ids: number[]) {
                const id = ids.pop();
                if (id) {
                    that.net.request(
                        'open-ils.url_verify',
                        'open-ils.url_verify.session.delete',
                        that.auth.token(),
                        id,
                    // eslint-disable-next-line rxjs-x/no-nested-subscribe
                    ).subscribe({
                        next: (res) => {
                            console.log('session.delete res', res);
                            // toast
                        },
                        error: (err: unknown) => {
                            console.log('session.delete err', err);
                            // toast
                        },
                        complete: () => {
                            console.log('session.delete finis');
                            delete_next(ids);
                        }
                    });
                } else {
                    setTimeout( () => { that.grid.reload(); } );
                }
            }

            delete_next(session_ids);

        });
    }

    initDataSource() {
        this.dataSource.getRows = (pager: Pager, sort: any[]) => {

            const query: any = {};

            if (this.searchOrgs || this.contextOrg) {
                query[this.viewOrgField] =
                    this.searchOrgs.orgIds || [this.contextOrg.id()];
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
}
