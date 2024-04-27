/* eslint-disable no-case-declarations, no-magic-numbers */
import {Injectable} from '@angular/core';
import {Observable, empty, from} from 'rxjs';
import {concatMap} from 'rxjs/operators';
import {IdlObject} from '@eg/core/idl.service';
import {NetService} from '@eg/core/net.service';
import {OrgService} from '@eg/core/org.service';
import {PcrudService} from '@eg/core/pcrud.service';
import {EventService, EgEvent} from '@eg/core/event.service';
import {AuthService} from '@eg/core/auth.service';
import {BibRecordService} from '@eg/share/catalog/bib-record.service';
import {AudioService} from '@eg/share/util/audio.service';
import {CircComponentsComponent} from './components.component';
import {StringService} from '@eg/share/string/string.service';
import {ServerStoreService} from '@eg/core/server-store.service';
import {HoldingsService} from '@eg/staff/share/holdings/holdings.service';
import {WorkLogService, WorkLogEntry} from '@eg/staff/share/worklog/worklog.service';

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
    'INVALID_PATRON_ADDRESS',
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
    'INVALID_PATRON_ADDRESS',
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
    void_overdues?: boolean;
    new_copy_alerts?: boolean;

    // internal tracking
    _override?: boolean;
    _renewal?: boolean;
    _checkbarcode?: boolean;
    _worklog?: WorkLogEntry;
}

export interface CircResultCommon {
    index: number;
    params: CheckinParams | CheckoutParams;
    firstEvent: EgEvent;
    allEvents: EgEvent[];
    success: boolean;
    copy?: IdlObject;
    volume?: IdlObject;
    record?: IdlObject;
    circ?: IdlObject;
    parent_circ?: IdlObject;
    hold?: IdlObject;

    // Set to one of circ_patron or hold_patron depending on the context.
    patron?: IdlObject;

    // Set to the patron linked to the relevant circulation.
    circ_patron?: IdlObject;

    // Set to the patron linked to the relevant hold.
    hold_patron?: IdlObject;

    transit?: IdlObject;
    copyAlerts?: IdlObject[];
    mbts?: IdlObject;

    routeTo?: string; // org name or in-branch destination

    // Calculated values
    title?: string;
    author?: string;
    isbn?: string;
}


export interface CheckoutResult extends CircResultCommon {
    params: CheckoutParams;
    canceled?: boolean;
    nonCatCirc?: IdlObject;
}

export interface CheckinParams {
    noop?: boolean;
    copy_id?: number;
    copy_barcode?: string;
    claims_never_checked_out?: boolean;
    void_overdues?: boolean;
    auto_print_holds_transits?: boolean;
    backdate?: string;
    capture?: string;
    next_copy_status?: number[];
    new_copy_alerts?: boolean;
    clear_expired?: boolean;
    hold_as_transit?: boolean;
    manual_float?: boolean;
    do_inventory_update?: boolean;
    no_precat_alert?: boolean;
    retarget_mode?: string;

    // internal / local values that are moved from the API request.
    _override?: boolean;
    _worklog?: WorkLogEntry;
    _checkbarcode?: boolean;
}

export interface CheckinResult extends CircResultCommon {
    params: CheckinParams;
    destOrg?: IdlObject;
    destAddress?: IdlObject;
    destCourierCode?: string;
}

@Injectable()
export class CircService {
    static resultIndex = 0;

    components: CircComponentsComponent;
    nonCatTypes: IdlObject[] = null;
    autoOverrideCheckoutEvents: {[textcode: string]: boolean} = {};
    suppressCheckinPopups = false;
    ignoreCheckinPrecats = false;
    copyLocationCache: {[id: number]: IdlObject} = {};
    clearHoldsOnCheckout = false;
    orgAddrCache: {[addrId: number]: IdlObject} = {};

    constructor(
        private audio: AudioService,
        private evt: EventService,
        private org: OrgService,
        private net: NetService,
        private pcrud: PcrudService,
        private serverStore: ServerStoreService,
        private strings: StringService,
        private auth: AuthService,
        private holdings: HoldingsService,
        private worklog: WorkLogService,
        private bib: BibRecordService
    ) {}

    applySettings(): Promise<any> {
        return this.serverStore.getItemBatch([
            'circ.clear_hold_on_checkout',
        ]).then(sets => {
            this.clearHoldsOnCheckout = sets['circ.clear_hold_on_checkout'];
            return this.worklog.loadSettings();
        });
    }

    // 'circ' is fleshed with copy, vol, bib, wide_display_entry
    // Extracts some display info from a fleshed circ.
    getDisplayInfo(circ: IdlObject): CircDisplayInfo {
        return this.getCopyDisplayInfo(circ.target_copy());
    }

    getCopyDisplayInfo(copy: IdlObject): CircDisplayInfo {

        if (copy.call_number() === -1 || copy.call_number().id() === -1) {
            // Precat Copy
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

    getOrgAddr(orgId: number, addrType): Promise<IdlObject> {
        const org = this.org.get(orgId);
        const addrId = this.org[addrType];

        if (!addrId) { return Promise.resolve(null); }

        if (this.orgAddrCache[addrId]) {
            return Promise.resolve(this.orgAddrCache[addrId]);
        }

        return this.pcrud.retrieve('aoa', addrId).toPromise()
            .then(addr => {
                this.orgAddrCache[addrId] = addr;
                return addr;
            });
    }

    // find the open transit for the given copy barcode; flesh the org
    // units locally.
    // Sets result.transit
    findCopyTransit(result: CircResultCommon): Promise<IdlObject> {
        // NOTE: result.transit may exist, but it's not necessarily
        // the transit we want, since a transit close + open in the API
        // returns the closed transit.
        return this.findCopyTransitById(result.copy.id())
            .then(transit => {
                result.transit = transit;
                return transit;
            });
    }

    findCopyTransitById(copyId: number): Promise<IdlObject> {
        return this.pcrud.search('atc', {
            dest_recv_time : null,
            cancel_time : null,
            target_copy: copyId
        }, {
            limit : 1,
            order_by : {atc : 'source_send_time desc'},
        }, {authoritative : true}
        ).toPromise().then(transit => {
            if (transit) {
                transit.source(this.org.get(transit.source()));
                transit.dest(this.org.get(transit.dest()));
                return transit;
            }

            return Promise.reject('No transit found');
        });
    }

    // Sets result.transit and result.copy
    findCopyTransitByBarcode(result: CircResultCommon): Promise<IdlObject> {
        // NOTE: result.transit may exist, but it's not necessarily
        // the transit we want, since a transit close + open in the API
        // returns the closed transit.

        const barcode = result.params.copy_barcode;

        return this.pcrud.search('atc', {
            dest_recv_time : null,
            cancel_time : null
        }, {
            flesh : 1,
            flesh_fields : {atc : ['target_copy']},
            join : {
                acp : {
                    filter : {
                        barcode : barcode,
                        deleted : 'f'
                    }
                }
            },
            limit : 1,
            order_by : {atc : 'source_send_time desc'}
        }, {authoritative : true}

        ).toPromise().then(transit => {
            if (transit) {
                transit.source(this.org.get(transit.source()));
                transit.dest(this.org.get(transit.dest()));
                result.transit = transit;
                result.copy = transit.target_copy();
                return transit;
            }
            return Promise.reject('No transit found');
        });
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

    // Remove internal tracking variables on Param objects so they are
    // not sent to the server, which can result in autoload errors.
    apiParams(
        params: CheckoutParams | CheckinParams): CheckoutParams | CheckinParams {

        const apiParams = Object.assign({}, params); // clone
        const remove = Object.keys(apiParams).filter(k => k.match(/^_/));
        remove.forEach(p => delete apiParams[p]);

        // This modifier is not sent to the server.
        // Should be _-prefixed, but we already have a workstation setting,
        // etc. for this one.  Just manually remove it from the API params.
        delete apiParams['auto_print_holds_transits'];

        return apiParams;
    }

    checkout(params: CheckoutParams): Promise<CheckoutResult> {

        params.new_copy_alerts = true;
        params._renewal = false;
        console.debug('checking out with', params);

        let method = 'open-ils.circ.checkout.full';
        if (params._override) { method += '.override'; }

        return this.inspectBarcode(params).then(barcodeOk => {
            if (!barcodeOk) { return null; }

            return this.net.request(
                'open-ils.circ', method,
                this.auth.token(), this.apiParams(params)).toPromise()
                .then(result => this.unpackCheckoutData(params, result))
                .then(result => this.processCheckoutResult(result));
        });
    }

    renew(params: CheckoutParams): Promise<CheckoutResult> {

        params.new_copy_alerts = true;
        params._renewal = true;
        console.debug('renewing out with', params);

        let method = 'open-ils.circ.renew';
        if (params._override) { method += '.override'; }

        return this.inspectBarcode(params).then(barcodeOk => {
            if (!barcodeOk) { return null; }

            return this.net.request(
                'open-ils.circ', method,
                this.auth.token(), this.apiParams(params)).toPromise()
                .then(result => this.unpackCheckoutData(params, result))
                .then(result => this.processCheckoutResult(result));
        });
    }


    unpackCheckoutData(
        params: CheckoutParams, response: any): Promise<CheckoutResult> {

        const allEvents = Array.isArray(response) ?
            response.map(r => this.evt.parse(r)) :
            [this.evt.parse(response)];

        console.debug('checkout events', allEvents.map(e => e.textcode));
        console.debug('checkout returned', allEvents);

        const firstEvent = allEvents[0];
        const payload = firstEvent.payload;

        const result: CheckoutResult = {
            index: CircService.resultIndex++,
            firstEvent: firstEvent,
            allEvents: allEvents,
            params: params,
            success: false
        };

        // Some scenarios (e.g. copy in transit) have no payload,
        // which is OK.
        if (!payload) { return Promise.resolve(result); }

        result.circ = payload.circ;
        result.copy = payload.copy;
        result.volume = payload.volume;
        result.patron = payload.patron;
        result.record = payload.record;
        result.nonCatCirc = payload.noncat_circ;

        return this.fleshCommonData(result).then(_ => {
            const action = params._renewal ? 'renew' :
                (params.noncat ? 'noncat_checkout' : 'checkout');
            this.addWorkLog(action, result);
            return result;
        });
    }

    processCheckoutResult(result: CheckoutResult): Promise<CheckoutResult> {
        const renewing = result.params._renewal;
        const key = renewing ? 'renew' : 'checkout';

        const overridable = renewing ?
            CAN_OVERRIDE_RENEW_EVENTS : CAN_OVERRIDE_CHECKOUT_EVENTS;

        if (result.allEvents.filter(
            e => overridable.includes(e.textcode)).length > 0) {
            return this.handleOverridableCheckoutEvents(result);
        }

        switch (result.firstEvent.textcode) {
            case 'SUCCESS':
                result.success = true;
                this.audio.play(`success.${key}`);
                return Promise.resolve(result);

            case 'ITEM_NOT_CATALOGED':
                return this.handlePrecat(result);

            case 'OPEN_CIRCULATION_EXISTS':

                if (result.firstEvent.payload.auto_renew) {
                    const coParams = Object.assign({}, result.params); // clone
                    return this.renew(coParams);
                }

                return this.handleOpenCirc(result);

            case 'COPY_IN_TRANSIT':
                this.audio.play(`warning.${key}.in_transit`);
                return this.copyInTransitDialog(result);

            case 'PATRON_CARD_INACTIVE':
            case 'PATRON_INACTIVE':
            case 'PATRON_ACCOUNT_EXPIRED':
            case 'CIRC_CLAIMS_RETURNED':
            case 'ACTOR_USER_NOT_FOUND':
            case 'AVAIL_HOLD_COPY_RATIO_EXCEEDED':
                this.audio.play(`warning.${key}`);
                return this.exitAlert({
                    textcode: result.firstEvent.textcode,
                    barcode: result.params.copy_barcode
                });

            case 'ASSET_COPY_NOT_FOUND':
                this.audio.play(`error.${key}.not_found`);
                return this.exitAlert({
                    textcode: result.firstEvent.textcode,
                    barcode: result.params.copy_barcode
                });

            default:
                this.audio.play(`error.${key}.unknown`);
                return this.exitAlert({
                    textcode: 'CHECKOUT_FAILED_GENERIC',
                    barcode: result.params.copy_barcode
                });
        }
    }

    exitAlert(context: any): Promise<any> {
        const key = 'staff.circ.events.' + context.textcode;
        return this.strings.interpolate(key, context)
            .then(str => {
                this.components.circFailedDialog.dialogBody = str;
                return this.components.circFailedDialog.open().toPromise();
            })
            .then(_ => Promise.reject('Bailling on event ' + context.textcode));
    }

    copyInTransitDialog(result: CheckoutResult): Promise<CheckoutResult> {
        this.components.copyInTransitDialog.checkout = result;

        return this.findCopyTransitByBarcode(result)
            .then(_ => this.components.copyInTransitDialog.open().toPromise())
            .then(cancelAndCheckout => {
                if (cancelAndCheckout) {

                    return this.abortTransit(result.transit.id())
                        .then(_ => {
                            // We had to look up the copy from the barcode since
                            // it was not embedded in the result event.  Since
                            // we have the specifics on the copy, go ahead and
                            // copy them into the params we use for the follow
                            // up checkout.
                            result.params.copy_barcode = result.copy.barcode();
                            result.params.copy_id = result.copy.id();
                            return this.checkout(result.params);
                        });

                } else {
                    return result;
                }
            });
    }

    // Ask the user if we should resolve the circulation and check
    // out to the user or leave it alone.
    // When resolving and checking out, renew if it's for the same
    // user, otherwise check it in, then back out to the current user.
    handleOpenCirc(result: CheckoutResult): Promise<CheckoutResult> {

        let sameUser = false;

        return this.net.request(
            'open-ils.circ',
            'open-ils.circ.copy_checkout_history.retrieve',
            this.auth.token(), result.params.copy_id, 1).toPromise()

            .then(circs => {
                const circ = circs[0];

                sameUser = result.params.patron_id === circ.usr();
                this.components.openCircDialog.sameUser = sameUser;
                this.components.openCircDialog.circDate = circ.xact_start();

                return this.components.openCircDialog.open({size: 'lg'}).toPromise();
            })

            .then(fromDialog => {

                // Leave the open circ checked out.
                if (!fromDialog) { return result; }

                const coParams = Object.assign({}, result.params); // clone

                if (fromDialog.renew) {
                    coParams.void_overdues = fromDialog.forgiveFines;
                    return this.renew(coParams);
                }

                const ciParams: CheckinParams = {
                    noop: true,
                    copy_id: coParams.copy_id,
                    void_overdues: fromDialog.forgiveFines
                };

                return this.checkin(ciParams)
                    .then(res => {
                        if (res.success) {
                            return this.checkout(coParams);
                        } else {
                            return Promise.reject('Unable to check in item');
                        }
                    });
            });
    }

    handleOverridableCheckoutEvents(result: CheckoutResult): Promise<CheckoutResult> {
        const params = result.params;
        const firstEvent = result.firstEvent;
        const events = result.allEvents;

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

        // New-style alerts are reported via COPY_ALERT_MESSAGE and
        // includes the alerts in the payload as an array.
        if (firstEvent.textcode === 'COPY_ALERT_MESSAGE'
            && Array.isArray(firstEvent.payload)) {
            this.components.copyAlertManager.alerts = firstEvent.payload;

            this.components.copyAlertManager.mode =
                params._renewal ? 'renew' : 'checkout';

            return this.components.copyAlertManager.open().toPromise()
                .then(resp => {
                    if (resp) {
                        params._override = true;
                        return this.checkout(params);
                    }
                });
        }

        return this.showOverrideDialog(result, events);
    }

    showOverrideDialog(result: CheckoutResult,
        events: EgEvent[], checkin?: boolean): Promise<CheckoutResult> {

        const params = result.params;
        const mode = checkin ? 'checkin' : (params._renewal ? 'renew' : 'checkout');

        const holdShelfEvent = events.filter(e => e.textcode === 'ITEM_ON_HOLDS_SHELF')[0];

        if (holdShelfEvent) {
            this.components.circEventsDialog.clearHolds = this.clearHoldsOnCheckout;
            this.components.circEventsDialog.patronId = holdShelfEvent.payload.patron_id;
            this.components.circEventsDialog.patronName = holdShelfEvent.payload.patron_name;
        }

        this.components.circEventsDialog.copyBarcode = result.params.copy_barcode;
        this.components.circEventsDialog.events = events;
        this.components.circEventsDialog.mode = mode;

        return this.components.circEventsDialog.open().toPromise()
            .then(resp => {
                const confirmed = resp.override;
                if (!confirmed) { return null; }

                let promise = Promise.resolve(null);

                if (!checkin) {
                // Indicate these events have been seen and overridden.
                    events.forEach(evt => {
                        if (CHECKOUT_OVERRIDE_AFTER_FIRST.includes(evt.textcode)) {
                            this.autoOverrideCheckoutEvents[evt.textcode] = true;
                        }
                    });

                    if (holdShelfEvent && resp.clearHold) {
                        const holdId = holdShelfEvent.payload.hold_id;

                        // Cancel the hold that put our checkout item
                        // on the holds shelf.

                        promise = promise.then(_ => {
                            return this.net.request(
                                'open-ils.circ',
                                'open-ils.circ.hold.cancel',
                                this.auth.token(),
                                holdId,
                                5, // staff forced
                                'Item checked out by other patron' // FIXME I18n
                            ).toPromise().then(netRequestResp => {
                                const evt = this.evt.parse(netRequestResp);
                                if (evt) {
                                    this.audio.play('warning.hold.cancel_failed');
                                    console.error('unable to cancel hold: ' + evt.toString());
                                } else {
                                    this.net.request(
                                        'open-ils.circ', 'open-ils.circ.hold.details.retrieve',
                                        this.auth.token(), holdId, {
                                            'suppress_notices': true,
                                            'suppress_transits': true,
                                            'suppress_mvr' : true,
                                            'include_usr' : true
                                        }).toPromise().then(details => {
                                        // console.log('details', details);
                                        const entry: WorkLogEntry = {
                                            'action' : 'canceled_hold',
                                            'hold_id' : holdId,
                                            'patron_id' : details.hold.usr().id(),
                                            'user' : details.patron_last,
                                            'item' : details.copy ? details.copy.barcode() : null,
                                            'item_id' : details.copy ? details.copy.id() : null
                                        };
                                        this.worklog.record(entry);
                                    }).catch(error => {
                                        console.error('Error retrieving hold details for Work Log', error);
                                    });
                                }
                                // worklog is just a side-effect, so we return the result of the previous link in the chain
                                return netRequestResp;
                            }).catch(error => {
                                console.error('Error in hold cancelation:', error);
                            });
                        });
                    }
                }

                return promise.then(_ => {
                    params._override = true;
                    return this[mode](params); // checkout/renew/checkin
                });
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
        params.new_copy_alerts = true;

        console.debug('checking in with', params);

        let method = 'open-ils.circ.checkin';
        if (params._override) { method += '.override'; }

        return this.inspectBarcode(params).then(barcodeOk => {
            if (!barcodeOk) { return null; }

            return this.net.request(
                'open-ils.circ', method,
                this.auth.token(), this.apiParams(params)).toPromise()
                .then(result => this.unpackCheckinData(params, result))
                .then(result => this.processCheckinResult(result));
        });
    }

    fetchPatron(userId: number): Promise<IdlObject> {
        return this.pcrud.retrieve('au', userId, {
            flesh: 1,
            flesh_fields : {'au' : ['card', 'stat_cat_entries']}
        })
            .toPromise();
    }

    fleshCommonData(result: CircResultCommon): Promise<CircResultCommon> {

        console.debug('fleshCommonData()');

        const copy = result.copy;
        const volume = result.volume;
        const circ = result.circ;
        const hold = result.hold;
        const nonCatCirc = (result as CheckoutResult).nonCatCirc;

        let promise: Promise<any> = Promise.resolve();

        if (hold) {
            console.debug('fleshCommonData() hold ', hold.usr());
            promise = promise.then(_ => {
                return this.fetchPatron(hold.usr())
                    .then(usr => {
                        result.hold_patron = usr;
                        console.debug('Setting hold patron to ' + usr.id());
                    });
            });
        }

        const circPatronId = circ ? circ.usr() :
            (nonCatCirc ? nonCatCirc.patron() : null);

        if (circPatronId) {
            console.debug('fleshCommonData() circ patron id', circPatronId);
            promise = promise.then(_ => {
                return this.fetchPatron(circPatronId)
                    .then(usr => {
                        result.circ_patron = usr;
                        console.debug('Setting circ patron to ' + usr.id());
                    });
            });
        }

        // Set a default patron value which is used in most cases.
        promise = promise.then(_ => {
            result.patron = result.hold_patron || result.circ_patron;
        });

        if (result.record) {
            result.title = result.record.title();
            result.author = result.record.author();
            result.isbn = result.record.isbn();

        } else if (copy) {
            result.title = result.copy.dummy_title();
            result.author = result.copy.dummy_author();
            result.isbn = result.copy.dummy_isbn();
        }

        if (copy) {
            if (this.copyLocationCache[copy.location()]) {
                copy.location(this.copyLocationCache[copy.location()]);
            } else {
                promise = promise.then(_ => {
                    return this.pcrud.retrieve('acpl', copy.location())
                        .toPromise().then(loc => {
                            copy.location(loc);
                            this.copyLocationCache[loc.id()] = loc;
                        });
                });
            }

            if (typeof copy.status() !== 'object') {
                promise = promise.then(_ => this.holdings.getCopyStatuses())
                    .then(stats => {
                        const stat =
                        Object.values(stats).filter(s => s.id() === copy.status())[0];
                        if (stat) { copy.status(stat); }
                    });
            }
        }

        promise = promise.then(_ => {
            // By default, all items route-to their location.
            // Value replaced later on as needed.
            if (copy && typeof copy.location() === 'object') {
                result.routeTo = copy.location().name();
            }
        });

        if (volume) {
            // Flesh volume prefixes and suffixes

            if (typeof volume.prefix() !== 'object') {
                promise = promise.then(_ =>
                    this.pcrud.retrieve('acnp', volume.prefix()).toPromise()
                ).then(p => volume.prefix(p));
            }

            if (typeof volume.suffix() !== 'object') {
                promise = promise.then(_ =>
                    this.pcrud.retrieve('acns', volume.suffix()).toPromise()
                ).then(p => volume.suffix(p));
            }
        }

        return promise.then(_ => result);
    }

    unpackCheckinData(params: CheckinParams, response: any): Promise<CheckinResult> {
        const allEvents = Array.isArray(response) ?
            response.map(r => this.evt.parse(r)) : [this.evt.parse(response)];

        console.debug('checkin events', allEvents.map(e => e.textcode));
        console.debug('checkin response', response);

        const firstEvent = allEvents[0];
        const payload = firstEvent.payload;

        const success =
            firstEvent.textcode.match(/SUCCESS|NO_CHANGE|ROUTE_ITEM/) !== null;

        const result: CheckinResult = {
            index: CircService.resultIndex++,
            firstEvent: firstEvent,
            allEvents: allEvents,
            params: params,
            success: success,
        };

        if (!payload) {
            // e.g. ASSET_COPY_NOT_FOUND
            return Promise.resolve(result);
        }

        result.circ = payload.circ;
        result.parent_circ = payload.parent_circ;
        result.copy = payload.copy;
        result.volume = payload.volume;
        result.record = payload.record;
        result.transit = payload.transit;
        result.hold = payload.hold;

        const copy = result.copy;
        const volume = result.volume;
        const transit = result.transit;
        const circ = result.circ;
        const parent_circ = result.parent_circ;

        if (transit) {
            if (typeof transit.dest() !== 'object') {
                transit.dest(this.org.get(transit.dest()));
            }
            if (typeof transit.source() !== 'object') {
                transit.source(this.org.get(transit.source()));
            }
        }

        // for checkin, the mbts lives on the main circ
        if (circ && circ.billable_transaction()) {
            result.mbts = circ.billable_transaction().summary();
        }

        // on renewals, the mbts lives on the parent circ
        if (parent_circ && parent_circ.billable_transaction()) {
            result.mbts = parent_circ.billable_transaction().summary();
        }

        return this.fleshCommonData(result)
            .then(_ => this.updateInventory(result))
            .then(_ => {
                this.addWorkLog('checkin', result);
                return result;
            });
    }

    updateInventory(result: CheckinResult): Promise<any> {

        if (result?.firstEvent?.payload?.do_inventory_update) {
            const inv = result?.firstEvent?.payload?.latest_inventory;

            if (inv.id()) {
                return this.pcrud.update(inv).toPromise();
            } else {
                return this.pcrud.create(inv).toPromise();
            }
        }

        return Promise.resolve();
    }

    processCheckinResult(result: CheckinResult): Promise<CheckinResult> {
        const params = result.params;
        const allEvents = result.allEvents;

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
            return this.handleOverridableCheckinEvents(result);
        }

        switch (result.firstEvent.textcode) {
            case 'SUCCESS':
            case 'NO_CHANGE':
                return this.handleCheckinSuccess(result);

            case 'ITEM_NOT_CATALOGED':
                this.audio.play('error.checkout.no_cataloged');
                result.routeTo = this.components.catalogingStr.text;
                return this.showPrecatAlert().then(_ => result);

            case 'ROUTE_ITEM':
                this.audio.play(result.hold ?
                    'info.checkin.transit.hold' : 'info.checkin.transit');

                if (params.noop) {
                    console.debug('Skipping route dialog on "noop" checkin');
                    return Promise.resolve(result);
                }

                this.components.routeDialog.checkin = result;
                return this.findCopyTransit(result)
                    .then(_ => this.components.routeDialog.open().toPromise())
                    .then(_ => result);

            case 'ASSET_COPY_NOT_FOUND':
                this.audio.play('error.checkin.not_found');
                return this.handleCheckinUncatAlert(result);

            default:
                this.audio.play('error.checkin.unknown');
                console.warn(
                    'Unhandled checkin response : ' + result.firstEvent.textcode);
        }

        return Promise.resolve(result);
    }

    addWorkLog(action: string, result: CircResultCommon) {
        const params = result.params;
        const copy = result.copy;
        const patron = result.patron;

        // Some worklog data may be provided by the caller in the params.
        const entry: WorkLogEntry =
            Object.assign(params._worklog || {}, {action: action});

        if (copy) {
            entry.item = copy.barcode();
            entry.item_id = copy.id();
        } else {
            entry.item = params.copy_barcode;
            entry.item_id = params.copy_id;
        }

        if (patron) {
            entry.patron_id = patron.id();
            entry.user = patron.family_name();
        }

        if (result.hold) {
            entry.hold_id = result.hold.id();
        }

        this.worklog.record(entry);
    }

    showPrecatAlert(): Promise<any> {
        if (!this.suppressCheckinPopups && !this.ignoreCheckinPrecats) {
            // Tell the user its a precat and return the result.
            return this.components.routeToCatalogingDialog.open()
                .toPromise();
        }
        return Promise.resolve(null);
    }

    handleCheckinSuccess(result: CheckinResult): Promise<CheckinResult> {
        const copy = result.copy;

        if (!copy) { return Promise.resolve(result); }

        const stat = copy.status();
        const statId = typeof stat === 'object' ? stat.id() : stat;

        switch (statId) {

            case 0: /* AVAILABLE */
            case 4: /* MISSING */
            case 7: /* RESHELVING */
                this.audio.play('success.checkin');
                return this.handleCheckinLocAlert(result);

            case 8: /* ON HOLDS SHELF */
                this.audio.play('info.checkin.holds_shelf');

                const hold = result.hold;

                if (hold) {

                    if (Number(hold.pickup_lib()) === Number(this.auth.user().ws_ou())) {
                        result.routeTo = this.components.holdShelfStr.text;
                        this.components.routeDialog.checkin = result;
                        return this.components.routeDialog.open().toPromise()
                            .then(_ => result);

                    } else {
                        // Should not happen in practice, but to be safe.
                        this.audio.play('warning.checkin.wrong_shelf');
                    }

                } else {
                    console.warn('API Returned insufficient info on holds');
                }
                break;

            case 11: /* CATALOGING */
                this.audio.play('info.checkin.cataloging');
                result.routeTo = this.components.catalogingStr.text;
                return this.showPrecatAlert().then(_ => result);

            case 15: /* ON_RESERVATION_SHELF */
                this.audio.play('info.checkin.reservation');
                break;

            default:
                this.audio.play('success.checkin');
                console.debug(`Unusual checkin copy status (may have been
                    set via copy alert): status=${statId}`);
        }

        return Promise.resolve(result);
    }

    handleCheckinLocAlert(result: CheckinResult): Promise<CheckinResult> {
        const copy = result.copy;

        if (this.suppressCheckinPopups
            || copy.location().checkin_alert() === 'f') {
            return Promise.resolve(result);
        }

        return this.strings.interpolate(
            'staff.circ.checkin.location.alert',
            {barcode: copy.barcode(), location: copy.location().name()}
        ).then(str => {
            this.components.locationAlertDialog.dialogBody = str;
            return this.components.locationAlertDialog.open().toPromise()
                .then(_ => result);
        });
    }

    handleCheckinUncatAlert(result: CheckinResult): Promise<CheckinResult> {
        const barcode = result.copy ?
            result.copy.barcode() : result.params.copy_barcode;

        if (this.suppressCheckinPopups) {
            return Promise.resolve(result);
        }

        return this.strings.interpolate(
            'staff.circ.checkin.uncat.alert', {barcode: barcode}
        ).then(str => {
            this.components.uncatAlertDialog.dialogBody = str;
            return this.components.uncatAlertDialog.open().toPromise()
                .then(_ => result);
        });
    }


    handleOverridableCheckinEvents(result: CheckinResult): Promise<CheckinResult> {
        const params = result.params;
        const events = result.allEvents;
        const firstEvent = result.firstEvent;

        if (params._override) {
            // Should never get here.  Just being safe.
            return Promise.reject(null);
        }

        if (this.suppressCheckinPopups && events.filter(
            e => !CAN_SUPPRESS_CHECKIN_ALERTS.includes(e.textcode)).length === 0) {
            // These events are automatically overridden when suppress
            // popups are in effect.
            params._override = true;
            return this.checkin(params);
        }

        // New-style alerts are reported via COPY_ALERT_MESSAGE and
        // includes the alerts in the payload as an array.
        if (firstEvent.textcode === 'COPY_ALERT_MESSAGE'
            && Array.isArray(firstEvent.payload)) {
            this.components.copyAlertManager.alerts = firstEvent.payload;
            this.components.copyAlertManager.mode = 'checkin';

            return this.components.copyAlertManager.open().toPromise()
                .then(resp => {

                    if (!resp) { return result; } // dialog was canceled

                    if (resp.nextStatus !== null) {
                        params.next_copy_status = [resp.nextStatus];
                        params.capture = 'nocapture';
                    }

                    params._override = true;

                    return this.checkin(params);
                });
        }

        return this.showOverrideDialog(result, events, true);
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

    abortTransit(transitId: number): Promise<any> {
        return this.net.request(
            'open-ils.circ',
            'open-ils.circ.transit.abort',
            this.auth.token(), {transitid : transitId}
        ).toPromise().then(resp => {
            const evt = this.evt.parse(resp);
            if (evt) {
                alert(evt);
                return Promise.reject(evt.toString());
            }
            return Promise.resolve();
        });
    }

    lastCopyCirc(copyId: number): Promise<IdlObject> {
        return this.pcrud.search('circ',
            {target_copy : copyId},
            {order_by : {circ : 'xact_start desc' }, limit : 1}
        ).toPromise();
    }

    // Resolves to true if the barcode is OK or the user confirmed it or
    // the user doesn't care to begin with
    inspectBarcode(params: CheckoutParams | CheckinParams): Promise<boolean> {
        if (!params._checkbarcode || !params.copy_barcode) {
            return Promise.resolve(true);
        }

        if (this.checkBarcode(params.copy_barcode)) {
            // Avoid prompting again on an override
            params._checkbarcode = false;
            return Promise.resolve(true);
        }

        this.components.badBarcodeDialog.barcode = params.copy_barcode;
        return this.components.badBarcodeDialog.open().toPromise()
        // Avoid prompting again on an override
            .then(response => {
                params._checkbarcode = false;
                return response;
            });
    }

    checkBarcode(barcode: string): boolean {
        if (barcode !== Number(barcode).toString()) { return false; }

        const bc = barcode.toString();

        // "16.00" == Number("16.00"), but the . is bad.
        // Throw out any barcode that isn't just digits
        if (bc.search(/\D/) !== -1) { return false; }

        const lastDigit = bc.substr(bc.length - 1);
        const strippedBarcode = bc.substr(0, bc.length - 1);
        return this.barcodeCheckdigit(strippedBarcode).toString() === lastDigit;
    }

    barcodeCheckdigit(bc: string): number {
        let checkSum = 0;
        let multiplier = 2;
        const reverseBarcode = bc.toString().split('').reverse();

        reverseBarcode.forEach(ch => {
            let tempSum = 0;
            const product = (Number(ch) * multiplier) + '';
            product.split('').forEach(num => tempSum += Number(num));
            checkSum += Number(tempSum);
            multiplier = multiplier === 2 ? 1 : 2;
        });

        const cSumStr = checkSum.toString();
        const nextMultipleOf10 =
            (Number(cSumStr.match(/(\d*)\d$/)[1]) * 10) + 10;

        let checkDigit = nextMultipleOf10 - Number(cSumStr);
        if (checkDigit === 10) { checkDigit = 0; }

        return checkDigit;
    }
}

