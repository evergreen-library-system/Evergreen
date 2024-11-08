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
    selector: 'eg-reporter-templates',
    templateUrl: 'my-templates.component.html',
    styleUrls: ['./my-templates.component.css'],
})

export class ReportTemplatesComponent implements OnInit {

	@Input() currentFolder: IdlObject = null;
	@Input() searchFolder: IdlObject = null;
	@Input() searchString = '';
	@Input() searchField = '';

	gridSource: GridDataSource;
    @ViewChild('TemplatesGrid', { static: true }) templatesGrid: GridComponent;
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
    @ViewChild('templateSaved', { static: true }) templateSavedString: StringComponent;
    @ViewChild('templateSaveError', { static: true }) templateSaveErrorString: StringComponent;


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
        if (this.currentFolder) {
            this.gridSource = this.RSvc.getTemplatesDatasource();
        } else {
            this.gridSource = this.RSvc.getTemplatesSearchDatasource(
                this.searchString,
                this.searchField,
                this.searchFolder
            );
        }

    }

    editSelected($event) {
        const path = ['edit',$event[0].rt_id];

        if (this.currentFolder) {
            path.push(this.currentFolder.id());
        }

        this.router.navigate(path, { relativeTo: this.route });
    }

    cloneSelected(rows: any) {
        if ( rows.length <= 0 || rows.length > 1 ) { return; }
        this.router.navigate(['clone', rows[0].rt_id], { relativeTo: this.route });
    }

    newTemplate($event) {
        const path = ['new'];

        if (this.currentFolder) {
            path.push(this.currentFolder.id());
        }

        this.router.navigate(path, { relativeTo: this.route });
    }

    reportsForTemplate(rows) {
        this.RSvc.selectedTemplate = rows[0]._rt;
        this.RSvc.currentFolderType = 'rrf-from-rt';
    }

    newReport(rows) {
        this.router.navigate(['define', 'new', rows[0].rt_id], { relativeTo: this.route });
    }

    renameFolder($event) {
        this.renameString.current({old: this.currentFolder.name()})
            .then(str => {
                this.renameDialog.dialogBody = str;
                this.renameDialog.promptValue = this.currentFolder.name();
                this.renameDialog.open().subscribe(
                    new_name => {
	                if ( new_name ) {
    	                this.RSvc.renameTemplateFolder(new_name);
        	        }
            	},
                    (e: unknown) => {},
                    () => this.templatesGrid.reload()
                );
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

    deleteFolder($event) {
        return this.deleteFolderConfirm.open().subscribe( c => {
            if (c) {
                this.RSvc.deleteFolder(this.currentFolder);
                this.currentFolder = null;
                this.RSvc.currentFolderType = null;
            }
        });
    }

    shareFolder(clickedButtonComponent) {
        return this.shareOrgDialog.open().subscribe( org => {
            if ( org ) {
   	           this.RSvc.shareFolder(this.currentFolder, org);
               // Need to remove the old button from the grid context to not display it twice
               this.templatesGrid.context.toolbarButtons = this.templatesGrid.context.toolbarButtons.filter(button => button != clickedButtonComponent.button);
            }
      	});
    }

    moveSelected(rows) {
        return this.changeFolderDialog.open().subscribe( new_folder => {
            if ( new_folder ) {
                const t_objs = rows.map(r => r._rt);
   	            this.RSvc.updateContainingFolder(t_objs, new_folder).subscribe(
                    _ => {},
                    (e: unknown) => {},
                    () => this.templatesGrid.reload()
                );
            }
      	});
    }

    unshareFolder(clickedButtonComponent) {
        // Need to remove the old button from the grid context to not display it twice
        this.templatesGrid.context.toolbarButtons = this.templatesGrid.context.toolbarButtons.filter(button => button != clickedButtonComponent.button);
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
                                    this.templatesGrid.reload();
                                }
                            );
                        }
                    });
            });
    }

}
