BEGIN;

INSERT INTO config.upgrade_log (version) VALUES ('0516'); 

CREATE OR REPLACE FUNCTION public.extract_acq_marc_field ( BIGINT, TEXT, TEXT) RETURNS TEXT AS $$    
    SELECT extract_marc_field('acq.lineitem', $1, $2, $3);
$$ LANGUAGE SQL;

COMMIT;
