BEGIN;

SELECT evergreen.upgrade_deps_block_check('0986', :eg_version);

CREATE EXTENSION IF NOT EXISTS unaccent SCHEMA public;

CREATE OR REPLACE FUNCTION evergreen.unaccent_and_squash ( IN arg text) RETURNS text
    IMMUTABLE STRICT AS $$
	BEGIN
	RETURN evergreen.lowercase(unaccent(regexp_replace(arg, '\s','','g')));
	END;
$$ LANGUAGE PLPGSQL;

-- The unaccented indices for patron name fields
CREATE INDEX actor_usr_first_given_name_unaccent_idx ON actor.usr (evergreen.unaccent_and_squash(first_given_name));
CREATE INDEX actor_usr_second_given_name_unaccent_idx ON actor.usr (evergreen.unaccent_and_squash(second_given_name));
CREATE INDEX actor_usr_family_name_unaccent_idx ON actor.usr (evergreen.unaccent_and_squash(family_name));

-- DB setting to control behavior; true by default
INSERT INTO config.org_unit_setting_type
( name, grp, label, description, datatype )
VALUES
('circ.patron_search.diacritic_insensitive',
 'circ',
 oils_i18n_gettext('circ.patron_search.diacritic_insensitive',
     'Patron search diacritic insensitive',
     'coust', 'label'),
 oils_i18n_gettext('circ.patron_search.diacritic_insensitive',
     'Match patron last, first, and middle names irrespective of usage of diacritical marks or spaces. (e.g., Ines will match Inés; de la Cruz will match Delacruz)',
     'coust', 'description'),
  'bool');

INSERT INTO actor.org_unit_setting (
    org_unit, name, value
) VALUES (
    (SELECT id FROM actor.org_unit WHERE parent_ou IS NULL),
    'circ.patron_search.diacritic_insensitive',
    'true'
);


COMMIT;

