#!/bin/sh
# args: {db-host} {db-port} {db-name} {db-user} {db-password} {db-version}

# echo "You may be prompted several times for your database password..."

PGPASSWORD=$5 PGUSER=$4 PGHOST=$1 PGPORT=$2 PGDATABASE=$3 psql -f 000.english.pg$6.fts-config.sql
PGPASSWORD=$5 PGUSER=$4 PGHOST=$1 PGPORT=$2 PGDATABASE=$3 psql -f 001.schema.offline.sql
PGPASSWORD=$5 PGUSER=$4 PGHOST=$1 PGPORT=$2 PGDATABASE=$3 psql -f 002.schema.config.sql
PGPASSWORD=$5 PGUSER=$4 PGHOST=$1 PGPORT=$2 PGDATABASE=$3 psql -f 005.schema.actors.sql
PGPASSWORD=$5 PGUSER=$4 PGHOST=$1 PGPORT=$2 PGDATABASE=$3 psql -f 006.schema.permissions.sql
PGPASSWORD=$5 PGUSER=$4 PGHOST=$1 PGPORT=$2 PGDATABASE=$3 psql -f 006.data.permissions.sql
PGPASSWORD=$5 PGUSER=$4 PGHOST=$1 PGPORT=$2 PGDATABASE=$3 psql -f 010.schema.biblio.sql
PGPASSWORD=$5 PGUSER=$4 PGHOST=$1 PGPORT=$2 PGDATABASE=$3 psql -f 011.schema.authority.sql
PGPASSWORD=$5 PGUSER=$4 PGHOST=$1 PGPORT=$2 PGDATABASE=$3 psql -f 020.schema.functions.sql
PGPASSWORD=$5 PGUSER=$4 PGHOST=$1 PGPORT=$2 PGDATABASE=$3 psql -f 030.schema.metabib.sql
PGPASSWORD=$5 PGUSER=$4 PGHOST=$1 PGPORT=$2 PGDATABASE=$3 psql -f 040.schema.asset.sql
PGPASSWORD=$5 PGUSER=$4 PGHOST=$1 PGPORT=$2 PGDATABASE=$3 psql -f 070.schema.container.sql
PGPASSWORD=$5 PGUSER=$4 PGHOST=$1 PGPORT=$2 PGDATABASE=$3 psql -f 080.schema.money.sql
PGPASSWORD=$5 PGUSER=$4 PGHOST=$1 PGPORT=$2 PGDATABASE=$3 psql -f 090.schema.action.sql

PGPASSWORD=$5 PGUSER=$4 PGHOST=$1 PGPORT=$2 PGDATABASE=$3 psql -f 300.schema.staged_search.sql

PGPASSWORD=$5 PGUSER=$4 PGHOST=$1 PGPORT=$2 PGDATABASE=$3 psql -f 500.view.cross-schema.sql

PGPASSWORD=$5 PGUSER=$4 PGHOST=$1 PGPORT=$2 PGDATABASE=$3 psql -f 800.fkeys.sql
PGPASSWORD=$5 PGUSER=$4 PGHOST=$1 PGPORT=$2 PGDATABASE=$3 psql -f 900.audit-functions.sql
PGPASSWORD=$5 PGUSER=$4 PGHOST=$1 PGPORT=$2 PGDATABASE=$3 psql -f 901.audit-tables.sql

PGPASSWORD=$5 PGUSER=$4 PGHOST=$1 PGPORT=$2 PGDATABASE=$3 psql -f reporter-schema.sql
PGPASSWORD=$5 PGUSER=$4 PGHOST=$1 PGPORT=$2 PGDATABASE=$3 psql -f extend-reporter.sql
