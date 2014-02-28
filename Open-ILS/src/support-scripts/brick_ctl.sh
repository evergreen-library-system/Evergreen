#!/bin/bash
# ---------------------------------------------------------------
# Copyright (C) 2007-2008  Georgia Public Library Service
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.

# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
# ---------------------------------------------------------------

# -------------------------------------------------------------------
# This script is used to manage "bricks", which are collections of
# servers all serving a single OpenSRF domain.  There will be 1
# master machine, which will typcically run this script, and 1 or more
# drones, which respond to this script.
# -------------------------------------------------------------------

# TODO finish the download and build functionality


[ -f /etc/profile ] && . /etc/profile
[ -f ~/.bashrc ] && . ~/.bashrc

DEFAULT_CONFIG=~/.oils_brick.cfg


# -------------------------------------------------------------------
# Make sure we're the opensrf user
# -------------------------------------------------------------------
[ $(whoami) != 'opensrf' ] && echo 'Must run as user "opensrf"' && exit;


function usage {
    echo "";    
    echo "usage: $0 -a <action>"
    echo "  -u <base_url> : host + path URL where the download file lives";
    echo "  -f <build_file> : the name of the bundle to fetch";
    echo "  -x <xul_dir> : staff client build directory";
    echo "  -i <xul_build_id> : staff client build ID";
    echo "  -s <service_name> : apply action only to specified service";
    echo "Actions:";    
    echo "  fetch";
    echo "  start_osrf";
    echo "  start_all";
    echo "  stop_osrf";
    echo "  stop_all";
    echo "  restart_osrf";
    echo "  restart_all";
    echo "  build";
    echo "  build_xul";
    echo "  detach_brick";
    echo "  attach_brick";
    exit 0;
}


# -------------------------------------------------------------------
# Load the config opts
# -------------------------------------------------------------------
while getopts  "a:x:bf:hu:c:i:s:l" flag; do
    case $flag in   
        "a") OPT_ACTION="$OPTARG";;
        "u") OPT_FETCH_BASE_URL="$OPTARG";;
        "f") OPT_FETCH_FILE="$OPTARG";;
        "x") OPT_XUL_BUILD_DIR="$OPTARG";;
        "i") OPT_XUL_BUILD_ID="$OPTARG";;
        "c") OPT_CONFIG_FILE="$OPTARG";;
        "l") OPT_LOCALHOST="-l";;
        "s") OPT_SERVICE="$OPTARG";;
        "h"|*) usage;;
    esac;
done

# -------------------------------------------------------------------
# Load the config file
# -------------------------------------------------------------------
if [ -e "$OPT_CONFIG_FILE" ]; then
    . $OPT_CONFIG_FILE;
else
    if [ -e ~/.oils_brick.cfg ]; then
        . $DEFAULT_CONFIG; 
    else
        echo "Please specify a valid config file or create one at $DEFAULT_CONFIG";
    fi;
fi;

[ -n "$OPT_LOCALHOST" ] && SERVICE_LOCALHOST_FLAG="--localhost";

# make sure an action was specified
[ -z "$OPT_ACTION" ] && usage;

LOCAL_BASE="osrf_control $OPT_LOCALHOST --pid-dir $OSRF_PID_DIR --config $OSRF_CONFIG";
DRONE_BASE=". /etc/profile && osrf_control --pid-dir $OSRF_PID_DIR --config $OSRF_CONFIG";
SERVICE_CONTROLLER="osrf_control $SERVICE_LOCALHOST_FLAG --config $OSRF_CONFIG --pid-dir $OSRF_PID_DIR --service $OPT_SERVICE";

# -------------------------------------------------------------------
# Runs DRONE_ACT on the drones, then LOCAL_ACT on the local machine
# -------------------------------------------------------------------
function drone_first {
    LOCAL_ACT=$1
    DRONE_ACT=$2
    echo "drone_first(): $LOCAL_ACT";
    for drone in ${DRONES[@]:0}; do
        echo "* $drone"
        ssh "$drone" "$DRONE_ACT";
    done;   
    $LOCAL_ACT;
}

# -------------------------------------------------------------------
# Runs LOCAL_ACT on the local machine then DRONE_ACT on the drones
# -------------------------------------------------------------------
function local_first {
    LOCAL_ACT=$1
    DRONE_ACT=$2
    echo  "local_first(): $LOCAL_ACT";
    $LOCAL_ACT;
    for drone in ${DRONES[@]:0}; do
        echo "* $drone"
        ssh "$drone" "$DRONE_ACT";
    done;   
}

function make_xul {
    DIR="$XUL_BASE/$OPT_XUL_BUILD_DIR";
    echo "Building XUL and copying to $DIR";
    cd "$OILS_SRC_DIR/Open-ILS/xul/staff_client" 
    make clean;
    make STAFF_CLIENT_BUILD_ID="$OPT_XUL_BUILD_ID";
    cd "$XUL_BASE";
    mkdir -p "$DIR";
    cd "$DIR/..";
    cp -r "$OILS_SRC_DIR/Open-ILS/xul/staff_client/build/server" "$DIR";
    echo -e "\nLinking to new build directory: $OPT_XUL_BUILD_ID -> $DIR\n";
    rm -f "$OPT_XUL_BUILD_ID";
    rm -f current;
    ln -s "$OPT_XUL_BUILD_DIR" current;
    ln -s current "$OPT_XUL_BUILD_ID";
}

function detach_brick {
    echo -n "Detaching brick...";

    [ ! -f "$LDIRECTOR_FILE" ] && \
        echo "ping file already moved, skipping ..." && return 0;

    mv -f "$LDIRECTOR_FILE" "$LDIRECTOR_FILE-"
    x=10;
    while(sleep 1); do
        x=$(expr $x - 1);
        echo -n " $x ";
        [ $x == 0 ] && break;
    done;
    echo "";
}

function fetch_build {

    [ -z "$OPT_FETCH_BASE_URL" -o -z "$OPT_FETCH_FILE" ] && \
        echo "I need a build URL and a bundle file..." && exit;
    
    NEW_DIR=${OPT_FETCH_FILE:0:$(expr ${#OPT_FETCH_FILE} - 7)};

    if [ ! -d "$NEW_DIR" ]; then
    
        echo "Fetching archive...  $OPT_FETCH_BASE_URL$OPT_FETCH_FILE";
        wget -q "$OPT_FETCH_BASE_URL$OPT_FETCH_FILE";
    
        [ ! -f "$OPT_FETCH_FILE" ] && \
            echo "Unable to fetch $OPT_FETCH_FILE!" && exit;
        
        # unpack the new build
        echo "Unpacking archive..."
        tar -zxf $OPT_FETCH_FILE;
        cp "current/install.conf" "$NEW_DIR/"
        rm $OPT_FETCH_FILE;
    fi;

    rm current;
    ln -s $NEW_DIR current;
}

# This is a per-service action.  Currently only support in Perl (and Python).
# When other active languages are added, this script will need a language param
# to determine which controller script to call.
if [ -n "$OPT_SERVICE" ]; then
    case $OPT_ACTION in
        "start_osrf") local_first "$SERVICE_CONTROLLER --start" \
            "$SERVICE_CONTROLLER --start";;
        "stop_osrf") local_first "$SERVICE_CONTROLLER --stop" \
            "$SERVICE_CONTROLLER --stop";;
        "restart_osrf") local_first "$SERVICE_CONTROLLER --restart" \
            "$SERVICE_CONTROLLER --restart";;
        *) echo "Can only do start_osrf, stop_osrf, or restart_osrf for an individual service";;
    esac;
    exit;
fi;

case $OPT_ACTION in

    "start_osrf") local_first "$LOCAL_BASE --start-services" \
        "$DRONE_BASE --start-services";;

    "stop_osrf") drone_first "$LOCAL_BASE --stop-services" \
        "$DRONE_BASE --stop-services";;

    "restart_osrf") local_first "$LOCAL_BASE --restart-services" \
        "$DRONE_BASE --restart-services";;

    "start_all") local_first "$LOCAL_BASE --start-all" \
        "$DRONE_BASE --start-services";;

    "stop_all") drone_first "$LOCAL_BASE --stop-all" \
        "$DRONE_BASE --stop-services";;

    "restart_all") $0 $OPT_LOCALHOST -a stop_all; $0 $OPT_LOCALHOST -a start_all;;
    "build") cd ~/ILS/ && make clean default_config all;;
    "build_xul") make_xul;;
    "detach_brick") detach_brick;;
    "attach_brick") mv "$LDIRECTOR_FILE-" "$LDIRECTOR_FILE";;
    "fetch") fetch_build;;
esac;


