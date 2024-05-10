/* eslint-disable */
import {Component, OnInit, OnDestroy, QueryList, ViewChild, ViewChildren} from '@angular/core';
import {ActivatedRoute, ParamMap, Router} from '@angular/router';
import {CanComponentDeactivate} from '@eg/share/util/can-deactivate.guard';
import {NgbNav, NgbNavChangeEvent} from '@ng-bootstrap/ng-bootstrap';
import {IdlService, IdlObject} from '@eg/core/idl.service';
import {EventService} from '@eg/core/event.service';
import {AuthService} from '@eg/core/auth.service';
import {PermService} from '@eg/core/perm.service';
import {PcrudService} from '@eg/core/pcrud.service';
import {InvoiceService} from './invoice.service';
import {InvoiceDetailsComponent} from './details.component';
import {LineitemListComponent} from '../lineitem/lineitem-list.component';
import {InvoiceChargesComponent} from './charges.component';
import {PoService} from '../po/po.service';
import {LineitemResultsComponent} from '@eg/staff/acq/search/lineitem-results.component';
import {firstValueFrom, Subscription} from 'rxjs';

@Component({
    templateUrl: 'invoice.component.html',
    styleUrls:  ['invoice.component.css']
})
export class InvoiceComponent implements OnInit, OnDestroy, CanComponentDeactivate {

    private angularNavigation = false;
    private permissions: any;
    context: string;

    count = 0;
    invoiceEntrySubscription: Subscription;
    attachedPoId: number; // for offering a return link upon error
    finalizablePoList: number[] = [];
    finalizeThese: { [key: number]: boolean } = {};
    finalizeDisabled = true;
    onTabChange: ($event: NgbNavChangeEvent) => void;
    errorText = '';
    loading = true;
    needs_invoice_create_perm = true;
    needs_invoice_view_perm = true;
    showFmEditor = true;

    @ViewChildren(LineitemResultsComponent) liResults: QueryList<LineitemResultsComponent>;
    @ViewChild(InvoiceDetailsComponent, { static: false }) invoiceDetails: InvoiceDetailsComponent;
    @ViewChild(LineitemListComponent, { static: false }) invoiceEntries: LineitemListComponent;
    @ViewChild(InvoiceChargesComponent, { static: false }) invoiceCharges: InvoiceChargesComponent;
    @ViewChild(NgbNav, { static: false }) acqInvoiceTabs: NgbNav;

    // isNavigating = false;

    constructor(
        private route: ActivatedRoute,
        private router: Router,
        private idl: IdlService,
        private evt: EventService,
        private auth: AuthService,
        private perm: PermService,
        private pcrud: PcrudService,
        public  invoiceService: InvoiceService,
        public  poService: PoService
    ) {}

    ngOnInit() {
        console.warn('InvoiceComponent, this', this);

        this.loadPerms().then(_ => console.log('InvoiceComponent, perms loaded'));

        window.addEventListener('beforeunload', this.beforeUnloadHandler.bind(this));

        /* this.router.events.subscribe((event) => {
            if (event instanceof NavigationStart) {
                this.isNavigating = true;
            } else if (event instanceof NavigationEnd) {
                this.isNavigating = false;
            }
        });*/

        this.route.url.subscribe(segments => {

            this.create_or_retrieve_invoice(segments);

        });

        this.invoiceEntrySubscription = this.invoiceService.invoiceEntryChange$
            .subscribe(invoiceEntry => {
                console.log('InvoiceComponent: invoiceEntry via subscription',invoiceEntry);
            });

        this.onTabChange = ($event) => {
            this.showFmEditor = $event.nextId === 'main';
        };
    }

    async loadPerms(): Promise<void> {
        if (this.permissions) {
            return;
        }
        this.permissions = await this.perm.hasWorkPermAt(
            ['ACQ_ALLOW_OVERSPEND','ACQ_INVOICE_REOPEN']
                .concat( this.idl.classes.acqinv.permacrud.create.perms )
                .concat( this.idl.classes.acqinv.permacrud.retrieve.perms )
                .concat( this.idl.classes.acqinv.permacrud.update.perms )
                .concat( this.idl.classes.acqinv.permacrud['delete'].perms )
                .concat( this.idl.classes.acqpro.permacrud.retrieve.perms )
            , true);

        this.needs_invoice_create_perm = !this.testFmPerm( 'acqinv', 'create', this.auth.user().ws_ou() );
        this.needs_invoice_view_perm = !this.testFmPerm( 'acqinv', 'retrieve', this.auth.user().ws_ou() );
    }

    testFmPerm(fmclass: string, action: string, org: number) {
        // console.log('InvoiceComponent, testFmPerm()',fmclass,action,org);
        if (!this.permissions) {
            console.warn('InvoiceComponent, testFmPerm, perms not initialized, returning false',
                fmclass,action,org);
            return false;
        }
        for (const perm of this.idl.classes[fmclass].permacrud[action].perms) {
            if (this.permissions[perm].includes(Number(org))) {
                // console.log('InvoiceComponent, testFmPerm, returning true',
                //    fmclass,action,org);
                return true;
            }
        }
        // console.log('InvoiceComponent, testFmPerm, returning false',fmclass,action,org);
        return false;
    }

    testReopenPerm() {
        const invoice = this.invoiceService.currentInvoice;
        const receiver = invoice && Number(this.idl.pkeyValue( invoice.receiver() ));
        if (!this.permissions) { return false; }
        if (!invoice.close_date()) { return false; }
        return this.permissions['ACQ_INVOICE_REOPEN'].includes( receiver );
    }

    needsContextPerm() {
        if (this.context === 'create') {
            return this.needs_invoice_create_perm;
        } else if (this.context === 'view') {
            return this.needs_invoice_view_perm;
        } else { return true; }
    }

    invoiceId(): number {
        return (this.invoiceService.currentInvoice && this.invoiceService.currentInvoice.id()) || null;
    }

    invoice(): IdlObject {
        return this.invoiceService.currentInvoice;
    }

    providerId(): number {
        if (this.invoice() && this.invoice().provider()) {
            return this.idl.pkeyValue( this.invoice().provider() );
        } else {
            return null;
        }
    }

    refresh(heavy = false) {
        console.debug('InvoiceComponent, refresh page');
        if (heavy) {
            location.href = location.href; // sledgehammer
        } else {
            this.router.navigateByUrl('/', {skipLocationChange: true}).then(() => {
                // this.router.navigate([decodeURI(this.location.path())]);
                if (this.invoiceService.currentInvoice.id()) {
                    this.router.navigate(['/staff/acq/invoice/' + this.invoiceService.currentInvoice.id()]);
                }
            });
        }
    }

    create_or_retrieve_invoice(segments: any[]) {
        this.route.queryParamMap.subscribe(queryParams => {

            const attachPoId = +queryParams.get('attach_po');
            this.attachedPoId = attachPoId;
            const usePoPrices = queryParams.has('po_prices');
            const attachLiIds = queryParams.getAll('attach_li').map(id => Number(id));

            if (segments[0].path === 'create') {
                this.context = 'create';
                this.invoiceService.createNewInvoice(attachPoId, attachLiIds, usePoPrices).then(result => {
                    console.debug('InvoiceComponent: newInvoice', result);
                    if (result) {
                        this.getFinalizablePoList();
                        this.loading = false;
                        // this.router.navigate( ['/staff/acq/invoice/' + this.invoiceService.currentInvoice.id()]);
                    } else {
                        console.error('InvoiceComponent: unable to create invoice');
                        this.errorText = $localize`Unable to create invoice.`;
                    }
                }, err => {
                    console.error('InvoiceComponent: unable to create invoice',err);
                    this.errorText = err;
                });
            } else {
                this.route.paramMap.subscribe((params: ParamMap) => {
                    this.context = 'view';
                    const invoiceId = +params.get('invoiceId');
                    if (invoiceId) {
                        this.invoiceService.getFleshedInvoice(invoiceId, {toCache: true}).then(
                            fleshedInvoice => {
                                console.debug('InvoiceComponent, fleshedInvoice', fleshedInvoice);
                                this.attachments(attachPoId, attachLiIds).then( _ => {
                                    this.getFinalizablePoList();
                                    this.loading = false;
                                    // if (attachPoId) {
                                    //    this.refresh();
                                    // } else {
                                    // just updates the URL in this case?
                                    // this.router.navigate(['/staff/acq/invoice/' + invoiceId]);
                                    // }
                                });
                            },
                            err => {
                                console.error('InvoiceComponent: unable to retrieve invoice',err);
                                this.errorText = err;
                            }
                        );
                    }
                });
            }
        });
    }

    async attachments(attachPoId: number, attachLiIds: number[]): Promise<any> {
        const lineitemSet = new Set(attachLiIds);
        let liIds: number[] = [];
        let po_items: IdlObject[] = [];

        if (attachPoId) {
            console.debug('InvoiceComponent, handling attachPoId', attachPoId);
            try {
                const po = await this.poService.getFleshedPo(attachPoId, {
                    fleshMore: {flesh_lineitem_ids: true, flesh_po_items: true}
                });
                console.debug('InvoiceComponent, fleshed po',po);
                po.lineitems().forEach((liId: number) => lineitemSet.add(liId));
                liIds = Array.from(lineitemSet);
                po_items = po.po_items();
            } catch (err) {
                console.error('InvoiceComponent, err',err);
                liIds = [];
            }
        } else {
            liIds = Array.from(lineitemSet);
        }

        console.debug('InvoiceComponent, attachments: liIds', liIds);
        console.debug('InvoiceComponent, attachments: po_items', po_items);
        if (liIds.length || po_items.length) {
            console.debug('InvoiceComponent, here we go...');
            await this.invoiceService.attachLiIdsAndPoItems(liIds, po_items);
        }
    }

    isFormDirty(): boolean {
        return this.invoiceDetails?.recordEditor?.fmEditForm?.dirty || false;
    }

    isFormInvalid(): boolean {
        return this.invoiceDetails?.duplicateInvIdentFound
        || this.invoiceDetails?.recordEditor?.fmEditForm?.invalid
        || false;
    }

    pro_save(): boolean {
        const isChanged = this.invoiceService.currentInvoice.ischanged();
        const isNew = this.invoiceService.currentInvoice.isnew();
        const pro_save_detailsPane = this.isFormDirty(); // this doesn't mark our model as ischanged
        const pro_save_liPane = (this.invoiceService.currentInvoice.entries() || []).some(
            (e: IdlObject) => e.isdeleted() || e.isnew() || e.ischanged() );
        const pro_save_chargesPane = this.invoiceCharges?.atLeastOneChargeIsChangedOrNewOrDeleted();
        return (pro_save_detailsPane || pro_save_liPane || pro_save_chargesPane || isChanged || isNew);
    }

    against_save(): boolean {
        const invoice = this.invoiceService.currentInvoice;
        const receiver = invoice && Number(this.idl.pkeyValue( invoice.receiver() ));
        const against_save_detailsPane = this.isFormInvalid();
        const against_save_liPane = false;
        const against_save_chargesPane = !this.invoiceCharges?.allChargesValid();
        const against_save_required_fields = !this.invoiceService.currentInvoice.inv_ident()
            || !invoice.receiver()
            || !invoice.provider()
            || !invoice.shipper()
            || !invoice.recv_date()
            || !invoice.recv_method();
        const against_save_perms = receiver
            && ( (invoice.isnew() && !this.testFmPerm('acqinv','create',receiver))
                || (invoice.ischanged() && !this.testFmPerm('acqinv','update',receiver))
            );
        return against_save_detailsPane
            || against_save_liPane
            || against_save_chargesPane
            || against_save_required_fields
            || against_save_perms
            || invoice.close_date();
    }

    isSafeToSaveInvoice(): boolean {
        return this.invoiceService.currentInvoice && this.pro_save() && !this.against_save();
    }

    canDeactivate(): boolean {
        this.angularNavigation = true;
        if(this.pro_save()) {
            return window.confirm($localize`You have unsaved changes. Do you want to navigate away?`);
        } else {
            return true;
        }
    }

    isSafeToCloseInvoice(): boolean {
        if (!this.invoiceService.currentInvoice) { return false; }
        if (!this.invoiceDetails) { return false; }
        const epsilon = 0.00001; // the joy of floating point numbers
        const balanced = Math.abs(this.invoiceDetails?.uiTotalPaid - this.invoiceDetails?.uiTotalCost) < epsilon;
        return !this.invoiceService.currentInvoice.close_date() && balanced;
    }

    isSafeToSaveAndClear() {
        return !this.against_save();
    }

    isSafeToSaveAndCloseInvoice() {
        return this.isSafeToCloseInvoice() && !this.against_save();
    }

    isSafeToSaveAndProrateInvoice(): boolean {
        return this.isSafeToProrateInvoice() && !this.against_save();
    }

    isSafeToProrateInvoice(): boolean {
        if (!this.invoiceService.currentInvoice) { return false; }
        return true;
    }

    continuePastUnsetPricesWarning(): boolean {
        if ((this.invoiceService.currentInvoice.entries() || []).some(
            (e: IdlObject) => e.amount_paid() === '' || e.cost_billed() === '')) {
            return window.confirm($localize`Some invoice entry prices are unset; continue anyway?`);
        } else {
            return true;
        }
    }

    async prorateInvoice(): Promise<boolean> {
        return this._prorateInvoice().then( result => {
            console.debug('InvoiceComponent, prorateInvoice', result);
            if (result) {
                this.invoiceService.changeNotify();
                this.invoiceDetails.updateFundSummary();
            }
            return result;
        });
    }

    async _prorateInvoice(): Promise<boolean> {
        try {
            if (!this.isSafeToProrateInvoice()) { return false; }
            return this.invoiceService.prorateInvoice();
        } catch(E) {
            window.alert( $localize`Error closing invoice` );
            console.log('InvoiceComponent, _closeInvoice, error', E);
            return false;
        }
    }

    async saveAndProrateInvoice(): Promise<void> {
        if (!this.continuePastUnsetPricesWarning()) { return; }
        if (this.pro_save()) {
            if (!this.against_save()) {
                const saveResult = await this.saveInvoice();
                if (saveResult) {
                    await this.prorateInvoice();
                }
            }
        } else {
            await this.prorateInvoice();
        }
    }

    async saveAndCloseInvoice(): Promise<void> {
        if (!this.continuePastUnsetPricesWarning()) { return; }
        if (this.pro_save()) {
            if (!this.against_save()) {
                const saveResult = await this.saveInvoice();
                if (saveResult) {
                    this.closeInvoice();
                }
            }
        } else {
            this.closeInvoice();
        }
    }

    closeInvoice() {
        this._closeInvoice().then( result => {
            console.debug('InvoiceComponent, closeInvoice', result);
            if (result) {
                this.acqInvoiceTabs.select('main');
                this.invoiceService.changeNotify();
                this.invoiceDetails.recordEditor.mode = 'view';
                this.invoiceDetails.recordEditor.handleRecordChange();
                this.invoiceDetails.updateSummary(this.invoice());
            }
        });
    }

    async _closeInvoice(): Promise<boolean> {
        try {
            if (!this.isSafeToCloseInvoice()) { return; }
            return this.invoiceService.closeInvoice();
        } catch(E) {
            window.alert( $localize`Error closing invoice` );
            console.log('InvoiceComponent, _closeInvoice, error', E);
            return false;
        }
    }

    reopenInvoice() {
        this._reopenInvoice().then( result => {
            console.debug('InvoiceComponent, reopenInvoice', result);
            if (result) {
                this.invoiceService.changeNotify();
                this.invoiceDetails.recordEditor.mode = 'update';
                this.invoiceDetails.recordEditor.handleRecordChange();
                this.invoiceDetails.updateSummary(this.invoice());
            }
        });
    }

    async _reopenInvoice(): Promise<boolean> {
        try {
            return this.invoiceService.reopenInvoice();
        } catch(E) {
            window.alert( $localize`Error closing invoice` );
            console.log('InvoiceComponent, _reopenInvoice, error', E);
            return false;
        }
    }

    async saveInvoice(): Promise<boolean> {
        if (!this.invoiceService.currentInvoice) { return false; }
        if (!this.continuePastUnsetPricesWarning()) { return false; }
        const wasNew = this.invoiceService.currentInvoice.isnew();
        return this._saveInvoice().then( result => {
            console.debug('InvoiceComponent, saveInvoice', result);
            if (result) {
                this.invoiceDetails.recordEditor.fmEditForm.form.markAsPristine();
                this.invoiceDetails.recordEditor.fmEditForm.form.markAsUntouched();
                this.invoiceDetails.updateSummary(this.invoice());
                this.invoiceCharges.resetBatch();
                if (wasNew) {
                    this.refresh(false);
                    this.invoiceEntries.load();
                    console.debug('phasefx got here');
                }
            }
            return result;
        });
    }

    async _saveInvoice(): Promise<boolean> {
        function unhandled_error(err,log_trace: any = '') {
            window.alert( $localize`Error saving invoice: ` + err);
            console.error('InvoiceComponent, _saveInvoice, error', log_trace, err);
        }
        try {
            if (!this.isSafeToSaveInvoice()) { return false; }
            // finalizeThese: { [key: number]: boolean };
            const poIds = [];
            Object.keys(this.finalizeThese).forEach( poId => {
                if (this.finalizeThese[poId]) {
                    poIds.push(Number(poId));
                }
            });
            return this.invoiceService.updateInvoice({'finalizeablePoIds': poIds}).catch(E => {
                try {
                    const evt = this.evt.parse(E);
                    if (evt) {
                        if (evt.textcode == 'ACQ_FUND_EXCEEDS_STOP_PERCENT'
                            || evt.textcode == 'ACQ_FUND_EXCEEDS_WARN_PERCENT') {
                            let funds;
                            try {
                                funds = evt.payload.tuples.map(
                                    tuple => tuple.fund.name() + ' (' + tuple.fund.code() + ')').join(', ');
                            } catch(F) {
                                funds = $localize`Error determining fund.`;
                                console.error('InvoiceComponent, _saveInvoice, ', funds, F);
                            }
                            const msg = evt.textcode == 'ACQ_FUND_EXCEEDS_STOP_PERCENT'
                                ? $localize`The following funds exceed their Balance Stop Percent threshold: `
                                : $localize`The following funds exceed their Balance Warn Percent threshold: `;
                            window.alert( msg + funds);
                        } else {
                            unhandled_error(E, 1);
                        }
                    } else {
                        unhandled_error(E, 1);
                    }
                    return false;
                } catch(G) {
                    console.error('invoiceComponent, invoiceService, updateInvoice. Hrmm',G);
                }
            });
        } catch(E) {
            unhandled_error(E, 2);
            window.alert( $localize`Error saving invoice` );
            console.error('InvoiceComponent, 2: _saveInvoice, error', E);
            return false;
        }
    }

    async onNewInvoiceClick(): Promise<void> {
        if (this.pro_save()) {
            if (!this.against_save()) {
                if (!this.continuePastUnsetPricesWarning()) { return; }
                const saveResult = await this.saveInvoice();
                if (saveResult) {
                    this.router.navigateByUrl('/staff/acq/invoice/create');
                }
            }
        } else {
            this.router.navigateByUrl('/staff/acq/invoice/create');
        }
    }

    private beforeUnloadHandler(event: BeforeUnloadEvent): void {
        if (this.angularNavigation) {
            this.angularNavigation = false;
            return;
        }
        if (this.pro_save()) {
            event.preventDefault();
            event.returnValue = true;
        }
    }

    ngOnDestroy() {
        window.removeEventListener('beforeunload', this.beforeUnloadHandler.bind(this));
        if (this.invoiceEntrySubscription) {
            this.invoiceEntrySubscription.unsubscribe();
        }
    }

    isBasePage(): boolean {
        return !this.route.firstChild ||
            this.route.firstChild.snapshot.url.length === 0;
    }

    toggleFmEditor() {
        this.showFmEditor = !this.showFmEditor;
    }

    linkFromSearch = (rows: IdlObject[], lineitemResults: LineitemResultsComponent) => {
        console.debug('InvoiceComponent: linkFromSearch', rows, lineitemResults);
        const acqSearchForm = lineitemResults.acqSearchForm;
        const liIds: number[] = rows.map( r => r.id() );
        if (liIds.length === 0) { return; }
        this.invoiceService.attachLiIdsAndPoItems(liIds, []).then(
            () => {
                if (acqSearchForm && acqSearchForm.filterOutTheseLiIds) {
                    acqSearchForm.filterOutTheseLiIds( liIds );
                }
                acqSearchForm.submitSearch();
                console.debug('InvoiceComponent, linkFromSearch, finis', this);
            }
        );
    };

    async getFinalizablePoList(): Promise<number[]> {
        const items = this.invoiceService.currentInvoice?.items() || [];
        console.debug('InvoiceComponent: getFinalizablePoList, items = ', items);
        if (!items.length) {return [];}

        await this.invoiceService.initialize();
        console.debug('InvoiceComponent: getFinalizablePoList, invItemTypeMap = ',this.invoiceService.invItemTypeMap);
        const poSet = new Set();
        items.filter( (i: IdlObject) => this.invoiceService.invItemTypeMap[i.inv_item_type()].blanket() === 't' )
            .forEach( (i: IdlObject) => { poSet.add( this.idl.pkeyValue( i.purchase_order() ) ); });
        const poList = Array.from(poSet);
        console.debug('InvoiceComponent: getFinalizablePoList, interim poList = ', poList);

        if (poList.length) {
            const pcrudObservable = this.pcrud.search('acqpo', { id: poList, state: { '!=': 'received'}},
                {}, {idlist: true, atomic: true});
            const finalizable = await firstValueFrom(pcrudObservable);
            this.finalizablePoList = finalizable;
        } else {
            this.finalizablePoList = [];
        }
        console.debug('InvoiceComponent: getFinalizablePoList, final list = ', this.finalizablePoList);
        return this.finalizablePoList;
    }

    finalizeBlanketOrders() {
        // finalizeThese: { [key: number]: boolean };
        const poIds = [];
        Object.keys(this.finalizeThese).forEach( poId => {
            if (this.finalizeThese[poId]) {
                poIds.push(Number(poId));
            }
        });
        this.invoiceService.finalizeBlanketOrders(poIds).then(
            _ => {
                console.debug('InvoiceComponent, finalizeBlanketOrders, no errors');
                this.invoiceService.refresh().then( invoice => {
                    console.debug('InvoiceComponent, refreshed invoice', invoice);
                    this.refresh();
                });
            },
            error => { console.error('InvoiceComponent, finalizeBlanketOrders', error); }
        );
    }
}

