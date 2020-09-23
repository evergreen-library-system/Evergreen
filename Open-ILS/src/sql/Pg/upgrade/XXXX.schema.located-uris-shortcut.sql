BEGIN;

-- SELECT evergreen.upgrade_deps_block_check('TODO', :eg_version);

CREATE OR REPLACE FUNCTION evergreen.located_uris_as_uris 
    (bibid BIGINT, ouid INT, pref_lib INT DEFAULT NULL)
    RETURNS SETOF asset.uri AS $FUNK$
    /* Maps a bib directly to its scoped asset.uri's */

    SELECT uri.* 
    FROM evergreen.located_uris($1, $2, $3) located_uri
    JOIN asset.uri_call_number_map map ON (map.call_number = located_uri.id)
    JOIN asset.uri uri ON (uri.id = map.uri)

$FUNK$ LANGUAGE SQL STABLE;

COMMIT;
