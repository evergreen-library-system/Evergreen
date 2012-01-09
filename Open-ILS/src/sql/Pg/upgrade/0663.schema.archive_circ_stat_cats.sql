-- Evergreen DB patch 0663.schema.archive_circ_stat_cats.sql
--
-- Enables users to set copy and patron stat cats to be archivable
-- for the purposes of statistics even after the circs are aged.
--
BEGIN;

-- check whether patch can be applied
SELECT evergreen.upgrade_deps_block_check('0663', :eg_version);

-- New tables

CREATE TABLE action.archive_actor_stat_cat (
    id          BIGSERIAL   PRIMARY KEY,
    xact        BIGINT      NOT NULL,
    stat_cat    INT         NOT NULL,
    value       TEXT        NOT NULL
);

CREATE TABLE action.archive_asset_stat_cat (
    id          BIGSERIAL   PRIMARY KEY,
    xact        BIGINT      NOT NULL,
    stat_cat    INT         NOT NULL,
    value       TEXT        NOT NULL
);

-- Add columns to existing tables

-- Archive Flag Columns
ALTER TABLE actor.stat_cat
    ADD COLUMN checkout_archive BOOL NOT NULL DEFAULT FALSE;
ALTER TABLE asset.stat_cat
    ADD COLUMN checkout_archive BOOL NOT NULL DEFAULT FALSE;

-- Circulation copy column
ALTER TABLE action.circulation
    ADD COLUMN copy_location INT NULL REFERENCES asset.copy_location(id) DEFERRABLE INITIALLY DEFERRED;

-- Create trigger function to auto-fill the copy_location field
CREATE OR REPLACE FUNCTION action.fill_circ_copy_location () RETURNS TRIGGER AS $$
BEGIN
    SELECT INTO NEW.copy_location location FROM asset.copy WHERE id = NEW.target_copy;
    RETURN NEW;
END;
$$ LANGUAGE PLPGSQL;

-- Create trigger function to auto-archive stat cat entries
CREATE OR REPLACE FUNCTION action.archive_stat_cats () RETURNS TRIGGER AS $$
BEGIN
    INSERT INTO action.archive_actor_stat_cat(xact, stat_cat, value)
        SELECT NEW.id, asceum.stat_cat, asceum.stat_cat_entry
        FROM actor.stat_cat_entry_usr_map asceum
             JOIN actor.stat_cat sc ON asceum.stat_cat = sc.id
        WHERE NEW.usr = asceum.target_usr AND sc.checkout_archive;
    INSERT INTO action.archive_asset_stat_cat(xact, stat_cat, value)
        SELECT NEW.id, ascecm.stat_cat, asce.value
        FROM asset.stat_cat_entry_copy_map ascecm
             JOIN asset.stat_cat sc ON ascecm.stat_cat = sc.id
             JOIN asset.stat_cat_entry asce ON ascecm.stat_cat_entry = asce.id
        WHERE NEW.target_copy = ascecm.owning_copy AND sc.checkout_archive;
    RETURN NULL;
END;
$$ LANGUAGE PLPGSQL;

-- Apply triggers
CREATE TRIGGER fill_circ_copy_location_tgr BEFORE INSERT ON action.circulation FOR EACH ROW EXECUTE PROCEDURE action.fill_circ_copy_location();
CREATE TRIGGER archive_stat_cats_tgr AFTER INSERT ON action.circulation FOR EACH ROW EXECUTE PROCEDURE action.archive_stat_cats();

-- Ensure all triggers are disabled for speedy updates!
ALTER TABLE action.circulation DISABLE TRIGGER ALL;

-- Update view to use circ's copy_location field instead of the copy's current copy_location field
CREATE OR REPLACE VIEW action.all_circulation AS
    SELECT  id,usr_post_code, usr_home_ou, usr_profile, usr_birth_year, copy_call_number, copy_location,
        copy_owning_lib, copy_circ_lib, copy_bib_record, xact_start, xact_finish, target_copy,
        circ_lib, circ_staff, checkin_staff, checkin_lib, renewal_remaining, grace_period, due_date,
        stop_fines_time, checkin_time, create_time, duration, fine_interval, recurring_fine,
        max_fine, phone_renewal, desk_renewal, opac_renewal, duration_rule, recurring_fine_rule,
        max_fine_rule, stop_fines, workstation, checkin_workstation, checkin_scan_time, parent_circ
      FROM  action.aged_circulation
            UNION ALL
    SELECT  DISTINCT circ.id,COALESCE(a.post_code,b.post_code) AS usr_post_code, p.home_ou AS usr_home_ou, p.profile AS usr_profile, EXTRACT(YEAR FROM p.dob)::INT AS usr_birth_year,
        cp.call_number AS copy_call_number, circ.copy_location, cn.owning_lib AS copy_owning_lib, cp.circ_lib AS copy_circ_lib,
        cn.record AS copy_bib_record, circ.xact_start, circ.xact_finish, circ.target_copy, circ.circ_lib, circ.circ_staff, circ.checkin_staff,
        circ.checkin_lib, circ.renewal_remaining, circ.grace_period, circ.due_date, circ.stop_fines_time, circ.checkin_time, circ.create_time, circ.duration,
        circ.fine_interval, circ.recurring_fine, circ.max_fine, circ.phone_renewal, circ.desk_renewal, circ.opac_renewal, circ.duration_rule,
        circ.recurring_fine_rule, circ.max_fine_rule, circ.stop_fines, circ.workstation, circ.checkin_workstation, circ.checkin_scan_time,
        circ.parent_circ
      FROM  action.circulation circ
        JOIN asset.copy cp ON (circ.target_copy = cp.id)
        JOIN asset.call_number cn ON (cp.call_number = cn.id)
        JOIN actor.usr p ON (circ.usr = p.id)
        LEFT JOIN actor.usr_address a ON (p.mailing_address = a.id)
        LEFT JOIN actor.usr_address b ON (p.billing_address = b.id);

-- Update action.circulation with real copy_location numbers instead of all NULL
DO $$BEGIN RAISE WARNING 'We are about to do an update on every row in action.circulation. This may take a while. %', timeofday(); END;$$;
UPDATE action.circulation circ SET copy_location = ac.location FROM asset.copy ac WHERE ac.id = circ.target_copy;

-- Set not null/default on new column, re-enable triggers
ALTER TABLE action.circulation
    ALTER COLUMN copy_location SET NOT NULL,
    ALTER COLUMN copy_location SET DEFAULT 1,
    ENABLE TRIGGER ALL;

COMMIT;
