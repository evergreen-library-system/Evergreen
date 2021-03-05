import {Injectable} from '@angular/core';
import {Observable, empty, from} from 'rxjs';
import {map, concatMap, mergeMap} from 'rxjs/operators';
import {IdlObject} from '@eg/core/idl.service';
import {NetService} from '@eg/core/net.service';
import {OrgService} from '@eg/core/org.service';
import {PcrudService} from '@eg/core/pcrud.service';
import {EventService, EgEvent} from '@eg/core/event.service';
import {AuthService} from '@eg/core/auth.service';
import {BibRecordService, BibRecordSummary} from '@eg/share/catalog/bib-record.service';
import {AudioService} from '@eg/share/util/audio.service';
import {CircEventsComponent} from './events-dialog.component';
import {CircComponentsComponent} from './components.component';

export interface CircDisplayInfo {
    title?: string;
    author?: string;
    isbn?: string;
    copy?: IdlObject;        // acp
    volume?: IdlObject;      // acn
    record?: IdlObject;      // bre
    display?: IdlObject;     // mwde
}

const CAN_OVERRIDE_CHECKOUT_EVENTS = [
    'PATRON_EXCEEDS_OVERDUE_COUNT',
    'PATRON_EXCEEDS_CHECKOUT_COUNT',
    'PATRON_EXCEEDS_FINES',
    'PATRON_EXCEEDS_LONGOVERDUE_COUNT',
    'PATRON_BARRED',
    'CIRC_EXCEEDS_COPY_RANGE',
    'ITEM_DEPOSIT_REQUIRED',
    'ITEM_RENTAL_FEE_REQUIRED',
    'PATRON_EXCEEDS_LOST_COUNT',
    'COPY_CIRC_NOT_ALLOWED',
    'COPY_NOT_AVAILABLE',
    'COPY_IS_REFERENCE',
    'COPY_ALERT_MESSAGE',
    'ITEM_ON_HOLDS_SHELF',
    'STAFF_C',
    'STAFF_CH',
    'STAFF_CHR',
    'STAFF_CR',
    'STAFF_H',
    'STAFF_HR',
    'STAFF_R'
];

const CHECKOUT_OVERRIDE_AFTER_FIRST = [
    'PATRON_EXCEEDS_OVERDUE_COUNT',
    'PATRON_BARRED',
    'PATRON_EXCEEDS_LOST_COUNT',
    'PATRON_EXCEEDS_CHECKOUT_COUNT',
    'PATRON_EXCEEDS_FINES',
    'PATRON_EXCEEDS_LONGOVERDUE_COUNT'
];

const CAN_OVERRIDE_RENEW_EVENTS = [
    'PATRON_EXCEEDS_OVERDUE_COUNT',
    'PATRON_EXCEEDS_LOST_COUNT',
    'PATRON_EXCEEDS_CHECKOUT_COUNT',
    'PATRON_EXCEEDS_FINES',
    'PATRON_EXCEEDS_LONGOVERDUE_COUNT',
    'CIRC_EXCEEDS_COPY_RANGE',
    'ITEM_DEPOSIT_REQUIRED',
    'ITEM_RENTAL_FEE_REQUIRED',
    'ITEM_DEPOSIT_PAID',
    'COPY_CIRC_NOT_ALLOWED',
    'COPY_NOT_AVAILABLE',
    'COPY_IS_REFERENCE',
    'COPY_ALERT_MESSAGE',
    'COPY_NEEDED_FOR_HOLD',
    'MAX_RENEWALS_REACHED',
    'CIRC_CLAIMS_RETURNED',
    'STAFF_C',
    'STAFF_CH',
    'STAFF_CHR',
    'STAFF_CR',
    'STAFF_H',
    'STAFF_HR',
    'STAFF_R'
];

// These checkin events do not produce alerts when
// options.suppress_alerts is in effect.
const CAN_SUPPRESS_CHECKIN_ALERTS = [
    'COPY_BAD_STATUS',
    'PATRON_BARRED',
    'PATRON_INACTIVE',
    'PATRON_ACCOUNT_EXPIRED',
    'ITEM_DEPOSIT_PAID',
    'CIRC_CLAIMS_RETURNED',
    'COPY_ALERT_MESSAGE',
    'COPY_STATUS_LOST',
    'COPY_STATUS_LOST_AND_PAID',
    'COPY_STATUS_LONG_OVERDUE',
    'COPY_STATUS_MISSING',
    'PATRON_EXCEEDS_FINES'
];

const CAN_OVERRIDE_CHECKIN_ALERTS = [
    // not technically overridable, but special prompt and param
    'HOLD_CAPTURE_DELAYED',
    'TRANSIT_CHECKIN_INTERVAL_BLOCK'
].concat(CAN_SUPPRESS_CHECKIN_ALERTS);


// API parameter options
export interface CheckoutParams {
    patron_id?: number;
    due_date?: string;
    copy_id?: number;
    copy_barcode?: string;
    noncat?: boolean;
    noncat_type?: number;
    noncat_count?: number;
    noop?: boolean;
    precat?: boolean;
    dummy_title?: string;
    dummy_author?: string;
    dummy_isbn?: string;
    circ_modifier?: string;

    // internal tracking
    _override?: boolean;
    _renewal?: boolean;
}

export interface CheckoutResult {
    index: number;
    firstEvent: EgEvent;
    allEvents: EgEvent[];
    params: CheckoutParams;
    success: boolean;
    canceled?: boolean;
    copy?: IdlObject;
    circ?: IdlObject;
    nonCatCirc?: IdlObject;
    record?: IdlObject;
}

export interface CheckinParams {
    noop?: boolean;
    copy_id?: number;
    copy_barcode?: string;
    claims_never_checked_out?: boolean;

    // internal tracking
    _override?: boolean;
}

export interface CheckinResult {
    index: number;
    firstEvent: EgEvent;
    allEvents: EgEvent[];
    params: CheckinParams;
    success: boolean;
    copy?: IdlObject;
    circ?: IdlObject;
    record?: IdlObject;
}

@Injectable()
export class CircService {
    static resultIndex = 0;

    components: CircComponentsComponent;
    nonCatTypes: IdlObject[] = null;
    billingTypes: IdlObject[] = null;
    autoOverrideCheckoutEvents: {[textcode: string]: boolean} = {};
    suppressCheckinPopups = false;
    ignoreCheckinPrecats = false;

    constructor(
        private audio: AudioService,
        private evt: EventService,
        private org: OrgService,
        private net: NetService,
        private pcrud: PcrudService,
        private auth: AuthService,
        private bib: BibRecordService,
    ) {}

    // 'circ' is fleshed with copy, vol, bib, wide_display_entry
    // Extracts some display info from a fleshed circ.
    getDisplayInfo(circ: IdlObject): CircDisplayInfo {

        const copy = circ.target_copy();

        if (copy.call_number().id() === -1) { // precat
            return {
                title: copy.dummy_title(),
                author: copy.dummy_author(),
                isbn: copy.dummy_isbn(),
                copy: copy
            };
        }

        const volume = copy.call_number();
        const record = volume.record();
        const display = record.wide_display_entry();

        let isbn = JSON.parse(display.isbn());
        if (Array.isArray(isbn)) { isbn = isbn.join(','); }

        return {
            title: JSON.parse(display.title()),
            author: JSON.parse(display.author()),
            isbn: isbn,
            copy: copy,
            volume: volume,
            record: record,
            display: display
        };
    }

    getNonCatTypes(): Promise<IdlObject[]> {

        if (this.nonCatTypes) {
            return Promise.resolve(this.nonCatTypes);
        }

        return this.pcrud.search('cnct',
            {owning_lib: this.org.fullPath(this.auth.user().ws_ou(), true)},
            {order_by: {cnct: 'name'}},
            {atomic: true}
        ).toPromise().then(types => this.nonCatTypes = types);
    }

    getBillingTypes(): Promise<IdlObject[]> {
        if (this.billingTypes) {
            return Promise.resolve(this.billingTypes);
        }

        return this.pcrud.search('cbt',
            {
                id: {'>': 100}, // first 100 are reserved
                owner: this.org.fullPath(this.auth.user().ws_ou(), true)
            },
            {order_by: {cbt: 'name'}},
            {atomic: true}
        ).toPromise().then(types => this.billingTypes = types);
    }

    // Remove internal tracking variables on Param objects so they are
    // not sent to the server, which can result in autoload errors.
    apiParams(
        params: CheckoutParams | CheckinParams): CheckoutParams | CheckinParams {

        const apiParams = Object.assign({}, params); // clone
        const remove = Object.keys(apiParams).filter(k => k.match(/^_/));
        remove.forEach(p => delete apiParams[p]);

        return apiParams;
    }

    checkout(params: CheckoutParams): Promise<CheckoutResult> {

        params._renewal = false;
        console.debug('checking out with', params);

        let method = 'open-ils.circ.checkout.full';
        if (params._override) { method += '.override'; }

        return this.net.request(
            'open-ils.circ', method,
            this.auth.token(), this.apiParams(params)).toPromise()
        .then(result => this.processCheckoutResult(params, result));
    }

    renew(params: CheckoutParams): Promise<CheckoutResult> {

        params._renewal = true;
        console.debug('renewing out with', params);

        let method = 'open-ils.circ.renew';
        if (params._override) { method += '.override'; }

        return this.net.request(
            'open-ils.circ', method,
            this.auth.token(), this.apiParams(params)).toPromise()
        .then(result => this.processCheckoutResult(params, result));
    }

    processCheckoutResult(
        params: CheckoutParams, response: any): Promise<CheckoutResult> {

        console.debug('checkout resturned', response);

        const allEvents = Array.isArray(response) ?
            response.map(r => this.evt.parse(r)) :
            [this.evt.parse(response)];

        const firstEvent = allEvents[0];
        const payload = firstEvent.payload;

        if (!payload) {
            this.audio.play('error.unknown.no_payload');
            return Promise.reject();
        }

        const result: CheckoutResult = {
            index: CircService.resultIndex++,
            firstEvent: firstEvent,
            allEvents: allEvents,
            params: params,
            success: false,
            circ: payload.circ,
            copy: payload.copy,
            record: payload.record,
            nonCatCirc: payload.noncat_circ
        };

        const overridable = result.params._renewal ?
            CAN_OVERRIDE_RENEW_EVENTS : CAN_OVERRIDE_CHECKOUT_EVENTS;

        if (allEvents.filter(
            e => overridable.includes(e.textcode)).length > 0) {
            return this.handleOverridableCheckoutEvents(result, allEvents);
        }

        switch (firstEvent.textcode) {
            case 'SUCCESS':
                result.success = true;
                this.audio.play('success.checkout');
                break;

            case 'ITEM_NOT_CATALOGED':
                return this.handlePrecat(result);
        }

        return Promise.resolve(result);
    }

    handleOverridableCheckoutEvents(
        result: CheckoutResult, events: EgEvent[]): Promise<CheckoutResult> {
        const params = result.params;
        const firstEvent = events[0];

        if (params._override) {
            // Should never get here.  Just being safe.
            return Promise.reject(null);
        }

        if (events.filter(
            e => !this.autoOverrideCheckoutEvents[e.textcode]).length === 0) {
            // User has already seen all of these events and overridden them,
            // so avoid showing them again since they are all auto-overridable.
            params._override = true;
            return params._renewal ? this.renew(params) : this.checkout(params);
        }

        return this.showOverrideDialog(result, events);
    }

    showOverrideDialog(result: CheckoutResult,
        events: EgEvent[], checkin?: boolean): Promise<CheckoutResult> {

        const params = result.params;
        const mode = checkin ? 'checkin' : (params._renewal ? 'renew' : 'checkout');

        this.components.circEventsDialog.events = events;
        this.components.circEventsDialog.mode = mode;

        return this.components.circEventsDialog.open().toPromise()
        .then(confirmed => {
            if (!confirmed) { return null; }

            if (!checkin) {
                // Indicate these events have been seen and overridden.
                events.forEach(evt => {
                    if (CHECKOUT_OVERRIDE_AFTER_FIRST.includes(evt.textcode)) {
                        this.autoOverrideCheckoutEvents[evt.textcode] = true;
                    }
                });
            }

            params._override = true;

            return this[mode](params); // checkout/renew/checkin
        });
    }

    handlePrecat(result: CheckoutResult): Promise<CheckoutResult> {
        this.components.precatDialog.barcode = result.params.copy_barcode;

        return this.components.precatDialog.open().toPromise().then(values => {

            if (values && values.dummy_title) {
                const params = result.params;
                params.precat = true;
                Object.keys(values).forEach(key => params[key] = values[key]);
                return this.checkout(params);
            }

            result.canceled = true;
            return Promise.resolve(result);
        });
    }

    checkin(params: CheckinParams): Promise<CheckinResult> {

        console.debug('checking in with', params);

        let method = 'open-ils.circ.checkin';
        if (params._override) { method += '.override'; }

        return this.net.request(
            'open-ils.circ', method,
            this.auth.token(), this.apiParams(params)).toPromise()
        .then(result => this.processCheckinResult(params, result));
    }

    processCheckinResult(
        params: CheckinParams, response: any): Promise<CheckinResult> {

        console.debug('checkout resturned', response);

        const allEvents = Array.isArray(response) ?
            response.map(r => this.evt.parse(r)) : [this.evt.parse(response)];

        const firstEvent = allEvents[0];
        const payload = firstEvent.payload;

        if (!payload) {
            this.audio.play('error.unknown.no_payload');
            return Promise.reject();
        }

        const success =
            firstEvent.textcode.match(/SUCCESS|NO_CHANGE|ROUTE_ITEM/) !== null;

        const result: CheckinResult = {
            index: CircService.resultIndex++,
            firstEvent: firstEvent,
            allEvents: response,
            params: params,
            success: success,
            circ: payload.circ,
            copy: payload.copy,
            record: payload.record
        };

        // Informational alerts that can be ignored if configured.
        if (this.suppressCheckinPopups &&
            allEvents.filter(e =>
                !CAN_SUPPRESS_CHECKIN_ALERTS.includes(e.textcode)).length === 0) {

            // Should not be necessary, but good to be safe.
            if (params._override) { return Promise.resolve(null); }

            params._override = true;
            return this.checkin(params);
        }


        // Alerts that require a manual override.
        if (allEvents.filter(
            e => CAN_OVERRIDE_CHECKIN_ALERTS.includes(e.textcode)).length > 0) {

            // Should not be necessary, but good to be safe.
            if (params._override) { return Promise.resolve(null); }

            return this.showOverrideDialog(result, allEvents, true);
        }

        switch (firstEvent.textcode) {
            case 'SUCCESS':
            case 'NO_CHANGE':
                this.audio.play('success.checkin');
                return this.handleCheckinSuccess(result);

            case 'ITEM_NOT_CATALOGED':
                this.audio.play('error.checkout.no_cataloged');

                if (!this.suppressCheckinPopups && !this.ignoreCheckinPrecats) {
                    // Tell the user its a precat and return the result.
                    return this.components.routeToCatalogingDialog.open()
                    .toPromise().then(_ => result);
                }
        }

        return Promise.resolve(result);
    }

    handleCheckinSuccess(result: CheckinResult): Promise<CheckinResult> {
        return Promise.resolve(result);
    }

    handleOverridableCheckinEvents(
        result: CheckinResult, events: EgEvent[]): Promise<CheckinResult> {
        const params = result.params;
        const firstEvent = events[0];

        if (params._override) {
            // Should never get here.  Just being safe.
            return Promise.reject(null);
        }

    }


    // The provided params (minus the copy_id) will be used
    // for all items.
    checkoutBatch(copyIds: number[],
        params: CheckoutParams): Observable<CheckoutResult> {

        if (copyIds.length === 0) { return empty(); }

        return from(copyIds).pipe(concatMap(id => {
            const cparams = Object.assign({}, params); // clone
            cparams.copy_id = id;
            return from(this.checkout(cparams));
        }));
    }

    // The provided params (minus the copy_id) will be used
    // for all items.
    renewBatch(copyIds: number[],
        params?: CheckoutParams): Observable<CheckoutResult> {

        if (copyIds.length === 0) { return empty(); }
        if (!params) { params = {}; }

        return from(copyIds).pipe(concatMap(id => {
            const cparams = Object.assign({}, params); // clone
            cparams.copy_id = id;
            return from(this.renew(cparams));
        }));
    }

    // The provided params (minus the copy_id) will be used
    // for all items.
    checkinBatch(copyIds: number[],
        params?: CheckinParams): Observable<CheckinResult> {

        if (copyIds.length === 0) { return empty(); }
        if (!params) { params = {}; }

        return from(copyIds).pipe(concatMap(id => {
            const cparams = Object.assign({}, params); // clone
            cparams.copy_id = id;
            return from(this.checkin(cparams));
        }));
    }
}

