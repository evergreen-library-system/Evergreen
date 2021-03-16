import {Injectable} from '@angular/core';
import {IdlObject} from '@eg/core/idl.service';
import {NetService} from '@eg/core/net.service';
import {OrgService} from '@eg/core/org.service';
import {AuthService} from '@eg/core/auth.service';
import {PatronService} from '@eg/staff/share/patron/patron.service';
import {PatronSearch} from '@eg/staff/share/patron/search.component';
import {StoreService} from '@eg/core/store.service';
import {CircService, CircDisplayInfo} from '@eg/staff/share/circ/circ.service';

export interface BillGridEntry extends CircDisplayInfo {
    xact: IdlObject // mbt
    billingLocation?: string;
    paymentPending?: number;
}

export interface CircGridEntry {
    title?: string;
    author?: string;
    isbn?: string;
    copy?: IdlObject;
    circ?: IdlObject;
    dueDate?: string;
    copyAlertCount: number;
    nonCatCount: number;
}

const PATRON_FLESH_FIELDS = [
    'card',
    'cards',
    'settings',
    'standing_penalties',
    'addresses',
    'billing_address',
    'mailing_address',
    'waiver_entries',
    'usr_activity',
    'notes',
    'profile',
    'net_access_level',
    'ident_type',
    'ident_type2',
    'groups'
];

interface PatronStats {
    fines: {balance_owed: number};
    checkouts: {
        overdue: number,
        claims_returned: number,
        lost: number,
        out: number,
        total_out: number,
        long_overdue: number,
        noncat: number
    };
    holds: {
        ready: number;
        total: number;
    };
}

export class PatronAlerts {
    holdsReady = 0;
    accountExpired = false;
    accountExpiresSoon = false;
    patronBarred = false;
    patronInactive = false;
    retrievedWithInactive = false;
    invalidAddress = false;
    alertMessage: string = null;
    alertPenalties: IdlObject[] = [];

    hasAlerts(): boolean {
        return (
            this.holdsReady > 0 ||
            this.accountExpired ||
            this.accountExpiresSoon ||
            this.patronBarred ||
            this.patronInactive ||
            this.retrievedWithInactive ||
            this.invalidAddress ||
            this.alertMessage !== null ||
            this.alertPenalties.length > 0
        );
    }
}

@Injectable()
export class PatronContextService {

    patron: IdlObject;
    patronStats: PatronStats;
    alerts: PatronAlerts;

    noTallyClaimsReturned = false; // circ.do_not_tally_claims_returned
    tallyLost = false; // circ.tally_lost

    loaded = false;

    lastPatronSearch: PatronSearch;
    searchBarcode: string = null;

    // These should persist tab changes
    checkouts: CircGridEntry[] = [];

    constructor(
        private store: StoreService,
        private net: NetService,
        private org: OrgService,
        private auth: AuthService,
        private circ: CircService,
        public patronService: PatronService
    ) {}

    loadPatron(id: number): Promise<any> {
        this.loaded = false;
        this.patron = null;
        this.checkouts = [];
        return this.refreshPatron(id).then(_ => this.loaded = true);
    }

    // Update the patron data without resetting all of the context data.
    refreshPatron(id?: number): Promise<any> {
        if (!id) { id = this.patron.id(); }

        this.alerts = new PatronAlerts();

        return this.net.request(
            'open-ils.actor',
            'open-ils.actor.user.fleshed.retrieve',
            this.auth.token(), id, PATRON_FLESH_FIELDS).toPromise()
        .then(p => this.patron = p)
        .then(_ => this.getPatronStats(id))
        .then(_ => this.compileAlerts());
    }

    getPatronStats(id: number): Promise<any> {

        // When quickly navigating patron search results it's possible
        // for this.patron to be cleared right before this function
        // is called.  Exit early instead of making an unneeded call.
        if (!this.patron) { return Promise.resolve(); }

        return this.net.request(
            'open-ils.actor',
            'open-ils.actor.user.opac.vital_stats.authoritative',
            this.auth.token(), id).toPromise()

        .then((stats: PatronStats) => {

            // force numeric values
            stats.fines.balance_owed = Number(stats.fines.balance_owed);

            Object.keys(stats.checkouts).forEach(key =>
                stats.checkouts[key] = Number(stats.checkouts[key]));

            stats.checkouts.total_out = stats.checkouts.out +
                stats.checkouts.overdue + stats.checkouts.long_overdue;

            if (!this.noTallyClaimsReturned) {
                stats.checkouts.total_out += stats.checkouts.claims_returned;
            }

            if (this.tallyLost) {
                stats.checkouts.total_out += stats.checkouts.lost;
            }

            this.patronStats = stats;

        }).then(_ => {

            if (!this.patron) { return; }

            return this.net.request(
                'open-ils.circ',
                'open-ils.circ.open_non_cataloged_circulation.user.authoritative',
                this.auth.token(), id).toPromise();

        }).then(noncats => {
            if (noncats && this.patronStats) {
                this.patronStats.checkouts.noncat = noncats.length;
            }
        });
    }

    patronAlertsShown(): boolean {
        if (!this.patron) { return false; }
        const shown = this.store.getSessionItem('eg.circ.last_alerted_patron');
        if (shown === this.patron.id()) { return true; }
        this.store.setSessionItem('eg.circ.last_alerted_patron', this.patron.id());
        return false;
    }

    compileAlerts(): Promise<any> {

        // User navigated to a different patron mid-data load.
        if (!this.patron) { return Promise.resolve(); }

        this.alerts.holdsReady = this.patronStats.holds.ready;
        this.alerts.patronBarred = this.patron.barred() === 't';
        this.alerts.patronInactive = this.patron.active() === 'f';
        this.alerts.invalidAddress = this.patron.addresses()
            .filter(a => a.valid() === 'f').length > 0;
        this.alerts.alertMessage = this.patron.alert_message();
        this.alerts.alertPenalties = this.patron.standing_penalties()
            .filter(p => p.standing_penalty().staff_alert() === 't');

        if (this.searchBarcode) {
            const card = this.patron.cards()
                .filter(c => c.barcode() === this.searchBarcode)[0];
            this.alerts.retrievedWithInactive = card && card.active() === 'f';
            this.searchBarcode = null;
        }

        return this.patronService.testExpire(this.patron)
        .then(value => {
            if (value === 'expired') {
                this.alerts.accountExpired = true;
            } else if (value === 'soon') {
                this.alerts.accountExpiresSoon = true;
            }
        });
    }

    orgSn(orgId: number): string {
        const org = this.org.get(orgId);
        return org ? org.shortname() : '';
    }

    formatXactForDisplay(xact: IdlObject): BillGridEntry {

        const entry: BillGridEntry = {
            xact: xact,
            paymentPending: 0
        };

        if (xact.summary().xact_type() !== 'circulation') {

            entry.xact.grocery().billing_location(
                this.org.get(entry.xact.grocery().billing_location()));

            entry.title = xact.summary().last_billing_type();
            entry.billingLocation =
                xact.grocery().billing_location().shortname();
            return entry;
        }

        entry.xact.circulation().circ_lib(
            this.org.get(entry.xact.circulation().circ_lib()));

        const circDisplay: CircDisplayInfo =
            this.circ.getDisplayInfo(xact.circulation());

        entry.billingLocation =
            xact.circulation().circ_lib().shortname();

        return Object.assign(entry, circDisplay);
    }
}


