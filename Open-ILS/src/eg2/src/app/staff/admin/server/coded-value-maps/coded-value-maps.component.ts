import {Pager} from '@eg/share/util/pager';
import {Component, ViewChild, OnInit} from '@angular/core';
import {IdlObject} from '@eg/core/idl.service';
import {GridDataSource} from '@eg/share/grid/grid';
import {GridComponent} from '@eg/share/grid/grid.component';
import {ToastService} from '@eg/share/toast/toast.service';
import {PcrudService} from '@eg/core/pcrud.service';
import {FmRecordEditorComponent} from '@eg/share/fm-editor/fm-editor.component';
import {StringComponent} from '@eg/share/string/string.component';

@Component({
    templateUrl: './coded-value-maps.component.html'
})

export class CodedValueMapsComponent implements OnInit {

    gridDataSource: GridDataSource = new GridDataSource();
    @ViewChild('createString', { static: true }) createString: StringComponent;
    @ViewChild('createErrString', { static: true }) createErrString: StringComponent;
    @ViewChild('updateSuccessString', { static: true }) updateSuccessString: StringComponent;
    @ViewChild('updateFailedString', { static: true }) updateFailedString: StringComponent;
    @ViewChild('deleteFailedString', { static: true }) deleteFailedString: StringComponent;
    @ViewChild('deleteSuccessString', { static: true }) deleteSuccessString: StringComponent;

    @ViewChild('grid', {static: true}) grid: GridComponent;
    @ViewChild('editDialog', { static: true }) editDialog: FmRecordEditorComponent;

    constructor(
        private pcrud: PcrudService,
        private toast: ToastService,
    ) {
    }

    ngOnInit() {
        this.gridDataSource.getRows = (pager: Pager, sort: any[]) => {
            return this.pcrud.retrieveAll('ccvm', {order_by: {ccvm: 'id'}}, {fleshSelectors: true});
        };
        this.grid.onRowActivate.subscribe(
            (idlThing: IdlObject) => this.showEditDialog(idlThing)
        );
    }

    showEditDialog(standingPenalty: IdlObject): Promise<any> {
        this.editDialog.mode = 'update';
        this.editDialog.recordId = standingPenalty['id']();
        return new Promise((resolve, reject) => {
            this.editDialog.open({size: 'lg'}).subscribe(
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

    editSelected = (maps: IdlObject[]) => {
        const editOneThing = (map: IdlObject) => {
            this.showEditDialog(map).then(
                () => editOneThing(maps.shift()));
        };
        editOneThing(maps.shift());
    }

    deleteSelected = (idlThings: IdlObject[]) => {
        idlThings.forEach(idlThing => idlThing.isdeleted(true));
        this.pcrud.autoApply(idlThings).subscribe(
            val => {
                console.debug('deleted: ' + val);
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

    createNew = () => {
        this.editDialog.mode = 'create';
        this.editDialog.recordId = null;
        this.editDialog.record = null;
        this.editDialog.open({size: 'lg'}).subscribe(
            ok => {
                this.createString.current()
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

 }
