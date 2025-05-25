import {Component, OnInit, Input, ViewChild} from '@angular/core';
import {ActivatedRoute} from '@angular/router';
import {GridDataSource} from '@eg/share/grid/grid';
import {GridComponent} from '@eg/share/grid/grid.component';
import {Pager} from '@eg/share/util/pager';
import {PcrudService} from '@eg/core/pcrud.service';
import {IdlObject} from '@eg/core/idl.service';
import {FmRecordEditorComponent} from '@eg/share/fm-editor/fm-editor.component';
import {ToastService} from '@eg/share/toast/toast.service';
import {StringComponent} from '@eg/share/string/string.component';
import {QueryDialogComponent} from './query-dialog.component';

@Component({
    templateUrl: './search-filter-group-entries.component.html'
})

export class SearchFilterGroupEntriesComponent implements OnInit {

    @ViewChild('editDialog') editDialog: FmRecordEditorComponent;
    @ViewChild('queryDialog') queryDialog: QueryDialogComponent;
    @ViewChild('grid', { static: true }) grid: GridComponent;

    @ViewChild('updateSuccessString') updateSuccessString: StringComponent;
    @ViewChild('updateFailedString') updateFailedString: StringComponent;
    @ViewChild('createString') createString: StringComponent;
    @ViewChild('createQueryString') createQueryString: StringComponent;
    @ViewChild('queryRequiredString') queryRequiredString: StringComponent;
    @ViewChild('createErrString') createErrString: StringComponent;
    @ViewChild('deleteFailedString') deleteFailedString: StringComponent;
    @ViewChild('deleteSuccessString') deleteSuccessString: StringComponent;

    @Input() dataSource: GridDataSource;

    currentId: number;

    constructor(
        private route: ActivatedRoute,
        private pcrud: PcrudService,
        private toast: ToastService
    ) {
        this.dataSource = new GridDataSource();
    }

    ngOnInit() {
        this.currentId = parseInt(this.route.snapshot.paramMap.get('id'), 10);
        this.dataSource.getRows = (pager: Pager, sort: any[]) => {
            const searchOps = {
                offset: pager.offset,
                limit: pager.limit,
                order_by: {asfge: 'pos'},
                flesh: 1,
                flesh_fields: {asfge: ['query']}
            };
            return this.pcrud.search('asfge', {grp: this.currentId}, searchOps);
        };
        this.grid.onRowActivate.subscribe(
            (idlThing: IdlObject) => this.editQuery([idlThing])
        );
    }

    createQuery = () => {
        this.queryDialog.mode = 'create';
        this.queryDialog.open({size: 'lg'}).subscribe(
            { next: result => {
                if (result.notFilledOut) {
                    this.queryRequiredString.current()
                        .then(str => this.toast.danger(str));
                } else {
                    this.createQueryString.current()
                        .then(str => this.toast.success(str));
                    this.grid.reload();
                }
            }, error: (error: unknown) => {
                this.createErrString.current()
                    .then(str => this.toast.danger(str));
            } }
        );
    };

    editQuery = (event) => {
        const firstRecord = event[0];
        this.queryDialog.record = firstRecord;
        this.queryDialog.mode = 'update';
        this.queryDialog.newQueryLabel = firstRecord.query().label();
        this.queryDialog.newQueryText = firstRecord.query().query_text();
        this.queryDialog.newQueryPosition = firstRecord.pos();
        this.queryDialog.recordId = firstRecord.id();
        this.queryDialog.open({size: 'lg'}).subscribe(
            { next: result => {
                if (result.notFilledOut) {
                    this.queryRequiredString.current()
                        .then(str => this.toast.danger(str));
                } else {
                    this.updateSuccessString.current()
                        .then(str => this.toast.success(str));
                    this.grid.reload();
                }
            }, error: (error: unknown) => {
                this.updateFailedString.current()
                    .then(str => this.toast.danger(str));
            } }
        );
    };

    deleteSelected = (idlThings: IdlObject[]) => {
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
}
