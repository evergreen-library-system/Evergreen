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

JSDIR="LOCALSTATEDIR/web/opac/common/js"
FMDOJODIR="LOCALSTATEDIR/web/js/dojo/fieldmapper"
COVERDIR="LOCALSTATEDIR/web/opac/extras/ac/jacket"

# ---------------------------------------------------------------------------
# Make sure we're not root and are able to write to the destination directory
# ---------------------------------------------------------------------------
[ `id -u` -eq 0 ] && echo 'Not to be run as root' && exit 1

function usage {
    echo ""
    echo "usage: $0 [-u]"
    echo ""
    echo "Updates the Evergreen organization tree and fieldmapper IDL."
    echo "Run this every time you change the Evergreen organization tree"
    echo "or update fm_IDL.xml"
    echo ""
    echo "Optional parameters:"
    echo -e "  -u\t\tupdate proximity of library sites in organization tree"
    echo -e "    \t\t(this is expensive for a large organization tree)"
    echo ""
    echo "Examples:"
    echo ""
    echo "  Update organization tree and fieldmapper IDL:"
    echo "    $0"
    echo ""
    echo "  Update organization tree and refresh proximity:"
    echo "    $0 -u"
    echo ""
}

function check_dir_writable {
    if [ ! -d "$1" ] || [ ! -w "$1" ]; then
        echo "Unable to write to ${1}, please check"
        OHNO=1
    fi
}

function check_files_writable {
    # Since we already know the directories are writable there's only
    # a problem if the file(s) already exist *and* for some reason isn't writable.

    # This may be passed a single filename or a glob for simplicity.
    for F in `ls $1 2>/dev/null`
    do
          if [ -f "$F" ] && [ ! -w "$F" ]; then
              echo "Unable to write to ${F}, please check"
              OHNO=1
          fi
    done
}

OHNO=0

# Verify we're able to write everywhere we need
for DIR in "$JSDIR" "$FMDOJODIR"
do
    check_dir_writable "$DIR"
done

# Verify we have cover image directories, creating where needed
for DIR in "small/r" "medium/r" "large/r"
do
    if [ ! -d "$COVERDIR/$DIR" ]; then
        mkdir -p "$COVERDIR/$DIR"
    fi
    check_dir_writable "$COVERDIR/$DIR"
done

for FILE in "$JSDIR/fmall.js" "$JSDIR/fmcore.js" "$JSDIR/*/OrgTree.js" "LOCALSTATEDIR/web/eg_cache_hash"
do
    check_files_writable "$FILE"
done

# Bail on badness
[ $OHNO -eq 0 ] || exit 1

(

cd "BINDIR"

# Initialize our variables
PROXIMITY=""
OSRF_CORE="SYSCONFDIR/opensrf_core.xml"

# ---------------------------------------------------------------------------
# Load the command line options and set the global vars
# ---------------------------------------------------------------------------
while getopts  "c:uh" flag; do
    case $flag in    
        "c")        OSRF_CORE="$OPTARG";;
        "u")        PROXIMITY="REFRESH";;
        "h")        usage && exit;;
    esac
done
shift $((OPTIND - 1))

echo "Updating Evergreen organization tree and IDL"
echo ""

OUTFILE="$JSDIR/fmall.js"
echo "Updating fieldmapper"
perl -MOpenILS::Utils::Configure -e 'print OpenILS::Utils::Configure::fieldmapper();' -- --osrf-config "$OSRF_CORE" > "$OUTFILE"
cp "$OUTFILE" "$FMDOJODIR/"
echo " -> $OUTFILE"
OUTFILES="$OUTFILE"

OUTFILE="$JSDIR/fmcore.js"
echo "Updating web_fieldmapper"
perl -MOpenILS::Utils::Configure -e 'print OpenILS::Utils::Configure::fieldmapper("web_core");' -- --osrf-config "$OSRF_CORE" > "$OUTFILE"
echo " -> $OUTFILE"
OUTFILES="$OUTFILES $OUTFILE"

OUTFILE="$JSDIR/*/OrgTree.js"
echo "Updating OrgTree"
perl -MOpenILS::Utils::Configure -e "OpenILS::Utils::Configure::org_tree_js('$JSDIR', 'OrgTree.js');" -- --osrf-config "$OSRF_CORE"
cp "$JSDIR/en-US/OrgTree.js" "$FMDOJODIR/"
echo " -> $OUTFILE"
OUTFILES="$OUTFILES $OUTFILE"

if [ ! -z "$PROXIMITY" ]
then
    echo "Refreshing proximity of org units"
    perl -MOpenILS::Utils::Configure -e "OpenILS::Utils::Configure::org_tree_proximity();" -- --osrf-config "$OSRF_CORE"
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

echo "Done"

)
