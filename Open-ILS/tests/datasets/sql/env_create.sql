/*
 * 'id' gives us insert sort order
 * 'tag' is mapped to the last_xact_id at import
 */
CREATE TABLE marcxml_import (id SERIAL PRIMARY KEY, marc TEXT, tag TEXT);

/**
 * create a callnumber for every bib record in the database,
 * appending the bib ID to the callnumber label to differentiate.
 * If set, 'bib_tag' will limit the inserted callnumbers to bibs
 * whose last_xact_id matches bib_tag
 */
CREATE FUNCTION evergreen.populate_call_number 
    (ownlib INTEGER, label TEXT, bib_tag TEXT, class INTEGER DEFAULT 1)
RETURNS void AS $$
    INSERT INTO asset.call_number (record, creator, editor, owning_lib, label, label_class)
        SELECT id, 1, 1, $1, $2 || id::text, $4
        FROM biblio.record_entry
        WHERE id > 0 AND 
            CASE WHEN $3 IS NULL THEN TRUE 
                ELSE last_xact_id = $3 END;
$$ LANGUAGE SQL;

CREATE FUNCTION evergreen.populate_call_number 
    (ownlib INTEGER, label TEXT, bib_tag TEXT)
RETURNS void AS $$
    SELECT evergreen.populate_call_number($1, $2, $3, NULL);
$$ LANGUAGE SQL;


/*
 * create a copy for every callnumber in the database whose label and owning_lib 
 * matches, appending the callnumber ID to the copy barcode to differentate.
 */
CREATE FUNCTION evergreen.populate_copy 
    (circlib INTEGER, ownlib INTEGER, barcode TEXT, label TEXT)
RETURNS void AS $$
    INSERT INTO asset.copy (call_number, circ_lib, creator, editor, loan_duration, fine_level, barcode)
        SELECT id, $1, 1, 1, 1, 1, $3 || id::text
        FROM asset.call_number
        WHERE record > 0 AND label LIKE $4 || '%' AND owning_lib = $2;
$$ LANGUAGE SQL;

/** Returns the next (by ID) non-deleted asset.copy */
CREATE FUNCTION evergreen.next_copy (copy_id BIGINT) RETURNS asset.copy AS $$
    SELECT * FROM asset.copy 
    WHERE id > $1 AND NOT deleted
    ORDER BY id LIMIT 1;
$$ LANGUAGE SQL;

/** Returns the next (by ID) non-deleted biblio.record_entry */
CREATE FUNCTION evergreen.next_bib (bib_id BIGINT) RETURNS biblio.record_entry AS $$
    SELECT * FROM biblio.record_entry
    WHERE id > $1 AND NOT deleted
    ORDER BY id LIMIT 1;
$$ LANGUAGE SQL;


/** Create one circulation */
CREATE FUNCTION evergreen.populate_circ (
    patron_id INTEGER,
    staff_id INTEGER,
    copy_id BIGINT,
    circ_lib INTEGER,
    duration_rule TEXT,
    recurring_fine_rule TEXT,
    max_fine_rule TEXT,
    overdue BOOLEAN
)

RETURNS void AS $$
    DECLARE duration config.rule_circ_duration%ROWTYPE;
    DECLARE recurring config.rule_recurring_fine%ROWTYPE;
    DECLARE max_fine config.rule_max_fine%ROWTYPE;
    DECLARE patron actor.usr%ROWTYPE;
    DECLARE xact_base_date TIMESTAMP;
    DECLARE due_date TIMESTAMP;
    DECLARE xact_start TIMESTAMP;
BEGIN

    SELECT INTO duration * FROM config.rule_circ_duration WHERE name = duration_rule;
    SELECT INTO recurring * FROM config.rule_recurring_fine WHERE name = recurring_fine_rule;
    SELECT INTO max_fine * FROM config.rule_max_fine WHERE name = max_fine_rule;
    SELECT INTO patron * FROM actor.usr WHERE id = patron_id;

    IF patron.expire_date < NOW() THEN
        xact_base_date = patron.expire_date;
    ELSE
        xact_base_date = NOW();
    END IF;

    IF overdue THEN
        -- if duration is '7 days', the overdue item was due 7 days ago
        due_date := xact_base_date - duration.normal;
        -- make overdue circs appear as if they were created two durations ago
        xact_start := xact_base_date - duration.normal - duration.normal;
    ELSE
        due_date := xact_base_date + duration.normal;
        xact_start := xact_base_date;
    END IF;

    IF duration.normal >= '1 day'::INTERVAL THEN
        due_date := (DATE(due_date) || ' 23:59:59')::TIMESTAMP;
    END IF;

    INSERT INTO action.circulation (
        xact_start, usr, target_copy, circ_lib, circ_staff, renewal_remaining,
        grace_period, duration, recurring_fine, max_fine, duration_rule,
        recurring_fine_rule, max_fine_rule, due_date )
    VALUES (
        xact_start,
        patron_id,
        copy_id,
        circ_lib, 
        staff_id,
        duration.max_renewals,
        recurring.grace_period,
        duration.normal,
        recurring.normal,
        max_fine.amount,
        duration.name,
        recurring.name,
        max_fine.name,
        due_date
    );

    -- mark copy as checked out
    UPDATE asset.copy SET status = 1 WHERE id = copy_id;

END;
$$ LANGUAGE PLPGSQL;



/** Create one hold */
CREATE FUNCTION evergreen.populate_hold (
    hold_type TEXT,
    target BIGINT,
    patron_id INTEGER,
    requestor INTEGER,
    pickup_lib INTEGER,
    frozen BOOLEAN,
    thawdate TIMESTAMP WITH TIME ZONE
) RETURNS void AS $$
BEGIN
    INSERT INTO action.hold_request (
        requestor, hold_type, target, usr, pickup_lib, 
            request_lib, selection_ou, frozen, thaw_date)
    VALUES (
        requestor,
        hold_type,
        target,
        patron_id,
        pickup_lib,
        pickup_lib,
        pickup_lib,
        frozen,
        thawdate
    );
END;
$$ LANGUAGE PLPGSQL;




