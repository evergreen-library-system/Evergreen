BEGIN;

SELECT evergreen.upgrade_deps_block_check('1087', :eg_version);

CREATE OR REPLACE FUNCTION asset.patron_default_visibility_mask () RETURNS TABLE (b_attrs TEXT, c_attrs TEXT)  AS $f$
DECLARE
    copy_flags      TEXT; -- "c" attr

    owning_lib      TEXT; -- "c" attr
    circ_lib        TEXT; -- "c" attr
    status          TEXT; -- "c" attr
    location        TEXT; -- "c" attr
    location_group  TEXT; -- "c" attr

    luri_org        TEXT; -- "b" attr
    bib_sources     TEXT; -- "b" attr

    bib_tests       TEXT := '';
BEGIN
    copy_flags      := asset.all_visible_flags(); -- Will always have at least one

    owning_lib      := NULLIF(asset.owning_lib_default(),'!()');

    circ_lib        := NULLIF(asset.circ_lib_default(),'!()');
    status          := NULLIF(asset.status_default(),'!()');
    location        := NULLIF(asset.location_default(),'!()');
    location_group  := NULLIF(asset.location_group_default(),'!()');

    -- LURIs will be handled at the perl layer directly
    -- luri_org        := NULLIF(asset.luri_org_default(),'!()');
    bib_sources     := NULLIF(asset.bib_source_default(),'()');


    IF luri_org IS NOT NULL AND bib_sources IS NOT NULL THEN
        bib_tests := '('||ARRAY_TO_STRING( ARRAY[luri_org,bib_sources], '|')||')&('||luri_org||')&';
    ELSIF luri_org IS NOT NULL THEN
        bib_tests := luri_org || '&';
    ELSIF bib_sources IS NOT NULL THEN
        bib_tests := bib_sources || '|';
    END IF;

    RETURN QUERY SELECT bib_tests,
        '('||ARRAY_TO_STRING(
            ARRAY[copy_flags,owning_lib,circ_lib,status,location,location_group]::TEXT[],
            '&'
        )||')';
END;
$f$ LANGUAGE PLPGSQL STABLE ROWS 1;

COMMIT;

