BEGIN;

SELECT evergreen.upgrade_deps_block_check('0945', :eg_version);

DROP VIEW action.all_circulation;
DROP VIEW reporter.demographic;
DROP VIEW auditor.actor_usr_lifecycle;
DROP VIEW action.all_hold_request;

ALTER TABLE actor.usr ALTER dob TYPE date USING (dob + '3 hours')::date;

CREATE VIEW auditor.actor_usr_lifecycle AS
     SELECT (-1) AS audit_id, now() AS audit_time,
        '-'::text AS audit_action, (-1) AS audit_user, (-1) AS audit_ws,
        usr.id, usr.card, usr.profile, usr.usrname, usr.email, usr.passwd,
        usr.standing, usr.ident_type, usr.ident_value, usr.ident_type2,
        usr.ident_value2, usr.net_access_level, usr.photo_url, usr.prefix,
        usr.first_given_name, usr.second_given_name, usr.family_name,
        usr.suffix, usr.alias, usr.day_phone, usr.evening_phone,
        usr.other_phone, usr.mailing_address, usr.billing_address,
        usr.home_ou, usr.dob, usr.active, usr.master_account,
        usr.super_user, usr.barred, usr.deleted, usr.juvenile, usr.usrgroup,
        usr.claims_returned_count, usr.credit_forward_balance,
        usr.last_xact_id, usr.alert_message, usr.create_date,
        usr.expire_date, usr.claims_never_checked_out_count,
        usr.last_update_time
       FROM actor.usr
UNION ALL
     SELECT actor_usr_history.audit_id, actor_usr_history.audit_time,
        actor_usr_history.audit_action, actor_usr_history.audit_user,
        actor_usr_history.audit_ws, actor_usr_history.id,
        actor_usr_history.card, actor_usr_history.profile,
        actor_usr_history.usrname, actor_usr_history.email,
        actor_usr_history.passwd, actor_usr_history.standing,
        actor_usr_history.ident_type, actor_usr_history.ident_value,
        actor_usr_history.ident_type2, actor_usr_history.ident_value2,
        actor_usr_history.net_access_level, actor_usr_history.photo_url,
        actor_usr_history.prefix, actor_usr_history.first_given_name,
        actor_usr_history.second_given_name, actor_usr_history.family_name,
        actor_usr_history.suffix, actor_usr_history.alias,
        actor_usr_history.day_phone, actor_usr_history.evening_phone,
        actor_usr_history.other_phone, actor_usr_history.mailing_address,
        actor_usr_history.billing_address, actor_usr_history.home_ou,
        actor_usr_history.dob, actor_usr_history.active,
        actor_usr_history.master_account, actor_usr_history.super_user,
        actor_usr_history.barred, actor_usr_history.deleted,
        actor_usr_history.juvenile, actor_usr_history.usrgroup,
        actor_usr_history.claims_returned_count,
        actor_usr_history.credit_forward_balance,
        actor_usr_history.last_xact_id, actor_usr_history.alert_message,
        actor_usr_history.create_date, actor_usr_history.expire_date,
        actor_usr_history.claims_never_checked_out_count,
        actor_usr_history.last_update_time
       FROM auditor.actor_usr_history;

CREATE VIEW reporter.demographic AS
    SELECT u.id, u.dob,
        CASE
            WHEN u.dob IS NULL THEN 'Adult'::text
            WHEN age(u.dob) > '18 years'::interval THEN 'Adult'::text
            ELSE 'Juvenile'::text
        END AS general_division
    FROM actor.usr u;

CREATE VIEW action.all_circulation AS
         SELECT aged_circulation.id, aged_circulation.usr_post_code,
            aged_circulation.usr_home_ou, aged_circulation.usr_profile,
            aged_circulation.usr_birth_year, aged_circulation.copy_call_number,
            aged_circulation.copy_location, aged_circulation.copy_owning_lib,
            aged_circulation.copy_circ_lib, aged_circulation.copy_bib_record,
            aged_circulation.xact_start, aged_circulation.xact_finish,
            aged_circulation.target_copy, aged_circulation.circ_lib,
            aged_circulation.circ_staff, aged_circulation.checkin_staff,
            aged_circulation.checkin_lib, aged_circulation.renewal_remaining,
            aged_circulation.grace_period, aged_circulation.due_date,
            aged_circulation.stop_fines_time, aged_circulation.checkin_time,
            aged_circulation.create_time, aged_circulation.duration,
            aged_circulation.fine_interval, aged_circulation.recurring_fine,
            aged_circulation.max_fine, aged_circulation.phone_renewal,
            aged_circulation.desk_renewal, aged_circulation.opac_renewal,
            aged_circulation.duration_rule,
            aged_circulation.recurring_fine_rule,
            aged_circulation.max_fine_rule, aged_circulation.stop_fines,
            aged_circulation.workstation, aged_circulation.checkin_workstation,
            aged_circulation.checkin_scan_time, aged_circulation.parent_circ
           FROM action.aged_circulation
UNION ALL
         SELECT DISTINCT circ.id,
            COALESCE(a.post_code, b.post_code) AS usr_post_code,
            p.home_ou AS usr_home_ou, p.profile AS usr_profile,
            date_part('year'::text, p.dob)::integer AS usr_birth_year,
            cp.call_number AS copy_call_number, circ.copy_location,
            cn.owning_lib AS copy_owning_lib, cp.circ_lib AS copy_circ_lib,
            cn.record AS copy_bib_record, circ.xact_start, circ.xact_finish,
            circ.target_copy, circ.circ_lib, circ.circ_staff,
            circ.checkin_staff, circ.checkin_lib, circ.renewal_remaining,
            circ.grace_period, circ.due_date, circ.stop_fines_time,
            circ.checkin_time, circ.create_time, circ.duration,
            circ.fine_interval, circ.recurring_fine, circ.max_fine,
            circ.phone_renewal, circ.desk_renewal, circ.opac_renewal,
            circ.duration_rule, circ.recurring_fine_rule, circ.max_fine_rule,
            circ.stop_fines, circ.workstation, circ.checkin_workstation,
            circ.checkin_scan_time, circ.parent_circ
           FROM action.circulation circ
      JOIN asset.copy cp ON circ.target_copy = cp.id
   JOIN asset.call_number cn ON cp.call_number = cn.id
   JOIN actor.usr p ON circ.usr = p.id
   LEFT JOIN actor.usr_address a ON p.mailing_address = a.id
   LEFT JOIN actor.usr_address b ON p.billing_address = b.id;

CREATE OR REPLACE VIEW action.all_hold_request AS
         SELECT DISTINCT COALESCE(a.post_code, b.post_code) AS usr_post_code,
            p.home_ou AS usr_home_ou, p.profile AS usr_profile,
            date_part('year'::text, p.dob)::integer AS usr_birth_year,
            ahr.requestor <> ahr.usr AS staff_placed, ahr.id, ahr.request_time,
            ahr.capture_time, ahr.fulfillment_time, ahr.checkin_time,
            ahr.return_time, ahr.prev_check_time, ahr.expire_time,
            ahr.cancel_time, ahr.cancel_cause, ahr.cancel_note, ahr.target,
            ahr.current_copy, ahr.fulfillment_staff, ahr.fulfillment_lib,
            ahr.request_lib, ahr.selection_ou, ahr.selection_depth,
            ahr.pickup_lib, ahr.hold_type, ahr.holdable_formats,
                CASE
                    WHEN ahr.phone_notify IS NULL THEN false
                    WHEN ahr.phone_notify = ''::text THEN false
                    ELSE true
                END AS phone_notify,
            ahr.email_notify,
                CASE
                    WHEN ahr.sms_notify IS NULL THEN false
                    WHEN ahr.sms_notify = ''::text THEN false
                    ELSE true
                END AS sms_notify,
            ahr.frozen, ahr.thaw_date, ahr.shelf_time, ahr.cut_in_line,
            ahr.mint_condition, ahr.shelf_expire_time, ahr.current_shelf_lib,
            ahr.behind_desk
           FROM action.hold_request ahr
      JOIN actor.usr p ON ahr.usr = p.id
   LEFT JOIN actor.usr_address a ON p.mailing_address = a.id
   LEFT JOIN actor.usr_address b ON p.billing_address = b.id
UNION ALL
         SELECT aged_hold_request.usr_post_code, aged_hold_request.usr_home_ou,
            aged_hold_request.usr_profile, aged_hold_request.usr_birth_year,
            aged_hold_request.staff_placed, aged_hold_request.id,
            aged_hold_request.request_time, aged_hold_request.capture_time,
            aged_hold_request.fulfillment_time, aged_hold_request.checkin_time,
            aged_hold_request.return_time, aged_hold_request.prev_check_time,
            aged_hold_request.expire_time, aged_hold_request.cancel_time,
            aged_hold_request.cancel_cause, aged_hold_request.cancel_note,
            aged_hold_request.target, aged_hold_request.current_copy,
            aged_hold_request.fulfillment_staff,
            aged_hold_request.fulfillment_lib, aged_hold_request.request_lib,
            aged_hold_request.selection_ou, aged_hold_request.selection_depth,
            aged_hold_request.pickup_lib, aged_hold_request.hold_type,
            aged_hold_request.holdable_formats, aged_hold_request.phone_notify,
            aged_hold_request.email_notify, aged_hold_request.sms_notify,
            aged_hold_request.frozen, aged_hold_request.thaw_date,
            aged_hold_request.shelf_time, aged_hold_request.cut_in_line,
            aged_hold_request.mint_condition,
            aged_hold_request.shelf_expire_time,
            aged_hold_request.current_shelf_lib, aged_hold_request.behind_desk
           FROM action.aged_hold_request;

COMMIT;
