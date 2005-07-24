#!/bin/sh
if [ "_$3" == "_" ]; then
	echo "Usage:"
	echo "	$0 {Open-ILS-driver} {db-host} {db-name} {db-user} {db-password}"
	exit 1;
fi

PWD=`pwd`
WD=`dirname $0`

(
	echo "cd $WD/../../sql/$1/;"
	cd $WD/../../sql/$1/;
	pwd
	./build-db.sh $2 $3 $4 $5
)
