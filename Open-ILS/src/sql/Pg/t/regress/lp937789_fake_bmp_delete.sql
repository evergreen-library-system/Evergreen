BEGIN;

SELECT plan(6);

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
    'LP#937789: new monograph parts start out active'
)
FROM biblio.monograph_part
WHERE record = 999999998
AND NOT deleted;

SELECT is(
    (XPATH(
        '//ns:monograph_parts/ns:monograph_part/@label',
        unapi.holdings_xml(999999998, 1, 'CONS', 0, '{bmp}'),
        '{{ns,http://open-ils.org/spec/holdings/v1}}'
    ))[1]::TEXT,
    'Part 1',
    'LP#937789: unapi.holdings_xml returns monograph part'
);

SELECT is(
    (XPATH(
        '/ns:monograph_part/@label',
        unapi.bmp(CURRVAL('biblio.monograph_part_id_seq'), '', '', '{}', 'CONS'),
        '{{ns,http://open-ils.org/spec/holdings/v1}}'
    ))[1]::TEXT,
    'Part 1',
    'LP#937789: unapi.bmp returns monograph part'
);

DELETE FROM biblio.monograph_part WHERE record = 999999998;

SELECT is(
    deleted,
    TRUE,
    'LP#937789: deleting monograph part sets deleted flag'
)
FROM biblio.monograph_part
WHERE record = 999999998
AND label = 'Part 1';

SELECT is(
    (XPATH(
        '//ns:monograph_parts/ns:monograph_part/@label',
        unapi.holdings_xml(999999998, 1, 'CONS', 0, '{bmp}'),
        '{{ns,http://open-ils.org/spec/holdings/v1}}'
    ))[1]::TEXT,
    NULL,
    'LP#937789: unapi.holdings_xml does not return deleted monograph part'
);

SELECT is(
    unapi.bmp(CURRVAL('biblio.monograph_part_id_seq'), '', '', '{}', 'CONS')::TEXT,
    NULL,
    'LP#937789: unapi.bmp does not return deleted monograph part'
);

ROLLBACK;
