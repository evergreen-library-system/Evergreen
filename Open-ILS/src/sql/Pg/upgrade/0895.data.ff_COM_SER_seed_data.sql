BEGIN;

SELECT evergreen.upgrade_deps_block_check('0895', :eg_version);

INSERT INTO config.marc21_ff_pos_map (fixed_field, tag, rec_type,start_pos, length, default_val) VALUES ('File', '008', 'COM', 26, 1, 'u');
INSERT INTO config.marc21_ff_pos_map (fixed_field, tag, rec_type,start_pos, length, default_val) VALUES ('File', '006', 'COM', 9, 1, 'u');
INSERT INTO config.marc21_ff_pos_map (fixed_field, tag, rec_type,start_pos, length, default_val) VALUES ('Freq', '008', 'SER', 18, 1, ' ');
INSERT INTO config.marc21_ff_pos_map (fixed_field, tag, rec_type,start_pos, length, default_val) VALUES ('Freq', '006', 'SER', 1, 1, ' ');
INSERT INTO config.marc21_ff_pos_map (fixed_field, tag, rec_type,start_pos, length, default_val) VALUES ('Regl', '008', 'SER', 19, 1, ' ');
INSERT INTO config.marc21_ff_pos_map (fixed_field, tag, rec_type,start_pos, length, default_val) VALUES ('Regl', '006', 'SER', 2, 1, ' ');

INSERT INTO config.record_attr_definition (name,label,fixed_field) values ('file','File','File');
INSERT INTO config.record_attr_definition (name,label,fixed_field) values ('freq','Freq','Freq');
INSERT INTO config.record_attr_definition (name,label,fixed_field) values ('regl','Regl','Regl');

COMMIT;
