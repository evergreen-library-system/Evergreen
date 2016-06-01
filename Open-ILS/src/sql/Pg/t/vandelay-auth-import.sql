BEGIN;

SELECT plan(3);

-------------------------
-- Setup test environment
--   User w/ library card
--   Vandelay settings (merge profile, queue)
--   "Pre-loaded" authority record to be overlayed
--   Matching authority record added to Vandelay queue
--     including 905u with user barcode
-------------------------

INSERT INTO actor.usr (profile, ident_type, usrname, home_ou, family_name,
            passwd, first_given_name, expire_date, dob, suffix)
    VALUES (13, 1, 'TEST_USER', 1, 'TESTER', 'TEST1234', 'TEST',
            NOW() + '3 years'::INTERVAL, NULL, NULL);

INSERT INTO actor.card (barcode, usr)
    VALUES ('TEST_BARCODE', CURRVAL('actor.usr_id_seq'));

UPDATE actor.usr
    SET card = CURRVAL('actor.card_id_seq')
    WHERE id = CURRVAL('actor.usr_id_seq');

INSERT INTO vandelay.merge_profile 
    (owner, name, preserve_spec) VALUES (1, 'TEST', '901c');

INSERT INTO vandelay.authority_queue (owner, name)
    VALUES (CURRVAL('actor.usr_id_seq'), 'TEST');

INSERT INTO authority.record_entry (id, edit_date, last_xact_id, marc)
    VALUES (1234512345, now() - '15 days'::INTERVAL, 'TEST',
   '<record xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xmlns="http://www.loc.gov/MARC21/slim" xsi:schemaLocation="http://www.loc.gov/MARC21/slim http://www.loc.gov/standards/marcxml/schema/MARC21slim.xsd"><leader>00208nz  a2200097o  45 0</leader><controlfield tag="001">73</controlfield><controlfield tag="003">CONS</controlfield><controlfield tag="005">20021207110052.0</controlfield><controlfield tag="008">021207n| acannaabn          |n aac     d</controlfield><datafield tag="035" ind1=" " ind2=" "><subfield code="a">(IISG)IISGa11554924</subfield></datafield><datafield tag="040" ind1=" " ind2=" "><subfield code="a">IISG</subfield><subfield code="c">IISG</subfield></datafield><datafield tag="100" ind1="0" ind2=" "><subfield code="a">Maloy, Eileen</subfield></datafield><datafield tag="901" ind1=" " ind2=" "><subfield code="t">authority</subfield></datafield></record>');

INSERT INTO vandelay.queued_authority_record (queue, purpose, marc)
    SELECT CURRVAL('vandelay.queue_id_seq'), 'overlay',
    '<record xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xmlns="http://www.loc.gov/MARC21/slim" xsi:schemaLocation="http://www.loc.gov/MARC21/slim http://www.loc.gov/standards/marcxml/schema/MARC21slim.xsd"><leader>00208nz  a2200097o  45 0</leader><controlfield tag="001">73</controlfield><controlfield tag="003">CONS</controlfield><controlfield tag="005">20021207110052.0</controlfield><controlfield tag="008">021207n| acannaabn          |n aac     d</controlfield><datafield tag="035" ind1=" " ind2=" "><subfield code="a">(IISG)IISGa11554924</subfield></datafield><datafield tag="040" ind1=" " ind2=" "><subfield code="a">IISG</subfield><subfield code="c">IISG</subfield></datafield><datafield tag="100" ind1="0" ind2=" "><subfield code="a">Maloy, Eileen</subfield></datafield><datafield tag="901" ind1=" " ind2=" "><subfield code="c">1234512345</subfield><subfield code="t">authority</subfield></datafield><datafield tag="905" ind1=" " ind2=" "><subfield code="u">' 
        || barcode || '</subfield></datafield></record>'
    FROM actor.card
    WHERE id = CURRVAL('actor.card_id_seq');

-----------------------
-- Import the record --
-----------------------
SELECT ok(
    (
        SELECT vandelay.overlay_authority_record(queued_record, eg_record,
            CURRVAL('vandelay.merge_profile_id_seq')::int )
        FROM vandelay.authority_match
        WHERE queued_record = CURRVAL('vandelay.queued_record_id_seq')
    ),
    'Function call succeeded'
);

---------------------------------
-- Test for new values of editor,
-- edit date, and source
---------------------------------
SELECT is(
    (SELECT editor::bigint FROM authority.record_entry ORDER BY id DESC LIMIT 1),
    CURRVAL('actor.usr_id_seq'),
    'Editor was updated'
);

SELECT is(
    (SELECT edit_date::date FROM authority.record_entry ORDER BY id DESC LIMIT 1),
    CURRENT_DATE,
    'Edit Date was updated'
);

ROLLBACK;

