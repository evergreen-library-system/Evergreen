#!/bin/sh
if [ "_$3" == "_" ]; then
	echo "Usage:"
	echo "	$0 {db-user} {Open-ILS-driver} {db-name}"
	exit 1;
fi

PWD=`pwd`
WD=`dirname $0`

(
	echo "cd $PWD/$WD/../../sql/$2/;"
	cd $PWD/$WD/../../sql/$2/;
	pwd
	./build-db-$2.sh $1 $3 $4
)
