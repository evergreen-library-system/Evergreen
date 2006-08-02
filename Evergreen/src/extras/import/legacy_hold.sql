BEGIN;

-- These are copy level holds
-- CREATE TABLE legacy_copy_hold_insert AS
INSERT INTO action.hold_request
	(target, current_copy, hold_type, pickup_lib, selection_ou, selection_depth, request_time, capture_time, request_lib, requestor, usr) 
	SELECT	cp.id AS target,
		cp.id AS target,
		'C'::TEXT AS hold_type,
		pou.id AS pickup_lib,
		pou.id AS selection_ou,
		CASE	WHEN lh.hold_range = 'SYSTEM' THEN 0
			WHEN lh.hold_range = 'GROUP' THEN 1
			ELSE 2
		END AS selection_depth,
		lh.hold_date AS request_time,
		CASE	WHEN lh.available IN ('Y','I') THEN now()
			ELSE NULL
		END AS capture_time,
		rou.id AS request_lib,
		au.id AS requestor,
		au.id AS usr
	  FROM	legacy_hold lh
		JOIN legacy_item jl
			ON (	jl.cat_key = lh.cat_key
				AND jl.call_key = lh.call_key
				AND jl.item_key = lh.call_key )
		JOIN asset.copy cp ON (cp.barcode = jl.item_id)
		JOIN actor.usr au ON (au.id = lh.user_key)
		JOIN actor.org_unit rou ON (rou.shortname = lh.placing_lib)
		JOIN actor.org_unit pou ON (pou.shortname = lh.pickup_lib)
	  WHERE	lh.hold_level = 'C';

-- And these are CN level holds
-- CREATE TABLE legacy_cn_hold_insert AS
INSERT INTO action.hold_request
	(target, current_copy, hold_type, pickup_lib, selection_ou, selection_depth, request_time, capture_time, request_lib, requestor, usr) 
	SELECT	cp.call_number AS target,
		cp.id AS current_copy,
		'V'::TEXT AS hold_type,
		pou.id AS pickup_lib,
		pou.id AS selection_ou,
		CASE	WHEN lh.hold_range = 'SYSTEM' THEN 0
			WHEN lh.hold_range = 'GROUP' THEN 1
			ELSE 2
		END AS selection_depth,
		lh.hold_date AS request_time,
		CASE	WHEN lh.available = 'Y' THEN now()
			ELSE NULL
		END AS capture_time,
		rou.id AS request_lib,
		au.id AS requestor,
		au.id AS usr
	  FROM	legacy_hold lh
		JOIN legacy_item jl
			ON (	jl.cat_key = lh.cat_key
				AND jl.call_key = lh.call_key
				AND jl.item_key = lh.call_key )
		JOIN asset.copy cp ON (cp.barcode = jl.item_id)
		JOIN actor.usr au ON (au.id = lh.user_key)
		JOIN actor.org_unit rou ON (rou.shortname = lh.placing_lib)
		JOIN actor.org_unit pou ON (pou.shortname = lh.pickup_lib)
	  WHERE	lh.hold_level = 'A';

-- And these are CN level holds
-- CREATE TABLE legacy_title_hold_insert AS
INSERT INTO action.hold_request
	(target, current_copy, hold_type, pickup_lib, selection_ou, selection_depth, request_time, capture_time, request_lib, requestor, usr) 
	SELECT	lh.cat_key AS target,
		cp.id AS current_copy,
		'T'::TEXT AS hold_type,
		pou.id AS pickup_lib,
		pou.id AS selection_ou,
		CASE	WHEN lh.hold_range = 'SYSTEM' THEN 0
			WHEN lh.hold_range = 'GROUP' THEN 1
			ELSE 2
		END AS selection_depth,
		lh.hold_date AS request_time,
		CASE	WHEN lh.available IN ('Y','I') THEN now()
			ELSE NULL
		END AS capture_time,
		rou.id AS request_lib,
		au.id AS requestor,
		au.id AS usr
	  FROM	legacy_hold lh
		JOIN legacy_item jl
			ON (	jl.cat_key = lh.cat_key
				AND jl.call_key = lh.call_key
				AND jl.item_key = lh.call_key )
		JOIN asset.copy cp ON (cp.barcode = jl.item_id)
		JOIN actor.usr au ON (au.id = lh.user_key)
		JOIN actor.org_unit rou ON (rou.shortname = lh.placing_lib)
		JOIN actor.org_unit pou ON (pou.shortname = lh.pickup_lib)
	  WHERE	lh.hold_level = 'T';

--COMMIT;
