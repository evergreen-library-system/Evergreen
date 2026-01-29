/**
 * Common code for mananging holds
 */
import {Injectable} from '@angular/core';
import {Observable, map, mergeMap} from 'rxjs';
import {IdlObject} from '@eg/core/idl.service';
import {NetService} from '@eg/core/net.service';
import {EventService, EgEvent} from '@eg/core/event.service';
import {AuthService} from '@eg/core/auth.service';
import {BibRecordService,
    BibRecordSummary} from '@eg/share/catalog/bib-record.service';

// Response from a place-holds API call.
export interface HoldRequestResult {
    success: boolean;
    holdId?: number;
    evt?: EgEvent;
}

// Values passed to the place-holds API call.
export interface HoldRequest {
    holdType: string;
    holdTarget: number;
    recipient: number;
    requestor: number;
    pickupLib: number;
    override?: boolean;
    notifyEmail?: boolean;
    notifyPhone?: string;
    notifySms?: string;
    smsCarrier?: string;
    thawDate?: string; // ISO date
    frozen?: boolean;
    holdableFormats?: {[target: number]: string};
    holdGroup?: boolean;
    holdGroupId?: number;
    result?: HoldRequestResult;
}

// A fleshed hold request target object containing whatever data is
// available for each hold type / target.  E.g. a TITLE hold will
// not have a value for 'callNum', but a COPY hold will, since all
// copies have call numbers.  Every HoldRequestTarget will have a bibId and
// bibSummary.  Some values come directly from the API call, others
// applied locally.
export interface HoldRequestTarget {
    target: number;
    metarecord?: IdlObject;
    bibrecord?: IdlObject;
    bibId?: number;
    bibSummary?: BibRecordSummary;
    part?: IdlObject;
    parts?: IdlObject[];
    callNum?: IdlObject;
    copy?: IdlObject;
    issuance?: IdlObject;
    metarecord_filters?: any;
    part_required?: boolean;
}

/** Service for performing various hold-related actions */

@Injectable()
export class HoldsService {

    constructor(
        private evt: EventService,
        private net: NetService,
        private auth: AuthService,
        private bib: BibRecordService,
    ) {}

    placeHold(request: HoldRequest): Observable<HoldRequest> {
        if (request.holdGroup) {
            return this.placeSubscriptionHold(request);
        }

        let method = 'open-ils.circ.holds.test_and_create.batch';
        if (request.override) { method = method + '.override'; }

        return this.net.request(
            'open-ils.circ', method, this.auth.token(), ...this.placeHoldArgs(request)
        ).pipe(map(
            resp => {
                request.result = this.parseResult(resp.result);
                return request;
            }
        ));
    }

    getHoldTargetMeta(holdType: string, holdTarget: number | number[],
        orgId?: number): Observable<HoldRequestTarget> {

        const targetIds = [].concat(holdTarget);

        return this.net.request(
            'open-ils.circ',
            'open-ils.circ.hold.get_metadata',
            holdType, targetIds, orgId
        ).pipe(mergeMap(meta => {
            const target: HoldRequestTarget = meta;
            target.bibId = target.bibrecord.id();
            target.callNum = meta.volume; // map to client terminology
            target.parts = meta.parts.sort((p1, p2) =>
                p1.label_sortkey() < p2.label_sortkey() ? 1 : -1);

            return this.bib.getBibSummary(target.bibId)
                .pipe(map(sum => {
                    target.bibSummary = sum;
                    return target;
                }));
        }));
    }

    /**
      * Update a list of holds.
      * Returns observable of results, one per hold.
      * Result is either a Number (hold ID) or an EgEvent object.
      */
    updateHolds(holds: IdlObject[]): Observable<any> {

        return this.net.request(
            'open-ils.circ',
            'open-ils.circ.hold.update.batch',
            this.auth.token(), holds
        ).pipe(map(response => {

            if (Number(response) > 0) { return Number(response); }

            if (Array.isArray(response)) { response = response[0]; }

            const evt = this.evt.parse(response);

            console.warn('Hold update returned event', evt);
            return evt;
        }));
    }

    private placeHoldArgs(request: HoldRequest): any[] {
        const params = {
            pickup_lib:     request.pickupLib,
            hold_type:      request.holdType,
            email_notify:   request.notifyEmail,
            phone_notify:   request.notifyPhone,
            thaw_date:      request.thawDate,
            frozen:         request.frozen,
            sms_notify:     request.notifySms,
            sms_carrier:    request.smsCarrier,
            holdable_formats_map: request.holdableFormats
        } as any;
        if (request.holdGroup) {
            return [
                params,
                request.holdGroupId,
                request.holdTarget
            ];
        }
        params.patronid = request.recipient;
        return [
            params,
            [request.holdTarget]
        ];
    }

    private placeSubscriptionHold(request: HoldRequest): Observable<HoldRequest> {
        let method = 'open-ils.circ.holds.test_and_create.subscription_batch';
        if (request.override) { method = method + '.override'; }

        return this.net.request(
            'open-ils.circ', method, this.auth.token(), ...this.placeHoldArgs(request)
        ).pipe(map(
            resp => {
                request.result = this.parseResult(resp.result);
                return request;
            }
        ));
    }

    private parseResult(raw: any): HoldRequestResult {
        const holdResult: HoldRequestResult = {success: true};

        // API can return an ID, an array of events, a hash
        // of info, or (for the summary of a hold group hold),
        // undefined.

        if (raw === undefined) {
            // This is the summary of a hold group subscription hold.  We can assume
            // success for now.  If a particular patron has an issue, that will be
            // revealed in future OpenSRF messages.
            return holdResult;
        }

        if (Number(raw) > 0) {
            // On success, the API returns the hold ID.
            holdResult.holdId = raw;
            console.debug(`Hold successfully placed ${raw}`);

        } else {
            console.info('Hold request failed: ', raw);
            holdResult.success = false;
            if (Array.isArray(raw)) { raw = raw[0]; }

            if (this.evt.parse(raw)) {
                holdResult.evt = this.evt.parse(raw);
            } else {
                holdResult.evt = this.evt.parse(raw.last_event);
            }
        }
        return holdResult;
    }
}



