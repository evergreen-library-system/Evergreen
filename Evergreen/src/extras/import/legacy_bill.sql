BEGIN;

INSERT INTO money.grocery (usr,xact_start,billing_location,note)
	SELECT	DISTINCT ON (au.id)
		au.id AS usr,
		lb.bill_date AS xact_start,
		ou.id AS billing_location,
		'Legacy Open Billing' AS note
  	FROM	legacy_bill lb
		JOIN actor.usr au ON (lb.user_key = au.id)
		JOIN actor.org_unit ou ON (lb.library = ou.shortname)
  	WHERE	lb.paid IS FALSE
  	ORDER BY au.id, lb.bill_key2;

INSERT INTO money.billing (xact,billing_ts,amount,billing_type,note)
	SELECT	mg.id AS xact,
		lb.bill_date AS billing_ts,
		(lb.balance / 100.0)::NUMERIC(6,2) AS amount,
		lb.reason AS billing_type,
		'Item Barcode: ' || jl.item_id AS note
  	FROM	legacy_bill lb
		JOIN money.grocery mg ON (lb.user_key = mg.usr)
		JOIN actor.usr au ON (lb.user_key = au.id)
		JOIN actor.org_unit ou ON (lb.library = ou.shortname)
		LEFT JOIN joined_legacy jl USING (cat_key, call_key, item_key)
  	WHERE	lb.paid IS FALSE;

COMMIT;
