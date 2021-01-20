import {Injectable, EventEmitter} from '@angular/core';
import {Observable, from, concat, empty} from 'rxjs';
import {switchMap, map, tap, merge} from 'rxjs/operators';
import {IdlObject, IdlService} from '@eg/core/idl.service';
import {NetService} from '@eg/core/net.service';
import {AuthService} from '@eg/core/auth.service';
import {PcrudService} from '@eg/core/pcrud.service';
import {ComboboxEntry} from '@eg/share/combobox/combobox.component';
import {ItemLocationService} from '@eg/share/item-location-select/item-location-select.service';

const COPY_ORDER_DISPOSITIONS:
    'canceled' | 'delayed' | 'received' | 'on-order' | 'pre-order' = null;
export type COPY_ORDER_DISPOSITION = typeof COPY_ORDER_DISPOSITIONS;

export interface BatchLineitemStruct {
    id: number;
    lineitem: IdlObject;
    existing_copies: number;
    all_locations: IdlObject[];
    all_funds: IdlObject[];
    all_circ_modifiers: IdlObject[];
}

export interface BatchLineitemUpdateStruct {
    lineitem: IdlObject;
    lid: number;
    max: number;
    progress: number;
    complete: number; // Perl bool
    total: number;
    [key: string]: any; // Perl Acq::BatchManager
}

interface FleshedLineitemParams {

    // Flesh data beyond the default.
    fleshMore?: any;

    // OK to pull the requested LI from the cache.
    fromCache?: boolean;

    // OK to add this LI to the cache.
    // Generally a good thing, but if you are fetching an LI with
    // fewer fleshed fields than the default, this could break code.
    toCache?: boolean;
}

@Injectable()
export class LineitemService {

    liAttrDefs: IdlObject[];

    // Emitted when our copy batch editor wants to apply a value
    // to a set of inputs.  This allows the the copy input comboboxes, etc.
    // to add the entry before it's forced to grab the value from the
    // server, often in large parallel batches.
    batchOptionWanted: EventEmitter<{[field: string]: ComboboxEntry}>
        = new EventEmitter<{[field: string]: ComboboxEntry}> ();

    // Emits a LI ID if the LI was edited in a way that could impact
    // its activatability of its linked PO.
    activateStateChange: EventEmitter<number> = new EventEmitter<number>();

    // Cache for circ modifiers and funds; locations are cached in the
    // item location select service.
    circModCache: {[code: string]: IdlObject} = {};
    fundCache: {[id: number]: IdlObject} = {};
    liCache: {[id: number]: BatchLineitemStruct} = {};

    // Alerts the user has already confirmed are OK.
    alertAcks: {[id: number]: boolean} = {};

    constructor(
        private idl: IdlService,
        private net: NetService,
        private auth: AuthService,
        private pcrud: PcrudService,
        private loc: ItemLocationService
    ) {}

    getFleshedLineitems(ids: number[],
        params: FleshedLineitemParams = {}): Observable<BatchLineitemStruct> {

        if (params.fromCache) {
            const fromCache = this.getLineitemsFromCache(ids);
            if (fromCache) { return from(fromCache); }
        }

        const flesh: any = Object.assign({
            flesh_attrs: true,
            flesh_provider: true,
            flesh_order_summary: true,
            flesh_cancel_reason: true,
            flesh_li_details: true,
            flesh_notes: true,
            flesh_fund: true,
            flesh_circ_modifier: true,
            flesh_location: true,
            flesh_fund_debit: true,
            flesh_po: true,
            flesh_pl: true,
            flesh_formulas: true,
            flesh_copies: true,
            clear_marc: false
        }, params.fleshMore || {});

        return this.net.request(
            'open-ils.acq', 'open-ils.acq.lineitem.retrieve.batch',
            this.auth.token(), ids, flesh
        ).pipe(tap(liStruct =>
            this.ingestLineitem(liStruct, params.toCache)));
    }

    getLineitemsFromCache(ids: number[]): BatchLineitemStruct[] {

        const fromCache: BatchLineitemStruct[] = [];

        ids.forEach(id => {
            if (this.liCache[id]) { fromCache.push(this.liCache[id]); }
        });

        // Only return LI's from cache if all of the requested LI's
        // are cached, otherwise they would be returned in the wrong
        // order.  Typically it will be all or none so I'm not
        // fussing with interleaving cached and uncached lineitems
        // to fix the sorting.
        if (fromCache.length === ids.length) { return fromCache; }

        return null;
    }

    ingestLineitem(
        liStruct: BatchLineitemStruct, toCache: boolean): BatchLineitemStruct {

        const li = liStruct.lineitem;

        // These values come through as NULL
        const summary = li.order_summary();
        if (!summary.estimated_amount()) { summary.estimated_amount(0); }
        if (!summary.encumbrance_amount()) { summary.encumbrance_amount(0); }
        if (!summary.paid_amount()) { summary.paid_amount(0); }

        // Sort the formula applications
        li.distribution_formulas(
            li.distribution_formulas().sort((f1, f2) =>
                f1.create_time() < f2.create_time() ? -1 : 1)
        );

        // consistent sorting
        li.lineitem_details(
            li.lineitem_details().sort((d1, d2) =>
                d1.id() < d2.id() ? -1 : 1)
        );

        // De-flesh some values we don't want living directly on
        // the copy.  Cache the values so our comboboxes, etc.
        // can use them without have to re-fetch them .
        li.lineitem_details().forEach(copy => {
            let val;
            if ((val = copy.circ_modifier())) { // assignment
                this.circModCache[val.code()] = copy.circ_modifier();
                copy.circ_modifier(val.code());
            }
            if ((val = copy.fund())) {
                this.fundCache[val.id()] = copy.fund();
                copy.fund(val.id());
            }
            if ((val = copy.location())) {
                this.loc.locationCache[val.id()] = copy.location();
                copy.location(val.id());
            }
        });

        if (toCache) { this.liCache[li.id()] = liStruct; }
        return liStruct;
    }

    // Returns all matching attributes
    // 'li' should be fleshed with attributes()
    getAttributes(li: IdlObject, name: string, attrType?: string): IdlObject[] {
        const values: IdlObject[] = [];
        li.attributes().forEach(attr => {
            if (attr.attr_name() === name) {
                if (!attrType || attrType === attr.attr_type()) {
                    values.push(attr);
                }
            }
        });

        return values;
    }

    getAttributeValues(li: IdlObject, name: string, attrType?: string): string[] {
        return this.getAttributes(li, name, attrType).map(attr => attr.attr_value());
    }

    // Returns the first matching attribute
    // 'li' should be fleshed with attributes()
    getFirstAttribute(li: IdlObject, name: string, attrType?: string): IdlObject {
        return this.getAttributes(li, name, attrType)[0];
    }

    getFirstAttributeValue(li: IdlObject, name: string, attrType?: string): string {
        const attr = this.getFirstAttribute(li, name, attrType);
        return attr ? attr.attr_value() : '';
    }

    getOrderIdent(li: IdlObject): IdlObject {
        for (let idx = 0; idx < li.attributes().length; idx++) {
            const attr = li.attributes()[idx];
            if (attr.order_ident() === 't' &&
                attr.attr_type() === 'lineitem_local_attr_definition') {
                return attr;
            }
        }
        return null;
    }

    // Returns an updated copy of the lineitem
    changeOrderIdent(li: IdlObject,
        id: number, attrType: string, attrValue: string): Observable<IdlObject> {

        const args: any = {lineitem_id: li.id()};

        if (id) {
            // Order ident set to an existing attribute.
            args.source_attr_id = id;
        } else {
            // Order ident set to a new free text value
            args.attr_name = attrType;
            args.attr_value = attrValue;
        }

        return this.net.request(
            'open-ils.acq',
            'open-ils.acq.lineitem.order_identifier.set',
            this.auth.token(), args
        ).pipe(switchMap(_ => this.getFleshedLineitems([li.id()]))
        ).pipe(map(struct => struct.lineitem));
    }

    applyBatchNote(liIds: number[],
        noteValue: string, vendorPublic: boolean): Promise<any> {

        if (!noteValue || liIds.length === 0) { return Promise.resolve(); }

        const notes = [];
        liIds.forEach(id => {
            const note = this.idl.create('acqlin');
            note.isnew(true);
            note.lineitem(id);
            note.value(noteValue);
            note.vendor_public(vendorPublic ? 't' : 'f');
            notes.push(note);
        });

        return this.net.request('open-ils.acq',
            'open-ils.acq.lineitem_note.cud.batch',
            this.auth.token(), notes
        ).pipe(tap(resp => {
            if (resp && resp.note) {
                const li = this.liCache[resp.note.lineitem()].lineitem;
                li.lineitem_notes().unshift(resp.note);
            }
        })).toPromise();
    }

    getLiAttrDefs(): Promise<IdlObject[]> {
        if (this.liAttrDefs) {
            return Promise.resolve(this.liAttrDefs);
        }

        return this.pcrud.retrieveAll('acqliad', {}, {atomic: true})
        .toPromise().then(defs => this.liAttrDefs = defs);
    }

    updateLiDetails(li: IdlObject): Observable<BatchLineitemUpdateStruct> {
        const lids = li.lineitem_details().filter(copy =>
            (copy.isnew() || copy.ischanged() || copy.isdeleted()));

        return from(

            // Ensure we have the updated fund/loc/mod values before
            // sending the copies off to be updated and then re-drawn.
            this.fetchFunds(lids.map(lid => lid.fund()))
            .then(_ => this.fetchLocations(lids.map(lid => lid.location())))
            .then(_ => this.fetchCircMods(lids.map(lid => lid.circ_modifier())))

        ).pipe(switchMap(_ =>
            this.net.request(
                'open-ils.acq',
                'open-ils.acq.lineitem_detail.cud.batch',
                this.auth.token(), lids
            )
        ));
    }

    updateLineitems(lis: IdlObject[]): Observable<BatchLineitemUpdateStruct> {

        // Fire updates one LI at a time.  Note the API allows passing
        // multiple LI's, but does not stream responses.  This approach
        // allows the caller to get a stream of responses instead of a
        // final "all done".
        let obs: Observable<any> = empty();
        lis.forEach(li => {
            obs = concat(obs, this.net.request(
                'open-ils.acq',
                'open-ils.acq.lineitem.update',
                this.auth.token(), li
            ));
        });

        return obs;
    }


    // Methods to fetch copy-related data, add it to our local cache,
    // and announce that new values are available for comboboxes.
    fetchFunds(fundIds: number[]): Promise<any> {
        fundIds = fundIds.filter(id => id && !(id in this.fundCache));
        if (fundIds.length === 0) { return Promise.resolve(); }

        return this.pcrud.search('acqf', {id: fundIds})
        .pipe(tap(fund => {
            this.fundCache[fund.id()] = fund;
            this.batchOptionWanted.emit(
                {fund: {id: fund.id(), label: fund.code(), fm: fund}});
        })).toPromise();
    }

    fetchCircMods(circMods: string[]): Promise<any> {
        circMods = circMods
            .filter(code => code && !(code in this.circModCache));

        if (circMods.length === 0) { return Promise.resolve(); }

        return this.pcrud.search('ccm', {code: circMods})
        .pipe(tap(mod => {
            this.circModCache[mod.code()] = mod;
            this.batchOptionWanted.emit({circ_modifier:
                {id: mod.code(), label: mod.code(), fm: mod}});
        })).toPromise();
    }

    fetchLocations(locIds: number[]): Promise<any> {
        locIds = locIds.filter(id => id && !(id in this.loc.locationCache));
        if (locIds.length === 0) { return Promise.resolve(); }

        return this.pcrud.search('acpl', {id: locIds})
        .pipe(tap(loc => {
            this.loc.locationCache[loc.id()] = loc;
            this.batchOptionWanted.emit({location:
                {id: loc.id(), label: loc.name(), fm: loc}});
        })).toPromise();
    }

    // Order disposition of a single lineitem detail
    copyDisposition(lineitem: IdlObject, copy: IdlObject): COPY_ORDER_DISPOSITION {
        if (!copy || !lineitem) {
            return null;
        } else if (copy.cancel_reason()) {
            if (copy.cancel_reason().keep_debits() === 't') {
                return 'delayed';
            } else {
                return 'canceled';
            }
        } else if (copy.recv_time()) {
            return 'received';
        } else if (lineitem.state() === 'on-order') {
            return 'on-order';
        } else { return 'pre-order'; }
    }
}

