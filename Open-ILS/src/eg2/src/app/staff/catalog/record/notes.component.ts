import {Component, OnInit, Input, ViewChild} from '@angular/core';
import {IdlService, IdlObject} from '@eg/core/idl.service';
import {PcrudService} from '@eg/core/pcrud.service';
import {Pager} from '@eg/share/util/pager';
import {OrgService} from '@eg/core/org.service';
import {PermService} from '@eg/core/perm.service';
import {GridDataSource} from '@eg/share/grid/grid';
import {GridComponent} from '@eg/share/grid/grid.component';
import {FmRecordEditorComponent} from '@eg/share/fm-editor/fm-editor.component';

@Component({
    selector: 'eg-catalog-record-notes',
    templateUrl: 'notes.component.html'
})
export class NotesComponent implements OnInit {

    recId: number;
    gridDataSource: GridDataSource;
    initDone: boolean;
    @ViewChild('notesGrid', { static: true }) notesGrid: GridComponent;
    @ViewChild('editDialog', { static: true }) editDialog: FmRecordEditorComponent;

    canCreate: boolean;
    canDelete: boolean;
    createNew: () => void;
    deleteSelected: (rows: IdlObject[]) => void;
    permissions: {[name: string]: boolean};

    @Input() set recordId(id: number) {
        this.recId = id;
        // Only force new data collection when recordId()
        // is invoked after ngInit() has already run.
        if (this.initDone) {
            this.notesGrid.reload();
        }
    }

    get recordId(): number {
        return this.recId;
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
            'CREATE_RECORD_NOTE',
            'UPDATE_RECORD_NOTE',
            'DELETE_RECORD_NOTE'
        ]).then(perms => this.permissions = perms);

        this.gridDataSource.getRows = (pager: Pager, sort: any[]) => {
            const orderBy: any = {};

            if (sort.length) { // Sort provided by grid.
                orderBy.bren = sort[0].name + ' ' + sort[0].dir;
            } else {
                orderBy.bren = 'edit_date';
            }

            const searchOps = {
                offset: pager.offset,
                limit: pager.limit,
                order_by: orderBy,
                flesh: 2,
                flesh_fields: {bren: ['creator', 'editor']}
            };

            return this.pcrud.search('bren',
                {record: this.recId, deleted: 'f'}, searchOps);
        };

        this.notesGrid.onRowActivate.subscribe(
            (note: IdlObject) => {
                this.editDialog.mode = 'update';
                this.editDialog.recordId = note.id();
                this.editDialog.open()
                    // eslint-disable-next-line rxjs/no-nested-subscribe
                    .subscribe(ok => this.notesGrid.reload());
            }
        );

        this.createNew = () => {

            const note = this.idl.create('bren');
            note.record(this.recordId);
            this.editDialog.record = note;

            this.editDialog.mode = 'create';
            this.editDialog.open().subscribe(ok => this.notesGrid.reload());
        };

        this.deleteSelected = (notes: IdlObject[]) => {
            notes.forEach(note => note.isdeleted(true));
            this.pcrud.autoApply(notes).subscribe(
                val => {},
                (err: unknown) => {},
                ()  => this.notesGrid.reload()
            );
        };
    }
}

