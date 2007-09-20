#!/bin/bash
# -------------------------------------------------------------------
#
# XXX This probably only works on Linux for now...
#
# This script is used to manage "bricks", which are collections of
# servers all serving a single OpenSRF domain.  There will be 1
# lead machine, which will typcically run this script, and 1 or more
# drones, which respond to this script.
#
# XXX The fetching and build commands need to be updated to work
# with the now-separated OpenSRF 0.9 and Evergreen 1.2 
# -------------------------------------------------------------------
[ -f /etc/profile ] && . /etc/profile
[ -f ~/.bashrc ] && . ~/.bashrc

DRONE_COUNT=2; # how many drones are in this brick
ETH_DEV="eth0" # ethernet device 
PREFIX="/openils" # the installed ILS files prefix

# this is useful if you are using ldirector.  we can
# "detach" a brick by removing the ldirector ping file
LDIRECTOR_FILE="/$PREFIX/var/web/ldirectorping.txt"

# XXX needs work
SRC_DIR="/home/opensrf/ILS";

STAFF_CLIENT_BUILD_ID="sc_v100_rc2";
XUL_BASE="/$PREFIX/var/web/xul";

IP_PREFIX=$(/sbin/ifconfig | grep -A1 $ETH_DEV | grep inet | cut -d'.' -f1,2,3 | cut -d':' -f2);
IP=$(/sbin/ifconfig | grep -A1 $ETH_DEV | grep inet | cut -d'.' -f 4 | cut -d' ' -f1);
FIRST=$(expr $IP + 1);
LAST=$(expr $IP + $DRONE_COUNT);

OSRF_PID_DIR="/tmp/";
OSRF_CONFIG="/$PREFIX/conf/opensrf_core.xml";
LOCAL_BASE="osrf_ctl.sh -d $OSRF_PID_DIR -c $OSRF_CONFIG";
DRONE_BASE=". /etc/profile && osrf_ctl.sh -d $OSRF_PID_DIR -c $OSRF_CONFIG";


# -------------------------------------------------------------------
# Make sure we're the opensrf user
# -------------------------------------------------------------------
[ $(whoami) != 'opensrf' ] && echo 'Must run as user "opensrf"' && exit;

function usage {
	echo "";	
	echo "usage: $0 -a <action>"
	echo "	-u <base_url> : host + path URL where the download file lives";
	echo "	-f <build_file> : the name of the bundle to fetch";
	echo "	-x <xul_dir> : the destination xul directory";
	echo "Actions:";	
	echo "	fetch";
	echo "	start_perl";
	echo "	start_c";
	echo "	start_perl_c";
	echo "	start_all";
	echo "	stop_perl";
	echo "	stop_c";
	echo "	stop_perl_c";
	echo "	stop_all";
	echo "	restart_perl";
	echo "	restart_c";
	echo "	restart_perl_c";
	echo "	restart_all";
	echo "	build";
	echo "	build_xul";
	echo "	detach_brick";
	echo "	attach_brick";
	exit 0;
}


# -------------------------------------------------------------------
# Load the config opts
# -------------------------------------------------------------------
while getopts  "a:x:bf:hu:" flag; do
	case $flag in	
		"a") OPT_ACTION="$OPTARG";;
		"x") OPT_XUL_DIR="$OPTARG";;
		"u") OPT_FETCH_BASE_URL="$OPTARG";;
		"f") OPT_FETCH_FILE="$OPTARG";;
		"h"|*) usage;;
	esac;
done



[ -z "$OPT_ACTION" ] && usage;


# -------------------------------------------------------------------
# Runs DRONE_ACT on the drones, the LOCAL_ACT on the local machine
# -------------------------------------------------------------------
function drone_first {
	LOCAL_ACT=$1
	DRONE_ACT=$2
	SLEEP=$3;
	echo -e "\ndrone_first() $LOCAL_ACT\n";
	for(( i = $FIRST; i <= $LAST; i++ )) {
		echo -e "\n$IP_PREFIX.$i\n"
		ssh $OPT_SSH_BACKGROUND "$IP_PREFIX.$i" "$DRONE_ACT";
		[ -n "$SLEEP" -a -n "$OPT_SSH_BACKGROUND" ] && sleep $SLEEP;
	}
	$LOCAL_ACT;
}

# -------------------------------------------------------------------
# Runs LOCAL_ACT on the local machine and DRONE_ACT on the drones
# -------------------------------------------------------------------
function local_first {
	LOCAL_ACT=$1
	DRONE_ACT=$2
	SLEEP=$3;
	echo -e "\nlocal_first() $LOCAL_ACT\n";
	$LOCAL_ACT;
	for(( i = $FIRST; i <= $LAST; i++ )) {
		echo -e "\n$IP_PREFIX.$i\n"
		ssh $OPT_SSH_BACKGROUND "$IP_PREFIX.$i" "$DRONE_ACT";
		[ -n "$SLEEP" -a -n "$OPT_SSH_BACKGROUND" ] && sleep $SLEEP;
	}
}

function make_xul {
	[ -z "$OPT_XUL_DIR" ] && echo "Try again with -x to specify xul directory" && exit;
	DIR="$XUL_BASE/$OPT_XUL_DIR";
	echo "Building XUL and copying to $DIR";
	cd "$SRC_DIR/Open-ILS/xul/staff_client" 
	make clean;
	make STAFF_CLIENT_BUILD_ID="$STAFF_CLIENT_BUILD_ID";
	cd /$PREFIX/var/web/xul/
	mkdir -p "$DIR";
	cd "$DIR";
	cp -r "$SRC_DIR/Open-ILS/xul/staff_client/build/server" "$DIR";
	#cp /$PREFIX/var/web/xul/*.jpg "$DIR/server/";
	#cp /$PREFIX/var/web/xul/index.html "$DIR/server/";
	#cd /$PREFIX/var/web/xul/;
	echo -e "\n[pwd=$PWD] Linking to new build directory: $STAFF_CLIENT_BUILD_ID -> $DIR\n";
	rm "$STAFF_CLIENT_BUILD_ID";
	ln -s "$OPT_XUL_DIR" "$STAFF_CLIENT_BUILD_ID";
}

function detach_brick {
	echo -n "Detaching brick...";

	[ ! -f "$LDIRECTOR_FILE" ] && \
		echo "ping file already moved, skipping ..." && return 0;

	mv -f "$LDIRECTOR_FILE" "$LDIRECTOR_FILE.x"
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
		cp "ILS/install.conf" "$NEW_DIR/"
		rm $OPT_FETCH_FILE;
	fi;

	rm ILS;
	ln -s $NEW_DIR ILS
}

case $OPT_ACTION in

	"start_perl_c") local_first "$LOCAL_BASE -a start_perl && $LOCAL_BASE -a start_c" \
		"$DRONE_BASE -a start_perl && $DRONE_BASE -a start_c" 4;;

	"stop_perl_c") drone_first "$LOCAL_BASE -a stop_perl && $LOCAL_BASE -a stop_c" \
		"$DRONE_BASE -a stop_perl && $DRONE_BASE -a stop_c" 2;;

	"restart_perl_c") local_first "$LOCAL_BASE -a restart_perl && $LOCAL_BASE -a restart_c" \
		"$DRONE_BASE -a restart_perl && $DRONE_BASE -a restart_c" 4;;

	"start_perl") local_first "$LOCAL_BASE -a start_perl" "$DRONE_BASE -a start_perl" 4;;
	"stop_perl") drone_first "$LOCAL_BASE -a stop_perl" "$DRONE_BASE -a stop_perl" 2;;
	"restart_perl") local_first "$LOCAL_BASE -a restart_perl" "$DRONE_BASE -a restart_perl" 4;;
	"start_c") local_first "$LOCAL_BASE -a start_c" "$DRONE_BASE -a start_c" 2;;
	"stop_c") drone_first "$LOCAL_BASE -a stop_c" "$DRONE_BASE -a stop_c" 2;;
	"restart_c") local_first "$LOCAL_BASE -a restart_c" "$DRONE_BASE -a restart_c" 2;;

	"start_all") local_first "$LOCAL_BASE -a start_all" \
		"$DRONE_BASE -a start_perl && $DRONE_BASE -a start_c" 4;;

	"stop_all") drone_first "$LOCAL_BASE -a stop_all" \
		"$DRONE_BASE -a stop_perl && $DRONE_BASE -a stop_c" 2;;

	"restart_all") $0 -a stop_all; $0 -a start_all;;
	"build") cd ~/ILS/ && make clean default_config all;;
	"build_xul") make_xul;;
	"detach_brick") detach_brick;;
	"attach_brick") mv "$LDIRECTOR_FILE.x" "$LDIRECTOR_FILE";;
	"fetch") fetch_build;;
esac;


