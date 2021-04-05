import {Injectable, EventEmitter} from '@angular/core';
import {IdlObject} from '@eg/core/idl.service';
import {NetService} from '@eg/core/net.service';
import {OrgService} from '@eg/core/org.service';
import {AuthService} from '@eg/core/auth.service';
import {PatronService, PatronStats, PatronAlerts
    } from '@eg/staff/share/patron/patron.service';
import {PatronSearch} from '@eg/staff/share/patron/search.component';
import {StoreService} from '@eg/core/store.service';
import {CircService, CircDisplayInfo} from '@eg/staff/share/circ/circ.service';

export interface BillGridEntry extends CircDisplayInfo {
    xact: IdlObject; // mbt
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

@Injectable()
export class PatronContextService {

    patron: IdlObject;
    patronStats: PatronStats;
    alerts: PatronAlerts;

    loaded = false;

    lastPatronSearch: PatronSearch;
    searchBarcode: string = null;

    // These should persist tab changes
    checkouts: CircGridEntry[] = [];

    settingsCache: {[key: string]: any} = {};

    constructor(
        private store: StoreService,
        private org: OrgService,
        private circ: CircService,
        public patrons: PatronService
    ) {}

    loadPatron(id: number): Promise<any> {
        this.loaded = false;
        this.checkouts = [];
        return this.refreshPatron(id).then(_ => this.loaded = true);
    }

    // Update the patron data without resetting all of the context data.
    refreshPatron(id?: number): Promise<any> {
        if (!id) { id = this.patron.id(); }

        this.alerts = new PatronAlerts();

        return this.patrons.getFleshedById(id, PATRON_FLESH_FIELDS)
        .then(p => this.patron = p)
        .then(_ => this.getPatronStats(id))
        .then(_ => this.compileAlerts());
    }

    getPatronStats(id: number): Promise<any> {

        // When quickly navigating patron search results it's possible
        // for this.patron to be cleared right before this function
        // is called.  Exit early instead of making an unneeded call.
        if (!this.patron) { return Promise.resolve(); }

        return this.patrons.getVitalStats(this.patron)
        .then(stats => this.patronStats = stats);
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

        return this.patrons.compileAlerts(this.patron, this.patronStats)
        .then(alerts => {
            this.alerts = alerts;

            if (this.searchBarcode) {
                const card = this.patron.cards()
                    .filter(c => c.barcode() === this.searchBarcode)[0];
                this.alerts.retrievedWithInactive = card && card.active() === 'f';
                this.searchBarcode = null;
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


