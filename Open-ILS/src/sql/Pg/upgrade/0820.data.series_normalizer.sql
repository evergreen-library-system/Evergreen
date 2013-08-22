BEGIN;

-- Remove [ and ] characters from seriestitle.
-- Those characters don't play well when searching.

SELECT evergreen.upgrade_deps_block_check('0820', :eg_version); -- Callender

INSERT INTO config.metabib_field_index_norm_map (field,norm,params, pos)
     SELECT  m.id,
             i.id,
             $$["]",""]$$,
             '-1'
       FROM  config.metabib_field m,
             config.index_normalizer i
       WHERE i.func IN ('replace')
             AND m.id IN (1);
             
INSERT INTO config.metabib_field_index_norm_map (field,norm,params, pos)
     SELECT  m.id,
             i.id,
             $$["[",""]$$,
             '-1'
       FROM  config.metabib_field m,
             config.index_normalizer i
       WHERE i.func IN ('replace')
             AND m.id IN (1);

COMMIT;
