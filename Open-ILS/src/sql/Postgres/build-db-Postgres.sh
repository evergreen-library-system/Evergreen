#!/bin/sh

psql -U $1 -d $2 -f 002.schema.config.sql
psql -U $1 -d $2 -f 005.schema.actors.sql
psql -U $1 -d $2 -f 010.schema.biblio.sql
psql -U $1 -d $2 -f 020.schema.functions.sql
psql -U $1 -d $2 -f 030.schema.metabib.sql
#psql -U $1 -d $2 -f 805.fkeys.actors.sql
#psql -U $1 -d $2 -f 810.fkeys.biblio.sql
#psql -U $1 -d $2 -f 830.fkeys.metabib.sql
#psql -U $1 -d $2 -f 910.audit.biblio.sql
