import {Injectable} from '@angular/core';
import {Router, Resolve, RouterStateSnapshot,
    ActivatedRouteSnapshot} from '@angular/router';
import {ServerStoreService} from '@eg/core/server-store.service';
import {NetService} from '@eg/core/net.service';
import {OrgService} from '@eg/core/org.service';
import {AuthService} from '@eg/core/auth.service';
import {PatronContextService} from './patron.service';
import {CircService} from '@eg/staff/share/circ/circ.service';

@Injectable()
export class PatronResolver implements Resolve<Promise<any[]>> {

    constructor(
        private store: ServerStoreService,
        private context: PatronContextService,
        private circ: CircService
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
            'ui.staff.max_recent_patrons',
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
            'credit.processor.default',
            'global.password_regex',
            'global.juvenile_age_threshold',
            'patron.password.use_phone',
            'ui.patron.default_inet_access_level',
            'ui.patron.default_ident_type',
            'ui.patron.default_country',
            'ui.patron.registration.require_address',
            'circ.holds.behind_desk_pickup_supported',
            'circ.patron_edit.clone.copy_address',
            'circ.privacy_waiver',
            'ui.patron.edit.au.prefix.require',
            'ui.patron.edit.au.prefix.show',
            'ui.patron.edit.au.prefix.suggest',
            'ui.patron.edit.ac.barcode.regex',
            'ui.patron.edit.au.second_given_name.show',
            'ui.patron.edit.au.second_given_name.suggest',
            'ui.patron.edit.au.suffix.show',
            'ui.patron.edit.au.suffix.suggest',
            'ui.patron.edit.au.alias.show',
            'ui.patron.edit.au.alias.suggest',
            'ui.patron.edit.au.dob.require',
            'ui.patron.edit.au.dob.show',
            'ui.patron.edit.au.dob.suggest',
            'ui.patron.edit.au.dob.calendar',
            'ui.patron.edit.au.dob.example',
            'ui.patron.edit.au.juvenile.show',
            'ui.patron.edit.au.juvenile.suggest',
            'ui.patron.edit.au.ident_value.show',
            'ui.patron.edit.au.ident_value.require',
            'ui.patron.edit.au.ident_value.suggest',
            'ui.patron.edit.au.ident_value2.show',
            'ui.patron.edit.au.ident_value2.suggest',
            'ui.patron.edit.au.email.require',
            'ui.patron.edit.au.email.show',
            'ui.patron.edit.au.email.suggest',
            'ui.patron.edit.au.email.regex',
            'ui.patron.edit.au.email.example',
            'ui.patron.edit.au.day_phone.require',
            'ui.patron.edit.au.day_phone.show',
            'ui.patron.edit.au.day_phone.suggest',
            'ui.patron.edit.au.day_phone.regex',
            'ui.patron.edit.au.day_phone.example',
            'ui.patron.edit.au.evening_phone.require',
            'ui.patron.edit.au.evening_phone.show',
            'ui.patron.edit.au.evening_phone.suggest',
            'ui.patron.edit.au.evening_phone.regex',
            'ui.patron.edit.au.evening_phone.example',
            'ui.patron.edit.au.other_phone.require',
            'ui.patron.edit.au.other_phone.show',
            'ui.patron.edit.au.other_phone.suggest',
            'ui.patron.edit.au.other_phone.regex',
            'ui.patron.edit.au.other_phone.example',
            'ui.patron.edit.aus.default_phone.regex',
            'ui.patron.edit.aus.default_phone.example',
            'ui.patron.edit.aus.default_sms_notify.regex',
            'ui.patron.edit.aus.default_sms_notify.example',
            'ui.patron.edit.phone.regex',
            'ui.patron.edit.phone.example',
            'ui.patron.edit.au.active.show',
            'ui.patron.edit.au.active.suggest',
            'ui.patron.edit.au.barred.show',
            'ui.patron.edit.au.barred.suggest',
            'ui.patron.edit.au.master_account.show',
            'ui.patron.edit.au.master_account.suggest',
            'ui.patron.edit.au.claims_returned_count.show',
            'ui.patron.edit.au.claims_returned_count.suggest',
            'ui.patron.edit.au.claims_never_checked_out_count.show',
            'ui.patron.edit.au.claims_never_checked_out_count.suggest',
            'ui.patron.edit.au.alert_message.show',
            'ui.patron.edit.au.alert_message.suggest',
            'ui.patron.edit.aua.post_code.regex',
            'ui.patron.edit.aua.post_code.example',
            'ui.patron.edit.aua.county.require',
            'ui.patron.edit.au.guardian.show',
            'ui.patron.edit.au.guardian.suggest',
            'ui.patron.edit.guardian_required_for_juv',
            'format.date',
            'ui.patron.edit.default_suggested',
            'opac.barcode_regex',
            'opac.username_regex',
            'sms.enable',
            'circ.obscure_dob',
            'ui.patron.edit.aua.state.require',
            'ui.patron.edit.aua.state.suggest',
            'ui.patron.edit.aua.state.show',
            'ui.admin.work_log.max_entries',
            'ui.admin.patron_log.max_entries',
            'circ.patron_expires_soon_warning'
        ]).then(settings => {
            this.context.settingsCache = settings;
            return this.circ.applySettings();
        });
    }
}

