BEGIN;

INSERT INTO config.upgrade_log (version) VALUES ('0254'); -- Scott McKellar

CREATE TABLE query.bind_variable (
	name          TEXT             PRIMARY KEY,
	type          TEXT             NOT NULL
		                           CONSTRAINT bind_variable_type CHECK
		                           ( type in ( 'string', 'number', 'string_list', 'number_list' )),
	description   TEXT             NOT NULL,
	default_value TEXT             -- to be encoded in JSON
);

COMMIT;
