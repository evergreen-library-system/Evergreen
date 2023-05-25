import {Component, OnInit, AfterViewInit, OnDestroy, Input, Output, EventEmitter, ViewChild, ChangeDetectorRef} from '@angular/core';
import {EMPTY, from, Subscription} from 'rxjs';
import {Router, ActivatedRoute, ParamMap} from '@angular/router';
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
import {ConfirmDialogComponent} from '@eg/share/dialog/confirm.component';
import {PcrudService} from '@eg/core/pcrud.service';

@Component({
    selector: 'eg-provider-edi-accounts',
    templateUrl: 'provider-edi-accounts.component.html',
})
export class ProviderEdiAccountsComponent implements OnInit, AfterViewInit, OnDestroy {

    edi_accounts: any[] = [];

    gridSource: GridDataSource;
    ediMessagesSource: GridDataSource;
    @ViewChild('editDialog', { static: true }) editDialog: FmRecordEditorComponent;
    @ViewChild('acqProviderEdiAccountsGrid', { static: true }) providerEdiAccountsGrid: GridComponent;
    @ViewChild('acqProviderEdiMessagesGrid', { static: false }) providerEdiMessagesGrid: GridComponent;
    @ViewChild('confirmSetAsDefault', { static: true }) confirmSetAsDefault: ConfirmDialogComponent;
    @ViewChild('successString', { static: true }) successString: StringComponent;
    @ViewChild('createString', { static: false }) createString: StringComponent;
    @ViewChild('createErrString', { static: false }) createErrString: StringComponent;
    @ViewChild('updateFailedString', { static: false }) updateFailedString: StringComponent;
    @ViewChild('deleteFailedString', { static: true }) deleteFailedString: StringComponent;
    @ViewChild('deleteSuccessString', { static: true }) deleteSuccessString: StringComponent;
    @ViewChild('setAsDefaultSuccessString', { static: true }) setAsDefaultSuccessString: StringComponent;
    @ViewChild('setAsDefaultFailedString', { static: true }) setAsDefaultFailedString: StringComponent;

    cellTextGenerator: GridCellTextGenerator;
    provider: IdlObject;
    selected: IdlObject;

    canCreate: boolean;
    canDelete: boolean;
    notOneSelectedRow: (rows: IdlObject[]) => boolean;
    deleteSelected: (rows: IdlObject[]) => void;

    viewEdiMessages: boolean;
    selectedEdiAccountId: number;
    selectedEdiAccountLabel = '';

    permissions: {[name: string]: boolean};

    subscription: Subscription;

    // Size of create/edito dialog.  Uses large by default.
    @Input() dialogSize: 'sm' | 'lg' = 'lg';
    @Output() desireSummarize: EventEmitter<number> = new EventEmitter<number>();

    constructor(
        private router: Router,
        private route: ActivatedRoute,
        private changeDetector: ChangeDetectorRef,
        private net: NetService,
        private idl: IdlService,
        private auth: AuthService,
        private pcrud: PcrudService,
        private providerRecord: ProviderRecordService,
        private toast: ToastService) {
    }

    ngOnInit() {
        this.gridSource = this.getDataSource();
        this.ediMessagesSource = this.getEdiMessagesSource();
        this.viewEdiMessages = false;
        this.selectedEdiAccountId = null;
        this.cellTextGenerator = {};
        this.notOneSelectedRow = (rows: IdlObject[]) => (rows.length !== 1);
        this.deleteSelected = (idlThings: IdlObject[]) => {
            idlThings.forEach(idlThing => idlThing.isdeleted(true));
            this.providerRecord.batchUpdate(idlThings).subscribe(
                val => {
                    console.debug('deleted: ' + val);
                    this.deleteSuccessString.current()
                        .then(str => this.toast.success(str));
                },
                (err: unknown) => {
                    this.deleteFailedString.current()
                        .then(str => this.toast.danger(str));
                },
                ()  => {
                    this.providerRecord.refreshCurrent().then(
                        () => {
                            this.providerEdiAccountsGrid.reload();
                        }
                    );
                }
            );
        };
        this.providerEdiAccountsGrid.onRowActivate.subscribe(
            (idlThing: IdlObject) => this.showEditDialog(idlThing)
        );
        this.subscription = this.providerRecord.providerUpdated$.subscribe(
            id => {
                this.providerEdiAccountsGrid.reload();
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
            let edi_accounts = this.provider.edi_accounts();

            if (sort.length > 0) {
                edi_accounts = edi_accounts.sort((a, b) => {
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

            return from(edi_accounts.slice(pager.offset, pager.offset + pager.limit));
        };
        return gridSource;
    }

    getEdiMessagesSource(): GridDataSource {
        const gridSource = new GridDataSource();
        gridSource.getRows = (pager: Pager, sort: any[]) => {
            const orderBy: any = {acqedim: 'create_time desc'};
            if (sort.length) {
                orderBy.acqedim = sort[0].name + ' ' + sort[0].dir;
            }

            // base query to grab everything
            const base: Object = {
                account: this.selectedEdiAccountId
            };
            const query: any = new Array();
            query.push(base);

            // and add any filters
            Object.keys(gridSource.filters).forEach(key => {
                Object.keys(gridSource.filters[key]).forEach(key2 => {
                    query.push(gridSource.filters[key][key2]);
                });
            });
            return this.pcrud.search('acqedim',
                query, {
                    flesh: 3,
                    flesh_fields: {acqedim: ['account', 'purchase_order']},
                    offset: pager.offset,
                    limit: pager.limit,
                    order_by: orderBy
                });
        };
        return gridSource;
    }

    showEditDialog(providerEdiAccount: IdlObject): Promise<any> {
        this.editDialog.mode = 'update';
        this.editDialog.recordId = providerEdiAccount['id']();
        return new Promise((resolve, reject) => {
            this.editDialog.open({size: this.dialogSize}).subscribe(
                result => {
                    this.successString.current()
                        .then(str => this.toast.success(str));
                    this.providerRecord.refreshCurrent().then(
                        () => this.providerEdiAccountsGrid.reload()
                    );
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

    editSelected(providerEdiAccountFields: IdlObject[]) {
        // Edit each IDL thing one at a time
        const editOneThing = (providerEdiAccount: IdlObject) => {
            if (!providerEdiAccount) { return; }

            this.showEditDialog(providerEdiAccount).then(
                () => editOneThing(providerEdiAccountFields.shift()));
        };

        editOneThing(providerEdiAccountFields.shift());
    }

    setAsDefault(providerEdiAccountFields: IdlObject[]) {
        this.selected = providerEdiAccountFields[0];
        this.confirmSetAsDefault.open().subscribe(confirmed => {
            if (!confirmed) { return; }
            this.providerRecord.refreshCurrent().then(() => {
                this.provider.edi_default(providerEdiAccountFields[0].id());
                this.provider.ischanged(true);
                // eslint-disable-next-line rxjs/no-nested-subscribe
                this.providerRecord.batchUpdate(this.provider).subscribe(
                    val => {
                        this.setAsDefaultSuccessString.current()
                            .then(str => this.toast.success(str));
                    },
                    (err: unknown) => {
                        this.setAsDefaultFailedString.current()
                            .then(str => this.toast.danger(str));
                    },
                    () => {
                        this.providerRecord.refreshCurrent().then(
                            () => {
                                this.providerEdiAccountsGrid.reload();
                                this.desireSummarize.emit(this.provider.id());
                            }
                        );
                    }
                );
            });
        });
    }

    displayEdiMessages(providerEdiAccountFields: IdlObject[]) {
        this.selectedEdiAccountId = providerEdiAccountFields[0].id();
        this.selectedEdiAccountLabel = providerEdiAccountFields[0].label();
        this.viewEdiMessages = true;
        this.changeDetector.detectChanges();
        this.providerEdiMessagesGrid.reload();
    }

    createNew() {
        this.editDialog.mode = 'create';
        const edi_account = this.idl.create('acqedi');
        edi_account.provider(this.provider.id());
        edi_account.owner(this.auth.user().ws_ou());
        edi_account.use_attrs(true);
        this.editDialog.record = edi_account;
        this.editDialog.recordId = null;
        this.editDialog.open({size: this.dialogSize}).subscribe(
            ok => {
                this.createString.current()
                    .then(str => this.toast.success(str));
                this.providerRecord.refreshCurrent().then(
                    () => this.providerEdiAccountsGrid.reload()
                );
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

}
