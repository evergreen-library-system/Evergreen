BEGIN;

SELECT evergreen.upgrade_deps_block_check('1123', :eg_version);

    ALTER TABLE config.rule_circ_duration
    ADD column max_auto_renewals INTEGER;

    ALTER TABLE action.circulation
    ADD column auto_renewal BOOLEAN;

    ALTER TABLE action.circulation
    ADD column auto_renewal_remaining INTEGER;

    ALTER TABLE action.aged_circulation
    ADD column auto_renewal BOOLEAN;

    ALTER TABLE action.aged_circulation
    ADD column auto_renewal_remaining INTEGER;

    INSERT INTO action_trigger.validator values('CircIsAutoRenewable', 'Checks whether the circulation is able to be autorenewed.');
    INSERT INTO action_trigger.reactor values('Circ::AutoRenew', 'Auto-Renews a circulation.');
    INSERT INTO action_trigger.hook(key, core_type, description) values('autorenewal', 'circ', 'Item was auto-renewed to patron.');

    -- AutoRenewer A/T Def: 
    INSERT INTO action_trigger.event_definition(active, owner, name, hook, validator, reactor, delay, max_delay, delay_field, group_field)
        values (false, 1, 'Autorenew', 'checkout.due', 'CircIsOpen', 'Circ::AutoRenew', '-23 hours'::interval,'-1 minute'::interval, 'due_date', 'usr');

    -- AutoRenewal outcome Email notifier A/T Def:
    INSERT INTO action_trigger.event_definition(active, owner, name, hook, validator, reactor, group_field, template)
        values (false, 1, 'AutorenewNotify', 'autorenewal', 'NOOP_True', 'SendEmail', 'usr', 
$$
[%- USE date -%]
[%- user = target.0.usr -%]
To: [%- params.recipient_email || user.email %]
From: [%- params.sender_email || default_sender %]
Date: [%- date.format(date.now, '%a, %d %b %Y %T -0000', gmt => 1) %]
Subject: Items Out Auto-Renewal Notification 
Auto-Submitted: auto-generated

Dear [% user.family_name %], [% user.first_given_name %]
An automatic renewal attempt was made for the following items:

[% FOR circ IN target %]
    [%- SET idx = loop.count - 1; SET udata =  user_data.$idx -%]
    [%- SET cid = circ.target_copy || udata.copy -%]
    [%- SET copy_details = helpers.get_copy_bib_basics(cid) -%]
    Item# [% loop.count %]
    Title: [% copy_details.title %]
    Author: [% copy_details.author %]
    [%- IF udata.is_renewed %]
    Status: Loan Renewed
    New Due Date: [% date.format(helpers.format_date(udata.new_due_date), '%Y-%m-%d') %]
    [%- ELSE %]
    Status: Not Renewed
    Reason: [% udata.reason %]
    Due Date: [% date.format(helpers.format_date(circ.due_date), '%Y-%m-%d') %]
    [% END %]
[% END %]
$$
    );

    INSERT INTO action_trigger.environment (event_def, path ) VALUES
    ( currval('action_trigger.event_definition_id_seq'), 'usr' ),
    ( currval('action_trigger.event_definition_id_seq'), 'circ_lib' );


DROP VIEW action.all_circulation;
CREATE OR REPLACE VIEW action.all_circulation AS
    SELECT  id,usr_post_code, usr_home_ou, usr_profile, usr_birth_year, copy_call_number, copy_location,
        copy_owning_lib, copy_circ_lib, copy_bib_record, xact_start, xact_finish, target_copy,
        circ_lib, circ_staff, checkin_staff, checkin_lib, renewal_remaining, grace_period, due_date,
        stop_fines_time, checkin_time, create_time, duration, fine_interval, recurring_fine,
        max_fine, phone_renewal, desk_renewal, opac_renewal, duration_rule, recurring_fine_rule,
        max_fine_rule, stop_fines, workstation, checkin_workstation, checkin_scan_time, parent_circ,
        auto_renewal, auto_renewal_remaining, NULL AS usr
      FROM  action.aged_circulation
            UNION ALL
    SELECT  DISTINCT circ.id,COALESCE(a.post_code,b.post_code) AS usr_post_code, p.home_ou AS usr_home_ou, p.profile AS usr_profile, EXTRACT(YEAR FROM p.dob)::INT AS usr_birth_year,
        cp.call_number AS copy_call_number, circ.copy_location, cn.owning_lib AS copy_owning_lib, cp.circ_lib AS copy_circ_lib,
        cn.record AS copy_bib_record, circ.xact_start, circ.xact_finish, circ.target_copy, circ.circ_lib, circ.circ_staff, circ.checkin_staff,
        circ.checkin_lib, circ.renewal_remaining, circ.grace_period, circ.due_date, circ.stop_fines_time, circ.checkin_time, circ.create_time, circ.duration,
        circ.fine_interval, circ.recurring_fine, circ.max_fine, circ.phone_renewal, circ.desk_renewal, circ.opac_renewal, circ.duration_rule,
        circ.recurring_fine_rule, circ.max_fine_rule, circ.stop_fines, circ.workstation, circ.checkin_workstation, circ.checkin_scan_time,
        circ.parent_circ, circ.auto_renewal, circ.auto_renewal_remaining, circ.usr
      FROM  action.circulation circ
        JOIN asset.copy cp ON (circ.target_copy = cp.id)
        JOIN asset.call_number cn ON (cp.call_number = cn.id)
        JOIN actor.usr p ON (circ.usr = p.id)
        LEFT JOIN actor.usr_address a ON (p.mailing_address = a.id)
        LEFT JOIN actor.usr_address b ON (p.billing_address = b.id);


DROP FUNCTION action.summarize_all_circ_chain (INTEGER);
DROP FUNCTION action.all_circ_chain (INTEGER);

-- rebuild slim circ view
DROP VIEW action.all_circulation_slim;
CREATE OR REPLACE VIEW action.all_circulation_slim AS
    SELECT
        id,
        usr,
        xact_start,
        xact_finish,
        unrecovered,
        target_copy,
        circ_lib,
        circ_staff,
        checkin_staff,
        checkin_lib,
        renewal_remaining,
        grace_period,
        due_date,
        stop_fines_time,
        checkin_time,
        create_time,
        duration,
        fine_interval,
        recurring_fine,
        max_fine,
        phone_renewal,
        desk_renewal,
        opac_renewal,
        duration_rule,
        recurring_fine_rule,
        max_fine_rule,
        stop_fines,
        workstation,
        checkin_workstation,
        copy_location,
        checkin_scan_time,
        auto_renewal,
        auto_renewal_remaining,
        parent_circ
    FROM action.circulation
UNION ALL
    SELECT
        id,
        NULL AS usr,
        xact_start,
        xact_finish,
        unrecovered,
        target_copy,
        circ_lib,
        circ_staff,
        checkin_staff,
        checkin_lib,
        renewal_remaining,
        grace_period,
        due_date,
        stop_fines_time,
        checkin_time,
        create_time,
        duration,
        fine_interval,
        recurring_fine,
        max_fine,
        phone_renewal,
        desk_renewal,
        opac_renewal,
        duration_rule,
        recurring_fine_rule,
        max_fine_rule,
        stop_fines,
        workstation,
        checkin_workstation,
        copy_location,
        checkin_scan_time,
        auto_renewal,
        auto_renewal_remaining,
        parent_circ
    FROM action.aged_circulation
;

CREATE OR REPLACE FUNCTION action.all_circ_chain (ctx_circ_id INTEGER) 
    RETURNS SETOF action.all_circulation_slim AS $$
DECLARE
    tmp_circ action.all_circulation_slim%ROWTYPE;
    circ_0 action.all_circulation_slim%ROWTYPE;
BEGIN

    SELECT INTO tmp_circ * FROM action.all_circulation_slim WHERE id = ctx_circ_id;

    IF tmp_circ IS NULL THEN
        RETURN NEXT tmp_circ;
    END IF;
    circ_0 := tmp_circ;

    -- find the front of the chain
    WHILE TRUE LOOP
        SELECT INTO tmp_circ * FROM action.all_circulation_slim 
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
        SELECT INTO tmp_circ * FROM action.all_circulation_slim 
            WHERE parent_circ = tmp_circ.id;
    END LOOP;

END;
$$ LANGUAGE 'plpgsql';

-- same as action.summarize_circ_chain, but returns data collected
-- from action.all_circulation, which may include aged circulations.
CREATE OR REPLACE FUNCTION action.summarize_all_circ_chain 
    (ctx_circ_id INTEGER) RETURNS action.circ_chain_summary AS $$

DECLARE

    -- first circ in the chain
    circ_0 action.all_circulation_slim%ROWTYPE;

    -- last circ in the chain
    circ_n action.all_circulation_slim%ROWTYPE;

    -- circ chain under construction
    chain action.circ_chain_summary;
    tmp_circ action.all_circulation_slim%ROWTYPE;

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
