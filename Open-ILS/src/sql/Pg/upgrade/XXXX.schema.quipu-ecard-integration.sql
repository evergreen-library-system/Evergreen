BEGIN;

SELECT evergreen.upgrade_deps_block_check('XXXX', :eg_version); -- berick/csharp/Dyrcona/phasefx

-- Thank you, berick :-)
-- Start at 100 to avoid barcodes with long stretches of zeros early on.
-- eCard barcodes have 7 auto-generated digits.
CREATE SEQUENCE actor.auto_barcode_ecard_seq START 100 MAXVALUE 9999999;

CREATE OR REPLACE FUNCTION actor.generate_barcode
    (prefix TEXT, numchars INTEGER, seqname TEXT) RETURNS TEXT AS
$$
    SELECT NEXTVAL($3); -- bump the sequence up 1
    SELECT CASE
        WHEN LENGTH(CURRVAL($3)::TEXT) > $2 THEN NULL
        ELSE $1 || LPAD(CURRVAL($3)::TEXT, $2, '0')
    END;
$$ LANGUAGE SQL;

COMMENT ON FUNCTION actor.generate_barcode(TEXT, INTEGER, TEXT) IS $$
Generate a barcode starting with 'prefix' and followed by 'numchars'
numbers.  The auto portion numbers are generated from the provided
sequence, guaranteeing uniquness across all barcodes generated with
the same sequence.  The number is left-padded with zeros to meet the
numchars size requirement.  Returns NULL if the sequnce value is
higher than numchars can accommodate.
$$;

CREATE OR REPLACE FUNCTION evergreen.json_delta(old_obj JSON, new_obj JSON, only_keys TEXT[] DEFAULT '{}') RETURNS JSONB AS $f$
use JSON;
use List::Util qw/uniq/;

my $old = shift;
my $new = shift;
my $keylist = shift;

$old = from_json($old) if (!ref($old));
$new = from_json($new) if (!ref($new));

my $delta = {};

my @keys = @$keylist;
@keys = (keys(%$old), keys(%$new)) if (!@keys);

for my $key (uniq @keys) {
    $$delta{$key} = [$$old{$key},$$new{$key}] if ((
        ((!exists($$old{$key}) or !exists($$new{$key})) and not (!exists($$old{$key}) and !exists($$new{$key}))) # one exists
        or ((!defined($$old{$key}) or !defined($$new{$key})) and not (!defined($$old{$key}) and !defined($$new{$key}))) # or one is defined
        or ((defined($$old{$key}) and defined($$new{$key})) and $$old{$key} ne $$new{$key}) # or they do not match
    ) and grep {defined} $$old{$key},$$new{$key}); # there is data
}

return to_json($delta);
$f$ LANGUAGE PLPERLU;

CREATE TABLE actor.usr_delta_history (
    id          BIGSERIAL   PRIMARY KEY,
    eg_user     INT         REFERENCES actor.usr (id) ON UPDATE CASCADE ON DELETE SET NULL,
    eg_ws       INT         REFERENCES actor.workstation (id) ON UPDATE CASCADE ON DELETE SET NULL,
    usr_id      INT         NOT NULL REFERENCES actor.usr (id) ON UPDATE CASCADE ON DELETE CASCADE,
    change_time TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    delta       JSONB       NOT NULL,
    keylist     TEXT[]
);

CREATE OR REPLACE FUNCTION actor.record_usr_delta() RETURNS TRIGGER AS $f$
BEGIN
    INSERT INTO actor.usr_delta_history (eg_user, eg_ws, usr_id, delta, keylist)
        SELECT  a.eg_user,
                a.eg_ws,
                OLD.id,
                evergreen.json_delta(to_json(OLD.*), to_json(NEW.*), TG_ARGV),
                TG_ARGV
          FROM  auditor.get_audit_info() a;
    RETURN NEW;
END;
$f$ LANGUAGE PLPGSQL;

CREATE TRIGGER record_usr_delta
    AFTER UPDATE ON actor.usr
    FOR EACH ROW
    EXECUTE FUNCTION actor.record_usr_delta(last_update_time /* unquoted, literal comma-separated column names to include in the delta */);
ALTER TABLE actor.usr DISABLE TRIGGER record_usr_delta;
ALTER TABLE permission.grp_tree ADD COLUMN erenew BOOL NOT NULL DEFAULT FALSE;
ALTER TABLE permission.grp_tree ADD COLUMN temporary_perm_interval INTERVAL;
ALTER TABLE actor.usr ADD COLUMN guardian_email TEXT;

SELECT auditor.update_auditors(); 

-- for guardian_email
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
			guardian_email = NULL,
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
			pref_prefix = NULL,
			pref_first_given_name = NULL,
			pref_second_given_name = NULL,
			pref_family_name = NULL,
			pref_suffix = NULL,
			name_keywords = NULL,
			create_date = now(),
			expire_date = now()
	WHERE
		id = src_usr;
END;
$$ LANGUAGE plpgsql;

---

COMMIT;
