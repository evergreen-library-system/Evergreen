import {Component, OnInit, Input, ViewChild} from '@angular/core';
import {IdlService, IdlObject} from '@eg/core/idl.service';
import {PcrudService} from '@eg/core/pcrud.service';
import {Pager} from '@eg/share/util/pager';
import {OrgService} from '@eg/core/org.service';
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
    @ViewChild('partsGrid') partsGrid: GridComponent;
    @ViewChild('editDialog') editDialog: FmRecordEditorComponent;
    @ViewChild('mergeDialog') mergeDialog: PartMergeDialogComponent;

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

    constructor(
        private idl: IdlService,
        private org: OrgService,
        private pcrud: PcrudService,
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
            'DELETE_MONOGRAPH_PART'
        ]).then(perms => this.permissions = perms);

        this.gridDataSource.getRows = (pager: Pager, sort: any[]) => {
            const orderBy: any = {};

            if (sort.length) { // Sort provided by grid.
                orderBy.bmp = sort[0].name + ' ' + sort[0].dir;
            } else {
                orderBy.bmp = 'label';
            }

            const searchOps = {
                offset: pager.offset,
                limit: pager.limit,
                order_by: orderBy
            };

            return this.pcrud.search('bmp',
                {record: this.recId, deleted: 'f'}, searchOps);
        };

        this.partsGrid.onRowActivate.subscribe(
            (part: IdlObject) => {
                this.editDialog.mode = 'update';
                this.editDialog.recId = part.id();
                this.editDialog.open().then(
                    ok => this.partsGrid.reload(),
                    err => {}
                );
            }
        );

        this.createNew = () => {

            const part = this.idl.create('bmp');
            part.record(this.recId);
            this.editDialog.record = part;

            this.editDialog.mode = 'create';
            this.editDialog.open().then(
                ok => this.partsGrid.reload(),
                err => {}
            );
        };

        this.deleteSelected = (parts: IdlObject[]) => {
            parts.forEach(part => part.isdeleted(true));
            this.pcrud.autoApply(parts).subscribe(
                val => console.debug('deleted: ' + val),
                err => {},
                ()  => this.partsGrid.reload()
            );
        };

        this.mergeSelected = (parts: IdlObject[]) => {
            if (parts.length < 2) { return; }
            this.mergeDialog.parts = parts;
            this.mergeDialog.open().then(
                ok => this.partsGrid.reload(),
                err => console.debug('Dialog dismissed')
            );
        };
    }
}

