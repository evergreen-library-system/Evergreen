/*
 * Copyright (C) 2009  Equinox Software, Inc. / Georgia Public Library Service
 * Scott McKellar <scott@esilibrary.com>
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

BEGIN;

DROP SCHEMA IF EXISTS query CASCADE;
CREATE SCHEMA query;
COMMENT ON SCHEMA query IS $$
Contains tables designed to represent user-defined queries for
reports and the like.
$$;

CREATE TABLE  query.stored_query (
	id            SERIAL         PRIMARY KEY,
	type          TEXT           NOT NULL CONSTRAINT query_type CHECK
	                             ( type IN ( 'SELECT', 'UNION', 'INTERSECT', 'EXCEPT' ) ),
	use_all       BOOLEAN        NOT NULL DEFAULT FALSE,
	use_distinct  BOOLEAN        NOT NULL DEFAULT FALSE,
	from_clause   INT,           --REFERENCES query.from_clause
	                             --DEFERRABLE INITIALLY DEFERRED,
	where_clause  INT,           --REFERENCES query.expression
	                             --DEFERRABLE INITIALLY DEFERRED,
	having_clause INT,           --REFERENCES query.expression
	                             --DEFERRABLE INITIALLY DEFERRED,
	limit_count   INT,           --REFERENCES query.expression
	                             --DEFERRABLE INITIALLY DEFERRED,
	offset_count  INT            --REFERENCES query.expression
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

CREATE TABLE query.datatype (
	id              SERIAL            PRIMARY KEY,
	datatype_name   TEXT              NOT NULL UNIQUE,
	is_numeric      BOOL              NOT NULL DEFAULT FALSE,
	is_composite    BOOL              NOT NULL DEFAULT FALSE,
	CONSTRAINT qdt_comp_not_num CHECK
	( is_numeric IS FALSE OR is_composite IS FALSE )
);

-- Leave room to seed with stock datatypes
-- before adding customized ones
SELECT setval( 'query.datatype_id_seq', 1000 );

CREATE TABLE query.subfield (
	id              SERIAL            PRIMARY KEY,
	composite_type  INT               NOT NULL
	                                  REFERENCES query.datatype(id)
	                                  ON DELETE CASCADE
	                                  DEFERRABLE INITIALLY DEFERRED,
	seq_no          INT               NOT NULL
	                                  CONSTRAINT qsf_pos_seq_no
	                                  CHECK( seq_no > 0 ),
	subfield_type   INT               NOT NULL
	                                  REFERENCES query.datatype(id)
	                                  DEFERRABLE INITIALLY DEFERRED,
	CONSTRAINT qsf_datatype_seq_no UNIQUE (composite_type, seq_no)
);

CREATE TABLE query.function_sig (
	id              SERIAL            PRIMARY KEY,
	function_name   TEXT              NOT NULL,
	return_type     INT               REFERENCES query.datatype(id)
	                                  DEFERRABLE INITIALLY DEFERRED,
	is_aggregate    BOOL              NOT NULL DEFAULT FALSE,
	CONSTRAINT qfd_rtn_or_aggr CHECK
	( return_type IS NULL OR is_aggregate = FALSE )
);

CREATE INDEX query_function_sig_name_idx 
	ON query.function_sig (function_name);

CREATE TABLE query.function_param_def (
	id              SERIAL            PRIMARY KEY,
	function_id     INT               NOT NULL
	                                  REFERENCES query.function_sig( id )
	                                  ON DELETE CASCADE
	                                  DEFERRABLE INITIALLY DEFERRED,
	seq_no          INT               NOT NULL
	                                  CONSTRAINT qfpd_pos_seq_no CHECK
	                                  ( seq_no > 0 ),
	datatype        INT               NOT NULL
	                                  REFERENCES query.datatype( id )
	                                  DEFERRABLE INITIALLY DEFERRED,
	CONSTRAINT qfpd_function_param_seq UNIQUE (function_id, seq_no)
);

CREATE TABLE query.bind_variable (
	name          TEXT             PRIMARY KEY,
	type          TEXT             NOT NULL
		                           CONSTRAINT bind_variable_type CHECK
		                           ( type in ( 'string', 'number', 'string_list', 'number_list' )),
	description   TEXT             NOT NULL,
	default_value TEXT,            -- to be encoded in JSON
	label         TEXT             NOT NULL
);

CREATE TABLE query.expression (
	id            SERIAL        PRIMARY KEY,
	type          TEXT          NOT NULL CONSTRAINT expression_type CHECK
	                            ( type IN (
	                             	'xbet',    -- between
									'xbind',   -- bind variable
									'xbool',   -- boolean
	                             	'xcase',   -- case
									'xcast',   -- cast
									'xcol',    -- column
									'xex',     -- exists
									'xfunc',   -- function
									'xin',     -- in
									'xisnull', -- is null
	                             	'xnull',   -- null
									'xnum',    -- number
									'xop',     -- operator
									'xser',    -- series
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
	                            DEFERRABLE INITIALLY DEFERRED,
	negate        BOOL          NOT NULL DEFAULT FALSE,
	bind_variable TEXT          REFERENCES query.bind_variable
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

ALTER TABLE query.stored_query
	ADD FOREIGN KEY ( limit_count )
	REFERENCES query.expression( id )
	DEFERRABLE INITIALLY DEFERRED;

ALTER TABLE query.stored_query
	ADD FOREIGN KEY ( offset_count )
	REFERENCES query.expression( id )
	DEFERRABLE INITIALLY DEFERRED;

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
	table_alias      TEXT,
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
	      AND on_clause IS NULL )
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

-- Create updatable views -------------------------------------------

-- Create updatable view for BETWEEN expressions

CREATE OR REPLACE VIEW query.expr_xbet AS
    SELECT
		id,
		parenthesize,
		parent_expr,
		seq_no,
		left_operand,
		negate
    FROM
        query.expression
    WHERE
        type = 'xbet';

CREATE OR REPLACE RULE query_expr_xbet_insert_rule AS
    ON INSERT TO query.expr_xbet
    DO INSTEAD
    INSERT INTO query.expression (
		id,
		type,
		parenthesize,
		parent_expr,
		seq_no,
		left_operand,
		negate
    ) VALUES (
        COALESCE(NEW.id, NEXTVAL('query.expression_id_seq'::REGCLASS)),
        'xbet',
        COALESCE(NEW.parenthesize, FALSE),
        NEW.parent_expr,
        COALESCE(NEW.seq_no, 1),
		NEW.left_operand,
		COALESCE(NEW.negate, false)
    );

CREATE OR REPLACE RULE query_expr_xbet_update_rule AS
    ON UPDATE TO query.expr_xbet
    DO INSTEAD
    UPDATE query.expression SET
        id = NEW.id,
        parenthesize = NEW.parenthesize,
        parent_expr = NEW.parent_expr,
        seq_no = NEW.seq_no,
		left_operand = NEW.left_operand,
		negate = NEW.negate
    WHERE
        id = OLD.id;

CREATE OR REPLACE RULE query_expr_xbet_delete_rule AS
    ON DELETE TO query.expr_xbet
    DO INSTEAD
    DELETE FROM query.expression WHERE id = OLD.id;

-- Create updatable view for bind variable expressions

CREATE OR REPLACE VIEW query.expr_xbind AS
    SELECT
		id,
		parenthesize,
		parent_expr,
		seq_no,
		bind_variable
    FROM
        query.expression
    WHERE
        type = 'xbind';

CREATE OR REPLACE RULE query_expr_xbind_insert_rule AS
    ON INSERT TO query.expr_xbind
    DO INSTEAD
    INSERT INTO query.expression (
		id,
		type,
		parenthesize,
		parent_expr,
		seq_no,
		bind_variable
    ) VALUES (
        COALESCE(NEW.id, NEXTVAL('query.expression_id_seq'::REGCLASS)),
        'xbind',
        COALESCE(NEW.parenthesize, FALSE),
        NEW.parent_expr,
        COALESCE(NEW.seq_no, 1),
		NEW.bind_variable
    );

CREATE OR REPLACE RULE query_expr_xbind_update_rule AS
    ON UPDATE TO query.expr_xbind
    DO INSTEAD
    UPDATE query.expression SET
        id = NEW.id,
        parenthesize = NEW.parenthesize,
        parent_expr = NEW.parent_expr,
        seq_no = NEW.seq_no,
		bind_variable = NEW.bind_variable
    WHERE
        id = OLD.id;

CREATE OR REPLACE RULE query_expr_xbind_delete_rule AS
    ON DELETE TO query.expr_xbind
    DO INSTEAD
    DELETE FROM query.expression WHERE id = OLD.id;

-- Create updatable view for boolean expressions

CREATE OR REPLACE VIEW query.expr_xbool AS
    SELECT
		id,
		parenthesize,
		parent_expr,
		seq_no,
		literal,
		negate
    FROM
        query.expression
    WHERE
        type = 'xbool';

CREATE OR REPLACE RULE query_expr_xbool_insert_rule AS
    ON INSERT TO query.expr_xbool
    DO INSTEAD
    INSERT INTO query.expression (
		id,
		type,
		parenthesize,
		parent_expr,
		seq_no,
		literal,
		negate
    ) VALUES (
        COALESCE(NEW.id, NEXTVAL('query.expression_id_seq'::REGCLASS)),
        'xbool',
        COALESCE(NEW.parenthesize, FALSE),
        NEW.parent_expr,
        COALESCE(NEW.seq_no, 1),
        NEW.literal,
		COALESCE(NEW.negate, false)
    );

CREATE OR REPLACE RULE query_expr_xbool_update_rule AS
    ON UPDATE TO query.expr_xbool
    DO INSTEAD
    UPDATE query.expression SET
        id = NEW.id,
        parenthesize = NEW.parenthesize,
        parent_expr = NEW.parent_expr,
        seq_no = NEW.seq_no,
        literal = NEW.literal,
		negate = NEW.negate
    WHERE
        id = OLD.id;

CREATE OR REPLACE RULE query_expr_xbool_delete_rule AS
    ON DELETE TO query.expr_xbool
    DO INSTEAD
    DELETE FROM query.expression WHERE id = OLD.id;

-- Create updatable view for CASE expressions

CREATE OR REPLACE VIEW query.expr_xcase AS
    SELECT
		id,
		parenthesize,
		parent_expr,
		seq_no,
		left_operand,
		negate
    FROM
        query.expression
    WHERE
        type = 'xcase';

CREATE OR REPLACE RULE query_expr_xcase_insert_rule AS
    ON INSERT TO query.expr_xcase
    DO INSTEAD
    INSERT INTO query.expression (
		id,
		type,
		parenthesize,
		parent_expr,
		seq_no,
		left_operand,
		negate
    ) VALUES (
        COALESCE(NEW.id, NEXTVAL('query.expression_id_seq'::REGCLASS)),
        'xcase',
        COALESCE(NEW.parenthesize, FALSE),
        NEW.parent_expr,
        COALESCE(NEW.seq_no, 1),
		NEW.left_operand,
		COALESCE(NEW.negate, false)
    );

CREATE OR REPLACE RULE query_expr_xcase_update_rule AS
    ON UPDATE TO query.expr_xcase
    DO INSTEAD
    UPDATE query.expression SET
        id = NEW.id,
        parenthesize = NEW.parenthesize,
        parent_expr = NEW.parent_expr,
        seq_no = NEW.seq_no,
		left_operand = NEW.left_operand,
		negate = NEW.negate
    WHERE
        id = OLD.id;

CREATE OR REPLACE RULE query_expr_xcase_delete_rule AS
    ON DELETE TO query.expr_xcase
    DO INSTEAD
    DELETE FROM query.expression WHERE id = OLD.id;

-- Create updatable view for cast expressions

CREATE OR REPLACE VIEW query.expr_xcast AS
    SELECT
		id,
		parenthesize,
		parent_expr,
		seq_no,
		left_operand,
		cast_type,
		negate
    FROM
        query.expression
    WHERE
        type = 'xcast';

CREATE OR REPLACE RULE query_expr_xcast_insert_rule AS
    ON INSERT TO query.expr_xcast
    DO INSTEAD
    INSERT INTO query.expression (
		id,
		type,
		parenthesize,
		parent_expr,
		seq_no,
		left_operand,
		cast_type,
		negate
    ) VALUES (
        COALESCE(NEW.id, NEXTVAL('query.expression_id_seq'::REGCLASS)),
        'xcast',
        COALESCE(NEW.parenthesize, FALSE),
        NEW.parent_expr,
        COALESCE(NEW.seq_no, 1),
		NEW.left_operand,
		NEW.cast_type,
		COALESCE(NEW.negate, false)
    );

CREATE OR REPLACE RULE query_expr_xcast_update_rule AS
    ON UPDATE TO query.expr_xcast
    DO INSTEAD
    UPDATE query.expression SET
        id = NEW.id,
        parenthesize = NEW.parenthesize,
        parent_expr = NEW.parent_expr,
        seq_no = NEW.seq_no,
		left_operand = NEW.left_operand,
		cast_type = NEW.cast_type,
		negate = NEW.negate
    WHERE
        id = OLD.id;

CREATE OR REPLACE RULE query_expr_xcast_delete_rule AS
    ON DELETE TO query.expr_xcast
    DO INSTEAD
    DELETE FROM query.expression WHERE id = OLD.id;

-- Create updatable view for column expressions

CREATE OR REPLACE VIEW query.expr_xcol AS
    SELECT
		id,
		parenthesize,
		parent_expr,
		seq_no,
		table_alias,
		column_name,
		negate
    FROM
        query.expression
    WHERE
        type = 'xcol';

CREATE OR REPLACE RULE query_expr_xcol_insert_rule AS
    ON INSERT TO query.expr_xcol
    DO INSTEAD
    INSERT INTO query.expression (
		id,
		type,
		parenthesize,
		parent_expr,
		seq_no,
		table_alias,
		column_name,
		negate
    ) VALUES (
        COALESCE(NEW.id, NEXTVAL('query.expression_id_seq'::REGCLASS)),
        'xcol',
        COALESCE(NEW.parenthesize, FALSE),
        NEW.parent_expr,
        COALESCE(NEW.seq_no, 1),
		NEW.table_alias,
		NEW.column_name,
		COALESCE(NEW.negate, false)
    );

CREATE OR REPLACE RULE query_expr_xcol_update_rule AS
    ON UPDATE TO query.expr_xcol
    DO INSTEAD
    UPDATE query.expression SET
        id = NEW.id,
        parenthesize = NEW.parenthesize,
        parent_expr = NEW.parent_expr,
        seq_no = NEW.seq_no,
		table_alias = NEW.table_alias,
		column_name = NEW.column_name,
		negate = NEW.negate
    WHERE
        id = OLD.id;

CREATE OR REPLACE RULE query_expr_xcol_delete_rule AS
    ON DELETE TO query.expr_xcol
    DO INSTEAD
    DELETE FROM query.expression WHERE id = OLD.id;

-- Create updatable view for EXISTS expressions

CREATE OR REPLACE VIEW query.expr_xex AS
    SELECT
		id,
		parenthesize,
		parent_expr,
		seq_no,
		subquery,
		negate
    FROM
        query.expression
    WHERE
        type = 'xex';

CREATE OR REPLACE RULE query_expr_xex_insert_rule AS
    ON INSERT TO query.expr_xex
    DO INSTEAD
    INSERT INTO query.expression (
		id,
		type,
		parenthesize,
		parent_expr,
		seq_no,
		subquery,
		negate
    ) VALUES (
        COALESCE(NEW.id, NEXTVAL('query.expression_id_seq'::REGCLASS)),
        'xex',
        COALESCE(NEW.parenthesize, FALSE),
        NEW.parent_expr,
        COALESCE(NEW.seq_no, 1),
		NEW.subquery,
		COALESCE(NEW.negate, false)
    );

CREATE OR REPLACE RULE query_expr_xex_update_rule AS
    ON UPDATE TO query.expr_xex
    DO INSTEAD
    UPDATE query.expression SET
        id = NEW.id,
        parenthesize = NEW.parenthesize,
        parent_expr = NEW.parent_expr,
        seq_no = NEW.seq_no,
		subquery = NEW.subquery,
		negate = NEW.negate
    WHERE
        id = OLD.id;

CREATE OR REPLACE RULE query_expr_xex_delete_rule AS
    ON DELETE TO query.expr_xex
    DO INSTEAD
    DELETE FROM query.expression WHERE id = OLD.id;

-- Create updatable view for function call expressions

CREATE OR REPLACE VIEW query.expr_xfunc AS
    SELECT
		id,
		parenthesize,
		parent_expr,
		seq_no,
		column_name,
		function_id,
		negate
    FROM
        query.expression
    WHERE
        type = 'xfunc';

CREATE OR REPLACE RULE query_expr_xfunc_insert_rule AS
    ON INSERT TO query.expr_xfunc
    DO INSTEAD
    INSERT INTO query.expression (
		id,
		type,
		parenthesize,
		parent_expr,
		seq_no,
		column_name,
		function_id,
		negate
    ) VALUES (
        COALESCE(NEW.id, NEXTVAL('query.expression_id_seq'::REGCLASS)),
        'xfunc',
        COALESCE(NEW.parenthesize, FALSE),
        NEW.parent_expr,
        COALESCE(NEW.seq_no, 1),
		NEW.column_name,
		NEW.function_id,
		COALESCE(NEW.negate, false)
    );

CREATE OR REPLACE RULE query_expr_xfunc_update_rule AS
    ON UPDATE TO query.expr_xfunc
    DO INSTEAD
    UPDATE query.expression SET
        id = NEW.id,
        parenthesize = NEW.parenthesize,
        parent_expr = NEW.parent_expr,
        seq_no = NEW.seq_no,
		column_name = NEW.column_name,
		function_id = NEW.function_id,
		negate = NEW.negate
    WHERE
        id = OLD.id;

CREATE OR REPLACE RULE query_expr_xfunc_delete_rule AS
    ON DELETE TO query.expr_xfunc
    DO INSTEAD
    DELETE FROM query.expression WHERE id = OLD.id;

-- Create updatable view for IN expressions

CREATE OR REPLACE VIEW query.expr_xin AS
    SELECT
		id,
		parenthesize,
		parent_expr,
		seq_no,
		left_operand,
		subquery,
		negate
    FROM
        query.expression
    WHERE
        type = 'xin';

CREATE OR REPLACE RULE query_expr_xin_insert_rule AS
    ON INSERT TO query.expr_xin
    DO INSTEAD
    INSERT INTO query.expression (
		id,
		type,
		parenthesize,
		parent_expr,
		seq_no,
		left_operand,
		subquery,
		negate
    ) VALUES (
        COALESCE(NEW.id, NEXTVAL('query.expression_id_seq'::REGCLASS)),
        'xin',
        COALESCE(NEW.parenthesize, FALSE),
        NEW.parent_expr,
        COALESCE(NEW.seq_no, 1),
		NEW.left_operand,
		NEW.subquery,
		COALESCE(NEW.negate, false)
    );

CREATE OR REPLACE RULE query_expr_xin_update_rule AS
    ON UPDATE TO query.expr_xin
    DO INSTEAD
    UPDATE query.expression SET
        id = NEW.id,
        parenthesize = NEW.parenthesize,
        parent_expr = NEW.parent_expr,
        seq_no = NEW.seq_no,
		left_operand = NEW.left_operand,
		subquery = NEW.subquery,
		negate = NEW.negate
    WHERE
        id = OLD.id;

CREATE OR REPLACE RULE query_expr_xin_delete_rule AS
    ON DELETE TO query.expr_xin
    DO INSTEAD
    DELETE FROM query.expression WHERE id = OLD.id;

-- Create updatable view for IS NULL expressions

CREATE OR REPLACE VIEW query.expr_xisnull AS
    SELECT
		id,
		parenthesize,
		parent_expr,
		seq_no,
		left_operand,
		negate
    FROM
        query.expression
    WHERE
        type = 'xisnull';

CREATE OR REPLACE RULE query_expr_xisnull_insert_rule AS
    ON INSERT TO query.expr_xisnull
    DO INSTEAD
    INSERT INTO query.expression (
		id,
		type,
		parenthesize,
		parent_expr,
		seq_no,
		left_operand,
		negate
    ) VALUES (
        COALESCE(NEW.id, NEXTVAL('query.expression_id_seq'::REGCLASS)),
        'xisnull',
        COALESCE(NEW.parenthesize, FALSE),
        NEW.parent_expr,
        COALESCE(NEW.seq_no, 1),
		NEW.left_operand,
		COALESCE(NEW.negate, false)
    );

CREATE OR REPLACE RULE query_expr_xisnull_update_rule AS
    ON UPDATE TO query.expr_xisnull
    DO INSTEAD
    UPDATE query.expression SET
        id = NEW.id,
        parenthesize = NEW.parenthesize,
        parent_expr = NEW.parent_expr,
        seq_no = NEW.seq_no,
		left_operand = NEW.left_operand,
		negate = NEW.negate
    WHERE
        id = OLD.id;

CREATE OR REPLACE RULE query_expr_xisnull_delete_rule AS
    ON DELETE TO query.expr_xisnull
    DO INSTEAD
    DELETE FROM query.expression WHERE id = OLD.id;

-- Create updatable view for NULL expressions

CREATE OR REPLACE VIEW query.expr_xnull AS
    SELECT
		id,
		parenthesize,
		parent_expr,
		seq_no,
		negate
    FROM
        query.expression
    WHERE
        type = 'xnull';

CREATE OR REPLACE RULE query_expr_xnull_insert_rule AS
    ON INSERT TO query.expr_xnull
    DO INSTEAD
    INSERT INTO query.expression (
		id,
		type,
		parenthesize,
		parent_expr,
		seq_no,
		negate
    ) VALUES (
        COALESCE(NEW.id, NEXTVAL('query.expression_id_seq'::REGCLASS)),
        'xnull',
        COALESCE(NEW.parenthesize, FALSE),
        NEW.parent_expr,
        COALESCE(NEW.seq_no, 1),
		COALESCE(NEW.negate, false)
    );

CREATE OR REPLACE RULE query_expr_xnull_update_rule AS
    ON UPDATE TO query.expr_xnull
    DO INSTEAD
    UPDATE query.expression SET
        id = NEW.id,
        parenthesize = NEW.parenthesize,
        parent_expr = NEW.parent_expr,
        seq_no = NEW.seq_no,
		negate = NEW.negate
    WHERE
        id = OLD.id;

CREATE OR REPLACE RULE query_expr_xnull_delete_rule AS
    ON DELETE TO query.expr_xnull
    DO INSTEAD
    DELETE FROM query.expression WHERE id = OLD.id;

-- Create updatable view for numeric literal expressions

CREATE OR REPLACE VIEW query.expr_xnum AS
    SELECT
		id,
		parenthesize,
		parent_expr,
		seq_no,
		literal
    FROM
        query.expression
    WHERE
        type = 'xnum';

CREATE OR REPLACE RULE query_expr_xnum_insert_rule AS
    ON INSERT TO query.expr_xnum
    DO INSTEAD
    INSERT INTO query.expression (
		id,
		type,
		parenthesize,
		parent_expr,
		seq_no,
		literal
    ) VALUES (
        COALESCE(NEW.id, NEXTVAL('query.expression_id_seq'::REGCLASS)),
        'xnum',
        COALESCE(NEW.parenthesize, FALSE),
        NEW.parent_expr,
        COALESCE(NEW.seq_no, 1),
        NEW.literal
    );

CREATE OR REPLACE RULE query_expr_xnum_update_rule AS
    ON UPDATE TO query.expr_xnum
    DO INSTEAD
    UPDATE query.expression SET
        id = NEW.id,
        parenthesize = NEW.parenthesize,
        parent_expr = NEW.parent_expr,
        seq_no = NEW.seq_no,
        literal = NEW.literal
    WHERE
        id = OLD.id;

CREATE OR REPLACE RULE query_expr_xnum_delete_rule AS
    ON DELETE TO query.expr_xnum
    DO INSTEAD
    DELETE FROM query.expression WHERE id = OLD.id;

-- Create updatable view for operator expressions

CREATE OR REPLACE VIEW query.expr_xop AS
    SELECT
		id,
		parenthesize,
		parent_expr,
		seq_no,
		left_operand,
		operator,
		right_operand,
		negate
    FROM
        query.expression
    WHERE
        type = 'xop';

CREATE OR REPLACE RULE query_expr_xop_insert_rule AS
    ON INSERT TO query.expr_xop
    DO INSTEAD
    INSERT INTO query.expression (
		id,
		type,
		parenthesize,
		parent_expr,
		seq_no,
		left_operand,
		operator,
		right_operand,
		negate
    ) VALUES (
        COALESCE(NEW.id, NEXTVAL('query.expression_id_seq'::REGCLASS)),
        'xop',
        COALESCE(NEW.parenthesize, FALSE),
        NEW.parent_expr,
        COALESCE(NEW.seq_no, 1),
		NEW.left_operand,
		NEW.operator,
		NEW.right_operand,
		COALESCE(NEW.negate, false)
    );

CREATE OR REPLACE RULE query_expr_xop_update_rule AS
    ON UPDATE TO query.expr_xop
    DO INSTEAD
    UPDATE query.expression SET
        id = NEW.id,
        parenthesize = NEW.parenthesize,
        parent_expr = NEW.parent_expr,
        seq_no = NEW.seq_no,
		left_operand = NEW.left_operand,
		operator = NEW.operator,
		right_operand = NEW.right_operand,
		negate = NEW.negate
    WHERE
        id = OLD.id;

CREATE OR REPLACE RULE query_expr_xop_delete_rule AS
    ON DELETE TO query.expr_xop
    DO INSTEAD
    DELETE FROM query.expression WHERE id = OLD.id;

-- Create updatable view for series expressions,
-- i.e. series of expressions separated by operators

CREATE OR REPLACE VIEW query.expr_xser AS
    SELECT
		id,
		parenthesize,
		parent_expr,
		seq_no,
		operator,
		negate
    FROM
        query.expression
    WHERE
        type = 'xser';

CREATE OR REPLACE RULE query_expr_xser_insert_rule AS
    ON INSERT TO query.expr_xser
    DO INSTEAD
    INSERT INTO query.expression (
		id,
		type,
		parenthesize,
		parent_expr,
		seq_no,
		operator,
		negate
    ) VALUES (
        COALESCE(NEW.id, NEXTVAL('query.expression_id_seq'::REGCLASS)),
        'xser',
        COALESCE(NEW.parenthesize, FALSE),
        NEW.parent_expr,
        COALESCE(NEW.seq_no, 1),
		NEW.operator,
		COALESCE(NEW.negate, false)
    );

CREATE OR REPLACE RULE query_expr_xser_update_rule AS
    ON UPDATE TO query.expr_xser
    DO INSTEAD
    UPDATE query.expression SET
        id = NEW.id,
        parenthesize = NEW.parenthesize,
        parent_expr = NEW.parent_expr,
        seq_no = NEW.seq_no,
		operator = NEW.operator,
		negate = NEW.negate
    WHERE
        id = OLD.id;

CREATE OR REPLACE RULE query_expr_xser_delete_rule AS
    ON DELETE TO query.expr_xser
    DO INSTEAD
    DELETE FROM query.expression WHERE id = OLD.id;

-- Create updatable view for string literal expressions

CREATE OR REPLACE VIEW query.expr_xstr AS
    SELECT
        id,
        parenthesize,
        parent_expr,
        seq_no,
        literal
    FROM
        query.expression
    WHERE
        type = 'xstr';

CREATE OR REPLACE RULE query_expr_string_insert_rule AS
    ON INSERT TO query.expr_xstr
    DO INSTEAD
    INSERT INTO query.expression (
        id,
        type,
        parenthesize,
        parent_expr,
        seq_no,
        literal
    ) VALUES (
        COALESCE(NEW.id, NEXTVAL('query.expression_id_seq'::REGCLASS)),
        'xstr',
        COALESCE(NEW.parenthesize, FALSE),
        NEW.parent_expr,
        COALESCE(NEW.seq_no, 1),
        NEW.literal
    );

CREATE OR REPLACE RULE query_expr_string_update_rule AS
    ON UPDATE TO query.expr_xstr
    DO INSTEAD
    UPDATE query.expression SET
        id = NEW.id,
        parenthesize = NEW.parenthesize,
        parent_expr = NEW.parent_expr,
        seq_no = NEW.seq_no,
        literal = NEW.literal
    WHERE
        id = OLD.id;

CREATE OR REPLACE RULE query_expr_string_delete_rule AS
    ON DELETE TO query.expr_xstr
    DO INSTEAD
    DELETE FROM query.expression WHERE id = OLD.id;

-- Create updatable view for subquery expressions

CREATE OR REPLACE VIEW query.expr_xsubq AS
    SELECT
		id,
		parenthesize,
		parent_expr,
		seq_no,
		subquery,
		negate
    FROM
        query.expression
    WHERE
        type = 'xsubq';

CREATE OR REPLACE RULE query_expr_xsubq_insert_rule AS
    ON INSERT TO query.expr_xsubq
    DO INSTEAD
    INSERT INTO query.expression (
		id,
		type,
		parenthesize,
		parent_expr,
		seq_no,
		subquery,
		negate
    ) VALUES (
        COALESCE(NEW.id, NEXTVAL('query.expression_id_seq'::REGCLASS)),
        'xsubq',
        COALESCE(NEW.parenthesize, FALSE),
        NEW.parent_expr,
        COALESCE(NEW.seq_no, 1),
		NEW.subquery,
		COALESCE(NEW.negate, false)
    );

CREATE OR REPLACE RULE query_expr_xsubq_update_rule AS
    ON UPDATE TO query.expr_xsubq
    DO INSTEAD
    UPDATE query.expression SET
        id = NEW.id,
        parenthesize = NEW.parenthesize,
        parent_expr = NEW.parent_expr,
        seq_no = NEW.seq_no,
		subquery = NEW.subquery,
		negate = NEW.negate
    WHERE
        id = OLD.id;

CREATE OR REPLACE RULE query_expr_xsubq_delete_rule AS
    ON DELETE TO query.expr_xsubq
    DO INSTEAD
    DELETE FROM query.expression WHERE id = OLD.id;

INSERT INTO query.bind_variable (name,type,description,label)
    SELECT  'bucket','number','ID of the bucket to pull items from','Bucket ID';

-- Assumes completely empty 'query' schema
INSERT INTO query.stored_query (type, use_distinct) VALUES ('SELECT', TRUE); -- 1

INSERT INTO query.from_relation (type, table_name, class_name, table_alias) VALUES ('RELATION', 'container.user_bucket_item', 'cubi', 'cubi'); -- 1
UPDATE query.stored_query SET from_clause = 1;

INSERT INTO query.expr_xcol (table_alias, column_name) VALUES ('cubi', 'target_user'); -- 1
INSERT INTO query.select_item (stored_query,seq_no,expression) VALUES (1,1,1);

INSERT INTO query.expr_xcol (table_alias, column_name) VALUES ('cubi', 'bucket'); -- 2
INSERT INTO query.expr_xbind (bind_variable) VALUES ('bucket'); -- 3

INSERT INTO query.expr_xop (left_operand, operator, right_operand) VALUES (2, '=', 3); -- 4
UPDATE query.stored_query SET where_clause = 4;

SELECT SETVAL('query.stored_query_id_seq', 1000, TRUE) FROM query.stored_query;
SELECT SETVAL('query.from_relation_id_seq', 1000, TRUE) FROM query.from_relation;
SELECT SETVAL('query.expression_id_seq', 10000, TRUE) FROM query.expression;


COMMIT;
