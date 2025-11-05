import {Injectable, EventEmitter} from '@angular/core';
import {IdlObject} from '@eg/core/idl.service';
import {NetService} from '@eg/core/net.service';
import {OrgService} from '@eg/core/org.service';
import {AuthService} from '@eg/core/auth.service';
import {PatronService, PatronSummary, PatronStats, PatronAlerts
} from '@eg/staff/share/patron/patron.service';
import {PatronSearch} from '@eg/staff/share/patron/search.component';
import {StoreService} from '@eg/core/store.service';
import {ServerStoreService} from '@eg/core/server-store.service';
import {CircService, CircDisplayInfo} from '@eg/staff/share/circ/circ.service';

export interface BillGridEntry extends CircDisplayInfo {
    xact: IdlObject; // mbt
    billingLocation?: string;
    paymentPending?: number;
}

export interface CircGridEntry {
    index: number;
    title?: string;
    author?: string;
    isbn?: string;
    copy?: IdlObject;
    circ?: IdlObject;
    volume?: IdlObject;
    record?: IdlObject;
    dueDate?: string;
    copyAlertCount: number;
    nonCatCount: number;
    patron: IdlObject;
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

    summary: PatronSummary;
    loaded = false;
    lastPatronSearch: PatronSearch;
    searchBarcode: string = null;

    // These should persist tab changes
    checkouts: CircGridEntry[] = [];

    maxRecentPatrons = 1;

    settingsCache: {[key: string]: any} = {};

    constructor(
        private store: StoreService,
        private serverStore: ServerStoreService,
        private org: OrgService,
        private circ: CircService,
        public patrons: PatronService
    ) {}

    reset() {
        this.summary = null;
        this.loaded = false;
        this.lastPatronSearch = null;
        this.searchBarcode = null;
        this.checkouts = [];
    }

    loadPatron(id: number): Promise<any> {
        this.loaded = false;
        this.checkouts = [];
        return this.refreshPatron(id).then(_ => this.loaded = true);
    }

    // Update the patron data without resetting all of the context data.
    refreshPatron(id?: number): Promise<any> {

        if (!id) {
            if (!this.summary) {
                return Promise.resolve();
            } else {
                id = this.summary.id;
            }
        }

        return this.patrons.getFleshedById(id, PATRON_FLESH_FIELDS)
            .then(p => this.summary = new PatronSummary(p))
            .then(_ => this.getPatronStats(id))
            .then(_ => this.formatSummaryUserSettings())
            .then(_ => this.compileAlerts())
            .then(_ => this.addRecentPatron());
    }

    addRecentPatron(patronId?: number): Promise<any> {

        if (!patronId) { patronId = this.summary.id; }

        return this.serverStore.getItem('ui.staff.max_recent_patrons')
            .then(num => {
                if (num) { this.maxRecentPatrons = num; }

                let patrons: number[] =
                this.store.getLoginSessionItem('eg.circ.recent_patrons') || [];

                // remove potential existing duplicates
                patrons = patrons.filter(id => patronId !== id);
                patrons.splice(0, 0, patronId);  // put this user at front
                patrons.splice(this.maxRecentPatrons); // remove excess

                this.store.setLoginSessionItem('eg.circ.recent_patrons', patrons);
            });
    }

    getPatronStats(id: number): Promise<any> {

        // When quickly navigating patron search results it's possible
        // for this.patron to be cleared right before this function
        // is called.  Exit early instead of making an unneeded call.
        if (!this.summary) { return Promise.resolve(); }

        return this.patrons.getVitalStats(this.summary.patron)
            .then(stats => this.summary.stats = stats);
    }

    formatSummaryUserSettings(): Promise<void> {
        if (!this.summary) { return Promise.resolve(); }

        return this.patrons.formatSupportedSettings(
            this.summary.patron?.settings() || []
        ).then(settings => {
            this.summary.settings = settings;
        });
    }


    patronAlertsShown(): boolean {
        if (!this.summary) { return false; }
        this.store.addLoginSessionKey('eg.circ.last_alerted_patron');
        const shown = this.store.getLoginSessionItem('eg.circ.last_alerted_patron');
        if (shown === this.summary.patron.id()) { return true; }
        this.store.setLoginSessionItem('eg.circ.last_alerted_patron', this.summary.patron.id());
        return false;
    }

    compileAlerts(): Promise<any> {

        // User navigated to a different patron mid-data load.
        if (!this.summary) { return Promise.resolve(); }

        return this.patrons.compileAlerts(this.summary)
            .then(alerts => {
                this.summary.alerts = alerts;

                if (this.searchBarcode) {
                    const card = this.summary.patron.cards()
                        .filter(c => c.barcode() === this.searchBarcode)[0];
                    this.summary.alerts.retrievedWithInactive =
                    card && card.active() === 'f';
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


