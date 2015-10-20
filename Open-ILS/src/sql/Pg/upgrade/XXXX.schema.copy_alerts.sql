BEGIN;

CREATE OR REPLACE FUNCTION asset.copy_state (cid BIGINT) RETURNS TEXT AS $$
DECLARE
    last_circ_stop	TEXT;
    the_copy	    asset.copy%ROWTYPE;
BEGIN

    SELECT * INTO the_copy FROM asset.copy WHERE id = cid;
    IF NOT FOUND THEN RETURN NULL; END IF;

    IF the_copy.status = 3 THEN -- Lost
        RETURN 'LOST';
    ELSIF the_copy.status = 4 THEN -- Missing
        RETURN 'MISSING';
    ELSIF the_copy.status = 14 THEN -- Damaged
        RETURN 'DAMAGED';
    ELSIF the_copy.status = 17 THEN -- Lost and paid
        RETURN 'LOST_AND_PAID';
    END IF;

    SELECT stop_fines INTO last_circ_stop
      FROM  action.circulation
      WHERE target_copy = cid
      ORDER BY xact_start DESC LIMIT 1;

    IF FOUND THEN
        IF last_circ_stop IN (
            'CLAIMSNEVERCHECKEDOUT',
            'CLAIMSRETURNED',
            'LONGOVERDUE'
        ) THEN
            RETURN last_circ_stop;
        END IF;
    END IF;

    RETURN 'NORMAL';
END;
$$ LANGUAGE PLPGSQL;

CREATE TYPE config.copy_alert_type_state AS ENUM (
    'NORMAL',
    'LOST',
    'LOST_AND_PAID',
    'MISSING',
    'DAMAGED',
    'CLAIMSRETURNED',
    'LONGOVERDUE',
    'CLAIMSNEVERCHECKEDOUT'
);

CREATE TYPE config.copy_alert_type_event AS ENUM (
    'CHECKIN',
    'CHECKOUT'
);

CREATE TABLE config.copy_alert_type (
    id      	serial  primary key, -- reserve 1-100 for system
    scope_org   int not null references actor.org_unit (id) on delete cascade,
    active      bool    not null default true,
    name        text    not null unique,
    state       config.copy_alert_type_state,
    event       config.copy_alert_type_event,
    in_renew    bool,
    invert_location bool    not null default false,
    at_circ     bool,
    at_owning   bool,
    next_status int[]
);
SELECT SETVAL('config.copy_alert_type_id_seq'::TEXT, 100);

CREATE TABLE actor.copy_alert_suppress (
    id          serial primary key,
    org         int not null references actor.org_unit (id) on delete cascade,
    alert_type  int not null references config.copy_alert_type (id) on delete cascade
);

CREATE TABLE asset.copy_alert (
    id      bigserial   primary key,
    alert_type  int     not null references config.copy_alert_type (id) on delete cascade,
    copy        bigint  not null references asset.copy (id) on delete cascade,
    temp        bool    not null default false,
    create_time timestamptz not null default now(),
    create_staff    bigint  not null references actor.usr (id) on delete set null,
    note        text,
    ack_time    timestamptz,
    ack_staff   bigint references actor.usr (id) on delete set null
);

CREATE VIEW asset.active_copy_alert AS
    SELECT  *
      FROM  asset.copy_alert
      WHERE ack_time IS NULL;

COMMIT;

