BEGIN;

SELECT evergreen.upgrade_deps_block_check('1516', :eg_version);

CREATE OR REPLACE FUNCTION actor.user_ingest_name_keywords()
    RETURNS TRIGGER AS $func$
BEGIN
    NEW.name_kw_tsvector := TO_TSVECTOR(
        COALESCE(NEW.prefix, '')                || ' ' ||
        COALESCE(NEW.first_given_name, '')      || ' ' ||
        COALESCE(evergreen.unaccent_and_squash(NEW.first_given_name), '') || ' ' ||
        COALESCE(NEW.second_given_name, '')     || ' ' ||
        COALESCE(evergreen.unaccent_and_squash(NEW.second_given_name), '') || ' ' ||
        COALESCE(NEW.family_name, '')           || ' ' ||
        COALESCE(evergreen.unaccent_and_squash(NEW.family_name), '') || ' ' ||
        COALESCE(NEW.suffix, '')                || ' ' ||
        COALESCE(NEW.pref_prefix, '')            || ' ' ||
        COALESCE(NEW.pref_first_given_name, '')  || ' ' ||
        COALESCE(evergreen.unaccent_and_squash(NEW.pref_first_given_name), '') || ' ' ||
        COALESCE(NEW.pref_second_given_name, '') || ' ' ||
        COALESCE(evergreen.unaccent_and_squash(NEW.pref_second_given_name), '') || ' ' ||
        COALESCE(NEW.pref_family_name, '')       || ' ' ||
        COALESCE(evergreen.unaccent_and_squash(NEW.pref_family_name), '') || ' ' ||
        COALESCE(NEW.pref_suffix, '')            || ' ' ||
        COALESCE(NEW.name_keywords, '')          || ' ' ||
        COALESCE(NEW.guardian, '')               || ' ' ||
        COALESCE(evergreen.unaccent_and_squash(NEW.guardian), '')
    );
    RETURN NEW;
END;
$func$ LANGUAGE PLPGSQL;

COMMIT;

-- to trigger user_ingest_name_keywords_tgr
-- UPDATE actor.usr SET id = id WHERE NOT DELETED;

\qecho ''
\qecho '-----'
\qecho 'To update the patron search keyword index to include patron/guardian '
\qecho 'data for existing patrons, update all non-deleted actor.usr rows'
\qecho 'similar to the follow, with the caveat that updating larger data'
\qecho 'sets should probably be performed in batches.'
\qecho ''
\qecho 'UPDATE actor.usr SET id = id WHERE NOT deleted;'
\qecho '-----'
\qecho ''

