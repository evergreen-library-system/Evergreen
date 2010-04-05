#!/bin/bash
#
# Author: Joe Atzberger, Equinox Software, Inc.
# License: GPL v2 or greater.
# 
# Based on initial version by Bill Erickson.

function svn_or_git {
    echo -en "###########\nUpdating source directory:" `pwd` "\n";
    if [ -d "./.git" ]; then
        if [ -d "./.git/svn/trunk" ]; then
            git svn fetch;
            # git svn rebase origin || die_msg "git svn rebase origin failed";
        else
            git fetch;
            # git rebase origin || die_msg "git rebase origin failed";
        fi
    else
        echo "Remember to run svn update as needed";
        # svn update || die_msg "svn update failed";
    fi
}

function feedback {
cat <<END_OF_FEEDBACK
Running with options:
    CLEAN = ${OPT_CLEAN:-no}
     FULL = ${OPT_FULL:-no}
  VERBOSE = ${OPT_VERBOSE:-no}

Using Directories --
  OpenSRF repo   : ${OSRF:-Missing}
  OpenILS repo   : ${ILS:-Missing}
  OpenILS install: ${INSTALL:-Missing}
      XUL install: ${XUL:-Missing}

END_OF_FEEDBACK
}

function usage {
    cat <<END_OF_USAGE
usage: $0 [-e /eg_trunk] [-i /openils_dir] [-s /srf_trunk] [-[cfbvt]]

PARAMETERS:
   -e  specify Evergreen (OpenILS) source repository (default pwd)
   -i  specify Evergreen installed directory (default /openils)
   -s  specify OpenSRF source repository (default ~/OpenSRF/trunk)

All parameters are optional, but you will probably need to use -e and -i.

OPTIONS:
   -c  clean: run make clean before make
   -f  full: make both packages, do OpenSRF make install (usually not required)
   -t  test: gives feedback but does not run anything
   -v  verbose

The purpose of this script is to consolidate a lot of the annoying
and error-prone tasks associated with an upgrade for a developer.

Considerations:
 * Run as opensrf.  
 * opensrf needs sudo 
 * Assumes opensrf has a configured (as in ./configure) both ILS and 
   OpenSRF as svn or git-svn checkouts
END_OF_USAGE
}

function die_msg {
    echo -e "ERROR: ${1:-Unknown}\n" >&2;
    usage;
    exit 1;
}

# ----------------------------------
# Prespond to command-line options
# ----------------------------------
while getopts  "cfhtvb:e:i:s:" flag; do
    case $flag in   
        "b") OPT_BASEDIR="$OPTARG";;    # HIDDEN (undocumented) option.
        "e") OPT_EGDIR="$OPTARG"  ;;
        "i") OPT_INSTALL="$OPTARG";;
        "s") OPT_OSRFDIR="$OPTARG";;
        "c") OPT_CLEAN=1  ;;
        "f") OPT_FULL=1   ;;
        "t") OPT_TEST=1   ;;
        "v") OPT_VERBOSE=1;;
        "h"|*) usage && exit;;
    esac;
done

# ----------------------------------
# DEFAULTS (w/ optional overrides)
# ----------------------------------
INSTALL=${OPT_INSTALL:-/openils};
BASE=~      # default to $HOME (~ doesn't like :- syntax for whatever reason)
[ -z "$OPT_BASEDIR" ] || BASE="$OPT_BASEDIR";

OSRF=${OPT_OSRFDIR:-$BASE/OpenSRF/trunk};
ILS=${OPT_EGDIR:-$(pwd)};
XUL="$INSTALL/var/web/xul";

# ----------------------------------
# TEST and SANITY CHECK
# ----------------------------------
[ ! -d "$ILS"     ]   && die_msg "Evergreen Source Directory '$ILS' does not exist!";
[ ! -d "$INSTALL" ]   && die_msg "Evergreen Install Directory '$INSTALL' does not exist!";
[ ! -d "$XUL"     ]   && die_msg "Evergreen XUL Client Directory '$XUL' does not exist!";
[ ! -d "$OSRF"    ]   && die_msg "OpenSRF Source Directory '$OSRF' does not exist!";
which sudo >/dev/null || die_msg "sudo not installed (or in PATH)";

[ -d "${ILS}/.svn" ] || [ -d "${ILS}/.git" ] || [ -d ${ILS}/.bzr ] || die_msg "Evergreen Source Directory '$ILS' is not a SVN, bzr or git repo";

if [ ! -z "$OPT_TEST" ] ; then
    feedback;
    exit;
fi

# ----------------------------------
# MAIN
# ----------------------------------
if [ -n "$OPT_FULL"  ]; then
    echo; echo; echo '*** Performing FULL installation ***' ; echo; echo;
fi
if [ -z "$OPT_VERBOSE" ] ; then
    echo "Running with some make output suppressed.  To see all output, run $0 with -v (verbose)";
    echo "This may take a few minutes... ";
    exec 3>&1          # Save current STDOUT to FD3
    exec 1>/dev/null   # redirect (not close) STDOUT
else
    feedback;
    echo -e "Password prompts are triggered by sudo (as this user)\nStopping Apache.";
    set -x;     # echo commands to screen
fi

sudo /etc/init.d/apache2 stop;
$INSTALL/bin/osrf_ctl.sh -l -a stop_all;

# OpenSRF perl directory is not shared.  update the drone
# ssh 10.5.0.202 "./update_osrf_perl.sh";

cd $OSRF; svn_or_git;
cd $ILS;  svn_or_git;

if [ -n "$OPT_CLEAN" ]; then
    cd $OSRF && make clean;
    cd $ILS  && make clean;
fi

if [ -n "$OPT_FULL"  ]; then
    cd $OSRF && make;
    cd $ILS  && make;
    cd $OSRF && sudo make install;
fi
sudo chown -R opensrf:opensrf $INSTALL

BID=$(date +"%Y-%m-%dT%H:%M:%S");   # or "current"
cd $ILS && sudo make install STAFF_CLIENT_BUILD_ID=$BID;
sudo chown -R opensrf:opensrf $INSTALL

[ -d "$XUL/$BID" ] || die_msg "New build directory $XUL/$BID was not created.  sudo make install failed?"

if [ -z "$OPT_VERBOSE" ] ; then
    exec 1>&3   # Restore STDOUT
fi

cd $XUL || die_msg "Could not cd to $XUL";
pwd;
rm -f $XUL/current-client-build.zip;
cp -r "$ILS/Open-ILS/xul/staff_client/build" ./
zip -rq current-client-build.zip build;
cat ./build/BUILD_ID
rm -rf ./build;


rm -f current;      # removing the link to the old build
ln -s $BID current; # linking "current" to the new build
ln -s current/server server;
    

sudo chown -R opensrf:opensrf $OSRF $ILS
$INSTALL/bin/osrf_ctl.sh -l -a start_all
sleep 2;
cd $INSTALL/bin; ./autogen.sh ../conf/opensrf_core.xml;
sudo /etc/init.d/apache2 start;

