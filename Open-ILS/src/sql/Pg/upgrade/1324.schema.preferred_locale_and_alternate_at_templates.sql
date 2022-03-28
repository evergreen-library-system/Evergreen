BEGIN;

SELECT evergreen.upgrade_deps_block_check('1324', :eg_version);

CREATE TABLE action_trigger.alternate_template (
      id               SERIAL,
      event_def        INTEGER REFERENCES action_trigger.event_definition(id) INITIALLY DEFERRED,
      template         TEXT,
      active           BOOLEAN DEFAULT TRUE,
      message_title    TEXT,
      message_template TEXT,
      locale           TEXT REFERENCES config.i18n_locale(code) INITIALLY DEFERRED,
      UNIQUE (event_def,locale)
);

ALTER TABLE actor.usr ADD COLUMN locale TEXT REFERENCES config.i18n_locale(code) INITIALLY DEFERRED;

ALTER TABLE action_trigger.event_output ADD COLUMN locale TEXT;

COMMIT;
