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
import {PrecatCheckoutDialogComponent
    } from '@eg/staff/share/circ/precat-dialog.component';


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
}

export interface CheckoutResult {
    index: number;
    evt: EgEvent;
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
}

export interface CheckinResult {
    index: number;
    evt: EgEvent;
    params: CheckinParams;
    success: boolean;
    copy?: IdlObject;
    circ?: IdlObject;
    record?: IdlObject;
}

@Injectable()
export class CircService {
    static resultIndex = 0;

    nonCatTypes: IdlObject[] = null;
    precatDialog: PrecatCheckoutDialogComponent;

    constructor(
        private audio: AudioService,
        private evt: EventService,
        private org: OrgService,
        private net: NetService,
        private pcrud: PcrudService,
        private auth: AuthService,
        private bib: BibRecordService,
    ) {}

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

    checkout(params: CheckoutParams, override?: boolean): Promise<CheckoutResult> {

        console.debug('checking out with', params);

        let method = 'open-ils.circ.checkout.full';
        if (override) { method += '.override'; }

        return this.net.request(
            'open-ils.circ', method,
            this.auth.token(), params).toPromise()
        .then(result => this.processCheckoutResult(params, result));
    }

    renew(params: CheckoutParams, override?: boolean): Promise<CheckoutResult> {

        console.debug('renewing out with', params);

        let method = 'open-ils.circ.renew';
        if (override) { method += '.override'; }

        return this.net.request(
            'open-ils.circ', method,
            this.auth.token(), params).toPromise()
        .then(result => this.processCheckoutResult(params, result));
    }

    processCheckoutResult(
        params: CheckoutParams, response: any): Promise<CheckoutResult> {

        console.debug('checkout resturned', response);

        if (Array.isArray(response)) { response = response[0]; }

        const evt = this.evt.parse(response);
        const payload = evt.payload;

        if (!payload) {
            this.audio.play('error.unknown.no_payload');
            return Promise.reject();
        }

        const result: CheckoutResult = {
            index: CircService.resultIndex++,
            evt: evt,
            params: params,
            success: evt.textcode === 'SUCCESS',
            circ: payload.circ,
            copy: payload.copy,
            record: payload.record,
            nonCatCirc: payload.noncat_circ
        };

        switch (evt.textcode) {
            case 'ITEM_NOT_CATALOGED':
                return this.handlePrecat(result);
        }

        return Promise.resolve(result);
    }

    handlePrecat(result: CheckoutResult): Promise<CheckoutResult> {
        this.precatDialog.barcode = result.params.copy_barcode;

        return this.precatDialog.open().toPromise().then(values => {

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

    checkin(params: CheckinParams, override?: boolean): Promise<CheckinResult> {

        console.debug('checking in with', params);

        let method = 'open-ils.circ.checkin';
        if (override) { method += '.override'; }

        return this.net.request(
            'open-ils.circ', method,
            this.auth.token(), params).toPromise()
        .then(result => this.processCheckinResult(params, result));
    }

    processCheckinResult(
        params: CheckinParams, response: any): Promise<CheckinResult> {

        console.debug('checkout resturned', response);

        if (Array.isArray(response)) { response = response[0]; }

        const evt = this.evt.parse(response);
        const payload = evt.payload;

        if (!payload) {
            this.audio.play('error.unknown.no_payload');
            return Promise.reject();
        }

        switch (evt.textcode) {
            case 'ITEM_NOT_CATALOGED':
                this.audio.play('error.checkout.no_cataloged');
                // alert, etc.
        }

        const success =
            evt.textcode.match(/SUCCESS|NO_CHANGE|ROUTE_ITEM/) !== null;

        const result: CheckinResult = {
            index: CircService.resultIndex++,
            evt: evt,
            params: params,
            success: success,
            circ: payload.circ,
            copy: payload.copy,
            record: payload.record
        };

        return Promise.resolve(result);
    }

    // The provided params (minus the copy_id) will be used
    // for all items.
    checkoutBatch(copyIds: number[], params: CheckoutParams): Observable<CheckoutResult> {
        if (copyIds.length === 0) { return empty(); }
        const source = from(copyIds);

        return source.pipe(concatMap(id => {
            const cparams = Object.assign(params, {}); // clone
            cparams.copy_id = id;
            return from(this.checkout(cparams));
        }));
    }

    // The provided params (minus the copy_id) will be used
    // for all items.
    renewBatch(copyIds: number[], params?: CheckoutParams): Observable<CheckoutResult> {
        if (copyIds.length === 0) { return empty(); }

        if (!params) { params = {}; }

        const source = from(copyIds);

        return source.pipe(concatMap(id => {
            const cparams = Object.assign(params, {}); // clone
            cparams.copy_id = id;
            return from(this.renew(cparams));
        }));
    }

    // The provided params (minus the copy_id) will be used
    // for all items.
    checkinBatch(copyIds: number[], params?: CheckinParams): Observable<CheckinResult> {
        if (copyIds.length === 0) { return empty(); }

        if (!params) { params = {}; }

        const source = from(copyIds);

        return source.pipe(concatMap(id => {
            const cparams = Object.assign(params, {}); // clone
            cparams.copy_id = id;
            return from(this.checkin(cparams));
        }));
    }
}

