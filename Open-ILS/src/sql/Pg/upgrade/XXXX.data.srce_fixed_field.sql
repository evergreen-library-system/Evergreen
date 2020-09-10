BEGIN;

SELECT evergreen.upgrade_deps_block_check('XXXX', :eg_version);

INSERT INTO config.marc21_ff_pos_map (fixed_field, tag, rec_type,start_pos, length, default_val) VALUES ('Srce', '008', 'BKS', 39, 1, ' ');
INSERT INTO config.marc21_ff_pos_map (fixed_field, tag, rec_type,start_pos, length, default_val) VALUES ('Srce', '008', 'COM', 39, 1, ' ');
INSERT INTO config.marc21_ff_pos_map (fixed_field, tag, rec_type,start_pos, length, default_val) VALUES ('Srce', '008', 'MAP', 39, 1, ' ');
INSERT INTO config.marc21_ff_pos_map (fixed_field, tag, rec_type,start_pos, length, default_val) VALUES ('Srce', '008', 'MIX', 39, 1, ' ');
INSERT INTO config.marc21_ff_pos_map (fixed_field, tag, rec_type,start_pos, length, default_val) VALUES ('Srce', '008', 'REC', 39, 1, ' ');
INSERT INTO config.marc21_ff_pos_map (fixed_field, tag, rec_type,start_pos, length, default_val) VALUES ('Srce', '008', 'SCO', 39, 1, ' ');
INSERT INTO config.marc21_ff_pos_map (fixed_field, tag, rec_type,start_pos, length, default_val) VALUES ('Srce', '008', 'SER', 39, 1, ' ');
INSERT INTO config.marc21_ff_pos_map (fixed_field, tag, rec_type,start_pos, length, default_val) VALUES ('Srce', '008', 'VIS', 39, 1, ' ');


INSERT INTO config.record_attr_definition (name,label,fixed_field) values ('srce','Srce','Srce');

INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES
(1750, 'srce', ' ', oils_i18n_gettext('1750', 'National bibliographic agency', 'ccvm', 'value')),
(1751, 'srce', 'c', oils_i18n_gettext('1751', 'Cooperative cataloging program', 'ccvm', 'value')),
(1752, 'srce', 'd', oils_i18n_gettext('1752', 'Other', 'ccvm', 'value'));

COMMIT;
