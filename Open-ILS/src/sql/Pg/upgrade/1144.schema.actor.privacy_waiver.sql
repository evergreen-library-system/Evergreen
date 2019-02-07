BEGIN;

INSERT INTO config.upgrade_log (version) VALUES ('1144');

CREATE TABLE actor.usr_privacy_waiver (
    id BIGSERIAL PRIMARY KEY,
    usr BIGINT NOT NULL REFERENCES actor.usr(id) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED,
    name TEXT NOT NULL,
    place_holds BOOL DEFAULT FALSE,
    pickup_holds BOOL DEFAULT FALSE,
    view_history BOOL DEFAULT FALSE,
    checkout_items BOOL DEFAULT FALSE
);
CREATE INDEX actor_usr_privacy_waiver_usr_idx ON actor.usr_privacy_waiver (usr);

COMMIT;

