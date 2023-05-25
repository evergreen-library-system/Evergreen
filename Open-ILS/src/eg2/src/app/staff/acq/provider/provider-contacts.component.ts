import {Component, OnInit, AfterViewInit, OnDestroy, Input, Output, ViewChild, EventEmitter, ChangeDetectorRef} from '@angular/core';
import {EMPTY, throwError, from, Subscription} from 'rxjs';
import {map} from 'rxjs/operators';
import {Router, ActivatedRoute} from '@angular/router';
import {Pager} from '@eg/share/util/pager';
import {IdlService, IdlObject} from '@eg/core/idl.service';
import {NetService} from '@eg/core/net.service';
import {PcrudService} from '@eg/core/pcrud.service';
import {EventService} from '@eg/core/event.service';
import {AuthService} from '@eg/core/auth.service';
import {GridComponent} from '@eg/share/grid/grid.component';
import {GridDataSource, GridCellTextGenerator} from '@eg/share/grid/grid';
import {ProviderRecordService} from './provider-record.service';
import {ProviderContactAddressesComponent} from './provider-contact-addresses.component';
import {FmRecordEditorComponent} from '@eg/share/fm-editor/fm-editor.component';
import {StringComponent} from '@eg/share/string/string.component';
import {ConfirmDialogComponent} from '@eg/share/dialog/confirm.component';
import {ToastService} from '@eg/share/toast/toast.service';


@Component({
    selector: 'eg-provider-contacts',
    templateUrl: 'provider-contacts.component.html',
})
export class ProviderContactsComponent implements OnInit, AfterViewInit, OnDestroy {

    @Input() providerId: any;
    contacts: any[] = [];

    gridSource: GridDataSource;
    @ViewChild('editDialog', { static: true }) editDialog: FmRecordEditorComponent;
    @ViewChild('providerContactAddresses', { static: false }) providerContactAddresses: ProviderContactAddressesComponent;
    @ViewChild('acqProviderContactsGrid', { static: true }) providerContactsGrid: GridComponent;
    @ViewChild('confirmSetAsPrimary', { static: true }) confirmSetAsPrimary: ConfirmDialogComponent;
    @ViewChild('confirmUnsetAsPrimary', { static: true }) confirmUnsetAsPrimary: ConfirmDialogComponent;
    @ViewChild('successString', { static: true }) successString: StringComponent;
    @ViewChild('createString', { static: false }) createString: StringComponent;
    @ViewChild('createErrString', { static: false }) createErrString: StringComponent;
    @ViewChild('updateFailedString', { static: false }) updateFailedString: StringComponent;
    @ViewChild('deleteFailedString', { static: true }) deleteFailedString: StringComponent;
    @ViewChild('deleteSuccessString', { static: true }) deleteSuccessString: StringComponent;
    @ViewChild('setAsPrimarySuccessString', { static: true }) setAsPrimarySuccessString: StringComponent;
    @ViewChild('setAsPrimaryFailedString', { static: true }) setAsPrimaryFailedString: StringComponent;
    @ViewChild('unsetAsPrimarySuccessString', { static: true }) unsetAsPrimarySuccessString: StringComponent;
    @ViewChild('unsetAsPrimaryFailedString', { static: true }) unsetAsPrimaryFailedString: StringComponent;

    @Output() desireSummarize: EventEmitter<number> = new EventEmitter<number>();

    cellTextGenerator: GridCellTextGenerator;
    provider: IdlObject;
    selectedContact: IdlObject;

    canCreate: boolean;
    canDelete: boolean;
    deleteSelected: (rows: IdlObject[]) => void;
    cannotSetPrimaryContact: (rows: IdlObject[]) => boolean;
    cannotUnsetPrimaryContact: (rows: IdlObject[]) => boolean;

    permissions: {[name: string]: boolean};

    subscription: Subscription;

    // Size of create/edito dialog.  Uses large by default.
    @Input() dialogSize: 'sm' | 'lg' = 'lg';

    constructor(
        private router: Router,
        private route: ActivatedRoute,
        private changeDetector: ChangeDetectorRef,
        private net: NetService,
        private pcrud: PcrudService,
        private evt: EventService,
        private auth: AuthService,
        private idl: IdlService,
        private providerRecord: ProviderRecordService,
        private toast: ToastService) {
    }

    ngOnInit() {
        this.gridSource = this.getDataSource();
        this.cellTextGenerator = {
            email: row => row.email(),
            phone: row => row.phone(),
        };
        this.cannotSetPrimaryContact = (rows: IdlObject[]) => (rows.length !== 1 || (rows.length === 1 && rows[0]._is_primary));
        this.cannotUnsetPrimaryContact = (rows: IdlObject[]) => (rows.length !== 1 || (rows.length === 1 && !rows[0]._is_primary));
        this.deleteSelected = (idlThings: IdlObject[]) => {
            idlThings.forEach(idlThing => idlThing.isdeleted(true));
            this.providerRecord.batchUpdate(idlThings).subscribe(
                val => {
                    console.debug('deleted: ' + val);
                    this.deleteSuccessString.current()
                        .then(str => this.toast.success(str));
                    this.desireSummarize.emit(this.provider.id());
                },
                (err: unknown) => {
                    this.deleteFailedString.current()
                        .then(str => this.toast.danger(str));
                },
                ()  => {
                    this.providerRecord.refreshCurrent().then(
                        () => this.providerContactsGrid.reload()
                    );
                }
            );
        };
        this.providerContactsGrid.onRowActivate.subscribe(
            (idlThing: IdlObject) => this.showEditDialog(idlThing)
        );
        this.subscription = this.providerRecord.providerUpdated$.subscribe(
            id => {
                this.providerContactsGrid.reload();
            }
        );
    }

    ngAfterViewInit() {
        console.debug('this.providerRecord', this.providerRecord);
        console.debug('this.providerContactAddresses', this.providerContactAddresses);
        this.providerContactsGrid.onRowClick.subscribe(
            (idlThing: IdlObject) => {
                this.selectedContact = idlThing;
                console.debug('selected contact', this.selectedContact);
                // ensure that the contact address grid is instantiated
                this.changeDetector.detectChanges();
                this.providerContactAddresses.reloadGrid();
            }
        );
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
            let contacts = this.provider.contacts();

            const query = this.generateSearch(gridSource.filters);
            if (query.length) {
                query.unshift( { id: contacts.map(a => a.id()) } );

                const opts = {};
                opts['offset'] = pager.offset;
                opts['limit'] = pager.limit;
                opts['au_by_id'] = true;

                if (sort.length > 0) {
                    opts['order_by'] = [];
                    sort.forEach(sort_clause => {
                        opts['order_by'].push({
                            class: 'acqpc',
                            field: sort_clause.name,
                            direction: sort_clause.dir
                        });
                    });
                }

                return this.pcrud.search('acqpc',
                    query,
                    opts
                ).pipe(
                    map(res => {
                        if (this.evt.parse(res)) {
                            // eslint-disable-next-line @typescript-eslint/no-throw-literal
                            throw throwError(res);
                        } else {
                            return res;
                        }
                    }),
                );
            }

            if (sort.length > 0) {
                contacts = contacts.sort((a, b) => {
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

            return from(contacts.slice(pager.offset, pager.offset + pager.limit));
        };
        return gridSource;
    }

    showEditDialog(providerContact: IdlObject): Promise<any> {
        this.editDialog.mode = 'update';
        this.editDialog.recordId = providerContact['id']();
        return new Promise((resolve, reject) => {
            this.editDialog.open({size: this.dialogSize}).subscribe(
                result => {
                    this.successString.current()
                        .then(str => this.toast.success(str));
                    this.providerRecord.refreshCurrent().then(
                        () => this.providerContactsGrid.reload()
                    );
                    this.desireSummarize.emit(this.provider.id());
                    resolve(result);
                },
                (error: unknown) => {
                    this.updateFailedString.current()
                        .then(str => this.toast.danger(str));
                    reject(error);
                }
            );
        });
    }

    editSelected(providerContactFields: IdlObject[]) {
        // Edit each IDL thing one at a time
        const editOneThing = (providerContact: IdlObject) => {
            if (!providerContact) { return; }

            this.showEditDialog(providerContact).then(
                () => editOneThing(providerContactFields.shift()));
        };

        editOneThing(providerContactFields.shift());
    }

    createNew() {
        this.editDialog.mode = 'create';
        const contact = this.idl.create('acqpc');
        contact.provider(this.provider.id());
        this.editDialog.record = contact;
        this.editDialog.recordId = null;
        this.editDialog.open({size: this.dialogSize}).subscribe(
            ok => {
                this.createString.current()
                    .then(str => this.toast.success(str));
                this.providerRecord.refreshCurrent().then(
                    () => this.providerContactsGrid.reload()
                );
                this.desireSummarize.emit(this.provider.id());
            },
            // eslint-disable-next-line rxjs/no-implicit-any-catch
            (rejection: any) => {
                if (!rejection.dismissed) {
                    this.createErrString.current()
                        .then(str => this.toast.danger(str));
                }
            }
        );
    }

    setAsPrimary(providerContacts: IdlObject[]) {
        this.selectedContact = providerContacts[0];
        this.confirmSetAsPrimary.open().subscribe(confirmed => {
            if (!confirmed) { return; }
            this.providerRecord.refreshCurrent().then(() => {
                this.provider.primary_contact(providerContacts[0].id());
                this.provider.ischanged(true);
                // eslint-disable-next-line rxjs/no-nested-subscribe
                this.providerRecord.batchUpdate(this.provider).subscribe(
                    val => {
                        this.setAsPrimarySuccessString.current()
                            .then(str => this.toast.success(str));
                    },
                    (err: unknown) => {
                        this.setAsPrimaryFailedString.current()
                            .then(str => this.toast.danger(str));
                    },
                    () => {
                        this.providerRecord.refreshCurrent().then(
                            () => {
                                this.providerContactsGrid.reload();
                                this.desireSummarize.emit(this.provider.id());
                            }
                        );
                    }
                );
            });
        });
    }

    unsetAsPrimary(providerContacts: IdlObject[]) {
        this.selectedContact = providerContacts[0];
        this.confirmUnsetAsPrimary.open().subscribe(confirmed => {
            if (!confirmed) { return; }
            this.providerRecord.refreshCurrent().then(() => {
                this.provider.primary_contact(null);
                this.provider.ischanged(true);
                // eslint-disable-next-line rxjs/no-nested-subscribe
                this.providerRecord.batchUpdate(this.provider).subscribe(
                    val => {
                        this.unsetAsPrimarySuccessString.current()
                            .then(str => this.toast.success(str));
                    },
                    (err: unknown) => {
                        this.unsetAsPrimaryFailedString.current()
                            .then(str => this.toast.danger(str));
                    },
                    () => {
                        this.providerRecord.refreshCurrent().then(
                            () => {
                                this.providerContactsGrid.reload();
                                this.desireSummarize.emit(this.provider.id());
                            }
                        );
                    }
                );
            });
        });
    }
}
