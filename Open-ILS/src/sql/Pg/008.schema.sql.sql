-- Script to create the sql schema and the tables therein

BEGIN;

DROP SCHEMA IF EXISTS sql CASCADE;
CREATE SCHEMA sql;
COMMENT ON SCHEMA sql is $$
/*
 * Copyright (C) 2009  Equinox Software, Inc. / Georgia Public Library Service
 * Scott McKellar <scott@esilibrary.com>
 *
 * Schema: sql
 *
 * Contains tables designed to represent SQL queries for use in
 * reports and the like.
 *
 * ****
 *
 * This program is free software; you can redistribute it and/or
 * modify it under the terms of the GNU General Public License
 * as published by the Free Software Foundation; either version 2
 * of the License, or (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 */
$$;

CREATE TABLE  sql.stored_query (
	id            SERIAL         PRIMARY KEY,
	type          TEXT           NOT NULL CONSTRAINT query_type CHECK
	                             ( type IN ( 'SELECT', 'UNION', 'INTERSECT', 'EXCEPT' ) ),
	use_all       BOOLEAN        NOT NULL DEFAULT FALSE,
	use_distinct  BOOLEAN        NOT NULL DEFAULT FALSE,
	from_clause   INT            NOT NULL , --REFERENCES sql.from_clause
	where_clause  INT            , --REFERENCES sql.expression
	                             --DEFERRABLE INITIALLY DEFERRED,
	having_clause INT            --REFERENCES sql.expression
	                             --DEFERRABLE INITIALLY DEFERRED
);

-- (Foreign keys to be defined later after other tables are created)

CREATE TABLE sql.query_sequence (
	id              SERIAL            PRIMARY KEY,
	parent_query    INT               NOT NULL
	                                  REFERENCES sql.stored_query
									  ON DELETE CASCADE
									  DEFERRABLE INITIALLY DEFERRED,
	seq_no          INT               NOT NULL,
	child_query     INT               NOT NULL
	                                  REFERENCES sql.stored_query
									  ON DELETE CASCADE
									  DEFERRABLE INITIALLY DEFERRED,
	CONSTRAINT sql_query_seq UNIQUE( parent_query, seq_no )
);

CREATE TABLE sql.datatype (
	id              SERIAL            PRIMARY KEY,
	datatype_name   TEXT              NOT NULL UNIQUE,
	is_numeric      BOOL              NOT NULL DEFAULT FALSE,
	is_composite    BOOL              NOT NULL DEFAULT FALSE,
	CONSTRAINT qdt_comp_not_num CHECK
	( is_numeric IS FALSE OR is_composite IS FALSE )
);

CREATE TABLE sql.subfield (
	id              SERIAL            PRIMARY KEY,
	composite_type  INT               NOT NULL
	                                  REFERENCES sql.datatype(id)
	                                  ON DELETE CASCADE
	                                  DEFERRABLE INITIALLY DEFERRED,
	seq_no          INT               NOT NULL
	                                  CONSTRAINT qsf_pos_seq_no
	                                  CHECK( seq_no > 0 ),
	subfield_type   INT               NOT NULL
	                                  REFERENCES sql.datatype(id)
	                                  DEFERRABLE INITIALLY DEFERRED,
	CONSTRAINT qsf_datatype_seq_no UNIQUE (composite_type, seq_no)
);

CREATE TABLE sql.function_sig (
	id              SERIAL            PRIMARY KEY,
	function_name   TEXT              NOT NULL,
	return_type     INT               REFERENCES sql.datatype(id)
	                                  DEFERRABLE INITIALLY DEFERRED,
	is_aggregate    BOOL              NOT NULL DEFAULT FALSE,
	CONSTRAINT qfd_rtn_or_aggr CHECK
	( return_type IS NULL OR is_aggregate = FALSE )
);

CREATE INDEX sql_function_sig_name_idx 
	ON sql.function_sig (function_name);

CREATE TABLE sql.function_param_def (
	id              SERIAL            PRIMARY KEY,
	function_id     INT               NOT NULL
	                                  REFERENCES sql.function_sig( id )
	                                  ON DELETE CASCADE
	                                  DEFERRABLE INITIALLY DEFERRED,
	seq_no          INT               NOT NULL
	                                  CONSTRAINT qfpd_pos_seq_no CHECK
	                                  ( seq_no > 0 ),
	datatype        INT               NOT NULL
	                                  REFERENCES sql.datatype( id )
	                                  DEFERRABLE INITIALLY DEFERRED,
	CONSTRAINT qfpd_function_param_seq UNIQUE (function_id, seq_no)
);

CREATE TABLE sql.expression (
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
	parent_expr   INT           REFERENCES sql.expression
	                            ON DELETE CASCADE
	                            DEFERRABLE INITIALLY DEFERRED,
	seq_no        INT           NOT NULL DEFAULT 1,
	literal       TEXT,
	table_alias   TEXT,
	column_name   TEXT,
	left_operand  INT           REFERENCES sql.expression
	                            DEFERRABLE INITIALLY DEFERRED,
	operator      TEXT,
	right_operand INT           REFERENCES sql.expression
	                            DEFERRABLE INITIALLY DEFERRED,
	function_id   INT           REFERENCES sql.function_sig
	                            DEFERRABLE INITIALLY DEFERRED,
	subquery      INT           REFERENCES sql.stored_query
	                            DEFERRABLE INITIALLY DEFERRED,
	cast_type     INT           REFERENCES sql.datatype
	                            DEFERRABLE INITIALLY DEFERRED
);

CREATE UNIQUE INDEX sql_expr_parent_seq
	ON sql.expression( parent_expr, seq_no )
	WHERE parent_expr IS NOT NULL;

-- Due to some circular references, the following foreign key definitions
-- had to be deferred until sql.expression existed:

ALTER TABLE sql.stored_query
	ADD FOREIGN KEY ( where_clause )
	REFERENCES sql.expression( id )
	DEFERRABLE INITIALLY DEFERRED;

ALTER TABLE sql.stored_query
	ADD FOREIGN KEY ( having_clause )
	REFERENCES sql.expression( id )
	DEFERRABLE INITIALLY DEFERRED;

CREATE TABLE sql.case_branch (
	id            SERIAL        PRIMARY KEY,
	parent_expr   INT           NOT NULL REFERENCES sql.expression
	                            ON DELETE CASCADE
	                            DEFERRABLE INITIALLY DEFERRED,
	seq_no        INT           NOT NULL,
	condition     INT           REFERENCES sql.expression
	                            DEFERRABLE INITIALLY DEFERRED,
	result        INT           NOT NULL REFERENCES sql.expression
	                            DEFERRABLE INITIALLY DEFERRED,
	CONSTRAINT case_branch_parent_seq UNIQUE (parent_expr, seq_no)
);

CREATE TABLE sql.from_relation (
	id               SERIAL        PRIMARY KEY,
	type             TEXT          NOT NULL CONSTRAINT relation_type CHECK (
	                                   type IN ( 'RELATION', 'SUBQUERY', 'FUNCTION' ) ),
	table_name       TEXT,
	class_name       TEXT,
	subquery         INT           REFERENCES sql.stored_query,
	function_call    INT           REFERENCES sql.expression,
	table_alias      TEXT          NOT NULL,
	parent_relation  INT           REFERENCES sql.from_relation
	                               ON DELETE CASCADE
	                               DEFERRABLE INITIALLY DEFERRED,
	seq_no           INT           NOT NULL DEFAULT 1,
	join_type        TEXT          CONSTRAINT good_join_type CHECK (
	                                   join_type IS NULL OR join_type IN
	                                   ( 'INNER', 'LEFT', 'RIGHT', 'FULL' )
	                               ),
	on_clause        INT           REFERENCES sql.expression
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
	ON sql.from_relation( parent_relation, seq_no )
	WHERE parent_relation IS NOT NULL;

-- The following foreign key had to be deferred until
-- sql.from_relation existed

ALTER TABLE sql.stored_query
	ADD FOREIGN KEY (from_clause)
	REFERENCES sql.from_relation
	DEFERRABLE INITIALLY DEFERRED;

CREATE TABLE sql.record_column (
	id            SERIAL            PRIMARY KEY,
	from_relation INT               NOT NULL REFERENCES sql.from_relation
	                                ON DELETE CASCADE
	                                DEFERRABLE INITIALLY DEFERRED,
	seq_no        INT               NOT NULL,
	column_name   TEXT              NOT NULL,
	column_type   TEXT              NOT NULL,
	CONSTRAINT column_sequence UNIQUE (from_relation, seq_no)
);

CREATE TABLE sql.select_item (
	id               SERIAL         PRIMARY KEY,
	stored_query     INT            NOT NULL REFERENCES sql.stored_query
	                                ON DELETE CASCADE
	                                DEFERRABLE INITIALLY DEFERRED,
	seq_no           INT            NOT NULL,
	expression       INT            NOT NULL REFERENCES sql.expression
	                                DEFERRABLE INITIALLY DEFERRED,
	column_alias     TEXT,
	grouped_by       BOOL           NOT NULL DEFAULT FALSE,
	CONSTRAINT select_sequence UNIQUE( stored_query, seq_no )
);

CREATE TABLE sql.order_by_item (
	id               SERIAL         PRIMARY KEY,
	stored_query     INT            NOT NULL REFERENCES sql.stored_query
	                                ON DELETE CASCADE
	                                DEFERRABLE INITIALLY DEFERRED,
	seq_no           INT            NOT NULL,
	expression       INT            NOT NULL REFERENCES sql.expression
	                                ON DELETE CASCADE
	                                DEFERRABLE INITIALLY DEFERRED,
	CONSTRAINT order_by_sequence UNIQUE( stored_query, seq_no )
);

COMMIT;
