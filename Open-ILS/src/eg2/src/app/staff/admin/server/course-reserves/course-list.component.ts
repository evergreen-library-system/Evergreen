import {Component, Input, ViewChild, OnInit} from '@angular/core';
import {IdlObject} from '@eg/core/idl.service';
import {PcrudService} from '@eg/core/pcrud.service';
import {GridComponent} from '@eg/share/grid/grid.component';
import {Pager} from '@eg/share/util/pager';
import {GridDataSource, GridColumn, GridRowFlairEntry} from '@eg/share/grid/grid';
import {FmRecordEditorComponent} from '@eg/share/fm-editor/fm-editor.component';
import {StringComponent} from '@eg/share/string/string.component';
import {ToastService} from '@eg/share/toast/toast.service';

@Component({
    templateUrl: './course-list.component.html'
})

export class CourseListComponent implements OnInit { 
 
    @ViewChild('editDialog', { static: true }) editDialog: FmRecordEditorComponent;
    @ViewChild('grid', { static: true }) grid: GridComponent;
    @ViewChild('successString', { static: true }) successString: StringComponent;
    @ViewChild('createString', { static: false }) createString: StringComponent;
    @ViewChild('createErrString', { static: false }) createErrString: StringComponent;
    @ViewChild('updateFailedString', { static: false }) updateFailedString: StringComponent;
    @ViewChild('deleteFailedString', { static: true }) deleteFailedString: StringComponent;
    @ViewChild('deleteSuccessString', { static: true }) deleteSuccessString: StringComponent;
    @ViewChild('flairTooltip', { static: true }) private flairTooltip: StringComponent;
    rowFlairCallback: (row: any) => GridRowFlairEntry;
    @Input() sort_field: string;
    @Input() idl_class = "acmc";
    @Input() dialog_size: 'sm' | 'lg' = 'lg';
    @Input() table_name = "Course";
    grid_source: GridDataSource = new GridDataSource();
    search_value = '';

    constructor(
            private pcrud: PcrudService,
            private toast: ToastService,
    ){}

    ngOnInit() {
        this.getSource();
        this.rowFlair();
    }

    /**
     * Gets the data, specified by the class, that is available.
     */
    getSource() {
        this.grid_source.getRows = (pager: Pager, sort: any[]) => {
            const orderBy: any = {};
            if (sort.length) {
                // Sort specified from grid
                orderBy[this.idl_class] = sort[0].name + ' ' + sort[0].dir;
            } else if (this.sort_field) {
                // Default sort field
                orderBy[this.idl_class] = this.sort_field;
            }
            const searchOps = {
                offset: pager.offset,
                limit: pager.limit,
                order_by: orderBy
            };
            return this.pcrud.retrieveAll(this.idl_class, searchOps, {fleshSelectors: true});
        };
    }

    rowFlair() {
        this.rowFlairCallback = (row: any): GridRowFlairEntry => {
            const flair = {icon: null, title: null};
            if (row.id() < 100) {
                flair.icon = 'not_interested';
                flair.title = this.flairTooltip.text;
            }
            return flair;
        };
    }

    gridCellClassCallback = (row: any, col: GridColumn): string => {
        if (col.name === 'id' && row.a[0] < 100) {
            return 'text-danger';
        }
        return '';
    }

    showEditDialog(standingPenalty: IdlObject): Promise<any> {
        this.editDialog.mode = 'update';
        this.editDialog.recordId = standingPenalty['id']();
        return new Promise((resolve, reject) => {
            this.editDialog.open({size: this.dialog_size}).subscribe(
                result => {
                    this.successString.current()
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

    createNew() {
        this.editDialog.mode = 'create';
        this.editDialog.recordId = null;
        this.editDialog.record = null;
        this.editDialog.open({size: this.dialog_size}).subscribe(
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

    editSelected(fields: IdlObject[]) {
        // Edit each IDL thing one at a time
        const editOneThing = (field_object: IdlObject) => {
            if (!field_object) { return; }
            this.showEditDialog(field_object).then(
                () => editOneThing(fields.shift()));
        };
        editOneThing(fields.shift());
    }

    deleteSelected(idl_object: IdlObject[]) {
            idl_object.forEach(idl_object => idl_object.isdeleted(true));
            this.pcrud.autoApply(idl_object).subscribe(
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
        };
}

