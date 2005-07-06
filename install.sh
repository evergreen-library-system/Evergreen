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
CONFIG_FILE="install.conf";
DEFAULT_CONFIG_FILE="install.conf.default";


# --------------------------------------------------------------------
# Loads all of the path information from the user setting 
# install variables as it goes
# --------------------------------------------------------------------

function fail {
	MSG="$1";
	echo "A build error occured: $MSG";
	exit 99;
}


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
	in install.config.  Otherwise, type enter.

	To disable this message, run "./install.sh force".

	WORDS
	read OK;
}

#function postMessage {

#cat <<-WORDS
#	--------------------------------------------------------------------


#}

# --------------------------------------------------------------------
# Makes sure the install directories exist and are writable
# --------------------------------------------------------------------
function mkInstallDirs {

	mkdir -p "$PREFIX";
	if [ "$?" != "0" ]; then
		fail "Error creating $PREFIX";
	fi

	mkdir -p "$TMP";
	if [ "$?" != "0" ]; then
		fail "Error creating $TMP";
	fi

	if [ ! -w "$PREFIX" ]; then
		fail "We don't have write access to $PREFIX";
	fi

	if [ ! -w "$TMP" ]; then
		fail "We don't have write access to $TMP";
	fi

}

# --------------------------------------------------------------------
# Loads the config file.  If it can't fine CONFIG_FILE, it attempts to
# use DEFAULT_CONFIG_FILE.  If it can't find that, it fails.
# --------------------------------------------------------------------
function loadConfig {
	if [ ! -f "$CONFIG_FILE" ]; then
		if [ -f "$DEFAULT_CONFIG_FILE" ]; then
			cp "$DEFAULT_CONFIG_FILE" "$CONFIG_FILE";
		else
			fail "config file \"$CONFIG_FILE\" cannot be found";
		fi
	fi
	source "$CONFIG_FILE";
}


function runInstall {


	loadConfig;
	#[ -z "$FORCE" ] && verifyInstallPaths;
	mkInstallDirs;

	# pass the collected variables to make
	for target in ${TARGETS[@]:0}; do

		cat <<-MSG

		--------------------------------------------------------------------
		Building $target
		--------------------------------------------------------------------

		MSG

		MAKE="make APXS2=$APXS2 PREFIX=$PREFIX TMP=$TMP APACHE2_HEADERS=$APACHE2_HEADERS LIBXML2_HEADERS=$LIBXML2_HEADERS"; 

		echo "Passing to sub-makes: $VARS"
			
		case "$target" in
			
			"jserver" | "router" | "gateway" | "srfsh" ) $MAKE -C "$OPENSRF_DIR" "$target" "$target-install";;

			*) fail "Unknown target: $target";;

		esac

	done
}


# --------------------------------------------------------------------
# Checks command line parameters for special behavior
# Supported params are:
# clean - cleans all build files
# force - forces build without the initial message
# --------------------------------------------------------------------
function checkParams {

	if [ -z "$1" ]; then return; fi;

	for arg in "$@"; do

		lastArg="$arg";

		case "$arg" in

			"clean") 
				make -C OpenSRF/src clean
				make -C Open-ILS/src clean
				make -C Evergreen/src clean;;

			"force")
				FORCE="1";;

			*) fail "Unknown command line argument: $arg";;
		esac
	done

	echo "LAST $lastArg";
	if [ "$lastArg" = "clean" ]; then exit 0; fi;
}

# if user passes in the word 'clean' as the first shell arg, clean all
checkParams "$@";


# Kick it off...
runInstall;



