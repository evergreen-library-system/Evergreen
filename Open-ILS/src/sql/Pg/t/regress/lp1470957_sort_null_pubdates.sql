BEGIN;

SELECT plan(1);

INSERT INTO biblio.record_entry (marc, last_xact_id)
VALUES (
    $$<record    xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"    xsi:schemaLocation="http://www.loc.gov/MARC21/slim http://www.loc.gov/standards/marcxml/schema/MARC21slim.xsd"    xmlns="http://www.loc.gov/MARC21/slim"><leader>00620cam a2200205Ka 4500</leader><controlfield tag="001">1</controlfield><controlfield tag="003">CONS</controlfield><controlfield tag="005">20150113170906.0</controlfield><controlfield tag="008">070101s||||                        eng d</controlfield><datafield tag="245" ind1=" " ind2=" "><subfield code="a">Harry potter</subfield></datafield><datafield tag="901" ind1=" " ind2=" "><subfield code="a">1</subfield><subfield code="b"></subfield><subfield code="c">1</subfield><subfield code="t">biblio</subfield></datafield></record>$$,
    'LP#1414112'
);

SELECT is(
    (
        SELECT COUNT(*) FROM metabib.record_sorter
        WHERE source = CURRVAL('biblio.record_entry_id_seq')
        AND attr = 'pubdate'
    ),
    0::BIGINT,
    'LP#1470957: do not provide sorter for |||| pubdate'
);

ROLLBACK;
