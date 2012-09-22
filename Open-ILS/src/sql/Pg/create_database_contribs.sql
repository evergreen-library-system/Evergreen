-- This file is intended to be called by eg_db_config.pl

-- If manually calling:
-- Connect to the postgres database initially
-- Specify the database to create as -vdb_name=DATABASE
-- Specify the postgres contrib directory as -vcontrib_dir=CONTRIBDIR
-- You can get the contrib directory using pg_config --sharedir and adding a /contrib to it

-- NOTE: This file does not do transactions
-- This is intentional. Please do not wrap in BEGIN/COMMIT.
DROP DATABASE IF EXISTS :db_name;

CREATE DATABASE :db_name TEMPLATE template0 ENCODING 'UNICODE' LC_COLLATE 'C' LC_CTYPE 'C';

\connect :db_name

--CREATE LANGUAGE plperl;
CREATE LANGUAGE plperlu;

-- This dance is because :variable/blah doesn't seem to work when doing \i
-- But it does when doing \set
-- So we \set to a single variable, then use that single variable with \i
\set load_file :contrib_dir/tablefunc.sql
\i :load_file
\set load_file :contrib_dir/pgxml.sql
\i :load_file
\set load_file :contrib_dir/hstore.sql
\i :load_file
