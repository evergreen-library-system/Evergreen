BEGIN;

INSERT INTO config.upgrade_log (version) VALUES ('0098'); -- Scott McKellar

CREATE TABLE  query.stored_query (
	id            SERIAL         PRIMARY KEY,
	type          TEXT           NOT NULL CONSTRAINT query_type CHECK
	                             ( type IN ( 'SELECT', 'UNION', 'INTERSECT', 'EXCEPT' ) ),
	use_all       BOOLEAN        NOT NULL DEFAULT FALSE,
	use_distinct  BOOLEAN        NOT NULL DEFAULT FALSE,
	from_clause   INT            NOT NULL , --REFERENCES query.from_clause
	where_clause  INT            , --REFERENCES query.expression
	                             --DEFERRABLE INITIALLY DEFERRED,
	having_clause INT            --REFERENCES query.expression
	                             --DEFERRABLE INITIALLY DEFERRED
);

-- (Foreign keys to be defined later after other tables are created)

CREATE TABLE query.query_sequence (
	id              SERIAL            PRIMARY KEY,
	parent_query    INT               NOT NULL
	                                  REFERENCES query.stored_query
									  ON DELETE CASCADE
									  DEFERRABLE INITIALLY DEFERRED,
	seq_no          INT               NOT NULL,
	child_query     INT               NOT NULL
	                                  REFERENCES query.stored_query
									  ON DELETE CASCADE
									  DEFERRABLE INITIALLY DEFERRED,
	CONSTRAINT query_query_seq UNIQUE( parent_query, seq_no )
);

COMMIT;
