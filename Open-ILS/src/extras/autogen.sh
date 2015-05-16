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
	echo "usage: $0 [-u]";
	echo "";
	echo "Updates the Evergreen organization tree and fieldmapper IDL.";
	echo "Run this every time you change the Evergreen organization tree";
	echo "or update fm_IDL.xml";
	echo "";
	echo "Optional parameters:";
	echo -e "  -u\t\tupdate proximity of library sites in organization tree";
	echo -e "    \t\t(this is expensive for a large organization tree)";
	echo "";
	echo "Examples:";
	echo "";
	echo "  Update organization tree and fieldmapper IDL:";
	echo "    $0";
	echo "";
	echo "  Update organization tree and refresh proximity:";
	echo "    $0 -u";
	echo "";
}

(

cd "BINDIR"

# Initialize our variables
PROXIMITY="";

# ---------------------------------------------------------------------------
# Load the command line options and set the global vars
# ---------------------------------------------------------------------------
while getopts  "u h" flag; do
	case $flag in	
		"u")		PROXIMITY="REFRESH";;
		"h")		usage && exit;;
	esac;
done
shift $((OPTIND - 1))

JSDIR="LOCALSTATEDIR/web/opac/common/js/";
FMDOJODIR="LOCALSTATEDIR/web/js/dojo/fieldmapper/";
SLIMPACDIR="LOCALSTATEDIR/web/opac/extras/slimpac/";
SKINDIR='LOCALSTATEDIR/web/opac/skin';

COMPRESSOR="" # TODO: set via ./configure
#COMPRESSOR="java -jar /opt/yuicompressor-2.4.2/build/yuicompressor-2.4.2.jar"

echo "Updating Evergreen organization tree and IDL"
echo ""

OUTFILE="$JSDIR/fmall.js"
echo "Updating fieldmapper";
perl -MOpenILS::Utils::Configure -e 'print OpenILS::Utils::Configure::fieldmapper();' > "$OUTFILE"
cp "$OUTFILE" "$FMDOJODIR/"
echo " -> $OUTFILE"
OUTFILES="$OUTFILE"

OUTFILE="$JSDIR/fmcore.js"
echo "Updating web_fieldmapper";
perl -MOpenILS::Utils::Configure -e 'print OpenILS::Utils::Configure::fieldmapper("web_core");' > "$OUTFILE"
echo " -> $OUTFILE"
OUTFILES="$OUTFILES $OUTFILE"

OUTFILE="$JSDIR/*/OrgTree.js"
echo "Updating OrgTree";
perl -MOpenILS::Utils::Configure -e "OpenILS::Utils::Configure::org_tree_js('$JSDIR', 'OrgTree.js');"
cp "$JSDIR/en-US/OrgTree.js" "$FMDOJODIR/"
echo " -> $OUTFILE"
OUTFILES="$OUTFILES $OUTFILE"

OUTFILE="$SLIMPACDIR/*/lib_list.inc"
echo "Updating OrgTree HTML";
perl -MOpenILS::Utils::Configure -e "OpenILS::Utils::Configure::org_tree_html_options('$SLIMPACDIR', 'lib_list.inc');"
echo " -> $OUTFILE"
OUTFILES="$OUTFILES $OUTFILE"

OUTFILE="$SLIMPACDIR/locales.inc"
echo "Updating locales selection HTML";
perl -MOpenILS::Utils::Configure -e "print OpenILS::Utils::Configure::locale_html_options();" > "$OUTFILE"
echo " -> $OUTFILE"
OUTFILES="$OUTFILES $OUTFILE"

if [ ! -z "$PROXIMITY" ]
then
	echo "Refreshing proximity of org units";
	perl -MOpenILS::Utils::Configure -e "OpenILS::Utils::Configure::org_tree_proximity();"
fi

# Generate a hash of the generated files
(
	date +%Y%m%d
	for file in `ls -1 $OUTFILES`; do
		if [[ -n $file && -f $file ]]
		then
			md5sum $file
		fi
	done
) | md5sum | cut -f1 -d' ' | cut -b 27-32 > LOCALSTATEDIR/web/eg_cache_hash

echo
echo -n "Current Evergreen cache key: "
cat LOCALSTATEDIR/web/eg_cache_hash

echo "Done";

)
