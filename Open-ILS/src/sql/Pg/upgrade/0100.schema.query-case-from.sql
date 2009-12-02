BEGIN;

INSERT INTO config.upgrade_log (version) VALUES ('0100'); -- Scott McKellar

CREATE TABLE query.case_branch (
	id            SERIAL        PRIMARY KEY,
	parent_expr   INT           NOT NULL REFERENCES query.expression
	                            ON DELETE CASCADE
	                            DEFERRABLE INITIALLY DEFERRED,
	seq_no        INT           NOT NULL,
	condition     INT           REFERENCES query.expression
	                            DEFERRABLE INITIALLY DEFERRED,
	result        INT           NOT NULL REFERENCES query.expression
	                            DEFERRABLE INITIALLY DEFERRED,
	CONSTRAINT case_branch_parent_seq UNIQUE (parent_expr, seq_no)
);

CREATE TABLE query.from_relation (
	id               SERIAL        PRIMARY KEY,
	type             TEXT          NOT NULL CONSTRAINT relation_type CHECK (
	                                   type IN ( 'RELATION', 'SUBQUERY', 'FUNCTION' ) ),
	table_name       TEXT,
	class_name       TEXT,
	subquery         INT           REFERENCES query.stored_query,
	function_call    INT           REFERENCES query.expression,
	table_alias      TEXT          NOT NULL,
	parent_relation  INT           REFERENCES query.from_relation
	                               ON DELETE CASCADE
	                               DEFERRABLE INITIALLY DEFERRED,
	seq_no           INT           NOT NULL DEFAULT 1,
	join_type        TEXT          CONSTRAINT good_join_type CHECK (
	                                   join_type IS NULL OR join_type IN
	                                   ( 'INNER', 'LEFT', 'RIGHT', 'FULL' )
	                               ),
	on_clause        INT           REFERENCES query.expression
	                               DEFERRABLE INITIALLY DEFERRED,
	CONSTRAINT join_or_core CHECK (
	    ( parent_relation IS NULL AND join_type IS NULL 
	      AND on_clause IS NULL and table_alias IS NULL )
	    OR
	    ( parent_relation IS NOT NULL AND join_type IS NOT NULL
	      AND on_clause IS NOT NULL )
	)
);

CREATE UNIQUE INDEX from_parent_seq
	ON query.from_relation( parent_relation, seq_no )
	WHERE parent_relation IS NOT NULL;

-- The following foreign key had to be deferred until
-- query.from_relation existed

ALTER TABLE query.stored_query
	ADD FOREIGN KEY (from_clause)
	REFERENCES query.from_relation
	DEFERRABLE INITIALLY DEFERRED;

COMMIT;
