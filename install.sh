#!/bin/bash
# vim:noet:ts=4
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
verbose="-s" #clear this to get full build output


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

function mkDir {
	mkdir -p "$1";
	[ "$?" != "0" ] && fail "Error creating $1";
	[ ! -w "$1" ] && fail "We don't have write access to $1";
}

function mkInstallDirs {

	installing 	&& mkDir "$PREFIX";
	building 	&& mkDir "$TMP";
	installing 	&& mkDir "$SOCK";
	installing 	&& mkDir "$PID";
	installing 	&& mkDir "$LOG";


	# add the opensrf user and group
	 if installing; then
	 	if [ ! $(grep "^opensrf:" /etc/group) ]; then groupadd opensrf; fi
	 	if [ ! $(grep "^opensrf:" /etc/passwd) ]; then useradd -g opensrf opensrf; fi
	fi;

}

function installing {
	if [ -z "$INSTALLING" ]; then return 1; fi;
	return 0;
}

function building {
	if [ -z "$BUILDING" ]; then return 1; fi;
	return 0;
}

function testing {
	if [ -z "$TESTING" ]; then return 1; fi;
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




function runInstall {

	# pass the collected variables to make
	for target in ${TARGETS[@]:0}; do

		echo ""
		echo "-------------- [ $target ] -------------------------------------------";
		echo ""

		MAKE="make $verbose APXS2=$APXS2 PREFIX=$PREFIX TMP=$TMP APR_HEADERS=$APR_HEADERS \
			APACHE2_HEADERS=$APACHE2_HEADERS LIBXML2_HEADERS=$LIBXML2_HEADERS DBPORT=$DBPORT\
			BINDIR=$BINDIR DBI_LIBS=$DBI_LIBS LIBDIR=$LIBDIR PERLDIR=$PERLDIR EG_PYTHON_INSTALL=$EG_PYTHON_INSTALL INCLUDEDIR=$INCLUDEDIR \
			WEBDIR=$WEBDIR TEMPLATEDIR=$TEMPLATEDIR ETCDIR=$ETCDIR REPORTERDIR=$REPORTERDIR\
			OPENSRF_HEADERS=$OPENSRF_HEADERS OPENSRF_LIBS=$OPENSRF_LIBS OPENILSDIR=$OPENILSDIR EVERGREENDIR=$EVERGREENDIR \
			CIRCRULESDIR=$CIRCRULESDIR CATALOGSCRIPTDIR=$CATALOGSCRIPTDIR CGIDIR=$CGIDIR \
			DBDRVR=$DBDRVR DBHOST=$DBHOST DATADIR=$DATADIR ADMINDIR=$ADMINDIR\
			PENALTYRULESDIR=$PENALTYRULESDIR DBNAME=$DBNAME DBUSER=$DBUSER DBPW=$DBPW XSLDIR=$XSLDIR NEW_OPAC_URL=$NEW_OPAC_URL \
			NEW_XUL_PACKAGE_NAME=$NEW_XUL_PACKAGE_NAME NEW_XUL_PACKAGE_LABEL=$NEW_XUL_PACKAGE_LABEL";


		case "$target" in
	
			# OpenILS --- 			

			"openils_all" )
				if building;	then $MAKE -C "$OPENILSDIR" all; fi;
				if testing;		then $MAKE -C "$OPENILSDIR/../examples" test; fi;
				if installing; then $MAKE -C "$OPENILSDIR" install; fi;
				;;

			"openils_core" )
				if building; then 
					$MAKE -C "$OPENILSDIR" "c_apps";
					$MAKE -C "$OPENILSDIR" "python-build";
				fi;
				if installing; then 
					$MAKE -C "$OPENILSDIR" "perl-install"; 
					$MAKE -C "$OPENILSDIR" "python-install"; 
					$MAKE -C "$OPENILSDIR" "string-templates-install"; 
					$MAKE -C "$OPENILSDIR" "xsl-install"; 
					$MAKE -C "$OPENILSDIR" "c_apps-install"; 
					$MAKE -C "$OPENILSDIR" "circ_rules-install"; 
					$MAKE -C "$OPENILSDIR" "autojs-install"; 
				fi;
				;;

			"openils_web" )
				if building; then $MAKE -C "$OPENILSDIR" "mod_xmlent"; fi;
				#if building; then $MAKE -C "$OPENILSDIR" "mod_ils_rest_gateway"; fi;
				if installing; then
					$MAKE -C "$OPENILSDIR" "web-install";
					$MAKE -C "$OPENILSDIR" "cgi-bootstrap";
					$MAKE -C "$OPENILSDIR" "reporter-install";
				fi;
				;;

			"openils_db" )
				if installing; then 
					$MAKE -C "$OPENILSDIR" "storage-bootstrap"; 
				fi;
				;;

			"openils_reporter" )
				if installing; then 
					$MAKE -C "$OPENILSDIR" "reporter-install";
				fi;
				;;

			"openils_client_xul" )
				if building; then
					$MAKE -C "$OPENILSDIR" "client-xul";
				fi;
				;;

			"openils_server_xul" )
				if installing; then
					$MAKE -C "$OPENILSDIR" "server-xul";
				fi;
				;;

			# Evergreen --- 			

			"evergreen_core" )
				if installing;	then $MAKE -C "$EVERGREENDIR" "install"; fi;
				;;	

			"evergreen_xul_client" )
				if building;	then $MAKE -C "$EVERGREENDIR" xul; fi;
				;;


			*) fail "Unknown target: $target";;

		esac

	done

	if installing; then
		echo -e "\nNow run: chown -R opensrf:opensrf $PREFIX"
	fi
}


# --------------------------------------------------------------------
# Checks command line parameters for special behavior
# Supported params are:
# clean - cleans all build files
# build - builds the specified sources
# install - installs the specified sources
# test - tests the specified sources
# --------------------------------------------------------------------
function checkParams {

	if [ -z "$1" ]; then usage; fi;

	for arg in "$@"; do

		lastArg="$arg";

		case "$arg" in

			"clean") 
				cleanMe;;

			"build")
				BUILDING="1";;

			"install")
				INSTALLING="1";;
			
			"verbose")
				verbose="";;

			"test")
				TESTING="1";;

			*) fail "Unknown option => $arg";
		esac
	done

	if [ "$lastArg" = "clean" ]; then exit 0; fi;
}


function cleanMe {
	loadConfig;
	make "TMP=$TMP" -s -C "$OPENILSDIR"  clean;
	make "TMP=$TMP" -s -C "$EVERGREENDIR" clean;
	make "TMP=$TMP" -s -C "$OPENILSDIR/../xul/staff_client"  clean;
}

function usage {
	echo "usage: $0 [ build | install | clean ]";
	exit;
}

checkParams "$@";

if building; then echo "Building..."; fi;
if testing; then echo "Testing..."; fi;
if installing; then echo "Installing..."; fi;


# --------------------------------------------------------------------
# Kick it off...
# --------------------------------------------------------------------
loadConfig;
mkInstallDirs;
runInstall;

