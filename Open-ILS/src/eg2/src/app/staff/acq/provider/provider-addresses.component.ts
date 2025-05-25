
import {Component, OnInit, AfterViewInit, OnDestroy, Input, ViewChild} from '@angular/core';
import {EMPTY, throwError, from, Subscription, map} from 'rxjs';
import {Router, ActivatedRoute} from '@angular/router';
import {Pager} from '@eg/share/util/pager';
import {IdlService, IdlObject} from '@eg/core/idl.service';
import {NetService} from '@eg/core/net.service';
import {AuthService} from '@eg/core/auth.service';
import {PcrudService} from '@eg/core/pcrud.service';
import {EventService} from '@eg/core/event.service';
import {GridComponent} from '@eg/share/grid/grid.component';
import {GridDataSource, GridCellTextGenerator} from '@eg/share/grid/grid';
import {ProviderRecordService} from './provider-record.service';
import {FmRecordEditorComponent} from '@eg/share/fm-editor/fm-editor.component';
import {StringComponent} from '@eg/share/string/string.component';
import {ToastService} from '@eg/share/toast/toast.service';

@Component({
    selector: 'eg-provider-addresses',
    templateUrl: 'provider-addresses.component.html',
})
export class ProviderAddressesComponent implements OnInit, AfterViewInit, OnDestroy {

    addresses: any[] = [];

    gridSource: GridDataSource;
    @ViewChild('editDialog', { static: true }) editDialog: FmRecordEditorComponent;
    @ViewChild('acqProviderAddressesGrid', { static: true }) providerAddressesGrid: GridComponent;
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
        private evt: EventService,
        private pcrud: PcrudService,
        private idl: IdlService,
        private auth: AuthService,
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
                        () => this.providerAddressesGrid.reload()
                    );
                } }
            );
        };
        this.providerAddressesGrid.onRowActivate.subscribe(
            (idlThing: IdlObject) => this.showEditDialog(idlThing)
        );
        this.subscription = this.providerRecord.providerUpdated$.subscribe(
            id => {
                this.providerAddressesGrid.reload();
            }
        );
    }

    ngAfterViewInit() {
        console.debug('this.providerRecord', this.providerRecord);
    }

    ngOnDestroy() {
        this.subscription.unsubscribe();
    }

    generateSearch(filters): any {
        const query: any = new Array();

        Object.keys(filters).forEach(filterField => {
            filters[filterField].forEach(condition => {
                query.push(condition);
            });
        });
        return query;
    }

    getDataSource(): GridDataSource {
        const gridSource = new GridDataSource();

        gridSource.getRows = (pager: Pager, sort: any[]) => {
            this.provider = this.providerRecord.current();
            if (!this.provider) {
                return EMPTY;
            }
            let addresses = this.provider.addresses();

            const query = this.generateSearch(gridSource.filters);
            if (query.length) {
                query.unshift( { id: addresses.map(a => a.id()) } );

                const opts = {};
                opts['offset'] = pager.offset;
                opts['limit'] = pager.limit;
                opts['au_by_id'] = true;

                if (sort.length > 0) {
                    opts['order_by'] = [];
                    sort.forEach(sort_clause => {
                        opts['order_by'].push({
                            class: 'acqpa',
                            field: sort_clause.name,
                            direction: sort_clause.dir
                        });
                    });
                }

                return this.pcrud.search('acqpa',
                    query,
                    opts
                ).pipe(
                    map(res => {
                        if (this.evt.parse(res)) {
                            throw throwError(res);
                        } else {
                            return res;
                        }
                    }),
                );
            }

            if (sort.length > 0) {
                addresses = addresses.sort((a, b) => {
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

            return from(addresses.slice(pager.offset, pager.offset + pager.limit));
        };
        return gridSource;
    }

    showEditDialog(providerAddress: IdlObject): Promise<any> {
        this.editDialog.mode = 'update';
        this.editDialog.recordId = providerAddress['id']();
        return new Promise((resolve, reject) => {
            this.editDialog.open({size: this.dialogSize}).subscribe(
                { next: result => {
                    this.successString.current()
                        .then(str => this.toast.success(str));
                    this.providerRecord.refreshCurrent().then(
                        () => this.providerAddressesGrid.reload()
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

    editSelected(providerAddressFields: IdlObject[]) {
        // Edit each IDL thing one at a time
        const editOneThing = (providerAddress: IdlObject) => {
            if (!providerAddress) { return; }

            this.showEditDialog(providerAddress).then(
                () => editOneThing(providerAddressFields.shift()));
        };

        editOneThing(providerAddressFields.shift());
    }

    createNew() {
        this.editDialog.mode = 'create';
        const address = this.idl.create('acqpa');
        address.provider(this.provider.id());
        address.valid(true);
        this.editDialog.record = address;
        this.editDialog.recordId = null;
        this.editDialog.open({size: this.dialogSize}).subscribe(
            { next: ok => {
                this.createString.current()
                    .then(str => this.toast.success(str));
                this.providerRecord.refreshCurrent().then(
                    () => this.providerAddressesGrid.reload()
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
