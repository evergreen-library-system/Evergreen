-- Evergreen DB patch 0624.data.fix_marc_conf_cont.sql
--
--
BEGIN;


-- check whether patch can be applied
SELECT evergreen.upgrade_deps_block_check('0624', :eg_version);

-- Cont was typod as Conf. Update the old entries.
UPDATE config.marc21_ff_pos_map SET fixed_field = 'Cont' WHERE fixed_field = 'Conf' AND length > 1;
-- Conf thus didn't exist. Add it.
INSERT INTO config.marc21_ff_pos_map (fixed_field, tag, rec_type,start_pos, length, default_val) VALUES ('Conf', '006', 'BKS', 11, 1, ' ');
INSERT INTO config.marc21_ff_pos_map (fixed_field, tag, rec_type,start_pos, length, default_val) VALUES ('Conf', '006', 'SER', 11, 1, ' ');
INSERT INTO config.marc21_ff_pos_map (fixed_field, tag, rec_type,start_pos, length, default_val) VALUES ('Conf', '008', 'BKS', 29, 1, ' ');
INSERT INTO config.marc21_ff_pos_map (fixed_field, tag, rec_type,start_pos, length, default_val) VALUES ('Conf', '008', 'SER', 29, 1, ' ');


COMMIT;
