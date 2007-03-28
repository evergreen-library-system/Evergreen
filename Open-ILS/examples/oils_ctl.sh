#!/bin/bash

OPT_ACTION=""
OPT_SIP_CONFIG=""
OPT_PID_DIR=""
SIP_DIR="/opt/SIPServer";

# ---------------------------------------------------------------------------
# Make sure we're running as the correct user
# ---------------------------------------------------------------------------
[ $(whoami) != 'opensrf' ] && echo 'Must run as user "opensrf"' && exit;


function usage {
	echo "";
	echo "usage: $0 -d <pid_dir> -s <sip_config> -a <action>";
	echo "";
	echo "Actions include:"
	echo -e "\tstart_sip"
	echo -e "\tstop_sip"
	echo -e "\trestart_sip"
	echo "";
	exit;
}


# ---------------------------------------------------------------------------
# Load the command line options and set the global vars
# ---------------------------------------------------------------------------
while getopts  "a:d:s:" flag; do
	case $flag in	
		"a")		OPT_ACTION="$OPTARG";;
		"s")		OPT_SIP_CONFIG="$OPTARG";;
		"d")		OPT_PID_DIR="$OPTARG";;
		"h"|*)	usage;;
	esac;
done


[ -z "$OPT_PID_DIR" ] && OPT_PID_DIR=/tmp;
[ -z "$OPT_ACTION" ] && usage;

PID_SIP="$OPT_PID_DIR/oils_sip.pid";


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


function start_sip {
	do_action "start" $PID_SIP "OILS SIP Server";
	DIR=$(pwd);
	cd $SIP_DIR;
    perl SIPServer.pm "$OPT_SIP_CONFIG" > /dev/null 2>&1 &
	pid=$!;
	cd $DIR;
	ps ax | grep "$pid";
	echo $pid > $PID_SIP;
	return 0;
}

function stop_sip {
	do_action "stop" $PID_SIP "OILS SIP Server";
	return 0;
}



# ---------------------------------------------------------------------------
# Do the requested action
# ---------------------------------------------------------------------------
case $OPT_ACTION in
	"start_sip") start_sip;;
	"stop_sip") stop_sip;;
	"restart_sip") stop_sip; start_sip;;
	*) usage;;
esac;



