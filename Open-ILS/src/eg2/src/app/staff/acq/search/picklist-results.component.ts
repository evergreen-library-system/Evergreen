import {Component, OnInit, Input, ViewChild} from '@angular/core';
import {Router, ActivatedRoute} from '@angular/router';
import {ToastService} from '@eg/share/toast/toast.service';
import {StringComponent} from '@eg/share/string/string.component';
import {IdlObject} from '@eg/core/idl.service';
import {NetService} from '@eg/core/net.service';
import {AuthService} from '@eg/core/auth.service';
import {PermService} from '@eg/core/perm.service';
import {GridComponent} from '@eg/share/grid/grid.component';
import {GridDataSource, GridCellTextGenerator} from '@eg/share/grid/grid';
import {AcqSearchService, AcqSearchTerm, AcqSearch} from './acq-search.service';
import {PicklistCreateDialogComponent} from './picklist-create-dialog.component';
import {PicklistCloneDialogComponent} from './picklist-clone-dialog.component';
import {PicklistDeleteDialogComponent} from './picklist-delete-dialog.component';
import {PicklistMergeDialogComponent} from './picklist-merge-dialog.component';
import {AcqSearchFormComponent} from './acq-search-form.component';

@Component({
    selector: 'eg-picklist-results',
    templateUrl: 'picklist-results.component.html'
})
export class PicklistResultsComponent implements OnInit {

    @Input() initialSearchTerms: AcqSearchTerm[] = [];

    gridSource: GridDataSource;
    @ViewChild('acqSearchForm', { static: true}) acqSearchForm: AcqSearchFormComponent;
    @ViewChild('acqSearchPicklistsGrid', { static: true }) picklistResultsGrid: GridComponent;
    @ViewChild('picklistCreateDialog', { static: true }) picklistCreateDialog: PicklistCreateDialogComponent;
    @ViewChild('picklistCloneDialog', { static: true }) picklistCloneDialog: PicklistCloneDialogComponent;
    @ViewChild('picklistDeleteDialog', { static: true }) picklistDeleteDialog: PicklistDeleteDialogComponent;
    @ViewChild('picklistMergeDialog', { static: true }) picklistMergeDialog: PicklistMergeDialogComponent;
    @ViewChild('createSelectionListString', { static: true }) createSelectionListString: StringComponent;
    @ViewChild('cloneSelectionListString', { static: true }) cloneSelectionListString: StringComponent;
    @ViewChild('deleteSelectionListString', { static: true }) deleteSelectionListString: StringComponent;
    @ViewChild('mergeSelectionListString', { static: true }) mergeSelectionListString: StringComponent;

    permissions: {[name: string]: boolean};
    noSelectedRows: (rows: IdlObject[]) => boolean;
    oneSelectedRows: (rows: IdlObject[]) => boolean;
    createNotAppropriate: () => boolean;
    cloneNotAppropriate: (rows: IdlObject[]) => boolean;
    mergeNotAppropriate: (rows: IdlObject[]) => boolean;
    deleteNotAppropriate: (rows: IdlObject[]) => boolean;

    cellTextGenerator: GridCellTextGenerator;

    fallbackSearchTerms: AcqSearchTerm[] = [{
        field:  'acqpl:owner',
        op:     '',
        value1: this.auth.user() ? this.auth.user().id() : '',
        value2: ''
    }];

    constructor(
        private router: Router,
        private route: ActivatedRoute,
        private toast: ToastService,
        private net: NetService,
        private auth: AuthService,
        private acqSearch: AcqSearchService,
        private perm: PermService
    ) {
        this.permissions = {};
    }

    ngOnInit() {
        this.gridSource = this.acqSearch.getAcqSearchDataSource('picklist');

        this.perm.hasWorkPermHere(['CREATE_PICKLIST', 'UPDATE_PICKLIST', 'VIEW_PICKLIST']).
            then(perms => this.permissions = perms);

        this.noSelectedRows = (rows: IdlObject[]) => (rows.length === 0);
        this.oneSelectedRows = (rows: IdlObject[]) => (rows.length === 1);
        this.createNotAppropriate = () => (!this.permissions.CREATE_PICKLIST);
        this.cloneNotAppropriate = (rows: IdlObject[]) => (!this.permissions.CREATE_PICKLIST || !this.oneSelectedRows(rows));
        this.mergeNotAppropriate = (rows: IdlObject[]) => (!this.permissions.UPDATE_PICKLIST || this.noSelectedRows(rows));
        this.deleteNotAppropriate = (rows: IdlObject[]) => (!this.permissions.UPDATE_PICKLIST || this.noSelectedRows(rows));

        this.cellTextGenerator = {
            name: row => row.name(),
        };
    }

    openCreateDialog() {
        this.picklistCreateDialog.open().subscribe(
            modified => {
                if (!modified) { return; }
                this.createSelectionListString.current().then(msg => this.toast.success(msg));
                this.picklistResultsGrid.reload(); // FIXME - spec calls for inserted grid row and not refresh
            }
        );
        this.picklistCreateDialog.update(); // clear and focus the textbox
    }

    openCloneDialog(rows: IdlObject[]) {
        this.picklistCloneDialog.open().subscribe(
            modified => {
                if (!modified) { return; }
                this.cloneSelectionListString.current().then(msg => this.toast.success(msg));
                this.picklistResultsGrid.reload(); // FIXME - spec calls for inserted grid row and not refresh
            }
        );
        this.picklistCloneDialog.update(); // update the dialog UI with selections
    }

    openDeleteDialog(rows: IdlObject[]) {
        this.picklistDeleteDialog.open().subscribe(
            modified => {
                if (!modified) { return; }
                this.deleteSelectionListString.current().then(msg => this.toast.success(msg));
                this.picklistResultsGrid.reload(); // FIXME - spec calls for removed grid rows and not refresh
            }
        );
        this.picklistDeleteDialog.update(); // update the dialog UI with selections
    }

    openMergeDialog(rows: IdlObject[]) {
        this.picklistMergeDialog.open().subscribe(
            modified => {
                if (!modified) { return; }
                this.mergeSelectionListString.current().then(msg => this.toast.success(msg));
                this.picklistResultsGrid.reload(); // FIXME - spec calls for removed grid rows and not refresh
            }
        );
        this.picklistMergeDialog.update(); // update the dialog UI with selections
    }

    showRow(row: any) {
        window.open('/eg2/staff/acq/picklist/' + row.id(), '_blank');
    }

    doSearch(search: AcqSearch) {
        setTimeout(() => {
            this.acqSearch.setSearch(search);
            this.picklistResultsGrid.reload();
        });
    }
}
