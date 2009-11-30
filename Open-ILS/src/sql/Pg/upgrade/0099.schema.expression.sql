BEGIN;

INSERT INTO config.upgrade_log (version) VALUES ('0099'); -- Scott McKellar

CREATE TABLE query.expression (
	id            SERIAL        PRIMARY KEY,
	type          TEXT          NOT NULL CONSTRAINT predicate_type CHECK
	                            ( type IN (
	                             	'xbet',    -- between
									'xbool',   -- boolean
	                             	'xcase',   -- case
									'xcast',   -- cast
									'xcol',    -- column
									'xex',     -- exists
									'xfld',    -- field
									'xfunc',   -- function
									'xin',     -- in
									'xnbet',   -- not between
	                             	'xnex',    -- not exists
									'xnin',    -- not in
	                             	'xnull',   -- null
									'xnum',    -- number
									'xop',     -- operator
									'xstr',    -- string
	                           		'xsubq'    -- subquery
								) ),
	parenthesize  BOOL          NOT NULL DEFAULT FALSE,
	parent_expr   INT           REFERENCES query.expression
	                            ON DELETE CASCADE
	                            DEFERRABLE INITIALLY DEFERRED,
	seq_no        INT           NOT NULL DEFAULT 1,
	literal       TEXT,
	table_alias   TEXT,
	column_name   TEXT,
	left_operand  INT           REFERENCES query.expression
	                            DEFERRABLE INITIALLY DEFERRED,
	operator      TEXT,
	right_operand INT           REFERENCES query.expression
	                            DEFERRABLE INITIALLY DEFERRED,
	function_id   INT           REFERENCES query.function_sig
	                            DEFERRABLE INITIALLY DEFERRED,
	subquery      INT           REFERENCES query.stored_query
	                            DEFERRABLE INITIALLY DEFERRED,
	cast_type     INT           REFERENCES query.datatype
	                            DEFERRABLE INITIALLY DEFERRED
);

CREATE UNIQUE INDEX query_expr_parent_seq
	ON query.expression( parent_expr, seq_no )
	WHERE parent_expr IS NOT NULL;

-- Due to some circular references, the following foreign key definitions
-- had to be deferred until query.expression existed:

ALTER TABLE query.stored_query
	ADD FOREIGN KEY ( where_clause )
	REFERENCES query.expression( id )
	DEFERRABLE INITIALLY DEFERRED;

ALTER TABLE query.stored_query
	ADD FOREIGN KEY ( having_clause )
	REFERENCES query.expression( id )
	DEFERRABLE INITIALLY DEFERRED;

COMMIT;
