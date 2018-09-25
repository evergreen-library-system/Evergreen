BEGIN;

SELECT evergreen.upgrade_deps_block_check('1096', :eg_version);

-- staff-usable alert types with no location awareness
INSERT INTO config.copy_alert_type (id, scope_org, active, name, state, event, in_renew)
VALUES (1, 1, TRUE, 'Normal checkout', 'NORMAL', 'CHECKOUT', FALSE);
INSERT INTO config.copy_alert_type (id, scope_org, active, name, state, event, in_renew)
VALUES (2, 1, TRUE, 'Normal checkin', 'NORMAL', 'CHECKIN', FALSE);
INSERT INTO config.copy_alert_type (id, scope_org, active, name, state, event, in_renew)
VALUES (3, 1, FALSE, 'Normal renewal', 'NORMAL', 'CHECKIN', TRUE);

-- copy alerts upon checkin or renewal of exceptional copy statuses are not active by
-- default; they're meant to be turned once a site is ready to fully
-- commit to using the webstaff client for circulation
INSERT INTO config.copy_alert_type (id, scope_org, active, name, state, event)
VALUES (4, 1, FALSE, 'Checkin of lost copy', 'LOST', 'CHECKIN');
INSERT INTO config.copy_alert_type (id, scope_org, active, name, state, event)
VALUES (5, 1, FALSE, 'Checkin of missing copy', 'MISSING', 'CHECKIN');
INSERT INTO config.copy_alert_type (id, scope_org, active, name, state, event)
VALUES (6, 1, FALSE, 'Checkin of lost-and-paid copy', 'LOST_AND_PAID', 'CHECKIN');
INSERT INTO config.copy_alert_type (id, scope_org, active, name, state, event)
VALUES (7, 1, FALSE, 'Checkin of damaged copy', 'DAMAGED', 'CHECKIN');
INSERT INTO config.copy_alert_type (id, scope_org, active, name, state, event)
VALUES (8, 1, FALSE, 'Checkin of claims-returned copy', 'CLAIMSRETURNED', 'CHECKIN');
INSERT INTO config.copy_alert_type (id, scope_org, active, name, state, event)
VALUES (9, 1, FALSE, 'Checkin of long overdue copy', 'LONGOVERDUE', 'CHECKIN');
INSERT INTO config.copy_alert_type (id, scope_org, active, name, state, event)
VALUES (10, 1, FALSE, 'Checkin of claims-never-checked-out copy', 'CLAIMSNEVERCHECKEDOUT', 'CHECKIN');

-- copy alerts upon checkout of exceptional copy statuses are not active by
-- default; they're meant to be turned once a site is ready to fully
-- commit to using the webstaff client for circulation
INSERT INTO config.copy_alert_type (id, scope_org, active, name, state, event)
VALUES (11, 1, FALSE, 'Checkout of lost copy', 'LOST', 'CHECKOUT');
INSERT INTO config.copy_alert_type (id, scope_org, active, name, state, event)
VALUES (12, 1, FALSE, 'Checkout of missing copy', 'MISSING', 'CHECKOUT');
INSERT INTO config.copy_alert_type (id, scope_org, active, name, state, event)
VALUES (13, 1, FALSE, 'Checkout of lost-and-paid copy', 'LOST_AND_PAID', 'CHECKOUT');
INSERT INTO config.copy_alert_type (id, scope_org, active, name, state, event)
VALUES (14, 1, FALSE, 'Checkout of damaged copy', 'DAMAGED', 'CHECKOUT');
INSERT INTO config.copy_alert_type (id, scope_org, active, name, state, event)
VALUES (15, 1, FALSE, 'Checkout of claims-returned copy', 'CLAIMSRETURNED', 'CHECKOUT');
INSERT INTO config.copy_alert_type (id, scope_org, active, name, state, event)
VALUES (16, 1, FALSE, 'Checkout of long overdue copy', 'LONGOVERDUE', 'CHECKOUT');
INSERT INTO config.copy_alert_type (id, scope_org, active, name, state, event)
VALUES (17, 1, FALSE, 'Checkout of claims-never-checked-out copy', 'CLAIMSNEVERCHECKEDOUT', 'CHECKOUT');

-- staff-usable alert types based on location
INSERT INTO config.copy_alert_type (id, scope_org, active, name, state, event, in_renew, at_circ)
VALUES (18, 1, FALSE, 'Normal checkout at circ lib', 'NORMAL', 'CHECKOUT', FALSE, TRUE);
INSERT INTO config.copy_alert_type (id, scope_org, active, name, state, event, in_renew, at_circ)
VALUES (19, 1, FALSE, 'Normal checkin at circ lib', 'NORMAL', 'CHECKIN', FALSE, TRUE);
INSERT INTO config.copy_alert_type (id, scope_org, active, name, state, event, in_renew, at_circ)
VALUES (20, 1, FALSE, 'Normal renewal at circ lib', 'NORMAL', 'CHECKIN', TRUE, TRUE);

INSERT INTO config.copy_alert_type (id, scope_org, active, name, state, event, in_renew, at_owning)
VALUES (21, 1, FALSE, 'Normal checkout at owning lib', 'NORMAL', 'CHECKOUT', FALSE, TRUE);
INSERT INTO config.copy_alert_type (id, scope_org, active, name, state, event, in_renew, at_owning)
VALUES (22, 1, FALSE, 'Normal checkin at owning lib', 'NORMAL', 'CHECKIN', FALSE, TRUE);
INSERT INTO config.copy_alert_type (id, scope_org, active, name, state, event, in_renew, at_owning)
VALUES (23, 1, FALSE, 'Normal renewal at owning lib', 'NORMAL', 'CHECKIN', TRUE, TRUE);

COMMIT;
