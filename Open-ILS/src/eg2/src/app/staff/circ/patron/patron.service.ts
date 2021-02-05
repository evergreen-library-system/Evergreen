import {Injectable} from '@angular/core';
import {IdlObject} from '@eg/core/idl.service';
import {NetService} from '@eg/core/net.service';
import {AuthService} from '@eg/core/auth.service';
import {PatronService} from '@eg/staff/share/patron/patron.service';
import {PatronSearch} from '@eg/staff/share/patron/search.component';

export interface CircGridEntry {
    title?: string;
    copy?: IdlObject;
    circ?: IdlObject;
    dueDate?: string;
    copyAlertCount: number;
}

const PATRON_FLESH_FIELDS = [
    'card',
    'cards',
    'settings',
    'standing_penalties',
    'addresses',
    'billing_address',
    'mailing_address',
    'stat_cat_entries',
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

@Injectable()
export class PatronManagerService {

    patron: IdlObject;
    patronStats: PatronStats;

    // Value for YAOUS circ.do_not_tally_claims_returned
    noTallyClaimsReturned = false;

    // Value for YAOUS circ.tally_lost
    tallyLost = false;

    loaded = false;

    accountExpired = false;
    accountExpiresSoon = false;

    lastPatronSearch: PatronSearch;

    // These should persist tab changes
    checkouts: CircGridEntry[] = [];
    dueDateOptions: 0 | 1 | 2 = 0; // auto date; specific date; session date

    constructor(
        private net: NetService,
        private auth: AuthService,
        public patronService: PatronService
    ) {}

    loadPatron(id: number): Promise<any> {
        this.loaded = false;
        this.patron = null;
        this.checkouts = [];

        return this.net.request(
            'open-ils.actor',
            'open-ils.actor.user.fleshed.retrieve',
            this.auth.token(), id, PATRON_FLESH_FIELDS).toPromise()
        .then(p => this.patron = p)
        .then(_ => this.getPatronStats(id))
        .then(_ => this.setExpires())
        .then(_ => this.loaded = true);
    }

    setExpires(): Promise<any> {
        this.accountExpired = false;
        this.accountExpiresSoon = false;

        // When quickly navigating patron search results it's possible
        // for this.patron to be cleared right before this function
        // is called.  Exit early instead of making an unneeded call.
        // For this func. in particular a nasty JS error is thrown.
        if (!this.patron) { return Promise.resolve(); }

        return this.patronService.testExpire(this.patron)
        .then(value => {
            if (value === 'expired') {
                this.accountExpired = true;
            } else if (value === 'soon') {
                this.accountExpiresSoon = true;
            }
        });
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
}


