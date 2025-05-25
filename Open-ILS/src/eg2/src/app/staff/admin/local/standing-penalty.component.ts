import {Pager} from '@eg/share/util/pager';
import {Component, OnInit, Input, ViewChild} from '@angular/core';
import {GridComponent} from '@eg/share/grid/grid.component';
import {GridDataSource, GridColumn, GridRowFlairEntry} from '@eg/share/grid/grid';
import {IdlObject} from '@eg/core/idl.service';
import {PcrudService} from '@eg/core/pcrud.service';
import {FmRecordEditorComponent} from '@eg/share/fm-editor/fm-editor.component';
import {StringComponent} from '@eg/share/string/string.component';
import {ToastService} from '@eg/share/toast/toast.service';

@Component({
    templateUrl: './standing-penalty.component.html'
})

export class StandingPenaltyComponent implements OnInit {
    recId: number;
    gridDataSource: GridDataSource;
    initDone = false;
    cspSource: GridDataSource = new GridDataSource();

    @ViewChild('editDialog', { static: true }) editDialog: FmRecordEditorComponent;
    @ViewChild('grid', { static: true }) grid: GridComponent;
    @ViewChild('successString', { static: true }) successString: StringComponent;
    @ViewChild('createString', { static: false }) createString: StringComponent;
    @ViewChild('createErrString', { static: false }) createErrString: StringComponent;
    @ViewChild('updateFailedString', { static: false }) updateFailedString: StringComponent;
    @ViewChild('deleteFailedString', { static: true }) deleteFailedString: StringComponent;
    @ViewChild('deleteSuccessString', { static: true }) deleteSuccessString: StringComponent;
    @ViewChild('cspFlairTooltip', { static: true }) private cspFlairTooltip: StringComponent;

    cspRowFlairCallback: (row: any) => GridRowFlairEntry;

    canCreate: boolean;
    canDelete: boolean;
    deleteSelected: (rows: IdlObject[]) => void;

    permissions: {[name: string]: boolean};

    // Default sort field, used when no grid sorting is applied.
    @Input() sortField: string;

    @Input() idlClass = 'csp';
    // Size of create/edito dialog.  Uses large by default.
    @Input() dialogSize: 'sm' | 'lg' = 'lg';
    // Optional comma-separated list of read-only fields
    // @Input() readonlyFields: string;

    constructor(
        private pcrud: PcrudService,
        private toast: ToastService
    ) {
        this.gridDataSource = new GridDataSource();
    }

    ngOnInit() {
        this.initDone = true;
        this.cspSource.getRows = (pager: Pager, sort: any[]) => {
            const orderBy: any = {};
            if (sort.length) {
                // Sort specified from grid
                orderBy[this.idlClass] = sort[0].name + ' ' + sort[0].dir;
            } else if (this.sortField) {
                // Default sort field
                orderBy[this.idlClass] = this.sortField;
            }

            const searchOps = {
                offset: pager.offset,
                limit: pager.limit,
                order_by: orderBy
            };
            return this.pcrud.retrieveAll('csp', searchOps, {fleshSelectors: true});
        };

        this.cspRowFlairCallback = (row: any): GridRowFlairEntry => {
            const flair = {icon: null, title: null};
            if (row.id() < 100) {
                flair.icon = 'not_interested';
                flair.title = this.cspFlairTooltip.text;
            }
            return flair;
        };

        this.deleteSelected = (idlThings: IdlObject[]) => {
            idlThings.forEach(idlThing => idlThing.isdeleted(true));
            this.pcrud.autoApply(idlThings).subscribe(
                { next: val => {
                    console.debug('deleted: ' + val);
                    this.deleteSuccessString.current()
                        .then(str => this.toast.success(str));
                }, error: (err: unknown) => {
                    this.deleteFailedString.current()
                        .then(str => this.toast.danger(str));
                }, complete: ()  => this.grid.reload() }
            );
        };

        this.grid.onRowActivate.subscribe(
            (idlThing: IdlObject) => this.showEditDialog(idlThing)
        );

    }

    cspReadonlyOverride = (field: string, csp: IdlObject): boolean => {
        if (csp.id() >= 100 || csp.id() === undefined) {
            return true;
        }
        return false;
    };

    cspGridCellClassCallback = (row: any, col: GridColumn): string => {
        if (col.name === 'id' && row.a[0] < 100) {
            return 'text-danger';
        }
        return '';
    };

    showEditDialog(standingPenalty: IdlObject): Promise<any> {
        this.editDialog.mode = 'update';
        this.editDialog.recordId = standingPenalty['id']();
        return new Promise((resolve, reject) => {
            this.editDialog.open({size: this.dialogSize}).subscribe(
                { next: result => {
                    this.successString.current()
                        .then(str => this.toast.success(str));
                    this.grid.reload();
                    resolve(result);
                }, error: (error: unknown) => {
                    this.updateFailedString.current()
                        .then(str => this.toast.danger(str));
                    reject(error);
                } }
            );
        });
    }

    editSelected(standingPenaltyFields: IdlObject[]) {
        // Edit each IDL thing one at a time
        const editOneThing = (standingPenalty: IdlObject) => {
            if (!standingPenalty) { return; }

            this.showEditDialog(standingPenalty).then(
                () => editOneThing(standingPenaltyFields.shift()));
        };

        editOneThing(standingPenaltyFields.shift());
    }

    createNew() {
        this.editDialog.mode = 'create';
        // We reuse the same editor for all actions.  Be sure
        // create action does not try to modify an existing record.
        this.editDialog.recordId = null;
        this.editDialog.record = null;
        this.editDialog.open({size: this.dialogSize}).subscribe(
            { next: ok => {
                this.createString.current()
                    .then(str => this.toast.success(str));
                this.grid.reload();
            }, error: (rejection: any) => {
                if (!rejection.dismissed) {
                    this.createErrString.current()
                        .then(str => this.toast.danger(str));
                }
            } }
        );
    }

}

