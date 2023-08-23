import {Component, OnInit, ViewChild, Input} from '@angular/core';
import {Router, ActivatedRoute} from '@angular/router';
import {AuthService} from '@eg/core/auth.service';
import {IdlObject, IdlService} from '@eg/core/idl.service';
import {PcrudService} from '@eg/core/pcrud.service';
import {StringComponent} from '@eg/share/string/string.component';
import {ToastService} from '@eg/share/toast/toast.service';
import {ConfirmDialogComponent} from '@eg/share/dialog/confirm.component';
import {Pager} from '@eg/share/util/pager';
import {GridComponent} from '@eg/share/grid/grid.component';
import {GridDataSource, GridCellTextGenerator} from '@eg/share/grid/grid';
import {ReporterService} from '../share/reporter.service';
import {PromptDialogComponent} from '@eg/share/dialog/prompt.component';
import {FolderShareOrgDialogComponent} from './folder-share-org-dialog.component';
import {ChangeFolderDialogComponent} from './change-folder-dialog.component';

@Component({
    selector: 'eg-reporter-outputs',
    templateUrl: 'my-outputs.component.html',
})

export class FullReporterOutputsComponent implements OnInit {

    @Input() currentFolder: IdlObject = null;
    @Input() searchReport: IdlObject = null;

    pendingGridSource: GridDataSource;
    completeGridSource: GridDataSource;

    @ViewChild('PendingOutputsGrid', { static: true }) pendingOutputsGrid: GridComponent;
    @ViewChild('CompleteOutputsGrid', { static: true }) completeOutputsGrid: GridComponent;
    @ViewChild('confirmDelete', { static: false }) confirmDeleteDialog: ConfirmDialogComponent;
    @ViewChild('confirmDeleteFolder', { static: true }) deleteFolderConfirm: ConfirmDialogComponent;
	@ViewChild('promptRename', { static: true }) renameDialog: PromptDialogComponent;
    @ViewChild('promptNewSubfolder', { static: true }) newSubfolderDialog: PromptDialogComponent;
    @ViewChild('promptChangeFolder', { static: true }) changeFolderDialog: ChangeFolderDialogComponent;

    @ViewChild('rename', { static: true} ) renameString: StringComponent;
    @ViewChild('newSF', { static: true} ) newSubfolderString: StringComponent;
    @ViewChild('deleted', { static: true} ) deletedString: StringComponent;
    @ViewChild('delete', { static: true} ) confirmDeleteString: StringComponent;
    @ViewChild('promptShareOrg', { static: true }) shareOrgDialog: FolderShareOrgDialogComponent;

    cellTextGenerator: GridCellTextGenerator;

    constructor(
        private router: Router,
        private route: ActivatedRoute,
        private auth: AuthService,
        private pcrud: PcrudService,
        private idl: IdlService,
        private toast: ToastService,
        public RSvc: ReporterService,
    ) {
        // These values are all replaced via custom templates and cause warnings if not specified here.
        this.cellTextGenerator = {
            _output: row => ''
        };

    }

    ngOnInit() {
        this.pendingGridSource = this.RSvc.getPendingOutputDatasource(this.searchReport);
        this.completeGridSource = this.RSvc.getCompleteOutputDatasource(this.searchReport);

    }

    // Expects an rt object with fleshed report to grab the template id.
    outputPath(row: any, file: string) {
        return `/reporter/${row.template_id}/${row.report_id}/${row.id}/${file}`;
    }

    goToOutput(rows) {
       window.open(this.outputPath(rows[0], 'report-data.html'), '_blank');
    }

    zeroSelectedRows(rows: any) {
        return rows.length === 0;
    }

    notOneSelectedRow(rows: any) {
        return rows.length !== 1;
    }

    deleteFolder() {
       return this.deleteFolderConfirm.open().subscribe( c => {
            if (c) {
                this.RSvc.deleteFolder(this.currentFolder);
                this.currentFolder = null;
                this.RSvc.currentFolderType = null;
            }
        });
    }

    moveSelected(rows) {
        return this.changeFolderDialog.open().subscribe( new_folder => {
            if ( new_folder ) {
                let t_objs = rows.map(r => r._rs);
                this.RSvc.updateContainingFolder(t_objs, new_folder).subscribe(
                    _ => {},
                    e => {},
                    () => this.refreshGridsFromOutputs(t_objs)
                );
            }
        });
    }

    renameFolder($event) {
        this.renameString.current({old: this.currentFolder.name()})
        .then(str => {
            this.renameDialog.dialogBody = str;
            this.renameDialog.promptValue = this.currentFolder.name();
            this.renameDialog.open().subscribe(new_name => {
                if ( new_name ) {
                    this.RSvc.renameOutputFolder(new_name);
                }
            });
        })
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
        })
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

    deleteOutputs(rows: any[]) {
        if ( rows.length <= 0 ) { return; }
        this.confirmDeleteString.current({ num: rows.length })
        .then(str => {
            this.confirmDeleteDialog.dialogBody = str;
            this.confirmDeleteDialog.open()
            .subscribe(confirmed => {
                if ( confirmed ) { this.doDeleteOutputs(rows.map(x => x._rs)); }
            });
        });
    }

	refreshGridsFromOutputs(outs: IdlObject[]) {
        let gridsToRefresh = [];

        if (outs.filter(r => !!r.start_time()).length > 0) {
            gridsToRefresh.push(this.completeOutputsGrid);
        }

        if (outs.filter(r => !r.start_time()).length > 0) {
            gridsToRefresh.push(this.pendingOutputsGrid);
        }

        gridsToRefresh.forEach(g => g.reload());
	}

    doDeleteOutputs(outs: IdlObject[]) {
        this.pcrud.remove(outs).toPromise()
        .then(res => {
            this.deletedString.current({num: outs.length})
            .then(str => {
                this.toast.success(str);
				this.refreshGridsFromOutputs(outs);
            });
        });

    }

    refreshBothGrids() {
        this.pendingOutputsGrid.reload();
        this.completeOutputsGrid.reload();
    }

    refreshPendingGrid($event) {
        this.pendingOutputsGrid.reload();
    }

    refreshCompleteGrid($event) {
        this.completeOutputsGrid.reload();
    }

    cloneSelected(rows) {
        return this.router.navigate(['define','clone', rows[0].report_id], { relativeTo: this.route });
    }

}

