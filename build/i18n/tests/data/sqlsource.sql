--002.schema.config.sql:
INSERT INTO config.bib_source (id, quality, source, transcendant) VALUES 
    (1, 90, oils_i18n_gettext(1, 'oclc', 'cbs', 'source'), FALSE);
INSERT INTO config.bib_source (id, quality, source, transcendant) VALUES 
    (2, 10, oils_i18n_gettext(2, 'System Local', 'cbs', 'source'), FALSE);
INSERT INTO config.bib_source (id, quality, source, transcendant) VALUES 
    (3, 1, oils_i18n_gettext(3, 'Project Gutenberg', 'cbs', 'source'), TRUE);

INSERT INTO config.standing (id, value) VALUES (1, oils_i18n_gettext(1, 'Good', 'cst', 'value'));
INSERT INTO config.standing (id, value) VALUES (2, oils_i18n_gettext(2, 'Barred', 'cst', 'value'));

INSERT INTO config.metabib_field ( field_class, name, format, xpath ) VALUES 
    ( 'series', 'seriestitle', 'mods32', $$//mods32:mods/mods32:relatedItem[@type="series"]/mods32:titleInfo$$ );
INSERT INTO config.metabib_field ( field_class, name, format, xpath ) VALUES 
    ( 'title', 'abbreviated', 'mods32', $$//mods32:mods/mods32:titleInfo[mods32:title and (@type='abbreviated')]$$ );
INSERT INTO config.metabib_field ( field_class, name, format, xpath ) VALUES 
    ( 'title', 'translated', 'mods32', $$//mods32:mods/mods32:titleInfo[mods32:title and (@type='translated')]$$ );
INSERT INTO config.metabib_field ( field_class, name, format, xpath ) VALUES 
    ( 'title', 'alternative', 'mods32', $$//mods32:mods/mods32:titleInfo[mods32:title and (@type='alternative')]$$ );
INSERT INTO config.metabib_field ( field_class, name, format, xpath ) VALUES 
    ( 'title', 'uniform', 'mods32', $$//mods32:mods/mods32:titleInfo[mods32:title and (@type='uniform')]$$ );
INSERT INTO config.metabib_field ( field_class, name, format, xpath ) VALUES 
    ( 'title', 'proper', 'mods32', $$//mods32:mods/mods32:titleInfo[mods32:title and not (@type)]$$ );
INSERT INTO config.metabib_field ( field_class, name, format, xpath ) VALUES 
    ( 'author', 'corporate', 'mods32', $$//mods32:mods/mods32:name[@type='corporate']/mods32:namePart[../mods32:role/mods32:roleTerm[text()='creator']]$$ );
INSERT INTO config.metabib_field ( field_class, name, format, xpath ) VALUES 
    ( 'author', 'personal', 'mods32', $$//mods32:mods/mods32:name[@type='personal']/mods32:namePart[../mods32:role/mods32:roleTerm[text()='creator']]$$ );
INSERT INTO config.metabib_field ( field_class, name, format, xpath ) VALUES 
    ( 'author', 'conference', 'mods32', $$//mods32:mods/mods32:name[@type='conference']/mods32:namePart[../mods32:role/mods32:roleTerm[text()='creator']]$$ );
INSERT INTO config.metabib_field ( field_class, name, format, xpath ) VALUES 
    ( 'author', 'other', 'mods32', $$//mods32:mods/mods32:name[@type='personal']/mods32:namePart[not(../mods32:role)]$$ );
INSERT INTO config.metabib_field ( field_class, name, format, xpath ) VALUES 
    ( 'subject', 'geographic', 'mods32', $$//mods32:mods/mods32:subject/mods32:geographic$$ );
INSERT INTO config.metabib_field ( field_class, name, format, xpath ) VALUES 
    ( 'subject', 'name', 'mods32', $$//mods32:mods/mods32:subject/mods32:name$$ );
INSERT INTO config.metabib_field ( field_class, name, format, xpath ) VALUES 
    ( 'subject', 'temporal', 'mods32', $$//mods32:mods/mods32:subject/mods32:temporal$$ );
INSERT INTO config.metabib_field ( field_class, name, format, xpath ) VALUES 
    ( 'subject', 'topic', 'mods32', $$//mods32:mods/mods32:subject/mods32:topic$$ );
--INSERT INTO config.metabib_field ( field_class, name, format, xpath ) VALUES 
--  ( field_class, name, xpath ) VALUES ( 'subject', 'genre', 'mods32', $$//mods32:mods/mods32:genre$$ );
INSERT INTO config.metabib_field ( field_class, name, format, xpath ) VALUES 
    ( 'keyword', 'keyword', 'mods32', $$//mods32:mods/*[not(local-name()='originInfo')]$$ ); -- /* to fool vim */;

INSERT INTO config.non_cataloged_type ( id, owning_lib, name ) VALUES ( 1, 1, oils_i18n_gettext(1, 'Paperback Book', 'cnct', 'name') );
SELECT SETVAL('config.non_cataloged_type_id_seq'::TEXT, 100);

INSERT INTO config.identification_type ( id, name ) VALUES 
    ( 1, oils_i18n_gettext(1, 'Drivers License', 'cit', 'name') );
INSERT INTO config.identification_type ( id, name ) VALUES 
    ( 2, oils_i18n_gettext(2, 'SSN', 'cit', 'name') );
INSERT INTO config.identification_type ( id, name ) VALUES 
    ( 3, oils_i18n_gettext(3, 'Other', 'cit', 'name') );
SELECT SETVAL('config.identification_type_id_seq'::TEXT, 100);

INSERT INTO config.rule_circ_duration VALUES 
    (1, oils_i18n_gettext(1, '7_days_0_renew', 'crcd', 'name'), '7 days', '7 days', '7 days', 0);
INSERT INTO config.rule_circ_duration VALUES 
    (2, oils_i18n_gettext(2, '28_days_2_renew', 'crcd', 'name'), '28 days', '28 days', '28 days', 2);
INSERT INTO config.rule_circ_duration VALUES 
    (3, oils_i18n_gettext(3, '3_months_0_renew', 'crcd', 'name'), '3 months', '3 months', '3 months', 0);
INSERT INTO config.rule_circ_duration VALUES 
    (4, oils_i18n_gettext(4, '3_days_1_renew', 'crcd', 'name'), '3 days', '3 days', '3 days', 1);
INSERT INTO config.rule_circ_duration VALUES 
    (5, oils_i18n_gettext(5, '2_months_2_renew', 'crcd', 'name'), '2 months', '2 months', '2 months', 2);
INSERT INTO config.rule_circ_duration VALUES 
    (6, oils_i18n_gettext(6, '35_days_1_renew', 'crcd', 'name'), '35 days', '35 days', '35 days', 1);
INSERT INTO config.rule_circ_duration VALUES 
    (7, oils_i18n_gettext(7, '7_days_2_renew', 'crcd', 'name'), '7 days', '7 days', '7 days', 2);

--040.schema.asset.sql:
INSERT INTO asset.copy_location (id, name,owning_lib) VALUES (1, oils_i18n_gettext(1, 'Stacks', 'acpl', 'name'),1);

-- Vandelay (for importing and exporting records) 012.schema.vandelay.sql 
INSERT INTO vandelay.bib_attr_definition ( id, code, description, xpath ) VALUES (1, 'title', oils_i18n_gettext(1, 'Title of work', 'vqbrad', 'description'),'//*[@tag="245"]/*[contains("abcmnopr",@code)]');
INSERT INTO vandelay.bib_attr_definition ( id, code, description, xpath ) VALUES (2, 'author', oils_i18n_gettext(1, 'Author of work', 'vqbrad', 'description'),'//*[@tag="100" or @tag="110" or @tag="113"]/*[contains("ad",@code)]');
INSERT INTO vandelay.bib_attr_definition ( id, code, description, xpath ) VALUES (3, 'language', oils_i18n_gettext(3, 'Language of work', 'vqbrad', 'description'),'//*[@tag="240"]/*[@code="l"][1]');
INSERT INTO vandelay.bib_attr_definition ( id, code, description, xpath ) VALUES (4, 'pagination', oils_i18n_gettext(4, 'Pagination', 'vqbrad', 'description'),'//*[@tag="300"]/*[@code="a"][1]');

INSERT INTO config.bib_level_map (code, value) VALUES ('b', oils_i18n_gettext('b', 'Serial component part', 'cblvl', 'value'));
INSERT INTO config.bib_level_map (code, value) VALUES ('c', oils_i18n_gettext('c', 'Collection', 'cblvl', 'value'));
INSERT INTO config.bib_level_map (code, value) VALUES ('d', oils_i18n_gettext('d', 'Subunit', 'cblvl', 'value'));
INSERT INTO config.bib_level_map (code, value) VALUES ('i', oils_i18n_gettext('i', 'Integrating resource', 'cblvl', 'value'));
INSERT INTO config.bib_level_map (code, value) VALUES ('m', oils_i18n_gettext('m', 'Monograph/Item', 'cblvl', 'value'));
INSERT INTO config.bib_level_map (code, value) VALUES ('s', oils_i18n_gettext('s', 'Serial', 'cblvl', 'value'));

-- available locales
INSERT INTO config.i18n_locale (code,marc_code,name,description)
    VALUES ('en-US', 'eng', oils_i18n_gettext('en-US', 'English (US)', 'i18n_l', 'name'),
	oils_i18n_gettext('en-US', 'American English', 'i18n_l', 'description'));
INSERT INTO config.i18n_locale (code,marc_code,name,description)
    VALUES ('en-CA', 'eng', oils_i18n_gettext('en-CA', 'English (Canada)', 'i18n_l', 'name'),
	oils_i18n_gettext('en-CA', 'Canadian English', 'i18n_l', 'description'));
INSERT INTO config.i18n_locale (code,marc_code,name,description)
    VALUES ('fr-CA', 'fre', oils_i18n_gettext('fr-CA', 'French (Canada)', 'i18n_l', 'name'),
	oils_i18n_gettext('fr-CA', 'Canadian French', 'i18n_l', 'description'));
INSERT INTO config.i18n_locale (code,marc_code,name,description)
    VALUES ('es-US', 'spa', oils_i18n_gettext('es-US', 'Spanish (US)', 'i18n_l', 'name'),
	oils_i18n_gettext('es-US', 'American Spanish', 'i18n_l', 'description'));

INSERT INTO container.copy_bucket_type (code,label) VALUES ('misc', oils_i18n_gettext('misc', 'Miscellaneous', 'ccpbt', 'label'));
INSERT INTO container.copy_bucket_type (code,label) VALUES ('staff_client', oils_i18n_gettext('staff_client', 'General Staff Client container', 'ccpbt', 'label'));
INSERT INTO container.call_number_bucket_type (code,label) VALUES ('misc', oils_i18n_gettext('misc', 'Miscellaneous', 'ccnbt', 'label'));
INSERT INTO container.biblio_record_entry_bucket_type (code,label) VALUES ('misc', oils_i18n_gettext('misc', 'Miscellaneous', 'cbrebt', 'label'));
INSERT INTO container.biblio_record_entry_bucket_type (code,label) VALUES ('staff_client', oils_i18n_gettext('staff_client', 'General Staff Client container', 'cbrebt', 'label'));
