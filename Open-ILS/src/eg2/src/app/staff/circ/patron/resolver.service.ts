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

        // Some of these are used by the shared circ services.
        // Precache them since we're making the call anyway.
        return this.store.getItemBatch([
          'circ.bills.receiptonpay',
          'eg.circ.bills.annotatepayment',
          'eg.circ.patron.summary.collapse',
          'circ.do_not_tally_claims_returned',
          'circ.tally_lost',
          'ui.staff.require_initials.patron_standing_penalty',
          'ui.admin.work_log.max_entries',
          'ui.admin.patron_log.max_entries',
          'circ.staff_client.do_not_auto_attempt_print',
          'circ.clear_hold_on_checkout',
          'ui.circ.suppress_checkin_popups',
          'ui.circ.billing.uncheck_bills_and_unfocus_payment_box',
          'ui.circ.billing.amount_warn',
          'ui.circ.billing.amount_limit',
          'circ.staff_client.do_not_auto_attempt_print',
          'circ.disable_patron_credit',
          'sms.enable',
          'ui.patron.registration.require_address',
          'credit.processor.default'
        ]).then(settings => {
            this.context.noTallyClaimsReturned =
                settings['circ.do_not_tally_claims_returned'];
            this.context.tallyLost = settings['circ.tally_lost'];
        });
    }
}

