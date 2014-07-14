#!/bin/bash

OPT_ACTION=""
OPT_SIP_CONFIG="SYSCONFDIR/oils_sip.xml"
OPT_PID_DIR="LOCALSTATEDIR/run"
OPT_SIP_ERR_LOG="LOCALSTATEDIR/log/oils_sip.log";
OPT_Z3950_CONFIG="SYSCONFDIR/oils_z3950.xml"
OPT_YAZ_CONFIG="SYSCONFDIR/oils_yaz.xml"
Z3950_LOG="LOCALSTATEDIR/log/oils_z3950.log"
SIP_DIR="/opt/SIPServer";

# ---------------------------------------------------------------------------
# Make sure we're running as the correct user
# ---------------------------------------------------------------------------
[ $(whoami) != 'opensrf' ] && echo 'Must run as user "opensrf"' && exit;


function usage {
	echo "";
	echo "usage: $0 -d <pid_dir> -s <sip_config> -z <z3950_config> -y <yaz_config> -a <action> -l <sip_err_log>";
	echo "";
	echo "Actions include:"
	echo -e "\tstart_sip"
	echo -e "\tstop_sip"
	echo -e "\trestart_sip"
	echo -e "\tstart_z3950"
	echo -e "\tstop_z3950"
	echo -e "\trestart_z3950"
	echo -e "\tstart_all"
	echo -e "\tstop_all"
	echo -e "\trestart_all"
	exit;
}


# ---------------------------------------------------------------------------
# Load the command line options and set the global vars
# ---------------------------------------------------------------------------
while getopts "a:d:s:l:y:z:" flag; do
	case $flag in	
		"a")		OPT_ACTION="$OPTARG";;
		"s")		OPT_SIP_CONFIG="$OPTARG";;
		"d")		OPT_PID_DIR="$OPTARG";;
		"l")		OPT_SIP_ERR_LOG="$OPTARG";;
		"z")		OPT_Z3950_CONFIG="$OPTARG";;
		"y")		OPT_YAZ_CONFIG="$OPTARG";;
		"h"|*)	usage;;
	esac;
done


[ -z "$OPT_PID_DIR" ] && OPT_PID_DIR=/tmp;
[ -z "$OPT_ACTION" ] && usage;

PID_SIP="$OPT_PID_DIR/oils_sip.pid";
PID_Z3950="$OPT_PID_DIR/oils_z3950.pid";

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
		kill -s TERM $pid;
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
	perl SIPServer.pm "$OPT_SIP_CONFIG" >> "$OPT_SIP_ERR_LOG" 2>&1 &
	pid=$!;
	cd $DIR;
	echo $pid > $PID_SIP;
	return 0;
}

function stop_sip {
	do_action "stop" $PID_SIP "OILS SIP Server";
	return 0;
}

function start_z3950 {
	do_action "start" $PID_Z3950 "OILS Z39.50 Server";
	simple2zoom -c $OPT_Z3950_CONFIG -- -f $OPT_YAZ_CONFIG >> "$Z3950_LOG" 2>&1 &
	pid=$!;
	echo $pid > $PID_Z3950;
	return 0;
}

function stop_z3950 {
	do_action "stop" $PID_Z3950 "OILS Z39.50 Server";
	return 0;
}


# ---------------------------------------------------------------------------
# Do the requested action
# ---------------------------------------------------------------------------
case $OPT_ACTION in
	"start_sip") start_sip;;
	"stop_sip") stop_sip;;
	"restart_sip") stop_sip; start_sip;;
	"start_z3950") start_z3950;;
	"stop_z3950") stop_z3950;;
	"restart_z3950") stop_z3950; start_z3950;;
	"start_all") start_sip; start_z3950;;
	"stop_all") stop_sip; stop_z3950;;
	"restart_all") stop_sip; stop_z3950; start_sip; start_z3950;;
	*) usage;;
esac;



