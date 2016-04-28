BEGIN;

SELECT plan(4);

INSERT INTO biblio.record_entry (id, last_xact_id, marc)
VALUES (999999998, 'pgtap', '<record    xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"    xsi:schemaLocation="http://www.loc.gov/MARC21/slim http://www.loc.gov/standards/marcxml/schema/MARC21slim.xsd"    xmlns="http://www.loc.gov/MARC21/slim">
  <leader>00531nam a2200157 a 4500</leader>
  <controlfield tag="005">20080729170300.0</controlfield>
  <controlfield tag="008">      t19981999enka              0 eng  </controlfield>
  <datafield tag="245" ind1="1" ind2="4">
    <subfield code="a">test-value</subfield>
  </datafield>
</record>');

INSERT INTO biblio.monograph_part(record, label) VALUES (999999998, 'Part 1');

SELECT is(
    label,
    'Part 1',
    'LP#1569884: new monograph parts start out active'
)
FROM biblio.monograph_part
WHERE record = 999999998
AND NOT deleted;

DELETE FROM biblio.monograph_part WHERE record = 999999998;

SELECT is(
    deleted,
    TRUE,
    'LP#1569884: deleting monograph part sets deleted flag'
)
FROM biblio.monograph_part
WHERE record = 999999998
AND label = 'Part 1';

SELECT lives_ok(
    $$INSERT INTO biblio.monograph_part(record, label) VALUES (999999998, 'Part 1')$$,
    'LP#1569884: can add monograph part with same label as logically deleted one'
);

SELECT is(
    COUNT(*)::INT,
    1,
    'LP#1569884: one active part with label Part 1'
)
FROM biblio.monograph_part
WHERE record = 999999998
AND label = 'Part 1'
AND NOT deleted;

ROLLBACK;
