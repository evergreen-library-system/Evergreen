#!/bin/sh

CONF=$1
FILE=$2
OUT=$3
KEYS=$4

if [ "_$OUT" == "_" ]; then
	echo "Usage: $0 {Config File} {MARC file} {Output File} [{key file}]"
	exit;
fi

DIR=`dirname $0`

$DIR/marc2bre.pl \
		-k $KEYS \
		-c $CONF $FILE 2>/dev/null | \
	$DIR/direct_ingest.pl \
		-c $CONF \
		-t 1 2>/dev/null | \
	$DIR/pg_loader.pl -c $CONF \
		-or bre \
		-or mrd \
		-or mfr \
		-or mtfe \
		-or mafe \
		-or msfe \
		-or mkfe \
		-or msefe \
		-a mrd \
		-a mfr \
		-a mtfe \
		-a mafe \
		-a msfe \
		-a mkfe \
		-a msefe
