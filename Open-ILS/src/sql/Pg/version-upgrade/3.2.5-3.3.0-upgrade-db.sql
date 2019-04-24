--Upgrade Script for 3.2.5 to 3.3.0
\set eg_version '''3.3.0'''
BEGIN;
INSERT INTO config.upgrade_log (version, applied_to) VALUES ('3.3.0', :eg_version);

SELECT evergreen.upgrade_deps_block_check('1135', :eg_version);

CREATE OR REPLACE FUNCTION biblio.indexing_ingest_or_delete () RETURNS TRIGGER AS $func$
DECLARE
    tmp_bool BOOL;
BEGIN

    IF NEW.deleted THEN -- If this bib is deleted

        PERFORM * FROM config.internal_flag WHERE
            name = 'ingest.metarecord_mapping.preserve_on_delete' AND enabled;

        tmp_bool := FOUND; -- Just in case this is changed by some other statement

        PERFORM metabib.remap_metarecord_for_bib( NEW.id, NEW.fingerprint, TRUE, tmp_bool );

        IF NOT tmp_bool THEN
            -- One needs to keep these around to support searches
            -- with the #deleted modifier, so one should turn on the named
            -- internal flag for that functionality.
            DELETE FROM metabib.record_attr_vector_list WHERE source = NEW.id;
        END IF;

        DELETE FROM authority.bib_linking WHERE bib = NEW.id; -- Avoid updating fields in bibs that are no longer visible
        DELETE FROM biblio.peer_bib_copy_map WHERE peer_record = NEW.id; -- Separate any multi-homed items
        DELETE FROM metabib.browse_entry_def_map WHERE source = NEW.id; -- Don't auto-suggest deleted bibs
        RETURN NEW; -- and we're done
    END IF;

    IF TG_OP = 'UPDATE' AND OLD.deleted IS FALSE THEN -- re-ingest?
        PERFORM * FROM config.internal_flag WHERE name = 'ingest.reingest.force_on_same_marc' AND enabled;

        IF NOT FOUND AND OLD.marc = NEW.marc THEN -- don't do anything if the MARC didn't change
            RETURN NEW;
        END IF;
    END IF;

    -- Record authority linking
    PERFORM * FROM config.internal_flag WHERE name = 'ingest.disable_authority_linking' AND enabled;
    IF NOT FOUND THEN
        PERFORM biblio.map_authority_linking( NEW.id, NEW.marc );
    END IF;

    -- Flatten and insert the mfr data
    PERFORM * FROM config.internal_flag WHERE name = 'ingest.disable_metabib_full_rec' AND enabled;
    IF NOT FOUND THEN
        PERFORM metabib.reingest_metabib_full_rec(NEW.id);

        -- Now we pull out attribute data, which is dependent on the mfr for all but XPath-based fields
        PERFORM * FROM config.internal_flag WHERE name = 'ingest.disable_metabib_rec_descriptor' AND enabled;
        IF NOT FOUND THEN
            PERFORM metabib.reingest_record_attributes(NEW.id, NULL, NEW.marc, TG_OP = 'INSERT' OR OLD.deleted);
        END IF;
    END IF;

    -- Gather and insert the field entry data
    PERFORM metabib.reingest_metabib_field_entries(NEW.id);

    -- Located URI magic
    PERFORM * FROM config.internal_flag WHERE name = 'ingest.disable_located_uri' AND enabled;
    IF NOT FOUND THEN PERFORM biblio.extract_located_uris( NEW.id, NEW.marc, NEW.editor ); END IF;

    -- (re)map metarecord-bib linking
    IF TG_OP = 'INSERT' THEN -- if not deleted and performing an insert, check for the flag
        PERFORM * FROM config.internal_flag WHERE name = 'ingest.metarecord_mapping.skip_on_insert' AND enabled;
        IF NOT FOUND THEN
            PERFORM metabib.remap_metarecord_for_bib( NEW.id, NEW.fingerprint );
        END IF;
    ELSE -- we're doing an update, and we're not deleted, remap
        PERFORM * FROM config.internal_flag WHERE name = 'ingest.metarecord_mapping.skip_on_update' AND enabled;
        IF NOT FOUND THEN
            PERFORM metabib.remap_metarecord_for_bib( NEW.id, NEW.fingerprint );
        END IF;
    END IF;

    RETURN NEW;
END;
$func$ LANGUAGE PLPGSQL;




SELECT evergreen.upgrade_deps_block_check('1139', :eg_version);

ALTER TABLE actor.usr ADD COLUMN guardian TEXT;

CREATE INDEX actor_usr_guardian_idx 
    ON actor.usr (evergreen.lowercase(guardian));
CREATE INDEX actor_usr_guardian_unaccent_idx 
    ON actor.usr (evergreen.unaccent_and_squash(guardian));

-- Modify auditor tables accordingly.
SELECT auditor.update_auditors();

-- clear the guardian field on delete
CREATE OR REPLACE FUNCTION actor.usr_delete(
	src_usr  IN INTEGER,
	dest_usr IN INTEGER
) RETURNS VOID AS $$
DECLARE
	old_profile actor.usr.profile%type;
	old_home_ou actor.usr.home_ou%type;
	new_profile actor.usr.profile%type;
	new_home_ou actor.usr.home_ou%type;
	new_name    text;
	new_dob     actor.usr.dob%type;
BEGIN
	SELECT
		id || '-PURGED-' || now(),
		profile,
		home_ou,
		dob
	INTO
		new_name,
		old_profile,
		old_home_ou,
		new_dob
	FROM
		actor.usr
	WHERE
		id = src_usr;
	--
	-- Quit if no such user
	--
	IF old_profile IS NULL THEN
		RETURN;
	END IF;
	--
	perform actor.usr_purge_data( src_usr, dest_usr );
	--
	-- Find the root grp_tree and the root org_unit.  This would be simpler if we 
	-- could assume that there is only one root.  Theoretically, someday, maybe,
	-- there could be multiple roots, so we take extra trouble to get the right ones.
	--
	SELECT
		id
	INTO
		new_profile
	FROM
		permission.grp_ancestors( old_profile )
	WHERE
		parent is null;
	--
	SELECT
		id
	INTO
		new_home_ou
	FROM
		actor.org_unit_ancestors( old_home_ou )
	WHERE
		parent_ou is null;
	--
	-- Truncate date of birth
	--
	IF new_dob IS NOT NULL THEN
		new_dob := date_trunc( 'year', new_dob );
	END IF;
	--
	UPDATE
		actor.usr
		SET
			card = NULL,
			profile = new_profile,
			usrname = new_name,
			email = NULL,
			passwd = random()::text,
			standing = DEFAULT,
			ident_type = 
			(
				SELECT MIN( id )
				FROM config.identification_type
			),
			ident_value = NULL,
			ident_type2 = NULL,
			ident_value2 = NULL,
			net_access_level = DEFAULT,
			photo_url = NULL,
			prefix = NULL,
			first_given_name = new_name,
			guardian = NULL,
			family_name = new_name,
			suffix = NULL,
			alias = NULL,
            guardian = NULL,
			day_phone = NULL,
			evening_phone = NULL,
			other_phone = NULL,
			mailing_address = NULL,
			billing_address = NULL,
			home_ou = new_home_ou,
			dob = new_dob,
			active = FALSE,
			master_account = DEFAULT, 
			super_user = DEFAULT,
			barred = FALSE,
			deleted = TRUE,
			juvenile = DEFAULT,
			usrgroup = 0,
			claims_returned_count = DEFAULT,
			credit_forward_balance = DEFAULT,
			last_xact_id = DEFAULT,
			alert_message = NULL,
			create_date = now(),
			expire_date = now()
	WHERE
		id = src_usr;
END;
$$ LANGUAGE plpgsql;

INSERT into config.org_unit_setting_type (name, label, description, datatype) 
VALUES ( 
    'ui.patron.edit.au.guardian.show',
    oils_i18n_gettext(
        'ui.patron.edit.au.guardian.show', 
        'GUI: Show guardian field on patron registration', 
        'coust', 'label'
    ),
    oils_i18n_gettext(
        'ui.patron.edit.au.guardian.show', 
        'The guardian field will be shown on the patron registration screen. Showing a field makes it appear with required fields even when not required. If the field is required this setting is ignored.', 
        'coust', 'description'
    ),
    'bool'
), (
    'ui.patron.edit.au.guardian.suggest',
    oils_i18n_gettext(
        'ui.patron.edit.au.guardian.suggest', 
        'GUI: Suggest guardian field on patron registration', 
        'coust', 'label'
    ),
    oils_i18n_gettext(
        'ui.patron.edit.au.guardian.suggest', 
        'The guardian field will be suggested on the patron registration screen. Suggesting a field makes it appear when suggested fields are shown. If the field is shown or required this setting is ignored.', 
        'coust', 'description'),
    'bool'
), (
    'ui.patron.edit.guardian_required_for_juv',
    oils_i18n_gettext(
        'ui.patron.edit.guardian_required_for_juv',
        'GUI: Juvenile account requires parent/guardian',
        'coust', 'label'
    ),
    oils_i18n_gettext(
        'ui.patron.edit.guardian_required_for_juv',
        'Require a value for the parent/guardian field in the patron editor for patrons marked as juvenile',
        'coust', 'description'),
    'bool'
);




SELECT evergreen.upgrade_deps_block_check('1140', :eg_version);

DROP FUNCTION IF EXISTS evergreen.org_top();

CREATE OR REPLACE FUNCTION evergreen.org_top()
RETURNS actor.org_unit AS $$
    SELECT * FROM actor.org_unit WHERE parent_ou IS NULL LIMIT 1;
$$ LANGUAGE SQL STABLE;


SELECT evergreen.upgrade_deps_block_check('1143', :eg_version);

INSERT into config.workstation_setting_type (name, grp, datatype, label)
VALUES (
    'eg.grid.admin.booking.resource', 'gui', 'object',
    oils_i18n_gettext (
        'eg.grid.admin.booking.resource',
        'Grid Config: admin.booking.resource',
        'cwst', 'label'
    )
), (
    'eg.grid.admin.booking.resource_attr', 'gui', 'object',
    oils_i18n_gettext (
    'eg.grid.admin.booking.resource_attr',
        'Grid Config: admin.booking.resource_attr',
        'cwst', 'label'
    )
), (
    'eg.grid.admin.booking.resource_attr_map', 'gui', 'object',
    oils_i18n_gettext (
    'eg.grid.admin.booking.resource_attr_map',
        'Grid Config: admin.booking.resource_attr_map',
        'cwst', 'label'
    )
), (
    'eg.grid.admin.booking.resource_attr_value', 'gui', 'object',
    oils_i18n_gettext (
    'eg.grid.admin.booking.resource_attr_value',
        'Grid Config: admin.booking.resource_attr_value',
        'cwst', 'label'
    )
), (
    'eg.grid.admin.booking.resource_type', 'gui', 'object',
    oils_i18n_gettext (
    'eg.grid.admin.booking.resource_type',
        'Grid Config: admin.booking.resource_type',
        'cwst', 'label'
    )
);


INSERT INTO config.upgrade_log (version) VALUES ('1144');

CREATE TABLE actor.usr_privacy_waiver (
    id BIGSERIAL PRIMARY KEY,
    usr BIGINT NOT NULL REFERENCES actor.usr(id) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED,
    name TEXT NOT NULL,
    place_holds BOOL DEFAULT FALSE,
    pickup_holds BOOL DEFAULT FALSE,
    view_history BOOL DEFAULT FALSE,
    checkout_items BOOL DEFAULT FALSE
);
CREATE INDEX actor_usr_privacy_waiver_usr_idx ON actor.usr_privacy_waiver (usr);



INSERT INTO config.upgrade_log (version) VALUES ('1145');

CREATE OR REPLACE FUNCTION actor.usr_purge_data(
	src_usr  IN INTEGER,
	specified_dest_usr IN INTEGER
) RETURNS VOID AS $$
DECLARE
	suffix TEXT;
	renamable_row RECORD;
	dest_usr INTEGER;
BEGIN

	IF specified_dest_usr IS NULL THEN
		dest_usr := 1; -- Admin user on stock installs
	ELSE
		dest_usr := specified_dest_usr;
	END IF;

	-- acq.*
	UPDATE acq.fund_allocation SET allocator = dest_usr WHERE allocator = src_usr;
	UPDATE acq.lineitem SET creator = dest_usr WHERE creator = src_usr;
	UPDATE acq.lineitem SET editor = dest_usr WHERE editor = src_usr;
	UPDATE acq.lineitem SET selector = dest_usr WHERE selector = src_usr;
	UPDATE acq.lineitem_note SET creator = dest_usr WHERE creator = src_usr;
	UPDATE acq.lineitem_note SET editor = dest_usr WHERE editor = src_usr;
    UPDATE acq.invoice SET closed_by = dest_usr WHERE closed_by = src_usr;
	DELETE FROM acq.lineitem_usr_attr_definition WHERE usr = src_usr;

	-- Update with a rename to avoid collisions
	FOR renamable_row in
		SELECT id, name
		FROM   acq.picklist
		WHERE  owner = src_usr
	LOOP
		suffix := ' (' || src_usr || ')';
		LOOP
			BEGIN
				UPDATE  acq.picklist
				SET     owner = dest_usr, name = name || suffix
				WHERE   id = renamable_row.id;
			EXCEPTION WHEN unique_violation THEN
				suffix := suffix || ' ';
				CONTINUE;
			END;
			EXIT;
		END LOOP;
	END LOOP;

	UPDATE acq.picklist SET creator = dest_usr WHERE creator = src_usr;
	UPDATE acq.picklist SET editor = dest_usr WHERE editor = src_usr;
	UPDATE acq.po_note SET creator = dest_usr WHERE creator = src_usr;
	UPDATE acq.po_note SET editor = dest_usr WHERE editor = src_usr;
	UPDATE acq.purchase_order SET owner = dest_usr WHERE owner = src_usr;
	UPDATE acq.purchase_order SET creator = dest_usr WHERE creator = src_usr;
	UPDATE acq.purchase_order SET editor = dest_usr WHERE editor = src_usr;
	UPDATE acq.claim_event SET creator = dest_usr WHERE creator = src_usr;

	-- action.*
	DELETE FROM action.circulation WHERE usr = src_usr;
	UPDATE action.circulation SET circ_staff = dest_usr WHERE circ_staff = src_usr;
	UPDATE action.circulation SET checkin_staff = dest_usr WHERE checkin_staff = src_usr;
	UPDATE action.hold_notification SET notify_staff = dest_usr WHERE notify_staff = src_usr;
	UPDATE action.hold_request SET fulfillment_staff = dest_usr WHERE fulfillment_staff = src_usr;
	UPDATE action.hold_request SET requestor = dest_usr WHERE requestor = src_usr;
	DELETE FROM action.hold_request WHERE usr = src_usr;
	UPDATE action.in_house_use SET staff = dest_usr WHERE staff = src_usr;
	UPDATE action.non_cat_in_house_use SET staff = dest_usr WHERE staff = src_usr;
	DELETE FROM action.non_cataloged_circulation WHERE patron = src_usr;
	UPDATE action.non_cataloged_circulation SET staff = dest_usr WHERE staff = src_usr;
	DELETE FROM action.survey_response WHERE usr = src_usr;
	UPDATE action.fieldset SET owner = dest_usr WHERE owner = src_usr;
	DELETE FROM action.usr_circ_history WHERE usr = src_usr;

	-- actor.*
	DELETE FROM actor.card WHERE usr = src_usr;
	DELETE FROM actor.stat_cat_entry_usr_map WHERE target_usr = src_usr;
	DELETE FROM actor.usr_privacy_waiver WHERE usr = src_usr;

	-- The following update is intended to avoid transient violations of a foreign
	-- key constraint, whereby actor.usr_address references itself.  It may not be
	-- necessary, but it does no harm.
	UPDATE actor.usr_address SET replaces = NULL
		WHERE usr = src_usr AND replaces IS NOT NULL;
	DELETE FROM actor.usr_address WHERE usr = src_usr;
	DELETE FROM actor.usr_note WHERE usr = src_usr;
	UPDATE actor.usr_note SET creator = dest_usr WHERE creator = src_usr;
	DELETE FROM actor.usr_org_unit_opt_in WHERE usr = src_usr;
	UPDATE actor.usr_org_unit_opt_in SET staff = dest_usr WHERE staff = src_usr;
	DELETE FROM actor.usr_setting WHERE usr = src_usr;
	DELETE FROM actor.usr_standing_penalty WHERE usr = src_usr;
	UPDATE actor.usr_standing_penalty SET staff = dest_usr WHERE staff = src_usr;

	-- asset.*
	UPDATE asset.call_number SET creator = dest_usr WHERE creator = src_usr;
	UPDATE asset.call_number SET editor = dest_usr WHERE editor = src_usr;
	UPDATE asset.call_number_note SET creator = dest_usr WHERE creator = src_usr;
	UPDATE asset.copy SET creator = dest_usr WHERE creator = src_usr;
	UPDATE asset.copy SET editor = dest_usr WHERE editor = src_usr;
	UPDATE asset.copy_note SET creator = dest_usr WHERE creator = src_usr;

	-- auditor.*
	DELETE FROM auditor.actor_usr_address_history WHERE id = src_usr;
	DELETE FROM auditor.actor_usr_history WHERE id = src_usr;
	UPDATE auditor.asset_call_number_history SET creator = dest_usr WHERE creator = src_usr;
	UPDATE auditor.asset_call_number_history SET editor  = dest_usr WHERE editor  = src_usr;
	UPDATE auditor.asset_copy_history SET creator = dest_usr WHERE creator = src_usr;
	UPDATE auditor.asset_copy_history SET editor  = dest_usr WHERE editor  = src_usr;
	UPDATE auditor.biblio_record_entry_history SET creator = dest_usr WHERE creator = src_usr;
	UPDATE auditor.biblio_record_entry_history SET editor  = dest_usr WHERE editor  = src_usr;

	-- biblio.*
	UPDATE biblio.record_entry SET creator = dest_usr WHERE creator = src_usr;
	UPDATE biblio.record_entry SET editor = dest_usr WHERE editor = src_usr;
	UPDATE biblio.record_note SET creator = dest_usr WHERE creator = src_usr;
	UPDATE biblio.record_note SET editor = dest_usr WHERE editor = src_usr;

	-- container.*
	-- Update buckets with a rename to avoid collisions
	FOR renamable_row in
		SELECT id, name
		FROM   container.biblio_record_entry_bucket
		WHERE  owner = src_usr
	LOOP
		suffix := ' (' || src_usr || ')';
		LOOP
			BEGIN
				UPDATE  container.biblio_record_entry_bucket
				SET     owner = dest_usr, name = name || suffix
				WHERE   id = renamable_row.id;
			EXCEPTION WHEN unique_violation THEN
				suffix := suffix || ' ';
				CONTINUE;
			END;
			EXIT;
		END LOOP;
	END LOOP;

	FOR renamable_row in
		SELECT id, name
		FROM   container.call_number_bucket
		WHERE  owner = src_usr
	LOOP
		suffix := ' (' || src_usr || ')';
		LOOP
			BEGIN
				UPDATE  container.call_number_bucket
				SET     owner = dest_usr, name = name || suffix
				WHERE   id = renamable_row.id;
			EXCEPTION WHEN unique_violation THEN
				suffix := suffix || ' ';
				CONTINUE;
			END;
			EXIT;
		END LOOP;
	END LOOP;

	FOR renamable_row in
		SELECT id, name
		FROM   container.copy_bucket
		WHERE  owner = src_usr
	LOOP
		suffix := ' (' || src_usr || ')';
		LOOP
			BEGIN
				UPDATE  container.copy_bucket
				SET     owner = dest_usr, name = name || suffix
				WHERE   id = renamable_row.id;
			EXCEPTION WHEN unique_violation THEN
				suffix := suffix || ' ';
				CONTINUE;
			END;
			EXIT;
		END LOOP;
	END LOOP;

	FOR renamable_row in
		SELECT id, name
		FROM   container.user_bucket
		WHERE  owner = src_usr
	LOOP
		suffix := ' (' || src_usr || ')';
		LOOP
			BEGIN
				UPDATE  container.user_bucket
				SET     owner = dest_usr, name = name || suffix
				WHERE   id = renamable_row.id;
			EXCEPTION WHEN unique_violation THEN
				suffix := suffix || ' ';
				CONTINUE;
			END;
			EXIT;
		END LOOP;
	END LOOP;

	DELETE FROM container.user_bucket_item WHERE target_user = src_usr;

	-- money.*
	DELETE FROM money.billable_xact WHERE usr = src_usr;
	DELETE FROM money.collections_tracker WHERE usr = src_usr;
	UPDATE money.collections_tracker SET collector = dest_usr WHERE collector = src_usr;

	-- permission.*
	DELETE FROM permission.usr_grp_map WHERE usr = src_usr;
	DELETE FROM permission.usr_object_perm_map WHERE usr = src_usr;
	DELETE FROM permission.usr_perm_map WHERE usr = src_usr;
	DELETE FROM permission.usr_work_ou_map WHERE usr = src_usr;

	-- reporter.*
	-- Update with a rename to avoid collisions
	BEGIN
		FOR renamable_row in
			SELECT id, name
			FROM   reporter.output_folder
			WHERE  owner = src_usr
		LOOP
			suffix := ' (' || src_usr || ')';
			LOOP
				BEGIN
					UPDATE  reporter.output_folder
					SET     owner = dest_usr, name = name || suffix
					WHERE   id = renamable_row.id;
				EXCEPTION WHEN unique_violation THEN
					suffix := suffix || ' ';
					CONTINUE;
				END;
				EXIT;
			END LOOP;
		END LOOP;
	EXCEPTION WHEN undefined_table THEN
		-- do nothing
	END;

	BEGIN
		UPDATE reporter.report SET owner = dest_usr WHERE owner = src_usr;
	EXCEPTION WHEN undefined_table THEN
		-- do nothing
	END;

	-- Update with a rename to avoid collisions
	BEGIN
		FOR renamable_row in
			SELECT id, name
			FROM   reporter.report_folder
			WHERE  owner = src_usr
		LOOP
			suffix := ' (' || src_usr || ')';
			LOOP
				BEGIN
					UPDATE  reporter.report_folder
					SET     owner = dest_usr, name = name || suffix
					WHERE   id = renamable_row.id;
				EXCEPTION WHEN unique_violation THEN
					suffix := suffix || ' ';
					CONTINUE;
				END;
				EXIT;
			END LOOP;
		END LOOP;
	EXCEPTION WHEN undefined_table THEN
		-- do nothing
	END;

	BEGIN
		UPDATE reporter.schedule SET runner = dest_usr WHERE runner = src_usr;
	EXCEPTION WHEN undefined_table THEN
		-- do nothing
	END;

	BEGIN
		UPDATE reporter.template SET owner = dest_usr WHERE owner = src_usr;
	EXCEPTION WHEN undefined_table THEN
		-- do nothing
	END;

	-- Update with a rename to avoid collisions
	BEGIN
		FOR renamable_row in
			SELECT id, name
			FROM   reporter.template_folder
			WHERE  owner = src_usr
		LOOP
			suffix := ' (' || src_usr || ')';
			LOOP
				BEGIN
					UPDATE  reporter.template_folder
					SET     owner = dest_usr, name = name || suffix
					WHERE   id = renamable_row.id;
				EXCEPTION WHEN unique_violation THEN
					suffix := suffix || ' ';
					CONTINUE;
				END;
				EXIT;
			END LOOP;
		END LOOP;
	EXCEPTION WHEN undefined_table THEN
	-- do nothing
	END;

	-- vandelay.*
	-- Update with a rename to avoid collisions
	FOR renamable_row in
		SELECT id, name
		FROM   vandelay.queue
		WHERE  owner = src_usr
	LOOP
		suffix := ' (' || src_usr || ')';
		LOOP
			BEGIN
				UPDATE  vandelay.queue
				SET     owner = dest_usr, name = name || suffix
				WHERE   id = renamable_row.id;
			EXCEPTION WHEN unique_violation THEN
				suffix := suffix || ' ';
				CONTINUE;
			END;
			EXIT;
		END LOOP;
	END LOOP;

    UPDATE vandelay.session_tracker SET usr = dest_usr WHERE usr = src_usr;

    -- NULL-ify addresses last so other cleanup (e.g. circ anonymization)
    -- can access the information before deletion.
	UPDATE actor.usr SET
		active = FALSE,
		card = NULL,
		mailing_address = NULL,
		billing_address = NULL
	WHERE id = src_usr;

END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION actor.usr_purge_data(INT, INT) IS $$
Finds rows dependent on a given row in actor.usr and either deletes them
or reassigns them to a different user.
$$;



SELECT evergreen.upgrade_deps_block_check('1146', :eg_version);

INSERT INTO config.org_unit_setting_type
    (name, label, description, grp, datatype)
    VALUES (
        'circ.privacy_waiver',
        oils_i18n_gettext('circ.privacy_waiver',
            'Allow others to use patron account (privacy waiver)',
            'coust', 'label'),
        oils_i18n_gettext('circ.privacy_waiver',
            'Add a note to a user account indicating that specified people are allowed to ' ||
            'place holds, pick up holds, check out items, or view borrowing history for that user account',
            'coust', 'description'),
        'circ',
        'bool'
    );



SELECT evergreen.upgrade_deps_block_check('1147', :eg_version);

INSERT INTO config.workstation_setting_type (name, grp, datatype, label)
VALUES (
    'eg.grid.admin.server.config.rule_age_hold_protect', 'gui', 'object',
    oils_i18n_gettext(
        'eg.grid.admin.server.config.rule_age_hold_protect',
        'Grid Config: admin.server.config.rule_age_hold_protect',
        'cwst', 'label'
    )
), (
    'eg.grid.admin.server.asset.stat_cat_sip_fields', 'gui', 'object',
    oils_i18n_gettext(
        'eg.grid.admin.server.asset.stat_cat_sip_fields',
        'Grid Config: admin.server.asset.stat_cat_sip_fields',
        'cwst', 'label'
    )
), (
    'eg.grid.admin.server.actor.stat_cat_sip_fields', 'gui', 'object',
    oils_i18n_gettext(
        'eg.grid.admin.server.actor.stat_cat_sip_fields',
        'Grid Config: admin.server.actor.stat_cat_sip_fields',
        'cwst', 'label'
    )
), (
    'eg.grid.admin.server.authority.browse_axis', 'gui', 'object',
    oils_i18n_gettext(
        'eg.grid.admin.server.authority.browse_axis',
        'Grid Config: admin.server.authority.browse_axis',
        'cwst', 'label'
    )
), (
    'eg.grid.admin.server.authority.control_set', 'gui', 'object',
    oils_i18n_gettext(
        'eg.grid.admin.server.authority.control_set',
        'Grid Config: admin.server.authority.control_set',
        'cwst', 'label'
    )
), (
    'eg.grid.admin.server.authority.heading_field', 'gui', 'object',
    oils_i18n_gettext(
        'eg.grid.admin.server.authority.heading_field',
        'Grid Config: admin.server.authority.heading_field',
        'cwst', 'label'
    )
), (
    'eg.grid.admin.server.authority.thesaurus', 'gui', 'object',
    oils_i18n_gettext(
        'eg.grid.admin.server.authority.thesaurus',
        'Grid Config: admin.server.authority.thesaurus',
        'cwst', 'label'
    )
), (
    'eg.grid.admin.server.config.best_hold_order', 'gui', 'object',
    oils_i18n_gettext(
        'eg.grid.admin.server.config.best_hold_order',
        'Grid Config: admin.server.config.best_hold_order',
        'cwst', 'label'
    )
), (
    'eg.grid.admin.server.config.billing_type', 'gui', 'object',
    oils_i18n_gettext(
        'eg.grid.admin.server.config.billing_type',
        'Grid Config: admin.server.config.billing_type',
        'cwst', 'label'
    )
), (
    'eg.grid.admin.server.asset.call_number_prefix', 'gui', 'object',
    oils_i18n_gettext(
        'eg.grid.admin.server.asset.call_number_prefix',
        'Grid Config: admin.server.asset.call_number_prefix',
        'cwst', 'label'
    )
), (
    'eg.grid.admin.server.asset.call_number_suffix', 'gui', 'object',
    oils_i18n_gettext(
        'eg.grid.admin.server.asset.call_number_suffix',
        'Grid Config: admin.server.asset.call_number_suffix',
        'cwst', 'label'
    )
), (
    'eg.grid.admin.server.config.rule_circ_duration', 'gui', 'object',
    oils_i18n_gettext(
        'eg.grid.admin.server.config.rule_circ_duration',
        'Grid Config: admin.server.config.rule_circ_duration',
        'cwst', 'label'
    )
), (
    'eg.grid.admin.server.config.circ_limit_group', 'gui', 'object',
    oils_i18n_gettext(
        'eg.grid.admin.server.config.circ_limit_group',
        'Grid Config: admin.server.config.circ_limit_group',
        'cwst', 'label'
    )
), (
    'eg.grid.admin.server.config.circ_matrix_weights', 'gui', 'object',
    oils_i18n_gettext(
        'eg.grid.admin.server.config.circ_matrix_weights',
        'Grid Config: admin.server.config.circ_matrix_weights',
        'cwst', 'label'
    )
), (
    'eg.grid.admin.server.config.rule_max_fine', 'gui', 'object',
    oils_i18n_gettext(
        'eg.grid.admin.server.config.rule_max_fine',
        'Grid Config: admin.server.config.rule_max_fine',
        'cwst', 'label'
    )
), (
    'eg.grid.admin.server.config.circ_modifier', 'gui', 'object',
    oils_i18n_gettext(
        'eg.grid.admin.server.config.circ_modifier',
        'Grid Config: admin.server.config.circ_modifier',
        'cwst', 'label'
    )
), (
    'eg.grid.admin.server.config.copy_status', 'gui', 'object',
    oils_i18n_gettext(
        'eg.grid.admin.server.config.copy_status',
        'Grid Config: admin.server.config.copy_status',
        'cwst', 'label'
    )
), (
    'eg.grid.admin.server.config.floating_group', 'gui', 'object',
    oils_i18n_gettext(
        'eg.grid.admin.server.config.floating_group',
        'Grid Config: admin.server.config.floating_group',
        'cwst', 'label'
    )
), (
    'eg.grid.admin.server.config.global_flag', 'gui', 'object',
    oils_i18n_gettext(
        'eg.grid.admin.server.config.global_flag',
        'Grid Config: admin.server.config.global_flag',
        'cwst', 'label'
    )
), (
    'eg.grid.admin.server.config.hard_due_date', 'gui', 'object',
    oils_i18n_gettext(
        'eg.grid.admin.server.config.hard_due_date',
        'Grid Config: admin.server.config.hard_due_date',
        'cwst', 'label'
    )
), (
    'eg.grid.admin.server.config.hold_matrix_weights', 'gui', 'object',
    oils_i18n_gettext(
        'eg.grid.admin.server.config.hold_matrix_weights',
        'Grid Config: admin.server.config.hold_matrix_weights',
        'cwst', 'label'
    )
), (
    'eg.grid.admin.server.vandelay.match_set', 'gui', 'object',
    oils_i18n_gettext(
        'eg.grid.admin.server.vandelay.match_set',
        'Grid Config: admin.server.vandelay.match_set',
        'cwst', 'label'
    )
), (
    'eg.grid.admin.server.config.coded_value_map', 'gui', 'object',
    oils_i18n_gettext(
        'eg.grid.admin.server.config.coded_value_map',
        'Grid Config: admin.server.config.coded_value_map',
        'cwst', 'label'
    )
), (
    'eg.grid.admin.server.vandelay.import_bib_trash_group', 'gui', 'object',
    oils_i18n_gettext(
        'eg.grid.admin.server.vandelay.import_bib_trash_group',
        'Grid Config: admin.server.vandelay.import_bib_trash_group',
        'cwst', 'label'
    )
), (
    'eg.grid.admin.server.config.record_attr_definition', 'gui', 'object',
    oils_i18n_gettext(
        'eg.grid.admin.server.config.record_attr_definition',
        'Grid Config: admin.server.config.record_attr_definition',
        'cwst', 'label'
    )
), (
    'eg.grid.admin.server.config.metabib_class', 'gui', 'object',
    oils_i18n_gettext(
        'eg.grid.admin.server.config.metabib_class',
        'Grid Config: admin.server.config.metabib_class',
        'cwst', 'label'
    )
), (
    'eg.grid.admin.server.config.metabib_field_ts_map', 'gui', 'object',
    oils_i18n_gettext(
        'eg.grid.admin.server.config.metabib_field_ts_map',
        'Grid Config: admin.server.config.metabib_field_ts_map',
        'cwst', 'label'
    )
), (
    'eg.grid.admin.server.config.metabib_field', 'gui', 'object',
    oils_i18n_gettext(
        'eg.grid.admin.server.config.metabib_field',
        'Grid Config: admin.server.config.metabib_field',
        'cwst', 'label'
    )
), (
    'eg.grid.admin.server.permission.perm_list', 'gui', 'object',
    oils_i18n_gettext(
        'eg.grid.admin.server.permission.perm_list',
        'Grid Config: admin.server.permission.perm_list',
        'cwst', 'label'
    )
), (
    'eg.grid.admin.server.config.remote_account', 'gui', 'object',
    oils_i18n_gettext(
        'eg.grid.admin.server.config.remote_account',
        'Grid Config: admin.server.config.remote_account',
        'cwst', 'label'
    )
), (
    'eg.grid.admin.server.config.sms_carrier', 'gui', 'object',
    oils_i18n_gettext(
        'eg.grid.admin.server.config.sms_carrier',
        'Grid Config: admin.server.config.sms_carrier',
        'cwst', 'label'
    )
), (
    'eg.grid.admin.server.config.usr_activity_type', 'gui', 'object',
    oils_i18n_gettext(
        'eg.grid.admin.server.config.usr_activity_type',
        'Grid Config: admin.server.config.usr_activity_type',
        'cwst', 'label'
    )
), (
    'eg.grid.admin.server.config.weight_assoc', 'gui', 'object',
    oils_i18n_gettext(
        'eg.grid.admin.server.config.weight_assoc',
        'Grid Config: admin.server.config.weight_assoc',
        'cwst', 'label'
    )
), (
    'eg.grid.admin.server.config.z3950_index_field_map', 'gui', 'object',
    oils_i18n_gettext(
        'eg.grid.admin.server.config.z3950_index_field_map',
        'Grid Config: admin.server.config.z3950_index_field_map',
        'cwst', 'label'
    )
), (
    'eg.grid.admin.server.config.z3950_source', 'gui', 'object',
    oils_i18n_gettext(
        'eg.grid.admin.server.config.z3950_source',
        'Grid Config: admin.server.config.z3950_source',
        'cwst', 'label'
    )
);




SELECT evergreen.upgrade_deps_block_check('1148', :eg_version); -- csharp/gmcharlt

CREATE OR REPLACE FUNCTION actor.usr_delete(
	src_usr  IN INTEGER,
	dest_usr IN INTEGER
) RETURNS VOID AS $$
DECLARE
	old_profile actor.usr.profile%type;
	old_home_ou actor.usr.home_ou%type;
	new_profile actor.usr.profile%type;
	new_home_ou actor.usr.home_ou%type;
	new_name    text;
	new_dob     actor.usr.dob%type;
BEGIN
	SELECT
		id || '-PURGED-' || now(),
		profile,
		home_ou,
		dob
	INTO
		new_name,
		old_profile,
		old_home_ou,
		new_dob
	FROM
		actor.usr
	WHERE
		id = src_usr;
	--
	-- Quit if no such user
	--
	IF old_profile IS NULL THEN
		RETURN;
	END IF;
	--
	perform actor.usr_purge_data( src_usr, dest_usr );
	--
	-- Find the root grp_tree and the root org_unit.  This would be simpler if we 
	-- could assume that there is only one root.  Theoretically, someday, maybe,
	-- there could be multiple roots, so we take extra trouble to get the right ones.
	--
	SELECT
		id
	INTO
		new_profile
	FROM
		permission.grp_ancestors( old_profile )
	WHERE
		parent is null;
	--
	SELECT
		id
	INTO
		new_home_ou
	FROM
		actor.org_unit_ancestors( old_home_ou )
	WHERE
		parent_ou is null;
	--
	-- Truncate date of birth
	--
	IF new_dob IS NOT NULL THEN
		new_dob := date_trunc( 'year', new_dob );
	END IF;
	--
	UPDATE
		actor.usr
		SET
			card = NULL,
			profile = new_profile,
			usrname = new_name,
			email = NULL,
			passwd = random()::text,
			standing = DEFAULT,
			ident_type = 
			(
				SELECT MIN( id )
				FROM config.identification_type
			),
			ident_value = NULL,
			ident_type2 = NULL,
			ident_value2 = NULL,
			net_access_level = DEFAULT,
			photo_url = NULL,
			prefix = NULL,
			first_given_name = new_name,
			second_given_name = NULL,
			family_name = new_name,
			suffix = NULL,
			alias = NULL,
            guardian = NULL,
			day_phone = NULL,
			evening_phone = NULL,
			other_phone = NULL,
			mailing_address = NULL,
			billing_address = NULL,
			home_ou = new_home_ou,
			dob = new_dob,
			active = FALSE,
			master_account = DEFAULT, 
			super_user = DEFAULT,
			barred = FALSE,
			deleted = TRUE,
			juvenile = DEFAULT,
			usrgroup = 0,
			claims_returned_count = DEFAULT,
			credit_forward_balance = DEFAULT,
			last_xact_id = DEFAULT,
			alert_message = NULL,
			create_date = now(),
			expire_date = now()
	WHERE
		id = src_usr;
END;
$$ LANGUAGE plpgsql;


SELECT evergreen.upgrade_deps_block_check('1150', :eg_version);

INSERT INTO config.workstation_setting_type (name, grp, datatype, label)
VALUES (
    'eg.grid.cat.vandelay.queue.bib', 'gui', 'object',
    oils_i18n_gettext(
        'eg.grid.cat.vandelay.queue.bib',
        'Grid Config: Vandelay Bib Queue',
        'cwst', 'label'
    )
), (
    'eg.grid.cat.vandelay.queue.authority', 'gui', 'object',
    oils_i18n_gettext(
        'eg.grid.cat.vandelay.queue.authority',
        'Grid Config: Vandelay Authority Queue',
        'cwst', 'label'
    )
), (
    'eg.grid.cat.vandelay.match_set.list', 'gui', 'object',
    oils_i18n_gettext(
        'eg.grid.cat.vandelay.match_set.list',
        'Grid Config: Vandelay Match Sets',
        'cwst', 'label'
    )
), (
    'eg.grid.cat.vandelay.match_set.quality', 'gui', 'object',
    oils_i18n_gettext(
        'eg.grid.cat.vandelay.match_set.quality',
        'Grid Config: Vandelay Match Quality Metrics',
        'cwst', 'label'
    )
), (
    'eg.grid.cat.vandelay.queue.items', 'gui', 'object',
    oils_i18n_gettext(
        'eg.grid.cat.vandelay.queue.items',
        'Grid Config: Vandelay Queue Import Items',
        'cwst', 'label'
    )
), (
    'eg.grid.cat.vandelay.queue.list.bib', 'gui', 'object',
    oils_i18n_gettext(
        'eg.grid.cat.vandelay.queue.list.bib',
        'Grid Config: Vandelay Bib Queue List',
        'cwst', 'label'
    )
), (
    'eg.grid.cat.vandelay.queue.bib.items', 'gui', 'object',
    oils_i18n_gettext(
        'eg.grid.cat.vandelay.queue.bib.items',
        'Grid Config: Vandelay Bib Items',
        'cwst', 'label'
    )
), (
    'eg.grid.cat.vandelay.queue.list.auth', 'gui', 'object',
    oils_i18n_gettext(
        'eg.grid.cat.vandelay.queue.list.auth',
        'Grid Config: Vandelay Authority Queue List',
        'cwst', 'label'
    )
), (
    'eg.grid.admin.vandelay.merge_profile', 'gui', 'object',
    oils_i18n_gettext(
        'eg.grid.admin.vandelay.merge_profile',
        'Grid Config: Vandelay Merge Profiles',
        'cwst', 'label'
    )
), (
    'eg.grid.admin.vandelay.bib_attr_definition', 'gui', 'object',
    oils_i18n_gettext(
        'eg.grid.admin.vandelay.bib_attr_definition',
        'Grid Config: Vandelay Bib Record Attributes',
        'cwst', 'label'
    )
), (
    'eg.grid.admin.vandelay.import_item_attr_definition', 'gui', 'object',
    oils_i18n_gettext(
        'eg.grid.admin.vandelay.import_item_attr_definition',
        'Grid Config: Vandelay Import Item Attributes',
        'cwst', 'label'
    )
);





SELECT evergreen.upgrade_deps_block_check('1151', :eg_version);

INSERT INTO config.workstation_setting_type (name, grp, datatype, label)
VALUES (
    'eg.cat.vandelay.import.templates', 'cat', 'object',
    oils_i18n_gettext(
        'eg.cat.vandelay.import.templates',
        'Vandelay Import Form Templates',
        'cwst', 'label'
    )
);


SELECT evergreen.upgrade_deps_block_check('1152', :eg_version);

INSERT into config.org_unit_setting_type 
    (name, datatype, grp, label, description)
VALUES ( 
    'ui.staff.angular_catalog.enabled', 'bool', 'gui',
    oils_i18n_gettext(
        'ui.staff.angular_catalog.enabled',
        'GUI: Enable Experimental Angular Staff Catalog',
        'coust', 'label'
    ),
    oils_i18n_gettext(
        'ui.staff.angular_catalog.enabled',
        'Display an entry point in the browser client for the ' ||
        'experimental Angular staff catalog.',
        'coust', 'description'
    )
);



SELECT evergreen.upgrade_deps_block_check('1153', :eg_version);

UPDATE config.org_unit_setting_type
SET label = oils_i18n_gettext(
         'webstaff.cat.label.left_label.left_margin'
        ,'Item Print Label - Left Margin for Spine Label'
        ,'coust'
        ,'label'
    ),
     description = oils_i18n_gettext(
         'webstaff.cat.label.left_label.left_margin'
        ,'Set the default left margin for the item print Spine Label. Please include a unit of measurement that is valid CSS. For example, "1in" or "2.5cm"'
        ,'coust'
        ,'description'
    )
WHERE NAME = 'webstaff.cat.label.left_label.left_margin';

UPDATE config.org_unit_setting_type
SET label = oils_i18n_gettext(
         'webstaff.cat.label.right_label.left_margin'
        ,'Item Print Label - Left Margin for Pocket Label'
        ,'coust'
        ,'label'
    ),
     description = oils_i18n_gettext(
         'webstaff.cat.label.right_label.left_margin'
        ,'Set the default left margin for the item print Pocket Label (or in other words, the desired space between the two labels). Please include a unit of measurement that is valid CSS. For example, "1in" or "2.5cm"'
        ,'coust'
        ,'description'
    )
WHERE NAME = 'webstaff.cat.label.right_label.left_margin';


UPDATE config.org_unit_setting_type
SET label = oils_i18n_gettext(
         'webstaff.cat.label.left_label.height'
        ,'Item Print Label - Height for Spine Label'
        ,'coust'
        ,'label'
    ),
     description = oils_i18n_gettext(
         'webstaff.cat.label.left_label.height'
        ,'Set the default height for the item print Spine Label. Please include a unit of measurement that is valid CSS. For example, "1in" or "2.5cm"'
        ,'coust'
        ,'description'
    )
WHERE NAME = 'webstaff.cat.label.left_label.height';

UPDATE config.org_unit_setting_type
SET label = oils_i18n_gettext(
         'webstaff.cat.label.left_label.width'
        ,'Item Print Label - Width for Spine Label'
        ,'coust'
        ,'label'
    ),
     description = oils_i18n_gettext(
         'webstaff.cat.label.left_label.width'
        ,'Set the default width for the item print Spine Label. Please include a unit of measurement that is valid CSS. For example, "1in" or "2.5cm"'
        ,'coust'
        ,'description'
    )
WHERE NAME = 'webstaff.cat.label.left_label.width';

UPDATE config.org_unit_setting_type
SET label = oils_i18n_gettext(
         'webstaff.cat.label.right_label.height'
        ,'Item Print Label - Height for Pocket Label'
        ,'coust'
        ,'label'
    ),
     description = oils_i18n_gettext(
         'webstaff.cat.label.right_label.height'
        ,'Set the default height for the item print Pocket Label. Please include a unit of measurement that is valid CSS. For example, "1in" or "2.5cm"'
        ,'coust'
        ,'description'
    )
WHERE NAME = 'webstaff.cat.label.right_label.height';

UPDATE config.org_unit_setting_type
SET label = oils_i18n_gettext(
         'webstaff.cat.label.right_label.width'
        ,'Item Print Label - Width for Pocket Label'
        ,'coust'
        ,'label'
    ),
     description = oils_i18n_gettext(
         'webstaff.cat.label.right_label.width'
        ,'Set the default width for the item print Pocket Label. Please include a unit of measurement that is valid CSS. For example, "1in" or "2.5cm"'
        ,'coust'
        ,'description'
    )
WHERE NAME = 'webstaff.cat.label.right_label.width';


SELECT evergreen.upgrade_deps_block_check('1155', :eg_version);

CREATE OR REPLACE FUNCTION reporter.enable_materialized_simple_record_trigger () RETURNS VOID AS $$

    TRUNCATE TABLE reporter.materialized_simple_record;

    INSERT INTO reporter.materialized_simple_record
        (id,fingerprint,quality,tcn_source,tcn_value,title,author,publisher,pubdate,isbn,issn)
        SELECT DISTINCT ON (id) * FROM reporter.old_super_simple_record;

    CREATE TRIGGER bbb_simple_rec_trigger
        AFTER INSERT OR UPDATE OR DELETE ON biblio.record_entry
        FOR EACH ROW EXECUTE PROCEDURE reporter.simple_rec_trigger();

$$ LANGUAGE SQL;



SELECT evergreen.upgrade_deps_block_check('1156', :eg_version);

ALTER TABLE reporter.template ALTER COLUMN description SET DEFAULT '';


SELECT evergreen.upgrade_deps_block_check('1159', :eg_version);

INSERT INTO config.marc_field(marc_format, marc_record_type, tag, name, description,
                              fixed_field, repeatable, mandatory, hidden)
VALUES (1, 'biblio', '758', $$Resource Identifier$$, $$An identifier for a resource that is either the resource described in the bibliographic record or a resource to which it is related. Resources thus identified may include, but are not limited to, FRBR works, expressions, manifestations, and items. The field does not prescribe a particular content standard or data model.$$,
FALSE, TRUE, FALSE, FALSE);
INSERT INTO config.record_attr_definition(name, label)
VALUES ('marc21_biblio_758_ind_1', 'MARC 21 biblio field 758 indicator position 1');
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_758_ind_1', '#', $$Undefined$$, FALSE, TRUE);
INSERT INTO config.record_attr_definition(name, label)
VALUES ('marc21_biblio_758_ind_2', 'MARC 21 biblio field 758 indicator position 2');
INSERT INTO config.coded_value_map(ctype, code, value, opac_visible, is_simple)
VALUES ('marc21_biblio_758_ind_2', '#', $$Undefined$$, FALSE, TRUE);
INSERT INTO config.marc_subfield(marc_format, marc_record_type, tag, code, description,
                                 repeatable, mandatory, hidden)
VALUES (1, 'biblio', '758', 'a', $$Label$$,
FALSE, FALSE, FALSE);
INSERT INTO config.marc_subfield(marc_format, marc_record_type, tag, code, description,
                                 repeatable, mandatory, hidden)
VALUES (1, 'biblio', '758', 'i', $$Relationship information$$,
TRUE, FALSE, FALSE);
INSERT INTO config.marc_subfield(marc_format, marc_record_type, tag, code, description,
                                 repeatable, mandatory, hidden)
VALUES (1, 'biblio', '758', '0', $$Authority record control number or standard number$$,
TRUE, FALSE, FALSE);
INSERT INTO config.marc_subfield(marc_format, marc_record_type, tag, code, description,
                                 repeatable, mandatory, hidden)
VALUES (1, 'biblio', '758', '1', $$Real World Object URI$$,
TRUE, FALSE, FALSE);
INSERT INTO config.marc_subfield(marc_format, marc_record_type, tag, code, description,
                                 repeatable, mandatory, hidden)
VALUES (1, 'biblio', '758', '3', $$Materials specified$$,
FALSE, FALSE, FALSE);
INSERT INTO config.marc_subfield(marc_format, marc_record_type, tag, code, description,
                                 repeatable, mandatory, hidden)
VALUES (1, 'biblio', '758', '4', $$Relationship$$,
TRUE, FALSE, FALSE);
INSERT INTO config.marc_subfield(marc_format, marc_record_type, tag, code, description,
                                 repeatable, mandatory, hidden)
VALUES (1, 'biblio', '758', '5', $$Institution to which field applies$$,
FALSE, FALSE, FALSE);
INSERT INTO config.marc_subfield(marc_format, marc_record_type, tag, code, description,
                                 repeatable, mandatory, hidden)
VALUES (1, 'biblio', '758', '6', $$Linkage$$,
FALSE, FALSE, FALSE);
INSERT INTO config.marc_subfield(marc_format, marc_record_type, tag, code, description,
                                 repeatable, mandatory, hidden)
VALUES (1, 'biblio', '758', '8', $$Field link and sequence number$$,
TRUE, FALSE, FALSE);

COMMIT;
