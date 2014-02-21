BEGIN;

SELECT evergreen.upgrade_deps_block_check('0867', :eg_version);

INSERT INTO config.global_flag (name, label, value, enabled) VALUES (
    'opac.metarecord.holds.format_attr', 
    oils_i18n_gettext(
        'opac.metarecord.holds.format_attr',
        'OPAC Metarecord Hold Formats Attribute', 
        'cgf',
        'label'
    ),
    'mr_hold_format', 
    TRUE
);

-- until we have a custom attribute for the selector, 
-- default to the icon_format attribute
INSERT INTO config.global_flag (name, label, value, enabled) VALUES (
    'opac.format_selector.attr', 
    oils_i18n_gettext(
        'opac.format_selector.attr', 
        'OPAC Format Selector Attribute', 
        'cgf',
        'label'
    ),
    'icon_format', 
    TRUE
);


INSERT INTO config.record_attr_definition 
    (name, label, multi, filter, composite) 
VALUES (
    'mr_hold_format', 
    oils_i18n_gettext(
        'mr_hold_format',
        'Metarecord Hold Formats', 
        'crad',
        'label'
    ),
    TRUE, TRUE, TRUE
);

-- these formats are a subset of the "icon_format" attribute,
-- modified to exclude electronic resources, which are not holdable

-- for i18n purposes, these have to be listed individually
INSERT INTO config.coded_value_map
    (id, ctype, code, value, search_label) VALUES 
(588, 'mr_hold_format', 'book', 
    oils_i18n_gettext(588, 'Book', 'ccvm', 'value'),
    oils_i18n_gettext(588, 'Book', 'ccvm', 'search_label')),
(589, 'mr_hold_format', 'braille', 
    oils_i18n_gettext(589, 'Braille', 'ccvm', 'value'),
    oils_i18n_gettext(589, 'Braille', 'ccvm', 'search_label')),
(590, 'mr_hold_format', 'software', 
    oils_i18n_gettext(590, 'Software and video games', 'ccvm', 'value'),
    oils_i18n_gettext(590, 'Software and video games', 'ccvm', 'search_label')),
(591, 'mr_hold_format', 'dvd', 
    oils_i18n_gettext(591, 'DVD', 'ccvm', 'value'),
    oils_i18n_gettext(591, 'DVD', 'ccvm', 'search_label')),
(592, 'mr_hold_format', 'kit', 
    oils_i18n_gettext(592, 'Kit', 'ccvm', 'value'),
    oils_i18n_gettext(592, 'Kit', 'ccvm', 'search_label')),
(593, 'mr_hold_format', 'map', 
    oils_i18n_gettext(593, 'Map', 'ccvm', 'value'),
    oils_i18n_gettext(593, 'Map', 'ccvm', 'search_label')),
(594, 'mr_hold_format', 'microform', 
    oils_i18n_gettext(594, 'Microform', 'ccvm', 'value'),
    oils_i18n_gettext(594, 'Microform', 'ccvm', 'search_label')),
(595, 'mr_hold_format', 'score', 
    oils_i18n_gettext(595, 'Music Score', 'ccvm', 'value'),
    oils_i18n_gettext(595, 'Music Score', 'ccvm', 'search_label')),
(596, 'mr_hold_format', 'picture', 
    oils_i18n_gettext(596, 'Picture', 'ccvm', 'value'),
    oils_i18n_gettext(596, 'Picture', 'ccvm', 'search_label')),
(597, 'mr_hold_format', 'equip', 
    oils_i18n_gettext(597, 'Equipment, games, toys', 'ccvm', 'value'),
    oils_i18n_gettext(597, 'Equipment, games, toys', 'ccvm', 'search_label')),
(598, 'mr_hold_format', 'serial', 
    oils_i18n_gettext(598, 'Serials and magazines', 'ccvm', 'value'),
    oils_i18n_gettext(598, 'Serials and magazines', 'ccvm', 'search_label')),
(599, 'mr_hold_format', 'vhs', 
    oils_i18n_gettext(599, 'VHS', 'ccvm', 'value'),
    oils_i18n_gettext(599, 'VHS', 'ccvm', 'search_label')),
(600, 'mr_hold_format', 'cdaudiobook', 
    oils_i18n_gettext(600, 'CD Audiobook', 'ccvm', 'value'),
    oils_i18n_gettext(600, 'CD Audiobook', 'ccvm', 'search_label')),
(601, 'mr_hold_format', 'cdmusic', 
    oils_i18n_gettext(601, 'CD Music recording', 'ccvm', 'value'),
    oils_i18n_gettext(601, 'CD Music recording', 'ccvm', 'search_label')),
(602, 'mr_hold_format', 'casaudiobook', 
    oils_i18n_gettext(602, 'Cassette audiobook', 'ccvm', 'value'),
    oils_i18n_gettext(602, 'Cassette audiobook', 'ccvm', 'search_label')),
(603, 'mr_hold_format', 'casmusic',
    oils_i18n_gettext(603, 'Audiocassette music recording', 'ccvm', 'value'),
    oils_i18n_gettext(603, 'Audiocassette music recording', 'ccvm', 'search_label')),
(604, 'mr_hold_format', 'phonospoken', 
    oils_i18n_gettext(604, 'Phonograph spoken recording', 'ccvm', 'value'),
    oils_i18n_gettext(604, 'Phonograph spoken recording', 'ccvm', 'search_label')),
(605, 'mr_hold_format', 'phonomusic', 
    oils_i18n_gettext(605, 'Phonograph music recording', 'ccvm', 'value'),
    oils_i18n_gettext(605, 'Phonograph music recording', 'ccvm', 'search_label')),
(606, 'mr_hold_format', 'lpbook', 
    oils_i18n_gettext(606, 'Large Print Book', 'ccvm', 'value'),
    oils_i18n_gettext(606, 'Large Print Book', 'ccvm', 'search_label'))
;

-- but we can auto-generate the composite definitions

DO $$
    DECLARE format TEXT;
BEGIN
    FOR format IN SELECT UNNEST(
        '{book,braille,software,dvd,kit,map,microform,score,picture,equip,serial,vhs,cdaudiobook,cdmusic,casaudiobook,casmusic,phonospoken,phonomusic,lpbook}'::text[]) LOOP

        INSERT INTO config.composite_attr_entry_definition 
            (coded_value, definition) VALUES
            (
                -- get the ID from the new ccvm above
                (SELECT id FROM config.coded_value_map 
                    WHERE code = format AND ctype = 'mr_hold_format'),
                -- get the def of the matching ccvm attached to the icon_format attr
                (SELECT definition FROM config.composite_attr_entry_definition ccaed
                    JOIN config.coded_value_map ccvm ON (ccaed.coded_value = ccvm.id)
                    WHERE ccvm.ctype = 'icon_format' AND ccvm.code = format)
            );
    END LOOP; 
END $$;

INSERT INTO config.coded_value_map
    (id, ctype, code, value, search_label) VALUES 
(607, 'icon_format', 'music', 
    oils_i18n_gettext(607, 'Musical Sound Recording (Unknown Format)', 'ccvm', 'value'),
    oils_i18n_gettext(607, 'Musical Sound Recording (Unknown Format)', 'ccvm', 'search_label'));

INSERT INTO config.composite_attr_entry_definition 
    (coded_value, definition) VALUES
(607, '{"0":{"_attr":"item_type","_val":"j"},"1":{"_not":[{"_attr":"sr_format","_val":"a"},{"_attr":"sr_format","_val":"b"},{"_attr":"sr_format","_val":"c"},{"_attr":"sr_format","_val":"d"},{"_attr":"sr_format","_val":"f"},{"_attr":"sr_format","_val":"e"},{"_attr":"sr_format","_val":"l"}]}}');

-- icon for blu-ray
INSERT INTO config.coded_value_map
    (id, ctype, code, value, search_label) VALUES 
(608, 'icon_format', 'blu-ray', 
    oils_i18n_gettext(608, 'Blu-ray', 'ccvm', 'value'),
    oils_i18n_gettext(608, 'Blu-ray', 'ccvm', 'search_label'));
INSERT INTO config.composite_attr_entry_definition 
    (coded_value, definition) VALUES (608, '{"_attr":"vr_format","_val":"s"}');

-- metarecord hold format for blu-ray
INSERT INTO config.coded_value_map
    (id, ctype, code, value, search_label) VALUES 
(609, 'mr_hold_format', 'blu-ray', 
    oils_i18n_gettext(609, 'Blu-ray', 'ccvm', 'value'),
    oils_i18n_gettext(609, 'Blu-ray', 'ccvm', 'search_label'));
INSERT INTO config.composite_attr_entry_definition 
    (coded_value, definition) VALUES (609, '{"_attr":"vr_format","_val":"s"}');

COMMIT;

