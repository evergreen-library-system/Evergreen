BEGIN;

-- Define the most common datatypes in query.datatype.  Note that none of
-- these stock datatypes specifies a width or precision.

-- Also: set the sequence for query.datatype to 1000, leaving plenty of
-- room for more stock datatypes if we ever want to add them.

INSERT INTO config.upgrade_log (version) VALUES ('0311'); -- Scott McKellar

SELECT setval( 'query.datatype_id_seq', 1000 );

INSERT INTO query.datatype (id, datatype_name, is_numeric )
  VALUES (1, 'SMALLINT', true);
 
INSERT INTO query.datatype (id, datatype_name, is_numeric )
  VALUES (2, 'INTEGER', true);
 
INSERT INTO query.datatype (id, datatype_name, is_numeric )
  VALUES (3, 'BIGINT', true);
 
INSERT INTO query.datatype (id, datatype_name, is_numeric )
  VALUES (4, 'DECIMAL', true);
 
INSERT INTO query.datatype (id, datatype_name, is_numeric )
  VALUES (5, 'NUMERIC', true);
 
INSERT INTO query.datatype (id, datatype_name, is_numeric )
  VALUES (6, 'REAL', true);
 
INSERT INTO query.datatype (id, datatype_name, is_numeric )
  VALUES (7, 'DOUBLE PRECISION', true);
 
INSERT INTO query.datatype (id, datatype_name, is_numeric )
  VALUES (8, 'SERIAL', true);
 
INSERT INTO query.datatype (id, datatype_name, is_numeric )
  VALUES (9, 'BIGSERIAL', true);
 
INSERT INTO query.datatype (id, datatype_name, is_numeric )
  VALUES (10, 'MONEY', false);
 
INSERT INTO query.datatype (id, datatype_name, is_numeric )
  VALUES (11, 'VARCHAR', false);
 
INSERT INTO query.datatype (id, datatype_name, is_numeric )
  VALUES (12, 'CHAR', false);
 
INSERT INTO query.datatype (id, datatype_name, is_numeric )
  VALUES (13, 'TEXT', false);
 
INSERT INTO query.datatype (id, datatype_name, is_numeric )
  VALUES (14, '"char"', false);
 
INSERT INTO query.datatype (id, datatype_name, is_numeric )
  VALUES (15, 'NAME', false);
 
INSERT INTO query.datatype (id, datatype_name, is_numeric )
  VALUES (16, 'BYTEA', false);
 
INSERT INTO query.datatype (id, datatype_name, is_numeric )
  VALUES (17, 'TIMESTAMP WITHOUT TIME ZONE', false);
 
INSERT INTO query.datatype (id, datatype_name, is_numeric )
  VALUES (18, 'TIMESTAMP WITH TIME ZONE', false);
 
INSERT INTO query.datatype (id, datatype_name, is_numeric )
  VALUES (19, 'DATE', false);
 
INSERT INTO query.datatype (id, datatype_name, is_numeric )
  VALUES (20, 'TIME WITHOUT TIME ZONE', false);
 
INSERT INTO query.datatype (id, datatype_name, is_numeric )
  VALUES (21, 'TIME WITH TIME ZONE', false);
 
INSERT INTO query.datatype (id, datatype_name, is_numeric )
  VALUES (22, 'INTERVAL', false);
 
INSERT INTO query.datatype (id, datatype_name, is_numeric )
  VALUES (23, 'BOOLEAN', false);
 
COMMIT;
