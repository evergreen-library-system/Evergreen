/* eslint-disable no-self-assign, no-magic-numbers */
import {Component, Input, OnInit, OnDestroy, ViewChild} from '@angular/core';
import {Router} from '@angular/router';
import {Subscription, tap} from 'rxjs';
import {IdlObject, IdlService} from '@eg/core/idl.service';
import {NetService} from '@eg/core/net.service';
import {AuthService} from '@eg/core/auth.service';
import {OrgService} from '@eg/core/org.service';
import {PcrudService} from '@eg/core/pcrud.service';
import {ServerStoreService} from '@eg/core/server-store.service';
import {ProgressDialogComponent} from '@eg/share/dialog/progress.component';
import {EventService, EgEvent} from '@eg/core/event.service';
import {ConfirmDialogComponent} from '@eg/share/dialog/confirm.component';
import {PoService} from './po.service';
import {LineitemService} from '../lineitem/lineitem.service';
import {CancelDialogComponent} from '../lineitem/cancel-dialog.component';
import {LinkInvoiceDialogComponent} from '../lineitem/link-invoice-dialog.component';

const PO_ACTIVATION_WARNINGS = [
    'ACQ_FUND_EXCEEDS_WARN_PERCENT'
];

@Component({
    templateUrl: 'summary.component.html',
    styleUrls: [ './summary.component.css' ],
    selector: 'eg-acq-po-summary'
})
export class PoSummaryComponent implements OnInit, OnDestroy {

    private _poId: number;
    @Input() set poId(id: number) {
        if (id === this._poId) { return; }
        this._poId = id;
        if (this.initDone) { this.load(); }
    }
    get poId(): number { return this._poId; }

    newPoName: string;
    editPoName = false;
    dupeResults = {
        dupeFound: false,
        dupePoId: -1
    };
    initDone = false;
    ediMessageCount = 0;
    invoiceCount = 0;
    showNotes = false;
    zeroCopyActivate = false;
    canActivate: boolean = null;
    canFinalize = false;
    showLegacyLinks = false;
    doingActivation = false;
    finishPoActivation = false;

    activationBlocks: EgEvent[] = [];
    activationWarnings: EgEvent[] = [];
    activationEvent: EgEvent;
    nameEditEnterToggled = false;
    stateChangeSub: Subscription;

    @ViewChild('cancelDialog') cancelDialog: CancelDialogComponent;
    @ViewChild('linkInvoiceDialog') linkInvoiceDialog: LinkInvoiceDialogComponent;
    @ViewChild('progressDialog') progressDialog: ProgressDialogComponent;
    @ViewChild('confirmFinalize') confirmFinalize: ConfirmDialogComponent;
    @ViewChild('confirmActivate') confirmActivate: ConfirmDialogComponent;

    constructor(
        private router: Router,
        private evt: EventService,
        private idl: IdlService,
        private net: NetService,
        private org: OrgService,
        private pcrud: PcrudService,
        private auth: AuthService,
        private store: ServerStoreService,
        private liService: LineitemService,
        private poService: PoService
    ) {}

    ngOnInit() {
        this.load().then(_ => this.initDone = true);

        // Re-check for activation blocks if the LI service tells us
        // something significant happened.
        this.stateChangeSub = this.liService.activateStateChange
            .pipe(tap(_ => this.poService.getFleshedPo(this.poId, {toCache: true})))
            .subscribe(_ => this.setCanActivate());
    }

    ngOnDestroy() {
        if (this.stateChangeSub) {
            this.stateChangeSub.unsubscribe();
        }
    }

    po(): IdlObject {
        return this.poService.currentPo;
    }

    load(useCache = true): Promise<any> {
        if (!this.poId) { return Promise.resolve(); }

        this.dupeResults.dupeFound = false;
        this.dupeResults.dupePoId = -1;

        if (history.state.finishPoActivation) {
            this.doingActivation = true;
            useCache = false;
        }

        return this.poService.getFleshedPo(this.poId, {fromCache: useCache, toCache: true})
            .then(po => {

                // EDI message count
                return this.pcrud.search('acqedim',
                    {purchase_order: this.poId}, {}, {idlist: true, atomic: true}
                ).toPromise().then(ids => this.ediMessageCount = ids.length);

            })
            .then(_ => {

                // Invoice count
                return this.net.request('open-ils.acq',
                    'open-ils.acq.invoice.unified_search.atomic',
                    this.auth.token(), {acqpo: [{id: this.poId}]},
                    null, null, {id_list: true}
                ).toPromise().then(ids => this.invoiceCount = ids.length);

            })
            .then(_ => this.setCanActivate())
            .then(_ => this.setCanFinalize())
            .then(_ => this.loadUiPrefs())
            .then(_ => this.activatePoIfRequested());
    }

    // Can run via Enter or blur.  If it just ran via Enter, avoid
    // running it again on the blur, which will happen directly after
    // the Enter.
    toggleNameEdit(fromEnter?: boolean) {

        // don't allow change if new name is currently
        // a duplicate
        if (this.dupeResults.dupeFound) {
            return;
        }

        if (fromEnter) {
            this.nameEditEnterToggled = true;
        } else {
            if (this.nameEditEnterToggled) {
                this.nameEditEnterToggled = false;
                return;
            }
        }

        this.editPoName = !this.editPoName;

        if (this.editPoName) {
            this.newPoName = this.po().name();
            setTimeout(() => {
                const node =
                    document.getElementById('pl-name-input') as HTMLInputElement;
                if (node) { node.select(); }
            });

        } else if (this.newPoName && this.newPoName !== this.po().name() &&
                   !this.dupeResults.dupeFound) {

            const prevName = this.po().name();
            this.po().name(this.newPoName);
            this.newPoName = null;
            this.dupeResults.dupeFound = false;

            this.pcrud.update(this.po()).subscribe(resp => {
                const evt = this.evt.parse(resp);
                if (evt) {
                    alert(evt);
                    this.po().name(prevName);
                }
            });
        }
    }

    checkDuplicatePoName() {
        this.poService.checkDuplicatePoName(
            this.po().ordering_agency(), this.newPoName, this.dupeResults
        );
    }

    cancelPo() {
        this.cancelDialog.open().subscribe(reason => {
            if (!reason) { return; }

            this.progressDialog.reset();
            this.progressDialog.open();
            this.net.request('open-ils.acq',
                'open-ils.acq.purchase_order.cancel',
                this.auth.token(), this.poId, reason
            // eslint-disable-next-line rxjs-x/no-nested-subscribe
            ).subscribe(resp => {
                this.progressDialog.close();

                const evt = this.evt.parse(resp);
                if (evt) {
                    alert(evt);
                } else {
                    location.href = location.href;
                }
            });
        });
    }

    linkInvoiceFromPo() {

        this.linkInvoiceDialog.poId = this.poId;
        this.linkInvoiceDialog.open().subscribe(invId => {
            if (!invId) { return; }

            const path = '/eg2/staff/acq/invoice/' + invId + '?' +
                     'attach_po=' + this.poId;
            window.location.href = path;
        });

    }

    setCanActivate() {
        this.canActivate = null;
        this.activationBlocks = [];
        this.activationWarnings = [];

        if (!(this.po().state().match(/new|pending/))) {
            this.canActivate = false;
            return;
        }

        const options = {
            zero_copy_activate: this.zeroCopyActivate
        };

        return this.net.request('open-ils.acq',
            'open-ils.acq.purchase_order.activate.dry_run',
            this.auth.token(), this.poId, null, options

        ).pipe(tap(resp => {

            const evt = this.evt.parse(resp);
            if (evt) {
                if (PO_ACTIVATION_WARNINGS.includes(evt.textcode)) {
                    this.activationWarnings.push(evt);
                } else {
                    this.activationBlocks.push(evt);
                }
            }

        })).toPromise().then(_ => {

            if (this.activationBlocks.length === 0) {
                this.canActivate = true;
                return;
            }

            this.canActivate = false;
        });
    }

    activatePo(noAssets?: boolean) {
        this.doingActivation = true;
        if (this.activationWarnings.length) {
            this.confirmActivate.open().subscribe(confirmed => {
                if (!confirmed) {
                    this.doingActivation = true;
                    return;
                }

                this._activatePo(noAssets);
            });
        } else {
            this._activatePo(noAssets);
        }
    }

    _activatePo(noAssets?: boolean) {
        if (noAssets) {
            // Bypass any Vandelay choices and force-load all records.
            const vandelay = {
                import_no_match: true,
                queue_name: `ACQ ${new Date().toISOString()}`
            };

            const options = {
                zero_copy_activate: this.zeroCopyActivate,
                no_assets: noAssets
            };

            this._doActualActivate(vandelay, options);
        } else {
            this.poService.checkIfImportNeeded().then(importNeeded => {
                if (importNeeded) {
                    this.router.navigate(
                        ['/staff/acq/po/' + this.po().id() + '/create-assets'],
                        { state: { activatePo: true } }
                    );
                } else {
                    // LIs are linked to bibs, so charge forward and activate with no options set
                    this._doActualActivate({}, {});
                }
            });
        }
    }

    _doActualActivate(vandelay: any, options: any) {
        this.activationEvent = null;
        this.progressDialog.open();
        this.progressDialog.update({max: this.po().lineitem_count() * 3});

        this.net.request(
            'open-ils.acq',
            'open-ils.acq.purchase_order.activate',
            this.auth.token(), this.poId, vandelay, options
        ).subscribe(resp => {
            const evt = this.evt.parse(resp);

            if (evt) {
                this.progressDialog.close();
                this.activationEvent = evt;
                return;
            }

            if (Number(resp) === 1) {
                this.progressDialog.close();
                // Refresh everything.
                this.initDone = false;
                this.doingActivation = false;
                this.load(false).then(_ => {
                    this.initDone = true;
                    this.liService.clearLiCache();
                    window.location.reload();
                });

            } else {
                this.progressDialog.update(
                    {value: resp.bibs + resp.li + resp.vqbr});
            }
        });
    }


    setCanFinalize() {

        if (this.po().state() === 'received') { return; }

        const invTypes = [];

        // get the unique set of invoice item type IDs
        this.po().po_items().forEach(item => {
            if (!invTypes.includes(item.inv_item_type())) {
                invTypes.push(item.inv_item_type());
            }
        });

        if (invTypes.length === 0) { return; }

        this.pcrud.search('aiit',
            {code: invTypes, blanket: 't'}, {limit: 1})
            .subscribe(_ => this.canFinalize = true);
    }

    loadUiPrefs() {
        return this.store.getItemBatch(['ui.staff.acq.show_deprecated_links'])
            .then(settings => {
                this.showLegacyLinks = settings['ui.staff.acq.show_deprecated_links'];
            });
    }

    activatePoIfRequested() {
        if (this.canActivate && history.state.finishPoActivation) {
            this.activatePo(false);
        }
    }

    finalizePo() {

        this.confirmFinalize.open().subscribe(confirmed => {
            if (!confirmed) { return; }

            this.net.request('open-ils.acq',
                'open-ils.acq.purchase_order.blanket.finalize',
                this.auth.token(), this.poId
            // eslint-disable-next-line rxjs-x/no-nested-subscribe
            ).subscribe(resp => {
                if (Number(resp) === 1) {
                    location.href = location.href;
                }
            });
        });
    }
}


