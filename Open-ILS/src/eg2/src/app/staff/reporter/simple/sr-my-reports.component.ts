import {Component, OnInit, ViewChild} from '@angular/core';
import {Router, ActivatedRoute} from '@angular/router';
import {map, concatMap, from} from 'rxjs';
import {AuthService} from '@eg/core/auth.service';
import {IdlService} from '@eg/core/idl.service';
import {PcrudService} from '@eg/core/pcrud.service';
import {GridComponent} from '@eg/share/grid/grid.component';
import {GridDataSource, GridCellTextGenerator} from '@eg/share/grid/grid';
import {ReporterService, SRTemplate} from '../share/reporter.service';
import {StringComponent} from '@eg/share/string/string.component';
import {ToastService} from '@eg/share/toast/toast.service';
import {ConfirmDialogComponent} from '@eg/share/dialog/confirm.component';
import {PromptDialogComponent} from '@eg/share/dialog/prompt.component';
import {NetService} from '@eg/core/net.service';

@Component({
    selector: 'eg-sr-reports',
    templateUrl: 'sr-my-reports.component.html',
})

export class SRReportsComponent implements OnInit {

    gridSource: GridDataSource;
    editSelected: ($event: any) => void;
    newReport: ($event: any) => void;
    @ViewChild('srReportsGrid', { static: true }) reportsGrid: GridComponent;
    @ViewChild('confirmDelete', { static: true }) deleteDialog: ConfirmDialogComponent;
    @ViewChild('promptClone', { static: true }) cloneDialog: PromptDialogComponent;
    @ViewChild('delete', { static: true} ) deleteString: StringComponent;
    @ViewChild('clone', { static: true} ) cloneString: StringComponent;
    @ViewChild('deleteSuccess', { static: true} ) deleteSuccessString: StringComponent;
    @ViewChild('deleteFailure', { static: true} ) deleteFailureString: StringComponent;
    @ViewChild('mixedResults', { static: true} ) mixedResultsString: StringComponent;
    @ViewChild('templateSaved', { static: true }) templateSavedString: StringComponent;
    @ViewChild('templateSaveError', { static: true }) templateSaveErrorString: StringComponent;


    cellTextGenerator: GridCellTextGenerator;

    constructor(
        private router: Router,
        private route: ActivatedRoute,
        private auth: AuthService,
        private pcrud: PcrudService,
        private idl: IdlService,
        private srSvc: ReporterService,
        private toast: ToastService,
        private net: NetService
    ) {
    }

    ngOnInit() {
        this.gridSource = this.srSvc.getSReportsDatasource();

        this.editSelected = ($event) => {
            this.router.navigate(['edit', $event[0].rt_id], { relativeTo: this.route });
        };

        this.newReport = ($event) => {
            this.router.navigate(['new'], { relativeTo: this.route });
        };
    }

    zeroSelectedRows(rows: any) {
        return rows.length === 0;
    }

    notOneSelectedRow(rows: any) {
        return rows.length !== 1;
    }

    deleteSelected(rows: any) {
        if ( rows.length <= 0 ) { return; }

        let successes = 0;
        let failures = 0;

        this.deleteString.current({ct: rows.length})
            .then(str => {
                this.deleteDialog.dialogBody = str;
                this.deleteDialog.open()
                    .subscribe(confirmed => {
                        if ( confirmed ) {
                            from(rows.map(x => x.rt_id)).pipe(concatMap(rt_id =>
                                this.net.request(
                                    'open-ils.reporter',
                                    'open-ils.reporter.template.delete.cascade',
                                    this.auth.token(),
                                    rt_id
                                ).pipe(map(res => ({
                                    result: res,
                                    rt_id: rt_id
                                })))
                            // eslint-disable-next-line rxjs-x/no-nested-subscribe
                            )).subscribe(
                                { next: (res) => {
                                    if (Number(res.result) === 2) {
                                        successes++;
                                    } else {
                                        failures++;
                                    }
                                }, error: (err: unknown) => {}, complete: () => {
                                    if (successes === rows.length) {
                                        this.deleteSuccessString.current({ct: successes}).then(str2 => { this.toast.success(str2); });
                                    } else if (failures && !successes) {
                                        this.deleteFailureString.current({ct: failures}).then(str2 => { this.toast.danger(str2); });
                                    } else {
                                        this.mixedResultsString.current({fail: failures, success: successes})
                                            .then(str2 => { this.toast.warning(str2); });
                                    }
                                    this.reportsGrid.reload();
                                } }
                            );
                        }
                    });
            });
    }

    cloneSelected(row: any) {
        if ( row.length <= 0 ) { return; }
        if ( row.length > 1 ) { return; }

        const rt_row = row[0];

        this.cloneString.current({old: rt_row.name})
            .then(str => {
                this.cloneDialog.dialogBody = str;
                this.cloneDialog.promptValue = rt_row.name + ' (Clone)';
                this.cloneDialog.open()
                    .subscribe(new_name => {
                        if ( new_name ) {
                            this.srSvc.loadTemplate(rt_row.rt_id)
                                .then(idl => {
                                    // build a new clone
                                    const new_templ = new SRTemplate(idl);
                                    new_templ.name = new_name;
                                    new_templ.id = -1;
                                    new_templ.isNew = true;
                                    new_templ.create_time = null;
                                    new_templ.runNow = 'now';
                                    new_templ.runTime = null;

                                    // and save it
                                    this.srSvc.saveTemplate(new_templ, false)
                                        .then(rt => {
                                            this.router.navigate(['edit', rt.id()], { relativeTo: this.route });
                                        },
                                        err => {
                                            this.templateSaveErrorString.current()
                                                .then(errstr => {
                                                    this.toast.danger(errstr + err);
                                                    console.error('Error saving template: %o', err);
                                                });
                                        });

                                });
                        }
                    });
            });
    }

}
