BEGIN;

INSERT INTO config.upgrade_log (version) VALUES ('0530'); -- senator

CREATE INDEX actor_usr_day_phone_idx_numeric ON actor.usr USING BTREE 
    (evergreen.lowercase(REGEXP_REPLACE(day_phone, '[^0-9]', '', 'g')));

CREATE INDEX actor_usr_evening_phone_idx_numeric ON actor.usr USING BTREE 
    (evergreen.lowercase(REGEXP_REPLACE(evening_phone, '[^0-9]', '', 'g')));

CREATE INDEX actor_usr_other_phone_idx_numeric ON actor.usr USING BTREE 
    (evergreen.lowercase(REGEXP_REPLACE(other_phone, '[^0-9]', '', 'g')));

COMMIT;
