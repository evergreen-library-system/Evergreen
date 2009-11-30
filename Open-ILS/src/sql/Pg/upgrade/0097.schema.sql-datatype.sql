-- Script to create the query schema and the tables therein

BEGIN;

INSERT INTO config.upgrade_log (version) VALUES ('0097'); -- Scott McKellar

DROP SCHEMA IF EXISTS sql CASCADE;
DROP SCHEMA IF EXISTS query CASCADE;

CREATE SCHEMA query;

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

COMMIT;
