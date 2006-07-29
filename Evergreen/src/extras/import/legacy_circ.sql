BEGIN;

-- First, we extract the real circs for users that we know about
CREATE TABLE legacy_real_circ (usr int, item int, start_date date, due_date date, item_type text, circ_lib int, claim_return_date date) AS
	SELECT	DISTINCT ON (lc.charge_key1, lc.charge_key2, lc.charge_key3)
		au.id AS usr,
		cp.id AS item,
		CASE WHEN lc.renewal_date = 'NEVER'
			THEN lc.charge_date::DATE
			ELSE lc.renewal_date::DATE
		END AS start_date,
		CASE WHEN lc.due_date = 'NEVER'
			THEN (now() + '20 years')::DATE
			ELSE lc.due_date::DATE
		END AS due_date,
		li.item_type,
		ou.id AS circ_lib,
		CASE WHEN lc.claim_return_date = '0'
			THEN NULL
			ELSE lc.claim_return_date::DATE
		END AS claim_return_date
	  FROM	legacy_charge lc
		JOIN joined_legacy li
			ON (	lc.charge_key1 = li.cat_key
				AND lc.charge_key2 = li.call_key
				AND lc.charge_key3 = li.item_key )
		JOIN asset.copy cp ON (cp.barcode = li.item_id)
		JOIN actor.org_unit ou ON (lc.library = ou.shortname)
		JOIN actor.usr au ON (lc.user_key = au.id)
		LEFT JOIN legacy_baduser_map bu ON (bu.id = lc.user_key)
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

