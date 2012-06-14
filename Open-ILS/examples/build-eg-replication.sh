#!/bin/bash
#
# Copyright (C) 2009 Equinox Software, Inc.
# Author: Mike Rylander <miker@esilibrary.com>
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#

#
# This script will help build the slonik scripts required to start
# replicating an Evergreen database using Slony-I.
#
# See: slony-1.2.16/tools/configure-replication.txt
#  for more information on the process
#
# See: slony1-1.2.16/doc/adminguide/firstdb.html
#  for an example of how to get the schema copied
#

if [ "_$NUMNODES" == "_" ]; then
  echo 'Please set the NUMNODES environment variable to the number of new nodes to be created in the new cluster'
  exit
fi

if [ "_$CLUSTER" == "_" ]; then
  echo 'Please set the CLUSTER environment variable to the new cluster name'
  exit
fi

if [ "_$PGDATABASE" == "_" ]; then
  echo 'Please set the PGDATABASE environment variable to the database name'
  exit
fi

if [ "_$PGPORT" == "_" ]; then
  echo 'Please set the PGPORT environment variable to the database port'
  exit
fi

if [ "_$PGUSER" == "_" ]; then
  echo 'Please set the PGPORT environment variable to the database superuser'
  exit
fi

if [ "_$TABLES" == "_" ]; then
  TABLES=$(psql -tc "
    select array_to_string(array_agg(table_schema || '.' || table_name),' ')
      from information_schema.tables
      where table_schema in (
        'acq', 'action', 'action_trigger', 'actor', 'asset', 'asset_hist', 'auditor',
        'authority', 'biblio', 'booking', 'circ_stats', 'config', 'container',
        'extend_reporter', 'metabib', 'money', 'offline', 'permission', 'query',
        'reporter', 'search', 'serial', 'staging', 'stats', 'vandelay'
      ) and table_type = 'BASE TABLE' order by 1;
  ")
  TABLES="$TABLES pg_ts_cfg pg_ts_cfgmap"
fi

if [ "_$SEQUENCES" == "_" ]; then
  SEQUENCES=$(psql -tc "select array_to_string(array_agg(schemaname || '.' || relname),' ') from pg_statio_user_sequences;")
fi


if [ "_$1" == "_" ]; then
  echo 'Please specify at least one host!'
  exit
fi

DB1=$PGDATABASE
USER1=$PGUSER
PORT1=$PGPORT
HOST1=$1

if [ "_$2" != "_" ]; then
  DB2=$PGDATABASE
  USER2=$PGUSER
  PORT2=$PGPORT
  HOST2=$2
fi

if [ "_$3" != "_" ]; then
  DB3=$PGDATABASE
  USER3=$PGUSER
  PORT3=$PGPORT
  HOST3=$3
fi

if [ "_$4" != "_" ]; then
  DB4=$PGDATABASE
  USER4=$PGUSER
  PORT4=$PGPORT
  HOST4=$4
fi

if [ "_$5" != "_" ]; then
  DB5=$PGDATABASE
  USER5=$PGUSER
  PORT5=$PGPORT
  HOST5=$5
fi

./configure-replication.sh

