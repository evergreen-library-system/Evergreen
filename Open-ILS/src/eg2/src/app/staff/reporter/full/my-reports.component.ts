/* eslint-disable */
import {Component, Input, OnInit, ViewChild} from '@angular/core';
import {Router, ActivatedRoute} from '@angular/router';
import {map, concatMap} from 'rxjs/operators';
import {from} from 'rxjs';
import {AuthService} from '@eg/core/auth.service';
import {IdlObject, IdlService} from '@eg/core/idl.service';
import {PcrudService} from '@eg/core/pcrud.service';
import {Pager} from '@eg/share/util/pager';
import {GridComponent} from '@eg/share/grid/grid.component';
import {GridDataSource, GridCellTextGenerator} from '@eg/share/grid/grid';
import {ReporterService, SRTemplate} from '../share/reporter.service';
import {StringComponent} from '@eg/share/string/string.component';
import {ToastService} from '@eg/share/toast/toast.service';
import {ConfirmDialogComponent} from '@eg/share/dialog/confirm.component';
import {PromptDialogComponent} from '@eg/share/dialog/prompt.component';
import {FolderShareOrgDialogComponent} from './folder-share-org-dialog.component';
import {ChangeFolderDialogComponent} from './change-folder-dialog.component';
import {NetService} from '@eg/core/net.service';

@Component({
    selector: 'eg-reporter-reports',
    templateUrl: 'my-reports.component.html',
    styleUrls: ['./my-reports.component.css'],
})

export class ReportReportsComponent implements OnInit {

    @Input() currentFolder: IdlObject = null;
    @Input() searchTemplate: IdlObject = null;

    gridSource: GridDataSource;
    @ViewChild('ReportsGrid', { static: true }) reportsGrid: GridComponent;
    @ViewChild('confirmDelete', { static: true }) deleteDialog: ConfirmDialogComponent;
    @ViewChild('confirmDeleteFolder', { static: true }) deleteFolderConfirm: ConfirmDialogComponent;
    @ViewChild('promptClone', { static: true }) cloneDialog: PromptDialogComponent;
    @ViewChild('promptRename', { static: true }) renameDialog: PromptDialogComponent;
	@ViewChild('promptNewSubfolder', { static: true }) newSubfolderDialog: PromptDialogComponent;
	@ViewChild('promptShareOrg', { static: true }) shareOrgDialog: FolderShareOrgDialogComponent;
    @ViewChild('promptChangeFolder', { static: true }) changeFolderDialog: ChangeFolderDialogComponent;

    @ViewChild('delete', { static: true} ) deleteString: StringComponent;
    @ViewChild('clone', { static: true} ) cloneString: StringComponent;
    @ViewChild('rename', { static: true} ) renameString: StringComponent;
	@ViewChild('newSF', { static: true} ) newSubfolderString: StringComponent;
    @ViewChild('deleteSuccess', { static: true} ) deleteSuccessString: StringComponent;
    @ViewChild('deleteFailure', { static: true} ) deleteFailureString: StringComponent;
    @ViewChild('mixedResults', { static: true} ) mixedResultsString: StringComponent;
    @ViewChild('reportSaved', { static: true }) reportSavedString: StringComponent;
    @ViewChild('reportSaveError', { static: true }) reportSaveErrorString: StringComponent;


    cellTextGenerator: GridCellTextGenerator;

    constructor(
        private router: Router,
        private route: ActivatedRoute,
        private auth: AuthService,
        private pcrud: PcrudService,
        private idl: IdlService,
        public RSvc: ReporterService,
        private toast: ToastService,
        private net: NetService
    ) {
    }

    ngOnInit() {
        this.gridSource = this.RSvc.getReportsDatasource(this.currentFolder ?? this.searchTemplate);
    }

    outputsForReport(rows) {
        this.RSvc.selectedReport = rows[0]._rr;
        this.RSvc.currentFolderType = 'rof-from-rr';
    }

    newReport(rows) {
        const path = ['define', 'new', rows[0].rt_id];

        if (this.currentFolder) {
            path.push(this.currentFolder.id());
        }

        this.router.navigate(path, { relativeTo: this.route });
    }

    renameFolder($event) {
        this.renameString.current({old: this.currentFolder.name()})
            .then(str => {
                this.renameDialog.dialogBody = str;
                this.renameDialog.promptValue = this.currentFolder.name();
                this.renameDialog.open().subscribe(new_name => {
                    if ( new_name ) {
                        this.RSvc.renameReportFolder(new_name);
                    }
                });
            });
    }

    newSubfolder($event) {
        this.newSubfolderString.current({old: this.currentFolder.name()})
            .then(str => {
                this.newSubfolderDialog.dialogBody = str;
                this.newSubfolderDialog.promptValue = this.RSvc.lastNewFolderName || this.currentFolder.name();
                this.newSubfolderDialog.open().subscribe( new_name => {
                    if ( new_name ) {
                        this.RSvc.newSubfolder(new_name, this.currentFolder);
                    }
                });
            });
    }

    moveSelected(rows) {
        return this.changeFolderDialog.open().subscribe( new_folder => {
            if ( new_folder ) {
                const t_objs = rows.map(r => r._rr);
                this.RSvc.updateContainingFolder(t_objs, new_folder).subscribe(
                    _ => {},
                    (e: unknown) => {},
                    () => this.reportsGrid.reload()
                );
            }
        });
    }

    deleteFolder($event) {
        return this.deleteFolderConfirm.open().subscribe( c => {
            if (c) {
                this.RSvc.deleteFolder(this.currentFolder);
                this.currentFolder = null;
                this.RSvc.currentFolderType = null;
            }
        });
    }

    shareFolder($event) {
        return this.shareOrgDialog.open().subscribe( org => {
            if ( org ) {
            	this.RSvc.shareFolder(this.currentFolder, org);
        	}
        });
    }

    unshareFolder($event) {
        return this.RSvc.unshareFolder(this.currentFolder);
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
                            from(rows.map(x => x.rr_id)).pipe(concatMap(rr_id =>
                                this.net.request(
                                    'open-ils.reporter',
                                    'open-ils.reporter.report.delete.cascade',
                                    this.auth.token(),
                                    rr_id
                                ).pipe(map(res => ({
                                    result: res,
                                    rr_id: rr_id
                                })))
                            )).subscribe(
                                (res) => {
                                    if (Number(res.result) === 2) {
                                        successes++;
                                    } else {
                                        failures++;
                                    }
                                },
                                (err: unknown) => {},
                                () => {
                                    if (successes === rows.length) {
                                        this.deleteSuccessString.current({ct: successes}).then(str2 => { this.toast.success(str2); });
                                    } else if (failures && !successes) {
                                        this.deleteFailureString.current({ct: failures}).then(str2 => { this.toast.danger(str2); });
                                    } else {
                                        this.mixedResultsString.current({fail: failures, success: successes})
                                            .then(str2 => { this.toast.warning(str2); });
                                    }
                                    this.reportsGrid.reload();
                                }
                            );
                        }
                    });
            });
    }

    openSelected(type, id) {
        return this.router.navigate(['define',type, id], { relativeTo: this.route });
    }

    cloneSelected(rows) {
        return this.openSelected('clone',rows[0].rr_id);
    }

    viewSelected(rows) {
        return this.openSelected('view',rows[0].rr_id);
    }

    editSelected(rows) {
        return this.openSelected('edit',rows[0].rr_id);
    }

}
