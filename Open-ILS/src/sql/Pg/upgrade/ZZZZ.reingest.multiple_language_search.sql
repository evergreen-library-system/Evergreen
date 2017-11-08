BEGIN;

SELECT evergreen.upgrade_deps_block_check('ZZZZ', :eg_version);

SELECT metabib.reingest_record_attributes (record, '{item_lang}'::TEXT[])
  FROM (SELECT  DINSTINCT record
          FROM  metabib.real_full_rec
           WHERE tag = '041'
                  AND subfield IN ('a','b','d','e','f','g','m')
       ) x;

COMMIT;

