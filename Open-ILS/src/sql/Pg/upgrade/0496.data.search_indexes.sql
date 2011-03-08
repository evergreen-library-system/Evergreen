BEGIN;

INSERT INTO config.upgrade_log (version) VALUES ('0496'); -- dbs

UPDATE config.metabib_field
    SET xpath = $$//marc:datafield[@tag='024' and @ind1='1']/marc:subfield[@code='a' or @code='z']$$
    WHERE field_class = 'identifier' AND name = 'upc';

UPDATE config.metabib_field
    SET xpath = $$//marc:datafield[@tag='024' and @ind1='2']/marc:subfield[@code='a' or @code='z']$$
    WHERE field_class = 'identifier' AND name = 'ismn';

UPDATE config.metabib_field
    SET xpath = $$//marc:datafield[@tag='024' and @ind1='3']/marc:subfield[@code='a' or @code='z']$$
    WHERE field_class = 'identifier' AND name = 'ean';

UPDATE config.metabib_field
    SET xpath = $$//marc:datafield[@tag='024' and @ind1='0']/marc:subfield[@code='a' or @code='z']$$
    WHERE field_class = 'identifier' AND name = 'isrc';

UPDATE config.metabib_field
    SET xpath = $$//marc:datafield[@tag='024' and @ind1='4']/marc:subfield[@code='a' or @code='z']$$
    WHERE field_class = 'identifier' AND name = 'sici';

COMMIT;
