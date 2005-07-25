#!/bin/sh
# args: {db-host} {db-name} {db-user} {db-password}

echo "You may be prompted several times for your database password..."

PGUSER=$3 PGHOST=$1 PGDATABASE=$2 psql -f 002.schema.config.sql
PGUSER=$3 PGHOST=$1 PGDATABASE=$2 psql -f 005.schema.actors.sql
PGUSER=$3 PGHOST=$1 PGDATABASE=$2 psql -f 006.schema.permissions.sql
PGUSER=$3 PGHOST=$1 PGDATABASE=$2 psql -f 010.schema.biblio.sql
PGUSER=$3 PGHOST=$1 PGDATABASE=$2 psql -f 020.schema.functions.sql
PGUSER=$3 PGHOST=$1 PGDATABASE=$2 psql -f 030.schema.metabib.sql
PGUSER=$3 PGHOST=$1 PGDATABASE=$2 psql -f 040.schema.asset.sql
PGUSER=$3 PGHOST=$1 PGDATABASE=$2 psql -f 080.schema.money.sql
PGUSER=$3 PGHOST=$1 PGDATABASE=$2 psql -f 090.schema.action.sql

PGUSER=$3 PGHOST=$1 PGDATABASE=$2 psql -f 800.fkeys.sql
PGUSER=$3 PGHOST=$1 PGDATABASE=$2 psql -f 900.audit-tables.sql
