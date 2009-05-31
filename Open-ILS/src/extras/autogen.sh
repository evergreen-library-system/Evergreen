#!/bin/bash
# -----------------------------------------------------------------------
# Copyright (C) 2005-2008  Georgia Public Library Service
# Bill Erickson <billserickson@gmail.com>
# 
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
# 
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
# -----------------------------------------------------------------------

# vim:noet:ts=4

# Exit script if any statement returns a non-true return value
set -e
# Throw an error for uninitialized variables
set -u

# ---------------------------------------------------------------------------
# Make sure we're running as the correct user
# ---------------------------------------------------------------------------
[ $(whoami) != 'opensrf' ] && echo 'Must run as user "opensrf"' && exit;

function usage {
	echo "";
	echo "usage: $0 [-u] [-c <c_config>]";
	echo "";
	echo "Updates the Evergreen organization tree and fieldmapper IDL.";
	echo "Run this every time you change the Evergreen organization tree";
	echo "or update fm_IDL.xml";
	echo "";
	echo "Optional parameters:";
	echo -e "  -c\t\tfull path to C configuration file (opensrf_core.xml)";
	echo -e "    \t\t - defaults to SYSCONFDIR/opensrf_core.xml";
	echo -e "  -u\t\tupdate proximity of library sites in organization tree";
	echo -e "    \t\t(this is expensive for a large organization tree)";
	echo "";
	echo "Examples:";
	echo "";
	echo "  Update organization tree and fieldmapper IDL:";
	echo "    $0 -c SYSCONFDIR/opensrf_core.xml";
	echo "";
	echo "  Update organization tree and refresh proximity:";
	echo "    $0 -u -c SYSCONFDIR/opensrf_core.xml";
	echo "";
}

(

cd "BINDIR"

# Initialize our variables
CONFIG="";
PROXIMITY="";

# ---------------------------------------------------------------------------
# Load the command line options and set the global vars
# ---------------------------------------------------------------------------
while getopts  "c:u h" flag; do
	case $flag in	
		"c")		CONFIG="$OPTARG";;
		"u")		PROXIMITY="REFRESH";;
		"h")		usage && exit;;
	esac;
	shift $((OPTIND - 1))
done

if [ -z "$CONFIG" ] && [[ ! -z "${1:-}" ]]; then
	# Support "autogen.sh /path/to/opensrf_core.xml" for legacy invocation
	CONFIG="$1";
fi
if [ -z "$CONFIG" ]; then
	# Fall back to the configured default
	CONFIG="SYSCONFDIR/opensrf_core.xml";
fi
if [ ! -f "$CONFIG" ]; then
	echo "ERROR: could not find configuration file '$CONFIG'";
	echo "";
	usage;
	exit 1;
fi;

JSDIR="LOCALSTATEDIR/web/opac/common/js/";
FMDOJODIR="LOCALSTATEDIR/web/js/dojo/fieldmapper/";
SLIMPACDIR="LOCALSTATEDIR/web/opac/extras/slimpac/";

echo "Updating Evergreen organization tree and IDL using '$CONFIG'"
echo ""

echo "Updating fieldmapper";
perl fieldmapper.pl "$CONFIG"	> "$JSDIR/fmall.js";
cp "$JSDIR/fmall.js" "$FMDOJODIR/"

echo "Updating web_fieldmapper";
perl fieldmapper.pl "$CONFIG" "web_core"	> "$JSDIR/fmcore.js";

echo "Updating OrgTree";
perl org_tree_js.pl "$CONFIG" "$JSDIR" "OrgTree.js";
cp "$JSDIR/en-US/OrgTree.js" "$FMDOJODIR/"

echo "Updating OrgTree HTML";
perl org_tree_html_options.pl "$CONFIG" "$SLIMPACDIR" "lib_list.inc";

echo "Updating locales selection HTML";
perl locale_html_options.pl "$CONFIG" "$SLIMPACDIR/locales.inc";

echo "Updating Search Groups";
perl org_lasso_js.pl "$CONFIG" > "$JSDIR/OrgLasso.js";
cp "$JSDIR/OrgLasso.js" "$FMDOJODIR/"

if [ ! -z "$PROXIMITY" ]
then
	echo "Refreshing proximity of org units";
	perl org_tree_proximity.pl "$CONFIG";
fi

echo "";
echo "Done";

)

