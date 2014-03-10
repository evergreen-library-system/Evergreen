
BEGIN;

SELECT evergreen.upgrade_deps_block_check('0871', :eg_version);

INSERT INTO config.record_attr_definition 
    (name, label, multi, filter, composite) VALUES (
        'search_format', 
        oils_i18n_gettext('search_format', 'Search Formats', 'crad', 'label'),
        TRUE, TRUE, TRUE
    );

INSERT INTO config.coded_value_map
    (id, ctype, code, value, search_label) VALUES 
(610, 'search_format', 'book', 
    oils_i18n_gettext(610, 'All Books', 'ccvm', 'value'),
    oils_i18n_gettext(610, 'All Books', 'ccvm', 'search_label')),
(611, 'search_format', 'braille', 
    oils_i18n_gettext(611, 'Braille', 'ccvm', 'value'),
    oils_i18n_gettext(611, 'Braille', 'ccvm', 'search_label')),
(612, 'search_format', 'software', 
    oils_i18n_gettext(612, 'Software and video games', 'ccvm', 'value'),
    oils_i18n_gettext(612, 'Software and video games', 'ccvm', 'search_label')),
(613, 'search_format', 'dvd', 
    oils_i18n_gettext(613, 'DVD', 'ccvm', 'value'),
    oils_i18n_gettext(613, 'DVD', 'ccvm', 'search_label')),
(614, 'search_format', 'ebook', 
    oils_i18n_gettext(614, 'E-book', 'ccvm', 'value'),
    oils_i18n_gettext(614, 'E-book', 'ccvm', 'search_label')),
(615, 'search_format', 'eaudio', 
    oils_i18n_gettext(615, 'E-audio', 'ccvm', 'value'),
    oils_i18n_gettext(615, 'E-audio', 'ccvm', 'search_label')),
(616, 'search_format', 'kit', 
    oils_i18n_gettext(616, 'Kit', 'ccvm', 'value'),
    oils_i18n_gettext(616, 'Kit', 'ccvm', 'search_label')),
(617, 'search_format', 'map', 
    oils_i18n_gettext(617, 'Map', 'ccvm', 'value'),
    oils_i18n_gettext(617, 'Map', 'ccvm', 'search_label')),
(618, 'search_format', 'microform', 
    oils_i18n_gettext(618, 'Microform', 'ccvm', 'value'),
    oils_i18n_gettext(618, 'Microform', 'ccvm', 'search_label')),
(619, 'search_format', 'score', 
    oils_i18n_gettext(619, 'Music Score', 'ccvm', 'value'),
    oils_i18n_gettext(619, 'Music Score', 'ccvm', 'search_label')),
(620, 'search_format', 'picture', 
    oils_i18n_gettext(620, 'Picture', 'ccvm', 'value'),
    oils_i18n_gettext(620, 'Picture', 'ccvm', 'search_label')),
(621, 'search_format', 'equip', 
    oils_i18n_gettext(621, 'Equipment, games, toys', 'ccvm', 'value'),
    oils_i18n_gettext(621, 'Equipment, games, toys', 'ccvm', 'search_label')),
(622, 'search_format', 'serial', 
    oils_i18n_gettext(622, 'Serials and magazines', 'ccvm', 'value'),
    oils_i18n_gettext(622, 'Serials and magazines', 'ccvm', 'search_label')),
(623, 'search_format', 'vhs', 
    oils_i18n_gettext(623, 'VHS', 'ccvm', 'value'),
    oils_i18n_gettext(623, 'VHS', 'ccvm', 'search_label')),
(624, 'search_format', 'evideo', 
    oils_i18n_gettext(624, 'E-video', 'ccvm', 'value'),
    oils_i18n_gettext(624, 'E-video', 'ccvm', 'search_label')),
(625, 'search_format', 'cdaudiobook', 
    oils_i18n_gettext(625, 'CD Audiobook', 'ccvm', 'value'),
    oils_i18n_gettext(625, 'CD Audiobook', 'ccvm', 'search_label')),
(626, 'search_format', 'cdmusic', 
    oils_i18n_gettext(626, 'CD Music recording', 'ccvm', 'value'),
    oils_i18n_gettext(626, 'CD Music recording', 'ccvm', 'search_label')),
(627, 'search_format', 'casaudiobook', 
    oils_i18n_gettext(627, 'Cassette audiobook', 'ccvm', 'value'),
    oils_i18n_gettext(627, 'Cassette audiobook', 'ccvm', 'search_label')),
(628, 'search_format', 'casmusic',
    oils_i18n_gettext(628, 'Audiocassette music recording', 'ccvm', 'value'),
    oils_i18n_gettext(628, 'Audiocassette music recording', 'ccvm', 'search_label')),
(629, 'search_format', 'phonospoken', 
    oils_i18n_gettext(629, 'Phonograph spoken recording', 'ccvm', 'value'),
    oils_i18n_gettext(629, 'Phonograph spoken recording', 'ccvm', 'search_label')),
(630, 'search_format', 'phonomusic', 
    oils_i18n_gettext(630, 'Phonograph music recording', 'ccvm', 'value'),
    oils_i18n_gettext(630, 'Phonograph music recording', 'ccvm', 'search_label')),
(631, 'search_format', 'lpbook', 
    oils_i18n_gettext(631, 'Large Print Book', 'ccvm', 'value'),
    oils_i18n_gettext(631, 'Large Print Book', 'ccvm', 'search_label')),
(632, 'search_format', 'music', 
    oils_i18n_gettext(632, 'All Music', 'ccvm', 'label'),
    oils_i18n_gettext(632, 'All Music', 'ccvm', 'search_label')),
(633, 'search_format', 'blu-ray', 
    oils_i18n_gettext(633, 'Blu-ray', 'ccvm', 'value'),
    oils_i18n_gettext(633, 'Blu-ray', 'ccvm', 'search_label'));



-- copy the composite definition from icon_format into 
-- search_format for a baseline data set
DO $$
    DECLARE format config.coded_value_map%ROWTYPE;
BEGIN
    FOR format IN SELECT * 
        FROM config.coded_value_map WHERE ctype = 'icon_format'
    LOOP
        INSERT INTO config.composite_attr_entry_definition 
            (coded_value, definition) VALUES
            (
                -- get the ID from the new ccvm above
                (SELECT id FROM config.coded_value_map 
                    WHERE code = format.code AND ctype = 'search_format'),

                -- def of the matching icon_format attr
                (SELECT definition FROM config.composite_attr_entry_definition 
                    WHERE coded_value = format.id)
            );
    END LOOP; 
END $$;

-- modify the 'book' definition so that it includes large print
UPDATE config.composite_attr_entry_definition 
    SET definition = '{"0":[{"_attr":"item_type","_val":"a"},{"_attr":"item_type","_val":"t"}],"1":{"_not":[{"_attr":"item_form","_val":"a"},{"_attr":"item_form","_val":"b"},{"_attr":"item_form","_val":"c"},{"_attr":"item_form","_val":"f"},{"_attr":"item_form","_val":"o"},{"_attr":"item_form","_val":"q"},{"_attr":"item_form","_val":"r"},{"_attr":"item_form","_val":"s"}]},"2":[{"_attr":"bib_level","_val":"a"},{"_attr":"bib_level","_val":"c"},{"_attr":"bib_level","_val":"d"},{"_attr":"bib_level","_val":"m"}]}'
    WHERE coded_value = 610;

-- modify 'music' to include all recorded music, regardless of format
UPDATE config.composite_attr_entry_definition 
    SET definition = '{"_attr":"item_type","_val":"j"}'
    WHERE coded_value = 632;

UPDATE config.global_flag 
    SET value = 'search_format' 
    WHERE name = 'opac.format_selector.attr';

COMMIT;

