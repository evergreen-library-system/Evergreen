BEGIN;

-- Bring authorized headings into the symspell dictionary. Side
-- loader should be used for Real Sites.  See below the COMMIT.
/*
SELECT  search.symspell_build_and_merge_entries(h.value, m.field_class, NULL)
  FROM  authority.simple_heading h
        JOIN authority.control_set_auth_field_metabib_field_map_refs a ON (a.authority_field = h.atag)
        JOIN config.metabib_field m ON (a.metabib_field=m.id);
*/

-- ensure that this function is in place; it hitherto had not been
-- present in baseline

CREATE OR REPLACE FUNCTION search.symspell_build_and_merge_entries (
    full_input      TEXT,
    source_class    TEXT,
    old_input       TEXT DEFAULT NULL,
    include_phrases BOOL DEFAULT FALSE
) RETURNS SETOF search.symspell_dictionary AS $F$
DECLARE
    new_entry       RECORD;
    conflict_entry  RECORD;
BEGIN

    IF full_input = old_input THEN -- neither NULL, and are the same
        RETURN;
    END IF;

    FOR new_entry IN EXECUTE $q$
        SELECT  count,
                prefix_key,
                s AS suggestions
          FROM  (SELECT prefix_key,
                        ARRAY_AGG(DISTINCT $q$ || source_class || $q$_suggestions[1]) s,
                        SUM($q$ || source_class || $q$_count) count
                  FROM  search.symspell_build_entries($1, $2, $3, $4)
                  GROUP BY 1) x
        $q$ USING full_input, source_class, old_input, include_phrases
    LOOP
        EXECUTE $q$
            SELECT  prefix_key,
                    $q$ || source_class || $q$_suggestions suggestions,
                    $q$ || source_class || $q$_count count
              FROM  search.symspell_dictionary
              WHERE prefix_key = $1 $q$
            INTO conflict_entry
            USING new_entry.prefix_key;

        IF new_entry.count <> 0 THEN -- Real word, and count changed
            IF conflict_entry.prefix_key IS NOT NULL THEN -- we'll be updating
                IF conflict_entry.count > 0 THEN -- it's a real word
                    RETURN QUERY EXECUTE $q$
                        UPDATE  search.symspell_dictionary
                           SET  $q$ || source_class || $q$_count = $2
                          WHERE prefix_key = $1
                          RETURNING * $q$
                        USING new_entry.prefix_key, GREATEST(0, new_entry.count + conflict_entry.count);
                ELSE -- it was a prefix key or delete-emptied word before
                    IF conflict_entry.suggestions @> new_entry.suggestions THEN -- already have all suggestions here...
                        RETURN QUERY EXECUTE $q$
                            UPDATE  search.symspell_dictionary
                               SET  $q$ || source_class || $q$_count = $2
                              WHERE prefix_key = $1
                              RETURNING * $q$
                            USING new_entry.prefix_key, GREATEST(0, new_entry.count);
                    ELSE -- new suggestion!
                        RETURN QUERY EXECUTE $q$
                            UPDATE  search.symspell_dictionary
                               SET  $q$ || source_class || $q$_count = $2,
                                    $q$ || source_class || $q$_suggestions = $3
                              WHERE prefix_key = $1
                              RETURNING * $q$
                            USING new_entry.prefix_key, GREATEST(0, new_entry.count), evergreen.text_array_merge_unique(conflict_entry.suggestions,new_entry.suggestions);
                    END IF;
                END IF;
            ELSE
                -- We keep the on-conflict clause just in case...
                RETURN QUERY EXECUTE $q$
                    INSERT INTO search.symspell_dictionary AS d (
                        $q$ || source_class || $q$_count,
                        prefix_key,
                        $q$ || source_class || $q$_suggestions
                    ) VALUES ( $1, $2, $3 ) ON CONFLICT (prefix_key) DO
                        UPDATE SET  $q$ || source_class || $q$_count = d.$q$ || source_class || $q$_count + EXCLUDED.$q$ || source_class || $q$_count,
                                    $q$ || source_class || $q$_suggestions = evergreen.text_array_merge_unique(d.$q$ || source_class || $q$_suggestions, EXCLUDED.$q$ || source_class || $q$_suggestions)
                        RETURNING * $q$
                    USING new_entry.count, new_entry.prefix_key, new_entry.suggestions;
            END IF;
        ELSE -- key only, or no change
            IF conflict_entry.prefix_key IS NOT NULL THEN -- we'll be updating
                IF NOT conflict_entry.suggestions @> new_entry.suggestions THEN -- There are new suggestions
                    RETURN QUERY EXECUTE $q$
                        UPDATE  search.symspell_dictionary
                           SET  $q$ || source_class || $q$_suggestions = $2
                          WHERE prefix_key = $1
                          RETURNING * $q$
                        USING new_entry.prefix_key, evergreen.text_array_merge_unique(conflict_entry.suggestions,new_entry.suggestions);
                END IF;
            ELSE
                RETURN QUERY EXECUTE $q$
                    INSERT INTO search.symspell_dictionary AS d (
                        $q$ || source_class || $q$_count,
                        prefix_key,
                        $q$ || source_class || $q$_suggestions
                    ) VALUES ( $1, $2, $3 ) ON CONFLICT (prefix_key) DO -- key exists, suggestions may be added due to this entry
                        UPDATE SET  $q$ || source_class || $q$_suggestions = evergreen.text_array_merge_unique(d.$q$ || source_class || $q$_suggestions, EXCLUDED.$q$ || source_class || $q$_suggestions)
                    RETURNING * $q$
                    USING new_entry.count, new_entry.prefix_key, new_entry.suggestions;
            END IF;
        END IF;
    END LOOP;
END;
$F$ LANGUAGE PLPGSQL;

CREATE OR REPLACE FUNCTION search.symspell_maintain_entries () RETURNS TRIGGER AS $f$
DECLARE
    search_class    TEXT;
    new_value       TEXT := NULL;
    old_value       TEXT := NULL;
BEGIN

    IF TG_TABLE_SCHEMA = 'authority' THEN
        SELECT  m.field_class INTO search_class
          FROM  authority.control_set_auth_field_metabib_field_map_refs a
                JOIN config.metabib_field m ON (a.metabib_field=m.id)
          WHERE a.authority_field = NEW.atag;

        IF NOT FOUND THEN
            RETURN NULL;
        END IF;
    ELSE
        search_class := COALESCE(TG_ARGV[0], SPLIT_PART(TG_TABLE_NAME,'_',1));
    END IF;

    IF TG_OP IN ('INSERT', 'UPDATE') THEN
        new_value := NEW.value;
    END IF;

    IF TG_OP IN ('DELETE', 'UPDATE') THEN
        old_value := OLD.value;
    END IF;

    PERFORM * FROM search.symspell_build_and_merge_entries(new_value, search_class, old_value);

    RETURN NULL; -- always fired AFTER
END;
$f$ LANGUAGE PLPGSQL;

CREATE TRIGGER maintain_symspell_entries_tgr
    AFTER INSERT OR UPDATE OR DELETE ON authority.simple_heading
    FOR EACH ROW EXECUTE PROCEDURE search.symspell_maintain_entries();

COMMIT;

-- Generate symspell sideloader data with authority headings included.

/*

\a
\t

\o title
select value from metabib.title_field_entry;
select  h.value
  from  authority.simple_heading h
        join authority.control_set_auth_field_metabib_field_map_refs a on (a.authority_field = h.atag)
        join config.metabib_field m on (a.metabib_field=m.id and m.field_class='title');

\o author
select value from metabib.author_field_entry;
select  h.value
  from  authority.simple_heading h
        join authority.control_set_auth_field_metabib_field_map_refs a on (a.authority_field = h.atag)
        join config.metabib_field m on (a.metabib_field=m.id and m.field_class='author');

\o subject
select value from metabib.subject_field_entry;
select  h.value
  from  authority.simple_heading h
        join authority.control_set_auth_field_metabib_field_map_refs a on (a.authority_field = h.atag)
        join config.metabib_field m on (a.metabib_field=m.id and m.field_class='subject');

\o series
select value from metabib.series_field_entry;

\o identifier
select value from metabib.identifier_field_entry;

\o keyword
select value from metabib.keyword_field_entry;

\o
\a
\t

*/

