import {Injectable, EventEmitter} from '@angular/core';
import {Router, ActivatedRoute, NavigationEnd} from '@angular/router';
import {empty, Observable} from 'rxjs';
import {OrgService} from '@eg/core/org.service';
import {NetService} from '@eg/core/net.service';
import {AuthService} from '@eg/core/auth.service';
import {EventService, EgEvent} from '@eg/core/event.service';
import {IdlService, IdlObject} from '@eg/core/idl.service';
import {StoreService} from '@eg/core/store.service';
import {PatronService, PatronSummary, PatronStats} from '@eg/staff/share/patron/patron.service';
import {ConfirmDialogComponent} from '@eg/share/dialog/confirm.component';
import {AlertDialogComponent} from '@eg/share/dialog/alert.component';
import {PrintService} from '@eg/share/print/print.service';
import {AudioService} from '@eg/share/util/audio.service';
import {StringService} from '@eg/share/string/string.service';
import {PcrudService} from '@eg/core/pcrud.service';

export interface ActionContext {
    barcode?: string; // item
    username?: string; // patron username or barcode
    result?: any;
    firstEvent?: EgEvent;
    payload?: any;
    override?: boolean;
    redo?: boolean;
    renew?: boolean;
    displayText?: string; // string key
    alertSound?: string;
    shouldPopup?: boolean;
    previousCirc?: IdlObject;
    renewalFailure?: boolean;
    newCirc?: IdlObject;
    external?: boolean; // not from main checkout input.
    renewSuccessCount?: number;
    renewFailCount?: number;
}

interface SessionCheckout {
    circ: IdlObject;
    ctx: ActionContext;
}

const CIRC_FLESH_DEPTH = 4;
const CIRC_FLESH_FIELDS = {
  circ: ['target_copy'],
  acp:  ['call_number'],
  acn:  ['record'],
  bre:  ['flat_display_entries']
};

@Injectable({providedIn: 'root'})
export class SckoService {

    // Currently active patron account object.
    patronSummary: PatronSummary;
    statusDisplayText = '';
    statusDisplaySuccess: boolean;

    barcodeRegex: RegExp;
    patronPasswordRequired = false;
    patronIdleTimeout: number;
    patronTimeoutId: number;
    logoutWarningTimeout = 20;
    logoutWarningTimerId: number;

    alertAudio = false;
    alertPopup = false;
    orgSettings: any;
    overrideCheckoutEvents: string[] = [];
    blockStatuses: number[] = [];

    sessionCheckouts: SessionCheckout[] = [];

    // We get this from the main scko component.
    logoutDialog: ConfirmDialogComponent;
    alertDialog: AlertDialogComponent;
    focusBarcode: EventEmitter<void> = new EventEmitter<void>();
    patronLoaded: EventEmitter<void> = new EventEmitter<void>();

    constructor(
        private router: Router,
        private route: ActivatedRoute,
        private org: OrgService,
        private net: NetService,
        private evt: EventService,
        public auth: AuthService,
        private pcrud: PcrudService,
        private printer: PrintService,
        private audio: AudioService,
        private strings: StringService,
        private patrons: PatronService,
    ) {}

    logoutStaff() {
        this.resetPatron();
        this.auth.logout();
        this.router.navigate(['/staff/scko']);
    }

    resetPatron() {
        this.statusDisplayText = '';
        this.patronSummary = null;
        this.sessionCheckouts = [];
    }

    load(): Promise<any> {
        this.auth.authDomain = 'eg.scko';

        return this.auth.testAuthToken()

        .then(_ => {

            // Note we cannot use server-store unless we are logged
            // in with a workstation.
            return this.org.settings([
                'opac.barcode_regex',
                'circ.selfcheck.patron_login_timeout',
                'circ.selfcheck.auto_override_checkout_events',
                'circ.selfcheck.patron_password_required',
                'circ.checkout_auto_renew_age',
                'circ.selfcheck.workstation_required',
                'circ.selfcheck.alert.popup',
                'circ.selfcheck.alert.sound',
                'credit.payments.allow',
                'circ.selfcheck.block_checkout_on_copy_status'
            ]);

        }).then(sets => {
            this.orgSettings = sets;

            const regPattern = sets['opac.barcode_regex'] || /^\d/;
            this.barcodeRegex = new RegExp(regPattern);
            this.patronPasswordRequired =
                sets['circ.selfcheck.patron_password_required'];

            this.alertAudio = sets['circ.selfcheck.alert.sound'];
            this.alertPopup = sets['circ.selfcheck.alert.popup'];

            this.overrideCheckoutEvents =
                sets['circ.selfcheck.auto_override_checkout_events'] || [];

            this.blockStatuses =
                sets['circ.selfcheck.block_checkout_on_copy_status'] ?
                sets['circ.selfcheck.block_checkout_on_copy_status'].map(s => Number(s)) :
                [];

            this.patronIdleTimeout =
                Number(sets['circ.selfcheck.patron_login_timeout'] || 160);

            // Compensate for the warning dialog
            this.patronIdleTimeout -= this.logoutWarningTimeout;

            // Load a patron by barcode via URL params.
            // Useful for development.
            const username = this.route.snapshot.queryParamMap.get('patron');

            if (username && !this.patronPasswordRequired) {
                return this.loadPatron(username);
            } else {
                // Go to the base checkout page by default.
                this.router.navigate(['/staff/scko']);
            }
        }).catch(_ => {}); // console errors
    }

    getFleshedCircs(circIds: number[]): Observable<IdlObject> {
        if (circIds.length === 0) { return empty(); }

        return this.pcrud.search('circ', {id: circIds}, {
            flesh: CIRC_FLESH_DEPTH,
            flesh_fields: CIRC_FLESH_FIELDS,
            order_by : {circ : 'due_date'},
            select: {bre : ['id']}
        });
    }

    getFleshedCirc(circId: number): Promise<IdlObject> {
        return this.getFleshedCircs([circId]).toPromise();
    }

    loadPatron(username: string, password?: string): Promise<any> {
        this.resetPatron();

        if (!username) { return; }

        let barcode;
        if (username.match(this.barcodeRegex)) {
            barcode = username;
            username = null;
        }

        if (!this.patronPasswordRequired) {
            return this.fetchPatron(username, barcode);
        }

        return this.net.request(
            'open-ils.actor',
            'open-ils.actor.verify_user_password',
            this.auth.token(), barcode, username, null, password)

        .toPromise().then(verified => {
            if (Number(verified) === 1) {
                return this.fetchPatron(username, barcode);
            } else {
                return Promise.reject('Bad password');
            }
        });
    }

    fetchPatron(username: string, barcode: string): Promise<any> {

        return this.net.request(
            'open-ils.actor',
            'open-ils.actor.user.retrieve_id_by_barcode_or_username',
            this.auth.token(), barcode, username).toPromise()

        .then(patronId => {

            const evt = this.evt.parse(patronId);

            if (evt || !patronId) {
                console.error('Cannot find user: ', evt);
                return Promise.reject('User not found');
            }

            return this.patrons.getFleshedById(patronId);
        })
        .then(patron => this.patronSummary = new PatronSummary(patron))
        .then(_ => this.patrons.getVitalStats(this.patronSummary.patron))
        .then(stats => this.patronSummary.stats = stats)
        .then(_ => this.resetPatronTimeout())
        .then(_ => this.patronLoaded.emit());
    }

    resetPatronTimeout() {
        console.debug('Resetting patron timeout=' + this.patronIdleTimeout);
        if (this.patronTimeoutId) {
            clearTimeout(this.patronTimeoutId);
        }
        this.startPatronTimer();
    }

    startPatronTimer() {
        setTimeout(
            () => this.showPatronLogoutWarning(),
            this.patronTimeoutId = this.patronIdleTimeout * 1000
        );
    }

    showPatronLogoutWarning() {
        console.debug('Session timing out.  Show warning dialog');

        this.logoutDialog.open().subscribe(remain => {
            if (remain) {
                clearTimeout(this.logoutWarningTimerId);
                this.logoutWarningTimerId = null;
                this.resetPatronTimeout();
            } else {
                this.resetPatron();
                this.router.navigate(['/staff/scko']);
            }
        });

        // Force the session to end if no action is taken on the
        // logout warning dialog.
        setTimeout(
            () => {
                console.debug('Clearing patron on warning dialog timeout');
                this.resetPatron();
                this.router.navigate(['/staff/scko']);
            },
            this.logoutWarningTimerId = this.logoutWarningTimeout * 1000
        );
    }

    sessionTotalCheckouts(): number {
        return this.sessionCheckouts.length;
    }

    accountTotalCheckouts(): number {
        // stats.checkouts.total_out includes claims returned
        // Exclude locally renewed items from the total checkouts

        return this.sessionCheckouts.filter(co => !co.ctx.external).length +
            this.patronSummary.stats.checkouts.out +
            this.patronSummary.stats.checkouts.overdue +
            this.patronSummary.stats.checkouts.long_overdue;
    }

    checkout(barcode: string, override?: boolean): Promise<any> {
        this.resetPatronTimeout();

        barcode = (barcode || '').trim();
        if (!barcode) { return Promise.resolve(); }

        let method = 'open-ils.circ.checkout.full';
        if (override) { method += '.override'; }

        return this.net.request(
            'open-ils.circ', method, this.auth.token(), {
            patron_id: this.patronSummary.id,
            copy_barcode: barcode
        }).toPromise()

        .then(result => {

            console.debug('CO returned', result);

            return this.handleCheckoutResult(result, barcode, 'checkout');

        }).then(ctx => {
            console.debug('handleCheckoutResult returned', ctx);

            if (ctx.override) {
                return this.checkout(barcode, true);
            } else if (ctx.redo) {
                return this.checkout(barcode);
            } else if (ctx.renew) {
                return this.renew(barcode);
            }

            return ctx;

        // Checkout actions always takes us back to the main page
        // so we can see our items out in progress.
        })
        .then(ctx => this.notifyPatron(ctx))
        .finally(() => this.router.navigate(['/staff/scko']));
    }

    renew(barcode: string,
        override?: boolean, external?: boolean): Promise<ActionContext> {

        let method = 'open-ils.circ.renew';
        if (override) { method += '.override'; }

        return this.net.request(
            'open-ils.circ', method, this.auth.token(), {
            patron_id: this.patronSummary.id,
            copy_barcode: barcode
        }).toPromise()

        .then(result => {
            console.debug('Renew returned', result);

            return this.handleCheckoutResult(result, barcode, 'renew', external);

        }).then(ctx => {
            console.debug('handleCheckoutResult returned', ctx);

            if (ctx.override) {
                return this.renew(barcode, true, external);
            }

            return ctx;
        });
    }

    notifyPatron(ctx: ActionContext) {
        console.debug('notifyPatron(): ', ctx);

        this.statusDisplayText = '';

        this.statusDisplaySuccess = !ctx.shouldPopup;

        this.focusBarcode.emit();

        if (this.alertAudio && ctx.alertSound) {
            this.audio.play(ctx.alertSound);
        }

        if (!ctx.displayText) { return; }

        this.strings.interpolate(ctx.displayText, {ctx: ctx})
        .then(str => {
            this.statusDisplayText = str;
            console.debug('Displaying text to user:', str);

            if (this.alertPopup && ctx.shouldPopup && str) {
                this.alertDialog.dialogBody = str;
                this.alertDialog.open().toPromise();
            }
        });
    }

    handleCheckoutResult(result: any, barcode: string,
        action: string, external?: boolean): Promise<ActionContext> {

        if (Array.isArray(result)) {
            result = result[0];
        }

        const evt: any = this.evt.parse(result) || {};
        const payload = evt.payload || {};

        if (evt.textcode === 'NO_SESSION') {
            this.logoutStaff();
            return;
        }

        const ctx: ActionContext = {
            result: result,
            firstEvent: evt,
            payload: payload,
            barcode: barcode,
            displayText: 'scko.unknown',
            alertSound: '',
            shouldPopup: false,
            redo: false,
            override: false,
            renew: false,
            external: external
        };

        if (evt.textcode === 'SUCCESS') {
            ctx.displayText = `scko.${action}.success`;
            ctx.alertSound = `success.scko.${action}`;

            return this.getFleshedCirc(payload.circ.id()).then(
                circ => {
                    ctx.newCirc = circ;
                    this.sessionCheckouts.push({circ: circ, ctx: ctx});
                    return ctx;
                }
            );
        }

        if (evt.textcode === 'OPEN_CIRCULATION_EXISTS' && action === 'checkout') {
            return this.handleOpenCirc(ctx);
        }

        return this.handleEvents(ctx);
    }

    handleOpenCirc(ctx: ActionContext): Promise<any> {

        if (ctx.payload.old_circ) {
            const age = this.orgSettings['circ.checkout_auto_renew_age'];

            if (!age || (age && ctx.payload.auto_renew)) {
                ctx.renew = true;

                // Flesh the previous circ so we can show the title,
                // etc. in the receipt.
                return this.getFleshedCirc(ctx.payload.old_circ.id())
                .then(oldCirc => {
                    ctx.previousCirc = oldCirc;
                    return ctx;
                });
            }
        }

        // LOST items can be checked in and made usable if configured.
        if (ctx.payload.copy
            && Number(ctx.payload.copy.status()) === /* LOST */ 3
            && this.overrideCheckoutEvents.length
            && this.overrideCheckoutEvents.includes('COPY_STATUS_LOST')) {

            return this.checkin(ctx.barcode).then(ok => {
                if (ok) {
                    ctx.redo = true;
                } else {
                    ctx.shouldPopup = true;
                    ctx.alertSound = 'error.scko.checkout';
                    ctx.displayText = 'scko.checkout.already_out';
                }

                return ctx;
            });
        }

        ctx.shouldPopup = true;
        ctx.alertSound = 'error.scko.checkout';
        ctx.displayText = 'scko.checkout.already_out';

        return Promise.resolve(ctx);
    }

    handleEvents(ctx: ActionContext): Promise<ActionContext> {
        let override = true;
        let abortTransit = false;
        let lastErrorText = '';

        [].concat(ctx.result).some(res => {

            if (!this.overrideCheckoutEvents.includes(res.textcode)) {
                console.debug('We are not configured to override', res.textcode);
                lastErrorText = this.getErrorDisplyText(this.evt.parse(res));
                return override = false;
            }

            if (this.blockStatuses.length > 0) {
                let stat = res.payload.status();
                if (typeof stat === 'object') { stat = stat.id(); }

                if (this.blockStatuses.includes(Number(stat))) {
                    return override = false;
                }
            }

            if (res.textcode === 'COPY_IN_TRANSIT') {
                abortTransit = true;
            }

            return true;
        });

        if (!override) {
            ctx.shouldPopup = true;
            ctx.alertSound = 'error.scko.checkout';
            ctx.renewalFailure = true;
            ctx.displayText = lastErrorText;
            return Promise.resolve(ctx);
        }

        if (!abortTransit) {
            ctx.override = true;
            return Promise.resolve(ctx);
        }

        return this.checkin(ctx.barcode, true).then(ok => {
            if (ok) {
                ctx.redo = true;
            } else {
                ctx.shouldPopup = true;
                ctx.alertSound = 'error.scko.checkout';
            }
            return ctx;
        });
    }

    getErrorDisplyText(evt: EgEvent): string {

        switch (evt.textcode) {
            case 'PATRON_EXCEEDS_CHECKOUT_COUNT':
                return 'scko.error.patron_exceeds_checkout_count';
            case 'MAX_RENEWALS_REACHED':
                return 'scko.error.max_renewals';
            case 'ITEM_NOT_CATALOGED':
                return 'scko.error.item_not_cataloged';
            case 'COPY_CIRC_NOT_ALLOWED':
                return 'scko.error.copy_circ_not_allowed';
            case 'OPEN_CIRCULATION_EXISTS':
                return 'scko.error.already_out';
            case 'PATRON_EXCEEDS_FINES':
                return 'scko.error.patron_fines';
            default:
                if (evt.payload && evt.payload.fail_part) {
                    return 'scko.error.' +
                        evt.payload.fail_part.replace(/\./g, '_');
                }
        }

        return 'scko.error.unknown';
    }

    checkin(barcode: string, abortTransit?: boolean): Promise<boolean> {

        let promise = Promise.resolve(true);

        if (abortTransit) {

            promise = this.net.request(
                'open-ils.circ',
                'open-ils.circ.transit.abort',
                this.auth.token(), {barcode: barcode}).toPromise()

            .then(resp => {

                console.debug('Transit abort returned', resp);
                return Number(resp) === 1;
            });
        }

        promise = promise.then(ok => {
            if (!ok) { return false; }

            return this.net.request(
                'open-ils.circ',
                'open-ils.circ.checkin.override',
                this.auth.token(), {
                    patron_id : this.patronSummary.id,
                    copy_barcode : barcode,
                    noop : true
                }

            ).toPromise().then(resp => {

                // If any response events are non-success, report the
                // checkin as a failure.
                let success = true;
                [].concat(resp).forEach(evt => {
                    console.debug('Checkin returned', resp);

                    const code = evt.textcode;
                    if (code !== 'SUCCESS' && code !== 'NO_CHANGE') {
                        success = false;
                    }
                });

                return success;

            });
        });

        return promise;
    }

    logoutPatron(receiptType: string): Promise<any> {

        let promise;

        switch (receiptType) {
            case 'email':
                promise = this.emailReceipt();
                break;
            case 'print':
                promise = this.printReceipt();
                break;
            default:
                promise = Promise.resolve();
        }

        return promise.then(_ => {
            this.resetPatron();
            this.router.navigate(['/staff/scko']);
        });
    }

    emailReceipt(): Promise<any> {

        const circIds = this.sessionCheckouts
            .filter(c => Boolean(c.circ)).map(c => c.circ.id());

        return this.net.request(
            'open-ils.circ',
            'open-ils.circ.checkout.batch_notify.session.atomic',
            this.auth.token(), this.patronSummary.id, circIds
        ).toPromise();
    }

    printReceipt(): Promise<any> {

        return new Promise((resolve, reject) => {

            const sub = this.printer.printJobQueued$.subscribe(_ => {
                sub.unsubscribe();
                // Give the print operation just a bit more time after
                // the data is passed to the printer just to be safe.
                setTimeout(() => resolve(null), 1000);
            });

            const data = this.sessionCheckouts.map(c => {
                const circ = c.circ || c.ctx.previousCirc;
                return {
                    checkout: c,
                    barcode: c.ctx.barcode,
                    circ: circ,
                    copy: circ ? circ.target_copy() : null,
                    title: this.getCircTitle(circ),
                    author: this.getCircAuthor(circ)
                };
            });

            this.printer.print({
                templateName: 'scko_checkouts',
                contextData: {
                    checkouts: data,
                    user: this.patronSummary.patron
                },
                printContext: 'default'
            });
        });
    }

    copyIsPrecat(copy: IdlObject): boolean {
        return Number(copy.id()) === -1;
    }

    circDisplayValue(circ: IdlObject, field: string): string {
        if (!circ) { return ''; }

        const entry =
            circ.target_copy().call_number().record().flat_display_entries()
            .filter(e => e.name() === field)[0];

        return entry ? entry.value() : '';
    }

    getCircTitle(circ: IdlObject): string {
        if (!circ) { return ''; }
        const copy = circ.target_copy();
        if (this.copyIsPrecat(copy)) { return copy.dummy_title(); }
        return this.circDisplayValue(circ, 'title');
    }

    getCircAuthor(circ: IdlObject): string {
        if (!circ) { return ''; }
        const copy = circ.target_copy();
        if (this.copyIsPrecat(copy)) { return copy.dummy_author(); }
        return this.circDisplayValue(circ, 'author');
    }

}



