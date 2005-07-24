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

#	if [ -f "$CONFIG_FILE" ]; then
#		echo "";
#		echo "Using existing config file \"$CONFIG_FILE\""; 
#		echo "To generate a new config, remove \"$CONFIG_FILE\"";
#		echo "";
#		sleep 3;	
#		exit 0;
#	fi


	if [ -f "$DEFAULT_CONFIG_FILE" ]; then
		source "$DEFAULT_CONFIG_FILE";
	fi;


	echo "";
	echo "-----------------------------------------------------------------------";
	echo "Type Enter to select the default"
	echo "-----------------------------------------------------------------------";

	prompt "Temporary files directory [$TMP] "
	read X; if [ ! -z "$X" ]; then TMP="$X"; fi;

	prompt "Install prefix [$PREFIX] ";
	read X;
	if [ ! -z "$X" ]; then 
		PREFIX="$X"; 
		BINDIR="$PREFIX/bin/";
		LIBDIR="$PREFIX/lib/";
		PERLDIR="$LIBDIR/perl5/";
		INCLUDEDIR="$PREFIX/include/";
		WEBDIR="$PREFIX/web";
		CGIDIR="$PREFIX/cgi-bin";
		ETCDIR="$PREFIX/etc";
		TEMPLATEDIR="$PREFIX/templates";
	fi

	prompt "Executables directory [$BINDIR] "
	read X; if [ ! -z "$X" ]; then BINDIR="$X"; fi;

	prompt "Lib directory [$LIBDIR] "
	read X; if [ ! -z "$X" ]; then LIBDIR="$X"; fi;

	prompt "Perl directory [$PERLDIR] "
	read X; if [ ! -z "$X" ]; then PERLDIR="$X"; fi;

	prompt "Include files directory [$INCLUDEDIR] "
	read X; if [ ! -z "$X" ]; then INCLUDEDIR="$X"; fi;

	prompt "Config files directory [$ETCDIR] "
	read X; if [ ! -z "$X" ]; then ETCDIR="$X"; fi;

	prompt "Web Root Directory [$WEBDIR] "
	read X; if [ ! -z "$X" ]; then WEBDIR="$X"; fi;

	prompt "Web CGI Directory [$CGIDIR] "
	read X; if [ ! -z "$X" ]; then CGIDIR="$X"; fi;

	prompt "Templates directory [$TEMPLATEDIR] "
	read X; if [ ! -z "$X" ]; then TEMPLATEDIR="$X"; fi;

	prompt "Apache2 apxs binary [$APXS2] "
	read X; if [ ! -z "$X" ]; then APXS2="$X"; fi;

	prompt "Apache2 headers directory [$APACHE2_HEADERS] "
	read X; if [ ! -z "$X" ]; then APACHE2_HEADERS="$X"; fi;

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

	writeConfig;
}

function prompt { echo ""; echo -n "$*"; }

function writeConfig {

	rm -f "$CONFIG_FILE";
	echo "Writing config to $CONFIG_FILE...";

	_write "PREFIX=\"$PREFIX\"";
	_write "BINDIR=\"$BINDIR\"";
	_write "LIBDIR=\"$LIBDIR\"";
	_write "PERLDIR=\"$PERLDIR\"";
	_write "INCLUDEDIR=\"$INCLUDEDIR\"";

	_write "TMP=\"$TMP\"";
	_write "APXS2=\"$APXS2\"";
	_write "APACHE2_HEADERS=\"$APACHE2_HEADERS\"";
	_write "LIBXML2_HEADERS=\"$LIBXML2_HEADERS\"";

	_write "WEBDIR=\"$WEBDIR\"";
	_write "TEMPLATEDIR=\"$TEMPLATEDIR\"";
	_write "ETCDIR=\"$ETCDIR\"";

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


	# Now we'll write out the DB bootstrapping config
	CONFIG_FILE='Open-ILS/src/cgi-bin/setup.pl';
	rm -f "$CONFIG_FILE";

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
	
	_write '$main::config{index} = "config.html";';


	prompt "To write a new config, run 'make config'";
	prompt "";

}

function _write {
	echo "$*" >> "$CONFIG_FILE";
}



buildConfig;
