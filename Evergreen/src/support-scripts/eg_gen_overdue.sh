#!/bin/bash
# ---------------------------------------------------------------
# This file runs the overdue generation script.
# If today is Monday, it runs the script for Sat/Sun/Mon, 
# otherwise it runs once per day.
# ---------------------------------------------------------------


DATE=$(date +%Y-%m-%d);
DAY=$(date +%u);
BSCONFIG="/openils/conf/bootstrap.conf"

[ $(whoami) != "opensrf" ] && echo "Must be run as opensrf" && exit 1;
source /etc/profile;
ARGS="0"

[ $DAY == 6 -o $DAY == 7 ] && exit 0; # don't run on saturday or sunday
if [ $DAY == 1 ]; then ARGS="2 1 0"; fi; # If today is monday, run for sat/sun/mon

./eg_gen_overdue.pl $BSCONFIG $ARGS > "/openils/var/web/tmp/overdue/EG_overdue.$DATE.xml"


