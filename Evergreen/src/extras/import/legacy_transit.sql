BEGIN;

-- hold transit import
INSERT INTO action.hold_transit_copy (dest, source, source_send_time, target_copy, copy_status, hold)
	SELECT	dou.id AS dest,
		sou.id AS source,
		l.transit_date AS source_send_time,
		cp.id AS target_copy,
		8 AS copy_status,
		h.id AS hold
  	FROM	legacy_transit l
		JOIN action.hold_request h ON (l.hold_key = h.id)
		JOIN legacy_item li USING (cat_key, call_key, item_key)
		JOIN asset.copy cp ON (li.item_id = cp.barcode)
		JOIN actor.org_unit dou ON (l.destination_lib = dou.shortname)
		JOIN actor.org_unit sou ON (l.starting_lib = sou.shortname)
  	WHERE	l.hold_key > 0;

-- normal transits
INSERT INTO action.transit_copy (dest, source, source_send_time, target_copy, copy_status)
	SELECT	dou.id AS dest,
		sou.id AS source,
		l.transit_date AS source_send_time,
		cp.id AS target_copy,
		7 AS copy_status
  	FROM	legacy_transit l
		JOIN legacy_item li USING (cat_key, call_key, item_key)
		JOIN asset.copy cp ON (li.item_id = cp.barcode)
		JOIN actor.org_unit dou ON (l.destination_lib = dou.shortname)
		JOIN actor.org_unit sou ON (l.starting_lib = sou.shortname)
  	WHERE	l.hold_key = 0;

COMMIT;
