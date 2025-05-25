import {Component, OnInit, Input, ViewChild} from '@angular/core';
import {IdlService, IdlObject} from '@eg/core/idl.service';
import {PcrudService} from '@eg/core/pcrud.service';
import {Pager} from '@eg/share/util/pager';
import {OrgService} from '@eg/core/org.service';
import {AuthService} from '@eg/core/auth.service';
import {PermService} from '@eg/core/perm.service';
import {GridDataSource} from '@eg/share/grid/grid';
import {GridComponent} from '@eg/share/grid/grid.component';
import {FmRecordEditorComponent} from '@eg/share/fm-editor/fm-editor.component';
import {PartMergeDialogComponent} from './part-merge-dialog.component';

@Component({
    selector: 'eg-catalog-record-parts',
    templateUrl: 'parts.component.html'
})
export class PartsComponent implements OnInit {

    recId: number;
    gridDataSource: GridDataSource;
    initDone: boolean;
    @ViewChild('partsGrid', { static: true }) partsGrid: GridComponent;
    @ViewChild('editDialog', { static: true }) editDialog: FmRecordEditorComponent;
    @ViewChild('mergeDialog', { static: true }) mergeDialog: PartMergeDialogComponent;

    canCreate: boolean;
    canDelete: boolean;
    createNew: () => void;
    deleteSelected: (rows: IdlObject[]) => void;
    mergeSelected: (rows: IdlObject[]) => void;
    permissions: {[name: string]: boolean};

    @Input() set recordId(id: number) {
        this.recId = id;
        // Only force new data collection when recordId()
        // is invoked after ngInit() has already run.
        if (this.initDone) {
            this.partsGrid.reload();
        }
    }

    get recordId(): number {
        return this.recId;
    }

    constructor(
        private idl: IdlService,
        private org: OrgService,
        private pcrud: PcrudService,
        private auth: AuthService,
        private perm: PermService
    ) {
        this.permissions = {};
        this.gridDataSource = new GridDataSource();
    }

    ngOnInit() {
        this.initDone = true;

        // Load edit perms
        this.perm.hasWorkPermHere([
            'CREATE_MONOGRAPH_PART',
            'UPDATE_MONOGRAPH_PART',
            'DELETE_MONOGRAPH_PART',
            'UPDATE_HOLD'
        ]).then(perms => this.permissions = perms);

        this.gridDataSource.getRows = (pager: Pager, sort: any[]) => {
            const orderBy: any = {};

            if (sort.length) { // Sort provided by grid.
                // Labels sort by label_sortkey instead of label
                const sort_name = sort[0].name === 'label' ? 'label_sortkey' : sort[0].name;
                orderBy.bmp = sort_name + ' ' + sort[0].dir;
            } else {
                orderBy.bmp = 'label_sortkey';
            }

            const searchOps = {
                offset: pager.offset,
                limit: pager.limit,
                order_by: orderBy,
                flesh: 2,
                flesh_fields: {
                    bmp: ['creator','editor']
                }
            };

            return this.pcrud.search('bmp',
                {record: this.recId, deleted: 'f'}, searchOps);
        };

        this.partsGrid.onRowActivate.subscribe(
            (part: IdlObject) => {
                part.editor(this.auth.user().id());
                part.edit_date('now');
                this.editDialog.mode = 'update';
                this.editDialog.record = part;
                this.editDialog.open()
                    // eslint-disable-next-line rxjs-x/no-nested-subscribe
                    .subscribe(ok => this.partsGrid.reload());
            }
        );

        this.createNew = () => {

            const part = this.idl.create('bmp');
            part.record(this.recordId);
            part.creator(this.auth.user().id());
            part.editor(this.auth.user().id());
            this.editDialog.record = part;

            this.editDialog.mode = 'create';
            this.editDialog.open().subscribe(ok => this.partsGrid.reload());
        };

        this.deleteSelected = (parts: IdlObject[]) => {
            parts.forEach(part => {
                part.editor(this.auth.user().id());
                part.edit_date('now');
            });

            this.pcrud.update(parts).toPromise().then(_ => {
                this.pcrud.remove(parts).toPromise().then(__ => {
                    this.partsGrid.reload();
                });
            });
        };

        this.mergeSelected = (parts: IdlObject[]) => {
            if (parts.length < 2) { return; }
            this.mergeDialog.parts = parts;
            this.mergeDialog.open().subscribe(ok => this.partsGrid.reload());
        };

    }
}

