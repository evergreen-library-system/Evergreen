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


#function postMessage {

#cat <<-WORDS
#	--------------------------------------------------------------------


#}



# --------------------------------------------------------------------
# Makes sure the install directories exist and are writable
# --------------------------------------------------------------------
function mkInstallDirs {

	if installing; then

		mkdir -p "$PREFIX";
		if [ "$?" != "0" ]; then
			fail "Error creating $PREFIX";
		fi

		if [ ! -w "$PREFIX" ]; then
			fail "We don't have write access to $PREFIX";
		fi

	fi

	if building; then

		mkdir -p "$TMP";
		if [ "$?" != "0" ]; then
			fail "Error creating $TMP";
		fi

		if [ ! -w "$TMP" ]; then
			fail "We don't have write access to $TMP";
		fi
	fi

	

}

function installing {
	if [ -z "$INSTALLING" ]; then return 1; fi;
	return 0;
}

function building {
	if [ -z "$BUILDING" ]; then return 1; fi;
	return 0;
}



# --------------------------------------------------------------------
# Loads the config file.  If it can't fine CONFIG_FILE, it attempts to
# use DEFAULT_CONFIG_FILE.  If it can't find that, it fails.
# --------------------------------------------------------------------
function loadConfig {
	if [ ! -f "$CONFIG_FILE" ]; then
		if [ -f "$DEFAULT_CONFIG_FILE" ]; then
			echo "+ + + Copying $DEFAULT_CONFIG_FILE to $CONFIG_FILE and using its settings...";
			cp "$DEFAULT_CONFIG_FILE" "$CONFIG_FILE";
		else
			fail "config file \"$CONFIG_FILE\" cannot be found";
		fi
	fi
	source "$CONFIG_FILE";
}




# install targets
#
# opensrf_jserver - custom 'single-domain' jabber server which may be used in place of jabberd2
# opensrf_router  - jabber router.  
# opensrf_gateway - mod_ils_gateway, Apache module for proxying API calls
# opensrf_srfsh   - diagnostic shell interface to OpenSRF
# opensrf_perl		- install the OpenSRF perl modules
# opensrf_all		- builds all OpenSRF compenents
# openils_marcdumper - utility code for converting MARC to MARCXML
# openils_perl			- install the Open-ILS perl modules
# openils_all			- builds all OpenILS compenents
# openils_web			- copies over the javascript and html templates to the web root directory
# evergreen_xul_client   - client XUL application
# evergreen_all	- builds all Evergreen components
function runInstall {



	# pass the collected variables to make
	for target in ${TARGETS[@]:0}; do

		cat <<-MSG

		--------------------------------------------------------------------
		Building $target
		--------------------------------------------------------------------

		MSG

		MAKE="make APXS2=$APXS2 PREFIX=$PREFIX TMP=$TMP \
			APACHE2_HEADERS=$APACHE2_HEADERS LIBXML2_HEADERS=$LIBXML2_HEADERS \
			BINDIR=$BINDIR LIBDIR=$LIBDIR PERLDIR=$PERLDIR INCLUDEDIR=$INCLUDEDIR";

		case "$target" in
	
			# OpenSRF --- 			

			"opensrf_all")
				if building;	then $MAKE -C "$OPENSRF_DIR" all; fi;
				if installing; then $MAKE -C "$OPENSRF_DIR" install; fi;
				;;

			"opensrf_jserver" )
				if building;	then $MAKE -C "$OPENSRF_DIR" "jserver"; fi;
				if installing; then $MAKE -C "$OPENSRF_DIR" "jserver-install"; fi;
				;;	

			"opensrf_router" ) 
				if building;	then $MAKE -C "$OPENSRF_DIR" "router"; fi;
				if installing; then $MAKE -C "$OPENSRF_DIR" "router-install"; fi;
				;;

			"opensrf_gateway" )
				if building;	then $MAKE -C "$OPENSRF_DIR" "gateway"; fi;
				if installing; then $MAKE -C "$OPENSRF_DIR" "gateway-install"; fi;
				;;

			"opensrf_srfsh" ) 
				if building;	then $MAKE -C "$OPENSRF_DIR" "srfsh"; fi;
				if installing; then $MAKE -C "$OPENSRF_DIR" "srfsh-install"; fi;
				;;

			"opensrf_perl")
				if installing; then $MAKE -C "$OPENSRF_DIR" "perl-install"; fi;
				;;


			# OpenILS --- 			

			"openils_all")
				if building;	then $MAKE -C "$OPENILS_DIR" all; fi;
				if installing; then $MAKE -C "$OPENILS_DIR" install; fi;
				;;

			"openils_perl")
				if installing; then $MAKE -C "$OPENILS_DIR" "perl-install"; fi;
				;;


			# Evergreen --- 			

			"evergreen_xul_client")
				if building;	then $MAKE -C "$EVERGREEN_DIR" xul; fi;
				;;


			*) fail "Unknown target: $target";;

		esac

	done
}


# --------------------------------------------------------------------
# Checks command line parameters for special behavior
# Supported params are:
# clean - cleans all build files
# build - builds the specified sources
# install - installs the specified sources
# --------------------------------------------------------------------
function checkParams {

	if [ -z "$1" ]; then return; fi;

	for arg in "$@"; do

		lastArg="$arg";

		case "$arg" in

			"clean") 
				cleanMe;;

			"build")
				BUILDING="1";;

			"install")
				INSTALLING="1";;

			*) fail "Unknown command line argument: $arg";;
		esac
	done

	if [ "$lastArg" = "clean" ]; then exit 0; fi;
}


function cleanMe {
	loadConfig;
	make -C "$OPENSRF_DIR" clean;
	make -C "$OPENILS_DIR"  clean;
	make -C "$EVERGREEN_DIR" clean;
}

checkParams "$@";


if building; then echo "Building..."; fi;
if installing; then echo "Installing..."; fi;


# --------------------------------------------------------------------
# Kick it off...
# --------------------------------------------------------------------
loadConfig;
mkInstallDirs;
runInstall;



