#!/bin/bash

# ***** BEGIN LICENSE BLOCK *****
# Version: MPL 1.1/GPL 2.0/LGPL 2.1
#
# The contents of this file are subject to the Mozilla Public License Version
# 1.1 (the "License"); you may not use this file except in compliance with
# the License. You may obtain a copy of the License at
# http://www.mozilla.org/MPL/
#
# Software distributed under the License is distributed on an "AS IS" basis,
# WITHOUT WARRANTY OF ANY KIND, either express or implied. See the License
# for the specific language governing rights and limitations under the
# License.
#
# The Original Code is Mozilla Update Packaging.
#
# The Initial Developer of the Original Code is
# Merrimack Valley Library Consortium.
# Portions created by the Initial Developer are Copyright (C) 2010
# the Initial Developer. All Rights Reserved.
#
# Contributor(s):
#  Thomas Berezansky <tsbere@mvlc.org>
#
# Alternatively, the contents of this file may be used under the terms of
# either the GNU General Public License Version 2 or later (the "GPL"), or
# the GNU Lesser General Public License Version 2.1 or later (the "LGPL"),
# in which case the provisions of the GPL or the LGPL are applicable instead
# of those above. If you wish to allow use of your version of this file only
# under the terms of either the GPL or the LGPL, and not to allow others to
# use your version of this file under the terms of the MPL, indicate your
# decision by deleting the provisions above and replace them with the notice
# and other provisions required by the GPL or the LGPL. If you do not delete
# the provisions above, a recipient may use your version of this file under
# the terms of any one of the MPL, the GPL or the LGPL.
#
# ***** END LICENSE BLOCK *****

# Portions of this code were based on code by Darin Fisher found here:
# http://mxr.mozilla.org/mozilla/source/tools/update-packaging/

prefix=${1:-/openils/var/updates}
BZIP2=${BZIP2:-bzip2}

GEN_UPDATES=0
WIN_UPDATES=0
LINUX32_UPDATES=0
LINUX64_UPDATES=0
EXT_UPDATES=0
CLIENTS=0
case "$2" in
	generic-updates*)
	echo "Building Generic Updates only"
	GEN_UPDATES=1
	;;
	win-updates*)
	echo "Building Windows Updates only"
	WIN_UPDATES=1
	;;
	linux32-updates*)
	echo "Building Linux (32 bit) Updates only"
	LINUX32_UPDATES=1
	;;
	linux64-updates*)
	echo "Building Linux (64 bit) Updates only"
	LINUX32_UPDATES=1
	;;
	extension-updates*)
	echo "Building Extension Updates only"
	EXT_UPDATES=1
	;;
	*)
	echo "Building All Updates"
	GEN_UPDATES=1
	WIN_UPDATES=1
	LINUX32_UPDATES=1
	LINUX64_UPDATES=1
	EXT_UPDATES=1
	;;
esac
case "$2" in
	extension-updates*)
	echo "Extension only - No client"
	;;
	*-client)
	echo "Building Client(s)"
	CLIENTS=1
	;;
	*)
	echo "Not Building Client(s)"
	;;
esac

function unwrap_update
{
	SOURCE="$1"
	DEST="$2"
	$MAR -C "$2" -x "$1"
	find "$2" -type f -exec mv {} {}.bz2 \;
	find "$2" -type f -name '*.bz2' -exec $BZIP2 -d {} \;
}

function prep_update
{
	NEW="$1"
	OLD="$2"
	WORK="$3"
	MANIFEST="$WORK/update.manifest"
	ARCHIVEFILES="update.manifest"
	rm -rf "$WORK"
	mkdir -p "$WORK"
	rm -f "$MANIFEST"
	for FILE in `find "$NEW" -type f`; do
		check_file $FILE
	done
	for FILE in `find "$OLD" -type f`; do
		remove_file $FILE
	done
	$BZIP2 -z9 "$MANIFEST"
	mv "$MANIFEST.bz2" "$MANIFEST"
	rm -rf "$OLD"
}

function check_file
{
	CHECK_FILE="${1#$NEW/}"
	if [ $CHECK_FILE == "update.manifest" -o $CHECK_FILE == "defaults/preferences/developers.js" -o $CHECK_FILE == "defaults/preferences/aa_per_machine.js" ]; then
        echo "Skipping $CHECK_FILE";
		return;
	fi
	DIR=$(dirname "$WORK/$CHECK_FILE")
	if [ ! -f "$OLD/$CHECK_FILE" ]; then
		echo "add \"$CHECK_FILE\"" >> "$MANIFEST"
		mkdir -p "$DIR"
		$BZIP2 -cz9 "$NEW/$CHECK_FILE" > "$WORK/$CHECK_FILE"
		if [ -x "$NEW/$CHECK_FILE" ]; then
			chmod 0755 "$WORK/$CHECK_FILE"
		else
			chmod 0644 "$WORK/$CHECK_FILE"
		fi
		ARCHIVEFILES="$ARCHIVEFILES \"$CHECK_FILE\""
		return
	elif ! diff "$OLD/$CHECK_FILE" "$NEW/$CHECK_FILE" > /dev/null; then
		mkdir -p "$DIR"
		$MBSDIFF "$OLD/$CHECK_FILE" "$NEW/$CHECK_FILE" "$WORK/$CHECK_FILE.patch"
		$BZIP2 -z9 "$WORK/$CHECK_FILE.patch"
		$BZIP2 -cz9 "$NEW/$CHECK_FILE" > "$WORK/$CHECK_FILE"
		PATCHSIZE=`du -b "$WORK/$CHECK_FILE.patch.bz2"`
		FULLSIZE=`du -b "$WORK/$CHECK_FILE"`
		PATCHSIZE="${PATCHSIZE%%	*}"
		FULLSIZE="${FULLSIZE%%	*}"
		if [ $PATCHSIZE -lt $FULLSIZE ]; then
			rm -f "$WORK/$CHECK_FILE"
			mv "$WORK/$CHECK_FILE.patch.bz2" "$WORK/$CHECK_FILE.patch"
			echo "patch \"$CHECK_FILE.patch\" \"$CHECK_FILE\"" >> "$MANIFEST"
			ARCHIVEFILES="$ARCHIVEFILES \"$CHECK_FILE.patch\""
		else
			rm -f "$WORK/$CHECK_FILE.patch.bz2"
			if [ -x "$NEW/$CHECK_FILE" ]; then
				chmod 0755 "$WORK/$CHECK_FILE"
			else
				chmod 0644 "$WORK/$CHECK_FILE"
			fi
			echo "add \"$CHECK_FILE\"" >> "$MANIFEST"
			ARCHIVEFILES="$ARCHIVEFILES \"$CHECK_FILE\""
		fi
	fi
	rm -f "$OLD/$CHECK_FILE"
}

function remove_file
{
	RM_FILE="${1#$OLD/}"
	if [ $RM_FILE != "update.manifest" -a $RM_FILE != "defaults/preferences/developers.js" -a $RM_FILE != "defaults/preferences/aa_per_machine.js" -a $RM_FILE != "defaults/preferences/autoupdate.js" -a $RM_FILE != "defaults/preferences/autochannel.js" ]; then
		echo "remove \"$RM_FILE\"" >> "$MANIFEST"
	fi
}

function build_update
{
	eval "$MAR -C \"$WORK\" -c output.mar $ARCHIVEFILES"
	mv "$WORK/output.mar" "$1"
	rm -rf "$WORK"
}

function check_mar
{
	if which mar; then
		MAR=${MAR:-mar}
	fi
	if which mbsdiff; then
		MBSDIFF=${MBSDIFF:-mbsdiff}
	fi
	if [ ! -x "$MAR" -o ! -x "$MBSDIFF" ]; then
		if [ ! -f "external/mar" -o ! -f "external/mbsdiff" ]; then
			wget ftp://ftp.mozilla.org/pub/mozilla.org/xulrunner/mar-generation-tools/mar-generation-tools-linux.zip
			unzip mar-generation-tools-linux.zip -d external
		fi
		MAR="$PWD/external/mar"
		MBSDIFF="$PWD/external/mbsdiff"
	fi
}

function make_full_update
{
	echo "Making full update"
	rm -rf "oldclient"
	mkdir -p "oldclient"
	prep_update client oldclient client.working
	build_update "full_update.mar"
	mkdir -p "$PUBPATH"
	mv full_update.mar "$PUBPATH/$VERSION.mar"
	echo "Making full update patch def"
	mkdir -p "$PATCHPATH"
	HASH=$(sha512sum "$PUBPATH/$VERSION.mar")
	SIZE=$(du -b "$PUBPATH/$VERSION.mar")
	echo "<patch type=\"complete\" URL=\"$VERSION.mar\" hashFunction=\"sha512\" hashValue=\"${HASH%% *}\" size=\"${SIZE%%	*}\"/>" > "$PATCHPATH/$VERSION.patchline"
}

function make_partial_update
{
	PREV_VERSION="${1%.mar}"
	if [ "$VERSION" == "$PREV_VERSION" ]; then
		echo "Skipping partial update for same version"
		return
	fi
	echo "Making partial update from $PREV_VERSION"
	rm -rf "oldclient"
	mkdir -p "oldclient"
	unwrap_update "$ARCHIVEPATH/$1" oldclient
	prep_update client oldclient client.working
	build_update "partial_update.mar"
	mv partial_update.mar "$PUBPATH/$PREV_VERSION-$VERSION.mar"
	echo "Making partial update patch def"
	mkdir -p "$PATCHPATH"
	HASH=$(sha512sum "$PUBPATH/$PREV_VERSION-$VERSION.mar")
	SIZE=$(du -b "$PUBPATH/$PREV_VERSION-$VERSION.mar")
	echo "<patch type=\"partial\" URL=\"$PREV_VERSION-$VERSION.mar\" hashFunction=\"sha512\" hashValue=\"${HASH%% *}\" size=\"${SIZE%%	*}\"/>" > "$PATCHPATH/$PREV_VERSION-$VERSION.patchline"
}

function make_partial_updates
{
	echo "Checking for partial update source files"
	if [ -d "$ARCHIVEPATH" ]; then
		for OLDVER in `find "$ARCHIVEPATH" -maxdepth 1 -name '*.mar'`; do
			make_partial_update "${OLDVER##*/}"
		done
	fi
	mkdir -p "$ARCHIVEPATH"
	echo "Copying full update to archive"
	cp "$PUBPATH/$VERSION.mar" "$ARCHIVEPATH"
	echo "Updating current version file"
	echo "$VERSION" > "$PATCHPATH/VERSION"
}

function cleanup_files
{
	echo "Cleaning up previous update mar files and update patch files"
	find "$PUBPATH" -maxdepth 1 -name "*.mar" ! -name "*$VERSION.mar" -delete -print
	find "$PATCHPATH" -maxdepth 1 -name "*.patch" ! -name "*$VERSION.patch" -delete -print
}

# First, do we have the mar and mbsdiff tools?
check_mar
VERSION=`cat build/VERSION`

# Generic Updates - No XULRunner packaged, channel of "release"
# NOTE: Generic updates CAN update Windows/Linux builds, and will do so if you don't build platform specific ones
if [ $GEN_UPDATES -eq 1 ]; then
	PATCHPATH="$prefix/patch"
	PUBPATH="$prefix/pub"
	ARCHIVEPATH="$prefix/archives"
	if [ $CLIENTS -eq 1 ]; then
		make generic-client
		mkdir -p "$prefix/pub/clients/"
		find "$prefix/pub/clients/" -name '*_client.xpi' -delete
		mv evergreen_staff_client.xpi "$prefix/pub/clients/${VERSION}_client.xpi"
	else
		make client_app
	fi
	make_full_update
	make_partial_updates
	cleanup_files
fi

# Windows Updates - Windows XULRunner, update channel of "win"
if [ $WIN_UPDATES -eq 1 ]; then
	PATCHPATH="$prefix/patch/win"
	PUBPATH="$prefix/pub/win"
	ARCHIVEPATH="$prefix/archives/win"
	if [ $CLIENTS -eq 1 ]; then
		make win-client
		mkdir -p "$prefix/pub/clients/"
		find "$prefix/pub/clients/" -name '*_setup.exe' -delete
		mv evergreen_staff_client_setup.exe "$prefix/pub/clients/${VERSION}_setup.exe"
	else
		make win-xulrunner
	fi
	make_full_update
	make_partial_updates
	cleanup_files
fi

# Linux 32 bit Updates - Linux XULRunner, update channel of "lin"
if [ $LINUX32_UPDATES -eq 1 ]; then
	PATCHPATH="$prefix/patch/lin"
	PUBPATH="$prefix/pub/lin"
	ARCHIVEPATH="$prefix/archives/lin"
	if [ $CLIENTS -eq 1 ]; then
		make linux32-client
		mkdir -p "$prefix/pub/clients/"
		find "$prefix/pub/clients/" -name '*_i686.tar.bz2' -delete
		mv evergreen_staff_client_i686.tar.bz2 "$prefix/pub/clients/${VERSION}_i686.tar.bz2"
	else
		make linux32-xulrunner
	fi
	make_full_update
	make_partial_updates
	cleanup_files
fi

# Linux 64 bit Updates - Linux XULRunner, update channel of "lin64"
if [ $LINUX64_UPDATES -eq 1 ]; then
	PATCHPATH="$prefix/patch/lin64"
	PUBPATH="$prefix/pub/lin64"
	ARCHIVEPATH="$prefix/archives/lin64"
	if [ $CLIENTS -eq 1 ]; then
		make linux64-client
		mkdir -p "$prefix/pub/clients/"
		find "$prefix/pub/clients/" -name '*_x86_64.tar.bz2' -delete
		mv evergreen_staff_client_x86_64.tar.bz2 "$prefix/pub/clients/${VERSION}_x86_64.tar.bz2"
	else
		make linux64-xulrunner
	fi
	make_full_update
	make_partial_updates
	cleanup_files
fi

# Extension Updates
# Not really "Updates" so much as "Update", plural for consistency in command.
# Extensions don't do partial updates. Or at least not that I found docs for.
if [ $EXT_UPDATES -eq 1 ]; then
	make extension
	mkdir -p "$prefix/pub/"
	find "$prefix/pub/" -maxdepth 1 -name '*_extension.xpi' -delete
	mv evergreen.xpi "$prefix/pub/${VERSION}_extension.xpi" 
	SHA512=$(sha512sum "$prefix/pub/${VERSION}_extension.xpi")
	SHA512=${SHA512%% *}
	sed -e "s|<em:version>.*</em:version>|<em:version>$VERSION</em:version>|" -e "s|<em:updateLink>.*</em:updateLink>|<em:updateLink>https://::HOSTNAME::/updates/${VERSION}_extension.xpi</em:updateLink>|" -e "s|<em:updateHash>.*</em:updateHash>|<em:updateHash>sha512:$SHA512</em:updateHash>|" update.rdf > "$prefix/patch/update.rdf"
fi
