BEGIN;

INSERT INTO config.upgrade_log (version) VALUES ('0363'); -- miker

INSERT INTO config.metabib_field ( id, field_class, name, label, format, xpath ) VALUES
    (26, 'identifier', 'tcn', oils_i18n_gettext(26, 'Title Control Number', 'cmf', 'label'), 'marcxml', $$//marc:datafield[@tag='901']/marc:subfield[@code='a']$$ );
INSERT INTO config.metabib_field ( id, field_class, name, label, format, xpath ) VALUES
    (27, 'identifier', 'bibid', oils_i18n_gettext(27, 'Internal ID', 'cmf', 'label'), 'marcxml', $$//marc:datafield[@tag='901']/marc:subfield[@code='c']$$ );
INSERT INTO config.metabib_search_alias (alias,field_class,field) VALUES ('eg.tcn','identifier', 26);
INSERT INTO config.metabib_search_alias (alias,field_class,field) VALUES ('eg.bibid','identifier', 27);

COMMIT;

