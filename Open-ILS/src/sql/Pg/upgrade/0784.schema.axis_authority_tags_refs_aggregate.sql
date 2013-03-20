-- Evergreen DB patch XXXX.function.axis_authority_tags_refs_aggregate.sql
--
BEGIN;

-- check whether patch can be applied
SELECT evergreen.upgrade_deps_block_check('0784', :eg_version);

CREATE OR REPLACE FUNCTION authority.axis_authority_tags_refs(a TEXT) RETURNS INT[] AS $$
    SELECT ARRAY_AGG(y) from (
       SELECT  unnest(ARRAY_CAT(
                 ARRAY[a.field],
                 (SELECT ARRAY_ACCUM(x.id) FROM authority.control_set_authority_field x WHERE x.main_entry = a.field)
             )) y
       FROM  authority.browse_axis_authority_field_map a
       WHERE axis = $1) x;
$$ LANGUAGE SQL;

CREATE OR REPLACE FUNCTION authority.btag_authority_tags_refs(btag TEXT) RETURNS INT[] AS $$
    SELECT ARRAY_AGG(y) from (
        SELECT  unnest(ARRAY_CAT(
                    ARRAY[a.authority_field],
                    (SELECT ARRAY_ACCUM(x.id) FROM authority.control_set_authority_field x WHERE x.main_entry = a.authority_field)
                )) y
      FROM  authority.control_set_bib_field a
      WHERE a.tag = $1) x
$$ LANGUAGE SQL;

CREATE OR REPLACE FUNCTION authority.atag_authority_tags_refs(atag TEXT) RETURNS INT[] AS $$
    SELECT ARRAY_AGG(y) from (
        SELECT  unnest(ARRAY_CAT(
                    ARRAY[a.id],
                    (SELECT ARRAY_ACCUM(x.id) FROM authority.control_set_authority_field x WHERE x.main_entry = a.id)
                )) y
      FROM  authority.control_set_authority_field a
      WHERE a.tag = $1) x
$$ LANGUAGE SQL;


COMMIT;
