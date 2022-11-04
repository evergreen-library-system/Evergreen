BEGIN;

SELECT evergreen.upgrade_deps_block_check('1344', :eg_version);

-- This function is used to help clean up facet labels. Due to quirks in
-- MARC parsing, some facet labels may be generated with periods or commas
-- at the end.  This will strip a trailing commas off all the time, and
-- periods when they don't look like they are part of initials or dotted
-- abbreviations.
--      Smith, John                 =>  no change
--      Smith, John,                =>  Smith, John
--      Smith, John.                =>  Smith, John
--      Public, John Q.             => no change
--      Public, John, Ph.D.         => no change
--      Atlanta -- Georgia -- U.S.  => no change
--      Atlanta -- Georgia.         => Atlanta, Georgia
--      The fellowship of the rings / => The fellowship of the rings
--      Some title ;                  => Some title
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
        -- must have a single word-character following at least one non-word character
        IF substring(result from '\W\w\.$') IS NULL THEN
            result := substring(result from '^(.*)\.$');
        END IF;

    ELSIF last_char IN ('/',':',';','=') THEN -- Dangling subtitle/SoR separator
        IF substring(result from ' .$') IS NOT NULL THEN -- must have a space before last_char
            result := substring(result from '^(.*) .$');
        END IF;
    END IF;

    RETURN result;

END;
$$ language 'plpgsql';


INSERT INTO config.metabib_field_index_norm_map (field,norm,pos)
    SELECT  m.id,
            i.id,
            -1
      FROM  config.metabib_field m,
            config.index_normalizer i
      WHERE i.func = 'metabib.trim_trailing_punctuation'
            AND m.field_class='title' AND (m.browse_field OR m.facet_field OR m.display_field)
            AND NOT EXISTS (SELECT 1 FROM config.metabib_field_index_norm_map WHERE field = m.id AND norm = i.id);

COMMIT;

\qecho A partial reingest is necessary to get the full benefit of this change.
\qecho It will take a while. You can cancel now withoug losing the effect of
\qecho the rest of the upgrade script, and arrange the reingest later.
\qecho 

SELECT metabib.reingest_metabib_field_entries(
    id, TRUE, FALSE, FALSE, TRUE, 
    (SELECT ARRAY_AGG(id) FROM config.metabib_field WHERE field_class='title' AND (browse_field OR facet_field OR display_field))
) FROM biblio.record_entry;

