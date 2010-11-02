BEGIN;

INSERT INTO config.upgrade_log (version) VALUES ('0456'); -- gmc

INSERT INTO acq.lineitem_marc_attr_definition ( code, description, xpath, remove )
SELECT 'upc', 'UPC', '//*[@tag="024" and @ind1="1"]/*[@code="a"]', $r$(?:-|\s.+$)$r$
WHERE NOT EXISTS (
    SELECT 1 FROM acq.lineitem_marc_attr_definition WHERE code = 'upc'
);

COMMIT;
