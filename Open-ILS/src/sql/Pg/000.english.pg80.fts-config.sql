/*
 * Copyright (C) 2004-2008  Georgia Public Library Service
 * Copyright (C) 2008  Equinox Software, Inc.
 * Mike Rylander <miker@esilibrary.com>
 *
 * This program is free software; you can redistribute it and/or
 * modify it under the terms of the GNU General Public License
 * as published by the Free Software Foundation; either version 2
 * of the License, or (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 */

BEGIN;

CREATE OR REPLACE FUNCTION oils_tsearch2 () RETURNS TRIGGER AS $$
BEGIN
	NEW.index_vector = to_tsvector(TG_ARGV[0], NEW.value);
	RETURN NEW;
END;
$$ LANGUAGE PLPGSQL;

INSERT INTO pg_ts_cfg VALUES ('title', 'default','C');
INSERT INTO pg_ts_cfg VALUES ('author', 'default','C');
INSERT INTO pg_ts_cfg VALUES ('subject', 'default','C');
INSERT INTO pg_ts_cfg VALUES ('keyword', 'default','C');
INSERT INTO pg_ts_cfg VALUES ('series', 'default','C');

INSERT INTO pg_ts_dict VALUES ('en_stem_nostop', 'snb_en_init(internal)', '', 'snb_lexize(internal,internal,integer)', 'English Stemmer. Snowball. No stop words.');

INSERT INTO pg_ts_cfgmap VALUES ('title', 'nlword', '{simple}');
INSERT INTO pg_ts_cfgmap VALUES ('title', 'word', '{simple}');
INSERT INTO pg_ts_cfgmap VALUES ('title', 'email', '{simple}');
INSERT INTO pg_ts_cfgmap VALUES ('title', 'url', '{simple}');
INSERT INTO pg_ts_cfgmap VALUES ('title', 'host', '{simple}');
INSERT INTO pg_ts_cfgmap VALUES ('title', 'sfloat', '{simple}');
INSERT INTO pg_ts_cfgmap VALUES ('title', 'version', '{simple}');
INSERT INTO pg_ts_cfgmap VALUES ('title', 'part_hword', '{simple}');
INSERT INTO pg_ts_cfgmap VALUES ('title', 'nlpart_hword', '{simple}');
INSERT INTO pg_ts_cfgmap VALUES ('title', 'hword', '{simple}');
INSERT INTO pg_ts_cfgmap VALUES ('title', 'nlhword', '{simple}');
INSERT INTO pg_ts_cfgmap VALUES ('title', 'uri', '{simple}');
INSERT INTO pg_ts_cfgmap VALUES ('title', 'file', '{simple}');
INSERT INTO pg_ts_cfgmap VALUES ('title', 'float', '{simple}');
INSERT INTO pg_ts_cfgmap VALUES ('title', 'int', '{simple}');
INSERT INTO pg_ts_cfgmap VALUES ('title', 'uint', '{simple}');
INSERT INTO pg_ts_cfgmap VALUES ('title', 'lword', '{en_stem_nostop}');
INSERT INTO pg_ts_cfgmap VALUES ('title', 'lpart_hword', '{en_stem_nostop}');
INSERT INTO pg_ts_cfgmap VALUES ('title', 'lhword', '{en_stem_nostop}');

INSERT INTO pg_ts_cfgmap VALUES ('author', 'nlword', '{simple}');
INSERT INTO pg_ts_cfgmap VALUES ('author', 'word', '{simple}');
INSERT INTO pg_ts_cfgmap VALUES ('author', 'email', '{simple}');
INSERT INTO pg_ts_cfgmap VALUES ('author', 'url', '{simple}');
INSERT INTO pg_ts_cfgmap VALUES ('author', 'host', '{simple}');
INSERT INTO pg_ts_cfgmap VALUES ('author', 'sfloat', '{simple}');
INSERT INTO pg_ts_cfgmap VALUES ('author', 'version', '{simple}');
INSERT INTO pg_ts_cfgmap VALUES ('author', 'part_hword', '{simple}');
INSERT INTO pg_ts_cfgmap VALUES ('author', 'nlpart_hword', '{simple}');
INSERT INTO pg_ts_cfgmap VALUES ('author', 'hword', '{simple}');
INSERT INTO pg_ts_cfgmap VALUES ('author', 'nlhword', '{simple}');
INSERT INTO pg_ts_cfgmap VALUES ('author', 'uri', '{simple}');
INSERT INTO pg_ts_cfgmap VALUES ('author', 'file', '{simple}');
INSERT INTO pg_ts_cfgmap VALUES ('author', 'float', '{simple}');
INSERT INTO pg_ts_cfgmap VALUES ('author', 'int', '{simple}');
INSERT INTO pg_ts_cfgmap VALUES ('author', 'uint', '{simple}');
INSERT INTO pg_ts_cfgmap VALUES ('author', 'lword', '{en_stem_nostop}');
INSERT INTO pg_ts_cfgmap VALUES ('author', 'lpart_hword', '{en_stem_nostop}');
INSERT INTO pg_ts_cfgmap VALUES ('author', 'lhword', '{en_stem_nostop}');

INSERT INTO pg_ts_cfgmap VALUES ('subject', 'nlword', '{simple}');
INSERT INTO pg_ts_cfgmap VALUES ('subject', 'word', '{simple}');
INSERT INTO pg_ts_cfgmap VALUES ('subject', 'email', '{simple}');
INSERT INTO pg_ts_cfgmap VALUES ('subject', 'url', '{simple}');
INSERT INTO pg_ts_cfgmap VALUES ('subject', 'host', '{simple}');
INSERT INTO pg_ts_cfgmap VALUES ('subject', 'sfloat', '{simple}');
INSERT INTO pg_ts_cfgmap VALUES ('subject', 'version', '{simple}');
INSERT INTO pg_ts_cfgmap VALUES ('subject', 'part_hword', '{simple}');
INSERT INTO pg_ts_cfgmap VALUES ('subject', 'nlpart_hword', '{simple}');
INSERT INTO pg_ts_cfgmap VALUES ('subject', 'hword', '{simple}');
INSERT INTO pg_ts_cfgmap VALUES ('subject', 'nlhword', '{simple}');
INSERT INTO pg_ts_cfgmap VALUES ('subject', 'uri', '{simple}');
INSERT INTO pg_ts_cfgmap VALUES ('subject', 'file', '{simple}');
INSERT INTO pg_ts_cfgmap VALUES ('subject', 'float', '{simple}');
INSERT INTO pg_ts_cfgmap VALUES ('subject', 'int', '{simple}');
INSERT INTO pg_ts_cfgmap VALUES ('subject', 'uint', '{simple}');
INSERT INTO pg_ts_cfgmap VALUES ('subject', 'lword', '{en_stem_nostop}');
INSERT INTO pg_ts_cfgmap VALUES ('subject', 'lpart_hword', '{en_stem_nostop}');
INSERT INTO pg_ts_cfgmap VALUES ('subject', 'lhword', '{en_stem_nostop}');

INSERT INTO pg_ts_cfgmap VALUES ('keyword', 'nlword', '{simple}');
INSERT INTO pg_ts_cfgmap VALUES ('keyword', 'word', '{simple}');
INSERT INTO pg_ts_cfgmap VALUES ('keyword', 'email', '{simple}');
INSERT INTO pg_ts_cfgmap VALUES ('keyword', 'url', '{simple}');
INSERT INTO pg_ts_cfgmap VALUES ('keyword', 'host', '{simple}');
INSERT INTO pg_ts_cfgmap VALUES ('keyword', 'sfloat', '{simple}');
INSERT INTO pg_ts_cfgmap VALUES ('keyword', 'version', '{simple}');
INSERT INTO pg_ts_cfgmap VALUES ('keyword', 'part_hword', '{simple}');
INSERT INTO pg_ts_cfgmap VALUES ('keyword', 'nlpart_hword', '{simple}');
INSERT INTO pg_ts_cfgmap VALUES ('keyword', 'hword', '{simple}');
INSERT INTO pg_ts_cfgmap VALUES ('keyword', 'nlhword', '{simple}');
INSERT INTO pg_ts_cfgmap VALUES ('keyword', 'uri', '{simple}');
INSERT INTO pg_ts_cfgmap VALUES ('keyword', 'file', '{simple}');
INSERT INTO pg_ts_cfgmap VALUES ('keyword', 'float', '{simple}');
INSERT INTO pg_ts_cfgmap VALUES ('keyword', 'int', '{simple}');
INSERT INTO pg_ts_cfgmap VALUES ('keyword', 'uint', '{simple}');
INSERT INTO pg_ts_cfgmap VALUES ('keyword', 'lword', '{en_stem_nostop}');
INSERT INTO pg_ts_cfgmap VALUES ('keyword', 'lpart_hword', '{en_stem_nostop}');
INSERT INTO pg_ts_cfgmap VALUES ('keyword', 'lhword', '{en_stem_nostop}');

INSERT INTO pg_ts_cfgmap VALUES ('series', 'nlword', '{simple}');
INSERT INTO pg_ts_cfgmap VALUES ('series', 'word', '{simple}');
INSERT INTO pg_ts_cfgmap VALUES ('series', 'email', '{simple}');
INSERT INTO pg_ts_cfgmap VALUES ('series', 'url', '{simple}');
INSERT INTO pg_ts_cfgmap VALUES ('series', 'host', '{simple}');
INSERT INTO pg_ts_cfgmap VALUES ('series', 'sfloat', '{simple}');
INSERT INTO pg_ts_cfgmap VALUES ('series', 'version', '{simple}');
INSERT INTO pg_ts_cfgmap VALUES ('series', 'part_hword', '{simple}');
INSERT INTO pg_ts_cfgmap VALUES ('series', 'nlpart_hword', '{simple}');
INSERT INTO pg_ts_cfgmap VALUES ('series', 'hword', '{simple}');
INSERT INTO pg_ts_cfgmap VALUES ('series', 'nlhword', '{simple}');
INSERT INTO pg_ts_cfgmap VALUES ('series', 'uri', '{simple}');
INSERT INTO pg_ts_cfgmap VALUES ('series', 'file', '{simple}');
INSERT INTO pg_ts_cfgmap VALUES ('series', 'float', '{simple}');
INSERT INTO pg_ts_cfgmap VALUES ('series', 'int', '{simple}');
INSERT INTO pg_ts_cfgmap VALUES ('series', 'uint', '{simple}');
INSERT INTO pg_ts_cfgmap VALUES ('series', 'lword', '{en_stem_nostop}');
INSERT INTO pg_ts_cfgmap VALUES ('series', 'lpart_hword', '{en_stem_nostop}');
INSERT INTO pg_ts_cfgmap VALUES ('series', 'lhword', '{en_stem_nostop}');

COMMIT;
