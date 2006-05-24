#!/bin/bash

OPT_ACTION=""
OPT_PERL_CONFIG=""
OPT_C_CONFIG=""
OPT_PID_DIR=""

# ---------------------------------------------------------------------------
# Make sure we're running as the correct user
# ---------------------------------------------------------------------------
[ $(whoami) != 'opensrf' ] && echo 'Must run as user "opensrf"' && exit;


# NOTE: Eventually, there will be one OpenSRF config file format
# When this happens, we will only need a single OPT_CONFIG variable

function usage {
	echo "";
	echo "usage: $0 -d <pid_dir> -p <perl_config> -c <c_config> -a <action>";
	echo "";
	echo "Actions include:"
	echo -e "\tstart_router"
	echo -e "\tstop_router"
	echo -e "\trestart_router"
	echo -e "\tstart_perl"
	echo -e "\tstop_perl"
	echo -e "\trestart_perl"
	echo -e "\tstart_c"
	echo -e "\tstop_c"
	echo -e "\trestart_c"
	echo -e "\tstart_osrf"
	echo -e "\tstop_osrf"
	echo -e "\trestart_osrf"
	echo -e "\tstop_all" 
	echo -e "\tstart_all"
	echo -e "\trestart_all"
	echo "";
	exit;
}


# ---------------------------------------------------------------------------
# Load the command line options and set the global vars
# ---------------------------------------------------------------------------
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
# Utility code for checking the PID files
# ---------------------------------------------------------------------------
function do_action {

	action="$1"; 
	pidfile="$2";
	item="$3"; 

	if [ $action == "start" ]; then

		if [ -e $pidfile ]; then
			pid=$(cat $pidfile);
			echo "$item already started : $pid";
			return 0;
		fi;
		echo "Starting $item";
	fi;

	if [ $action == "stop" ]; then

		if [ ! -e $pidfile ]; then
			echo "$item not running";
			return 0;
		fi;

		pid=$(cat $pidfile);
		echo "Stopping $item : $pid";
		kill -s INT $pid;
		rm -f $pidfile;

	fi;

	return 0;
}


# ---------------------------------------------------------------------------
# Start / Stop functions
# ---------------------------------------------------------------------------


function start_router {
	do_action "start" $PID_ROUTER "OpenSRF Router";
	opensrf_router $OPT_C_CONFIG router
	pid=$(ps ax | grep "OpenSRF Router" | grep -v grep | awk '{print $1}')
	echo $pid > $PID_ROUTER;
	return 0;
}

function stop_router {
	do_action "stop" $PID_ROUTER "OpenSRF Router";
	return 0;
}

function start_perl {
	do_action "start" $PID_OSRF_PERL "OpenSRF Perl";
	perl -MOpenSRF::System="$OPT_PERL_CONFIG" -e 'OpenSRF::System->bootstrap()' & 
	pid=$!;
	echo $pid > $PID_OSRF_PERL;
	sleep 5;
	return 0;
}

function stop_perl {
	do_action "stop" $PID_OSRF_PERL "OpenSRF Perl";
	sleep 1;
	return 0;
}

function start_c {
	do_action "start" $PID_OSRF_C "OpenSRF C";
	opensrf-c $(hostname -f) $OPT_C_CONFIG opensrf;
	pid=$(ps ax | grep "OpenSRF System-C" | grep -v grep | awk '{print $1}')
	echo $pid > "$PID_OSRF_C";
	return 0;
}

function stop_c {
	do_action "stop" $PID_OSRF_C "OpenSRF C";
	killall -9 opensrf-c  # hack for now to force kill all C services
	sleep 1;
	return 0;
}



# ---------------------------------------------------------------------------
# Do the requested action
# ---------------------------------------------------------------------------
case $OPT_ACTION in
	"start_router") start_router;;
	"stop_router") stop_router;;
	"restart_router") stop_router; start_router;;
	"start_perl") start_perl;;
	"stop_perl") stop_perl;;
	"restart_perl") stop_perl; start_perl;;
	"start_c") start_c;;
	"stop_c") stop_c;;
	"restart_c") stop_c; start_c;;
	"start_osrf") start_perl; start_c;;
	"stop_osrf") stop_perl; stop_c;;
	"restart_osrf") stop_perl; stop_c; start_perl; start_c;;
	"stop_all") stop_c; stop_perl; stop_router;;
	"start_all") start_router; start_perl; start_c;;
	"restart_all") stop_c; stop_perl; stop_router; start_router; start_perl; start_c;;
	*) usage;;
esac;



