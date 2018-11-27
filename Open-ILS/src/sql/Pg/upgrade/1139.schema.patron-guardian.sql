
BEGIN;

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


COMMIT;

