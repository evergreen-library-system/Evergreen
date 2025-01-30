/* eslint-disable */
import {Injectable, EventEmitter} from '@angular/core';
import {IdlService, IdlObject} from '@eg/core/idl.service';
import {EventService} from '@eg/core/event.service';
import {NetService} from '@eg/core/net.service';
import {AuthService} from '@eg/core/auth.service';
import {PcrudService} from '@eg/core/pcrud.service';
import {LineitemService, FleshCacheParams, BatchLineitemStruct} from '@eg/staff/acq/lineitem/lineitem.service';
import {PoService} from '@eg/staff/acq/po/po.service';
import {Subject} from 'rxjs';
import * as moment from 'moment-timezone';
import {toArray, throwError, forkJoin, firstValueFrom, lastValueFrom, Observable} from 'rxjs';
import {map, catchError} from 'rxjs/operators';

export interface InvoiceDupeCheckResults {
    dupeFound: boolean;
    dupeInvoiceId: number;
}

interface UpdateInvoiceOptions {
    finalizeablePoIds?: number[];
    set_current_invoice?: boolean;
    dry_run?: boolean;
    override?: boolean;
}

@Injectable()
export class InvoiceService {

    currentInvoice: IdlObject; // this may be a new or pending changes invoice

    newFakeId = -1; // this is for referring to specific things that don't have real ids yet

    invItemTypes: IdlObject[] = [];
    invItemTypeMap: { [key: string]: IdlObject } = {};

    private invoiceEntrySubject = new Subject<void>();
    private invoiceItemSubject = new Subject<void>();
    private invoiceSubject = new Subject<void>();
    invoiceEntryChange$ = this.invoiceEntrySubject.asObservable();
    invoiceItemChange$ = this.invoiceItemSubject.asObservable();
    invoiceChange$ = this.invoiceSubject.asObservable();

    invoiceRetrieved: EventEmitter<IdlObject> = new EventEmitter<IdlObject>();

    constructor(
        private evt: EventService,
        private net: NetService,
        private pcrud: PcrudService,
        private auth: AuthService,
        private poService: PoService,
        private liService: LineitemService,
        private idl: IdlService,
    ) {
        console.debug('InvoiceService',this);
    }

    async initialize() {
        const invItemTypeObservable = this.pcrud.retrieveAll('aiit',{},{atomic: true});
        this.invItemTypes = await firstValueFrom(invItemTypeObservable);
        this.invItemTypeMap = this.invItemTypes.reduce(
            (map: { [key: string]: IdlObject }, itemType: IdlObject) => {
                const code = itemType.code();
                map[code] = itemType;
                return map;
            }, {});
    }

    updateInvoiceEntry(invoiceEntry: IdlObject) {
        // just the in-memory version of currentInvoice
        console.debug('updateInvoiceEntry', invoiceEntry);
        const entries = (this.currentInvoice.entries() || [])
            .filter( (e: IdlObject) => e.id() !== invoiceEntry.id() );
        this.currentInvoice.entries( entries.concat( [ invoiceEntry ] ) );
        this.currentInvoice.ischanged(true);
        this.invoiceEntrySubject.next();
        this.invoiceSubject.next();
    }

    updateInvoiceItem(invoiceItem: IdlObject) {
        // may need to go through the invoice update function
        console.debug('InvoiceService, updateInvoiceItem',invoiceItem);
        let method = 'update';
        try {
            if (invoiceItem.isnew()) {
                invoiceItem.id(undefined);
                method = 'create';
            }
        } catch(E) {
            throw Error(E);
        }

        this.pcrud[method](invoiceItem).subscribe((resp: any) => {
            console.debug('InvoiceService, ' + method + 'InvoiceItem',invoiceItem);
            const evt = this.evt.parse(resp);
            if (evt) {
                console.log(method + 'InvoiceItem, failed',evt);
                alert(evt); // TODO: better error handling
            } else {
                // pcrud.update should return 1 if not an ils_event
                console.debug(method + 'InvoiceItem, success',resp);
                // invoiceItem.isnew(false); invoiceItem.ischanged(false);
                this.invoiceItemSubject.next();
                this.refresh();
            }
        });
    }

    async refresh(): Promise<boolean> {
        if (this.currentInvoice) {
            if (this.currentInvoice.ischanged() || this.currentInvoice.isnew()) {
                console.warn('InvoiceService, refresh() denied because of new or changed currentInvoice');
                return false;
            }
            await this.getFleshedInvoice( this.currentInvoice.id(), { toCache: true } );
        } else {
            console.warn('InvoiceService, refresh() but no current invoice is set');
            return false;
        }
    }

    getFleshedInvoice(id: number, params: FleshCacheParams = {}): Promise<IdlObject> {
        console.error('InvoiceService, getFleshedInvoice', id, params);

        return new Promise<IdlObject>((resolve, reject) => {
            if (params.fromCache) {
                if (this.currentInvoice && id === this.currentInvoice.id()) {
                    // Set invoiceService.currentInvoice = null to bypass the cache
                    this.currentInvoice._x_from_cache = true; // for debugging
                    return resolve(this.currentInvoice);
                }
            }

            if (params.toCache && this.currentInvoice && (this.currentInvoice.isnew() || this.currentInvoice.ischanged)) {
                console.warn('InvoiceService: discarding changes to currentInvoice', this.currentInvoice);
            }

            this.net.request(
                'open-ils.acq',
                'open-ils.acq.invoice.fleshed.retrieve',
                this.auth.token(), id
            ).subscribe({
                next: invoice => {
                    const evt = this.evt.parse(invoice);
                    if (evt) {
                        console.warn('ILSEvent returned instead of invoice',evt);
                        return reject(evt + '');
                    }
                    invoice._x_method = 'open-ils.acq.invoice.fleshed.retrieve'; // for debugging

                    if (params.toCache) {
                        console.debug('1: InvoiceService, set currentInvoice to', invoice);
                        this.currentInvoice = invoice;
                    } else {
                        console.debug('1: InvoiceService, not setting currentInvoice to', invoice);
                        console.debug('1: currentInvoice is currently', this.currentInvoice);
                    }

                    this.invoiceRetrieved.emit(invoice);
                    resolve(invoice);
                },
                error: (error: unknown) => {
                    console.warn('InvoiceService, error retrieving invoice',error);
                    reject(error);
                }
            });
        });
    }

    async checkDuplicateInvoiceVendorIdent(invoiceId: number, invoiceVendorIdent: string): Promise<any[]> {
        try {
            const pcrudObservable = this.pcrud.search('acqinv',
                { id: { '!=': (invoiceId||-1) }, inv_ident: invoiceVendorIdent },
                {}, { idlist: true, atomic: true }
            );
            return firstValueFrom( pcrudObservable );
        } catch(E) {
            console.error('InvoiceService, checkDuplicateInvoiceVendorIdent, error', E);
            return [];
        }
    }

    randomString(): string {
        return (Math.random() * 1e32).toString(36);
    }

    createInvoiceItem(po_item: IdlObject, use_po_prices = true): IdlObject {
        const item = this.idl.create('acqii');
        item.isnew(true);
        item.id(this.newFakeId--);
        item.fund(po_item.fund());
        item.title(po_item.title());
        item.author(po_item.author());
        item.note(po_item.note());
        item.inv_item_type(po_item.inv_item_type());
        item.purchase_order(po_item.purchase_order());
        item.po_item(po_item.id());
        const estimated_cost = Number(po_item.estimated_cost()) || 0.00;
        if (use_po_prices) {
            // console.warn('actually using the po prices');
            item.cost_billed( estimated_cost );
            item.amount_paid( estimated_cost );
        } else {
            // console.warn('not actually using the po prices');
            const blanket = this.invItemTypeMap[po_item.inv_item_type()]?.blanket() === 't';
            if (blanket) {
                // console.warn('except this is a blanket charge, so we are');
                item.cost_billed( estimated_cost );
                item.amount_paid( estimated_cost );
            } else {
                // leaving unset
            }
        }
        return item;
    }

    async createNewInvoice(po_id: number, lineitem_ids: number[], use_po_prices = false): Promise<boolean> {
        try {
            console.debug('InvoiceService, createNewInvoice(...)', po_id, use_po_prices, lineitem_ids);
            const lineitemSet = new Set(lineitem_ids);

            this._createInvoice();
            this.currentInvoice._x_just_created = true; // for debugging

            const new_items = [];
            if (po_id) {
                const purchase_order = await this.poService.getFleshedPo(po_id, { fleshMore: { flesh_lineitems: true, flesh_lineitem_details: true } });
                console.debug('InvoiceService, createNewInvoice, getFleshedPo',purchase_order);
                this.currentInvoice.provider( purchase_order.provider() );
                this.currentInvoice.shipper( purchase_order.provider() );
                this.currentInvoice.receiver( purchase_order.ordering_agency() );
                purchase_order.lineitems()?.forEach( (li: IdlObject) => lineitemSet.add( li.id() ) );
                purchase_order.po_items()?.forEach( (po_item: IdlObject) => {
                    const item = this.createInvoiceItem(po_item, use_po_prices);
                    new_items.push(item);
                });
            }
            this.currentInvoice.items( new_items );

            const new_entries = await this._attachLiIds(Array.from(lineitemSet), use_po_prices);
            this.currentInvoice.entries( new_entries );

            if (new_entries.length > 0 && (!this.currentInvoice.provider() || !this.currentInvoice.shipper())) {
                console.debug('InvoiceService, createNewInvoice, setting invoice provider/shipper via lineitem');
                this.currentInvoice.provider( this.currentInvoice.provider() || new_entries[0].lineitem()?.provider()?.id() );
                this.currentInvoice.shipper( this.currentInvoice.shipper() || new_entries[0].lineitem()?.provider()?.id() );
            } else {
                console.debug('InvoiceService, createNewInvoice, not setting invoice provider/shipper via lineitem');
            }

            return true;
        } catch(E) {
            console.log('InvoiceService, createNewInvoice error',E);
            return false;
        }
    }

    async finalizeBlanketOrders(poIds: number[] = []): Promise<boolean> {
        // return this._touchInvoiceInDb(this.currentInvoice, [], [], poIds);
        console.debug('InvoiceService, finalizeBlanketOrders, poIds =', poIds);
        try {
            let pass = 0; let fail = 0;
            for (const poId of poIds) {
                const observable = this.net.request(
                    'open-ils.acq',
                    'open-ils.acq.purchase_order.blanket.finalize',
                    this.auth.token(), poId
                );
                const result = await firstValueFrom(observable);
                if (result === '1') {
                    console.debug('InvoiceService, finalizeBlanketOrder successful');
                    pass += 1;
                } else {
                    console.error('InvoiceService, finalizeBlanketOrders failed',result);
                    fail += 1;
                }
            }
            console.debug('InvoiceService, finalizaBlanketOrder pass/fail',pass,fail);
            return fail === 0;
        } catch(E) {
            console.error('InvoiceService, error finalizing blanket orders',E);
            return false;
        }
    }

    changeNotify() {
        this.invoiceSubject.next();
    }

    async updateInvoice(options: UpdateInvoiceOptions = {}): Promise<boolean> {
        console.debug('InvoiceService, updateInvoice', options);
        const { finalizeablePoIds = [], set_current_invoice = true, dry_run = false, override = false, } = options;
        const result = await this._touchInvoiceInDb(
            this.currentInvoice,
            this.currentInvoice.items() || [],
            this.currentInvoice.entries() || [],
            finalizeablePoIds,
            set_current_invoice,
            dry_run,
            override);
        this.invoiceSubject.next();
        return result;
    }

    _touchInvoiceInDb(invoice: IdlObject, items: IdlObject[], entries: IdlObject[], finalizablePoIds: number[] = [], setCurrentInvoice = true, dry_run = false, override = false): Promise<boolean> {

        console.debug('InvoiceService, _touchInvoiceInDb(...)',
            'invoice', invoice,
            'items', items,
            'entries', entries,
            'finalizablePoIds', finalizablePoIds,
            'setCurrentInvoice', setCurrentInvoice,
            'dry_run', dry_run,
            'override', override);

        // otherwise we _will_ get negative ID's in the database
        items = items.map( i => { if (i.isnew()) { i.id(null); } return i; });
        entries = entries.map( e => { if (e.isnew()) { e.id(null); } return e; });

        // convert empty string to null for invoice_entry prices
        entries = entries.map( e => { if (e.cost_billed() === '') { e.cost_billed(null); } return e; });
        entries = entries.map( e => { if (e.actual_cost() === '') { e.actual_cost(null); } return e; });
        entries = entries.map( e => { if (e.amount_paid() === '') { e.amount_paid(null); } return e; });

        // deflesh lineitems
        entries = entries.map(e => {
            if (typeof e.lineitem() === 'object') {
                e.lineitem( e.lineitem().id() );
            }
            return e;
        });

        return new Promise((resolve, reject) => {
            this.net.request(
                'open-ils.acq',
                override
                    ? 'open-ils.acq.invoice.update.fleshed.override'
                    : (dry_run
                        ? 'open-ils.acq.invoice.update.fleshed.dry_run'
                        : 'open-ils.acq.invoice.update.fleshed'),
                this.auth.token(), invoice, entries, items, finalizablePoIds
            ).subscribe({
                next: invoice => {
                    const evt = this.evt.parse(invoice);
                    console.debug('InvoiceService, update.fleshed returned',evt);
                    if (evt) {
                        console.warn('InvoiceService: ILSEvent returned instead of invoice',evt);
                        reject(evt);
                    } else {
                        invoice._x_method = override
                            ? 'open-ils.acq.invoice.update.fleshed.override'
                            : 'open-ils.acq.invoice.update.fleshed'; // for debugging
                        if (setCurrentInvoice) {
                            console.debug('3: InvoiceService, set currentInvoice to', invoice);
                            this.currentInvoice = invoice;
                        } else {
                            console.debug('3: InvoiceService, not setting currentInvoice to', invoice);
                            console.debug('3: InvoiceService, currentInvoice is currently', this.currentInvoice);
                        }
                        console.debug('3: InvoiceService, currentInvoice.isnew()',this.currentInvoice.isnew());
                        this.invoiceRetrieved.emit(invoice);
                        resolve(true);
                    }
                },
                error: (error: unknown) => {
                    console.warn('InvoiceService: error retrieving invoice',error);
                    reject(error);
                }
            });
        });
    }

    _createInvoice() {
        this.currentInvoice = this.idl.create('acqinv');
        this.currentInvoice.isnew(true);
        this.currentInvoice.recv_method('PPR');
        this.currentInvoice.recv_date(moment().toDate().toISOString());
        this.currentInvoice.receiver(this.auth.user().ws_ou());
    }

    async attachLiIdsAndPoItems(lineitem_ids: number[], po_items: IdlObject[], use_po_prices = false): Promise<void> {
        console.debug('InvoiceService, attachLiIdsAndPoItems(..)',lineitem_ids,po_items,use_po_prices);
        if (lineitem_ids.length === 0 && po_items.length === 0) {
            return null;
        }

        if (!this.currentInvoice) {
            console.error('InvoiceService: attachLiIdsAndPoItems() with no currentInvoice');
            return null;
        }

        const existing_entries = this.currentInvoice.entries() || [];
        const existing_items = this.currentInvoice.items() || [];
        const new_entries = await this._attachLiIds(lineitem_ids, use_po_prices);
        const new_items = po_items.map( po_item => {
            this.createInvoiceItem(po_item, use_po_prices);
        });
        this.currentInvoice.entries( existing_entries.concat( new_entries ) );
        this.currentInvoice.items( existing_items.concat( new_items ) );

        if (lineitem_ids.length > 0 && (!this.currentInvoice.provider() || !this.currentInvoice.shipper())) {
            console.debug('InvoiceService, attachLiIdsAndPoItems, setting invoice provider/shipper via lineitem');
            // just fleshing the first lineitem here so we can use its provider for the invoice
            const lineitemsObservable = this.liService.getFleshedLineitems([ lineitem_ids[0] ]);
            const lineitems: IdlObject[] = (await lastValueFrom(lineitemsObservable.pipe(toArray()))).map(
                (item: BatchLineitemStruct) => item.lineitem
            );

            this.currentInvoice.provider( this.currentInvoice.provider() || lineitems[0]?.provider()?.id() );
            this.currentInvoice.shipper( this.currentInvoice.shipper() || lineitems[0]?.provider()?.id() );
        } else {
            console.debug('InvoiceService, attachLiIdsAndPoItems, not setting invoice provider/shipper via lineitem');
        }
    }

    async _attachLiIds(lineitem_ids: number[], use_po_prices = false): Promise<IdlObject[]> {
        console.debug('invoice.service, _attachLiIds', lineitem_ids, use_po_prices);
        const lineitemSet = new Set(lineitem_ids);
        const lineitemsObservable = this.liService.getFleshedLineitems(Array.from(lineitemSet));
        const lineitems: IdlObject[] = (await lastValueFrom(lineitemsObservable.pipe(toArray()))).map(
            (item: BatchLineitemStruct) => item.lineitem
        );
        console.debug('getFleshedLineitems',lineitems);

        const entries = [];
        lineitems?.forEach( li => {
            const entry = this.idl.create('acqie');
            if (this.currentInvoice.id()) {
                entry.invoice(this.currentInvoice.id());
            }
            entry.isnew(true);
            entry.id(this.newFakeId--);
            entry.lineitem(li);
            if (!li.purchase_order()) {
                console.warn('Not creating invoice entry for lineitem ' + li.id() + ' for lack of a PO');
                return; // we should only link lineitems attached to POs
            }
            entry.purchase_order(li.purchase_order());
            // by default, attempt to pay for all non-canceled and as-of-yet-un-invoiced items
            const count = Number(li.order_summary().item_count() || 0) -
                        Number(li.order_summary().cancel_count() || 0) -
                       Number(li.order_summary().invoice_count() || 0);
            entry.phys_item_count(count);
            entry.inv_item_count(count);
            if (/* use_po_prices &&*/ !isNaN(Number(li.estimated_unit_price()))) {
                entry.cost_billed( (li.estimated_unit_price() * count * 100) / 100 );
                entry.amount_paid( (li.estimated_unit_price() * count * 100) / 100 );
            }
            entries.push(entry);
        });
        return entries;
    }

    async prorateInvoice(): Promise<boolean> {
        if (!this.currentInvoice) {
            console.error('InvoiceService: prorateInvoice() with no currentInvoice');
            return false;
        }
        try {
            const prorateObservable = this.net.request(
                'open-ils.acq', 'open-ils.acq.invoice.apply_prorate',
                this.auth.token(), this.currentInvoice.id());
            const resp = await firstValueFrom(prorateObservable);
            console.debug('InvoiceService, prorateInvoice returned', resp);
            const evt = this.evt.parse(resp);
            if (evt) {
                throw(evt);
            } else {
                console.debug('InvoiceService, setting currentInvoice from prorate');
                this.currentInvoice = resp;
            }
            return true;
        } catch(E) {
            console.error('InvoiceService, prorateInvoice error', E);
            alert(E); // TODO: better error handling
            return false;
        }
    }

    async closeInvoice(): Promise<boolean> {
        if (!this.currentInvoice) {
            console.error('InvoiceService: closeInvoice() with no currentInvoice');
            return false;
        }
        this.currentInvoice.close_date('now');
        this.currentInvoice.closed_by(this.auth.user().id());
        this.currentInvoice.ischanged(true);
        return this.updateInvoice();
    }

    async reopenInvoice(): Promise<boolean> {
        if (!this.currentInvoice) {
            console.error('InvoiceService: reopenInvoice() with no currentInvoice');
            return false;
        }
        this.currentInvoice.close_date(null);
        // this.currentInvoice.closed_by(null); // the dojo version leaves closed_by alone
        this.currentInvoice.ischanged(true);
        return this.updateInvoice();
    }

    getFundSummary(fundId: number): Promise<any> {
        return new Promise<IdlObject>((resolve, reject) => {
            this.net.request(
                'open-ils.acq',
                'open-ils.acq.fund.summary.retrieve',
                this.auth.token(), fundId
            ).subscribe({
                next: summary => {
                    console.debug('InvoiceService, getFundSummary',summary);
                    const evt = this.evt.parse(summary);
                    if (evt) {
                        console.warn('InvoiceService, getFundSummary, ILSEvent returned instead of summary',evt);
                        return reject(evt + '');
                    }
                    resolve(summary);
                },
                error: (error: unknown) => {
                    console.warn('InvoiceService, getFundSummary, error retrieving summary',error);
                    reject(error);
                }
            });
        });
    }

    getInvFundSummary(inv_id: number): Promise<any> {

        return new Promise<IdlObject>((resolve, reject) => {
            this.net.request(
                'open-ils.acq',
                'open-ils.acq.invoice.fund_summary',
                this.auth.token(), inv_id
            ).subscribe({
                next: summary => {
                    console.debug('InvoiceService, getInvFundSummary',summary);
                    const evt = this.evt.parse(summary);
                    if (evt) {
                        console.warn('InvoiceService, getInvFundSummary, ILSEvent returned instead of summary',evt);
                        return reject(evt + '');
                    }
                    resolve(summary);
                },
                error: (error: unknown) => {
                    console.warn('InvoiceService, getInvFundSummary, error retrieving summary',error);
                    reject(error);
                }
            });
        });
    }

    checkAmountAgainstFund(fundId: number, amount: number): Observable<any> {
        console.debug('InvoiceService, checkAmountAgainstFund',fundId,amount);
        return this.net.request(
            'open-ils.acq',
            'open-ils.acq.fund.check_balance_percentages',
            this.auth.token(), fundId, amount
        ).pipe(
            map(([stop, warn]) => ({fundId, stop, warn}))
        );
    }

    checkAmountAgainstFunds(fundIds: number[], amount: number): Observable<any> {
        console.debug('InvoiceService, checkAmountAgainstFunds',fundIds,amount);
        if (!fundIds.length) {
            const error_msg = 'InvoiceService, checkAmountAgainstFunds, empty fund list';
            console.error(error_msg);
            return throwError(() => new Error(error_msg));
        }

        const observables = fundIds.map(fundId => this.checkAmountAgainstFund(fundId, amount));

        // this will wait for all Observables to complete
        return forkJoin(observables).pipe(
            catchError((error: unknown) => {
                console.error('checkAmountsAgainstFunds, error',error);
                return throwError(() => error);
            })
        );
    }

    defleshInvoice() {
        if (this.currentInvoice.shipper()) {
            this.currentInvoice.shipper( this.idl.pkeyValue( this.currentInvoice.shipper() ) );
        }
        if (this.currentInvoice.provider()) {
            this.currentInvoice.provider( this.idl.pkeyValue( this.currentInvoice.provider() ) );
        }
        if (this.currentInvoice.closed_by()) {
            this.currentInvoice.closed_by( this.idl.pkeyValue( this.currentInvoice.closed_by() ) );
        }
    }
}



