-- Script to create the query schema and the tables therein

BEGIN;

INSERT INTO config.upgrade_log (version) VALUES ('0102'); -- Scott McKellar

CREATE TABLE query.record_column (
	id            SERIAL            PRIMARY KEY,
	from_relation INT               NOT NULL REFERENCES query.from_relation
	                                ON DELETE CASCADE
	                                DEFERRABLE INITIALLY DEFERRED,
	seq_no        INT               NOT NULL,
	column_name   TEXT              NOT NULL,
	column_type   INT               NOT NULL REFERENCES query.datatype
	                                ON DELETE CASCADE
									DEFERRABLE INITIALLY DEFERRED,
	CONSTRAINT column_sequence UNIQUE (from_relation, seq_no)
);

CREATE TABLE query.select_item (
	id               SERIAL         PRIMARY KEY,
	stored_query     INT            NOT NULL REFERENCES query.stored_query
	                                ON DELETE CASCADE
	                                DEFERRABLE INITIALLY DEFERRED,
	seq_no           INT            NOT NULL,
	expression       INT            NOT NULL REFERENCES query.expression
	                                DEFERRABLE INITIALLY DEFERRED,
	column_alias     TEXT,
	grouped_by       BOOL           NOT NULL DEFAULT FALSE,
	CONSTRAINT select_sequence UNIQUE( stored_query, seq_no )
);

CREATE TABLE query.order_by_item (
	id               SERIAL         PRIMARY KEY,
	stored_query     INT            NOT NULL REFERENCES query.stored_query
	                                ON DELETE CASCADE
	                                DEFERRABLE INITIALLY DEFERRED,
	seq_no           INT            NOT NULL,
	expression       INT            NOT NULL REFERENCES query.expression
	                                ON DELETE CASCADE
	                                DEFERRABLE INITIALLY DEFERRED,
	CONSTRAINT order_by_sequence UNIQUE( stored_query, seq_no )
);

COMMIT;
