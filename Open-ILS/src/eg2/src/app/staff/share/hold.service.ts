/**
 * Common code for mananging holdings
 */
import {Injectable, EventEmitter} from '@angular/core';
import {Observable} from 'rxjs/Observable';
import {map} from 'rxjs/operators/map';
import {mergeMap} from 'rxjs/operators/mergeMap';
import {IdlObject} from '@eg/core/idl.service';
import {NetService} from '@eg/core/net.service';
import {PcrudService} from '@eg/core/pcrud.service';
import {EventService, EgEvent} from '@eg/core/event.service';
import {AuthService} from '@eg/core/auth.service';
import {BibRecordService, BibRecordSummary} 
    from '@eg/share/catalog/bib-record.service';

// Response from a place-holds API call.
export interface HoldRequestResult {
    success: boolean;
    holdId?: number;
    evt?: EgEvent;
};

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
    result?: HoldRequestResult
};

// A fleshed hold request target object containing whatever data is
// available for each hold type / target.  E.g. a TITLE hold will
// not have a value for 'volume', but a COPY hold will, since all
// copies have volumes.  Every HoldRequestTarget will have a bibId and
// bibSummary.  Some values come directly from the API call, others
// applied locally.
export interface HoldRequestTarget {
    target: number;
    metarecord?: IdlObject;
    bibrecord?: IdlObject;
    bibId?: number;
    bibSummary?: BibRecordSummary;
    part?: IdlObject;
    volume?: IdlObject;
    copy?: IdlObject;
    issuance?: IdlObject;
    metarecord_filters?: any;
}

@Injectable()
export class HoldService {

    constructor(
        private evt: EventService,
        private net: NetService,
        private pcrud: PcrudService,
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

            return this.bib.getBibSummary(target.bibId)
            .pipe(map(sum => {
                target.bibSummary = sum;
                return target;
            }));
        }));
    }
}

