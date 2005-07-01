#!/bin/bash
# --------------------------------------------------------------------
# Copyright (C) 2005  Georgia Public Library Service 
# Bill Erickson <highfalutin@gmail.com>
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
# --------------------------------------------------------------------


# --------------------------------------------------------------------
# ILS install script
# --------------------------------------------------------------------

 
# *!*!* EDIT THESE *!*!*
# --------------------------------------------------------------------
# Here define all of the necessary install variables 
# --------------------------------------------------------------------
APXS2="/pines/apps/apache2/bin/apxs";
PREFIX="/pines/";
TMP="/tmp/pines/";
APACHE2_HEADERS="/pines/apps/apache2/include/";
LIBXML2_HEADERS="/usr/include/libxml2/";
TARGETS=("OpenSRF" "Open-ILS" "Evergreen");
# --------------------------------------------------------------------

# --------------------------------------------------------------------
# if FORCE is set to any non-empty value, we'll use 
# the default settings
FORCE=$1 
# --------------------------------------------------------------------





# --------------------------------------------------------------------
# Loads all of the path information from the user setting 
# install variables as it goes
# --------------------------------------------------------------------
function verifyInstallPaths {

	cat <<-WORDS

	-----------------------------------------------------------------------
	Verify the following install directories are sane.
	Note: * indicates that you must have write privelages for the location
	-----------------------------------------------------------------------

	-----------------------------------------------------------------------
	Install prefix            [$PREFIX]*
	Temporary files directory [$TMP]*
	Apache2 apxs binary       [$APXS2]
	Apache2 header directory  [$APACHE2_HEADERS]
	Libxml2 header directory  [$LIBXML2_HEADERS]
	Building targets          [${TARGETS[@]:0}];
	-----------------------------------------------------------------------

	If these are not OK, use control-c to break out and fix the variables 
	at the top of this script.  Otherwise, type enter.

	WORDS
	read OK;
}

# --------------------------------------------------------------------
# Makes sure the install directories exist and are writable
# --------------------------------------------------------------------
function mkInstallDirs {

	mkdir -p "$PREFIX";

	if [ "$?" != "0" ]; then
		echo "Error creating $PREFIX";
		exit 99;
	fi

	mkdir -p "$TMP";
	if [ "$?" != "0" ]; then
		echo "Error creating $TMP";
		exit 99;
	fi

	if [ ! -w "$PREFIX" ]; then
		echo "We don't have write access to $PREFIX";
		exit 99;
	fi

	if [ ! -w "$TMP" ]; then
		echo "We don't have write access to $TMP";
		exit 99;
	fi

}


function runInstall {

	[ -z "$FORCE" ] && verifyInstallPaths;
	mkInstallDirs;

	# pass the collected variables to make
	for target in ${TARGETS[@]:0}; do

		target="$target/src";

		make -C "$target" \
			APXS2="$APXS2" \
			PREFIX="$PREFIX" \
			TMP="$TMP" \
			APCHE2_HEADERS="$APACHE2_HEADERS" \
			LIBXML2_HEADERS="$LIBXML2_HEADERS" \
			all;	

	done
}



# Kick it off...
runInstall;

