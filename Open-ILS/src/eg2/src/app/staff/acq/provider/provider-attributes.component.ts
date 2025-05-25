import {Component, OnInit, AfterViewInit, OnDestroy, Input, ViewChild} from '@angular/core';
import {EMPTY, from, Subscription} from 'rxjs';
import {Router, ActivatedRoute} from '@angular/router';
import {Pager} from '@eg/share/util/pager';
import {IdlService, IdlObject} from '@eg/core/idl.service';
import {NetService} from '@eg/core/net.service';
import {AuthService} from '@eg/core/auth.service';
import {GridComponent} from '@eg/share/grid/grid.component';
import {GridDataSource, GridCellTextGenerator} from '@eg/share/grid/grid';
import {ProviderRecordService} from './provider-record.service';
import {FmRecordEditorComponent} from '@eg/share/fm-editor/fm-editor.component';
import {StringComponent} from '@eg/share/string/string.component';
import {ToastService} from '@eg/share/toast/toast.service';


@Component({
    selector: 'eg-provider-attributes',
    templateUrl: 'provider-attributes.component.html',
})
export class ProviderAttributesComponent implements OnInit, AfterViewInit, OnDestroy {

    @Input() providerId: any;
    attributes: any[] = [];

    gridSource: GridDataSource;
    @ViewChild('editDialog', { static: true }) editDialog: FmRecordEditorComponent;
    @ViewChild('acqProviderAttributesGrid', { static: true }) providerAttributesGrid: GridComponent;
    @ViewChild('successString', { static: true }) successString: StringComponent;
    @ViewChild('createString', { static: false }) createString: StringComponent;
    @ViewChild('createErrString', { static: false }) createErrString: StringComponent;
    @ViewChild('updateFailedString', { static: false }) updateFailedString: StringComponent;
    @ViewChild('deleteFailedString', { static: true }) deleteFailedString: StringComponent;
    @ViewChild('deleteSuccessString', { static: true }) deleteSuccessString: StringComponent;

    cellTextGenerator: GridCellTextGenerator;
    provider: IdlObject;

    canCreate: boolean;
    canDelete: boolean;
    deleteSelected: (rows: IdlObject[]) => void;

    permissions: {[name: string]: boolean};

    subscription: Subscription;

    // Size of create/edito dialog.  Uses large by default.
    @Input() dialogSize: 'sm' | 'lg' = 'lg';

    constructor(
        private router: Router,
        private route: ActivatedRoute,
        private net: NetService,
        private auth: AuthService,
        private idl: IdlService,
        private providerRecord: ProviderRecordService,
        private toast: ToastService) {

    }

    ngOnInit() {
        this.gridSource = this.getDataSource();
        this.cellTextGenerator = {};
        this.deleteSelected = (idlThings: IdlObject[]) => {
            idlThings.forEach(idlThing => idlThing.isdeleted(true));
            this.providerRecord.batchUpdate(idlThings).subscribe(
                { next: val => {
                    console.debug('deleted: ' + val);
                    this.deleteSuccessString.current()
                        .then(str => this.toast.success(str));
                }, error: (err: unknown) => {
                    this.deleteFailedString.current()
                        .then(str => this.toast.danger(str));
                }, complete: ()  => {
                    this.providerRecord.refreshCurrent().then(
                        () => this.providerAttributesGrid.reload()
                    );
                } }
            );
        };
        this.providerAttributesGrid.onRowActivate.subscribe(
            (idlThing: IdlObject) => this.showEditDialog(idlThing)
        );
        this.subscription = this.providerRecord.providerUpdated$.subscribe(
            id => {
                this.providerAttributesGrid.reload();
            }
        );

    }

    ngAfterViewInit() {
        console.debug('this.providerRecord', this.providerRecord);
    }

    ngOnDestroy() {
        this.subscription.unsubscribe();
    }

    getDataSource(): GridDataSource {
        const gridSource = new GridDataSource();

        gridSource.getRows = (pager: Pager, sort: any[]) => {
            this.provider = this.providerRecord.current();
            if (!this.provider) {
                return EMPTY;
            }
            let attributes = this.provider.attributes();

            if (sort.length > 0) {
                attributes = attributes.sort((a, b) => {
                    for (let i = 0; i < sort.length; i++) {
                        let lt = -1;
                        const sfield = sort[i].name;
                        if (sort[i].dir.substring(0, 1).toLowerCase() === 'd') {
                            lt *= -1;
                        }
                        if (a[sfield]() < b[sfield]()) { return lt; }
                        if (a[sfield]() > b[sfield]()) { return lt * -1; }
                    }
                    return 0;
                });

            }

            return from(attributes.slice(pager.offset, pager.offset + pager.limit));
        };
        return gridSource;
    }

    showEditDialog(providerAttribute: IdlObject): Promise<any> {
        this.editDialog.mode = 'update';
        this.editDialog.recordId = providerAttribute['id']();
        return new Promise((resolve, reject) => {
            this.editDialog.open({size: this.dialogSize}).subscribe(
                { next: result => {
                    this.successString.current()
                        .then(str => this.toast.success(str));
                    this.providerRecord.refreshCurrent().then(
                        () => this.providerAttributesGrid.reload()
                    );
                    resolve(result);
                }, error: (error: unknown) => {
                    this.updateFailedString.current()
                        .then(str => this.toast.danger(str));
                    reject(error);
                } }
            );
        });
    }

    editSelected(providerAttributesFields: IdlObject[]) {
        // Edit each IDL thing one at a time
        const editOneThing = (providerAttributes: IdlObject) => {
            if (!providerAttributes) { return; }

            this.showEditDialog(providerAttributes).then(
                () => editOneThing(providerAttributesFields.shift()));
        };

        editOneThing(providerAttributesFields.shift());
    }

    createNew() {
        this.editDialog.mode = 'create';
        const attributes = this.idl.create('acqlipad');
        attributes.provider(this.provider.id());
        this.editDialog.record = attributes;
        this.editDialog.recordId = null;
        this.editDialog.open({size: this.dialogSize}).subscribe(
            { next: ok => {
                this.createString.current()
                    .then(str => this.toast.success(str));
                this.providerRecord.refreshCurrent().then(
                    () => this.providerAttributesGrid.reload()
                );
            }, error: (rejection: any) => {
                if (!rejection.dismissed) {
                    this.createErrString.current()
                        .then(str => this.toast.danger(str));
                }
            } }
        );
    }
}
