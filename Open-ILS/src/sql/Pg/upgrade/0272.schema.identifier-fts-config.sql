
-- No transaction, because any or all of these can fail.  Expect errors!

INSERT INTO config.upgrade_log (version) VALUES ('0272'); -- miker

DROP TRIGGER metabib_identifier_field_entry_fti_trigger ON metabib.identifier_field_entry;

-- 8.3 and beyond
CREATE TEXT SEARCH CONFIGURATION identifier ( COPY = title );

-- 8.2 and before
INSERT INTO pg_ts_cfg VALUES ('identifier', 'default','C');
INSERT INTO pg_ts_cfgmap VALUES ('identifier', 'nlword', '{simple}');
INSERT INTO pg_ts_cfgmap VALUES ('identifier', 'word', '{simple}');
INSERT INTO pg_ts_cfgmap VALUES ('identifier', 'email', '{simple}');
INSERT INTO pg_ts_cfgmap VALUES ('identifier', 'url', '{simple}');
INSERT INTO pg_ts_cfgmap VALUES ('identifier', 'host', '{simple}');
INSERT INTO pg_ts_cfgmap VALUES ('identifier', 'sfloat', '{simple}');
INSERT INTO pg_ts_cfgmap VALUES ('identifier', 'version', '{simple}');
INSERT INTO pg_ts_cfgmap VALUES ('identifier', 'part_hword', '{simple}');
INSERT INTO pg_ts_cfgmap VALUES ('identifier', 'nlpart_hword', '{simple}');
INSERT INTO pg_ts_cfgmap VALUES ('identifier', 'hword', '{simple}');
INSERT INTO pg_ts_cfgmap VALUES ('identifier', 'nlhword', '{simple}');
INSERT INTO pg_ts_cfgmap VALUES ('identifier', 'uri', '{simple}');
INSERT INTO pg_ts_cfgmap VALUES ('identifier', 'file', '{simple}');
INSERT INTO pg_ts_cfgmap VALUES ('identifier', 'float', '{simple}');
INSERT INTO pg_ts_cfgmap VALUES ('identifier', 'int', '{simple}');
INSERT INTO pg_ts_cfgmap VALUES ('identifier', 'uint', '{simple}');
INSERT INTO pg_ts_cfgmap VALUES ('identifier', 'lword', '{en_stem_nostop}');
INSERT INTO pg_ts_cfgmap VALUES ('identifier', 'lpart_hword', '{en_stem_nostop}');
INSERT INTO pg_ts_cfgmap VALUES ('identifier', 'lhword', '{en_stem_nostop}');


CREATE TRIGGER metabib_identifier_field_entry_fti_trigger
    BEFORE UPDATE OR INSERT ON metabib.identifier_field_entry
    FOR EACH ROW EXECUTE PROCEDURE oils_tsearch2('identifier');

