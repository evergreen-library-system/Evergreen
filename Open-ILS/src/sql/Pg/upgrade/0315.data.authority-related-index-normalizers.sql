BEGIN;

INSERT INTO config.upgrade_log (version) VALUES ('0315'); --miker

CREATE OR REPLACE FUNCTION public.remove_paren_substring( TEXT ) RETURNS TEXT AS $func$
    SELECT regexp_replace($1, $$\([^)]+\)$$, '', 'g');
$func$ LANGUAGE SQL STRICT IMMUTABLE;

INSERT INTO config.metabib_field ( id, field_class, name, label, format, xpath, facet_field, search_field ) VALUES
    (26, 'identifier', 'arcn', oils_i18n_gettext(26, 'Authority record control number', 'cmf', 'label'), 'marcxml', $$//marc:subfield[@code='0']$$, TRUE, FALSE );
 
SELECT SETVAL('config.metabib_field_id_seq'::TEXT, (SELECT MAX(id) FROM config.metabib_field), TRUE);
 
INSERT INTO config.index_normalizer (name, description, func, param_count) VALUES (
	'Remove Parenthesized Substring',
	'Remove any parenthesized substrings from the extracted text, such as the agency code preceding authority record control numbers in subfield 0.',
	'remove_paren_substring',
	0
);

INSERT INTO config.index_normalizer (name, description, func, param_count) VALUES (
	'Trim Surrounding Space',
	'Trim leading and trailing spaces from extracted text.',
	'btrim',
	0
);

INSERT INTO config.metabib_field_index_norm_map (field,norm,pos)
    SELECT  m.id,
            i.id,
            -2
      FROM  config.metabib_field m,
            config.index_normalizer i
      WHERE i.func IN ('remove_paren_substring')
            AND m.id IN (26);

INSERT INTO config.metabib_field_index_norm_map (field,norm,pos)
    SELECT  m.id,
            i.id,
            -1
      FROM  config.metabib_field m,
            config.index_normalizer i
      WHERE i.func IN ('btrim')
            AND m.id IN (26);

COMMIT;

