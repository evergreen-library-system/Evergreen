--002.schema.config.sql:
INSERT INTO config.bib_source (quality, source, transcendant) VALUES 
    (90, oils_i18n_gettext('oclc'), FALSE);
INSERT INTO config.bib_source (quality, source, transcendant) VALUES 
    (10, oils_i18n_gettext('System Local'), FALSE);
INSERT INTO config.bib_source (quality, source, transcendant) VALUES 
    (1, oils_i18n_gettext('Project Gutenberg'), TRUE);

INSERT INTO config.standing (value) VALUES (oils_i18n_gettext('Good'));
INSERT INTO config.standing (value) VALUES (oils_i18n_gettext('Barred'));

INSERT INTO config.metabib_field ( field_class, name, xpath ) VALUES 
    ( 'series', 'seriestitle', $$//mods:mods/mods:relatedItem[@type="series"]/mods:titleInfo$$ );
INSERT INTO config.metabib_field ( field_class, name, xpath ) VALUES 
    ( 'title', 'abbreviated', $$//mods:mods/mods:titleInfo[mods:title and (@type='abbreviated')]$$ );
INSERT INTO config.metabib_field ( field_class, name, xpath ) VALUES 
    ( 'title', 'translated', $$//mods:mods/mods:titleInfo[mods:title and (@type='translated')]$$ );
INSERT INTO config.metabib_field ( field_class, name, xpath ) VALUES 
    ( 'title', 'uniform', $$//mods:mods/mods:titleInfo[mods:title and (@type='uniform')]$$ );
INSERT INTO config.metabib_field ( field_class, name, xpath ) VALUES 
    ( 'title', 'proper', $$//mods:mods/mods:titleInfo[mods:title and not (@type)]$$ );
INSERT INTO config.metabib_field ( field_class, name, xpath ) VALUES 
    ( 'author', 'corporate', $$//mods:mods/mods:name[@type='corporate']/mods:namePart[../mods:role/mods:text[text()='creator']]$$ );
INSERT INTO config.metabib_field ( field_class, name, xpath ) VALUES 
    ( 'author', 'personal', $$//mods:mods/mods:name[@type='personal']/mods:namePart[../mods:role/mods:text[text()='creator']]$$ );
INSERT INTO config.metabib_field ( field_class, name, xpath ) VALUES 
    ( 'author', 'conference', $$//mods:mods/mods:name[@type='conference']/mods:namePart[../mods:role/mods:text[text()='creator']]$$ );
INSERT INTO config.metabib_field ( field_class, name, xpath ) VALUES 
    ( 'author', 'other', $$//mods:mods/mods:name[@type='personal']/mods:namePart[not(../mods:role)]$$ );
INSERT INTO config.metabib_field ( field_class, name, xpath ) VALUES 
    ( 'subject', 'geographic', $$//mods:mods/mods:subject/mods:geographic$$ );
INSERT INTO config.metabib_field ( field_class, name, xpath ) VALUES 
    ( 'subject', 'name', $$//mods:mods/mods:subject/mods:name$$ );
INSERT INTO config.metabib_field ( field_class, name, xpath ) VALUES 
    ( 'subject', 'temporal', $$//mods:mods/mods:subject/mods:temporal$$ );
INSERT INTO config.metabib_field ( field_class, name, xpath ) VALUES 
    ( 'subject', 'topic', $$//mods:mods/mods:subject/mods:topic$$ );
--INSERT INTO config.metabib_field ( field_class, name, xpath ) VALUES 
--  ( field_class, name, xpath ) VALUES ( 'subject', 'genre', $$//mods:mods/mods:genre$$ );
INSERT INTO config.metabib_field ( field_class, name, xpath ) VALUES 
    ( 'keyword', 'keyword', $$//mods:mods/*[not(local-name()='originInfo')]$$ ); -- /* to fool vim */;

INSERT INTO config.non_cataloged_type ( owning_lib, name ) VALUES ( 1, oils_i18n_gettext('Paperback Book') );

INSERT INTO config.identification_type ( name ) VALUES 
    ( oils_i18n_gettext('Drivers License') );
INSERT INTO config.identification_type ( name ) VALUES 
    ( oils_i18n_gettext('SSN') );
INSERT INTO config.identification_type ( name ) VALUES 
    ( oils_i18n_gettext('Other') );

INSERT INTO config.rule_circ_duration VALUES 
    (DEFAULT, oils_i18n_gettext('7_days_0_renew'), '7 days', '7 days', '7 days', 0);
INSERT INTO config.rule_circ_duration VALUES 
    (DEFAULT, oils_i18n_gettext('28_days_2_renew'), '28 days', '28 days', '28 days', 2);
INSERT INTO config.rule_circ_duration VALUES 
    (DEFAULT, oils_i18n_gettext('3_months_0_renew'), '3 months', '3 months', '3 months', 0);
INSERT INTO config.rule_circ_duration VALUES 
    (DEFAULT, oils_i18n_gettext('3_days_1_renew'), '3 days', '3 days', '3 days', 1);
INSERT INTO config.rule_circ_duration VALUES 
    (DEFAULT, oils_i18n_gettext('2_months_2_renew'), '2 months', '2 months', '2 months', 2);
INSERT INTO config.rule_circ_duration VALUES 
    (DEFAULT, oils_i18n_gettext('35_days_1_renew'), '35 days', '35 days', '35 days', 1);
INSERT INTO config.rule_circ_duration VALUES 
    (DEFAULT, oils_i18n_gettext('7_days_2_renew'), '7 days', '7 days', '7 days', 2);
INSERT INTO config.rule_circ_duration VALUES 
    (DEFAULT, oils_i18n_gettext('1_hour_2_renew'), '1 hour', '1 hour', '1 hour', 2);
INSERT INTO config.rule_circ_duration VALUES 
    (DEFAULT, oils_i18n_gettext('28_days_0_renew'), '28 days', '28 days', '28 days', 0);
INSERT INTO config.rule_circ_duration VALUES 
    (DEFAULT, oils_i18n_gettext('14_days_2_renew'), '14 days', '14 days', '14 days', 2);
INSERT INTO config.rule_circ_duration VALUES 
    (DEFAULT, oils_i18n_gettext('default'), '21 days', '14 days', '7 days', 2);

INSERT INTO config.rule_max_fine VALUES 
    (DEFAULT, oils_i18n_gettext('default'), 5.00);
INSERT INTO config.rule_max_fine VALUES 
    (DEFAULT, oils_i18n_gettext('overdue_min'), 5.00);
INSERT INTO config.rule_max_fine VALUES 
    (DEFAULT, oils_i18n_gettext('overdue_mid'), 10.00);
INSERT INTO config.rule_max_fine VALUES 
    (DEFAULT, oils_i18n_gettext('overdue_max'), 100.00);
INSERT INTO config.rule_max_fine VALUES 
    (DEFAULT, oils_i18n_gettext('overdue_equip_min'), 25.00);
INSERT INTO config.rule_max_fine VALUES 
    (DEFAULT, oils_i18n_gettext('overdue_equip_mid'), 25.00);
INSERT INTO config.rule_max_fine VALUES 
    (DEFAULT, oils_i18n_gettext('overdue_equip_max'), 100.00);

INSERT INTO config.rule_recuring_fine VALUES 
    (DEFAULT, oils_i18n_gettext('default'), 0.50, 0.10, 0.05, '1 day');
INSERT INTO config.rule_recuring_fine VALUES 
    (DEFAULT, oils_i18n_gettext('10_cent_per_day'), 0.50, 0.10, 0.10, '1 day');
INSERT INTO config.rule_recuring_fine VALUES 
    (DEFAULT, oils_i18n_gettext('50_cent_per_day'), 0.50, 0.50, 0.50, '1 day');

INSERT INTO config.rule_age_hold_protect VALUES (DEFAULT, oils_i18n_gettext('3month'), '3 months', 0);
INSERT INTO config.rule_age_hold_protect VALUES (DEFAULT, oils_i18n_gettext('6month'), '6 months', 2);

INSERT INTO config.copy_status (id,name,holdable,opac_visible)		VALUES (0,oils_i18n_gettext('Available'),'t','t');

INSERT INTO config.copy_status (id,name,holdable,opac_visible)		VALUES (1,oils_i18n_gettext('Checked out'),'t','t');

INSERT INTO config.copy_status (id,name)			VALUES (2,oils_i18n_gettext('Bindery'));
INSERT INTO config.copy_status (id,name)			VALUES (3,oils_i18n_gettext('Lost'));
INSERT INTO config.copy_status (id,name)			VALUES (4,oils_i18n_gettext('Missing'));

INSERT INTO config.copy_status (id,name,holdable,opac_visible)		VALUES (5,oils_i18n_gettext('In process'),'t','t');
INSERT INTO config.copy_status (id,name,holdable,opac_visible)		VALUES (6,oils_i18n_gettext('In transit'),'t','t');
INSERT INTO config.copy_status (id,name,holdable,opac_visible)		VALUES (7,oils_i18n_gettext('Reshelving'),'t','t');
INSERT INTO config.copy_status (id,name,holdable,opac_visible)		VALUES (8,oils_i18n_gettext('On holds shelf'),'t','t');
INSERT INTO config.copy_status (id,name,holdable,opac_visible)		VALUES (9,oils_i18n_gettext('On order'),'t','t');

INSERT INTO config.copy_status (id,name)			VALUES (10,oils_i18n_gettext('ILL'));
INSERT INTO config.copy_status (id,name)			VALUES (11,oils_i18n_gettext('Cataloging'));
INSERT INTO config.copy_status (id,name,opac_visible)			VALUES (12,oils_i18n_gettext('Reserves'),'t');
INSERT INTO config.copy_status (id,name)			VALUES (13,oils_i18n_gettext('Discard/Weed'));
INSERT INTO config.copy_status (id,name)			VALUES (14,oils_i18n_gettext('Damaged'));

SELECT SETVAL('config.copy_status_id_seq'::TEXT, 100);

INSERT INTO config.net_access_level (name) VALUES 
    (oils_i18n_gettext('Filtered'));
INSERT INTO config.net_access_level (name) VALUES 
    (oils_i18n_gettext('Unfiltered'));
INSERT INTO config.net_access_level (name) VALUES 
    (oils_i18n_gettext('No Access'));

INSERT INTO config.audience_map (code, value, description) VALUES 
    ('', oils_i18n_gettext('Unknown or unspecified'), oils_i18n_gettext('The target audience for the item not known or not specified.'));
INSERT INTO config.audience_map (code, value, description) VALUES 
    ('a', oils_i18n_gettext('Preschool'), oils_i18n_gettext('The item is intended for children, approximate ages 0-5 years.'));
INSERT INTO config.audience_map (code, value, description) VALUES 
    ('b', oils_i18n_gettext('Primary'), oils_i18n_gettext('The item is intended for children, approximate ages 6-8 years.'));
INSERT INTO config.audience_map (code, value, description) VALUES 
    ('c', oils_i18n_gettext('Pre-adolescent'), oils_i18n_gettext('The item is intended for young people, approximate ages 9-13 years.'));
INSERT INTO config.audience_map (code, value, description) VALUES 
    ('d', oils_i18n_gettext('Adolescent'), oils_i18n_gettext('The item is intended for young people, approximate ages 14-17 years.'));
INSERT INTO config.audience_map (code, value, description) VALUES 
    ('e', oils_i18n_gettext('Adult'), oils_i18n_gettext('The item is intended for adults.'));
INSERT INTO config.audience_map (code, value, description) VALUES 
    ('f', oils_i18n_gettext('Specialized'), oils_i18n_gettext('The item is aimed at a particular audience and the nature of the presentation makes the item of little interest to another audience.'));
INSERT INTO config.audience_map (code, value, description) VALUES 
    ('g', oils_i18n_gettext('General'), oils_i18n_gettext('The item is of general interest and not aimed at an audience of a particular intellectual level.'));
INSERT INTO config.audience_map (code, value, description) VALUES 
    ('j', oils_i18n_gettext('Juvenile'), oils_i18n_gettext('The item is intended for children and young people, approximate ages 0-15 years.'));

INSERT INTO config.lit_form_map (code, value, description) VALUES 
    ('0', oils_i18n_gettext('Not fiction (not further specified)'), oils_i18n_gettext('The item is not a work of fiction and no further identification of the literary form is desired'));
INSERT INTO config.lit_form_map (code, value, description) VALUES 
    ('1', oils_i18n_gettext('Fiction (not further specified)'), oils_i18n_gettext('The item is a work of fiction and no further identification of the literary form is desired'));
INSERT INTO config.lit_form_map (code, value, description) VALUES 
    ('c', oils_i18n_gettext('Comic strips'), NULL);
INSERT INTO config.lit_form_map (code, value, description) VALUES 
    ('d', oils_i18n_gettext('Dramas'), NULL);
INSERT INTO config.lit_form_map (code, value, description) VALUES 
    ('e', oils_i18n_gettext('Essays'), NULL);
INSERT INTO config.lit_form_map (code, value, description) VALUES 
    ('f', oils_i18n_gettext('Novels'), NULL);
INSERT INTO config.lit_form_map (code, value, description) VALUES 
    ('h', oils_i18n_gettext('Humor, satires, etc.'), oils_i18n_gettext('The item is a humorous work, satire or of similar literary form.'));
INSERT INTO config.lit_form_map (code, value, description) VALUES 
    ('i', oils_i18n_gettext('Letters'), oils_i18n_gettext('The item is a single letter or collection of correspondence.'));
INSERT INTO config.lit_form_map (code, value, description) VALUES 
    ('j', oils_i18n_gettext('Short stories'), oils_i18n_gettext('The item is a short story or collection of short stories.'));
INSERT INTO config.lit_form_map (code, value, description) VALUES 
    ('m', oils_i18n_gettext('Mixed forms'), oils_i18n_gettext('The item is a variety of literary forms (e.g., poetry and short stories).'));
INSERT INTO config.lit_form_map (code, value, description) VALUES 
    ('p', oils_i18n_gettext('Poetry'), oils_i18n_gettext('The item is a poem or collection of poems.'));
INSERT INTO config.lit_form_map (code, value, description) VALUES 
    ('s', oils_i18n_gettext('Speeches'), oils_i18n_gettext('The item is a speech or collection of speeches.'));
INSERT INTO config.lit_form_map (code, value, description) VALUES 
    ('u', oils_i18n_gettext('Unknown'), oils_i18n_gettext('The literary form of the item is unknown.'));

-- TO-DO: Auto-generate these values from CLDR
INSERT INTO config.language_map (code, value) VALUES ('aar', oils_i18n_gettext('Afar'));
INSERT INTO config.language_map (code, value) VALUES ('abk', oils_i18n_gettext('Abkhaz'));
INSERT INTO config.language_map (code, value) VALUES ('ace', oils_i18n_gettext('Achinese'));
INSERT INTO config.language_map (code, value) VALUES ('ach', oils_i18n_gettext('Acoli'));
INSERT INTO config.language_map (code, value) VALUES ('ada', oils_i18n_gettext('Adangme'));
INSERT INTO config.language_map (code, value) VALUES ('ady', oils_i18n_gettext('Adygei'));
INSERT INTO config.language_map (code, value) VALUES ('afa', oils_i18n_gettext('Afroasiatic (Other)'));
INSERT INTO config.language_map (code, value) VALUES ('afh', oils_i18n_gettext('Afrihili (Artificial language)'));
INSERT INTO config.language_map (code, value) VALUES ('afr', oils_i18n_gettext('Afrikaans'));
INSERT INTO config.language_map (code, value) VALUES ('-ajm', oils_i18n_gettext('Aljamía'));
INSERT INTO config.language_map (code, value) VALUES ('aka', oils_i18n_gettext('Akan'));
INSERT INTO config.language_map (code, value) VALUES ('akk', oils_i18n_gettext('Akkadian'));
INSERT INTO config.language_map (code, value) VALUES ('alb', oils_i18n_gettext('Albanian'));
INSERT INTO config.language_map (code, value) VALUES ('ale', oils_i18n_gettext('Aleut'));
INSERT INTO config.language_map (code, value) VALUES ('alg', oils_i18n_gettext('Algonquian (Other)'));
INSERT INTO config.language_map (code, value) VALUES ('amh', oils_i18n_gettext('Amharic'));
INSERT INTO config.language_map (code, value) VALUES ('ang', oils_i18n_gettext('English, Old (ca. 450-1100)'));
INSERT INTO config.language_map (code, value) VALUES ('apa', oils_i18n_gettext('Apache languages'));
INSERT INTO config.language_map (code, value) VALUES ('ara', oils_i18n_gettext('Arabic'));
INSERT INTO config.language_map (code, value) VALUES ('arc', oils_i18n_gettext('Aramaic'));
INSERT INTO config.language_map (code, value) VALUES ('arg', oils_i18n_gettext('Aragonese Spanish'));
INSERT INTO config.language_map (code, value) VALUES ('arm', oils_i18n_gettext('Armenian'));
INSERT INTO config.language_map (code, value) VALUES ('arn', oils_i18n_gettext('Mapuche'));
INSERT INTO config.language_map (code, value) VALUES ('arp', oils_i18n_gettext('Arapaho'));
INSERT INTO config.language_map (code, value) VALUES ('art', oils_i18n_gettext('Artificial (Other)'));
INSERT INTO config.language_map (code, value) VALUES ('arw', oils_i18n_gettext('Arawak'));
INSERT INTO config.language_map (code, value) VALUES ('asm', oils_i18n_gettext('Assamese'));
INSERT INTO config.language_map (code, value) VALUES ('ast', oils_i18n_gettext('Bable'));
INSERT INTO config.language_map (code, value) VALUES ('ath', oils_i18n_gettext('Athapascan (Other)'));
INSERT INTO config.language_map (code, value) VALUES ('aus', oils_i18n_gettext('Australian languages'));
INSERT INTO config.language_map (code, value) VALUES ('ava', oils_i18n_gettext('Avaric'));
INSERT INTO config.language_map (code, value) VALUES ('ave', oils_i18n_gettext('Avestan'));
INSERT INTO config.language_map (code, value) VALUES ('awa', oils_i18n_gettext('Awadhi'));
INSERT INTO config.language_map (code, value) VALUES ('aym', oils_i18n_gettext('Aymara'));
INSERT INTO config.language_map (code, value) VALUES ('aze', oils_i18n_gettext('Azerbaijani'));
INSERT INTO config.language_map (code, value) VALUES ('bad', oils_i18n_gettext('Banda'));
INSERT INTO config.language_map (code, value) VALUES ('bai', oils_i18n_gettext('Bamileke languages'));
INSERT INTO config.language_map (code, value) VALUES ('bak', oils_i18n_gettext('Bashkir'));
INSERT INTO config.language_map (code, value) VALUES ('bal', oils_i18n_gettext('Baluchi'));
INSERT INTO config.language_map (code, value) VALUES ('bam', oils_i18n_gettext('Bambara'));
INSERT INTO config.language_map (code, value) VALUES ('ban', oils_i18n_gettext('Balinese'));
INSERT INTO config.language_map (code, value) VALUES ('baq', oils_i18n_gettext('Basque'));
INSERT INTO config.language_map (code, value) VALUES ('bas', oils_i18n_gettext('Basa'));
INSERT INTO config.language_map (code, value) VALUES ('bat', oils_i18n_gettext('Baltic (Other)'));
INSERT INTO config.language_map (code, value) VALUES ('bej', oils_i18n_gettext('Beja'));
INSERT INTO config.language_map (code, value) VALUES ('bel', oils_i18n_gettext('Belarusian'));
INSERT INTO config.language_map (code, value) VALUES ('bem', oils_i18n_gettext('Bemba'));
INSERT INTO config.language_map (code, value) VALUES ('ben', oils_i18n_gettext('Bengali'));
INSERT INTO config.language_map (code, value) VALUES ('ber', oils_i18n_gettext('Berber (Other)'));
INSERT INTO config.language_map (code, value) VALUES ('bho', oils_i18n_gettext('Bhojpuri'));
INSERT INTO config.language_map (code, value) VALUES ('bih', oils_i18n_gettext('Bihari'));
INSERT INTO config.language_map (code, value) VALUES ('bik', oils_i18n_gettext('Bikol'));
INSERT INTO config.language_map (code, value) VALUES ('bin', oils_i18n_gettext('Edo'));
INSERT INTO config.language_map (code, value) VALUES ('bis', oils_i18n_gettext('Bislama'));
INSERT INTO config.language_map (code, value) VALUES ('bla', oils_i18n_gettext('Siksika'));
INSERT INTO config.language_map (code, value) VALUES ('bnt', oils_i18n_gettext('Bantu (Other)'));
INSERT INTO config.language_map (code, value) VALUES ('bos', oils_i18n_gettext('Bosnian'));
INSERT INTO config.language_map (code, value) VALUES ('bra', oils_i18n_gettext('Braj'));
INSERT INTO config.language_map (code, value) VALUES ('bre', oils_i18n_gettext('Breton'));
INSERT INTO config.language_map (code, value) VALUES ('btk', oils_i18n_gettext('Batak'));
INSERT INTO config.language_map (code, value) VALUES ('bua', oils_i18n_gettext('Buriat'));
INSERT INTO config.language_map (code, value) VALUES ('bug', oils_i18n_gettext('Bugis'));
INSERT INTO config.language_map (code, value) VALUES ('bul', oils_i18n_gettext('Bulgarian'));
INSERT INTO config.language_map (code, value) VALUES ('bur', oils_i18n_gettext('Burmese'));
INSERT INTO config.language_map (code, value) VALUES ('cad', oils_i18n_gettext('Caddo'));
INSERT INTO config.language_map (code, value) VALUES ('cai', oils_i18n_gettext('Central American Indian (Other)'));
INSERT INTO config.language_map (code, value) VALUES ('-cam', oils_i18n_gettext('Khmer'));
INSERT INTO config.language_map (code, value) VALUES ('car', oils_i18n_gettext('Carib'));
INSERT INTO config.language_map (code, value) VALUES ('cat', oils_i18n_gettext('Catalan'));
INSERT INTO config.language_map (code, value) VALUES ('cau', oils_i18n_gettext('Caucasian (Other)'));
INSERT INTO config.language_map (code, value) VALUES ('ceb', oils_i18n_gettext('Cebuano'));
INSERT INTO config.language_map (code, value) VALUES ('cel', oils_i18n_gettext('Celtic (Other)'));
INSERT INTO config.language_map (code, value) VALUES ('cha', oils_i18n_gettext('Chamorro'));
INSERT INTO config.language_map (code, value) VALUES ('chb', oils_i18n_gettext('Chibcha'));
INSERT INTO config.language_map (code, value) VALUES ('che', oils_i18n_gettext('Chechen'));
INSERT INTO config.language_map (code, value) VALUES ('chg', oils_i18n_gettext('Chagatai'));
INSERT INTO config.language_map (code, value) VALUES ('chi', oils_i18n_gettext('Chinese'));
INSERT INTO config.language_map (code, value) VALUES ('chk', oils_i18n_gettext('Truk'));
INSERT INTO config.language_map (code, value) VALUES ('chm', oils_i18n_gettext('Mari'));
INSERT INTO config.language_map (code, value) VALUES ('chn', oils_i18n_gettext('Chinook jargon'));
INSERT INTO config.language_map (code, value) VALUES ('cho', oils_i18n_gettext('Choctaw'));
INSERT INTO config.language_map (code, value) VALUES ('chp', oils_i18n_gettext('Chipewyan'));
INSERT INTO config.language_map (code, value) VALUES ('chr', oils_i18n_gettext('Cherokee'));
INSERT INTO config.language_map (code, value) VALUES ('chu', oils_i18n_gettext('Church Slavic'));
INSERT INTO config.language_map (code, value) VALUES ('chv', oils_i18n_gettext('Chuvash'));
INSERT INTO config.language_map (code, value) VALUES ('chy', oils_i18n_gettext('Cheyenne'));
INSERT INTO config.language_map (code, value) VALUES ('cmc', oils_i18n_gettext('Chamic languages'));
INSERT INTO config.language_map (code, value) VALUES ('cop', oils_i18n_gettext('Coptic'));
INSERT INTO config.language_map (code, value) VALUES ('cor', oils_i18n_gettext('Cornish'));
INSERT INTO config.language_map (code, value) VALUES ('cos', oils_i18n_gettext('Corsican'));
INSERT INTO config.language_map (code, value) VALUES ('cpe', oils_i18n_gettext('Creoles and Pidgins, English-based (Other)'));
INSERT INTO config.language_map (code, value) VALUES ('cpf', oils_i18n_gettext('Creoles and Pidgins, French-based (Other)'));
INSERT INTO config.language_map (code, value) VALUES ('cpp', oils_i18n_gettext('Creoles and Pidgins, Portuguese-based (Other)'));
INSERT INTO config.language_map (code, value) VALUES ('cre', oils_i18n_gettext('Cree'));
INSERT INTO config.language_map (code, value) VALUES ('crh', oils_i18n_gettext('Crimean Tatar'));
INSERT INTO config.language_map (code, value) VALUES ('crp', oils_i18n_gettext('Creoles and Pidgins (Other)'));
INSERT INTO config.language_map (code, value) VALUES ('cus', oils_i18n_gettext('Cushitic (Other)'));
INSERT INTO config.language_map (code, value) VALUES ('cze', oils_i18n_gettext('Czech'));
INSERT INTO config.language_map (code, value) VALUES ('dak', oils_i18n_gettext('Dakota'));
INSERT INTO config.language_map (code, value) VALUES ('dan', oils_i18n_gettext('Danish'));
INSERT INTO config.language_map (code, value) VALUES ('dar', oils_i18n_gettext('Dargwa'));
INSERT INTO config.language_map (code, value) VALUES ('day', oils_i18n_gettext('Dayak'));
INSERT INTO config.language_map (code, value) VALUES ('del', oils_i18n_gettext('Delaware'));
INSERT INTO config.language_map (code, value) VALUES ('den', oils_i18n_gettext('Slave'));
INSERT INTO config.language_map (code, value) VALUES ('dgr', oils_i18n_gettext('Dogrib'));
INSERT INTO config.language_map (code, value) VALUES ('din', oils_i18n_gettext('Dinka'));
INSERT INTO config.language_map (code, value) VALUES ('div', oils_i18n_gettext('Divehi'));
INSERT INTO config.language_map (code, value) VALUES ('doi', oils_i18n_gettext('Dogri'));
INSERT INTO config.language_map (code, value) VALUES ('dra', oils_i18n_gettext('Dravidian (Other)'));
INSERT INTO config.language_map (code, value) VALUES ('dua', oils_i18n_gettext('Duala'));
INSERT INTO config.language_map (code, value) VALUES ('dum', oils_i18n_gettext('Dutch, Middle (ca. 1050-1350)'));
INSERT INTO config.language_map (code, value) VALUES ('dut', oils_i18n_gettext('Dutch'));
INSERT INTO config.language_map (code, value) VALUES ('dyu', oils_i18n_gettext('Dyula'));
INSERT INTO config.language_map (code, value) VALUES ('dzo', oils_i18n_gettext('Dzongkha'));
INSERT INTO config.language_map (code, value) VALUES ('efi', oils_i18n_gettext('Efik'));
INSERT INTO config.language_map (code, value) VALUES ('egy', oils_i18n_gettext('Egyptian'));
INSERT INTO config.language_map (code, value) VALUES ('eka', oils_i18n_gettext('Ekajuk'));
INSERT INTO config.language_map (code, value) VALUES ('elx', oils_i18n_gettext('Elamite'));
INSERT INTO config.language_map (code, value) VALUES ('eng', oils_i18n_gettext('English'));
INSERT INTO config.language_map (code, value) VALUES ('enm', oils_i18n_gettext('English, Middle (1100-1500)'));
INSERT INTO config.language_map (code, value) VALUES ('epo', oils_i18n_gettext('Esperanto'));
INSERT INTO config.language_map (code, value) VALUES ('-esk', oils_i18n_gettext('Eskimo languages'));
INSERT INTO config.language_map (code, value) VALUES ('-esp', oils_i18n_gettext('Esperanto'));
INSERT INTO config.language_map (code, value) VALUES ('est', oils_i18n_gettext('Estonian'));
INSERT INTO config.language_map (code, value) VALUES ('-eth', oils_i18n_gettext('Ethiopic'));
INSERT INTO config.language_map (code, value) VALUES ('ewe', oils_i18n_gettext('Ewe'));
INSERT INTO config.language_map (code, value) VALUES ('ewo', oils_i18n_gettext('Ewondo'));
INSERT INTO config.language_map (code, value) VALUES ('fan', oils_i18n_gettext('Fang'));
INSERT INTO config.language_map (code, value) VALUES ('fao', oils_i18n_gettext('Faroese'));
INSERT INTO config.language_map (code, value) VALUES ('-far', oils_i18n_gettext('Faroese'));
INSERT INTO config.language_map (code, value) VALUES ('fat', oils_i18n_gettext('Fanti'));
INSERT INTO config.language_map (code, value) VALUES ('fij', oils_i18n_gettext('Fijian'));
INSERT INTO config.language_map (code, value) VALUES ('fin', oils_i18n_gettext('Finnish'));
INSERT INTO config.language_map (code, value) VALUES ('fiu', oils_i18n_gettext('Finno-Ugrian (Other)'));
INSERT INTO config.language_map (code, value) VALUES ('fon', oils_i18n_gettext('Fon'));
INSERT INTO config.language_map (code, value) VALUES ('fre', oils_i18n_gettext('French'));
INSERT INTO config.language_map (code, value) VALUES ('-fri', oils_i18n_gettext('Frisian'));
INSERT INTO config.language_map (code, value) VALUES ('frm', oils_i18n_gettext('French, Middle (ca. 1400-1600)'));
INSERT INTO config.language_map (code, value) VALUES ('fro', oils_i18n_gettext('French, Old (ca. 842-1400)'));
INSERT INTO config.language_map (code, value) VALUES ('fry', oils_i18n_gettext('Frisian'));
INSERT INTO config.language_map (code, value) VALUES ('ful', oils_i18n_gettext('Fula'));
INSERT INTO config.language_map (code, value) VALUES ('fur', oils_i18n_gettext('Friulian'));
INSERT INTO config.language_map (code, value) VALUES ('gaa', oils_i18n_gettext('Gã'));
INSERT INTO config.language_map (code, value) VALUES ('-gae', oils_i18n_gettext('Scottish Gaelic'));
INSERT INTO config.language_map (code, value) VALUES ('-gag', oils_i18n_gettext('Galician'));
INSERT INTO config.language_map (code, value) VALUES ('-gal', oils_i18n_gettext('Oromo'));
INSERT INTO config.language_map (code, value) VALUES ('gay', oils_i18n_gettext('Gayo'));
INSERT INTO config.language_map (code, value) VALUES ('gba', oils_i18n_gettext('Gbaya'));
INSERT INTO config.language_map (code, value) VALUES ('gem', oils_i18n_gettext('Germanic (Other)'));
INSERT INTO config.language_map (code, value) VALUES ('geo', oils_i18n_gettext('Georgian'));
INSERT INTO config.language_map (code, value) VALUES ('ger', oils_i18n_gettext('German'));
INSERT INTO config.language_map (code, value) VALUES ('gez', oils_i18n_gettext('Ethiopic'));
INSERT INTO config.language_map (code, value) VALUES ('gil', oils_i18n_gettext('Gilbertese'));
INSERT INTO config.language_map (code, value) VALUES ('gla', oils_i18n_gettext('Scottish Gaelic'));
INSERT INTO config.language_map (code, value) VALUES ('gle', oils_i18n_gettext('Irish'));
INSERT INTO config.language_map (code, value) VALUES ('glg', oils_i18n_gettext('Galician'));
INSERT INTO config.language_map (code, value) VALUES ('glv', oils_i18n_gettext('Manx'));
INSERT INTO config.language_map (code, value) VALUES ('gmh', oils_i18n_gettext('German, Middle High (ca. 1050-1500)'));
INSERT INTO config.language_map (code, value) VALUES ('goh', oils_i18n_gettext('German, Old High (ca. 750-1050)'));
INSERT INTO config.language_map (code, value) VALUES ('gon', oils_i18n_gettext('Gondi'));
INSERT INTO config.language_map (code, value) VALUES ('gor', oils_i18n_gettext('Gorontalo'));
INSERT INTO config.language_map (code, value) VALUES ('got', oils_i18n_gettext('Gothic'));
INSERT INTO config.language_map (code, value) VALUES ('grb', oils_i18n_gettext('Grebo'));
INSERT INTO config.language_map (code, value) VALUES ('grc', oils_i18n_gettext('Greek, Ancient (to 1453)'));
INSERT INTO config.language_map (code, value) VALUES ('gre', oils_i18n_gettext('Greek, Modern (1453- )'));
INSERT INTO config.language_map (code, value) VALUES ('grn', oils_i18n_gettext('Guarani'));
INSERT INTO config.language_map (code, value) VALUES ('-gua', oils_i18n_gettext('Guarani'));
INSERT INTO config.language_map (code, value) VALUES ('guj', oils_i18n_gettext('Gujarati'));
INSERT INTO config.language_map (code, value) VALUES ('gwi', oils_i18n_gettext('Gwich''in'));
INSERT INTO config.language_map (code, value) VALUES ('hai', oils_i18n_gettext('Haida'));
INSERT INTO config.language_map (code, value) VALUES ('hat', oils_i18n_gettext('Haitian French Creole'));
INSERT INTO config.language_map (code, value) VALUES ('hau', oils_i18n_gettext('Hausa'));
INSERT INTO config.language_map (code, value) VALUES ('haw', oils_i18n_gettext('Hawaiian'));
INSERT INTO config.language_map (code, value) VALUES ('heb', oils_i18n_gettext('Hebrew'));
INSERT INTO config.language_map (code, value) VALUES ('her', oils_i18n_gettext('Herero'));
INSERT INTO config.language_map (code, value) VALUES ('hil', oils_i18n_gettext('Hiligaynon'));
INSERT INTO config.language_map (code, value) VALUES ('him', oils_i18n_gettext('Himachali'));
INSERT INTO config.language_map (code, value) VALUES ('hin', oils_i18n_gettext('Hindi'));
INSERT INTO config.language_map (code, value) VALUES ('hit', oils_i18n_gettext('Hittite'));
INSERT INTO config.language_map (code, value) VALUES ('hmn', oils_i18n_gettext('Hmong'));
INSERT INTO config.language_map (code, value) VALUES ('hmo', oils_i18n_gettext('Hiri Motu'));
INSERT INTO config.language_map (code, value) VALUES ('hun', oils_i18n_gettext('Hungarian'));
INSERT INTO config.language_map (code, value) VALUES ('hup', oils_i18n_gettext('Hupa'));
INSERT INTO config.language_map (code, value) VALUES ('iba', oils_i18n_gettext('Iban'));
INSERT INTO config.language_map (code, value) VALUES ('ibo', oils_i18n_gettext('Igbo'));
INSERT INTO config.language_map (code, value) VALUES ('ice', oils_i18n_gettext('Icelandic'));
INSERT INTO config.language_map (code, value) VALUES ('ido', oils_i18n_gettext('Ido'));
INSERT INTO config.language_map (code, value) VALUES ('iii', oils_i18n_gettext('Sichuan Yi'));
INSERT INTO config.language_map (code, value) VALUES ('ijo', oils_i18n_gettext('Ijo'));
INSERT INTO config.language_map (code, value) VALUES ('iku', oils_i18n_gettext('Inuktitut'));
INSERT INTO config.language_map (code, value) VALUES ('ile', oils_i18n_gettext('Interlingue'));
INSERT INTO config.language_map (code, value) VALUES ('ilo', oils_i18n_gettext('Iloko'));
INSERT INTO config.language_map (code, value) VALUES ('ina', oils_i18n_gettext('Interlingua (International Auxiliary Language Association)'));
INSERT INTO config.language_map (code, value) VALUES ('inc', oils_i18n_gettext('Indic (Other)'));
INSERT INTO config.language_map (code, value) VALUES ('ind', oils_i18n_gettext('Indonesian'));
INSERT INTO config.language_map (code, value) VALUES ('ine', oils_i18n_gettext('Indo-European (Other)'));
INSERT INTO config.language_map (code, value) VALUES ('inh', oils_i18n_gettext('Ingush'));
INSERT INTO config.language_map (code, value) VALUES ('-int', oils_i18n_gettext('Interlingua (International Auxiliary Language Association)'));
INSERT INTO config.language_map (code, value) VALUES ('ipk', oils_i18n_gettext('Inupiaq'));
INSERT INTO config.language_map (code, value) VALUES ('ira', oils_i18n_gettext('Iranian (Other)'));
INSERT INTO config.language_map (code, value) VALUES ('-iri', oils_i18n_gettext('Irish'));
INSERT INTO config.language_map (code, value) VALUES ('iro', oils_i18n_gettext('Iroquoian (Other)'));
INSERT INTO config.language_map (code, value) VALUES ('ita', oils_i18n_gettext('Italian'));
INSERT INTO config.language_map (code, value) VALUES ('jav', oils_i18n_gettext('Javanese'));
INSERT INTO config.language_map (code, value) VALUES ('jpn', oils_i18n_gettext('Japanese'));
INSERT INTO config.language_map (code, value) VALUES ('jpr', oils_i18n_gettext('Judeo-Persian'));
INSERT INTO config.language_map (code, value) VALUES ('jrb', oils_i18n_gettext('Judeo-Arabic'));
INSERT INTO config.language_map (code, value) VALUES ('kaa', oils_i18n_gettext('Kara-Kalpak'));
INSERT INTO config.language_map (code, value) VALUES ('kab', oils_i18n_gettext('Kabyle'));
INSERT INTO config.language_map (code, value) VALUES ('kac', oils_i18n_gettext('Kachin'));
INSERT INTO config.language_map (code, value) VALUES ('kal', oils_i18n_gettext('Kalâtdlisut'));
INSERT INTO config.language_map (code, value) VALUES ('kam', oils_i18n_gettext('Kamba'));
INSERT INTO config.language_map (code, value) VALUES ('kan', oils_i18n_gettext('Kannada'));
INSERT INTO config.language_map (code, value) VALUES ('kar', oils_i18n_gettext('Karen'));
INSERT INTO config.language_map (code, value) VALUES ('kas', oils_i18n_gettext('Kashmiri'));
INSERT INTO config.language_map (code, value) VALUES ('kau', oils_i18n_gettext('Kanuri'));
INSERT INTO config.language_map (code, value) VALUES ('kaw', oils_i18n_gettext('Kawi'));
INSERT INTO config.language_map (code, value) VALUES ('kaz', oils_i18n_gettext('Kazakh'));
INSERT INTO config.language_map (code, value) VALUES ('kbd', oils_i18n_gettext('Kabardian'));
INSERT INTO config.language_map (code, value) VALUES ('kha', oils_i18n_gettext('Khasi'));
INSERT INTO config.language_map (code, value) VALUES ('khi', oils_i18n_gettext('Khoisan (Other)'));
INSERT INTO config.language_map (code, value) VALUES ('khm', oils_i18n_gettext('Khmer'));
INSERT INTO config.language_map (code, value) VALUES ('kho', oils_i18n_gettext('Khotanese'));
INSERT INTO config.language_map (code, value) VALUES ('kik', oils_i18n_gettext('Kikuyu'));
INSERT INTO config.language_map (code, value) VALUES ('kin', oils_i18n_gettext('Kinyarwanda'));
INSERT INTO config.language_map (code, value) VALUES ('kir', oils_i18n_gettext('Kyrgyz'));
INSERT INTO config.language_map (code, value) VALUES ('kmb', oils_i18n_gettext('Kimbundu'));
INSERT INTO config.language_map (code, value) VALUES ('kok', oils_i18n_gettext('Konkani'));
INSERT INTO config.language_map (code, value) VALUES ('kom', oils_i18n_gettext('Komi'));
INSERT INTO config.language_map (code, value) VALUES ('kon', oils_i18n_gettext('Kongo'));
INSERT INTO config.language_map (code, value) VALUES ('kor', oils_i18n_gettext('Korean'));
INSERT INTO config.language_map (code, value) VALUES ('kos', oils_i18n_gettext('Kusaie'));
INSERT INTO config.language_map (code, value) VALUES ('kpe', oils_i18n_gettext('Kpelle'));
INSERT INTO config.language_map (code, value) VALUES ('kro', oils_i18n_gettext('Kru'));
INSERT INTO config.language_map (code, value) VALUES ('kru', oils_i18n_gettext('Kurukh'));
INSERT INTO config.language_map (code, value) VALUES ('kua', oils_i18n_gettext('Kuanyama'));
INSERT INTO config.language_map (code, value) VALUES ('kum', oils_i18n_gettext('Kumyk'));
INSERT INTO config.language_map (code, value) VALUES ('kur', oils_i18n_gettext('Kurdish'));
INSERT INTO config.language_map (code, value) VALUES ('-kus', oils_i18n_gettext('Kusaie'));
INSERT INTO config.language_map (code, value) VALUES ('kut', oils_i18n_gettext('Kutenai'));
INSERT INTO config.language_map (code, value) VALUES ('lad', oils_i18n_gettext('Ladino'));
INSERT INTO config.language_map (code, value) VALUES ('lah', oils_i18n_gettext('Lahnda'));
INSERT INTO config.language_map (code, value) VALUES ('lam', oils_i18n_gettext('Lamba'));
INSERT INTO config.language_map (code, value) VALUES ('-lan', oils_i18n_gettext('Occitan (post-1500)'));
INSERT INTO config.language_map (code, value) VALUES ('lao', oils_i18n_gettext('Lao'));
INSERT INTO config.language_map (code, value) VALUES ('-lap', oils_i18n_gettext('Sami'));
INSERT INTO config.language_map (code, value) VALUES ('lat', oils_i18n_gettext('Latin'));
INSERT INTO config.language_map (code, value) VALUES ('lav', oils_i18n_gettext('Latvian'));
INSERT INTO config.language_map (code, value) VALUES ('lez', oils_i18n_gettext('Lezgian'));
INSERT INTO config.language_map (code, value) VALUES ('lim', oils_i18n_gettext('Limburgish'));
INSERT INTO config.language_map (code, value) VALUES ('lin', oils_i18n_gettext('Lingala'));
INSERT INTO config.language_map (code, value) VALUES ('lit', oils_i18n_gettext('Lithuanian'));
INSERT INTO config.language_map (code, value) VALUES ('lol', oils_i18n_gettext('Mongo-Nkundu'));
INSERT INTO config.language_map (code, value) VALUES ('loz', oils_i18n_gettext('Lozi'));
INSERT INTO config.language_map (code, value) VALUES ('ltz', oils_i18n_gettext('Letzeburgesch'));
INSERT INTO config.language_map (code, value) VALUES ('lua', oils_i18n_gettext('Luba-Lulua'));
INSERT INTO config.language_map (code, value) VALUES ('lub', oils_i18n_gettext('Luba-Katanga'));
INSERT INTO config.language_map (code, value) VALUES ('lug', oils_i18n_gettext('Ganda'));
INSERT INTO config.language_map (code, value) VALUES ('lui', oils_i18n_gettext('Luiseño'));
INSERT INTO config.language_map (code, value) VALUES ('lun', oils_i18n_gettext('Lunda'));
INSERT INTO config.language_map (code, value) VALUES ('luo', oils_i18n_gettext('Luo (Kenya and Tanzania)'));
INSERT INTO config.language_map (code, value) VALUES ('lus', oils_i18n_gettext('Lushai'));
INSERT INTO config.language_map (code, value) VALUES ('mac', oils_i18n_gettext('Macedonian'));
INSERT INTO config.language_map (code, value) VALUES ('mad', oils_i18n_gettext('Madurese'));
INSERT INTO config.language_map (code, value) VALUES ('mag', oils_i18n_gettext('Magahi'));
INSERT INTO config.language_map (code, value) VALUES ('mah', oils_i18n_gettext('Marshallese'));
INSERT INTO config.language_map (code, value) VALUES ('mai', oils_i18n_gettext('Maithili'));
INSERT INTO config.language_map (code, value) VALUES ('mak', oils_i18n_gettext('Makasar'));
INSERT INTO config.language_map (code, value) VALUES ('mal', oils_i18n_gettext('Malayalam'));
INSERT INTO config.language_map (code, value) VALUES ('man', oils_i18n_gettext('Mandingo'));
INSERT INTO config.language_map (code, value) VALUES ('mao', oils_i18n_gettext('Maori'));
INSERT INTO config.language_map (code, value) VALUES ('map', oils_i18n_gettext('Austronesian (Other)'));
INSERT INTO config.language_map (code, value) VALUES ('mar', oils_i18n_gettext('Marathi'));
INSERT INTO config.language_map (code, value) VALUES ('mas', oils_i18n_gettext('Masai'));
INSERT INTO config.language_map (code, value) VALUES ('-max', oils_i18n_gettext('Manx'));
INSERT INTO config.language_map (code, value) VALUES ('may', oils_i18n_gettext('Malay'));
INSERT INTO config.language_map (code, value) VALUES ('mdr', oils_i18n_gettext('Mandar'));
INSERT INTO config.language_map (code, value) VALUES ('men', oils_i18n_gettext('Mende'));
INSERT INTO config.language_map (code, value) VALUES ('mga', oils_i18n_gettext('Irish, Middle (ca. 1100-1550)'));
INSERT INTO config.language_map (code, value) VALUES ('mic', oils_i18n_gettext('Micmac'));
INSERT INTO config.language_map (code, value) VALUES ('min', oils_i18n_gettext('Minangkabau'));
INSERT INTO config.language_map (code, value) VALUES ('mis', oils_i18n_gettext('Miscellaneous languages'));
INSERT INTO config.language_map (code, value) VALUES ('mkh', oils_i18n_gettext('Mon-Khmer (Other)'));
INSERT INTO config.language_map (code, value) VALUES ('-mla', oils_i18n_gettext('Malagasy'));
INSERT INTO config.language_map (code, value) VALUES ('mlg', oils_i18n_gettext('Malagasy'));
INSERT INTO config.language_map (code, value) VALUES ('mlt', oils_i18n_gettext('Maltese'));
INSERT INTO config.language_map (code, value) VALUES ('mnc', oils_i18n_gettext('Manchu'));
INSERT INTO config.language_map (code, value) VALUES ('mni', oils_i18n_gettext('Manipuri'));
INSERT INTO config.language_map (code, value) VALUES ('mno', oils_i18n_gettext('Manobo languages'));
INSERT INTO config.language_map (code, value) VALUES ('moh', oils_i18n_gettext('Mohawk'));
INSERT INTO config.language_map (code, value) VALUES ('mol', oils_i18n_gettext('Moldavian'));
INSERT INTO config.language_map (code, value) VALUES ('mon', oils_i18n_gettext('Mongolian'));
INSERT INTO config.language_map (code, value) VALUES ('mos', oils_i18n_gettext('Mooré'));
INSERT INTO config.language_map (code, value) VALUES ('mul', oils_i18n_gettext('Multiple languages'));
INSERT INTO config.language_map (code, value) VALUES ('mun', oils_i18n_gettext('Munda (Other)'));
INSERT INTO config.language_map (code, value) VALUES ('mus', oils_i18n_gettext('Creek'));
INSERT INTO config.language_map (code, value) VALUES ('mwr', oils_i18n_gettext('Marwari'));
INSERT INTO config.language_map (code, value) VALUES ('myn', oils_i18n_gettext('Mayan languages'));
INSERT INTO config.language_map (code, value) VALUES ('nah', oils_i18n_gettext('Nahuatl'));
INSERT INTO config.language_map (code, value) VALUES ('nai', oils_i18n_gettext('North American Indian (Other)'));
INSERT INTO config.language_map (code, value) VALUES ('nap', oils_i18n_gettext('Neapolitan Italian'));
INSERT INTO config.language_map (code, value) VALUES ('nau', oils_i18n_gettext('Nauru'));
INSERT INTO config.language_map (code, value) VALUES ('nav', oils_i18n_gettext('Navajo'));
INSERT INTO config.language_map (code, value) VALUES ('nbl', oils_i18n_gettext('Ndebele (South Africa)'));
INSERT INTO config.language_map (code, value) VALUES ('nde', oils_i18n_gettext('Ndebele (Zimbabwe)  '));
INSERT INTO config.language_map (code, value) VALUES ('ndo', oils_i18n_gettext('Ndonga'));
INSERT INTO config.language_map (code, value) VALUES ('nds', oils_i18n_gettext('Low German'));
INSERT INTO config.language_map (code, value) VALUES ('nep', oils_i18n_gettext('Nepali'));
INSERT INTO config.language_map (code, value) VALUES ('new', oils_i18n_gettext('Newari'));
INSERT INTO config.language_map (code, value) VALUES ('nia', oils_i18n_gettext('Nias'));
INSERT INTO config.language_map (code, value) VALUES ('nic', oils_i18n_gettext('Niger-Kordofanian (Other)'));
INSERT INTO config.language_map (code, value) VALUES ('niu', oils_i18n_gettext('Niuean'));
INSERT INTO config.language_map (code, value) VALUES ('nno', oils_i18n_gettext('Norwegian (Nynorsk)'));
INSERT INTO config.language_map (code, value) VALUES ('nob', oils_i18n_gettext('Norwegian (Bokmål)'));
INSERT INTO config.language_map (code, value) VALUES ('nog', oils_i18n_gettext('Nogai'));
INSERT INTO config.language_map (code, value) VALUES ('non', oils_i18n_gettext('Old Norse'));
INSERT INTO config.language_map (code, value) VALUES ('nor', oils_i18n_gettext('Norwegian'));
INSERT INTO config.language_map (code, value) VALUES ('nso', oils_i18n_gettext('Northern Sotho'));
INSERT INTO config.language_map (code, value) VALUES ('nub', oils_i18n_gettext('Nubian languages'));
INSERT INTO config.language_map (code, value) VALUES ('nya', oils_i18n_gettext('Nyanja'));
INSERT INTO config.language_map (code, value) VALUES ('nym', oils_i18n_gettext('Nyamwezi'));
INSERT INTO config.language_map (code, value) VALUES ('nyn', oils_i18n_gettext('Nyankole'));
INSERT INTO config.language_map (code, value) VALUES ('nyo', oils_i18n_gettext('Nyoro'));
INSERT INTO config.language_map (code, value) VALUES ('nzi', oils_i18n_gettext('Nzima'));
INSERT INTO config.language_map (code, value) VALUES ('oci', oils_i18n_gettext('Occitan (post-1500)'));
INSERT INTO config.language_map (code, value) VALUES ('oji', oils_i18n_gettext('Ojibwa'));
INSERT INTO config.language_map (code, value) VALUES ('ori', oils_i18n_gettext('Oriya'));
INSERT INTO config.language_map (code, value) VALUES ('orm', oils_i18n_gettext('Oromo'));
INSERT INTO config.language_map (code, value) VALUES ('osa', oils_i18n_gettext('Osage'));
INSERT INTO config.language_map (code, value) VALUES ('oss', oils_i18n_gettext('Ossetic'));
INSERT INTO config.language_map (code, value) VALUES ('ota', oils_i18n_gettext('Turkish, Ottoman'));
INSERT INTO config.language_map (code, value) VALUES ('oto', oils_i18n_gettext('Otomian languages'));
INSERT INTO config.language_map (code, value) VALUES ('paa', oils_i18n_gettext('Papuan (Other)'));
INSERT INTO config.language_map (code, value) VALUES ('pag', oils_i18n_gettext('Pangasinan'));
INSERT INTO config.language_map (code, value) VALUES ('pal', oils_i18n_gettext('Pahlavi'));
INSERT INTO config.language_map (code, value) VALUES ('pam', oils_i18n_gettext('Pampanga'));
INSERT INTO config.language_map (code, value) VALUES ('pan', oils_i18n_gettext('Panjabi'));
INSERT INTO config.language_map (code, value) VALUES ('pap', oils_i18n_gettext('Papiamento'));
INSERT INTO config.language_map (code, value) VALUES ('pau', oils_i18n_gettext('Palauan'));
INSERT INTO config.language_map (code, value) VALUES ('peo', oils_i18n_gettext('Old Persian (ca. 600-400 B.C.)'));
INSERT INTO config.language_map (code, value) VALUES ('per', oils_i18n_gettext('Persian'));
INSERT INTO config.language_map (code, value) VALUES ('phi', oils_i18n_gettext('Philippine (Other)'));
INSERT INTO config.language_map (code, value) VALUES ('phn', oils_i18n_gettext('Phoenician'));
INSERT INTO config.language_map (code, value) VALUES ('pli', oils_i18n_gettext('Pali'));
INSERT INTO config.language_map (code, value) VALUES ('pol', oils_i18n_gettext('Polish'));
INSERT INTO config.language_map (code, value) VALUES ('pon', oils_i18n_gettext('Ponape'));
INSERT INTO config.language_map (code, value) VALUES ('por', oils_i18n_gettext('Portuguese'));
INSERT INTO config.language_map (code, value) VALUES ('pra', oils_i18n_gettext('Prakrit languages'));
INSERT INTO config.language_map (code, value) VALUES ('pro', oils_i18n_gettext('Provençal (to 1500)'));
INSERT INTO config.language_map (code, value) VALUES ('pus', oils_i18n_gettext('Pushto'));
INSERT INTO config.language_map (code, value) VALUES ('que', oils_i18n_gettext('Quechua'));
INSERT INTO config.language_map (code, value) VALUES ('raj', oils_i18n_gettext('Rajasthani'));
INSERT INTO config.language_map (code, value) VALUES ('rap', oils_i18n_gettext('Rapanui'));
INSERT INTO config.language_map (code, value) VALUES ('rar', oils_i18n_gettext('Rarotongan'));
INSERT INTO config.language_map (code, value) VALUES ('roa', oils_i18n_gettext('Romance (Other)'));
INSERT INTO config.language_map (code, value) VALUES ('roh', oils_i18n_gettext('Raeto-Romance'));
INSERT INTO config.language_map (code, value) VALUES ('rom', oils_i18n_gettext('Romani'));
INSERT INTO config.language_map (code, value) VALUES ('rum', oils_i18n_gettext('Romanian'));
INSERT INTO config.language_map (code, value) VALUES ('run', oils_i18n_gettext('Rundi'));
INSERT INTO config.language_map (code, value) VALUES ('rus', oils_i18n_gettext('Russian'));
INSERT INTO config.language_map (code, value) VALUES ('sad', oils_i18n_gettext('Sandawe'));
INSERT INTO config.language_map (code, value) VALUES ('sag', oils_i18n_gettext('Sango (Ubangi Creole)'));
INSERT INTO config.language_map (code, value) VALUES ('sah', oils_i18n_gettext('Yakut'));
INSERT INTO config.language_map (code, value) VALUES ('sai', oils_i18n_gettext('South American Indian (Other)'));
INSERT INTO config.language_map (code, value) VALUES ('sal', oils_i18n_gettext('Salishan languages'));
INSERT INTO config.language_map (code, value) VALUES ('sam', oils_i18n_gettext('Samaritan Aramaic'));
INSERT INTO config.language_map (code, value) VALUES ('san', oils_i18n_gettext('Sanskrit'));
INSERT INTO config.language_map (code, value) VALUES ('-sao', oils_i18n_gettext('Samoan'));
INSERT INTO config.language_map (code, value) VALUES ('sas', oils_i18n_gettext('Sasak'));
INSERT INTO config.language_map (code, value) VALUES ('sat', oils_i18n_gettext('Santali'));
INSERT INTO config.language_map (code, value) VALUES ('scc', oils_i18n_gettext('Serbian'));
INSERT INTO config.language_map (code, value) VALUES ('sco', oils_i18n_gettext('Scots'));
INSERT INTO config.language_map (code, value) VALUES ('scr', oils_i18n_gettext('Croatian'));
INSERT INTO config.language_map (code, value) VALUES ('sel', oils_i18n_gettext('Selkup'));
INSERT INTO config.language_map (code, value) VALUES ('sem', oils_i18n_gettext('Semitic (Other)'));
INSERT INTO config.language_map (code, value) VALUES ('sga', oils_i18n_gettext('Irish, Old (to 1100)'));
INSERT INTO config.language_map (code, value) VALUES ('sgn', oils_i18n_gettext('Sign languages'));
INSERT INTO config.language_map (code, value) VALUES ('shn', oils_i18n_gettext('Shan'));
INSERT INTO config.language_map (code, value) VALUES ('-sho', oils_i18n_gettext('Shona'));
INSERT INTO config.language_map (code, value) VALUES ('sid', oils_i18n_gettext('Sidamo'));
INSERT INTO config.language_map (code, value) VALUES ('sin', oils_i18n_gettext('Sinhalese'));
INSERT INTO config.language_map (code, value) VALUES ('sio', oils_i18n_gettext('Siouan (Other)'));
INSERT INTO config.language_map (code, value) VALUES ('sit', oils_i18n_gettext('Sino-Tibetan (Other)'));
INSERT INTO config.language_map (code, value) VALUES ('sla', oils_i18n_gettext('Slavic (Other)'));
INSERT INTO config.language_map (code, value) VALUES ('slo', oils_i18n_gettext('Slovak'));
INSERT INTO config.language_map (code, value) VALUES ('slv', oils_i18n_gettext('Slovenian'));
INSERT INTO config.language_map (code, value) VALUES ('sma', oils_i18n_gettext('Southern Sami'));
INSERT INTO config.language_map (code, value) VALUES ('sme', oils_i18n_gettext('Northern Sami'));
INSERT INTO config.language_map (code, value) VALUES ('smi', oils_i18n_gettext('Sami'));
INSERT INTO config.language_map (code, value) VALUES ('smj', oils_i18n_gettext('Lule Sami'));
INSERT INTO config.language_map (code, value) VALUES ('smn', oils_i18n_gettext('Inari Sami'));
INSERT INTO config.language_map (code, value) VALUES ('smo', oils_i18n_gettext('Samoan'));
INSERT INTO config.language_map (code, value) VALUES ('sms', oils_i18n_gettext('Skolt Sami'));
INSERT INTO config.language_map (code, value) VALUES ('sna', oils_i18n_gettext('Shona'));
INSERT INTO config.language_map (code, value) VALUES ('snd', oils_i18n_gettext('Sindhi'));
INSERT INTO config.language_map (code, value) VALUES ('-snh', oils_i18n_gettext('Sinhalese'));
INSERT INTO config.language_map (code, value) VALUES ('snk', oils_i18n_gettext('Soninke'));
INSERT INTO config.language_map (code, value) VALUES ('sog', oils_i18n_gettext('Sogdian'));
INSERT INTO config.language_map (code, value) VALUES ('som', oils_i18n_gettext('Somali'));
INSERT INTO config.language_map (code, value) VALUES ('son', oils_i18n_gettext('Songhai'));
INSERT INTO config.language_map (code, value) VALUES ('sot', oils_i18n_gettext('Sotho'));
INSERT INTO config.language_map (code, value) VALUES ('spa', oils_i18n_gettext('Spanish'));
INSERT INTO config.language_map (code, value) VALUES ('srd', oils_i18n_gettext('Sardinian'));
INSERT INTO config.language_map (code, value) VALUES ('srr', oils_i18n_gettext('Serer'));
INSERT INTO config.language_map (code, value) VALUES ('ssa', oils_i18n_gettext('Nilo-Saharan (Other)'));
INSERT INTO config.language_map (code, value) VALUES ('-sso', oils_i18n_gettext('Sotho'));
INSERT INTO config.language_map (code, value) VALUES ('ssw', oils_i18n_gettext('Swazi'));
INSERT INTO config.language_map (code, value) VALUES ('suk', oils_i18n_gettext('Sukuma'));
INSERT INTO config.language_map (code, value) VALUES ('sun', oils_i18n_gettext('Sundanese'));
INSERT INTO config.language_map (code, value) VALUES ('sus', oils_i18n_gettext('Susu'));
INSERT INTO config.language_map (code, value) VALUES ('sux', oils_i18n_gettext('Sumerian'));
INSERT INTO config.language_map (code, value) VALUES ('swa', oils_i18n_gettext('Swahili'));
INSERT INTO config.language_map (code, value) VALUES ('swe', oils_i18n_gettext('Swedish'));
INSERT INTO config.language_map (code, value) VALUES ('-swz', oils_i18n_gettext('Swazi'));
INSERT INTO config.language_map (code, value) VALUES ('syr', oils_i18n_gettext('Syriac'));
INSERT INTO config.language_map (code, value) VALUES ('-tag', oils_i18n_gettext('Tagalog'));
INSERT INTO config.language_map (code, value) VALUES ('tah', oils_i18n_gettext('Tahitian'));
INSERT INTO config.language_map (code, value) VALUES ('tai', oils_i18n_gettext('Tai (Other)'));
INSERT INTO config.language_map (code, value) VALUES ('-taj', oils_i18n_gettext('Tajik'));
INSERT INTO config.language_map (code, value) VALUES ('tam', oils_i18n_gettext('Tamil'));
INSERT INTO config.language_map (code, value) VALUES ('-tar', oils_i18n_gettext('Tatar'));
INSERT INTO config.language_map (code, value) VALUES ('tat', oils_i18n_gettext('Tatar'));
INSERT INTO config.language_map (code, value) VALUES ('tel', oils_i18n_gettext('Telugu'));
INSERT INTO config.language_map (code, value) VALUES ('tem', oils_i18n_gettext('Temne'));
INSERT INTO config.language_map (code, value) VALUES ('ter', oils_i18n_gettext('Terena'));
INSERT INTO config.language_map (code, value) VALUES ('tet', oils_i18n_gettext('Tetum'));
INSERT INTO config.language_map (code, value) VALUES ('tgk', oils_i18n_gettext('Tajik'));
INSERT INTO config.language_map (code, value) VALUES ('tgl', oils_i18n_gettext('Tagalog'));
INSERT INTO config.language_map (code, value) VALUES ('tha', oils_i18n_gettext('Thai'));
INSERT INTO config.language_map (code, value) VALUES ('tib', oils_i18n_gettext('Tibetan'));
INSERT INTO config.language_map (code, value) VALUES ('tig', oils_i18n_gettext('Tigré'));
INSERT INTO config.language_map (code, value) VALUES ('tir', oils_i18n_gettext('Tigrinya'));
INSERT INTO config.language_map (code, value) VALUES ('tiv', oils_i18n_gettext('Tiv'));
INSERT INTO config.language_map (code, value) VALUES ('tkl', oils_i18n_gettext('Tokelauan'));
INSERT INTO config.language_map (code, value) VALUES ('tli', oils_i18n_gettext('Tlingit'));
INSERT INTO config.language_map (code, value) VALUES ('tmh', oils_i18n_gettext('Tamashek'));
INSERT INTO config.language_map (code, value) VALUES ('tog', oils_i18n_gettext('Tonga (Nyasa)'));
INSERT INTO config.language_map (code, value) VALUES ('ton', oils_i18n_gettext('Tongan'));
INSERT INTO config.language_map (code, value) VALUES ('tpi', oils_i18n_gettext('Tok Pisin'));
INSERT INTO config.language_map (code, value) VALUES ('-tru', oils_i18n_gettext('Truk'));
INSERT INTO config.language_map (code, value) VALUES ('tsi', oils_i18n_gettext('Tsimshian'));
INSERT INTO config.language_map (code, value) VALUES ('tsn', oils_i18n_gettext('Tswana'));
INSERT INTO config.language_map (code, value) VALUES ('tso', oils_i18n_gettext('Tsonga'));
INSERT INTO config.language_map (code, value) VALUES ('-tsw', oils_i18n_gettext('Tswana'));
INSERT INTO config.language_map (code, value) VALUES ('tuk', oils_i18n_gettext('Turkmen'));
INSERT INTO config.language_map (code, value) VALUES ('tum', oils_i18n_gettext('Tumbuka'));
INSERT INTO config.language_map (code, value) VALUES ('tup', oils_i18n_gettext('Tupi languages'));
INSERT INTO config.language_map (code, value) VALUES ('tur', oils_i18n_gettext('Turkish'));
INSERT INTO config.language_map (code, value) VALUES ('tut', oils_i18n_gettext('Altaic (Other)'));
INSERT INTO config.language_map (code, value) VALUES ('tvl', oils_i18n_gettext('Tuvaluan'));
INSERT INTO config.language_map (code, value) VALUES ('twi', oils_i18n_gettext('Twi'));
INSERT INTO config.language_map (code, value) VALUES ('tyv', oils_i18n_gettext('Tuvinian'));
INSERT INTO config.language_map (code, value) VALUES ('udm', oils_i18n_gettext('Udmurt'));
INSERT INTO config.language_map (code, value) VALUES ('uga', oils_i18n_gettext('Ugaritic'));
INSERT INTO config.language_map (code, value) VALUES ('uig', oils_i18n_gettext('Uighur'));
INSERT INTO config.language_map (code, value) VALUES ('ukr', oils_i18n_gettext('Ukrainian'));
INSERT INTO config.language_map (code, value) VALUES ('umb', oils_i18n_gettext('Umbundu'));
INSERT INTO config.language_map (code, value) VALUES ('und', oils_i18n_gettext('Undetermined'));
INSERT INTO config.language_map (code, value) VALUES ('urd', oils_i18n_gettext('Urdu'));
INSERT INTO config.language_map (code, value) VALUES ('uzb', oils_i18n_gettext('Uzbek'));
INSERT INTO config.language_map (code, value) VALUES ('vai', oils_i18n_gettext('Vai'));
INSERT INTO config.language_map (code, value) VALUES ('ven', oils_i18n_gettext('Venda'));
INSERT INTO config.language_map (code, value) VALUES ('vie', oils_i18n_gettext('Vietnamese'));
INSERT INTO config.language_map (code, value) VALUES ('vol', oils_i18n_gettext('Volapük'));
INSERT INTO config.language_map (code, value) VALUES ('vot', oils_i18n_gettext('Votic'));
INSERT INTO config.language_map (code, value) VALUES ('wak', oils_i18n_gettext('Wakashan languages'));
INSERT INTO config.language_map (code, value) VALUES ('wal', oils_i18n_gettext('Walamo'));
INSERT INTO config.language_map (code, value) VALUES ('war', oils_i18n_gettext('Waray'));
INSERT INTO config.language_map (code, value) VALUES ('was', oils_i18n_gettext('Washo'));
INSERT INTO config.language_map (code, value) VALUES ('wel', oils_i18n_gettext('Welsh'));
INSERT INTO config.language_map (code, value) VALUES ('wen', oils_i18n_gettext('Sorbian languages'));
INSERT INTO config.language_map (code, value) VALUES ('wln', oils_i18n_gettext('Walloon'));
INSERT INTO config.language_map (code, value) VALUES ('wol', oils_i18n_gettext('Wolof'));
INSERT INTO config.language_map (code, value) VALUES ('xal', oils_i18n_gettext('Kalmyk'));
INSERT INTO config.language_map (code, value) VALUES ('xho', oils_i18n_gettext('Xhosa'));
INSERT INTO config.language_map (code, value) VALUES ('yao', oils_i18n_gettext('Yao (Africa)'));
INSERT INTO config.language_map (code, value) VALUES ('yap', oils_i18n_gettext('Yapese'));
INSERT INTO config.language_map (code, value) VALUES ('yid', oils_i18n_gettext('Yiddish'));
INSERT INTO config.language_map (code, value) VALUES ('yor', oils_i18n_gettext('Yoruba'));
INSERT INTO config.language_map (code, value) VALUES ('ypk', oils_i18n_gettext('Yupik languages'));
INSERT INTO config.language_map (code, value) VALUES ('zap', oils_i18n_gettext('Zapotec'));
INSERT INTO config.language_map (code, value) VALUES ('zen', oils_i18n_gettext('Zenaga'));
INSERT INTO config.language_map (code, value) VALUES ('zha', oils_i18n_gettext('Zhuang'));
INSERT INTO config.language_map (code, value) VALUES ('znd', oils_i18n_gettext('Zande'));
INSERT INTO config.language_map (code, value) VALUES ('zul', oils_i18n_gettext('Zulu'));
INSERT INTO config.language_map (code, value) VALUES ('zun', oils_i18n_gettext('Zuni'));

INSERT INTO config.item_form_map (code, value) VALUES ('a', oils_i18n_gettext('Microfilm'));
INSERT INTO config.item_form_map (code, value) VALUES ('b', oils_i18n_gettext('Microfiche'));
INSERT INTO config.item_form_map (code, value) VALUES ('c', oils_i18n_gettext('Microopaque'));
INSERT INTO config.item_form_map (code, value) VALUES ('d', oils_i18n_gettext('Large print'));
INSERT INTO config.item_form_map (code, value) VALUES ('f', oils_i18n_gettext('Braille'));
INSERT INTO config.item_form_map (code, value) VALUES ('r', oils_i18n_gettext('Regular print reproduction'));
INSERT INTO config.item_form_map (code, value) VALUES ('s', oils_i18n_gettext('Electronic'));

INSERT INTO config.item_type_map (code, value) VALUES ('a', oils_i18n_gettext('Language material'));
INSERT INTO config.item_type_map (code, value) VALUES ('t', oils_i18n_gettext('Manuscript language material'));
INSERT INTO config.item_type_map (code, value) VALUES ('g', oils_i18n_gettext('Projected medium'));
INSERT INTO config.item_type_map (code, value) VALUES ('k', oils_i18n_gettext('Two-dimensional nonprojectable graphic'));
INSERT INTO config.item_type_map (code, value) VALUES ('r', oils_i18n_gettext('Three-dimensional artifact or naturally occurring object'));
INSERT INTO config.item_type_map (code, value) VALUES ('o', oils_i18n_gettext('Kit'));
INSERT INTO config.item_type_map (code, value) VALUES ('p', oils_i18n_gettext('Mixed materials'));
INSERT INTO config.item_type_map (code, value) VALUES ('e', oils_i18n_gettext('Cartographic material'));
INSERT INTO config.item_type_map (code, value) VALUES ('f', oils_i18n_gettext('Manuscript cartographic material'));
INSERT INTO config.item_type_map (code, value) VALUES ('c', oils_i18n_gettext('Notated music'));
INSERT INTO config.item_type_map (code, value) VALUES ('d', oils_i18n_gettext('Manuscript notated music'));
INSERT INTO config.item_type_map (code, value) VALUES ('i', oils_i18n_gettext('Nonmusical sound recording'));
INSERT INTO config.item_type_map (code, value) VALUES ('j', oils_i18n_gettext('Musical sound recording'));
INSERT INTO config.item_type_map (code, value) VALUES ('m', oils_i18n_gettext('Computer file'));

INSERT INTO config.bib_level_map (code, value) VALUES ('a', oils_i18n_gettext('Monographic component part'));
INSERT INTO config.bib_level_map (code, value) VALUES ('b', oils_i18n_gettext('Serial component part'));
INSERT INTO config.bib_level_map (code, value) VALUES ('c', oils_i18n_gettext('Collection'));
INSERT INTO config.bib_level_map (code, value) VALUES ('d', oils_i18n_gettext('Subunit'));
INSERT INTO config.bib_level_map (code, value) VALUES ('i', oils_i18n_gettext('Integrating resource'));
INSERT INTO config.bib_level_map (code, value) VALUES ('m', oils_i18n_gettext('Monograph/Item'));
INSERT INTO config.bib_level_map (code, value) VALUES ('s', oils_i18n_gettext('Serial'));

--005.schema.actors.sql:

-- The PINES levels
INSERT INTO actor.org_unit_type (name, opac_label, depth, parent, can_have_users, can_have_vols) VALUES 
    ( oils_i18n_gettext('Consortium'),oils_i18n_gettext('Everywhere'), 0, NULL, FALSE, FALSE );
INSERT INTO actor.org_unit_type (name, opac_label, depth, parent, can_have_users, can_have_vols) VALUES 
    ( oils_i18n_gettext('System'),oils_i18n_gettext('Local Library System'), 1, 1, FALSE, FALSE );
INSERT INTO actor.org_unit_type (name, opac_label, depth, parent) VALUES 
    ( oils_i18n_gettext('Branch'),oils_i18n_gettext('This Branch'), 2, 2 );
INSERT INTO actor.org_unit_type (name, opac_label, depth, parent) VALUES 
    ( oils_i18n_gettext('Sub-lib'),oils_i18n_gettext('This Specialized Library'), 3, 3 );
INSERT INTO actor.org_unit_type (name, opac_label, depth, parent) VALUES 
    ( oils_i18n_gettext('Bookmobile'),oils_i18n_gettext('Your Bookmobile'), 3, 3 );

INSERT INTO actor.org_unit (parent_ou, ou_type, shortname, name) VALUES 
    (NULL, 1, 'CONS', oils_i18n_gettext('Example Consortium'));
INSERT INTO actor.org_unit (parent_ou, ou_type, shortname, name) VALUES 
    (1, 2, 'SYS1', oils_i18n_gettext('Example System 1'));
INSERT INTO actor.org_unit (parent_ou, ou_type, shortname, name) VALUES 
    (1, 2, 'SYS2', oils_i18n_gettext('Example System 2'));
INSERT INTO actor.org_unit (parent_ou, ou_type, shortname, name) VALUES 
    (2, 3, 'BR1', oils_i18n_gettext('Example Branch 1'));
INSERT INTO actor.org_unit (parent_ou, ou_type, shortname, name) VALUES 
    (2, 3, 'BR2', oils_i18n_gettext('Example Branch 2'));
INSERT INTO actor.org_unit (parent_ou, ou_type, shortname, name) VALUES 
    (3, 3, 'BR3', oils_i18n_gettext('Example Branch 3'));
INSERT INTO actor.org_unit (parent_ou, ou_type, shortname, name) VALUES 
    (3, 3, 'BR4', oils_i18n_gettext('Example Branch 4'));
INSERT INTO actor.org_unit (parent_ou, ou_type, shortname, name) VALUES 
    (4, 4, 'SL1', oils_i18n_gettext('Example Sub-lib 1'));
INSERT INTO actor.org_unit (parent_ou, ou_type, shortname, name) VALUES 
    (6, 5, 'BM1', oils_i18n_gettext('Example Bookmobile 1'));

INSERT INTO actor.org_address VALUES (DEFAULT,DEFAULT,DEFAULT,1,oils_i18n_gettext('123 Main St.'),NULL,oils_i18n_gettext('Anywhere'),NULL,oils_i18n_gettext('GA'),oils_i18n_gettext('US'),oils_i18n_gettext('30303'));

UPDATE actor.org_unit SET holds_address = 1, ill_address = 1, billing_address = 1, mailing_address = 1;

--006.data.permissions.sql:
INSERT INTO permission.perm_list VALUES 
    (-1, 'EVERYTHING', NULL);
INSERT INTO permission.perm_list VALUES 
    (2, 'OPAC_LOGIN', NULL);
INSERT INTO permission.perm_list VALUES 
    (4, 'STAFF_LOGIN', NULL);
INSERT INTO permission.perm_list VALUES 
    (5, 'MR_HOLDS', NULL);
INSERT INTO permission.perm_list VALUES 
    (6, 'TITLE_HOLDS', NULL);
INSERT INTO permission.perm_list VALUES 
    (7, 'VOLUME_HOLDS', NULL);
INSERT INTO permission.perm_list VALUES 
    (8, 'COPY_HOLDS', oils_i18n_gettext('User is allowed to place a hold on a specific copy'));
INSERT INTO permission.perm_list VALUES 
    (9, 'REQUEST_HOLDS', NULL);
INSERT INTO permission.perm_list VALUES 
    (10, 'REQUEST_HOLDS_OVERRIDE', NULL);
INSERT INTO permission.perm_list VALUES 
    (11, 'VIEW_HOLD', oils_i18n_gettext('Allows a user to view another user''s holds'));
INSERT INTO permission.perm_list VALUES 
    (13, 'DELETE_HOLDS', NULL);
INSERT INTO permission.perm_list VALUES 
    (14, 'UPDATE_HOLD', oils_i18n_gettext('Allows a user to update another user''s hold'));
INSERT INTO permission.perm_list VALUES 
    (15, 'RENEW_CIRC', NULL);
INSERT INTO permission.perm_list VALUES 
    (16, 'VIEW_USER_FINES_SUMMARY', NULL);
INSERT INTO permission.perm_list VALUES 
    (17, 'VIEW_USER_TRANSACTIONS', NULL);
INSERT INTO permission.perm_list VALUES 
    (18, 'UPDATE_MARC', NULL);
INSERT INTO permission.perm_list VALUES 
    (19, 'CREATE_MARC', oils_i18n_gettext('User is allowed to create new MARC records'));
INSERT INTO permission.perm_list VALUES 
    (20, 'IMPORT_MARC', NULL);
INSERT INTO permission.perm_list VALUES 
    (21, 'CREATE_VOLUME', NULL);
INSERT INTO permission.perm_list VALUES 
    (22, 'UPDATE_VOLUME', NULL);
INSERT INTO permission.perm_list VALUES 
    (23, 'DELETE_VOLUME', NULL);
INSERT INTO permission.perm_list VALUES 
    (25, 'UPDATE_COPY', NULL);
INSERT INTO permission.perm_list VALUES 
    (26, 'DELETE_COPY', NULL);
INSERT INTO permission.perm_list VALUES 
    (27, 'RENEW_HOLD_OVERRIDE', NULL);
INSERT INTO permission.perm_list VALUES 
    (28, 'CREATE_USER', NULL);
INSERT INTO permission.perm_list VALUES 
    (29, 'UPDATE_USER', NULL);
INSERT INTO permission.perm_list VALUES 
    (30, 'DELETE_USER', NULL);
INSERT INTO permission.perm_list VALUES 
    (31, 'VIEW_USER', NULL);
INSERT INTO permission.perm_list VALUES 
    (32, 'COPY_CHECKIN', NULL);
INSERT INTO permission.perm_list VALUES 
    (33, 'CREATE_TRANSIT', NULL);
INSERT INTO permission.perm_list VALUES 
    (34, 'VIEW_PERMISSION', NULL);
INSERT INTO permission.perm_list VALUES 
    (35, 'CHECKIN_BYPASS_HOLD_FULFILL', NULL);
INSERT INTO permission.perm_list VALUES 
    (36, 'CREATE_PAYMENT', NULL);
INSERT INTO permission.perm_list VALUES 
    (37, 'SET_CIRC_LOST', NULL);
INSERT INTO permission.perm_list VALUES 
    (38, 'SET_CIRC_MISSING', NULL);
INSERT INTO permission.perm_list VALUES 
    (39, 'SET_CIRC_CLAIMS_RETURNED', NULL);
INSERT INTO permission.perm_list VALUES 
    (41, 'CREATE_TRANSACTION', oils_i18n_gettext('User may create new billable transactions'));
INSERT INTO permission.perm_list VALUES 
    (43, 'CREATE_BILL', oils_i18n_gettext('Allows a user to create a new bill on a transaction'));
INSERT INTO permission.perm_list VALUES 
    (44, 'VIEW_CONTAINER', oils_i18n_gettext('Allows a user to view another user''s containers (buckets)'));
INSERT INTO permission.perm_list VALUES 
    (45, 'CREATE_CONTAINER', oils_i18n_gettext('Allows a user to create a new container for another user'));
INSERT INTO permission.perm_list VALUES 
    (24, 'CREATE_COPY', oils_i18n_gettext('User is allowed to create a new copy object'));
INSERT INTO permission.perm_list VALUES 
    (47, 'UPDATE_ORG_UNIT', oils_i18n_gettext('Allows a user to change org unit settings'));
INSERT INTO permission.perm_list VALUES 
    (48, 'VIEW_CIRCULATIONS', oils_i18n_gettext('Allows a user to see what another use has checked out'));
INSERT INTO permission.perm_list VALUES 
    (42, 'VIEW_TRANSACTION', oils_i18n_gettext('User may view another user''s transactions'));
INSERT INTO permission.perm_list VALUES 
    (49, 'DELETE_CONTAINER', oils_i18n_gettext('Allows a user to delete another user container'));
INSERT INTO permission.perm_list VALUES 
    (50, 'CREATE_CONTAINER_ITEM', oils_i18n_gettext('Create a container item for another user'));
INSERT INTO permission.perm_list VALUES 
    (51, 'CREATE_USER_GROUP_LINK', oils_i18n_gettext('User can add other users to permission groups'));
INSERT INTO permission.perm_list VALUES 
    (52, 'REMOVE_USER_GROUP_LINK', oils_i18n_gettext('User can remove other users from permission groups'));
INSERT INTO permission.perm_list VALUES 
    (53, 'VIEW_PERM_GROUPS', oils_i18n_gettext('Allow user to view others'' permission groups'));
INSERT INTO permission.perm_list VALUES 
    (54, 'VIEW_PERMIT_CHECKOUT', oils_i18n_gettext('Allows a user to determine of another user can checkout an item'));
INSERT INTO permission.perm_list VALUES 
    (55, 'UPDATE_BATCH_COPY', oils_i18n_gettext('Allows a user to edit copies in batch'));
INSERT INTO permission.perm_list VALUES 
    (56, 'CREATE_PATRON_STAT_CAT', oils_i18n_gettext('User may create a new patron statistical category'));
INSERT INTO permission.perm_list VALUES 
    (57, 'CREATE_COPY_STAT_CAT', oils_i18n_gettext('User may create a copy stat cat'));
INSERT INTO permission.perm_list VALUES 
    (58, 'CREATE_PATRON_STAT_CAT_ENTRY', oils_i18n_gettext('User may create a new patron stat cat entry'));
INSERT INTO permission.perm_list VALUES 
    (59, 'CREATE_COPY_STAT_CAT_ENTRY', oils_i18n_gettext('User may create a new copy stat cat entry'));
INSERT INTO permission.perm_list VALUES 
    (60, 'UPDATE_PATRON_STAT_CAT', oils_i18n_gettext('User may update a patron stat cat'));
INSERT INTO permission.perm_list VALUES 
    (61, 'UPDATE_COPY_STAT_CAT', oils_i18n_gettext('User may update a copy stat cat'));
INSERT INTO permission.perm_list VALUES 
    (62, 'UPDATE_PATRON_STAT_CAT_ENTRY', oils_i18n_gettext('User may update a patron stat cat entry'));
INSERT INTO permission.perm_list VALUES 
    (63, 'UPDATE_COPY_STAT_CAT_ENTRY', oils_i18n_gettext('User may update a copy stat cat entry'));
INSERT INTO permission.perm_list VALUES 
    (65, 'CREATE_COPY_STAT_CAT_ENTRY_MAP', oils_i18n_gettext('User may link a copy to a stat cat entry'));
INSERT INTO permission.perm_list VALUES 
    (64, 'CREATE_PATRON_STAT_CAT_ENTRY_MAP', oils_i18n_gettext('User may link another user to a stat cat entry'));
INSERT INTO permission.perm_list VALUES 
    (66, 'DELETE_PATRON_STAT_CAT', oils_i18n_gettext('User may delete a patron stat cat'));
INSERT INTO permission.perm_list VALUES 
    (67, 'DELETE_COPY_STAT_CAT', oils_i18n_gettext('User may delete a copy stat cat'));
INSERT INTO permission.perm_list VALUES 
    (68, 'DELETE_PATRON_STAT_CAT_ENTRY', oils_i18n_gettext('User may delete a patron stat cat entry'));
INSERT INTO permission.perm_list VALUES 
    (69, 'DELETE_COPY_STAT_CAT_ENTRY', oils_i18n_gettext('User may delete a copy stat cat entry'));
INSERT INTO permission.perm_list VALUES 
    (70, 'DELETE_PATRON_STAT_CAT_ENTRY_MAP', oils_i18n_gettext('User may delete a patron stat cat entry map'));
INSERT INTO permission.perm_list VALUES 
    (71, 'DELETE_COPY_STAT_CAT_ENTRY_MAP', oils_i18n_gettext('User may delete a copy stat cat entry map'));
INSERT INTO permission.perm_list VALUES 
    (72, 'CREATE_NON_CAT_TYPE', oils_i18n_gettext('Allows a user to create a new non-cataloged item type'));
INSERT INTO permission.perm_list VALUES 
    (73, 'UPDATE_NON_CAT_TYPE', oils_i18n_gettext('Allows a user to update a non cataloged type'));
INSERT INTO permission.perm_list VALUES 
    (74, 'CREATE_IN_HOUSE_USE', oils_i18n_gettext('Allows a user to create a new in-house-use '));
INSERT INTO permission.perm_list VALUES 
    (75, 'COPY_CHECKOUT', oils_i18n_gettext('Allows a user to check out a copy'));
INSERT INTO permission.perm_list VALUES 
    (76, 'CREATE_COPY_LOCATION', oils_i18n_gettext('Allows a user to create a new copy location'));
INSERT INTO permission.perm_list VALUES 
    (77, 'UPDATE_COPY_LOCATION', oils_i18n_gettext('Allows a user to update a copy location'));
INSERT INTO permission.perm_list VALUES 
    (78, 'DELETE_COPY_LOCATION', oils_i18n_gettext('Allows a user to delete a copy location'));
INSERT INTO permission.perm_list VALUES 
    (79, 'CREATE_COPY_TRANSIT', oils_i18n_gettext('Allows a user to create a transit_copy object for transiting a copy'));
INSERT INTO permission.perm_list VALUES 
    (80, 'COPY_TRANSIT_RECEIVE', oils_i18n_gettext('Allows a user to close out a transit on a copy'));
INSERT INTO permission.perm_list VALUES 
    (81, 'VIEW_HOLD_PERMIT', oils_i18n_gettext('Allows a user to see if another user has permission to place a hold on a given copy'));
INSERT INTO permission.perm_list VALUES 
    (82, 'VIEW_COPY_CHECKOUT_HISTORY', oils_i18n_gettext('Allows a user to view which users have checked out a given copy'));
INSERT INTO permission.perm_list VALUES 
    (83, 'REMOTE_Z3950_QUERY', oils_i18n_gettext('Allows a user to perform z3950 queries against remote servers'));
INSERT INTO permission.perm_list VALUES 
    (84, 'REGISTER_WORKSTATION', oils_i18n_gettext('Allows a user to register a new workstation'));
INSERT INTO permission.perm_list VALUES 
    (85, 'VIEW_COPY_NOTES', oils_i18n_gettext('Allows a user to view all notes attached to a copy'));
INSERT INTO permission.perm_list VALUES 
    (86, 'VIEW_VOLUME_NOTES', oils_i18n_gettext('Allows a user to view all notes attached to a volume'));
INSERT INTO permission.perm_list VALUES 
    (87, 'VIEW_TITLE_NOTES', oils_i18n_gettext('Allows a user to view all notes attached to a title'));
INSERT INTO permission.perm_list VALUES 
    (89, 'CREATE_VOLUME_NOTE', oils_i18n_gettext('Allows a user to create a new volume note'));
INSERT INTO permission.perm_list VALUES 
    (88, 'CREATE_COPY_NOTE', oils_i18n_gettext('Allows a user to create a new copy note'));
INSERT INTO permission.perm_list VALUES 
    (90, 'CREATE_TITLE_NOTE', oils_i18n_gettext('Allows a user to create a new title note'));
INSERT INTO permission.perm_list VALUES 
    (91, 'DELETE_COPY_NOTE', oils_i18n_gettext('Allows a user to delete someone elses copy notes'));
INSERT INTO permission.perm_list VALUES 
    (92, 'DELETE_VOLUME_NOTE', oils_i18n_gettext('Allows a user to delete someone elses volume note'));
INSERT INTO permission.perm_list VALUES 
    (93, 'DELETE_TITLE_NOTE', oils_i18n_gettext('Allows a user to delete someone elses title note'));
INSERT INTO permission.perm_list VALUES 
    (94, 'UPDATE_CONTAINER', oils_i18n_gettext('Allows a user to update another users container'));
INSERT INTO permission.perm_list VALUES 
    (95, 'CREATE_MY_CONTAINER', oils_i18n_gettext('Allows a user to create a container for themselves'));
INSERT INTO permission.perm_list VALUES 
    (96, 'VIEW_HOLD_NOTIFICATION', oils_i18n_gettext('Allows a user to view notifications attached to a hold'));
INSERT INTO permission.perm_list VALUES 
    (97, 'CREATE_HOLD_NOTIFICATION', oils_i18n_gettext('Allows a user to create new hold notifications'));
INSERT INTO permission.perm_list VALUES 
    (98, 'UPDATE_ORG_SETTING', oils_i18n_gettext('Allows a user to update an org unit setting'));
INSERT INTO permission.perm_list VALUES 
    (99, 'OFFLINE_UPLOAD', oils_i18n_gettext('Allows a user to upload an offline script'));
INSERT INTO permission.perm_list VALUES 
    (100, 'OFFLINE_VIEW', oils_i18n_gettext('Allows a user to view uploaded offline script information'));
INSERT INTO permission.perm_list VALUES 
    (101, 'OFFLINE_EXECUTE', oils_i18n_gettext('Allows a user to execute an offline script batch'));
INSERT INTO permission.perm_list VALUES 
    (102, 'CIRC_OVERRIDE_DUE_DATE', oils_i18n_gettext('Allows a user to change set the due date on an item to any date'));
INSERT INTO permission.perm_list VALUES 
    (103, 'CIRC_PERMIT_OVERRIDE', oils_i18n_gettext('Allows a user to bypass the circ permit call for checkout'));
INSERT INTO permission.perm_list VALUES 
    (104, 'COPY_IS_REFERENCE.override', oils_i18n_gettext('Allows a user to override the copy_is_reference event'));
INSERT INTO permission.perm_list VALUES 
    (105, 'VOID_BILLING', oils_i18n_gettext('Allows a user to void a bill'));
INSERT INTO permission.perm_list VALUES 
    (106, 'CIRC_CLAIMS_RETURNED.override', oils_i18n_gettext('Allows a person to check in/out an item that is claims returned'));
INSERT INTO permission.perm_list VALUES 
    (107, 'COPY_BAD_STATUS.override', oils_i18n_gettext('Allows a user to check out an item in a non-circulatable status'));
INSERT INTO permission.perm_list VALUES 
    (108, 'COPY_ALERT_MESSAGE.override', oils_i18n_gettext('Allows a user to check in/out an item that has an alert message'));
INSERT INTO permission.perm_list VALUES 
    (109, 'COPY_STATUS_LOST.override', oils_i18n_gettext('Allows a user to remove the lost status from a copy'));
INSERT INTO permission.perm_list VALUES 
    (110, 'COPY_STATUS_MISSING.override', oils_i18n_gettext('Allows a user to change the missing status on a copy'));
INSERT INTO permission.perm_list VALUES 
    (111, 'ABORT_TRANSIT', oils_i18n_gettext('Allows a user to abort a copy transit if the user is at the transit destination or source'));
INSERT INTO permission.perm_list VALUES 
    (112, 'ABORT_REMOTE_TRANIST', oils_i18n_gettext('Allows a user to abort a copy transit if the user is not at the transit source or dest'));
INSERT INTO permission.perm_list VALUES 
    (113, 'VIEW_ZIP_DATA', oils_i18n_gettext('Allowsa user to query the zip code data method'));
INSERT INTO permission.perm_list VALUES 
    (114, 'CANCEL_HOLDS', oils_i18n_gettext(''));
INSERT INTO permission.perm_list VALUES 
    (115, 'CREATE_DUPLICATE_HOLDS', oils_i18n_gettext('Allows a user to create duplicate holds (e.g. two holds on the same title)'));
INSERT INTO permission.perm_list VALUES 
    (117, 'actor.org_unit.closed_date.update', oils_i18n_gettext('Allows a user to update a closed date interval for a given location'));
INSERT INTO permission.perm_list VALUES 
    (116, 'actor.org_unit.closed_date.delete', oils_i18n_gettext('Allows a user to remove a closed date interval for a given location'));
INSERT INTO permission.perm_list VALUES 
    (118, 'actor.org_unit.closed_date.create', oils_i18n_gettext('Allows a user to create a new closed date for a location'));
INSERT INTO permission.perm_list VALUES 
    (119, 'DELETE_NON_CAT_TYPE', oils_i18n_gettext('Allows a user to delete a non cataloged type'));
INSERT INTO permission.perm_list VALUES 
    (120, 'money.collections_tracker.create', oils_i18n_gettext('Allows a user to put someone into collections'));
INSERT INTO permission.perm_list VALUES 
    (121, 'money.collections_tracker.delete', oils_i18n_gettext('Allows a user to remove someone from collections'));
INSERT INTO permission.perm_list VALUES 
    (122, 'BAR_PATRON', oils_i18n_gettext('Allows a user to bar a patron'));
INSERT INTO permission.perm_list VALUES 
    (123, 'UNBAR_PATRON', oils_i18n_gettext('Allows a user to un-bar a patron'));
INSERT INTO permission.perm_list VALUES 
    (124, 'DELETE_WORKSTATION', oils_i18n_gettext('Allows a user to remove an existing workstation so a new one can replace it'));
INSERT INTO permission.perm_list VALUES 
    (125, 'group_application.user', oils_i18n_gettext('Allows a user to add/remove users to/from the "User" group'));
INSERT INTO permission.perm_list VALUES 
    (126, 'group_application.user.patron', oils_i18n_gettext('Allows a user to add/remove users to/from the "Patron" group'));
INSERT INTO permission.perm_list VALUES 
    (127, 'group_application.user.staff', oils_i18n_gettext('Allows a user to add/remove users to/from the "Staff" group'));
INSERT INTO permission.perm_list VALUES 
    (128, 'group_application.user.staff.circ', oils_i18n_gettext('Allows a user to add/remove users to/from the "Circulator" group'));
INSERT INTO permission.perm_list VALUES 
    (129, 'group_application.user.staff.cat', oils_i18n_gettext('Allows a user to add/remove users to/from the "Cataloger" group'));
INSERT INTO permission.perm_list VALUES 
    (130, 'group_application.user.staff.admin.global_admin', oils_i18n_gettext('Allows a user to add/remove users to/from the "GlobalAdmin" group'));
INSERT INTO permission.perm_list VALUES 
    (131, 'group_application.user.staff.admin.local_admin', oils_i18n_gettext('Allows a user to add/remove users to/from the "LocalAdmin" group'));
INSERT INTO permission.perm_list VALUES 
    (132, 'group_application.user.staff.admin.lib_manager', oils_i18n_gettext('Allows a user to add/remove users to/from the "LibraryManager" group'));
INSERT INTO permission.perm_list VALUES 
    (133, 'group_application.user.staff.cat.cat1', oils_i18n_gettext('Allows a user to add/remove users to/from the "Cat1" group'));
INSERT INTO permission.perm_list VALUES 
    (134, 'group_application.user.staff.supercat', oils_i18n_gettext('Allows a user to add/remove users to/from the "Supercat" group'));
INSERT INTO permission.perm_list VALUES 
    (135, 'group_application.user.sip_client', oils_i18n_gettext('Allows a user to add/remove users to/from the "SIP-Client" group'));
INSERT INTO permission.perm_list VALUES 
    (136, 'group_application.user.vendor', oils_i18n_gettext('Allows a user to add/remove users to/from the "Vendor" group'));
INSERT INTO permission.perm_list VALUES 
    (137, 'ITEM_AGE_PROTECTED.override', oils_i18n_gettext('Allows a user to place a hold on an age-protected item'));
INSERT INTO permission.perm_list VALUES 
    (138, 'MAX_RENEWALS_REACHED.override', oils_i18n_gettext('Allows a user to renew an item past the maximun renewal count'));
INSERT INTO permission.perm_list VALUES 
    (139, 'PATRON_EXCEEDS_CHECKOUT_COUNT.override', oils_i18n_gettext('Allow staff to override checkout count failure'));
INSERT INTO permission.perm_list VALUES 
    (140, 'PATRON_EXCEEDS_OVERDUE_COUNT.override', oils_i18n_gettext('Allow staff to override overdue count failure'));
INSERT INTO permission.perm_list VALUES 
    (141, 'PATRON_EXCEEDS_FINES.override', oils_i18n_gettext('Allow staff to override fine amount checkout failure'));
INSERT INTO permission.perm_list VALUES 
    (142, 'CIRC_EXCEEDS_COPY_RANGE.override', oils_i18n_gettext(''));
INSERT INTO permission.perm_list VALUES 
    (143, 'ITEM_ON_HOLDS_SHELF.override', oils_i18n_gettext(''));
INSERT INTO permission.perm_list VALUES 
    (144, 'COPY_NOT_AVAILABLE.override', oils_i18n_gettext('Allow staff to force checkout of Missing/Lost type items'));
INSERT INTO permission.perm_list VALUES 
    (146, 'HOLD_EXISTS.override', oils_i18n_gettext('allows users to place multiple holds on a single title'));
INSERT INTO permission.perm_list VALUES 
    (147, 'RUN_REPORTS', oils_i18n_gettext('Allows a users to run reports'));
INSERT INTO permission.perm_list VALUES 
    (148, 'SHARE_REPORT_FOLDER', oils_i18n_gettext('Allows a user to share report his own folders'));
INSERT INTO permission.perm_list VALUES 
    (149, 'VIEW_REPORT_OUTPUT', oils_i18n_gettext('Allow user to view report output'));
INSERT INTO permission.perm_list VALUES 
    (150, 'COPY_CIRC_NOT_ALLOWED.override', oils_i18n_gettext('Allows a user to checkout an item that is marked as non-circ'));
INSERT INTO permission.perm_list VALUES 
    (151, 'DELETE_CONTAINER_ITEM', oils_i18n_gettext('Allows a user to delete an item out of another user''s container'));
INSERT INTO permission.perm_list VALUES 
    (152, 'ASSIGN_WORK_ORG_UNIT', oils_i18n_gettext('Allow a staff member to define where another staff member has their permissions'));

SELECT SETVAL('permission.perm_list_id_seq'::TEXT, (SELECT MAX(id) FROM permission.perm_list));

INSERT INTO permission.perm_list (code) VALUES ('ASSIGN_GROUP_PERM');
INSERT INTO permission.perm_list (code) VALUES ('CREATE_AUDIENCE');
INSERT INTO permission.perm_list (code) VALUES ('CREATE_BIB_LEVEL');
INSERT INTO permission.perm_list (code) VALUES ('CREATE_CIRC_DURATION');
INSERT INTO permission.perm_list (code) VALUES ('CREATE_CIRC_MOD');
INSERT INTO permission.perm_list (code) VALUES ('CREATE_COPY_STATUS');
INSERT INTO permission.perm_list (code) VALUES ('CREATE_HOURS_OF_OPERATION');
INSERT INTO permission.perm_list (code) VALUES ('CREATE_ITEM_FORM');
INSERT INTO permission.perm_list (code) VALUES ('CREATE_ITEM_TYPE');
INSERT INTO permission.perm_list (code) VALUES ('CREATE_LANGUAGE');
INSERT INTO permission.perm_list (code) VALUES ('CREATE_LASSO');
INSERT INTO permission.perm_list (code) VALUES ('CREATE_LASSO_MAP');
INSERT INTO permission.perm_list (code) VALUES ('CREATE_LIT_FORM');
INSERT INTO permission.perm_list (code) VALUES ('CREATE_METABIB_FIELD');
INSERT INTO permission.perm_list (code) VALUES ('CREATE_NET_ACCESS_LEVEL');
INSERT INTO permission.perm_list (code) VALUES ('CREATE_ORG_ADDRESS');
INSERT INTO permission.perm_list (code) VALUES ('CREATE_ORG_TYPE');
INSERT INTO permission.perm_list (code) VALUES ('CREATE_ORG_UNIT');
INSERT INTO permission.perm_list (code) VALUES ('CREATE_ORG_UNIT_CLOSING');
INSERT INTO permission.perm_list (code) VALUES ('CREATE_PERM');
INSERT INTO permission.perm_list (code) VALUES ('CREATE_RELEVANCE_ADJUSTMENT');
INSERT INTO permission.perm_list (code) VALUES ('CREATE_SURVEY');
INSERT INTO permission.perm_list (code) VALUES ('CREATE_VR_FORMAT');
INSERT INTO permission.perm_list (code) VALUES ('CREATE_XML_TRANSFORM');
INSERT INTO permission.perm_list (code) VALUES ('DELETE_AUDIENCE');
INSERT INTO permission.perm_list (code) VALUES ('DELETE_BIB_LEVEL');
INSERT INTO permission.perm_list (code) VALUES ('DELETE_CIRC_DURATION');
INSERT INTO permission.perm_list (code) VALUES ('DELETE_CIRC_MOD');
INSERT INTO permission.perm_list (code) VALUES ('DELETE_COPY_STATUS');
INSERT INTO permission.perm_list (code) VALUES ('DELETE_HOURS_OF_OPERATION');
INSERT INTO permission.perm_list (code) VALUES ('DELETE_ITEM_FORM');
INSERT INTO permission.perm_list (code) VALUES ('DELETE_ITEM_TYPE');
INSERT INTO permission.perm_list (code) VALUES ('DELETE_LANGUAGE');
INSERT INTO permission.perm_list (code) VALUES ('DELETE_LASSO');
INSERT INTO permission.perm_list (code) VALUES ('DELETE_LASSO_MAP');
INSERT INTO permission.perm_list (code) VALUES ('DELETE_LIT_FORM');
INSERT INTO permission.perm_list (code) VALUES ('DELETE_METABIB_FIELD');
INSERT INTO permission.perm_list (code) VALUES ('DELETE_NET_ACCESS_LEVEL');
INSERT INTO permission.perm_list (code) VALUES ('DELETE_ORG_ADDRESS');
INSERT INTO permission.perm_list (code) VALUES ('DELETE_ORG_TYPE');
INSERT INTO permission.perm_list (code) VALUES ('DELETE_ORG_UNIT');
INSERT INTO permission.perm_list (code) VALUES ('DELETE_ORG_UNIT_CLOSING');
INSERT INTO permission.perm_list (code) VALUES ('DELETE_PERM');
INSERT INTO permission.perm_list (code) VALUES ('DELETE_RELEVANCE_ADJUSTMENT');
INSERT INTO permission.perm_list (code) VALUES ('DELETE_SURVEY');
INSERT INTO permission.perm_list (code) VALUES ('DELETE_TRANSIT');
INSERT INTO permission.perm_list (code) VALUES ('DELETE_VR_FORMAT');
INSERT INTO permission.perm_list (code) VALUES ('DELETE_XML_TRANSFORM');
INSERT INTO permission.perm_list (code) VALUES ('REMOVE_GROUP_PERM');
INSERT INTO permission.perm_list (code) VALUES ('TRANSIT_COPY');
INSERT INTO permission.perm_list (code) VALUES ('UPDATE_AUDIENCE');
INSERT INTO permission.perm_list (code) VALUES ('UPDATE_BIB_LEVEL');
INSERT INTO permission.perm_list (code) VALUES ('UPDATE_CIRC_DURATION');
INSERT INTO permission.perm_list (code) VALUES ('UPDATE_CIRC_MOD');
INSERT INTO permission.perm_list (code) VALUES ('UPDATE_COPY_NOTE');
INSERT INTO permission.perm_list (code) VALUES ('UPDATE_COPY_STATUS');
INSERT INTO permission.perm_list (code) VALUES ('UPDATE_GROUP_PERM');
INSERT INTO permission.perm_list (code) VALUES ('UPDATE_HOURS_OF_OPERATION');
INSERT INTO permission.perm_list (code) VALUES ('UPDATE_ITEM_FORM');
INSERT INTO permission.perm_list (code) VALUES ('UPDATE_ITEM_TYPE');
INSERT INTO permission.perm_list (code) VALUES ('UPDATE_LANGUAGE');
INSERT INTO permission.perm_list (code) VALUES ('UPDATE_LASSO');
INSERT INTO permission.perm_list (code) VALUES ('UPDATE_LASSO_MAP');
INSERT INTO permission.perm_list (code) VALUES ('UPDATE_LIT_FORM');
INSERT INTO permission.perm_list (code) VALUES ('UPDATE_METABIB_FIELD');
INSERT INTO permission.perm_list (code) VALUES ('UPDATE_NET_ACCESS_LEVEL');
INSERT INTO permission.perm_list (code) VALUES ('UPDATE_ORG_ADDRESS');
INSERT INTO permission.perm_list (code) VALUES ('UPDATE_ORG_TYPE');
INSERT INTO permission.perm_list (code) VALUES ('UPDATE_ORG_UNIT_CLOSING');
INSERT INTO permission.perm_list (code) VALUES ('UPDATE_PERM');
INSERT INTO permission.perm_list (code) VALUES ('UPDATE_RELEVANCE_ADJUSTMENT');
INSERT INTO permission.perm_list (code) VALUES ('UPDATE_SURVEY');
INSERT INTO permission.perm_list (code) VALUES ('UPDATE_TRANSIT');
INSERT INTO permission.perm_list (code) VALUES ('UPDATE_VOLUME_NOTE');
INSERT INTO permission.perm_list (code) VALUES ('UPDATE_VR_FORMAT');
INSERT INTO permission.perm_list (code) VALUES ('UPDATE_XML_TRANSFORM');
INSERT INTO permission.perm_list (code) VALUES ('MERGE_BIB_RECORDS');


INSERT INTO permission.grp_tree (id, name, parent, description, perm_interval, usergroup, application_perm) VALUES
	(1, 'Users', NULL, NULL, '3 years', FALSE, 'group_application.user');
INSERT INTO permission.grp_tree (id, name, parent, description, perm_interval, usergroup, application_perm) VALUES
	(2, 'Patrons', 1, NULL, '3 years', TRUE, 'group_application.user.patron');
INSERT INTO permission.grp_tree (id, name, parent, description, perm_interval, usergroup, application_perm) VALUES
	(3, 'Staff', 1, NULL, '3 years', FALSE, 'group_application.user.staff');
INSERT INTO permission.grp_tree (id, name, parent, description, perm_interval, usergroup, application_perm) VALUES
	(4, 'Catalogers', 3, NULL, '3 years', TRUE, 'group_application.user.staff.cat');
INSERT INTO permission.grp_tree (id, name, parent, description, perm_interval, usergroup, application_perm) VALUES
	(5, 'Circulators', 3, NULL, '3 years', TRUE, 'group_application.user.staff.circ');
INSERT INTO permission.grp_tree (id, name, parent, description, perm_interval, usergroup, application_perm) VALUES
	(10, 'Local System Administrator', 3, 'System maintenance, configuration, etc.', '3 years', TRUE, 'group_application.user.staff.admin.local_admin');

SELECT SETVAL('permission.grp_tree_id_seq'::TEXT, (SELECT MAX(id) FROM permission.grp_tree));

-- XXX Incomplete base permission setup.  A patch would be appreciated.
INSERT INTO permission.grp_perm_map VALUES (57, 2, 15, 0, false);
INSERT INTO permission.grp_perm_map VALUES (109, 2, 95, 0, false);
INSERT INTO permission.grp_perm_map VALUES (1, 1, 2, 0, false);
INSERT INTO permission.grp_perm_map VALUES (12, 1, 5, 0, false);
INSERT INTO permission.grp_perm_map VALUES (13, 1, 6, 0, false);
INSERT INTO permission.grp_perm_map VALUES (51, 1, 32, 0, false);
INSERT INTO permission.grp_perm_map VALUES (111, 1, 95, 0, false);
INSERT INTO permission.grp_perm_map VALUES (11, 3, 4, 0, false);
INSERT INTO permission.grp_perm_map VALUES (14, 3, 7, 2, false);
INSERT INTO permission.grp_perm_map VALUES (16, 3, 9, 0, false);
INSERT INTO permission.grp_perm_map VALUES (19, 3, 15, 0, false);
INSERT INTO permission.grp_perm_map VALUES (20, 3, 16, 0, false);
INSERT INTO permission.grp_perm_map VALUES (21, 3, 17, 0, false);
INSERT INTO permission.grp_perm_map VALUES (116, 3, 18, 0, false);
INSERT INTO permission.grp_perm_map VALUES (117, 3, 20, 0, false);
INSERT INTO permission.grp_perm_map VALUES (118, 3, 21, 2, false);
INSERT INTO permission.grp_perm_map VALUES (119, 3, 22, 2, false);
INSERT INTO permission.grp_perm_map VALUES (120, 3, 23, 2, false);
INSERT INTO permission.grp_perm_map VALUES (121, 3, 25, 2, false);
INSERT INTO permission.grp_perm_map VALUES (26, 3, 27, 0, false);
INSERT INTO permission.grp_perm_map VALUES (27, 3, 28, 0, false);
INSERT INTO permission.grp_perm_map VALUES (28, 3, 29, 0, false);
INSERT INTO permission.grp_perm_map VALUES (29, 3, 30, 0, false);
INSERT INTO permission.grp_perm_map VALUES (44, 3, 31, 0, false);
INSERT INTO permission.grp_perm_map VALUES (31, 3, 33, 0, false);
INSERT INTO permission.grp_perm_map VALUES (32, 3, 34, 0, false);
INSERT INTO permission.grp_perm_map VALUES (33, 3, 35, 0, false);
INSERT INTO permission.grp_perm_map VALUES (41, 3, 36, 0, false);
INSERT INTO permission.grp_perm_map VALUES (45, 3, 37, 0, false);
INSERT INTO permission.grp_perm_map VALUES (46, 3, 38, 0, false);
INSERT INTO permission.grp_perm_map VALUES (47, 3, 39, 0, false);
INSERT INTO permission.grp_perm_map VALUES (122, 3, 41, 0, false);
INSERT INTO permission.grp_perm_map VALUES (123, 3, 43, 0, false);
INSERT INTO permission.grp_perm_map VALUES (60, 3, 44, 0, false);
INSERT INTO permission.grp_perm_map VALUES (110, 3, 45, 0, false);
INSERT INTO permission.grp_perm_map VALUES (124, 3, 8, 2, false);
INSERT INTO permission.grp_perm_map VALUES (125, 3, 24, 2, false);
INSERT INTO permission.grp_perm_map VALUES (126, 3, 19, 0, false);
INSERT INTO permission.grp_perm_map VALUES (61, 3, 47, 2, false);
INSERT INTO permission.grp_perm_map VALUES (95, 3, 48, 0, false);
INSERT INTO permission.grp_perm_map VALUES (17, 3, 11, 0, false);
INSERT INTO permission.grp_perm_map VALUES (62, 3, 42, 0, false);
INSERT INTO permission.grp_perm_map VALUES (63, 3, 49, 0, false);
INSERT INTO permission.grp_perm_map VALUES (64, 3, 50, 0, false);
INSERT INTO permission.grp_perm_map VALUES (127, 3, 53, 0, false);
INSERT INTO permission.grp_perm_map VALUES (65, 3, 54, 0, false);
INSERT INTO permission.grp_perm_map VALUES (128, 3, 55, 2, false);
INSERT INTO permission.grp_perm_map VALUES (67, 3, 56, 2, false);
INSERT INTO permission.grp_perm_map VALUES (68, 3, 57, 2, false);
INSERT INTO permission.grp_perm_map VALUES (69, 3, 58, 2, false);
INSERT INTO permission.grp_perm_map VALUES (70, 3, 59, 2, false);
INSERT INTO permission.grp_perm_map VALUES (71, 3, 60, 2, false);
INSERT INTO permission.grp_perm_map VALUES (72, 3, 61, 2, false);
INSERT INTO permission.grp_perm_map VALUES (73, 3, 62, 2, false);
INSERT INTO permission.grp_perm_map VALUES (74, 3, 63, 2, false);
INSERT INTO permission.grp_perm_map VALUES (81, 3, 72, 2, false);
INSERT INTO permission.grp_perm_map VALUES (82, 3, 73, 2, false);
INSERT INTO permission.grp_perm_map VALUES (83, 3, 74, 2, false);
INSERT INTO permission.grp_perm_map VALUES (84, 3, 75, 0, false);
INSERT INTO permission.grp_perm_map VALUES (85, 3, 76, 2, false);
INSERT INTO permission.grp_perm_map VALUES (86, 3, 77, 2, false);
INSERT INTO permission.grp_perm_map VALUES (89, 3, 79, 0, false);
INSERT INTO permission.grp_perm_map VALUES (90, 3, 80, 0, false);
INSERT INTO permission.grp_perm_map VALUES (91, 3, 81, 0, false);
INSERT INTO permission.grp_perm_map VALUES (92, 3, 82, 0, false);
INSERT INTO permission.grp_perm_map VALUES (98, 3, 83, 0, false);
INSERT INTO permission.grp_perm_map VALUES (115, 3, 84, 0, false);
INSERT INTO permission.grp_perm_map VALUES (100, 3, 85, 0, false);
INSERT INTO permission.grp_perm_map VALUES (101, 3, 86, 0, false);
INSERT INTO permission.grp_perm_map VALUES (102, 3, 87, 0, false);
INSERT INTO permission.grp_perm_map VALUES (103, 3, 89, 2, false);
INSERT INTO permission.grp_perm_map VALUES (104, 3, 88, 2, false);
INSERT INTO permission.grp_perm_map VALUES (108, 3, 94, 0, false);
INSERT INTO permission.grp_perm_map VALUES (112, 3, 96, 0, false);
INSERT INTO permission.grp_perm_map VALUES (113, 3, 97, 0, false);
INSERT INTO permission.grp_perm_map VALUES (130, 3, 99, 1, false);
INSERT INTO permission.grp_perm_map VALUES (131, 3, 100, 1, false);
INSERT INTO permission.grp_perm_map VALUES (22, 4, 18, 0, false);
INSERT INTO permission.grp_perm_map VALUES (24, 4, 20, 0, false);
INSERT INTO permission.grp_perm_map VALUES (38, 4, 21, 2, false);
INSERT INTO permission.grp_perm_map VALUES (34, 4, 22, 2, false);
INSERT INTO permission.grp_perm_map VALUES (39, 4, 23, 2, false);
INSERT INTO permission.grp_perm_map VALUES (35, 4, 25, 2, false);
INSERT INTO permission.grp_perm_map VALUES (129, 4, 26, 2, false);
INSERT INTO permission.grp_perm_map VALUES (15, 4, 8, 2, false);
INSERT INTO permission.grp_perm_map VALUES (40, 4, 24, 2, false);
INSERT INTO permission.grp_perm_map VALUES (23, 4, 19, 0, false);
INSERT INTO permission.grp_perm_map VALUES (66, 4, 55, 2, false);
INSERT INTO permission.grp_perm_map VALUES (134, 10, 51, 1, false);
INSERT INTO permission.grp_perm_map VALUES (75, 10, 66, 2, false);
INSERT INTO permission.grp_perm_map VALUES (76, 10, 67, 2, false);
INSERT INTO permission.grp_perm_map VALUES (77, 10, 68, 2, false);
INSERT INTO permission.grp_perm_map VALUES (78, 10, 69, 2, false);
INSERT INTO permission.grp_perm_map VALUES (79, 10, 70, 2, false);
INSERT INTO permission.grp_perm_map VALUES (80, 10, 71, 2, false);
INSERT INTO permission.grp_perm_map VALUES (87, 10, 78, 2, false);
INSERT INTO permission.grp_perm_map VALUES (105, 10, 91, 1, false);
INSERT INTO permission.grp_perm_map VALUES (106, 10, 92, 1, false);
INSERT INTO permission.grp_perm_map VALUES (107, 10, 93, 0, false);
INSERT INTO permission.grp_perm_map VALUES (114, 10, 98, 1, false);
INSERT INTO permission.grp_perm_map VALUES (132, 10, 101, 1, true);
INSERT INTO permission.grp_perm_map VALUES (136, 10, 102, 1, false);
INSERT INTO permission.grp_perm_map VALUES (137, 10, 103, 1, false);
INSERT INTO permission.grp_perm_map VALUES (97, 5, 41, 0, false);
INSERT INTO permission.grp_perm_map VALUES (96, 5, 43, 0, false);
INSERT INTO permission.grp_perm_map VALUES (93, 5, 48, 0, false);
INSERT INTO permission.grp_perm_map VALUES (94, 5, 53, 0, false);
INSERT INTO permission.grp_perm_map VALUES (133, 5, 102, 0, false);
INSERT INTO permission.grp_perm_map VALUES (138, 5, 104, 1, false);

SELECT SETVAL('permission.grp_perm_map_id_seq'::TEXT, (SELECT MAX(id) FROM permission.grp_perm_map));

-- Admin user account
INSERT INTO actor.usr ( profile, card, usrname, passwd, first_given_name, family_name, dob, master_account, super_user, ident_type, ident_value, home_ou ) VALUES ( 1, 1, 'admin', 'open-ils', oils_i18n_gettext('Administrator'), oils_i18n_gettext('System Account'), '1979-01-22', TRUE, TRUE, 1, 'identification', 1 );

-- Admin user barcode
INSERT INTO actor.card (usr, barcode) VALUES (1,'101010101010101');
UPDATE actor.usr SET card = (SELECT id FROM actor.card WHERE barcode = '101010101010101') WHERE id = 1;

-- Admin user permissions
INSERT INTO permission.usr_perm_map (usr,perm,depth) VALUES (1,-1,0);

--010.schema.biblio.sql:
INSERT INTO biblio.record_entry VALUES (-1,1,1,1,-1,NOW(),NOW(),FALSE,FALSE,'','AUTOGEN','-1','','FOO');

--040.schema.asset.sql:
INSERT INTO asset.copy_location (name,owning_lib) VALUES (oils_i18n_gettext('Stacks'),1);
INSERT INTO asset.call_number VALUES (-1,1,NOW(),1,NOW(),-1,1,'UNCATALOGED');

-- some more from 002.schema.config.sql:
INSERT INTO config.xml_transform VALUES ( 'marcxml', 'http://www.loc.gov/MARC21/slim', 'marc', '---' );
INSERT INTO config.xml_transform VALUES ( 'mods', 'http://www.loc.gov/mods/', 'mods', '');
INSERT INTO config.xml_transform VALUES ( 'mods3', 'http://www.loc.gov/mods/v3', 'mods3', '');
INSERT INTO config.xml_transform VALUES ( 'mods32', 'http://www.loc.gov/mods/v3', 'mods32', '');

-- circ matrix
INSERT INTO config.circ_matrix_matchpoint (org_unit,grp) VALUES (1,1);
INSERT INTO config.circ_matrix_ruleset (matchpoint,duration_rule,recurring_fine_rule,max_fine_rule) VALUES (1,11,1,1);


-- hold matrix - 110.hold_matrix.sql:
INSERT INTO config.hold_matrix_matchpoint (requestor_grp) VALUES (1);

-- Staged Search (for default matchpoints)
INSERT INTO search.relevance_adjustment (field, bump_type, multiplier) VALUES(1, 'first_word', 1.5);
INSERT INTO search.relevance_adjustment (field, bump_type, multiplier) VALUES(1, 'full_match', 20);
INSERT INTO search.relevance_adjustment (field, bump_type, multiplier) VALUES(2, 'first_word', 1.5);
INSERT INTO search.relevance_adjustment (field, bump_type, multiplier) VALUES(2, 'word_order', 10);
INSERT INTO search.relevance_adjustment (field, bump_type, multiplier) VALUES(2, 'full_match', 20);
INSERT INTO search.relevance_adjustment (field, bump_type, multiplier) VALUES(3, 'first_word', 1.5);
INSERT INTO search.relevance_adjustment (field, bump_type, multiplier) VALUES(3, 'word_order', 10);
INSERT INTO search.relevance_adjustment (field, bump_type, multiplier) VALUES(3, 'full_match', 20);
INSERT INTO search.relevance_adjustment (field, bump_type, multiplier) VALUES(4, 'first_word', 1.5);
INSERT INTO search.relevance_adjustment (field, bump_type, multiplier) VALUES(4, 'word_order', 10);
INSERT INTO search.relevance_adjustment (field, bump_type, multiplier) VALUES(4, 'full_match', 20);
INSERT INTO search.relevance_adjustment (field, bump_type, multiplier) VALUES(5, 'first_word', 1.5);
INSERT INTO search.relevance_adjustment (field, bump_type, multiplier) VALUES(5, 'word_order', 10);
INSERT INTO search.relevance_adjustment (field, bump_type, multiplier) VALUES(5, 'full_match', 20);
INSERT INTO search.relevance_adjustment (field, bump_type, multiplier) VALUES(6, 'first_word', 1.5);
INSERT INTO search.relevance_adjustment (field, bump_type, multiplier) VALUES(7, 'first_word', 1.5);
INSERT INTO search.relevance_adjustment (field, bump_type, multiplier) VALUES(8, 'first_word', 1.5);
INSERT INTO search.relevance_adjustment (field, bump_type, multiplier) VALUES(9, 'first_word', 1.5);
INSERT INTO search.relevance_adjustment (field, bump_type, multiplier) VALUES(14, 'word_order', 10);

