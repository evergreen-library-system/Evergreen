DROP TABLE joined_legacy;
DROP TABLE legacy_copy_status_map;

BEGIN;

-- Build the status map ... by hand, which suxorz.
CREATE TABLE legacy_copy_status_map (id int, name text);
COPY legacy_copy_status_map FROM STDIN;
0	ADULT
0	AV
0	AWARDBOOKS
0	BHDESK
2	BINDERY
0	BIOGRAPHY
0	BOOKMOBILE
0	BROWSING
11	CATALOGING
1	CHECKEDOUT
0	DATALOAD
13	DISCARD
0	DISPLAY
0	EASY
0	EASY-RDR
0	FANTASY
0	FIC
0	FIXLIB
0	FOREIGNL
0	GA-CIRC
0	GENEALOGY
0	GEORGIA
0	GOV-DOC
8	HOLDS
10	ILL
10	ILS-ILL
0	INDEX
5	INPROCESS
6	INTRANSIT
0	JUV
0	LEASE
0	LG-PRNT
0	LIB-CLOSED
0	LITERACY
0	LONGOVRDUE
3	LOST
3	LOST-PAID
0	MAG
0	MAPS
4	MISSING
0	MYSTERY
0	NEW-BKS
0	NEWS
0	NONFIC
0	OFFICE
9	ON-ORDER
10	ONLOAN
0	OVERSIZED
0	PBK
0	PICTURE
0	REF
11	REPAIR
0	RESERVES
7	RESHELVING
0	ROTATING
0	SCIFI
0	SHORTSTORY
0	SPEC-COL-R
0	SPEC-COLL
0	SPECNEEDS
0	STACKS
0	STATELIBGA
0	STORAGE
0	THRILLER
0	TODDLER
0	UNAVAILBLE
0	UNKNOWN
0	VRTICLFILE
0	WEBSITE
0	WESTERN
0	YA
\.


-- First, we build shelving location
INSERT INTO asset.copy_location (name, owning_lib)
	SELECT	DISTINCT l.home_location, ou.id
	  FROM	legacy_item l JOIN actor.org_unit ou
	  		ON (l.owning_library = ou.shortname);


-- Now set their flags
UPDATE	asset.copy_location
  SET	holdable = FALSE
  WHERE	name IN ('BINDERY','DISCARD','GENEALOGY','GOV-DOC','INDEX',
		 'LIB-CLOSED','LONGOVERDUE','LOST','LOST-PAID','MAG',
		 'NEWS','ONLOAN','REF','REPAIR','SPEC-COL-R');

UPDATE	asset.copy_location
  SET	opac_visible = FALSE
  WHERE	name IN ('DATALOA','DISCARD','FIXLIB','LIB-CLOSED', 'LONGOVERDUE',
		 'LOST','LOST-PAID','STORAGE', 'UNKNOWN');


-- Now the old stat-cat stuff
INSERT INTO asset.stat_cat (owner, name) VALUES (1, 'Legacy CAT1');
INSERT INTO asset.stat_cat_entry (stat_cat, owner, value)
	SELECT	DISTINCT currval('asset.stat_cat_id_seq'::regclass), 1, cat_1
	  FROM	legacy_item;

INSERT INTO asset.stat_cat (owner, name) VALUES (1, 'Legacy CAT2');
INSERT INTO asset.stat_cat_entry (stat_cat, owner, value)
	SELECT	DISTINCT currval('asset.stat_cat_id_seq'::regclass), 1, cat_2
	  FROM	legacy_item;


-- Create a temp table to speed up CN and copy inserts
CREATE TABLE joined_legacy AS
	SELECT	i.*, c.call_num
	  FROM	legacy_item i
		JOIN legacy_callnum c USING (cat_key,call_key);

CREATE INDEX lj_cat_call_idx ON joined_legacy (cat_key,call_key);

-- Import the call numbers
-- Getting the owning lib from the first available copy on the CN
INSERT INTO asset.call_number (creator,editor,record,label,owning_lib)
	SELECT	DISTINCT 1, 1, l.cat_key , l.call_num, ou.id
	  FROM	joined_legacy l
		JOIN biblio.record_entry b ON (cat_key = b.id)
		JOIN actor.org_unit ou ON (l.owning_library = ou.shortname);



-- Import base copy data
INSERT INTO asset.copy (circ_lib,creator,editor,create_date,barcode,status,location,loan_duration,fine_level,opac_visible,price,circ_modifier,call_number, alert_message)
	SELECT	DISTINCT ou.id AS circ_lib,
		1 AS creator,
		1 AS editor,
		l.creation_date AS create_date,
		l.item_id AS barcode,
		s_map.id AS status,
		cl.id AS location,
		2 AS loan_duration,
		2 AS fine_level,
		CASE WHEN l.shadow IS TRUE THEN FALSE ELSE TRUE END AS opac_visible,
		(l.price/100::numeric)::numeric(8,2) AS price,
		l.item_type AS circ_modifier,
		cn.id AS call_number,
		pc.cnt || ' pieces' as alert_message
	  FROM	joined_legacy l
		JOIN legacy_copy_status_map s_map
			ON (s_map.name = l.current_location)
		JOIN actor.org_unit ou
			ON (l.owning_library = ou.shortname)
		JOIN asset.copy_location cl
			ON (ou.id = cl.owning_lib AND l.home_location = cl.name)
		JOIN asset.call_number cn
			ON (ou.id = cn.owning_lib AND l.cat_key = cn.record AND l.call_num = cn.label)
		LEFT JOIN legacy_piece_count pc ON (pc.barcode = l.item_id);

-- Move copy notes into the notes table ... non-public
INSERT INTO asset.copy_note (owning_copy,creator,title,value)
	SELECT	cp.id,
		1,
		'Legacy Note',
		l.item_comment
	  FROM	legacy_item l
		JOIN asset.copy cp ON (cp.barcode = l.item_id)
	  WHERE	l.item_comment IS NOT NULL
		AND l.item_comment <> '';

COMMIT;

