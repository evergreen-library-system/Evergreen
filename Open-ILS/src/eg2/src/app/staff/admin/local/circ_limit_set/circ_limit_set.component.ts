import {Pager} from '@eg/share/util/pager';
import {Component, OnInit, Input, ViewChild} from '@angular/core';
import {GridComponent} from '@eg/share/grid/grid.component';
import {GridDataSource} from '@eg/share/grid/grid';
import {Router} from '@angular/router';
import {IdlObject} from '@eg/core/idl.service';
import {PcrudService} from '@eg/core/pcrud.service';
import {FmRecordEditorComponent} from '@eg/share/fm-editor/fm-editor.component';
import {StringComponent} from '@eg/share/string/string.component';
import {ToastService} from '@eg/share/toast/toast.service';

@Component({
    templateUrl: './circ_limit_set.component.html'
})

export class CircLimitSetComponent implements OnInit {

    recId: number;
    gridDataSource: GridDataSource;
    initDone = false;
    cspSource: GridDataSource = new GridDataSource();

    @ViewChild('editDialog', {static: true}) editDialog: FmRecordEditorComponent;
    @ViewChild('grid', {static: true}) grid: GridComponent;
    @ViewChild('updateSuccessString', {static: true}) updateSuccessString: StringComponent;
    @ViewChild('updateFailedString', {static: true}) updateFailedString: StringComponent;
    @ViewChild('deleteFailedString', {static: true}) deleteFailedString: StringComponent;
    @ViewChild('deleteSuccessString', {static: true}) deleteSuccessString: StringComponent;
    @ViewChild('createSuccessString', {static: true}) createSuccessString: StringComponent;
    @ViewChild('createErrString', {static: true}) createErrString: StringComponent;

    @Input() dialogSize: 'sm' | 'lg' = 'lg';

    constructor(
        private pcrud: PcrudService,
        private toast: ToastService,
        private router: Router
    ) {
        this.gridDataSource = new GridDataSource();
    }

    ngOnInit() {
        this.gridDataSource.getRows = (pager: Pager, sort: any[]) => {
            const orderBy: any = {};
            const searchOps = {
                offset: pager.offset,
                limit: pager.limit,
                order_by: orderBy
            };
            return this.pcrud.retrieveAll('ccls', searchOps, {fleshSelectors: true});
        };

        this.grid.onRowActivate.subscribe(
            (set: IdlObject) => {
                const idToEdit = set.id();
                this.navigateToEditPage(idToEdit);
            }
        );
    }

    deleteSelected = (idlThings: IdlObject[]) => {
        idlThings.forEach(idlThing => idlThing.isdeleted(true));
        this.pcrud.autoApply(idlThings).subscribe(
            val => {
                this.deleteSuccessString.current()
                    .then(str => this.toast.success(str));
            },
            err => {
                this.deleteFailedString.current()
                    .then(str => this.toast.danger(str));
            },
            ()  => this.grid.reload()
        );
    }

    editSelected(sets: IdlObject[]) {
        const idToEdit = sets[0].id();
        this.navigateToEditPage(idToEdit);
    }

    navigateToEditPage(id: any) {
        this.router.navigate(['/staff/admin/local/config/circ_limit_set/' + id]);
    }

    createNew() {
        this.editDialog.mode = 'create';
        this.editDialog.recordId = null;
        this.editDialog.record = null;
        this.editDialog.open({size: this.dialogSize}).subscribe(
            ok => {
                this.createSuccessString.current()
                    .then(str => this.toast.success(str));
                this.grid.reload();
            },
            rejection => {
                if (!rejection.dismissed) {
                    this.createErrString.current()
                        .then(str => this.toast.danger(str));
                }
            }
        );
    }

    showEditDialog(standingPenalty: IdlObject): Promise<any> {
        this.editDialog.mode = 'update';
        this.editDialog.recordId = standingPenalty['id']();
        return new Promise((resolve, reject) => {
            this.editDialog.open({size: this.dialogSize}).subscribe(
                result => {
                    this.updateSuccessString.current()
                        .then(str => this.toast.success(str));
                    this.grid.reload();
                    resolve(result);
                },
                error => {
                    this.updateFailedString.current()
                        .then(str => this.toast.danger(str));
                    reject(error);
                }
            );
        });
    }
}
