--Upgrade Script for 3.12.7 to 3.12.8
\set eg_version '''3.12.8'''
BEGIN;
INSERT INTO config.upgrade_log (version, applied_to) VALUES ('3.12.8', :eg_version);

INSERT INTO config.upgrade_log (version) VALUES ('1439');

-- Use oils_xpath_table instead of pgxml's xpath_table
CREATE OR REPLACE FUNCTION acq.extract_holding_attr_table (lineitem int, tag text) RETURNS SETOF acq.flat_lineitem_holding_subfield AS $$
DECLARE
    counter INT;
    lida    acq.flat_lineitem_holding_subfield%ROWTYPE;
BEGIN

    SELECT  COUNT(*) INTO counter
      FROM  oils_xpath_table(
                'id',
                'marc',
                'acq.lineitem',
                '//*[@tag="' || tag || '"]',
                'id=' || lineitem
            ) as t(i int,c text);

    FOR i IN 1 .. counter LOOP
        FOR lida IN
            SELECT  *
              FROM  (   SELECT  id,i,t,v
                          FROM  oils_xpath_table(
                                    'id',
                                    'marc',
                                    'acq.lineitem',
                                    '//*[@tag="' || tag || '"][position()=' || i || ']/*[text()]/@code|' ||
                                        '//*[@tag="' || tag || '"][position()=' || i || ']/*[@code and text()]',
                                    'id=' || lineitem
                                ) as t(id int,t text,v text)
                    )x
        LOOP
            RETURN NEXT lida;
        END LOOP;
    END LOOP;

    RETURN;
END;
$$ LANGUAGE PLPGSQL;


COMMIT;

-- Update auditor tables to catch changes to source tables.
--   Can be removed/skipped if there were no schema changes.
SELECT auditor.update_auditors();
