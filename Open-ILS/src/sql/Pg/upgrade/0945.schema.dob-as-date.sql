BEGIN;

SELECT evergreen.upgrade_deps_block_check('0945', :eg_version);

-- run the entire update inside a DO block for managing the logic
-- of whether to recreate the optional reporter views
DO $$
DECLARE
    has_current_circ BOOLEAN;
    has_billing_summary BOOLEAN;
BEGIN

SELECT INTO has_current_circ TRUE FROM pg_views 
    WHERE schemaname = 'reporter' AND viewname = 'classic_current_circ';

SELECT INTO has_billing_summary TRUE FROM pg_views 
    WHERE schemaname = 'reporter' AND 
    viewname = 'classic_current_billing_summary';

DROP VIEW action.all_circulation;
DROP VIEW IF EXISTS reporter.classic_current_circ;
DROP VIEW IF EXISTS reporter.classic_current_billing_summary;
DROP VIEW reporter.demographic;
DROP VIEW auditor.actor_usr_lifecycle;
DROP VIEW action.all_hold_request;

ALTER TABLE actor.usr 
    ALTER dob TYPE DATE USING (dob + '3 hours'::INTERVAL)::DATE;

-- alter the auditor table manually to apply the same
-- dob mangling logic as above.
ALTER TABLE auditor.actor_usr_history 
    ALTER dob TYPE DATE USING (dob + '3 hours'::INTERVAL)::DATE;

-- this recreates auditor.actor_usr_lifecycle
PERFORM auditor.update_auditors();

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

IF has_current_circ THEN
RAISE NOTICE 'Recreating optional view reporter.classic_current_circ';

CREATE OR REPLACE VIEW reporter.classic_current_circ AS
SELECT	cl.shortname AS circ_lib,
	cl.id AS circ_lib_id,
	circ.xact_start AS xact_start,
	circ_type.type AS circ_type,
	cp.id AS copy_id,
	cp.circ_modifier,
	ol.shortname AS owning_lib_name,
	lm.value AS language,
	lfm.value AS lit_form,
	ifm.value AS item_form,
	itm.value AS item_type,
	sl.name AS shelving_location,
	p.id AS patron_id,
	g.name AS profile_group,
	dem.general_division AS demographic_general_division,
	circ.id AS id,
	cn.id AS call_number,
	cn.label AS call_number_label,
	call_number_dewey(cn.label) AS dewey,
	CASE
		WHEN call_number_dewey(cn.label) ~  E'^[0-9.]+$'
			THEN
				btrim(
					to_char(
						10 * floor((call_number_dewey(cn.label)::float) / 10), '000'
					)
				)
		ELSE NULL
	END AS dewey_block_tens,
	CASE
		WHEN call_number_dewey(cn.label) ~  E'^[0-9.]+$'
			THEN
				btrim(
					to_char(
						100 * floor((call_number_dewey(cn.label)::float) / 100), '000'
					)
				)
		ELSE NULL
	END AS dewey_block_hundreds,
	CASE
		WHEN call_number_dewey(cn.label) ~  E'^[0-9.]+$'
			THEN
				btrim(
					to_char(
						10 * floor((call_number_dewey(cn.label)::float) / 10), '000'
					)
				)
				|| '-' ||
				btrim(
					to_char(
						10 * floor((call_number_dewey(cn.label)::float) / 10) + 9, '000'
					)
				)
		ELSE NULL
	END AS dewey_range_tens,
	CASE
		WHEN call_number_dewey(cn.label) ~  E'^[0-9.]+$'
			THEN
				btrim(
					to_char(
						100 * floor((call_number_dewey(cn.label)::float) / 100), '000'
					)
				)
				|| '-' ||
				btrim(
					to_char(
						100 * floor((call_number_dewey(cn.label)::float) / 100) + 99, '000'
					)
				)
		ELSE NULL
	END AS dewey_range_hundreds,
	hl.id AS patron_home_lib,
	hl.shortname AS patron_home_lib_shortname,
	paddr.county AS patron_county,
	paddr.city AS patron_city,
	paddr.post_code AS patron_zip,
	sc1.stat_cat_entry AS stat_cat_1,
	sc2.stat_cat_entry AS stat_cat_2,
	sce1.value AS stat_cat_1_value,
	sce2.value AS stat_cat_2_value
  FROM	action.circulation circ
	JOIN reporter.circ_type circ_type ON (circ.id = circ_type.id)
	JOIN asset.copy cp ON (cp.id = circ.target_copy)
	JOIN asset.copy_location sl ON (cp.location = sl.id)
	JOIN asset.call_number cn ON (cp.call_number = cn.id)
	JOIN actor.org_unit ol ON (cn.owning_lib = ol.id)
	JOIN metabib.rec_descriptor rd ON (rd.record = cn.record)
	JOIN actor.org_unit cl ON (circ.circ_lib = cl.id)
	JOIN actor.usr p ON (p.id = circ.usr)
	JOIN actor.org_unit hl ON (p.home_ou = hl.id)
	JOIN permission.grp_tree g ON (p.profile = g.id)
	JOIN reporter.demographic dem ON (dem.id = p.id)
	JOIN actor.usr_address paddr ON (paddr.id = p.billing_address)
	LEFT JOIN config.language_map lm ON (rd.item_lang = lm.code)
	LEFT JOIN config.lit_form_map lfm ON (rd.lit_form = lfm.code)
	LEFT JOIN config.item_form_map ifm ON (rd.item_form = ifm.code)
	LEFT JOIN config.item_type_map itm ON (rd.item_type = itm.code)
	LEFT JOIN asset.stat_cat_entry_copy_map sc1 ON (sc1.owning_copy = cp.id AND sc1.stat_cat = 1)
	LEFT JOIN asset.stat_cat_entry sce1 ON (sce1.id = sc1.stat_cat_entry)
	LEFT JOIN asset.stat_cat_entry_copy_map sc2 ON (sc2.owning_copy = cp.id AND sc2.stat_cat = 2)
	LEFT JOIN asset.stat_cat_entry sce2 ON (sce2.id = sc2.stat_cat_entry);
END IF;

IF has_billing_summary THEN
RAISE NOTICE 'Recreating optional view reporter.classic_current_billing_summary';

CREATE OR REPLACE VIEW reporter.classic_current_billing_summary AS
SELECT	x.id AS id,
	x.usr AS usr,
	bl.shortname AS billing_location_shortname,
	bl.name AS billing_location_name,
	x.billing_location AS billing_location,
	c.barcode AS barcode,
	u.home_ou AS usr_home_ou,
	ul.shortname AS usr_home_ou_shortname,
	ul.name AS usr_home_ou_name,
	x.xact_start AS xact_start,
	x.xact_finish AS xact_finish,
	x.xact_type AS xact_type,
	x.total_paid AS total_paid,
	x.total_owed AS total_owed,
	x.balance_owed AS balance_owed,
	x.last_payment_ts AS last_payment_ts,
	x.last_payment_note AS last_payment_note,
	x.last_payment_type AS last_payment_type,
	x.last_billing_ts AS last_billing_ts,
	x.last_billing_note AS last_billing_note,
	x.last_billing_type AS last_billing_type,
	paddr.county AS patron_county,
	paddr.city AS patron_city,
	paddr.post_code AS patron_zip,
	g.name AS profile_group,
	dem.general_division AS demographic_general_division
  FROM	money.open_billable_xact_summary x
	JOIN actor.org_unit bl ON (x.billing_location = bl.id)
	JOIN actor.usr u ON (u.id = x.usr)
	JOIN actor.org_unit ul ON (u.home_ou = ul.id)
	JOIN actor.card c ON (u.card = c.id)
	JOIN permission.grp_tree g ON (u.profile = g.id)
	JOIN reporter.demographic dem ON (dem.id = u.id)
	JOIN actor.usr_address paddr ON (paddr.id = u.billing_address);
END IF;

END $$;

COMMIT;
