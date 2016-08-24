
BEGIN;

SELECT evergreen.upgrade_deps_block_check('0998', :eg_version);

DROP VIEW IF EXISTS action.all_circulation;
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
        aged_circulation.checkin_scan_time, aged_circulation.parent_circ,
        NULL AS usr
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
        circ.checkin_scan_time, circ.parent_circ, circ.usr
       FROM action.circulation circ
  JOIN asset.copy cp ON circ.target_copy = cp.id
JOIN asset.call_number cn ON cp.call_number = cn.id
JOIN actor.usr p ON circ.usr = p.id
LEFT JOIN actor.usr_address a ON p.mailing_address = a.id
LEFT JOIN actor.usr_address b ON p.billing_address = b.id;


CREATE OR REPLACE FUNCTION action.all_circ_chain (ctx_circ_id INTEGER) 
    RETURNS SETOF action.all_circulation AS $$
DECLARE
    tmp_circ action.all_circulation%ROWTYPE;
    circ_0 action.all_circulation%ROWTYPE;
BEGIN

    SELECT INTO tmp_circ * FROM action.all_circulation WHERE id = ctx_circ_id;

    IF tmp_circ IS NULL THEN
        RETURN NEXT tmp_circ;
    END IF;
    circ_0 := tmp_circ;

    -- find the front of the chain
    WHILE TRUE LOOP
        SELECT INTO tmp_circ * FROM action.all_circulation 
            WHERE id = tmp_circ.parent_circ;
        IF tmp_circ IS NULL THEN
            EXIT;
        END IF;
        circ_0 := tmp_circ;
    END LOOP;

    -- now send the circs to the caller, oldest to newest
    tmp_circ := circ_0;
    WHILE TRUE LOOP
        IF tmp_circ IS NULL THEN
            EXIT;
        END IF;
        RETURN NEXT tmp_circ;
        SELECT INTO tmp_circ * FROM action.all_circulation 
            WHERE parent_circ = tmp_circ.id;
    END LOOP;

END;
$$ LANGUAGE 'plpgsql';

CREATE OR REPLACE FUNCTION action.summarize_all_circ_chain 
    (ctx_circ_id INTEGER) RETURNS action.circ_chain_summary AS $$

DECLARE

    -- first circ in the chain
    circ_0 action.all_circulation%ROWTYPE;

    -- last circ in the chain
    circ_n action.all_circulation%ROWTYPE;

    -- circ chain under construction
    chain action.circ_chain_summary;
    tmp_circ action.all_circulation%ROWTYPE;

BEGIN
    
    chain.num_circs := 0;
    FOR tmp_circ IN SELECT * FROM action.all_circ_chain(ctx_circ_id) LOOP

        IF chain.num_circs = 0 THEN
            circ_0 := tmp_circ;
        END IF;

        chain.num_circs := chain.num_circs + 1;
        circ_n := tmp_circ;
    END LOOP;

    chain.start_time := circ_0.xact_start;
    chain.last_stop_fines := circ_n.stop_fines;
    chain.last_stop_fines_time := circ_n.stop_fines_time;
    chain.last_checkin_time := circ_n.checkin_time;
    chain.last_checkin_scan_time := circ_n.checkin_scan_time;
    SELECT INTO chain.checkout_workstation name FROM actor.workstation WHERE id = circ_0.workstation;
    SELECT INTO chain.last_checkin_workstation name FROM actor.workstation WHERE id = circ_n.checkin_workstation;

    IF chain.num_circs > 1 THEN
        chain.last_renewal_time := circ_n.xact_start;
        SELECT INTO chain.last_renewal_workstation name FROM actor.workstation WHERE id = circ_n.workstation;
    END IF;

    RETURN chain;

END;
$$ LANGUAGE 'plpgsql';


COMMIT;

