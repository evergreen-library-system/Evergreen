BEGIN;

SELECT evergreen.upgrade_deps_block_check('1006', :eg_version);

-- This function is used to help clean up facet labels. Due to quirks in
-- MARC parsing, some facet labels may be generated with periods or commas
-- at the end.  This will strip a trailing commas off all the time, and
-- periods when they don't look like they are part of initials.
--      Smith, John    =>  no change
--      Smith, John,   =>  Smith, John
--      Smith, John.   =>  Smith, John
--      Public, John Q. => no change
CREATE OR REPLACE FUNCTION metabib.trim_trailing_punctuation ( TEXT ) RETURNS TEXT AS $$
DECLARE
    result    TEXT;
    last_char TEXT;
BEGIN
    result := $1;
    last_char = substring(result from '.$');

    IF last_char = ',' THEN
        result := substring(result from '^(.*),$');

    ELSIF last_char = '.' THEN
        IF substring(result from ' \w\.$') IS NULL THEN
            result := substring(result from '^(.*)\.$');
        END IF;
    END IF;

    RETURN result;

END;
$$ language 'plpgsql';

INSERT INTO config.index_normalizer (name, description, func, param_count) VALUES (
	'Trim Trailing Punctuation',
	'Eliminate extraneous trailing commas and periods in text',
	'metabib.trim_trailing_punctuation',
	0
);

INSERT INTO config.metabib_field_index_norm_map (field,norm,pos)
    SELECT  m.id,
            i.id,
            -1
      FROM  config.metabib_field m,
            config.index_normalizer i
      WHERE i.func = 'metabib.trim_trailing_punctuation'
            AND m.id IN (7,8,9,10);

COMMIT;

\qecho To apply the improvements for facets and browse entries for author
\qecho headings, you need to perform a browse and facet reingest of your
\qecho records. It may take a while. You can cancel now withoug losing
\qecho the effect of the rest of the upgrade script, and arrange the reingest
\qecho later.
\qecho 
SELECT metabib.reingest_metabib_field_entries(id, FALSE, FALSE, TRUE)
    FROM biblio.record_entry;
