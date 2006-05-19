#!/bin/bash

# NOTE: Eventually, there will be one OpenSRF config file format
# When this happens, we will only need a single OPT_CONFIG variable
# Also note that PIDs are collect from ps/grep/awk for C commands because
# they fork internally and there's no way to find their PIDs at launch time
# This is hackish and likely non-portable

OPT_ACTION="" 
OPT_PERL_CONFIG=""
OPT_C_CONFIG=""
OPT_PID_DIR=""

function usage {
	echo "usage: $0 -d <pid_dir> -p <perl_config> -c <c_config> -a <action>";
	exit;
}


while getopts  "p:c:a:d:h" flag; do
	case $flag in	
		"a")		OPT_ACTION="$OPTARG";;
		"c")		OPT_C_CONFIG="$OPTARG";;
		"p")		OPT_PERL_CONFIG="$OPTARG";;
		"d")		OPT_PID_DIR="$OPTARG";;
		"h"|*)	usage;;
	esac;
done

[ -z "$OPT_PID_DIR" ] && OPT_PID_DIR=/tmp;
[ -z "$OPT_ACTION" ] && usage;


PID_ROUTER="$OPT_PID_DIR/router.pid";
PID_OSRF_PERL="$OPT_PID_DIR/osrf_perl.pid";
PID_OSRF_C="$OPT_PID_DIR/osrf_c.pid";


# ---------------------------------------------------------------------------
# Start / Stop functions
# ---------------------------------------------------------------------------
function start_router {
	if [ -e "$PID_ROUTER" ]; then
		pid=$(cat "$PID_ROUTER");
		echo "Router is already running : $pid" && return 0;
	fi;
	echo "Starting router...";
	opensrf_router $OPT_C_CONFIG router
	pid=$(ps ax | grep "OpenSRF Router" | grep -v grep | awk '{print $1}')
	echo $pid > $PID_ROUTER;
	return 0;
}

function stop_router {
	[ ! -e "$PID_ROUTER" ] && echo "Router is not running" && return 0;
	pid=$(cat "$PID_ROUTER");
	echo "Stopping router : $pid";
	kill -s INT $pid;
	rm "$PID_ROUTER";
	return 0;
}

function start_perl {
	if [ -e "$PID_OSRF_PERL" ]; then
		pid=$(cat "$PID_OSRF_PERL");
		echo "OpenSRF perl is already running : $pid" && return 0;
	fi;
	perl -MOpenSRF::System="$OPT_PERL_CONFIG" -e 'OpenSRF::System->bootstrap()' & 
	pid=$!;
	echo $pid > $PID_OSRF_PERL;
	return 0;
}

function stop_perl {
	[ ! -e "$PID_OSRF_PERL" ] && echo "OpenSRF-Perl is not running" && return 0;
	pid=$(cat "$PID_OSRF_PERL");
	echo "Stopping perl : $pid";
	kill -s INT $pid;
	rm "$PID_OSRF_PERL";
	return 0;
}

function start_c {
	if [ -e "$PID_OSRF_C" ]; then
		pid=$(cat "$PID_OSRF_C");
		echo "OpenSRF-C is already running : $pid" && return 0;
	fi;
	echo "Starting OpenSRF C";
	opensrf-c $(hostname -f) $OPT_C_CONFIG opensrf;
	pid=$(ps ax | grep "OpenSRF System-C" | grep -v grep | awk '{print $1}')
	echo $pid > "$PID_OSRF_C";
	return 0;
}

function stop_c {
	[ ! -e "$PID_OSRF_C" ] && echo "OpenSRF-C is not running" && return 0;
	pid=$(cat "$PID_OSRF_C");
	echo "Stopping OpenSRF C : $pid";
	#kill -9 $pid;
	killall -9 opensrf-c  # hack for now
	rm $PID_OSRF_C;
	return 0;
}



# ---------------------------------------------------------------------------
# Do the requested action
# ---------------------------------------------------------------------------
case $OPT_ACTION in
	"start_router") start_router;;
	"stop_router") stop_router;;
	"start_perl") start_perl;;
	"stop_perl") stop_perl;;
	"restart_perl") stop_perl && sleep 1 && start_perl;;
	"start_c") start_c;;
	"stop_c") stop_c;;
	"restart_c") stop_c && sleep 1 && start_c;;
	"start_osrf") start_perl && sleep 5 && start_c;;
	"stop_osrf") stop_perl; stop_c;;
	"restart_osrf") stop_perl; stop_c; start_perl; start_c;;
	"stop_all") stop_c; stop_perl; stop_router;;
	"start_all") start_router; start_perl && sleep 5 && start_c;;
	"restart_all") stop_c; stop_perl; stop_router; start_router; start_perl && sleep 5 && start_c;;
	*) usage;;
esac;



