BEGIN;

SELECT evergreen.upgrade_deps_block_check('XXXX', :eg_version);

CREATE OR REPLACE VIEW metabib.record_attr_flat AS
    SELECT  v.source AS id,
            m.attr AS attr,
            m.value AS value
      FROM  metabib.record_attr_vector_list v
            LEFT JOIN metabib.uncontrolled_record_attr_value m ON ( m.id = ANY( v.vlist ) )
        UNION
    SELECT  v.source AS id,
            c.ctype AS attr,
            c.code AS value
      FROM  metabib.record_attr_vector_list v
            LEFT JOIN config.coded_value_map c ON ( c.id = ANY( v.vlist ) );

COMMIT;

