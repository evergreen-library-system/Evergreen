#!/bin/sh

if [ $# = 0 ]; then
    echo Update database schema comments for an Evegreen database
    echo
    echo usage: $0 db-host db-port db-name db-user db-password
    exit 0;
fi

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

cd `dirname $0`
export PATH=.:$PATH

grab-db-comments.pl sql_file_manifest | psql
