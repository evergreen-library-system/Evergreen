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

CREATE LANGUAGE plperlu;

CREATE EXTENSION tablefunc;
CREATE EXTENSION xml2;
CREATE EXTENSION hstore;
