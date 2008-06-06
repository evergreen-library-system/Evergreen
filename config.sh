#!/bin/bash
# --------------------------------------------------------------------
# Copyright (C) 2005  Georgia Public Library Service 
# Bill Erickson <highfalutin@gmail.com>
# Mike Rylander <mrylander@gmail.com>
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
# Prompts the user for config settings and writes a custom config
# file based on these settings
# --------------------------------------------------------------------


CONFIG_FILE="install.conf";
DEFAULT_CONFIG_FILE="install.conf.default";
USE_DEFAULT="$1";

function buildConfig {

	if [ -f "$CONFIG_FILE" ]; then
		source "$CONFIG_FILE";
	else
		if [ -f "$DEFAULT_CONFIG_FILE" ]; then
			source "$DEFAULT_CONFIG_FILE";
		fi;
	fi;

    if [ -n "$USE_DEFAULT" ]; then
        prompt "Default config requested, not prompting for values...\n";
        writeConfig;
        return 0;
    fi;


	echo "";
	echo "-----------------------------------------------------------------------";
	echo "Type Enter to select the default"
	echo "-----------------------------------------------------------------------";

	prompt "Install prefix [$PREFIX] ";
	read X; if [ ! -z "$X" ]; then PREFIX="$X"; fi

	BINDIR="$PREFIX/bin/";
	LIBDIR="$PREFIX/lib/";
	PERLDIR="$LIBDIR/perl5/";
	INCLUDEDIR="$PREFIX/include/";
	ETCDIR="$PREFIX/conf";
	WEBDIR="$PREFIX/var/web";
	DATADIR="$PREFIX/var/data";
	CGIDIR="$PREFIX/var/cgi-bin";
	TEMPLATEDIR="$PREFIX/var/templates";
	CIRCRULESDIR="$PREFIX/var/circ";
	CATALOGSCRIPTDIR="$PREFIX/var/catalog";
	PENALTYRULESDIR="$PREFIX/var/penalty";
	XSLDIR="$PREFIX/var/xsl";
	REPORTERDIR="$PREFIX/var/web/reporter";
	TMP="$(pwd)/.tmp";
	ADMINDIR="$PREFIX/var/admin";

	prompt "Apache2 apxs binary [$APXS2] "
	read X; if [ ! -z "$X" ]; then APXS2="$X"; fi;

	prompt "Apache2 headers directory [$APACHE2_HEADERS] "
	read X; if [ ! -z "$X" ]; then APACHE2_HEADERS="$X"; fi;

	prompt "Apache2 APR headers directory [$APR_HEADERS] "
	read X; if [ ! -z "$X" ]; then APR_HEADERS="$X"; fi;

	prompt "Libdbi libraries directory [$DBI_LIBS] "
	read X; if [ ! -z "$X" ]; then DBI_LIBS="$X"; fi;

	prompt "Libxml2 headers directory [$LIBXML2_HEADERS] "
	read X; if [ ! -z "$X" ]; then LIBXML2_HEADERS="$X"; fi;

	prompt "OpenSRF headers directory [$OPENSRF_HEADERS] "
	read X; if [ ! -z "$X" ]; then OPENSRF_HEADERS="$X"; fi;

	prompt "OpenSRF libraries directory [$OPENSRF_LIBS] "
	read X; if [ ! -z "$X" ]; then OPENSRF_LIBS="$X"; fi;

	prompt "Build targets [${TARGETS[@]:0}] "
	read X; if [ ! -z "$X" ]; then TARGETS=("$X"); fi;

	prompt "Database Driver [$DBDRVR] "
	read X; if [ ! -z "$X" ]; then DBDRVR="$X"; fi;

	if [ "$DBDRVR" == "Pg" ]; then
		prompt "Bootstrapping Database Version (80 for 8.0.x, 81 for 8.1.x, 82 for 8.2.x) [$DBVER] "
		read X; if [ ! -z "$X" ]; then DBVER="$X"; fi;
	fi;

	prompt "Database Host [$DBHOST] "
	read X; if [ ! -z "$X" ]; then DBHOST="$X"; fi;

	prompt "Database Port [$DBPORT] "
	read X; if [ ! -z "$X" ]; then DBPORT="$X"; fi;

	prompt "Database Name [$DBNAME] "
	read X; if [ ! -z "$X" ]; then DBNAME="$X"; fi;

	prompt "Database User [$DBUSER] "
	read X; if [ ! -z "$X" ]; then DBUSER="$X"; fi;

	prompt "Database Password [$DBPW] "
	read X; if [ ! -z "$X" ]; then DBPW="$X"; fi;

	prompt "Reporter Template Directory [$REPORTERDIR] "
	read X; if [ ! -z "$X" ]; then REPORTERDIR="$X"; fi;

	writeConfig;
}

function prompt { echo ""; echo -en "$*"; }

function writeConfig {

	rm -f "$CONFIG_FILE";
	echo "Writing installation config to $CONFIG_FILE...";

	_write "PREFIX=\"$PREFIX\"";
	_write "BINDIR=\"$BINDIR\"";
	_write "LIBDIR=\"$LIBDIR\"";
	_write "PERLDIR=\"$PERLDIR\"";
	_write "INCLUDEDIR=\"$INCLUDEDIR\"";
	_write "SOCK=\"$PREFIX/var/sock\"";
	_write "PID=\"$PREFIX/var/pid\"";
	_write "LOG=\"$PREFIX/var/log\"";
	_write "DATADIR=\"$DATADIR\"";

	_write "TMP=\"$TMP\"";
	_write "APXS2=\"$APXS2\"";
	_write "APACHE2_HEADERS=\"$APACHE2_HEADERS\"";
	_write "APR_HEADERS=\"$APR_HEADERS\"";
	_write "DBI_LIBS=\"$DBI_LIBS\"";
	_write "LIBXML2_HEADERS=\"$LIBXML2_HEADERS\"";

	_write "OPENSRF_HEADERS=\"$OPENSRF_HEADERS\"";
	_write "OPENSRF_LIBS=\"$OPENSRF_LIBS\"";

	_write "WEBDIR=\"$WEBDIR\"";
	_write "TEMPLATEDIR=\"$TEMPLATEDIR\"";
	_write "ETCDIR=\"$ETCDIR\"";
	_write "CIRCRULESDIR=\"$CIRCRULESDIR\"";
	_write "CATALOGSCRIPTDIR=\"$CATALOGSCRIPTDIR\"";
	_write "PENALTYRULESDIR=\"$PENALTYRULESDIR\"";
	_write "XSLDIR=\"$XSLDIR\"";

	# print out the targets
	STR="TARGETS=(";
	for target in ${TARGETS[@]:0}; do
		STR="$STR \"$target\"";
	done;
	STR="$STR)";
	_write "$STR";

	_write "OPENILSDIR=\"Open-ILS/src/\"";
	_write "EVERGREENDIR=\"Evergreen/\"";


	_write "CGIDIR=\"$CGIDIR\"";

	# db vars
	_write "DBDRVR=\"$DBDRVR\"";
	_write "DBHOST=\"$DBHOST\"";
	_write "DBPORT=\"$DBPORT\"";
	_write "DBNAME=\"$DBNAME\"";
	_write "DBUSER=\"$DBUSER\"";
	_write "DBPW=\"$DBPW\"";
	_write "DBVER=\"$DBVER\"";
	_write "REPORTERDIR=\"$REPORTERDIR\"";
	_write "ADMINDIR=\"$ADMINDIR\"";


	# Now we'll write out the DB bootstrapping config
	CONFIG_FILE='Open-ILS/src/cgi-bin/setup.pl';
	rm -f "$CONFIG_FILE";
	echo "Writing bootstrapping config to $CONFIG_FILE...";

	STR='$main::config{dsn} =';
		STR="$STR 'dbi:${DBDRVR}:host=";
		STR="${STR}${DBHOST};dbname=";
		STR="${STR}${DBNAME};port=";
		STR="${STR}${DBPORT}';";
	_write "$STR"

	STR='$main::config{usr} =';
		STR="$STR '$DBUSER';";
	_write "$STR"
	
	STR='$main::config{pw} =';
		STR="$STR '$DBPW';";
	_write "$STR"
	
	_write '$main::config{index} = "config.cgi";';


    # --------------------------------------------------------------------
	# Now we'll write out the offline config
	CONFIG_FILE='Open-ILS/src/offline/offline-config.pl';
	rm -f "$CONFIG_FILE";
	echo "Writing bootstrapping config to $CONFIG_FILE...";

    _write "\$main::config{base_dir} = '$PREFIX/var/data/offline/';";
    _write "\$main::config{bootstrap} = '$ETCDIR/opensrf_core.xml';";

	STR='$main::config{dsn} =';
		STR="$STR 'dbi:${DBDRVR}:host=";
		STR="${STR}${DBHOST};dbname=";
		STR="${STR}${DBNAME};port=";
		STR="${STR}${DBPORT}';";
	_write "$STR"

	STR='$main::config{usr} =';
		STR="$STR '$DBUSER';";
	_write "$STR"
	
	STR='$main::config{pw} =';
		STR="$STR '$DBPW';";
	_write "$STR"
    # --------------------------------------------------------------------
	

	prompt "";
	prompt "";
	prompt "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!";
	prompt "!! If installing openils_all / openils_db !!";
	prompt "!! Before running 'make install' you MUST !!";
	prompt "!! create a database for Open-ILS.  Use   !!";
	prompt "!! the settings that you listed above and !!";
	prompt "!! the install scripts will create the    !!";
	prompt "!! database for you.  -miker              !!";
	prompt "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!";
	prompt "";
	prompt "";

	prompt "To write a new config, run 'make config'";
	prompt "";
	prompt "To edit individual install locations (e.g. changing the lib directory),"
	prompt "edit the install.conf file generated from this script"
	prompt ""

}

function _write {
	echo "$*" >> "$CONFIG_FILE";
}



buildConfig;
