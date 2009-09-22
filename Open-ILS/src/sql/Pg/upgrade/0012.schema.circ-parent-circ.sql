BEGIN;

INSERT INTO config.upgrade_log (version) VALUES ('0012');

ALTER TABLE action.circulation
ADD COLUMN parent_circ BIGINT
	REFERENCES action.circulation(id)
	DEFERRABLE INITIALLY DEFERRED;

CREATE UNIQUE INDEX circ_parent_idx
ON action.circulation( parent_circ )
WHERE parent_circ IS NOT NULL;

CREATE OR REPLACE FUNCTION action.age_circ_on_delete () RETURNS TRIGGER AS $$
BEGIN
    INSERT INTO action.aged_circulation
        (id,usr_post_code, usr_home_ou, usr_profile, usr_birth_year, copy_call_number, copy_location,
        copy_owning_lib, copy_circ_lib, copy_bib_record, xact_start, xact_finish, target_copy,
        circ_lib, circ_staff, checkin_staff, checkin_lib, renewal_remaining, due_date,
        stop_fines_time, checkin_time, create_time, duration, fine_interval, recuring_fine,
        max_fine, phone_renewal, desk_renewal, opac_renewal, duration_rule, recuring_fine_rule,
        max_fine_rule, stop_fines, checkin_workstation, checkin_scan_time, parent_circ)
      SELECT
        id,usr_post_code, usr_home_ou, usr_profile, usr_birth_year, copy_call_number, copy_location,
        copy_owning_lib, copy_circ_lib, copy_bib_record, xact_start, xact_finish, target_copy,
        circ_lib, circ_staff, checkin_staff, checkin_lib, renewal_remaining, due_date,
        stop_fines_time, checkin_time, create_time, duration, fine_interval, recuring_fine,
        max_fine, phone_renewal, desk_renewal, opac_renewal, duration_rule, recuring_fine_rule,
        max_fine_rule, stop_fines, checkin_workstation, checkin_scan_time, parent_circ
        FROM action.all_circulation WHERE id = OLD.id;

    RETURN OLD;
END;
$$ LANGUAGE 'plpgsql';

COMMIT;
