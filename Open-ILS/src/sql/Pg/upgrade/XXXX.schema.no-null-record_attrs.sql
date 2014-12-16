BEGIN;

CREATE OR REPLACE VIEW metabib.record_attr AS
    SELECT  id, HSTORE( ARRAY_AGG( attr ), ARRAY_AGG( value ) ) AS attrs
      FROM  metabib.record_attr_flat
      WHERE attr IS NOT NULL
      GROUP BY 1;

COMMIT;

