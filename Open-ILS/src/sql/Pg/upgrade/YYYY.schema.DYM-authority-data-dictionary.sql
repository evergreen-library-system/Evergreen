BEGIN;

-- Bring authorized headings into the symspell dictionary. Side
-- loader should be used for Real Sites.  See below the COMMIT.
/*
SELECT  search.symspell_build_and_merge_entries(h.value, m.field_class, NULL)
  FROM  authority.simple_heading h
        JOIN authority.control_set_auth_field_metabib_field_map_refs a ON (a.authority_field = a.atag)
        JOIN config.metabib_field m ON (a.metabib_field=m.id);
*/

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
        join authority.control_set_auth_field_metabib_field_map_refs a on (a.authority_field = a.atag)
        join config.metabib_field m on (a.metabib_field=m.id and m.field_class='title');

\o author
select value from metabib.author_field_entry;
select  h.value
  from  authority.simple_heading h
        join authority.control_set_auth_field_metabib_field_map_refs a on (a.authority_field = a.atag)
        join config.metabib_field m on (a.metabib_field=m.id and m.field_class='author');

\o subject
select value from metabib.subject_field_entry;
select  h.value
  from  authority.simple_heading h
        join authority.control_set_auth_field_metabib_field_map_refs a on (a.authority_field = a.atag)
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

