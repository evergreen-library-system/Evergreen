BEGIN;

INSERT INTO config.upgrade_log (version) VALUES ('0351'); -- Scott McKellar

CREATE TABLE actor.usr_saved_search (
    id              SERIAL          PRIMARY KEY,
	owner           INT             NOT NULL REFERENCES actor.usr (id)
	                                ON DELETE CASCADE
	                                DEFERRABLE INITIALLY DEFERRED,
	name            TEXT            NOT NULL,
	create_date     TIMESTAMPTZ     NOT NULL DEFAULT now(),
	query_text      TEXT            NOT NULL,
	query_type      TEXT            NOT NULL
	                                CONSTRAINT valid_query_text CHECK (
	                                query_type IN ( 'URL' )) DEFAULT 'URL',
	                                -- we may add other types someday
	target          TEXT            NOT NULL
	                                CONSTRAINT valid_target CHECK (
	                                target IN ( 'record', 'metarecord', 'callnumber' )),
	CONSTRAINT name_once_per_user UNIQUE (owner, name)
);

COMMIT;
