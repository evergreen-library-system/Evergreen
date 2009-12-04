-- Script to create the query schema and the tables therein

BEGIN;

DROP SCHEMA IF EXISTS query CASCADE;
CREATE SCHEMA query;
COMMENT ON SCHEMA actor IS $$
/*
 * Copyright (C) 2009  Equinox Software, Inc. / Georgia Public Library Service
 * Scott McKellar <scott@esilibrary.com>
 *
 * Schema: query
 *
 * Contains tables designed to represent user-defined queries for
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

CREATE TABLE query.datatype (
	id              SERIAL            PRIMARY KEY,
	datatype_name   TEXT              NOT NULL UNIQUE,
	is_numeric      BOOL              NOT NULL DEFAULT FALSE,
	is_composite    BOOL              NOT NULL DEFAULT FALSE,
	CONSTRAINT qdt_comp_not_num CHECK
	( is_numeric IS FALSE OR is_composite IS FALSE )
);

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
		seq_no
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
		seq_no
    ) VALUES (
        COALESCE(NEW.id, NEXTVAL('query.expression_id_seq'::REGCLASS)),
        'xbet',
        COALESCE(NEW.parenthesize, FALSE),
        NEW.parent_expr,
        COALESCE(NEW.seq_no, 1)
    );

CREATE OR REPLACE RULE query_expr_xbet_update_rule AS
    ON UPDATE TO query.expr_xbet
    DO INSTEAD
    UPDATE query.expression SET
        id = NEW.id,
        parenthesize = NEW.parenthesize,
        parent_expr = NEW.parent_expr,
        seq_no = NEW.seq_no
    WHERE
        id = OLD.id;

CREATE OR REPLACE RULE query_expr_xbet_delete_rule AS
    ON DELETE TO query.expr_xbet
    DO INSTEAD
    DELETE FROM query.expression WHERE id = OLD.id;

-- Create updatable view for boolean expressions

CREATE OR REPLACE VIEW query.expr_xbool AS
    SELECT
		id,
		parenthesize,
		parent_expr,
		seq_no,
		literal
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
		literal
    ) VALUES (
        COALESCE(NEW.id, NEXTVAL('query.expression_id_seq'::REGCLASS)),
        'xbool',
        COALESCE(NEW.parenthesize, FALSE),
        NEW.parent_expr,
        COALESCE(NEW.seq_no, 1),
        NEW.literal
    );

CREATE OR REPLACE RULE query_expr_xbool_update_rule AS
    ON UPDATE TO query.expr_xbool
    DO INSTEAD
    UPDATE query.expression SET
        id = NEW.id,
        parenthesize = NEW.parenthesize,
        parent_expr = NEW.parent_expr,
        seq_no = NEW.seq_no,
        literal = NEW.literal
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
		seq_no
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
		seq_no
    ) VALUES (
        COALESCE(NEW.id, NEXTVAL('query.expression_id_seq'::REGCLASS)),
        'xcase',
        COALESCE(NEW.parenthesize, FALSE),
        NEW.parent_expr,
        COALESCE(NEW.seq_no, 1)
    );

CREATE OR REPLACE RULE query_expr_xcase_update_rule AS
    ON UPDATE TO query.expr_xcase
    DO INSTEAD
    UPDATE query.expression SET
        id = NEW.id,
        parenthesize = NEW.parenthesize,
        parent_expr = NEW.parent_expr,
        seq_no = NEW.seq_no
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
		cast_type
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
		cast_type
    ) VALUES (
        COALESCE(NEW.id, NEXTVAL('query.expression_id_seq'::REGCLASS)),
        'xcast',
        COALESCE(NEW.parenthesize, FALSE),
        NEW.parent_expr,
        COALESCE(NEW.seq_no, 1),
		NEW.left_operand,
		NEW.cast_type
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
		cast_type = NEW.cast_type
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
		column_name
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
		column_name
    ) VALUES (
        COALESCE(NEW.id, NEXTVAL('query.expression_id_seq'::REGCLASS)),
        'xcol',
        COALESCE(NEW.parenthesize, FALSE),
        NEW.parent_expr,
        COALESCE(NEW.seq_no, 1),
		NEW.table_alias,
		NEW.column_name
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
		column_name = NEW.column_name
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
		subquery
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
		subquery
    ) VALUES (
        COALESCE(NEW.id, NEXTVAL('query.expression_id_seq'::REGCLASS)),
        'xex',
        COALESCE(NEW.parenthesize, FALSE),
        NEW.parent_expr,
        COALESCE(NEW.seq_no, 1),
		NEW.subquery
    );

CREATE OR REPLACE RULE query_expr_xex_update_rule AS
    ON UPDATE TO query.expr_xex
    DO INSTEAD
    UPDATE query.expression SET
        id = NEW.id,
        parenthesize = NEW.parenthesize,
        parent_expr = NEW.parent_expr,
        seq_no = NEW.seq_no,
		subquery = NEW.subquery
    WHERE
        id = OLD.id;

CREATE OR REPLACE RULE query_expr_xex_delete_rule AS
    ON DELETE TO query.expr_xex
    DO INSTEAD
    DELETE FROM query.expression WHERE id = OLD.id;

-- Create updatable view for field expressions

CREATE OR REPLACE VIEW query.expr_xfld AS
    SELECT
		id,
		parenthesize,
		parent_expr,
		seq_no,
		column_name,
		left_operand
    FROM
        query.expression
    WHERE
        type = 'xfld';

CREATE OR REPLACE RULE query_expr_xfld_insert_rule AS
    ON INSERT TO query.expr_xfld
    DO INSTEAD
    INSERT INTO query.expression (
		id,
		type,
		parenthesize,
		parent_expr,
		seq_no,
		column_name,
		left_operand
    ) VALUES (
        COALESCE(NEW.id, NEXTVAL('query.expression_id_seq'::REGCLASS)),
        'xfld',
        COALESCE(NEW.parenthesize, FALSE),
        NEW.parent_expr,
        COALESCE(NEW.seq_no, 1),
		NEW.column_name,
		NEW.left_operand
    );

CREATE OR REPLACE RULE query_expr_xfld_update_rule AS
    ON UPDATE TO query.expr_xfld
    DO INSTEAD
    UPDATE query.expression SET
        id = NEW.id,
        parenthesize = NEW.parenthesize,
        parent_expr = NEW.parent_expr,
        seq_no = NEW.seq_no,
		column_name = NEW.column_name,
		left_operand = NEW.left_operand
    WHERE
        id = OLD.id;

CREATE OR REPLACE RULE query_expr_xfld_delete_rule AS
    ON DELETE TO query.expr_xfld
    DO INSTEAD
    DELETE FROM query.expression WHERE id = OLD.id;

-- Create updatable view for function call expressions

CREATE OR REPLACE VIEW query.expr_xfunc AS
    SELECT
		id,
		parenthesize,
		parent_expr,
		seq_no,
		function_id
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
		function_id
    ) VALUES (
        COALESCE(NEW.id, NEXTVAL('query.expression_id_seq'::REGCLASS)),
        'xfunc',
        COALESCE(NEW.parenthesize, FALSE),
        NEW.parent_expr,
        COALESCE(NEW.seq_no, 1),
		NEW.function_id
    );

CREATE OR REPLACE RULE query_expr_xfunc_update_rule AS
    ON UPDATE TO query.expr_xfunc
    DO INSTEAD
    UPDATE query.expression SET
        id = NEW.id,
        parenthesize = NEW.parenthesize,
        parent_expr = NEW.parent_expr,
        seq_no = NEW.seq_no,
		function_id = NEW.function_id
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
		subquery
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
		subquery
    ) VALUES (
        COALESCE(NEW.id, NEXTVAL('query.expression_id_seq'::REGCLASS)),
        'xin',
        COALESCE(NEW.parenthesize, FALSE),
        NEW.parent_expr,
        COALESCE(NEW.seq_no, 1),
		NEW.subquery
    );

CREATE OR REPLACE RULE query_expr_xin_update_rule AS
    ON UPDATE TO query.expr_xin
    DO INSTEAD
    UPDATE query.expression SET
        id = NEW.id,
        parenthesize = NEW.parenthesize,
        parent_expr = NEW.parent_expr,
        seq_no = NEW.seq_no,
		subquery = NEW.subquery
    WHERE
        id = OLD.id;

CREATE OR REPLACE RULE query_expr_xin_delete_rule AS
    ON DELETE TO query.expr_xin
    DO INSTEAD
    DELETE FROM query.expression WHERE id = OLD.id;

-- Create updatable view for NOT BETWEEN expressions

CREATE OR REPLACE VIEW query.expr_xnbet AS
    SELECT
		id,
		parenthesize,
		parent_expr,
		seq_no
    FROM
        query.expression
    WHERE
        type = 'xnbet';

CREATE OR REPLACE RULE query_expr_xnbet_insert_rule AS
    ON INSERT TO query.expr_xnbet
    DO INSTEAD
    INSERT INTO query.expression (
		id,
		type,
		parenthesize,
		parent_expr,
		seq_no
    ) VALUES (
        COALESCE(NEW.id, NEXTVAL('query.expression_id_seq'::REGCLASS)),
        'xnbet',
        COALESCE(NEW.parenthesize, FALSE),
        NEW.parent_expr,
        COALESCE(NEW.seq_no, 1)
    );

CREATE OR REPLACE RULE query_expr_xnbet_update_rule AS
    ON UPDATE TO query.expr_xnbet
    DO INSTEAD
    UPDATE query.expression SET
        id = NEW.id,
        parenthesize = NEW.parenthesize,
        parent_expr = NEW.parent_expr,
        seq_no = NEW.seq_no
    WHERE
        id = OLD.id;

CREATE OR REPLACE RULE query_expr_xnbet_delete_rule AS
    ON DELETE TO query.expr_xnbet
    DO INSTEAD
    DELETE FROM query.expression WHERE id = OLD.id;

-- Create updatable view for NOT EXISTS expressions

CREATE OR REPLACE VIEW query.expr_xnex AS
    SELECT
		id,
		parenthesize,
		parent_expr,
		seq_no,
		subquery
    FROM
        query.expression
    WHERE
        type = 'xnex';

CREATE OR REPLACE RULE query_expr_xnex_insert_rule AS
    ON INSERT TO query.expr_xnex
    DO INSTEAD
    INSERT INTO query.expression (
		id,
		type,
		parenthesize,
		parent_expr,
		seq_no,
		subquery
    ) VALUES (
        COALESCE(NEW.id, NEXTVAL('query.expression_id_seq'::REGCLASS)),
        'xnex',
        COALESCE(NEW.parenthesize, FALSE),
        NEW.parent_expr,
        COALESCE(NEW.seq_no, 1),
		NEW.subquery
    );

CREATE OR REPLACE RULE query_expr_xnex_update_rule AS
    ON UPDATE TO query.expr_xnex
    DO INSTEAD
    UPDATE query.expression SET
        id = NEW.id,
        parenthesize = NEW.parenthesize,
        parent_expr = NEW.parent_expr,
        seq_no = NEW.seq_no,
		subquery = NEW.subquery
    WHERE
        id = OLD.id;

CREATE OR REPLACE RULE query_expr_xnex_delete_rule AS
    ON DELETE TO query.expr_xnex
    DO INSTEAD
    DELETE FROM query.expression WHERE id = OLD.id;

-- Create updatable view for NOT IN expressions

CREATE OR REPLACE VIEW query.expr_xnin AS
    SELECT
		id,
		parenthesize,
		parent_expr,
		seq_no,
		subquery
    FROM
        query.expression
    WHERE
        type = 'xnin';

CREATE OR REPLACE RULE query_expr_xnin_insert_rule AS
    ON INSERT TO query.expr_xnin
    DO INSTEAD
    INSERT INTO query.expression (
		id,
		type,
		parenthesize,
		parent_expr,
		seq_no,
		subquery
    ) VALUES (
        COALESCE(NEW.id, NEXTVAL('query.expression_id_seq'::REGCLASS)),
        'xnin',
        COALESCE(NEW.parenthesize, FALSE),
        NEW.parent_expr,
        COALESCE(NEW.seq_no, 1),
		NEW.subquery
    );

CREATE OR REPLACE RULE query_expr_xnin_update_rule AS
    ON UPDATE TO query.expr_xnin
    DO INSTEAD
    UPDATE query.expression SET
        id = NEW.id,
        parenthesize = NEW.parenthesize,
        parent_expr = NEW.parent_expr,
        seq_no = NEW.seq_no,
		subquery = NEW.subquery
    WHERE
        id = OLD.id;

CREATE OR REPLACE RULE query_expr_xnin_delete_rule AS
    ON DELETE TO query.expr_xnin
    DO INSTEAD
    DELETE FROM query.expression WHERE id = OLD.id;

-- Create updatable view for NULL expressions

CREATE OR REPLACE VIEW query.expr_xnull AS
    SELECT
		id,
		parenthesize,
		parent_expr,
		seq_no
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
		seq_no
    ) VALUES (
        COALESCE(NEW.id, NEXTVAL('query.expression_id_seq'::REGCLASS)),
        'xnull',
        COALESCE(NEW.parenthesize, FALSE),
        NEW.parent_expr,
        COALESCE(NEW.seq_no, 1)
    );

CREATE OR REPLACE RULE query_expr_xnull_update_rule AS
    ON UPDATE TO query.expr_xnull
    DO INSTEAD
    UPDATE query.expression SET
        id = NEW.id,
        parenthesize = NEW.parenthesize,
        parent_expr = NEW.parent_expr,
        seq_no = NEW.seq_no
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
		right_operand
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
		right_operand
    ) VALUES (
        COALESCE(NEW.id, NEXTVAL('query.expression_id_seq'::REGCLASS)),
        'xop',
        COALESCE(NEW.parenthesize, FALSE),
        NEW.parent_expr,
        COALESCE(NEW.seq_no, 1),
		NEW.left_operand,
		NEW.operator,
		NEW.right_operand
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
		right_operand = NEW.right_operand
    WHERE
        id = OLD.id;

CREATE OR REPLACE RULE query_expr_xop_delete_rule AS
    ON DELETE TO query.expr_xop
    DO INSTEAD
    DELETE FROM query.expression WHERE id = OLD.id;

-- Create updatable view for string literal expressions

CREATE OR REPLACE VIEW query.expr_string AS
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
    ON INSERT TO query.expr_string
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
    ON UPDATE TO query.expr_string
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
    ON DELETE TO query.expr_string
    DO INSTEAD
    DELETE FROM query.expression WHERE id = OLD.id;

-- Create updatable view for subquery expressions

CREATE OR REPLACE VIEW query.expr_xsubq AS
    SELECT
		id,
		parenthesize,
		parent_expr,
		seq_no,
		subquery
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
		subquery
    ) VALUES (
        COALESCE(NEW.id, NEXTVAL('query.expression_id_seq'::REGCLASS)),
        'xsubq',
        COALESCE(NEW.parenthesize, FALSE),
        NEW.parent_expr,
        COALESCE(NEW.seq_no, 1),
		NEW.subquery
    );

CREATE OR REPLACE RULE query_expr_xsubq_update_rule AS
    ON UPDATE TO query.expr_xsubq
    DO INSTEAD
    UPDATE query.expression SET
        id = NEW.id,
        parenthesize = NEW.parenthesize,
        parent_expr = NEW.parent_expr,
        seq_no = NEW.seq_no,
		subquery = NEW.subquery
    WHERE
        id = OLD.id;

CREATE OR REPLACE RULE query_expr_xsubq_delete_rule AS
    ON DELETE TO query.expr_xsubq
    DO INSTEAD
    DELETE FROM query.expression WHERE id = OLD.id;

COMMIT;
