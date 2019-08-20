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
    @ViewChild('partsGrid') partsGrid: GridComponent;
    @ViewChild('editDialog') editDialog: FmRecordEditorComponent;
    @ViewChild('grid') grid: GridComponent;
    @ViewChild('successString') successString: StringComponent;
    @ViewChild('createString') createString: StringComponent;
    @ViewChild('createErrString') createErrString: StringComponent;
    @ViewChild('updateFailedString') updateFailedString: StringComponent;
    @ViewChild('cspFlairTooltip') private cspFlairTooltip: StringComponent;
    
    cspRowFlairCallback: (row: any) => GridRowFlairEntry;

    canCreate: boolean;
    canDelete: boolean;
    deleteSelected: (rows: IdlObject[]) => void;
    
    permissions: {[name: string]: boolean};

    // Default sort field, used when no grid sorting is applied.
    @Input() sortField: string;

    @Input() idlClass: string = "csp";
    // Size of create/edito dialog.  Uses large by default.
    @Input() dialogSize: 'sm' | 'lg' = 'lg';
    // Optional comma-separated list of read-only fields
    // @Input() readonlyFields: string;

    @Input() set recordId(id: number) {
        this.recId = id;
        // Only force new data collection when recordId()
        // is invoked after ngInit() has already run.
        if (this.initDone) {
            this.partsGrid.reload();
        }
    }

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
        }
        
        this.cspRowFlairCallback = (row: any): GridRowFlairEntry => {        
            const flair = {icon: null, title: null};
            if (row.id() < 100) {
                flair.icon = 'not_interested';
                flair.title = this.cspFlairTooltip.text;
            }
            return flair;
        }
    }

    cspReadonlyOverride = (field: string, copy: IdlObject): boolean => {
        if (copy.id() >= 100) {
            return true;
        }
        return false;
    }

    cspGridCellClassCallback = (row: any, col: GridColumn): string => {
        if (col.name === "id" && row.a[0] < 100) {
            return "text-danger";
        }
        return "";
    };

    showEditDialog(standingPenalty: IdlObject): Promise<any> {
        this.editDialog.mode = 'update';
        this.editDialog.recId = standingPenalty["id"]();
        return new Promise((resolve, reject) => {
            this.editDialog.open({size: this.dialogSize}).subscribe(
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
        this.editDialog.recId = null;
        this.editDialog.record = null;
        this.editDialog.open({size: this.dialogSize}).subscribe(
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

