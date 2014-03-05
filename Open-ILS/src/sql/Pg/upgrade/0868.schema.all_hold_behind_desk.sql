-- add missing behind_desk column

\qecho *** This ALTER TABLE might fail depending on your DB vintage. ***
\qecho *** It should be harmless. ***
ALTER TABLE action.aged_hold_request ADD COLUMN behind_desk BOOLEAN;

BEGIN;

SELECT evergreen.upgrade_deps_block_check('0868', :eg_version);

CREATE OR REPLACE VIEW action.all_hold_request AS
    SELECT DISTINCT
           COALESCE(a.post_code, b.post_code) AS usr_post_code,
           p.home_ou AS usr_home_ou,
           p.profile AS usr_profile,
           EXTRACT(YEAR FROM p.dob)::INT AS usr_birth_year,
           CAST(ahr.requestor <> ahr.usr AS BOOLEAN) AS staff_placed,
           ahr.id,
           ahr.request_time,
           ahr.capture_time,
           ahr.fulfillment_time,
           ahr.checkin_time,
           ahr.return_time,
           ahr.prev_check_time,
           ahr.expire_time,
           ahr.cancel_time,
           ahr.cancel_cause,
           ahr.cancel_note,
           ahr.target,
           ahr.current_copy,
           ahr.fulfillment_staff,
           ahr.fulfillment_lib,
           ahr.request_lib,
           ahr.selection_ou,
           ahr.selection_depth,
           ahr.pickup_lib,
           ahr.hold_type,
           ahr.holdable_formats,
           CASE
           WHEN ahr.phone_notify IS NULL THEN FALSE
           WHEN ahr.phone_notify = '' THEN FALSE
           ELSE TRUE
           END AS phone_notify,
           ahr.email_notify,
           CASE
           WHEN ahr.sms_notify IS NULL THEN FALSE
           WHEN ahr.sms_notify = '' THEN FALSE
           ELSE TRUE
           END AS sms_notify,
           ahr.frozen,
           ahr.thaw_date,
           ahr.shelf_time,
           ahr.cut_in_line,
           ahr.mint_condition,
           ahr.shelf_expire_time,
           ahr.current_shelf_lib,
           ahr.behind_desk
    FROM action.hold_request ahr
         JOIN actor.usr p ON (ahr.usr = p.id)
         LEFT JOIN actor.usr_address a ON (p.mailing_address = a.id)
         LEFT JOIN actor.usr_address b ON (p.billing_address = b.id)
    UNION ALL
    SELECT 
           usr_post_code,
           usr_home_ou,
           usr_profile,
           usr_birth_year,
           staff_placed,
           id,
           request_time,
           capture_time,
           fulfillment_time,
           checkin_time,
           return_time,
           prev_check_time,
           expire_time,
           cancel_time,
           cancel_cause,
           cancel_note,
           target,
           current_copy,
           fulfillment_staff,
           fulfillment_lib,
           request_lib,
           selection_ou,
           selection_depth,
           pickup_lib,
           hold_type,
           holdable_formats,
           phone_notify,
           email_notify,
           sms_notify,
           frozen,
           thaw_date,
           shelf_time,
           cut_in_line,
           mint_condition,
           shelf_expire_time,
           current_shelf_lib,
           behind_desk
    FROM action.aged_hold_request;



CREATE OR REPLACE FUNCTION action.age_hold_on_delete () RETURNS TRIGGER AS $$
DECLARE
BEGIN
    -- Archive a copy of the old row to action.aged_hold_request

    INSERT INTO action.aged_hold_request
           (usr_post_code,
            usr_home_ou,
            usr_profile,
            usr_birth_year,
            staff_placed,
            id,
            request_time,
            capture_time,
            fulfillment_time,
            checkin_time,
            return_time,
            prev_check_time,
            expire_time,
            cancel_time,
            cancel_cause,
            cancel_note,
            target,
            current_copy,
            fulfillment_staff,
            fulfillment_lib,
            request_lib,
            selection_ou,
            selection_depth,
            pickup_lib,
            hold_type,
            holdable_formats,
            phone_notify,
            email_notify,
            sms_notify,
            frozen,
            thaw_date,
            shelf_time,
            cut_in_line,
            mint_condition,
            shelf_expire_time,
            current_shelf_lib,
            behind_desk)
      SELECT 
           usr_post_code,
           usr_home_ou,
           usr_profile,
           usr_birth_year,
           staff_placed,
           id,
           request_time,
           capture_time,
           fulfillment_time,
           checkin_time,
           return_time,
           prev_check_time,
           expire_time,
           cancel_time,
           cancel_cause,
           cancel_note,
           target,
           current_copy,
           fulfillment_staff,
           fulfillment_lib,
           request_lib,
           selection_ou,
           selection_depth,
           pickup_lib,
           hold_type,
           holdable_formats,
           phone_notify,
           email_notify,
           sms_notify,
           frozen,
           thaw_date,
           shelf_time,
           cut_in_line,
           mint_condition,
           shelf_expire_time,
           current_shelf_lib,
           behind_desk
        FROM action.all_hold_request WHERE id = OLD.id;

    RETURN OLD;
END;
$$ LANGUAGE 'plpgsql';

COMMIT;

