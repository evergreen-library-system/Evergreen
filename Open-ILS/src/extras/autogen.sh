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

# ---------------------------------------------------------------------------
# Make sure we're running as the correct user
# ---------------------------------------------------------------------------
[ $(whoami) != 'opensrf' ] && echo 'Must run as user "opensrf"' && exit;

function usage {
	echo "";
	echo "usage: $0 [-u] -c <c_config>";
	echo "";
	echo "Mandatory parameters:";
	echo -e "  -c\t\tfull path to C configuration file (opensrf_core.xml)";
	echo "";
	echo "Optional parameters:";
	echo -e "  -u\t\tupdate proximity of library sites in organization tree";
	echo -e "    \t\t(this is expensive for a large organization tree)";
	echo "";
	echo "Examples:";
	echo "";
	echo "  Update organization tree:";
	echo "    $0 -c SYSCONFDIR/opensrf_core.xml";
	echo "    $0 SYSCONFDIR/opensrf_core.xml";
	echo "";
	echo "  Update organization tree and refresh proximity:";
	echo "    $0 -u -c SYSCONFDIR/opensrf_core.xml";
	echo "";
	exit;
}

(

BASEDIR=${0%/*}
if test "$BASEDIR" = "$0" ; then
	BASEDIR="$(which $0)"
	BASEDIR=${BASEDIR%/*}
fi

cd "$BASEDIR"

CONFIG="$1";

# ---------------------------------------------------------------------------
# Load the command line options and set the global vars
# ---------------------------------------------------------------------------
while getopts  "c:u h" flag; do
	case $flag in	
		"c")		CONFIG="$OPTARG";;
		"u")		PROXIMITY="REFRESH";;
		"h")		usage;;
	esac;
done

[ -z "$CONFIG" ] && usage;

JSDIR="LOCALSTATEDIR/web/opac/common/js/";
FMDOJODIR="LOCALSTATEDIR/web/js/dojo/fieldmapper/";
SLIMPACDIR="LOCALSTATEDIR/web/opac/extras/slimpac/";

echo "Updating fieldmapper";
perl fieldmapper.pl "$CONFIG"	> "$JSDIR/fmall.js";
cp "$JSDIR/fmall.js" "$FMDOJODIR/"

echo "Updating web_fieldmapper";
perl fieldmapper.pl "$CONFIG" "web_core"	> "$JSDIR/fmcore.js";

echo "Updating OrgTree";
perl org_tree_js.pl "$CONFIG" > "$JSDIR/OrgTree.js";

echo "Updating OrgTree HTML";
perl org_tree_html_options.pl "$CONFIG" "$SLIMPACDIR/lib_list.inc";
cp "$JSDIR/OrgTree.js" "$FMDOJODIR/"

echo "Updating Search Groups";
perl org_lasso_js.pl "$CONFIG" > "$JSDIR/OrgLasso.js";
cp "$JSDIR/OrgLasso.js" "$FMDOJODIR/"

if [ "$PROXIMITY" ]
then
	echo "Refreshing proximity of org units";
	perl org_tree_proximity.pl "$CONFIG";
fi

echo "";
echo "Done";

)

