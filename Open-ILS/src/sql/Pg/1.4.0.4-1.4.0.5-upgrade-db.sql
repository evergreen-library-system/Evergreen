/*
 * Copyright (C) 2009  Equinox Software, Inc.
 * Mike Rylander <miker@esilibrary.com>
 *
 * This program is free software; you can redistribute it and/or
 * modify it under the terms of the GNU General Public License
 * as published by the Free Software Foundation; either version 2
 * of the License, or (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 */


INSERT INTO config.upgrade_log (version) VALUES ('1.4.0.5');

CREATE OR REPLACE VIEW action.all_circulation AS
        SELECT  id,usr_post_code, usr_home_ou, usr_profile, usr_birth_year, copy_call_number, copy_location,
                copy_owning_lib, copy_circ_lib, copy_bib_record, xact_start, xact_finish, target_copy,
                circ_lib, circ_staff, checkin_staff, checkin_lib, renewal_remaining, due_date,
                stop_fines_time, checkin_time, create_time, duration, fine_interval, recuring_fine,
                max_fine, phone_renewal, desk_renewal, opac_renewal, duration_rule, recuring_fine_rule,
                max_fine_rule, stop_fines
          FROM  action.aged_circulation
                        UNION ALL
        SELECT  DISTINCT circ.id, COALESCE(a.post_code,b.post_code) AS usr_post_code, p.home_ou AS usr_home_ou, p.profile AS usr_profile,
                EXTRACT(YEAR FROM p.dob)::INT AS usr_birth_year,
                cp.call_number AS copy_call_number, cp.location AS copy_location, cn.owning_lib AS copy_owning_lib, cp.circ_lib AS copy_circ_lib,
                cn.record AS copy_bib_record, circ.xact_start, circ.xact_finish, circ.target_copy, circ.circ_lib, circ.circ_staff, circ.checkin_staff,
                circ.checkin_lib, circ.renewal_remaining, circ.due_date, circ.stop_fines_time, circ.checkin_time, circ.create_time, circ.duration,
                circ.fine_interval, circ.recuring_fine, circ.max_fine, circ.phone_renewal, circ.desk_renewal, circ.opac_renewal, circ.duration_rule,
                circ.recuring_fine_rule, circ.max_fine_rule, circ.stop_fines
          FROM  action.circulation circ
                JOIN asset.copy cp ON (circ.target_copy = cp.id)
                JOIN asset.call_number cn ON (cp.call_number = cn.id)
                JOIN actor.usr p ON (circ.usr = p.id)
                LEFT JOIN actor.usr_address a ON (p.mailing_address = a.id)
                LEFT JOIN actor.usr_address b ON (p.billing_address = a.id);

INSERT INTO permission.perm_list (code) VALUES ('UPDATE_ORG_UNIT_SETTING_ALL');
INSERT INTO permission.perm_list (code) VALUES ('UPDATE_ORG_UNIT_SETTING.circ.lost_materials_processing_fee');
INSERT INTO permission.perm_list (code) VALUES ('UPDATE_ORG_UNIT_SETTING.cat.default_item_price');
INSERT INTO permission.perm_list (code) VALUES ('UPDATE_ORG_UNIT_SETTING.auth.opac_timeout');
INSERT INTO permission.perm_list (code) VALUES ('UPDATE_ORG_UNIT_SETTING.auth.staff_timeout');
INSERT INTO permission.perm_list (code) VALUES ('UPDATE_ORG_UNIT_SETTING.org.bounced_emails');
INSERT INTO permission.perm_list (code) VALUES ('UPDATE_ORG_UNIT_SETTING.circ.hold_expire_alert_interval');
INSERT INTO permission.perm_list (code) VALUES ('UPDATE_ORG_UNIT_SETTING.circ.hold_expire_interval');
INSERT INTO permission.perm_list (code) VALUES ('UPDATE_ORG_UNIT_SETTING.global.credit.allow');
INSERT INTO permission.perm_list (code) VALUES ('UPDATE_ORG_UNIT_SETTING.global.default_locale');
INSERT INTO permission.perm_list (code) VALUES ('UPDATE_ORG_UNIT_SETTING.circ.void_overdue_on_lost');
INSERT INTO permission.perm_list (code) VALUES ('UPDATE_ORG_UNIT_SETTING.circ.hold_stalling.soft');
INSERT INTO permission.perm_list (code) VALUES ('UPDATE_ORG_UNIT_SETTING.circ.hold_boundary.hard');
INSERT INTO permission.perm_list (code) VALUES ('UPDATE_ORG_UNIT_SETTING.circ.hold_boundary.soft');
INSERT INTO permission.perm_list (code) VALUES ('UPDATE_ORG_UNIT_SETTING.opac.barcode_regex');
INSERT INTO permission.perm_list (code) VALUES ('UPDATE_ORG_UNIT_SETTING.circ.item_checkout_history.max');
INSERT INTO permission.perm_list (code) VALUES ('UPDATE_ORG_UNIT_SETTING.circ.reshelving_complete.interval');
INSERT INTO permission.perm_list (code) VALUES ('UPDATE_ORG_UNIT_SETTING.circ.selfcheck.patron_login_timeout');
INSERT INTO permission.perm_list (code) VALUES ('UPDATE_ORG_UNIT_SETTING.circ.selfcheck.alert_on_checkout_event');
INSERT INTO permission.perm_list (code) VALUES ('UPDATE_ORG_UNIT_SETTING.circ.selfcheck.require_patron_password');
INSERT INTO permission.perm_list (code) VALUES ('UPDATE_ORG_UNIT_SETTING.cat.bib.keep_on_empty');
INSERT INTO permission.perm_list (code) VALUES ('UPDATE_ORG_UNIT_SETTING.cat.bib.alert_on_empty');

