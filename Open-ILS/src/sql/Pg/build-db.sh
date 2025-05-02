#!/bin/sh

# ---------------------------------------------------------------------------
# Store command line args for later use
# args: {db-host} {db-port} {db-name} {db-user} {db-password} {verbose}
# ---------------------------------------------------------------------------
PGHOST=$1
PGPORT=$2
PGDATABASE=$3
PGUSER=$4
PGPASSWORD=$5
VERBOSE=$6
export PGHOST PGPORT PGDATABASE PGUSER PGPASSWORD

# ---------------------------------------------------------------------------
# Lookup the database version from the PostgreSQL server.
# ---------------------------------------------------------------------------
DB_VERSION=`psql -qXAtc 'show server_version;' | cut -d. -f 1,2 | tr -d '.' | cut -c1,2`
if [ -z "$DB_VERSION" ] || [ `echo $DB_VERSION | grep -c '[^0-9]'` != 0 ]; then
  cat <<EOM
********************************************************************************
* Could not determine the version of PostgreSQL you have installed.  Our best  *
* guess was:                                                                   *
* $DB_VERSION
* which didn't make any sense.  For assistance, please email                   *
* open-ils-general@list.georgialibraries.org or join #Evergreen on the         *
* Libera IRC network.                                                        *
********************************************************************************
EOM
  exit 1
fi

fts_config_file="000.english.pg.fts-config.sql"

# ---------------------------------------------------------------------------
# Import files via psql, warn user on error, suggest abort.  SQL scripts
# are processed in the ordered listed in sql_file_manifest.
# ---------------------------------------------------------------------------
cat sql_file_manifest | while read sql_file; do
  if [ `expr "$sql_file" : "^#"` = 1 ] || [ "$sql_file" = '' ]; then
    continue;
  fi

  if [ $sql_file = 'FTS_CONFIG_FILE' ]; then
    sql_file=$fts_config_file
  fi

  # It would be wise to turn this on only if confidence is high that errors in
  # scripts will result in terminal failures.  Currently, there are a couple
  # that seem benign.  --asjoyner
  # export ON_ERROR_STOP=1

  export PGHOST PGPORT PGDATABASE PGUSER PGPASSWORD
  # Hide most of the harmless messages that obscure real problems
  if [ -z "$VERBOSE" ]; then
    psql -v eg_version=NULL -f $sql_file 2>&1 | grep -v NOTICE | grep -v "^INSERT"
  else
    psql -v eg_version=NULL -f $sql_file
  fi
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

