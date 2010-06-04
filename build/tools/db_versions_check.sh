#!/bin/bash
#
# Author: Joe Atzberger
# 

DB_HOST=$1
DB_USER=$2
DB_NAME=$3

function usage() {
    cat <<END_OF_USAGE
usage: $0  db_host  db_user  db_name

Look for missing or failed DB updates in the update log.

ALL parameters are required to access the postgres database.

PARAMETERS:
  db_host - database host system (e.g. "localhost" or "10.121.99.6")
  db_user - database username
  db_name - database name
    
You will be prompted for the postgres password if necessary.

END_OF_USAGE
}

function die() {
    echo "ERROR: $1" >&2;
    exit 1;
}

function usage_die() {
    exec >&2;
    echo;
    echo "ERROR: $1";
    echo;
    usage;
    exit 1;
}

[ -z "$DB_HOST" -o -z "$DB_USER" -o -z "$DB_NAME" ] && usage_die "Need all DB parameters";

PSQL_ACCESS="-h $DB_HOST -U $DB_USER $DB_NAME";

declare -a FILES;
declare -a MISSING;
STEP=0;

psql -c "SELECT version FROM config.upgrade_log ORDER BY version" -t $PSQL_ACCESS | \
while read VERSION; do 
    [ -z $VERSION ] && break;
    [    $VERSION ] || break;
    STEP=$((${STEP}+1));
    # echo -n "Version: $VERSION  ";
    FILES[${#FILES[@]}]=$VERSION;      # "push" onto FILES array
    VERSION=$(echo $VERSION | sed -e 's/^ *0*//');    # This is a separate step so we can check $? above.
    # echo $VERSION " (" ${#FILES[@]} " / " ${#MISSING[@]} ")";
    while [[ $STEP -lt $VERSION ]] ; do
        echo "MISSING:" $(printf "%0.4d" $STEP) "*******";
        MISSING[${#MISSING[@]}]=$(printf "%0.4d" $STEP);      # "push" onto FILES array
        STEP=$((${STEP}+1));
    done;
    # [ $VERBOSE ] && echo RAW VERSION: $VERSION      # TODO: for verbose mod
done;
[  $? -gt 0  ] && die "Database access failed or was interrupted.";
exit;

