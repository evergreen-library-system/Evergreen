--002.schema.config.sql:
INSERT INTO config.bib_source (quality, source, transcendant) VALUES 
    (90, oils_i18n_gettext('oclc'), FALSE),
    (10, oils_i18n_gettext('System Local'), FALSE),
    (1, oils_i18n_gettext('Project Gutenberg'), TRUE);

INSERT INTO config.standing (value) VALUES (oils_i18n_gettext('Good'));
INSERT INTO config.standing (value) VALUES (oils_i18n_gettext('Barred'));

INSERT INTO config.xml_transform VALUES ( 'marcxml', 'http://www.loc.gov/MARC21/slim', 'marc', '---' );
INSERT INTO config.xml_transform VALUES ( 'mods', 'http://www.loc.gov/mods/', 'mods', '/home/miker/MARC21slim2MODS.xsl' );

INSERT INTO config.metabib_field ( field_class, name, xpath ) VALUES 
    ( 'series', 'seriestitle', $$//mods:mods/mods:relatedItem[@type="series"]/mods:titleInfo$$ ),
    ( 'title', 'abbreviated', $$//mods:mods/mods:titleInfo[mods:title and (@type='abbreviated')]$$ ),
    ( 'title', 'translated', $$//mods:mods/mods:titleInfo[mods:title and (@type='translated')]$$ ),
    ( 'title', 'uniform', $$//mods:mods/mods:titleInfo[mods:title and (@type='uniform')]$$ ),
    ( 'title', 'proper', $$//mods:mods/mods:titleInfo[mods:title and not (@type)]$$ ),
    ( 'author', 'corporate', $$//mods:mods/mods:name[@type='corporate']/mods:namePart[../mods:role/mods:text[text()='creator']]$$ ),
    ( 'author', 'personal', $$//mods:mods/mods:name[@type='personal']/mods:namePart[../mods:role/mods:text[text()='creator']]$$ ),
    ( 'author', 'conference', $$//mods:mods/mods:name[@type='conference']/mods:namePart[../mods:role/mods:text[text()='creator']]$$ ),
    ( 'author', 'other', $$//mods:mods/mods:name[@type='personal']/mods:namePart[not(../mods:role)]$$ ),
    ( 'subject', 'geographic', $$//mods:mods/mods:subject/mods:geographic$$ ),
    ( 'subject', 'name', $$//mods:mods/mods:subject/mods:name$$ ),
    ( 'subject', 'temporal', $$//mods:mods/mods:subject/mods:temporal$$ ),
    ( 'subject', 'topic', $$//mods:mods/mods:subject/mods:topic$$ ),
--  ( field_class, name, xpath ) VALUES ( 'subject', 'genre', $$//mods:mods/mods:genre$$ ),
    ( 'keyword', 'keyword', $$//mods:mods/*[not(local-name()='originInfo')]$$ ); -- /* to fool vim */

INSERT INTO config.audience_map (code, value, description) VALUES 
    ('', oils_i18n_gettext('Unknown or unspecified'), oils_i18n_gettext('The target audience for the item not known or not specified.')),
    ('a', oils_i18n_gettext('Preschool'), oils_i18n_gettext('The item is intended for children, approximate ages 0-5 years.')),
    ('b', oils_i18n_gettext('Primary'), oils_i18n_gettext('The item is intended for children, approximate ages 6-8 years.')),
    ('c', oils_i18n_gettext('Pre-adolescent'), oils_i18n_gettext('The item is intended for young people, approximate ages 9-13 years.')),
    ('d', oils_i18n_gettext('Adolescent'), oils_i18n_gettext('The item is intended for young people, approximate ages 14-17 years.')),
    ('e', oils_i18n_gettext('Adult'), oils_i18n_gettext('The item is intended for adults.')),
    ('f', oils_i18n_gettext('Specialized'), oils_i18n_gettext('The item is aimed at a particular audience and the nature of the presentation makes the item of little interest to another audience.')),
    ('g', oils_i18n_gettext('General'), oils_i18n_gettext('The item is of general interest and not aimed at an audience of a particular intellectual level.')),
    ('j', oils_i18n_gettext('Juvenile'), oils_i18n_gettext('The item is intended for children and young people, approximate ages 0-15 years.'));

-- Admin user
INSERT INTO permission.usr_perm_map (usr,perm,depth) VALUES (1,-1,0);

--010.schema.biblio.sql:
INSERT INTO biblio.record_entry VALUES (-1,1,1,1,-1,NOW(),NOW(),FALSE,FALSE,'','AUTOGEN','-1','','FOO');

--040.schema.asset.sql:
INSERT INTO asset.copy_location (name,owning_lib) VALUES (oils_i18n_gettext('Stacks'),1);
INSERT INTO asset.call_number VALUES (-1,1,NOW(),1,NOW(),-1,1,'UNCATALOGED');
