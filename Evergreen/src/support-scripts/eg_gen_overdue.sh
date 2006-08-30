#!/bin/bash
# ---------------------------------------------------------------
# This file runs the overdue generation script.
# If today is Monday, it runs the script for Sat/Sun/Mon, 
# otherwise it runs once per day.
# ---------------------------------------------------------------




DATE=$(date +%Y-%m-%d);
DAY=$(date +%u);
BSCONFIG="/openils/conf/bootstrap.conf"
ODDIR="/openils/var/data/overdue";
#ODDIR="/tmp";

export EG_OVERDUE_EMAIL_TEMPLATE="../extras/overdue_notice_email";
export EG_OVERDUE_SMTP_HOST="apollo.georgialibraries.org";
export EG_OVERDUE_EMAIL_SENDER="evergreen@georgialibraries.org";

[ $(whoami) != "opensrf" ] && echo "Must be run as opensrf" && exit 1;
source /etc/profile;
ARGS="0"

[ $DAY == 6 -o $DAY == 7 ] && exit 0; # don't run on saturday or sunday
if [ $DAY == 1 ]; then ARGS="2 1 0"; fi; # If today is monday, run for sat/sun/mon

echo "RUNNING";
./eg_gen_overdue.pl $BSCONFIG $ARGS > "$ODDIR/overdue.$DATE.xml"

