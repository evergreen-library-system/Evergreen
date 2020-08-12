import {Injectable} from '@angular/core';
import {IdlObject} from '@eg/core/idl.service';
import {NetService} from '@eg/core/net.service';
import {AuthService} from '@eg/core/auth.service';
import {PatronService} from '@eg/staff/share/patron/patron.service';

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
        long_overdue: number
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

    constructor(
        private net: NetService,
        private auth: AuthService,
        public patronService: PatronService
    ) {}

    loadPatron(id: number): Promise<any> {
        this.loaded = false;
        this.patron = null;

        return this.net.request(
            'open-ils.actor',
            'open-ils.actor.user.fleshed.retrieve',
            this.auth.token(), id, PATRON_FLESH_FIELDS).toPromise()
        .then(patron => this.patron = patron)
        .then(_ => this.getPatronStats(id))
        .then(_ => this.loaded = true);
    }

   getPatronStats(id: number): Promise<any> {

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
                stats.checkouts.overdue + stats.checkouts.long_overdue

            if (!this.noTallyClaimsReturned) {
                stats.checkouts.total_out += stats.checkouts.claims_returned;
            }

            if (this.tallyLost) {
                stats.checkouts.total_out += stats.checkouts.lost
            }

            return this.patronStats = stats;
        });
    }
}


