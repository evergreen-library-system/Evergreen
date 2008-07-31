#!/bin/sh

# ---------------------------------------------------------------------------
# Store command line args for later use
# args: {db-host} {db-port} {db-name} {db-user} {db-password}
# ---------------------------------------------------------------------------
PGHOST=$1
PGPORT=$2
PGDATABASE=$3
PGUSER=$4
PGPASSWORD=$5
export PGHOST PGPORT PGDATABASE PGUSER PGPASSWORD

# ---------------------------------------------------------------------------
# Lookup the database version from the PostgreSQL server.
# ---------------------------------------------------------------------------
DB_VERSION=`psql -qtc 'show server_version;' | xargs | cut -c1,3`
if [ -z "$DB_VERSION" ] || [ `echo $DB_VERSION | grep -c '[^0-9]'` != 0 ]; then
  cat <<EOM
********************************************************************************
* Could not determine the version of PostgreSQL you have installed.  Our best  *
* guess was:                                                                   *
* $DB_VERSION
* which didn't make any sense.  For assistance, please email                   *
* open-ils-general@list.georgialibraries.org or join #OpenILS-Evergreen on the *
* freenode IRC network.                                                        *
********************************************************************************
EOM
  exit 1
fi

# ---------------------------------------------------------------------------
# Validate fts-config file is available for specified DB_VERSION.
# ---------------------------------------------------------------------------
if [ -e "000.english.pg$DB_VERSION.fts-config.sql" ]; then
  fts_config_file="000.english.pg$DB_VERSION.fts-config.sql"
else
  # -------------------------------------------------------------------------
  # Attempt to auto-detect the latest available config file.
  # -------------------------------------------------------------------------
  last_ver=""
  for i in $(seq 80 99 | sort -rn); do
    if [ -e "000.english.pg$i.fts-config.sql" ]; then
      last_ver=$i
      break
    fi
  done
  if [ -z "$last_ver" ]; then
    cat <<EOM
********************************************************************************
* Cannot locate any configuration files for  full text search config.  This    *
* may indicate a problem with your copy of the source files.  We attempted to  *
* find files like 000.english.pg83.fts-config.sql in this directory:           *
* `pwd` 
* but were unsuccessful.  Aborting.                                            *
********************************************************************************
EOM
    exit 1
  fi

  a=$DB_VERSION  # preserves the text alignment below, in a cheap fashion
  b=$last_ver    # assuming of course two character DB_VERSION and last_ver
cat <<EOM
********************************************************************************
* There is no configuration for full text search config, for the database      *
* version you have installed ($a).  If you're not really sure why, you should  *
* proabably press 'Control-C' now, and abort.  To continue using the latest    *
* available version ($b), press enter. For assistance, please email            *
* open-ils-general@list.georgialibraries.org or join #OpenILS-Evergreen on the *
* freenode IRC network.                                                        *
********************************************************************************
EOM
  read unused
  fts_config_file="000.english.pg$last_ver.fts-config.sql"
fi

# ---------------------------------------------------------------------------
# This describes the order in which the SQL files will be eval'd by psql.
# ---------------------------------------------------------------------------
ordered_file_list="
  $fts_config_file

  001.schema.offline.sql

  002.schema.config.sql
  002.functions.aggregate.sql
  002.functions.config.sql

  005.schema.actors.sql
  006.schema.permissions.sql
  010.schema.biblio.sql
  011.schema.authority.sql
  012.schema.vandelay.sql
  020.schema.functions.sql
  030.schema.metabib.sql
  040.schema.asset.sql
  070.schema.container.sql
  080.schema.money.sql
  090.schema.action.sql
  
  100.circ_matrix.sql
  110.hold_matrix.sql

  200.schema.acq.sql
  210.schema.serials.sql
  
  300.schema.staged_search.sql
  
  500.view.cross-schema.sql
  
  800.fkeys.sql
  
  900.audit-functions.sql
  901.audit-tables.sql
  950.data.seed-values.sql
  951.data.MODS-xsl.sql
  952.data.MODS3-xsl.sql
  953.data.MODS32-xsl.sql
  
  reporter-schema.sql
  extend-reporter.sql
"

# ---------------------------------------------------------------------------
# Import files via psql, warn user on error, suggest abort.
# ---------------------------------------------------------------------------
for sql_file in $ordered_file_list; do
  # It would be wise to turn this on only if confidence is high that errors in
  # scripts will result in terminal failures.  Currently, there are a couple
  # that seem benign.  --asjoyner
  # export ON_ERROR_STOP=1

  export PGHOST PGPORT PGDATABASE PGUSER PGPASSWORD
  psql -f $sql_file
  if [ $? != 0 ]; then
    cat <<EOM
********************************************************************************
* There was an error with a database configuration file:                       *
* $sql_file
* It is very likely that your installation will be unsuccessful because of     *
* this error.  Press Control-C to abort, or press enter to charge ahead.       *
********************************************************************************
EOM
    read unused
  fi
done

