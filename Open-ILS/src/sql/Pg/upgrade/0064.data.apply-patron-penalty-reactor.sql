BEGIN;

INSERT INTO config.upgrade_log (version) VALUES ('0064');

INSERT INTO action_trigger.reactor (module,description) VALUES ('ApplyPatronPenalty','Applies the conifigured penalty to a patron.  Required named environment variables are "user", which refers to the user object, and "context_org", which refers to the org_unit object that acts as the focus for the penalty.');

COMMIT;

