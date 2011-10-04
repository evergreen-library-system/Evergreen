#!/bin/bash
#
# Based on a script by Bill Erickson.
#
# TODO:
#   ADD OPTIONS:
#     ~ single-step mode that calls psql -f once per file
#          (but also prompts for password once per file).
#     ~ help/usage option

DB_HOST=$1
DB_USER=$2
DB_NAME=$3

function usage() {
    cat <<END_OF_USAGE
usage: $0  db_host  db_user  db_name

Automtically update the DB with all numbered updates beyond the last installed one.

ALL parameters are required to access the postgres database.

PARAMETERS:
  db_host - database host system (e.g. "localhost" or "10.121.99.6")
  db_user - database username
  db_name - database name
    
Run from your source repository root or Open-ILS/src/sql/Pg directory.

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

function feedback() {
    #TODO: add a test and verbose mode that use this.
    echo "Updating database $DB_NAME on $DB_HOST as user $DB_USER";
}

[ -z "$DB_HOST" -o -z "$DB_USER" -o -z "$DB_NAME" ] && usage_die "Need all DB parameters";

PSQL_ACCESS="-h $DB_HOST -U $DB_USER $DB_NAME";

# Find the current version of Evergreen, which is the installed version to which the upgrade script is being applied
EGVERSION=$(eg_config --version|cut -f2 -d' ');
[  $? -gt 0  ] && die "Could not find eg_config, please make sure it is in your path.";
[  -z "$EGVERSION"  ] && die "Could not determine Evergreen version from eg_config.";

# Need to avoid versions like '1.6.0.4' from throwing off the upgrade
VERSION=$(psql -c "SELECT MAX(version) FROM config.upgrade_log WHERE version ~ E'^\\\\d+$'" -t $PSQL_ACCESS);
[  $? -gt 0  ] && die "Database access failed.";
# [ $VERBOSE ] && echo RAW VERSION: $VERSION     # TODO: for verbose mode
VERSION=$(echo $VERSION | sed -e 's/^ *0*//');    # This is a separate step so we can check $? above.
[ -z "$VERSION" ] && usage_die "config.upgrade_log missing ANY installed version data!";
echo "* Last installed version  ->  $VERSION";

if [ -d ./Open-ILS/src/sql/Pg ] ; then
    cd ./Open-ILS/src/sql/Pg ;
fi
[ -d ./upgrade ] || usage_die "No ./upgrade directory found.  Please run from Open-ILS/src/sql/Pg";

MAX=$(ls upgrade/[0-9][0-9][0-9][0-9]* 2>/dev/null | tail -1 | cut -c9-12 );   # could take an optional arg to set this, if we wanted.
echo "* Last upgrade file found -> $MAX";
MAX=$(echo $MAX | sed -e 's/^ *0*//');      # remove leading zeroes

declare -a FILES;
declare -a SKIPPED;
while true; do
    VERSION=$(($VERSION + 1));
    [ $VERSION -gt $MAX ] && break;
    PREFIX=$(printf "%0.4d" $VERSION);
    FILE=$(ls upgrade/$PREFIX* 2>/dev/null);
    if [ -f "$FILE" ] ; then
        # Note: we only report skipped files once we find the next one.  
        # Otherwise, we'd report everything from $VERSION+1 to $MAX
        for skip in ${SKIPPED[@]} ; do
            echo "* WARNING: Upgrade $skip NOT FOUND.  Skipping it."; 
        done
        SKIPPED=();                     # After we reported them, reset array.
        FILES[${#FILES[@]}]=$FILE;      # "push" onto FILES array
        # echo "* Pending $FILE";
    else
        SKIPPED[${#SKIPPED[@]}]=$PREFIX; # "push" onto SKIPPED array
    fi
done;

COUNT=${#FILES[@]};

if [ $COUNT -gt 0 ] ; then
    echo "* $COUNT update scripts to apply."
    exec 3>&1;  # our copy of STDOUT
    for (( i=0; i<$COUNT; i++ )) ; do
        echo "* Applying ${FILES[$i]}" >&3;   # to the main script STDOUT
        cat ${FILES[$i]};                     # to the psql pipe
    done | psql --set=eg_version="'$EGVERSION'" $PSQL_ACCESS ;
else
    echo "* Nothing to update";
fi
