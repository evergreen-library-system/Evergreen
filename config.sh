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

function buildConfig {

	if [ -f "$DEFAULT_CONFIG_FILE" ]; then
		source "$DEFAULT_CONFIG_FILE";
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
	CGIDIR="$PREFIX/var/cgi-bin";
	TEMPLATEDIR="$PREFIX/var/templates";
	CIRCRULESDIR="$PREFIX/var/circ";
	XSLDIR="$PREFIX/var/xsl";
	REPORTERDIR="$PREFIX/var/reporter";
	TMP="$(pwd)/.tmp";

	prompt "Web domain for OPAC in Staff Client [$NEW_OPAC_URL] "
	read X; if [ ! -z "$X" ]; then NEW_OPAC_URL="$X"; fi;

	prompt "Package Name for Staff Client [$NEW_XUL_PACKAGE_NAME] "
	read X; if [ ! -z "$X" ]; then NEW_XUL_PACKAGE_NAME="$X"; fi;

	prompt "Package Label for Staff Client [$NEW_XUL_PACKAGE_LABEL] "
	read X; if [ ! -z "$X" ]; then NEW_XUL_PACKAGE_LABEL="$X"; fi;

	prompt "Apache2 apxs binary [$APXS2] "
	read X; if [ ! -z "$X" ]; then APXS2="$X"; fi;

	prompt "Apache2 headers directory [$APACHE2_HEADERS] "
	read X; if [ ! -z "$X" ]; then APACHE2_HEADERS="$X"; fi;

	prompt "Apache2 APR headers directory [$APR_HEADERS] "
	read X; if [ ! -z "$X" ]; then APR_HEADERS="$X"; fi;

	prompt "Libxml2 headers directory [$LIBXML2_HEADERS] "
	read X; if [ ! -z "$X" ]; then LIBXML2_HEADERS="$X"; fi;

	prompt "Build targets [${TARGETS[@]:0}] "
	read X; if [ ! -z "$X" ]; then TARGETS=("$X"); fi;

	prompt "Bootstrapping Database Driver [$DBDRVR] "
	read X; if [ ! -z "$X" ]; then DBDRVR="$X"; fi;

	prompt "Bootstrapping Database Host [$DBHOST] "
	read X; if [ ! -z "$X" ]; then DBHOST="$X"; fi;

	prompt "Bootstrapping Database Name [$DBNAME] "
	read X; if [ ! -z "$X" ]; then DBNAME="$X"; fi;

	prompt "Bootstrapping Database User [$DBUSER] "
	read X; if [ ! -z "$X" ]; then DBUSER="$X"; fi;

	prompt "Bootstrapping Database Password [$DBPW] "
	read X; if [ ! -z "$X" ]; then DBPW="$X"; fi;

	prompt "Reporter Template Directory [$REPORTERDIR] "
	read X; if [ ! -z "$X" ]; then REPORTERDIR="$X"; fi;

	writeConfig;
}

function prompt { echo ""; echo -n "$*"; }

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

	_write "TMP=\"$TMP\"";
	_write "APXS2=\"$APXS2\"";
	_write "APACHE2_HEADERS=\"$APACHE2_HEADERS\"";
	_write "APR_HEADERS=\"$APR_HEADERS\"";
	_write "LIBXML2_HEADERS=\"$LIBXML2_HEADERS\"";

	_write "WEBDIR=\"$WEBDIR\"";
	_write "TEMPLATEDIR=\"$TEMPLATEDIR\"";
	_write "ETCDIR=\"$ETCDIR\"";
	_write "CIRCRULESDIR=\"$CIRCRULESDIR\"";
	_write "XSLDIR=\"$XSLDIR\"";

	_write "NEW_OPAC_URL=\"$NEW_OPAC_URL\"";
	_write "NEW_XUL_PACKAGE_NAME=\"$NEW_XUL_PACKAGE_NAME\"";
	_write "NEW_XUL_PACKAGE_LABEL=\"$NEW_XUL_PACKAGE_LABEL\"";

	# print out the targets
	STR="TARGETS=(";
	for target in ${TARGETS[@]:0}; do
		STR="$STR \"$target\"";
	done;
	STR="$STR)";
	_write "$STR";

	_write "OPENSRFDIR=\"OpenSRF/src/\"";
	_write "OPENILSDIR=\"Open-ILS/src/\"";
	_write "EVERGREENDIR=\"Evergreen/\"";


	_write "CGIDIR=\"$CGIDIR\"";

	# db vars
	_write "DBDRVR=\"$DBDRVR\"";
	_write "DBHOST=\"$DBHOST\"";
	_write "DBNAME=\"$DBNAME\"";
	_write "DBUSER=\"$DBUSER\"";
	_write "DBPW=\"$DBPW\"";
	_write "REPORTERDIR=\"$REPORTERDIR\"";


	# Now we'll write out the DB bootstrapping config
	CONFIG_FILE='Open-ILS/src/cgi-bin/setup.pl';
	rm -f "$CONFIG_FILE";
	echo "Writing bootstrapping config to $CONFIG_FILE...";

	STR='$main::config{dsn} =';
		STR="$STR 'dbi:${DBDRVR}:host=";
		STR="${STR}${DBHOST};dbname=";
		STR="${STR}${DBNAME}';";
	_write "$STR"

	STR='$main::config{usr} =';
		STR="$STR '$DBUSER';";
	_write "$STR"
	
	STR='$main::config{pw} =';
		STR="$STR '$DBPW';";
	_write "$STR"
	
	_write '$main::config{index} = "config.cgi";';


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
