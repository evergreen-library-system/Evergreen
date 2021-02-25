import {Injectable} from '@angular/core';
import {Router, Resolve, RouterStateSnapshot,
        ActivatedRouteSnapshot} from '@angular/router';
import {ServerStoreService} from '@eg/core/server-store.service';
import {NetService} from '@eg/core/net.service';
import {OrgService} from '@eg/core/org.service';
import {AuthService} from '@eg/core/auth.service';
import {PatronContextService} from './patron.service';


@Injectable()
export class PatronResolver implements Resolve<Promise<any[]>> {

    constructor(
        private store: ServerStoreService,
        private context: PatronContextService
    ) {}

    resolve(
        route: ActivatedRouteSnapshot,
        state: RouterStateSnapshot): Promise<any[]> {

        return this.fetchSettings();
    }

    fetchSettings(): Promise<any> {

        return this.store.getItemBatch([
          'eg.circ.patron.summary.collapse',
          'circ.do_not_tally_claims_returned',
          'circ.tally_lost'

        ]).then(settings => {
            this.context.noTallyClaimsReturned =
                settings['circ.do_not_tally_claims_returned'];
            this.context.tallyLost = settings['circ.tally_lost'];
        });
    }
}

