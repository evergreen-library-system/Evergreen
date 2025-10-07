import {Injectable} from '@angular/core';
import {tap, Observable} from 'rxjs';
import {IdlObject} from '@eg/core/idl.service';
import {NetService} from '@eg/core/net.service';
import {OrgService} from '@eg/core/org.service';
import {EventService} from '@eg/core/event.service';
import {PcrudService} from '@eg/core/pcrud.service';
import {AuthService} from '@eg/core/auth.service';
import {ServerStoreService} from '@eg/core/server-store.service';

export class PatronStats {
    fines = {
        balance_owed: 0,
        group_balance_owed: 0
    };

    checkouts = {
        overdue: 0,
        claims_returned: 0,
        lost: 0,
        out: 0,
        total_out: 0,
        long_overdue: 0,
        noncat: 0
    };

    holds = {
        ready: 0,
        total: 0
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
    alertPenalties: IdlObject[] = [];
    allPenalties: IdlObject[] = [];

    hasAlerts(): boolean {
        return (
            this.holdsReady > 0 ||
            this.accountExpired ||
            this.accountExpiresSoon ||
            this.patronBarred ||
            this.patronInactive ||
            this.retrievedWithInactive ||
            this.invalidAddress ||
            this.alertPenalties.length > 0
        );
    }
}

export class PatronSummary {
    id: number;
    patron: IdlObject;
    stats: PatronStats = new PatronStats();
    alerts: PatronAlerts = new PatronAlerts();

    constructor(patron?: IdlObject) {
        if (patron) {
            this.id = patron.id();
            this.patron = patron;
        }
    }
}

@Injectable()
export class PatronService {

    identTypes: IdlObject[];
    inetLevels: IdlObject[];
    profileGroups: IdlObject[];
    smsCarriers: IdlObject[];
    statCats: IdlObject[];
    surveys: IdlObject[];

    constructor(
        private net: NetService,
        private org: OrgService,
        private evt: EventService,
        private pcrud: PcrudService,
        private auth: AuthService,
        private store: ServerStoreService
    ) {}

    bcSearch(barcode: string): Observable<any> {
        return this.net.request(
            'open-ils.actor',
            'open-ils.actor.get_barcodes',
            this.auth.token(), this.auth.user().ws_ou(),
            'actor', barcode.trim());
    }

    // XXX: This assumes the provided barcode only matches a single patron.
    // Use the <eg-barcode-select> component instead when the provided
    // barcode could match multiple patrons.
    //
    // Note pcrudOps should be constructed from the perspective
    // of a user ('au') retrieval, not a barcode ('ac') retrieval.
    getByBarcode(barcode: string, pcrudOps?: any): Promise<IdlObject> {
        return this.bcSearch(barcode).toPromise()
            .then(barcodes => {
                if (!barcodes) { return null; }

                // Use the first successful barcode response.
                // Use for-loop for early exit since we have async
                // action within the loop.
                for (let i = 0; i < barcodes.length; i++) {
                    const bc = barcodes[i];
                    if (!this.evt.parse(bc)) {
                        return this.getById(bc.id, pcrudOps);
                    }
                }

                return null;
            });
    }

    getById(id: number, pcrudOps?: any): Promise<IdlObject> {
        return this.pcrud.retrieve('au', id, pcrudOps).toPromise();
    }


    // Alternate retrieval method that uses the fleshed user API,
    // which performs some additional data munging on the back end.
    getFleshedById(id: number, fleshFields?: string[]): Promise<IdlObject> {
        return this.net.request(
            'open-ils.actor',
            'open-ils.actor.user.fleshed.retrieve',
            this.auth.token(), id, fleshFields).toPromise();
    }

    // Returns a trimmed name part (e.g., family_name) preferring the
    // preferred value when available. Null/undefined/empty become ''.
    namePart(patron: IdlObject, part: string): string {
        if (!patron) { return ''; }
        const raw = patron['pref_' + part]() || patron[part]();
        return (raw && String(raw).trim()) || '';
    }


    // Returns promise of 'expired', 'soon', or null depending on the
    // expire date disposition of the provided patron.
    testExpire(patron: IdlObject): Promise<'expired' | 'soon'> {

        const expire = new Date(Date.parse(patron.expire_date()));
        if (expire < new Date()) {
            return Promise.resolve('expired');
        }

        return this.org.settings(['circ.patron_expires_soon_warning'])
            .then(setting => {
                const days = setting['circ.patron_expires_soon_warning'];

                if (Number(days)) {
                    const preExpire = new Date();
                    preExpire.setDate(preExpire.getDate() + Number(days));
                    if (expire < preExpire) { return 'soon'; }
                }

                return null;
            });
    }

    getIdentTypes(): Promise<IdlObject[]> {
        if (this.identTypes) {
            return Promise.resolve(this.identTypes);
        }

        return this.pcrud.retrieveAll('cit',
            {order_by: {cit: ['name']}}, {atomic: true})
            .toPromise().then(types => this.identTypes = types);
    }

    getInetLevels(): Promise<IdlObject[]> {
        if (this.inetLevels) {
            return Promise.resolve(this.inetLevels);
        }

        return this.pcrud.retrieveAll('cnal',
            {order_by: {cit: ['name']}}, {atomic: true})
            .toPromise().then(levels => this.inetLevels = levels);
    }

    getProfileGroups(): Promise<IdlObject[]> {
        if (this.profileGroups) {
            return Promise.resolve(this.profileGroups);
        }

        return this.pcrud.retrieveAll('pgt',
            {order_by: {cit: ['name']}}, {atomic: true})
            .toPromise().then(types => this.profileGroups = types);
    }

    getSmsCarriers(): Promise<IdlObject[]> {
        if (this.smsCarriers) {
            return Promise.resolve(this.smsCarriers);
        }

        this.smsCarriers = [];
        return this.pcrud.search(
            'csc', {active: 't'}, {order_by: {csc: 'name'}})
            .pipe(tap(carrier => this.smsCarriers.push(carrier))
            ).toPromise().then(_ => this.smsCarriers);
    }

    // Local stat cats fleshed with entries; sorted.
    getStatCats(): Promise<IdlObject[]> {
        if (this.statCats) {
            return Promise.resolve(this.statCats);
        }

        return this.net.request(
            'open-ils.circ',
            'open-ils.circ.stat_cat.actor.retrieve.all',
            this.auth.token(), this.auth.user().ws_ou()
        ).toPromise().then(cats => {
            cats.sort((a, b) => a.name() < b.name() ? -1 : 1);
            cats.forEach(cat => {
                cat.entries(
                    cat.entries().sort((a, b) => a.value() < b.value() ? -1 : 1)
                );
            });
            return cats;
        });
    }

    getSurveys(): Promise<IdlObject[]> {
        if (this.surveys) {
            return Promise.resolve(this.surveys);
        }

        const orgIds = this.org.fullPath(this.auth.user().ws_ou(), true);

        return this.pcrud.search('asv', {
            owner: orgIds,
            start_date: {'<=': 'now'},
            end_date: {'>=': 'now'}
        }, {
            flesh: 2,
            flesh_fields: {
                asv: ['questions'],
                asvq: ['answers']
            }
        },
        {atomic : true}
        ).toPromise().then(surveys => {
            return this.surveys =
                surveys.sort((s1, s2) => s1.name() < s2.name() ? -1 : 1);
        });
    }

    getVitalStats(patron: IdlObject): Promise<PatronStats> {

        let patronStats: PatronStats;
        let noTallyClaimsReturned, tallyLost;

        return this.store.getItemBatch([
            'circ.do_not_tally_claims_returned',
            'circ.tally_lost'

        ]).then(settings => {

            noTallyClaimsReturned = settings['circ.do_not_tally_claims_returned'];
            tallyLost = settings['circ.tally_lost'];

        }).then(_ => {

            return this.net.request(
                'open-ils.actor',
                'open-ils.actor.user.opac.vital_stats.authoritative',
                this.auth.token(), patron.id()).toPromise();

        }).then((stats: PatronStats) => {

            // force numeric values
            stats.fines.balance_owed = Number(stats.fines.balance_owed);

            Object.keys(stats.checkouts).forEach(key =>
                stats.checkouts[key] = Number(stats.checkouts[key]));

            stats.checkouts.total_out = stats.checkouts.out +
                stats.checkouts.overdue + stats.checkouts.long_overdue;

            if (!noTallyClaimsReturned) {
                stats.checkouts.total_out += stats.checkouts.claims_returned;
            }

            if (tallyLost) {
                stats.checkouts.total_out += stats.checkouts.lost;
            }

            return patronStats = stats;

        }).then(_ => {
            return this.pcrud.search('aoncc',
                {patron: patron.id()}, {}, {idlist: true, atomic: true}).toPromise();

        }).then(noncats => {
            if (noncats && patronStats) {
                patronStats.checkouts.noncat = noncats.length;
            }

            return this.net.request(
                'open-ils.actor',
                'open-ils.actor.usergroup.members.balance_owed.authoritative',
                this.auth.token(), patron.usrgroup()
            ).toPromise();

        }).then(fines => {

            let total = 0;
            fines.forEach(f => total += Number(f.balance_owed) * 100);
            patronStats.fines.group_balance_owed = total / 100;

            return patronStats;
        });
    }

    compileAlerts(summary: PatronSummary): Promise<PatronAlerts> {

        const patron = summary.patron;
        const stats = summary.stats;
        const alerts = new PatronAlerts();

        alerts.holdsReady = stats.holds.ready;
        alerts.patronBarred = patron.barred() === 't';
        alerts.patronInactive = patron.active() === 'f';
        alerts.invalidAddress = patron.addresses()
            .filter(a => a.valid() === 'f').length > 0;
        alerts.alertPenalties = patron.standing_penalties()
            .filter(p => p.standing_penalty().staff_alert() === 't');
        alerts.allPenalties = patron.standing_penalties();

        return this.testExpire(patron)
            .then(value => {
                if (value === 'expired') {
                    alerts.accountExpired = true;
                } else if (value === 'soon') {
                    alerts.accountExpiresSoon = true;
                }

                return alerts;
            });
    }

    patronStatusColor(patron: IdlObject, summary: PatronSummary): string {

        if (patron.barred() === 't') {
            return 'PATRON_BARRED';
        }

        if (patron.active() === 'f') {
            return 'PATRON_INACTIVE';
        }

        if (summary.stats.fines.balance_owed > 0) {
            return 'PATRON_HAS_BILLS';
        }

        if (summary.stats.checkouts.overdue > 0) {
            return 'PATRON_HAS_OVERDUES';
        }

        if (summary.alerts.accountExpired || summary.alerts.accountExpiresSoon) {
            return 'PATRON_EXPIRED';
        }

        if (patron.notes().length > 0) {
            return 'PATRON_HAS_NOTES';
        }

        if (summary.stats.checkouts.lost > 0) {
            return 'PATRON_HAS_LOST';
        }

        let penalty: string;
        let penaltyCount = 0;

        patron.standing_penalties().some(p => {

            if (p.standing_penalty().staff_alert() === 't' ||
                p.standing_penalty().block_list()) {
                penalty = 'PATRON_HAS_STAFF_ALERT';
                return true;
            }

            if (p.standing_penalty().block_list()) {
                // Penalties without a block are just Notes
                penaltyCount++;
            }

            const name = p.standing_penalty();

            switch (name) {
                case 'PATRON_EXCEEDS_CHECKOUT_COUNT':
                case 'PATRON_EXCEEDS_OVERDUE_COUNT':
                case 'PATRON_EXCEEDS_FINES':
                    penalty = name;
                    return true;
            }
        });

        if (penalty) { return penalty; }

        if (penaltyCount === 1) {
            return 'ONE_PENALTY';
        } else if (penaltyCount > 1) {
            return 'MULTIPLE_PENALTIES';
        }

        if (patron.alert_message()) {
            return 'PATRON_HAS_ALERT';
        }

        if (patron.juvenile() === 't') {
            return 'PATRON_JUVENILE';
        }

        return 'NO_PENALTIES';
    }
}

