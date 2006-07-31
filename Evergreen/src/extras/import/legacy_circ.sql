BEGIN;

CREATE TABLE legacy_lib_max_fine (lib text, max_fine numeric(6,2)); 
COPY legacy_lib_max_fine (lib, max_fine) FROM STDIN;
CHRLS	10.00   
FRRLS	10.00           
HCLS	10.00                   
OCRL	10.00                   
OHOOP	10.00   
OKRL	10.00   
PPL	10.00   
PMRLS	10.00   
STRL	10.00   
DTRL	100.00
SJRL	100.00
ARL	100.00  
ECGRL	100.00  
\.

CREATE TABLE legacy_type_circ_map (lib text, max_fine numeric(6,2), renewals int);
COPY legacy_type_circ_map (item_type, recuring_fine, renewals) FROM STDIN;
ART	0.10	0
ATLAS	0.50	2
AUDIOBOOK	0.50	2
AV	0.50	2
BESTSELLER	0.50	2
BOOK	0.10	2
CD	0.10	2
COMPUTER	0.10	2
DATALOAD	0.10	2
DEPOSIT	0.10	2
DVD	0.50	0
DVD-LONG	0.10	2
E-AUDIO	0.50	1
E-BOOK	0.50	1
EQUIP-LONG	0.50	0
EQUIPMENT	0.50	1
FACBESTSLR	0.10	2
FACNEWBK	0.10	2
FILMSTRIP	0.10	2
ILL-ITEM	0.50	0
INTERNET	0.10	1
KIT	0.10	2
LASERDISC	0.50	0
LIBRARYUSE	0.10	2
MAG-CIRC	0.10	2
MAG-NOCIRC	0.10	2
MAP	0.50	1
MICROFORM	0.10	2
MUSIC	0.10	2
NEW-AV	0.50	1
NEW-BOOK	0.10	2
NEWSPAPER	0.10	2
NILS-ITEM	0.10	2
OUTREACH	0.10	2
PAMPHLET	0.10	2
PAPERBACK	0.10	2
REALIA	0.10	2
RECORD	0.10	2
REFERENCE	0.00	0
RESERVE	0.00	0
ROOM	0.00	0
ROOMSATELL	0.00	0
SOFTWARE	0.10	2
SOFTWRLONG	0.10	2
STATE-BOOK	0.10	1
STATE-MFRM	0.10	2
TALKINGBK	0.00	0
TOY	0.10	2
UNKNOWN	0.10	2
VIDEO	0.10	0
VIDEO-LONG	0.10	2
VIDEO-SPEC	0.00	2
WEBSOURCE	0.00	2
\.

-- First, we extract the real circs for users that we know about
-- CREATE TABLE legacy_real_circ AS
INSERT INTO action.circulation
	(
		usr,
		xact_start,
		target_copy,
		circ_lib,
		circ_staff,
		renewal_remaining,
		due_date,
		stop_fines_time,
		duration,
		recuring_fine,
		max_fine,
		desk_renewal,
		duration_rule,
		recuring_fine_rule,
		max_fine_rule,
		stop_fines
	)
	SELECT	DISTINCT ON (lc.charge_key1, lc.charge_key2, lc.charge_key3)
		au.id AS usr,
		CASE WHEN lc.renewal_date = 'NEVER' THEN lc.charge_date::DATE ELSE lc.renewal_date::DATE END AS xact_start,
		cp.id AS target_copy,
		ou.id AS circ_lib,
		1 AS circ_staff,
		tm.renewals AS renewal_remaining,
		CASE WHEN lc.due_date = 'NEVER' THEN (now() + '20 years')::DATE ELSE lc.due_date::DATE END AS due_date,
		CASE WHEN lc.claim_return_date = '0' THEN NULL ELSE lc.claim_return_date::DATE END AS stop_fines_time,
		((CASE WHEN lc.due_date = 'NEVER' THEN (now() + '20 years')::DATE ELSE lc.due_date::DATE END
			-
		  CASE WHEN lc.renewal_date = 'NEVER' THEN lc.charge_date::DATE ELSE lc.renewal_date::DATE END)||' days')::interval AS duration,
		tm.recuring_fine AS recuring_fine,
		COALESCE( mf.max_fine, 5.00 ) AS max_fine,
		CASE WHEN lc.renewal_date = 'NEVER' THEN FALSE ELSE TRUE END AS desk_renewal,
		'IMPORT'::TEXT AS duration_rule,
		'IMPORT'::TEXT AS recuring_fine_rule,
		'IMPORT'::TEXT AS max_fine_rule,
		CASE WHEN lc.claim_return_date = '0' THEN NULL ELSE 'CLAIMSRETURNED' END AS stop_fines
	  FROM	legacy_charge lc
		JOIN joined_legacy li
			ON (	lc.charge_key1 = li.cat_key
				AND lc.charge_key2 = li.call_key
				AND lc.charge_key3 = li.item_key )
		JOIN asset.copy cp ON (cp.barcode = li.item_id)
		JOIN legacy_type_circ_map tm ON (cp.circ_modifier = tm.item_type)
		JOIN actor.org_unit ou ON (lc.library = ou.shortname)
		JOIN actor.usr au ON (lc.user_key = au.id)
		LEFT JOIN legacy_baduser_map bu ON (bu.id = lc.user_key)
		LEFT JOIN legacy_lib_max_fine mf ON (ou.shortname LIKE mf.lib||'%')
	  WHERE bu.id IS NULL
	  ORDER BY
		lc.charge_key1,
		lc.charge_key2,
		lc.charge_key3,
		lc.charge_key4 DESC;


-- Now build a table containing the status change info ...
CREATE TABLE legacy_status_change_circ AS
	SELECT	DISTINCT ON (lc.charge_key1, lc.charge_key2, lc.charge_key3)
		pol.profile AS profile,
		cp.id AS item
	  FROM	legacy_charge lc
		JOIN joined_legacy li
			ON (	lc.charge_key1 = li.cat_key
				AND lc.charge_key2 = li.call_key
				AND lc.charge_key3 = li.item_key )
		JOIN asset.copy cp ON (cp.barcode = li.item_id)
		JOIN legacy_baduser_map bu ON (bu.id = lc.user_key)
		JOIN legacy_non_real_user pol ON (bu.barcode = pol.barcode)
	  WHERE bu.type = 'N'
	  ORDER BY
		lc.charge_key1,
		lc.charge_key2,
		lc.charge_key3,
		lc.charge_key4 DESC;

-- ... and update the copies with it
UPDATE	asset.copy
  SET	status = legacy_copy_status_map.id
  FROM	legacy_status_change_circ
	JOIN legacy_copy_status_map ON (legacy_copy_status_map.name = legacy_status_change_circ.profile)
  WHERE	asset.copy.id = legacy_status_change_circ.item;


-- Next up, circ_lib changes based on recirc users ...
CREATE TABLE legacy_lib_change_circ AS
	SELECT	DISTINCT ON (lc.charge_key1, lc.charge_key2, lc.charge_key3)
		ou.id AS lib,
		cp.id AS item
	  FROM	legacy_charge lc
		JOIN joined_legacy li
			ON (	lc.charge_key1 = li.cat_key
				AND lc.charge_key2 = li.call_key
				AND lc.charge_key3 = li.item_key )
		JOIN asset.copy cp ON (cp.barcode = li.item_id)
		JOIN legacy_baduser_map bu ON (bu.id = lc.user_key)
		JOIN legacy_recirc_lib pol ON (bu.barcode = pol.barcode)
		JOIN actor.org_unit ou ON (ou.shortname = pol.lib)
	  WHERE bu.type = 'R'
	  ORDER BY
		lc.charge_key1,
		lc.charge_key2,
		lc.charge_key3,
		lc.charge_key4 DESC;

-- ... and apply that too.
UPDATE	asset.copy
  SET	circ_lib = legacy_lib_change_circ.lib
  FROM	legacy_lib_change_circ
  WHERE	asset.copy.id = legacy_lib_change_circ.item;

COMMIT;
