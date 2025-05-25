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

        let method = 'open-ils.circ.holds.test_and_create.batch';
        if (request.override) { method = method + '.override'; }

        return this.net.request(
            'open-ils.circ', method, this.auth.token(), {
                patronid:       request.recipient,
                pickup_lib:     request.pickupLib,
                hold_type:      request.holdType,
                email_notify:   request.notifyEmail,
                phone_notify:   request.notifyPhone,
                thaw_date:      request.thawDate,
                frozen:         request.frozen,
                sms_notify:     request.notifySms,
                sms_carrier:    request.smsCarrier,
                holdable_formats_map: request.holdableFormats
            },
            [request.holdTarget]
        ).pipe(map(
            resp => {
                let result = resp.result;
                const holdResult: HoldRequestResult = {success: true};

                // API can return an ID, an array of events, or a hash
                // of info.

                if (Number(result) > 0) {
                    // On success, the API returns the hold ID.
                    holdResult.holdId = result;
                    console.debug(`Hold successfully placed ${result}`);

                } else {
                    holdResult.success = false;
                    console.info('Hold request failed: ', result);

                    if (Array.isArray(result)) { result = result[0]; }

                    if (this.evt.parse(result)) {
                        holdResult.evt = this.evt.parse(result);
                    } else {
                        holdResult.evt = this.evt.parse(result.last_event);
                    }
                }

                request.result = holdResult;
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
}



