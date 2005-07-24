#!/bin/sh

psql -U $1 -d $2 -f 002.schema.config.sql
psql -U $1 -d $2 -f 005.schema.actors.sql
psql -U $1 -d $2 -f 010.schema.biblio.sql
psql -U $1 -d $2 -f 020.schema.functions.sql
psql -U $1 -d $2 -f 030.schema.metabib.sql
psql -U $1 -d $2 -f 040.schema.asset.sql
psql -U $1 -d $2 -f 080.schema.money.sql
psql -U $1 -d $2 -f 090.schema.action.sql

psql -U $1 -d $2 -f 800.fkeys.sql
psql -U $1 -d $2 -f 900.audit-tables.sql
