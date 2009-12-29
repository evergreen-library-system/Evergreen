BEGIN;

INSERT INTO config.upgrade_log (version) VALUES ('0127'); -- miker

CREATE TABLE config.marc21_rec_type_map (
    code        TEXT    PRIMARY KEY,
    type_val    TEXT    NOT NULL,
    blvl_val    TEXT    NOT NULL
);

CREATE TABLE config.marc21_ff_pos_map (
    id          SERIAL  PRIMARY KEY,
    fixed_field TEXT    NOT NULL,
    tag         TEXT    NOT NULL,
    rec_type    TEXT    NOT NULL,
    start_pos   INT     NOT NULL,
    length      INT     NOT NULL,
    default_val TEXT    NOT NULL DEFAULT ' '
);

CREATE TABLE config.marc21_physical_characteristic_type_map (
    ptype_key   TEXT    PRIMARY KEY,
    label       TEXT    NOT NULL -- I18N
);

CREATE TABLE config.marc21_physical_characteristic_subfield_map (
    id          SERIAL  PRIMARY KEY,
    ptype_key   TEXT    NOT NULL REFERENCES config.marc21_physical_characteristic_type_map (ptype_key) ON DELETE CASCADE ON UPDATE CASCADE,
    subfield    TEXT    NOT NULL,
    start_pos   INT     NOT NULL,
    length      INT     NOT NULL,
    label       TEXT    NOT NULL -- I18N
);

CREATE TABLE config.marc21_physical_characteristic_value_map (
    id              SERIAL  PRIMARY KEY,
    value           TEXT    NOT NULL,
    ptype_subfield  INT     NOT NULL REFERENCES config.marc21_physical_characteristic_subfield_map (id),
    label           TEXT    NOT NULL -- I18N
);


----------------------------------
-- MARC21 record structure data --
----------------------------------

-- Record type map
INSERT INTO config.marc21_rec_type_map (code, type_val, blvl_val) VALUES ('BKS','at','acdm');
INSERT INTO config.marc21_rec_type_map (code, type_val, blvl_val) VALUES ('SER','a','bsi');
INSERT INTO config.marc21_rec_type_map (code, type_val, blvl_val) VALUES ('VIS','gkro','abcdmsi');
INSERT INTO config.marc21_rec_type_map (code, type_val, blvl_val) VALUES ('MIX','p','cdi');
INSERT INTO config.marc21_rec_type_map (code, type_val, blvl_val) VALUES ('MAP','ef','abcdmsi');
INSERT INTO config.marc21_rec_type_map (code, type_val, blvl_val) VALUES ('SCO','cd','abcdmsi');
INSERT INTO config.marc21_rec_type_map (code, type_val, blvl_val) VALUES ('REC','ij','abcdmsi');
INSERT INTO config.marc21_rec_type_map (code, type_val, blvl_val) VALUES ('COM','m','abcdmsi');


------ Physical Characteristics

-- Map
INSERT INTO config.marc21_physical_characteristic_type_map (ptype_key, label) VALUES ('a','Map');
INSERT INTO config.marc21_physical_characteristic_subfield_map (ptype_key,subfield,start_pos,length,label) VALUES ('a','b','1','1','SMD');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('d',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Atlas');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('g',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Diagram');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('j',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Map');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('k',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Profile');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('q',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Model');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('r',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Remote-sensing image');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('s',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Section');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('u',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Unspecified');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('y',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'View');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('z',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Other');
INSERT INTO config.marc21_physical_characteristic_subfield_map (ptype_key,subfield,start_pos,length,label) VALUES ('a','d','3','1','Color');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('a',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'One color');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('c',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Multicolored');
INSERT INTO config.marc21_physical_characteristic_subfield_map (ptype_key,subfield,start_pos,length,label) VALUES ('a','e','4','1','Physical medium');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('a',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Paper');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('b',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Wood');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('c',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Stone');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('d',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Metal');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('e',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Synthetics');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('f',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Skins');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('g',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Textile');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('p',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Plaster');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('q',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Flexible base photographic medium, positive');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('r',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Flexible base photographic medium, negative');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('s',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Non-flexible base photographic medium, positive');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('t',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Non-flexible base photographic medium, negative');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('u',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Unknown');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('y',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Other photographic medium');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('z',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Other');
INSERT INTO config.marc21_physical_characteristic_subfield_map (ptype_key,subfield,start_pos,length,label) VALUES ('a','f','5','1','Type of reproduction');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('f',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Facsimile');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('n',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Not applicable');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('u',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Unknown');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('z',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Other');
INSERT INTO config.marc21_physical_characteristic_subfield_map (ptype_key,subfield,start_pos,length,label) VALUES ('a','g','6','1','Production/reproduction details');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('a',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Photocopy, blueline print');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('b',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Photocopy');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('c',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Pre-production');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('d',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Film');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('u',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Unknown');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('z',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Other');
INSERT INTO config.marc21_physical_characteristic_subfield_map (ptype_key,subfield,start_pos,length,label) VALUES ('a','h','7','1','Positive/negative');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('a',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Positive');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('b',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Negative');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('m',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Mixed');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('n',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Not applicable');

-- Electronic Resource
INSERT INTO config.marc21_physical_characteristic_type_map (ptype_key, label) VALUES ('c','Electronic Resource');
INSERT INTO config.marc21_physical_characteristic_subfield_map (ptype_key,subfield,start_pos,length,label) VALUES ('c','b','1','1','SMD');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('a',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Tape Cartridge');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('b',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Chip cartridge');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('c',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Computer optical disk cartridge');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('f',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Tape cassette');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('h',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Tape reel');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('j',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Magnetic disk');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('m',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Magneto-optical disk');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('o',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Optical disk');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('r',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Remote');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('u',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Unspecified');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('z',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Other');
INSERT INTO config.marc21_physical_characteristic_subfield_map (ptype_key,subfield,start_pos,length,label) VALUES ('c','d','3','1','Color');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('a',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'One color');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('b',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Black-and-white');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('c',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Multicolored');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('g',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Gray scale');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('m',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Mixed');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('n',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Not applicable');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('u',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Unknown');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('z',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Other');
INSERT INTO config.marc21_physical_characteristic_subfield_map (ptype_key,subfield,start_pos,length,label) VALUES ('c','e','4','1','Dimensions');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('a',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'3 1/2 in.');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('e',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'12 in.');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('g',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'4 3/4 in. or 12 cm.');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('i',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'1 1/8 x 2 3/8 in.');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('j',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'3 7/8 x 2 1/2 in.');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('n',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Not applicable');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('o',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'5 1/4 in.');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('u',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Unknown');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('v',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'8 in.');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('z',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Other');
INSERT INTO config.marc21_physical_characteristic_subfield_map (ptype_key,subfield,start_pos,length,label) VALUES ('c','f','5','1','Sound');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES (' ',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'No sound (Silent)');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('a',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Sound');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('u',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Unknown');
INSERT INTO config.marc21_physical_characteristic_subfield_map (ptype_key,subfield,start_pos,length,label) VALUES ('c','g','6','3','Image bit depth');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('---',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Unknown');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('mmm',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Multiple');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('nnn',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Not applicable');
INSERT INTO config.marc21_physical_characteristic_subfield_map (ptype_key,subfield,start_pos,length,label) VALUES ('c','h','9','1','File formats');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('a',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'One file format');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('m',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Multiple file formats');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('u',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Unknown');
INSERT INTO config.marc21_physical_characteristic_subfield_map (ptype_key,subfield,start_pos,length,label) VALUES ('c','i','10','1','Quality assurance target(s)');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('a',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Absent');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('n',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Not applicable');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('p',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Present');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('u',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Unknown');
INSERT INTO config.marc21_physical_characteristic_subfield_map (ptype_key,subfield,start_pos,length,label) VALUES ('c','j','11','1','Antecedent/Source');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('a',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'File reproduced from original');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('b',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'File reproduced from microform');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('c',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'File reproduced from electronic resource');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('d',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'File reproduced from an intermediate (not microform)');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('m',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Mixed');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('n',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Not applicable');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('u',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Unknown');
INSERT INTO config.marc21_physical_characteristic_subfield_map (ptype_key,subfield,start_pos,length,label) VALUES ('c','k','12','1','Level of compression');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('a',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Uncompressed');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('b',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Lossless');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('d',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Lossy');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('m',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Mixed');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('u',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Unknown');
INSERT INTO config.marc21_physical_characteristic_subfield_map (ptype_key,subfield,start_pos,length,label) VALUES ('c','l','13','1','Reformatting quality');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('a',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Access');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('n',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Not applicable');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('p',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Preservation');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('r',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Replacement');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('u',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Unknown');

-- Globe
INSERT INTO config.marc21_physical_characteristic_type_map (ptype_key, label) VALUES ('d','Globe');
INSERT INTO config.marc21_physical_characteristic_subfield_map (ptype_key,subfield,start_pos,length,label) VALUES ('d','b','1','1','SMD');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('a',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Celestial globe');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('b',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Planetary or lunar globe');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('c',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Terrestrial globe');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('e',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Earth moon globe');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('u',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Unspecified');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('z',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Other');
INSERT INTO config.marc21_physical_characteristic_subfield_map (ptype_key,subfield,start_pos,length,label) VALUES ('d','d','3','1','Color');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('a',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'One color');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('c',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Multicolored');
INSERT INTO config.marc21_physical_characteristic_subfield_map (ptype_key,subfield,start_pos,length,label) VALUES ('d','e','4','1','Physical medium');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('a',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Paper');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('b',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Wood');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('c',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Stone');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('d',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Metal');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('e',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Synthetics');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('f',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Skins');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('g',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Textile');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('p',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Plaster');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('u',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Unknown');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('z',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Other');
INSERT INTO config.marc21_physical_characteristic_subfield_map (ptype_key,subfield,start_pos,length,label) VALUES ('d','f','5','1','Type of reproduction');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('f',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Facsimile');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('n',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Not applicable');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('u',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Unknown');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('z',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Other');

-- Tactile Material
INSERT INTO config.marc21_physical_characteristic_type_map (ptype_key, label) VALUES ('f','Tactile Material');
INSERT INTO config.marc21_physical_characteristic_subfield_map (ptype_key,subfield,start_pos,length,label) VALUES ('f','b','1','1','SMD');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('a',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Moon');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('b',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Braille');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('c',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Combination');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('d',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Tactile, with no writing system');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('u',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Unspecified');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('z',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Other');
INSERT INTO config.marc21_physical_characteristic_subfield_map (ptype_key,subfield,start_pos,length,label) VALUES ('f','d','3','2','Class of braille writing');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('a',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Literary braille');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('b',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Format code braille');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('c',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Mathematics and scientific braille');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('d',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Computer braille');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('e',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Music braille');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('m',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Multiple braille types');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('n',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Not applicable');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('u',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Unknown');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('z',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Other');
INSERT INTO config.marc21_physical_characteristic_subfield_map (ptype_key,subfield,start_pos,length,label) VALUES ('f','e','4','1','Level of contraction');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('a',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Uncontracted');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('b',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Contracted');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('m',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Combination');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('n',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Not applicable');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('u',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Unknown');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('z',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Other');
INSERT INTO config.marc21_physical_characteristic_subfield_map (ptype_key,subfield,start_pos,length,label) VALUES ('f','f','6','3','Braille music format');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('a',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Bar over bar');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('b',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Bar by bar');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('c',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Line over line');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('d',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Paragraph');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('e',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Single line');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('f',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Section by section');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('g',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Line by line');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('h',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Open score');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('i',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Spanner short form scoring');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('j',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Short form scoring');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('k',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Outline');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('l',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Vertical score');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('n',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Not applicable');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('u',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Unknown');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('z',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Other');
INSERT INTO config.marc21_physical_characteristic_subfield_map (ptype_key,subfield,start_pos,length,label) VALUES ('f','g','9','1','Special physical characteristics');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('a',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Print/braille');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('b',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Jumbo or enlarged braille');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('n',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Not applicable');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('u',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Unknown');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('z',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Other');

-- Projected Graphic
INSERT INTO config.marc21_physical_characteristic_type_map (ptype_key, label) VALUES ('g','Projected Graphic');
INSERT INTO config.marc21_physical_characteristic_subfield_map (ptype_key,subfield,start_pos,length,label) VALUES ('g','b','1','1','SMD');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('c',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Film cartridge');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('d',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Filmstrip');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('f',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Film filmstrip type');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('o',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Filmstrip roll');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('s',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Slide');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('t',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Transparency');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('z',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Other');
INSERT INTO config.marc21_physical_characteristic_subfield_map (ptype_key,subfield,start_pos,length,label) VALUES ('g','d','3','1','Color');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('b',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Black-and-white');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('c',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Multicolored');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('h',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Hand-colored');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('m',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Mixed');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('n',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Not applicable');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('u',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Unknown');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('z',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Other');
INSERT INTO config.marc21_physical_characteristic_subfield_map (ptype_key,subfield,start_pos,length,label) VALUES ('g','e','4','1','Base of emulsion');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('d',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Glass');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('e',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Synthetics');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('j',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Safety film');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('k',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Film base, other than safety film');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('m',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Mixed collection');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('o',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Paper');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('u',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Unknown');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('z',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Other');
INSERT INTO config.marc21_physical_characteristic_subfield_map (ptype_key,subfield,start_pos,length,label) VALUES ('g','f','5','1','Sound on medium or separate');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('a',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Sound on medium');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('b',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Sound separate from medium');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('u',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Unknown');
INSERT INTO config.marc21_physical_characteristic_subfield_map (ptype_key,subfield,start_pos,length,label) VALUES ('g','g','6','1','Medium for sound');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('a',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Optical sound track on motion picture film');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('b',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Magnetic sound track on motion picture film');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('c',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Magnetic audio tape in cartridge');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('d',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Sound disc');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('e',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Magnetic audio tape on reel');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('f',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Magnetic audio tape in cassette');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('g',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Optical and magnetic sound track on film');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('h',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Videotape');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('i',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Videodisc');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('u',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Unknown');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('z',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Other');
INSERT INTO config.marc21_physical_characteristic_subfield_map (ptype_key,subfield,start_pos,length,label) VALUES ('g','h','7','1','Dimensions');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('a',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Standard 8 mm.');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('b',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Super 8 mm./single 8 mm.');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('c',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'9.5 mm.');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('d',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'16 mm.');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('e',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'28 mm.');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('f',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'35 mm.');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('g',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'70 mm.');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('j',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'2 x 2 in. (5 x 5 cm.)');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('k',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'2 1/4 x 2 1/4 in. (6 x 6 cm.)');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('s',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'4 x 5 in. (10 x 13 cm.)');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('t',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'5 x 7 in. (13 x 18 cm.)');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('u',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Unknown');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('v',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'8 x 10 in. (21 x 26 cm.)');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('w',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'9 x 9 in. (23 x 23 cm.)');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('x',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'10 x 10 in. (26 x 26 cm.)');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('y',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'7 x 7 in. (18 x 18 cm.)');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('z',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Other');
INSERT INTO config.marc21_physical_characteristic_subfield_map (ptype_key,subfield,start_pos,length,label) VALUES ('g','i','8','1','Secondary support material');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('c',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Cardboard');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('d',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Glass');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('e',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Synthetics');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('h',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'metal');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('j',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Metal and glass');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('k',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Synthetics and glass');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('m',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Mixed collection');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('u',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Unknown');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('z',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Other');

-- Microform
INSERT INTO config.marc21_physical_characteristic_type_map (ptype_key, label) VALUES ('h','Microform');
INSERT INTO config.marc21_physical_characteristic_subfield_map (ptype_key,subfield,start_pos,length,label) VALUES ('h','b','1','1','SMD');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('a',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Aperture card');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('b',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Microfilm cartridge');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('c',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Microfilm cassette');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('d',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Microfilm reel');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('e',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Microfiche');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('f',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Microfiche cassette');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('g',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Microopaque');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('u',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Unspecified');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('z',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Other');
INSERT INTO config.marc21_physical_characteristic_subfield_map (ptype_key,subfield,start_pos,length,label) VALUES ('h','d','3','1','Positive/negative');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('a',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Positive');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('b',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Negative');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('m',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Mixed');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('u',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Unknown');
INSERT INTO config.marc21_physical_characteristic_subfield_map (ptype_key,subfield,start_pos,length,label) VALUES ('h','e','4','1','Dimensions');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('a',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'8 mm.');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('e',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'16 mm.');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('f',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'35 mm.');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('g',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'70mm.');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('h',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'105 mm.');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('l',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'3 x 5 in. (8 x 13 cm.)');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('m',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'4 x 6 in. (11 x 15 cm.)');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('o',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'6 x 9 in. (16 x 23 cm.)');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('p',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'3 1/4 x 7 3/8 in. (9 x 19 cm.)');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('u',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Unknown');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('z',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Other');
INSERT INTO config.marc21_physical_characteristic_subfield_map (ptype_key,subfield,start_pos,length,label) VALUES ('h','f','5','4','Reduction ratio range/Reduction ratio');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('a',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Low (1-16x)');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('b',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Normal (16-30x)');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('c',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'High (31-60x)');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('d',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Very high (61-90x)');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('e',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Ultra (90x-)');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('u',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Unknown');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('v',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Reduction ratio varies');
INSERT INTO config.marc21_physical_characteristic_subfield_map (ptype_key,subfield,start_pos,length,label) VALUES ('h','g','9','1','Color');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('b',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Black-and-white');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('c',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Multicolored');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('m',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Mixed');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('u',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Unknown');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('z',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Other');
INSERT INTO config.marc21_physical_characteristic_subfield_map (ptype_key,subfield,start_pos,length,label) VALUES ('h','h','10','1','Emulsion on film');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('a',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Silver halide');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('b',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Diazo');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('c',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Vesicular');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('m',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Mixed');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('n',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Not applicable');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('u',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Unknown');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('z',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Other');
INSERT INTO config.marc21_physical_characteristic_subfield_map (ptype_key,subfield,start_pos,length,label) VALUES ('h','i','11','1','Quality assurance target(s)');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('a',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'1st gen. master');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('b',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Printing master');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('c',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Service copy');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('m',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Mixed generation');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('u',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Unknown');
INSERT INTO config.marc21_physical_characteristic_subfield_map (ptype_key,subfield,start_pos,length,label) VALUES ('h','j','12','1','Base of film');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('a',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Safety base, undetermined');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('c',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Safety base, acetate undetermined');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('d',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Safety base, diacetate');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('l',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Nitrate base');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('m',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Mixed base');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('n',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Not applicable');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('p',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Safety base, polyester');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('r',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Safety base, mixed');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('t',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Safety base, triacetate');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('u',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Unknown');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('z',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Other');

-- Non-projected Graphic
INSERT INTO config.marc21_physical_characteristic_type_map (ptype_key, label) VALUES ('k','Non-projected Graphic');
INSERT INTO config.marc21_physical_characteristic_subfield_map (ptype_key,subfield,start_pos,length,label) VALUES ('k','b','1','1','SMD');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('c',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Collage');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('d',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Drawing');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('e',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Painting');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('f',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Photo-mechanical print');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('g',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Photonegative');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('h',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Photoprint');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('i',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Picture');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('j',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Print');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('l',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Technical drawing');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('n',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Chart');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('o',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Flash/activity card');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('u',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Unspecified');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('z',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Other');
INSERT INTO config.marc21_physical_characteristic_subfield_map (ptype_key,subfield,start_pos,length,label) VALUES ('k','d','3','1','Color');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('a',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'One color');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('b',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Black-and-white');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('c',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Multicolored');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('h',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Hand-colored');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('m',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Mixed');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('u',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Unknown');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('z',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Other');
INSERT INTO config.marc21_physical_characteristic_subfield_map (ptype_key,subfield,start_pos,length,label) VALUES ('k','e','4','1','Primary support material');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('a',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Canvas');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('b',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Bristol board');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('c',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Cardboard/illustration board');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('d',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Glass');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('e',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Synthetics');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('f',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Skins');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('g',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Textile');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('h',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Metal');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('m',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Mixed collection');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('o',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Paper');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('p',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Plaster');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('q',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Hardboard');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('r',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Porcelain');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('s',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Stone');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('t',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Wood');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('u',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Unknown');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('z',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Other');
INSERT INTO config.marc21_physical_characteristic_subfield_map (ptype_key,subfield,start_pos,length,label) VALUES ('k','f','5','1','Secondary support material');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('a',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Canvas');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('b',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Bristol board');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('c',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Cardboard/illustration board');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('d',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Glass');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('e',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Synthetics');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('f',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Skins');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('g',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Textile');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('h',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Metal');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('m',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Mixed collection');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('o',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Paper');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('p',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Plaster');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('q',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Hardboard');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('r',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Porcelain');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('s',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Stone');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('t',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Wood');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('u',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Unknown');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('z',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Other');

-- Motion Picture
INSERT INTO config.marc21_physical_characteristic_type_map (ptype_key, label) VALUES ('m','Motion Picture');
INSERT INTO config.marc21_physical_characteristic_subfield_map (ptype_key,subfield,start_pos,length,label) VALUES ('m','b','1','1','SMD');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('a',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Film cartridge');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('f',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Film cassette');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('r',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Film reel');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('u',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Unspecified');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('z',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Other');
INSERT INTO config.marc21_physical_characteristic_subfield_map (ptype_key,subfield,start_pos,length,label) VALUES ('m','d','3','1','Color');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('b',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Black-and-white');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('c',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Multicolored');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('h',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Hand-colored');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('m',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Mixed');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('u',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Unknown');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('z',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Other');
INSERT INTO config.marc21_physical_characteristic_subfield_map (ptype_key,subfield,start_pos,length,label) VALUES ('m','e','4','1','Motion picture presentation format');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('a',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Standard sound aperture, reduced frame');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('b',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Nonanamorphic (wide-screen)');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('c',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'3D');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('d',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Anamorphic (wide-screen)');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('e',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Other-wide screen format');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('f',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Standard. silent aperture, full frame');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('u',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Unknown');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('z',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Other');
INSERT INTO config.marc21_physical_characteristic_subfield_map (ptype_key,subfield,start_pos,length,label) VALUES ('m','f','5','1','Sound on medium or separate');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('a',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Sound on medium');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('b',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Sound separate from medium');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('u',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Unknown');
INSERT INTO config.marc21_physical_characteristic_subfield_map (ptype_key,subfield,start_pos,length,label) VALUES ('m','g','6','1','Medium for sound');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('a',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Optical sound track on motion picture film');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('b',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Magnetic sound track on motion picture film');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('c',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Magnetic audio tape in cartridge');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('d',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Sound disc');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('e',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Magnetic audio tape on reel');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('f',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Magnetic audio tape in cassette');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('g',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Optical and magnetic sound track on film');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('h',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Videotape');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('i',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Videodisc');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('u',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Unknown');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('z',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Other');
INSERT INTO config.marc21_physical_characteristic_subfield_map (ptype_key,subfield,start_pos,length,label) VALUES ('m','h','7','1','Dimensions');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('a',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Standard 8 mm.');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('b',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Super 8 mm./single 8 mm.');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('c',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'9.5 mm.');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('d',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'16 mm.');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('e',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'28 mm.');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('f',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'35 mm.');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('g',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'70 mm.');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('u',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Unknown');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('z',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Other');
INSERT INTO config.marc21_physical_characteristic_subfield_map (ptype_key,subfield,start_pos,length,label) VALUES ('m','i','8','1','Configuration of playback channels');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('k',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Mixed');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('m',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Monaural');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('n',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Not applicable');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('q',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Multichannel, surround or quadraphonic');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('s',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Stereophonic');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('u',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Unknown');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('z',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Other');
INSERT INTO config.marc21_physical_characteristic_subfield_map (ptype_key,subfield,start_pos,length,label) VALUES ('m','j','9','1','Production elements');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('a',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Work print');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('b',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Trims');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('c',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Outtakes');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('d',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Rushes');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('e',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Mixing tracks');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('f',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Title bands/inter-title rolls');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('g',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Production rolls');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('n',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Not applicable');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('z',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Other');

-- Remote-sensing Image
INSERT INTO config.marc21_physical_characteristic_type_map (ptype_key, label) VALUES ('r','Remote-sensing Image');
INSERT INTO config.marc21_physical_characteristic_subfield_map (ptype_key,subfield,start_pos,length,label) VALUES ('r','b','1','1','SMD');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('u',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Unspecified');
INSERT INTO config.marc21_physical_characteristic_subfield_map (ptype_key,subfield,start_pos,length,label) VALUES ('r','d','3','1','Altitude of sensor');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('a',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Surface');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('b',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Airborne');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('c',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Spaceborne');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('n',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Not applicable');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('u',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Unknown');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('z',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Other');
INSERT INTO config.marc21_physical_characteristic_subfield_map (ptype_key,subfield,start_pos,length,label) VALUES ('r','e','4','1','Attitude of sensor');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('a',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Low oblique');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('b',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'High oblique');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('c',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Vertical');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('n',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Not applicable');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('u',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Unknown');
INSERT INTO config.marc21_physical_characteristic_subfield_map (ptype_key,subfield,start_pos,length,label) VALUES ('r','f','5','1','Cloud cover');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('0',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'0-09%');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('1',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'10-19%');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('2',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'20-29%');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('3',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'30-39%');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('4',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'40-49%');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('5',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'50-59%');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('6',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'60-69%');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('7',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'70-79%');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('8',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'80-89%');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('9',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'90-100%');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('n',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Not applicable');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('u',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Unknown');
INSERT INTO config.marc21_physical_characteristic_subfield_map (ptype_key,subfield,start_pos,length,label) VALUES ('r','g','6','1','Platform construction type');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('a',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Balloon');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('b',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Aircraft-low altitude');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('c',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Aircraft-medium altitude');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('d',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Aircraft-high altitude');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('e',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Manned spacecraft');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('f',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Unmanned spacecraft');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('g',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Land-based remote-sensing device');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('h',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Water surface-based remote-sensing device');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('i',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Submersible remote-sensing device');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('n',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Not applicable');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('u',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Unknown');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('z',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Other');
INSERT INTO config.marc21_physical_characteristic_subfield_map (ptype_key,subfield,start_pos,length,label) VALUES ('r','h','7','1','Platform use category');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('a',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Meteorological');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('b',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Surface observing');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('c',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Space observing');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('m',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Mixed uses');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('n',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Not applicable');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('u',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Unknown');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('z',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Other');
INSERT INTO config.marc21_physical_characteristic_subfield_map (ptype_key,subfield,start_pos,length,label) VALUES ('r','i','8','1','Sensor type');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('a',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Active');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('b',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Passive');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('u',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Unknown');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('z',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Other');
INSERT INTO config.marc21_physical_characteristic_subfield_map (ptype_key,subfield,start_pos,length,label) VALUES ('r','j','9','2','Data type');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('aa',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Visible light');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('da',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Near infrared');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('db',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Middle infrared');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('dc',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Far infrared');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('dd',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Thermal infrared');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('de',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Shortwave infrared (SWIR)');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('df',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Reflective infrared');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('dv',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Combinations');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('dz',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Other infrared data');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('ga',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Sidelooking airborne radar (SLAR)');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('gb',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Synthetic aperture radar (SAR-single frequency)');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('gc',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'SAR-multi-frequency (multichannel)');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('gd',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'SAR-like polarization');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('ge',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'SAR-cross polarization');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('gf',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Infometric SAR');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('gg',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Polarmetric SAR');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('gu',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Passive microwave mapping');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('gz',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Other microwave data');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('ja',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Far ultraviolet');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('jb',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Middle ultraviolet');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('jc',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Near ultraviolet');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('jv',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Ultraviolet combinations');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('jz',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Other ultraviolet data');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('ma',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Multi-spectral, multidata');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('mb',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Multi-temporal');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('mm',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Combination of various data types');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('nn',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Not applicable');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('pa',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Sonar-water depth');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('pb',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Sonar-bottom topography images, sidescan');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('pc',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Sonar-bottom topography, near-surface');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('pd',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Sonar-bottom topography, near-bottom');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('pe',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Seismic surveys');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('pz',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Other acoustical data');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('ra',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Gravity anomales (general)');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('rb',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Free-air');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('rc',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Bouger');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('rd',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Isostatic');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('sa',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Magnetic field');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('ta',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Radiometric surveys');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('uu',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Unknown');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('zz',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Other');

-- Sound Recording
INSERT INTO config.marc21_physical_characteristic_type_map (ptype_key, label) VALUES ('s','Sound Recording');
INSERT INTO config.marc21_physical_characteristic_subfield_map (ptype_key,subfield,start_pos,length,label) VALUES ('s','b','1','1','SMD');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('d',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Sound disc');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('e',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Cylinder');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('g',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Sound cartridge');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('i',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Sound-track film');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('q',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Roll');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('s',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Sound cassette');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('t',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Sound-tape reel');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('u',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Unspecified');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('w',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Wire recording');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('z',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Other');
INSERT INTO config.marc21_physical_characteristic_subfield_map (ptype_key,subfield,start_pos,length,label) VALUES ('s','d','3','1','Speed');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('a',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'16 rpm');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('b',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'33 1/3 rpm');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('c',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'45 rpm');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('d',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'78 rpm');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('e',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'8 rpm');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('f',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'1.4 mps');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('h',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'120 rpm');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('i',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'160 rpm');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('k',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'15/16 ips');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('l',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'1 7/8 ips');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('m',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'3 3/4 ips');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('o',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'7 1/2 ips');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('p',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'15 ips');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('r',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'30 ips');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('u',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Unknown');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('z',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Other');
INSERT INTO config.marc21_physical_characteristic_subfield_map (ptype_key,subfield,start_pos,length,label) VALUES ('s','e','4','1','Configuration of playback channels');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('m',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Monaural');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('q',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Quadraphonic');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('s',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Stereophonic');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('u',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Unknown');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('z',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Other');
INSERT INTO config.marc21_physical_characteristic_subfield_map (ptype_key,subfield,start_pos,length,label) VALUES ('s','f','5','1','Groove width or pitch');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('m',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Microgroove/fine');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('n',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Not applicable');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('s',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Coarse/standard');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('u',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Unknown');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('z',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Other');
INSERT INTO config.marc21_physical_characteristic_subfield_map (ptype_key,subfield,start_pos,length,label) VALUES ('s','g','6','1','Dimensions');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('a',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'3 in.');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('b',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'5 in.');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('c',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'7 in.');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('d',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'10 in.');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('e',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'12 in.');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('f',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'16 in.');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('g',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'4 3/4 in. (12 cm.)');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('j',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'3 7/8 x 2 1/2 in.');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('n',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Not applicable');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('o',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'5 1/4 x 3 7/8 in.');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('s',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'2 3/4 x 4 in.');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('u',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Unknown');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('z',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Other');
INSERT INTO config.marc21_physical_characteristic_subfield_map (ptype_key,subfield,start_pos,length,label) VALUES ('s','h','7','1','Tape width');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('l',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'1/8 in.');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('m',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'1/4in.');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('n',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Not applicable');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('o',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'1/2 in.');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('p',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'1 in.');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('u',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Unknown');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('z',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Other');
INSERT INTO config.marc21_physical_characteristic_subfield_map (ptype_key,subfield,start_pos,length,label) VALUES ('s','i','8','1','Tape configuration ');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('a',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Full (1) track');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('b',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Half (2) track');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('c',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Quarter (4) track');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('d',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'8 track');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('e',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'12 track');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('f',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'16 track');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('n',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Not applicable');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('u',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Unknown');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('z',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Other');
INSERT INTO config.marc21_physical_characteristic_subfield_map (ptype_key,subfield,start_pos,length,label) VALUES ('s','m','12','1','Special playback');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('a',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'NAB standard');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('b',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'CCIR standard');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('c',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Dolby-B encoded, standard Dolby');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('d',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'dbx encoded');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('e',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Digital recording');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('f',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Dolby-A encoded');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('g',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Dolby-C encoded');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('h',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'CX encoded');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('n',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Not applicable');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('u',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Unknown');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('z',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Other');
INSERT INTO config.marc21_physical_characteristic_subfield_map (ptype_key,subfield,start_pos,length,label) VALUES ('s','n','13','1','Capture and storage');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('a',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Acoustical capture, direct storage');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('b',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Direct storage, not acoustical');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('d',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Digital storage');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('e',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Analog electrical storage');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('u',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Unknown');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('z',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Other');

-- Videorecording
INSERT INTO config.marc21_physical_characteristic_type_map (ptype_key, label) VALUES ('v','Videorecording');
INSERT INTO config.marc21_physical_characteristic_subfield_map (ptype_key,subfield,start_pos,length,label) VALUES ('v','b','1','1','SMD');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('c',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Videocartridge');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('d',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Videodisc');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('f',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Videocassette');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('r',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Videoreel');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('u',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Unspecified');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('z',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Other');
INSERT INTO config.marc21_physical_characteristic_subfield_map (ptype_key,subfield,start_pos,length,label) VALUES ('v','d','3','1','Color');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('b',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Black-and-white');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('c',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Multicolored');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('m',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Mixed');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('n',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Not applicable');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('u',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Unknown');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('z',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Other');
INSERT INTO config.marc21_physical_characteristic_subfield_map (ptype_key,subfield,start_pos,length,label) VALUES ('v','e','4','1','Videorecording format');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('a',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Beta');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('b',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'VHS');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('c',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'U-matic');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('d',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'EIAJ');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('e',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Type C');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('f',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Quadruplex');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('g',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Laserdisc');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('h',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'CED');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('i',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Betacam');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('j',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Betacam SP');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('k',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Super-VHS');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('m',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'M-II');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('o',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'D-2');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('p',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'8 mm.');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('q',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Hi-8 mm.');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('u',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Unknown');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('v',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'DVD');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('z',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Other');
INSERT INTO config.marc21_physical_characteristic_subfield_map (ptype_key,subfield,start_pos,length,label) VALUES ('v','f','5','1','Sound on medium or separate');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('a',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Sound on medium');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('b',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Sound separate from medium');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('u',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Unknown');
INSERT INTO config.marc21_physical_characteristic_subfield_map (ptype_key,subfield,start_pos,length,label) VALUES ('v','g','6','1','Medium for sound');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('a',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Optical sound track on motion picture film');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('b',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Magnetic sound track on motion picture film');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('c',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Magnetic audio tape in cartridge');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('d',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Sound disc');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('e',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Magnetic audio tape on reel');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('f',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Magnetic audio tape in cassette');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('g',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Optical and magnetic sound track on motion picture film');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('h',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Videotape');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('i',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Videodisc');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('u',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Unknown');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('z',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Other');
INSERT INTO config.marc21_physical_characteristic_subfield_map (ptype_key,subfield,start_pos,length,label) VALUES ('v','h','7','1','Dimensions');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('a',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'8 mm.');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('m',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'1/4 in.');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('o',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'1/2 in.');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('p',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'1 in.');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('q',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'2 in.');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('r',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'3/4 in.');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('u',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Unknown');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('z',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Other');
INSERT INTO config.marc21_physical_characteristic_subfield_map (ptype_key,subfield,start_pos,length,label) VALUES ('v','i','8','1','Configuration of playback channel');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('k',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Mixed');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('m',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Monaural');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('n',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Not applicable');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('q',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Multichannel, surround or quadraphonic');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('s',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Stereophonic');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('u',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Unknown');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('z',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Other');

-- Fixed Field position data -- 0-based!
INSERT INTO config.marc21_ff_pos_map (fixed_field, tag, rec_type,start_pos, length, default_val) VALUES ('Alph', '006', 'SER', 16, 1, ' ');
INSERT INTO config.marc21_ff_pos_map (fixed_field, tag, rec_type,start_pos, length, default_val) VALUES ('Alph', '008', 'SER', 33, 1, ' ');
INSERT INTO config.marc21_ff_pos_map (fixed_field, tag, rec_type,start_pos, length, default_val) VALUES ('Audn', '006', 'BKS', 5, 1, ' ');
INSERT INTO config.marc21_ff_pos_map (fixed_field, tag, rec_type,start_pos, length, default_val) VALUES ('Audn', '006', 'COM', 5, 1, ' ');
INSERT INTO config.marc21_ff_pos_map (fixed_field, tag, rec_type,start_pos, length, default_val) VALUES ('Audn', '006', 'REC', 5, 1, ' ');
INSERT INTO config.marc21_ff_pos_map (fixed_field, tag, rec_type,start_pos, length, default_val) VALUES ('Audn', '006', 'SCO', 5, 1, ' ');
INSERT INTO config.marc21_ff_pos_map (fixed_field, tag, rec_type,start_pos, length, default_val) VALUES ('Audn', '006', 'SER', 5, 1, ' ');
INSERT INTO config.marc21_ff_pos_map (fixed_field, tag, rec_type,start_pos, length, default_val) VALUES ('Audn', '006', 'VIS', 5, 1, ' ');
INSERT INTO config.marc21_ff_pos_map (fixed_field, tag, rec_type,start_pos, length, default_val) VALUES ('Audn', '008', 'BKS', 22, 1, ' ');
INSERT INTO config.marc21_ff_pos_map (fixed_field, tag, rec_type,start_pos, length, default_val) VALUES ('Audn', '008', 'COM', 22, 1, ' ');
INSERT INTO config.marc21_ff_pos_map (fixed_field, tag, rec_type,start_pos, length, default_val) VALUES ('Audn', '008', 'REC', 22, 1, ' ');
INSERT INTO config.marc21_ff_pos_map (fixed_field, tag, rec_type,start_pos, length, default_val) VALUES ('Audn', '008', 'SCO', 22, 1, ' ');
INSERT INTO config.marc21_ff_pos_map (fixed_field, tag, rec_type,start_pos, length, default_val) VALUES ('Audn', '008', 'SER', 22, 1, ' ');
INSERT INTO config.marc21_ff_pos_map (fixed_field, tag, rec_type,start_pos, length, default_val) VALUES ('Audn', '008', 'VIS', 22, 1, ' ');
INSERT INTO config.marc21_ff_pos_map (fixed_field, tag, rec_type,start_pos, length, default_val) VALUES ('BLvl', 'ldr', 'BKS', 7, 1, 'm');
INSERT INTO config.marc21_ff_pos_map (fixed_field, tag, rec_type,start_pos, length, default_val) VALUES ('BLvl', 'ldr', 'COM', 7, 1, 'm');
INSERT INTO config.marc21_ff_pos_map (fixed_field, tag, rec_type,start_pos, length, default_val) VALUES ('BLvl', 'ldr', 'MAP', 7, 1, 'm');
INSERT INTO config.marc21_ff_pos_map (fixed_field, tag, rec_type,start_pos, length, default_val) VALUES ('BLvl', 'ldr', 'MIX', 7, 1, 'c');
INSERT INTO config.marc21_ff_pos_map (fixed_field, tag, rec_type,start_pos, length, default_val) VALUES ('BLvl', 'ldr', 'REC', 7, 1, 'm');
INSERT INTO config.marc21_ff_pos_map (fixed_field, tag, rec_type,start_pos, length, default_val) VALUES ('BLvl', 'ldr', 'SCO', 7, 1, 'm');
INSERT INTO config.marc21_ff_pos_map (fixed_field, tag, rec_type,start_pos, length, default_val) VALUES ('BLvl', 'ldr', 'SER', 7, 1, 's');
INSERT INTO config.marc21_ff_pos_map (fixed_field, tag, rec_type,start_pos, length, default_val) VALUES ('BLvl', 'ldr', 'VIS', 7, 1, 'm');
INSERT INTO config.marc21_ff_pos_map (fixed_field, tag, rec_type,start_pos, length, default_val) VALUES ('Biog', '006', 'BKS', 17, 1, ' ');
INSERT INTO config.marc21_ff_pos_map (fixed_field, tag, rec_type,start_pos, length, default_val) VALUES ('Biog', '008', 'BKS', 34, 1, ' ');
INSERT INTO config.marc21_ff_pos_map (fixed_field, tag, rec_type,start_pos, length, default_val) VALUES ('Conf', '006', 'BKS', 7, 4, ' ');
INSERT INTO config.marc21_ff_pos_map (fixed_field, tag, rec_type,start_pos, length, default_val) VALUES ('Conf', '006', 'SER', 8, 3, ' ');
INSERT INTO config.marc21_ff_pos_map (fixed_field, tag, rec_type,start_pos, length, default_val) VALUES ('Conf', '008', 'BKS', 24, 4, ' ');
INSERT INTO config.marc21_ff_pos_map (fixed_field, tag, rec_type,start_pos, length, default_val) VALUES ('Conf', '008', 'SER', 25, 3, ' ');
INSERT INTO config.marc21_ff_pos_map (fixed_field, tag, rec_type,start_pos, length, default_val) VALUES ('Ctrl', 'ldr', 'BKS', 8, 1, ' ');
INSERT INTO config.marc21_ff_pos_map (fixed_field, tag, rec_type,start_pos, length, default_val) VALUES ('Ctrl', 'ldr', 'COM', 8, 1, ' ');
INSERT INTO config.marc21_ff_pos_map (fixed_field, tag, rec_type,start_pos, length, default_val) VALUES ('Ctrl', 'ldr', 'MAP', 8, 1, ' ');
INSERT INTO config.marc21_ff_pos_map (fixed_field, tag, rec_type,start_pos, length, default_val) VALUES ('Ctrl', 'ldr', 'MIX', 8, 1, ' ');
INSERT INTO config.marc21_ff_pos_map (fixed_field, tag, rec_type,start_pos, length, default_val) VALUES ('Ctrl', 'ldr', 'REC', 8, 1, ' ');
INSERT INTO config.marc21_ff_pos_map (fixed_field, tag, rec_type,start_pos, length, default_val) VALUES ('Ctrl', 'ldr', 'SCO', 8, 1, ' ');
INSERT INTO config.marc21_ff_pos_map (fixed_field, tag, rec_type,start_pos, length, default_val) VALUES ('Ctrl', 'ldr', 'SER', 8, 1, ' ');
INSERT INTO config.marc21_ff_pos_map (fixed_field, tag, rec_type,start_pos, length, default_val) VALUES ('Ctrl', 'ldr', 'VIS', 8, 1, ' ');
INSERT INTO config.marc21_ff_pos_map (fixed_field, tag, rec_type,start_pos, length, default_val) VALUES ('Ctry', '008', 'BKS', 15, 3, ' ');
INSERT INTO config.marc21_ff_pos_map (fixed_field, tag, rec_type,start_pos, length, default_val) VALUES ('Ctry', '008', 'COM', 15, 3, ' ');
INSERT INTO config.marc21_ff_pos_map (fixed_field, tag, rec_type,start_pos, length, default_val) VALUES ('Ctry', '008', 'MAP', 15, 3, ' ');
INSERT INTO config.marc21_ff_pos_map (fixed_field, tag, rec_type,start_pos, length, default_val) VALUES ('Ctry', '008', 'MIX', 15, 3, ' ');
INSERT INTO config.marc21_ff_pos_map (fixed_field, tag, rec_type,start_pos, length, default_val) VALUES ('Ctry', '008', 'REC', 15, 3, ' ');
INSERT INTO config.marc21_ff_pos_map (fixed_field, tag, rec_type,start_pos, length, default_val) VALUES ('Ctry', '008', 'SCO', 15, 3, ' ');
INSERT INTO config.marc21_ff_pos_map (fixed_field, tag, rec_type,start_pos, length, default_val) VALUES ('Ctry', '008', 'SER', 15, 3, ' ');
INSERT INTO config.marc21_ff_pos_map (fixed_field, tag, rec_type,start_pos, length, default_val) VALUES ('Ctry', '008', 'VIS', 15, 3, ' ');
INSERT INTO config.marc21_ff_pos_map (fixed_field, tag, rec_type,start_pos, length, default_val) VALUES ('Date1', '008', 'BKS', 7, 4, ' ');
INSERT INTO config.marc21_ff_pos_map (fixed_field, tag, rec_type,start_pos, length, default_val) VALUES ('Date1', '008', 'COM', 7, 4, ' ');
INSERT INTO config.marc21_ff_pos_map (fixed_field, tag, rec_type,start_pos, length, default_val) VALUES ('Date1', '008', 'MAP', 7, 4, ' ');
INSERT INTO config.marc21_ff_pos_map (fixed_field, tag, rec_type,start_pos, length, default_val) VALUES ('Date1', '008', 'MIX', 7, 4, ' ');
INSERT INTO config.marc21_ff_pos_map (fixed_field, tag, rec_type,start_pos, length, default_val) VALUES ('Date1', '008', 'REC', 7, 4, ' ');
INSERT INTO config.marc21_ff_pos_map (fixed_field, tag, rec_type,start_pos, length, default_val) VALUES ('Date1', '008', 'SCO', 7, 4, ' ');
INSERT INTO config.marc21_ff_pos_map (fixed_field, tag, rec_type,start_pos, length, default_val) VALUES ('Date1', '008', 'SER', 7, 4, ' ');
INSERT INTO config.marc21_ff_pos_map (fixed_field, tag, rec_type,start_pos, length, default_val) VALUES ('Date1', '008', 'VIS', 7, 4, ' ');
INSERT INTO config.marc21_ff_pos_map (fixed_field, tag, rec_type,start_pos, length, default_val) VALUES ('Date2', '008', 'BKS', 11, 4, ' ');
INSERT INTO config.marc21_ff_pos_map (fixed_field, tag, rec_type,start_pos, length, default_val) VALUES ('Date2', '008', 'COM', 11, 4, ' ');
INSERT INTO config.marc21_ff_pos_map (fixed_field, tag, rec_type,start_pos, length, default_val) VALUES ('Date2', '008', 'MAP', 11, 4, ' ');
INSERT INTO config.marc21_ff_pos_map (fixed_field, tag, rec_type,start_pos, length, default_val) VALUES ('Date2', '008', 'MIX', 11, 4, ' ');
INSERT INTO config.marc21_ff_pos_map (fixed_field, tag, rec_type,start_pos, length, default_val) VALUES ('Date2', '008', 'REC', 11, 4, ' ');
INSERT INTO config.marc21_ff_pos_map (fixed_field, tag, rec_type,start_pos, length, default_val) VALUES ('Date2', '008', 'SCO', 11, 4, ' ');
INSERT INTO config.marc21_ff_pos_map (fixed_field, tag, rec_type,start_pos, length, default_val) VALUES ('Date2', '008', 'SER', 11, 4, '9');
INSERT INTO config.marc21_ff_pos_map (fixed_field, tag, rec_type,start_pos, length, default_val) VALUES ('Date2', '008', 'VIS', 11, 4, ' ');
INSERT INTO config.marc21_ff_pos_map (fixed_field, tag, rec_type,start_pos, length, default_val) VALUES ('Desc', 'ldr', 'BKS', 18, 1, ' ');
INSERT INTO config.marc21_ff_pos_map (fixed_field, tag, rec_type,start_pos, length, default_val) VALUES ('Desc', 'ldr', 'COM', 18, 1, ' ');
INSERT INTO config.marc21_ff_pos_map (fixed_field, tag, rec_type,start_pos, length, default_val) VALUES ('Desc', 'ldr', 'MAP', 18, 1, ' ');
INSERT INTO config.marc21_ff_pos_map (fixed_field, tag, rec_type,start_pos, length, default_val) VALUES ('Desc', 'ldr', 'MIX', 18, 1, ' ');
INSERT INTO config.marc21_ff_pos_map (fixed_field, tag, rec_type,start_pos, length, default_val) VALUES ('Desc', 'ldr', 'REC', 18, 1, ' ');
INSERT INTO config.marc21_ff_pos_map (fixed_field, tag, rec_type,start_pos, length, default_val) VALUES ('Desc', 'ldr', 'SCO', 18, 1, ' ');
INSERT INTO config.marc21_ff_pos_map (fixed_field, tag, rec_type,start_pos, length, default_val) VALUES ('Desc', 'ldr', 'SER', 18, 1, ' ');
INSERT INTO config.marc21_ff_pos_map (fixed_field, tag, rec_type,start_pos, length, default_val) VALUES ('Desc', 'ldr', 'VIS', 18, 1, ' ');
INSERT INTO config.marc21_ff_pos_map (fixed_field, tag, rec_type,start_pos, length, default_val) VALUES ('DtSt', '008', 'BKS', 6, 1, ' ');
INSERT INTO config.marc21_ff_pos_map (fixed_field, tag, rec_type,start_pos, length, default_val) VALUES ('DtSt', '008', 'COM', 6, 1, ' ');
INSERT INTO config.marc21_ff_pos_map (fixed_field, tag, rec_type,start_pos, length, default_val) VALUES ('DtSt', '008', 'MAP', 6, 1, ' ');
INSERT INTO config.marc21_ff_pos_map (fixed_field, tag, rec_type,start_pos, length, default_val) VALUES ('DtSt', '008', 'MIX', 6, 1, ' ');
INSERT INTO config.marc21_ff_pos_map (fixed_field, tag, rec_type,start_pos, length, default_val) VALUES ('DtSt', '008', 'REC', 6, 1, ' ');
INSERT INTO config.marc21_ff_pos_map (fixed_field, tag, rec_type,start_pos, length, default_val) VALUES ('DtSt', '008', 'SCO', 6, 1, ' ');
INSERT INTO config.marc21_ff_pos_map (fixed_field, tag, rec_type,start_pos, length, default_val) VALUES ('DtSt', '008', 'SER', 6, 1, 'c');
INSERT INTO config.marc21_ff_pos_map (fixed_field, tag, rec_type,start_pos, length, default_val) VALUES ('DtSt', '008', 'VIS', 6, 1, ' ');
INSERT INTO config.marc21_ff_pos_map (fixed_field, tag, rec_type,start_pos, length, default_val) VALUES ('ELvl', 'ldr', 'BKS', 17, 1, ' ');
INSERT INTO config.marc21_ff_pos_map (fixed_field, tag, rec_type,start_pos, length, default_val) VALUES ('ELvl', 'ldr', 'COM', 17, 1, ' ');
INSERT INTO config.marc21_ff_pos_map (fixed_field, tag, rec_type,start_pos, length, default_val) VALUES ('ELvl', 'ldr', 'MAP', 17, 1, ' ');
INSERT INTO config.marc21_ff_pos_map (fixed_field, tag, rec_type,start_pos, length, default_val) VALUES ('ELvl', 'ldr', 'MIX', 17, 1, ' ');
INSERT INTO config.marc21_ff_pos_map (fixed_field, tag, rec_type,start_pos, length, default_val) VALUES ('ELvl', 'ldr', 'REC', 17, 1, ' ');
INSERT INTO config.marc21_ff_pos_map (fixed_field, tag, rec_type,start_pos, length, default_val) VALUES ('ELvl', 'ldr', 'SCO', 17, 1, ' ');
INSERT INTO config.marc21_ff_pos_map (fixed_field, tag, rec_type,start_pos, length, default_val) VALUES ('ELvl', 'ldr', 'SER', 17, 1, ' ');
INSERT INTO config.marc21_ff_pos_map (fixed_field, tag, rec_type,start_pos, length, default_val) VALUES ('ELvl', 'ldr', 'VIS', 17, 1, ' ');
INSERT INTO config.marc21_ff_pos_map (fixed_field, tag, rec_type,start_pos, length, default_val) VALUES ('Fest', '006', 'BKS', 13, 1, '0');
INSERT INTO config.marc21_ff_pos_map (fixed_field, tag, rec_type,start_pos, length, default_val) VALUES ('Fest', '008', 'BKS', 30, 1, '0');
INSERT INTO config.marc21_ff_pos_map (fixed_field, tag, rec_type,start_pos, length, default_val) VALUES ('Form', '006', 'BKS', 6, 1, ' ');
INSERT INTO config.marc21_ff_pos_map (fixed_field, tag, rec_type,start_pos, length, default_val) VALUES ('Form', '006', 'MAP', 12, 1, ' ');
INSERT INTO config.marc21_ff_pos_map (fixed_field, tag, rec_type,start_pos, length, default_val) VALUES ('Form', '006', 'MIX', 6, 1, ' ');
INSERT INTO config.marc21_ff_pos_map (fixed_field, tag, rec_type,start_pos, length, default_val) VALUES ('Form', '006', 'REC', 6, 1, ' ');
INSERT INTO config.marc21_ff_pos_map (fixed_field, tag, rec_type,start_pos, length, default_val) VALUES ('Form', '006', 'SCO', 6, 1, ' ');
INSERT INTO config.marc21_ff_pos_map (fixed_field, tag, rec_type,start_pos, length, default_val) VALUES ('Form', '006', 'SER', 6, 1, ' ');
INSERT INTO config.marc21_ff_pos_map (fixed_field, tag, rec_type,start_pos, length, default_val) VALUES ('Form', '006', 'VIS', 12, 1, ' ');
INSERT INTO config.marc21_ff_pos_map (fixed_field, tag, rec_type,start_pos, length, default_val) VALUES ('Form', '008', 'BKS', 23, 1, ' ');
INSERT INTO config.marc21_ff_pos_map (fixed_field, tag, rec_type,start_pos, length, default_val) VALUES ('Form', '008', 'MAP', 29, 1, ' ');
INSERT INTO config.marc21_ff_pos_map (fixed_field, tag, rec_type,start_pos, length, default_val) VALUES ('Form', '008', 'MIX', 23, 1, ' ');
INSERT INTO config.marc21_ff_pos_map (fixed_field, tag, rec_type,start_pos, length, default_val) VALUES ('Form', '008', 'REC', 23, 1, ' ');
INSERT INTO config.marc21_ff_pos_map (fixed_field, tag, rec_type,start_pos, length, default_val) VALUES ('Form', '008', 'SCO', 23, 1, ' ');
INSERT INTO config.marc21_ff_pos_map (fixed_field, tag, rec_type,start_pos, length, default_val) VALUES ('Form', '008', 'SER', 23, 1, ' ');
INSERT INTO config.marc21_ff_pos_map (fixed_field, tag, rec_type,start_pos, length, default_val) VALUES ('Form', '008', 'VIS', 29, 1, ' ');
INSERT INTO config.marc21_ff_pos_map (fixed_field, tag, rec_type,start_pos, length, default_val) VALUES ('GPub', '006', 'BKS', 11, 1, ' ');
INSERT INTO config.marc21_ff_pos_map (fixed_field, tag, rec_type,start_pos, length, default_val) VALUES ('GPub', '006', 'COM', 11, 1, ' ');
INSERT INTO config.marc21_ff_pos_map (fixed_field, tag, rec_type,start_pos, length, default_val) VALUES ('GPub', '006', 'MAP', 11, 1, ' ');
INSERT INTO config.marc21_ff_pos_map (fixed_field, tag, rec_type,start_pos, length, default_val) VALUES ('GPub', '006', 'SER', 11, 1, ' ');
INSERT INTO config.marc21_ff_pos_map (fixed_field, tag, rec_type,start_pos, length, default_val) VALUES ('GPub', '006', 'VIS', 11, 1, ' ');
INSERT INTO config.marc21_ff_pos_map (fixed_field, tag, rec_type,start_pos, length, default_val) VALUES ('GPub', '008', 'BKS', 28, 1, ' ');
INSERT INTO config.marc21_ff_pos_map (fixed_field, tag, rec_type,start_pos, length, default_val) VALUES ('GPub', '008', 'COM', 28, 1, ' ');
INSERT INTO config.marc21_ff_pos_map (fixed_field, tag, rec_type,start_pos, length, default_val) VALUES ('GPub', '008', 'MAP', 28, 1, ' ');
INSERT INTO config.marc21_ff_pos_map (fixed_field, tag, rec_type,start_pos, length, default_val) VALUES ('GPub', '008', 'SER', 28, 1, ' ');
INSERT INTO config.marc21_ff_pos_map (fixed_field, tag, rec_type,start_pos, length, default_val) VALUES ('GPub', '008', 'VIS', 28, 1, ' ');
INSERT INTO config.marc21_ff_pos_map (fixed_field, tag, rec_type,start_pos, length, default_val) VALUES ('Ills', '006', 'BKS', 1, 4, ' ');
INSERT INTO config.marc21_ff_pos_map (fixed_field, tag, rec_type,start_pos, length, default_val) VALUES ('Ills', '008', 'BKS', 18, 4, ' ');
INSERT INTO config.marc21_ff_pos_map (fixed_field, tag, rec_type,start_pos, length, default_val) VALUES ('Indx', '006', 'BKS', 14, 1, '0');
INSERT INTO config.marc21_ff_pos_map (fixed_field, tag, rec_type,start_pos, length, default_val) VALUES ('Indx', '006', 'MAP', 14, 1, '0');
INSERT INTO config.marc21_ff_pos_map (fixed_field, tag, rec_type,start_pos, length, default_val) VALUES ('Indx', '008', 'BKS', 31, 1, '0');
INSERT INTO config.marc21_ff_pos_map (fixed_field, tag, rec_type,start_pos, length, default_val) VALUES ('Indx', '008', 'MAP', 31, 1, '0');
INSERT INTO config.marc21_ff_pos_map (fixed_field, tag, rec_type,start_pos, length, default_val) VALUES ('Lang', '008', 'BKS', 35, 3, ' ');
INSERT INTO config.marc21_ff_pos_map (fixed_field, tag, rec_type,start_pos, length, default_val) VALUES ('Lang', '008', 'COM', 35, 3, ' ');
INSERT INTO config.marc21_ff_pos_map (fixed_field, tag, rec_type,start_pos, length, default_val) VALUES ('Lang', '008', 'MAP', 35, 3, ' ');
INSERT INTO config.marc21_ff_pos_map (fixed_field, tag, rec_type,start_pos, length, default_val) VALUES ('Lang', '008', 'MIX', 35, 3, ' ');
INSERT INTO config.marc21_ff_pos_map (fixed_field, tag, rec_type,start_pos, length, default_val) VALUES ('Lang', '008', 'REC', 35, 3, ' ');
INSERT INTO config.marc21_ff_pos_map (fixed_field, tag, rec_type,start_pos, length, default_val) VALUES ('Lang', '008', 'SCO', 35, 3, ' ');
INSERT INTO config.marc21_ff_pos_map (fixed_field, tag, rec_type,start_pos, length, default_val) VALUES ('Lang', '008', 'SER', 35, 3, ' ');
INSERT INTO config.marc21_ff_pos_map (fixed_field, tag, rec_type,start_pos, length, default_val) VALUES ('Lang', '008', 'VIS', 35, 3, ' ');
INSERT INTO config.marc21_ff_pos_map (fixed_field, tag, rec_type,start_pos, length, default_val) VALUES ('LitF', '006', 'BKS', 16, 1, '0');
INSERT INTO config.marc21_ff_pos_map (fixed_field, tag, rec_type,start_pos, length, default_val) VALUES ('LitF', '008', 'BKS', 33, 1, '0');
INSERT INTO config.marc21_ff_pos_map (fixed_field, tag, rec_type,start_pos, length, default_val) VALUES ('MRec', '008', 'BKS', 38, 1, ' ');
INSERT INTO config.marc21_ff_pos_map (fixed_field, tag, rec_type,start_pos, length, default_val) VALUES ('MRec', '008', 'COM', 38, 1, ' ');
INSERT INTO config.marc21_ff_pos_map (fixed_field, tag, rec_type,start_pos, length, default_val) VALUES ('MRec', '008', 'MAP', 38, 1, ' ');
INSERT INTO config.marc21_ff_pos_map (fixed_field, tag, rec_type,start_pos, length, default_val) VALUES ('MRec', '008', 'MIX', 38, 1, ' ');
INSERT INTO config.marc21_ff_pos_map (fixed_field, tag, rec_type,start_pos, length, default_val) VALUES ('MRec', '008', 'REC', 38, 1, ' ');
INSERT INTO config.marc21_ff_pos_map (fixed_field, tag, rec_type,start_pos, length, default_val) VALUES ('MRec', '008', 'SCO', 38, 1, ' ');
INSERT INTO config.marc21_ff_pos_map (fixed_field, tag, rec_type,start_pos, length, default_val) VALUES ('MRec', '008', 'SER', 38, 1, ' ');
INSERT INTO config.marc21_ff_pos_map (fixed_field, tag, rec_type,start_pos, length, default_val) VALUES ('MRec', '008', 'VIS', 38, 1, ' ');
INSERT INTO config.marc21_ff_pos_map (fixed_field, tag, rec_type,start_pos, length, default_val) VALUES ('S/L', '006', 'SER', 17, 1, '0');
INSERT INTO config.marc21_ff_pos_map (fixed_field, tag, rec_type,start_pos, length, default_val) VALUES ('S/L', '008', 'SER', 34, 1, '0');
INSERT INTO config.marc21_ff_pos_map (fixed_field, tag, rec_type,start_pos, length, default_val) VALUES ('TMat', '006', 'VIS', 16, 1, ' ');
INSERT INTO config.marc21_ff_pos_map (fixed_field, tag, rec_type,start_pos, length, default_val) VALUES ('TMat', '008', 'VIS', 33, 1, ' ');
INSERT INTO config.marc21_ff_pos_map (fixed_field, tag, rec_type,start_pos, length, default_val) VALUES ('Type', 'ldr', 'BKS', 6, 1, 'a');
INSERT INTO config.marc21_ff_pos_map (fixed_field, tag, rec_type,start_pos, length, default_val) VALUES ('Type', 'ldr', 'COM', 6, 1, 'm');
INSERT INTO config.marc21_ff_pos_map (fixed_field, tag, rec_type,start_pos, length, default_val) VALUES ('Type', 'ldr', 'MAP', 6, 1, 'e');
INSERT INTO config.marc21_ff_pos_map (fixed_field, tag, rec_type,start_pos, length, default_val) VALUES ('Type', 'ldr', 'MIX', 6, 1, 'p');
INSERT INTO config.marc21_ff_pos_map (fixed_field, tag, rec_type,start_pos, length, default_val) VALUES ('Type', 'ldr', 'REC', 6, 1, 'i');
INSERT INTO config.marc21_ff_pos_map (fixed_field, tag, rec_type,start_pos, length, default_val) VALUES ('Type', 'ldr', 'SCO', 6, 1, 'c');
INSERT INTO config.marc21_ff_pos_map (fixed_field, tag, rec_type,start_pos, length, default_val) VALUES ('Type', 'ldr', 'SER', 6, 1, 'a');
INSERT INTO config.marc21_ff_pos_map (fixed_field, tag, rec_type,start_pos, length, default_val) VALUES ('Type', 'ldr', 'VIS', 6, 1, 'g');


CREATE OR REPLACE FUNCTION biblio.marc21_record_type( rid BIGINT ) RETURNS config.marc21_rec_type_map AS $func$
DECLARE
	ldr         RECORD;
	tval        TEXT;
	tval_rec    RECORD;
	bval        TEXT;
	bval_rec    RECORD;
    retval      config.marc21_rec_type_map%ROWTYPE;
BEGIN
    SELECT * INTO ldr FROM metabib.full_rec WHERE record = rid AND tag = 'LDR' LIMIT 1;

    IF ldr.id IS NULL THEN
        SELECT * INTO retval FROM config.marc21_rec_type_map WHERE code = 'BKS';
        RETURN retval;
    END IF;

    SELECT * INTO tval_rec FROM config.marc21_ff_pos_map WHERE fixed_field = 'Type' LIMIT 1; -- They're all the same
    SELECT * INTO bval_rec FROM config.marc21_ff_pos_map WHERE fixed_field = 'BLvl' LIMIT 1; -- They're all the same


    tval := SUBSTRING( ldr.value, tval_rec.start_pos + 1, tval_rec.length );
    bval := SUBSTRING( ldr.value, bval_rec.start_pos + 1, bval_rec.length );

    -- RAISE NOTICE 'type %, blvl %, ldr %', tval, bval, ldr.value;

    SELECT * INTO retval FROM config.marc21_rec_type_map WHERE type_val LIKE '%' || tval || '%' AND blvl_val LIKE '%' || bval || '%';


    IF retval.code IS NULL THEN
        SELECT * INTO retval FROM config.marc21_rec_type_map WHERE code = 'BKS';
    END IF;

    RETURN retval;
END;
$func$ LANGUAGE PLPGSQL;

CREATE OR REPLACE FUNCTION biblio.marc21_extract_fixed_field( rid BIGINT, ff TEXT ) RETURNS TEXT AS $func$
DECLARE
    rtype       TEXT;
    ff_pos      RECORD;
    tag_data    RECORD;
    val         TEXT;
BEGIN
    rtype := (biblio.marc21_record_type( rid )).code;
    FOR ff_pos IN SELECT * FROM config.marc21_ff_pos_map WHERE fixed_field = ff AND rec_type = rtype ORDER BY tag DESC LOOP
        FOR tag_data IN SELECT * FROM metabib.full_rec WHERE tag = UPPER(ff_pos.tag) AND record = rid LOOP
            val := SUBSTRING( tag_data.value, ff_pos.start_pos + 1, ff_pos.length );
            RETURN val;
        END LOOP;
        val := REPEAT( ff_pos.default_val, ff_pos.length );
        RETURN val;
    END LOOP;

    RETURN NULL;
END;
$func$ LANGUAGE PLPGSQL;

CREATE TYPE biblio.marc21_physical_characteristics AS ( id INT, record BIGINT, ptype TEXT, subfield INT, value INT );
CREATE OR REPLACE FUNCTION biblio.marc21_physical_characteristics( rid BIGINT ) RETURNS SETOF biblio.marc21_physical_characteristics AS $func$
DECLARE
    rowid   INT := 0;
    _007    RECORD;
    ptype   config.marc21_physical_characteristic_type_map%ROWTYPE;
    psf     config.marc21_physical_characteristic_subfield_map%ROWTYPE;
    pval    config.marc21_physical_characteristic_value_map%ROWTYPE;
    retval  biblio.marc21_physical_characteristics%ROWTYPE;
BEGIN

    SELECT * INTO _007 FROM metabib.full_rec WHERE record = rid AND tag = '007' LIMIT 1;

    IF _007.id IS NOT NULL THEN
        SELECT * INTO ptype FROM config.marc21_physical_characteristic_type_map WHERE ptype_key = SUBSTRING( _007.value, 1, 1 );

        IF ptype.ptype_key IS NOT NULL THEN
            FOR psf IN SELECT * FROM config.marc21_physical_characteristic_subfield_map WHERE ptype_key = ptype.ptype_key LOOP
                SELECT * INTO pval FROM config.marc21_physical_characteristic_value_map WHERE ptype_subfield = psf.id AND value = SUBSTRING( _007.value, psf.start_pos + 1, psf.length );

                IF pval.id IS NOT NULL THEN
                    rowid := rowid + 1;
                    retval.id := rowid;
                    retval.record := rid;
                    retval.ptype := ptype.ptype_key;
                    retval.subfield := psf.id;
                    retval.value := pval.id;
                    RETURN NEXT retval;
                END IF;

            END LOOP;
        END IF;
    END IF;

    RETURN;
END;
$func$ LANGUAGE PLPGSQL;

COMMIT;
