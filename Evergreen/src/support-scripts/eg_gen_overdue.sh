#!/bin/bash
# ---------------------------------------------------------------
# This file runs the overdue generation script.
# If today is Monday, it runs the script for Sat/Sun/Mon, 
# otherwise it runs once per day.
# ---------------------------------------------------------------


DATE=$(date +%Y-%d-%m);
DAY=$(date +%u);
BSCONFIG="/openils/conf/bootstrap.conf"

[ $(whoami) != "opensrf" ] && echo "Must be run as opensrf" && exit 1;
source /etc/profile;
ARGS="0"

# If today is monday, run for sat/sun/mon
if [ "$DAY" == "1" ]; then ARGS="2 1 0"; fi;

./eg_gen_overdue.pl $BSCONFIG $ARGS > "/tmp/EG_overdue.$DATE.xml"


