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
# Prompts the user for config settings and writes a custom config
# file based on these settings
# --------------------------------------------------------------------


CONFIG_FILE="install.conf";
DEFAULT_CONFIG_FILE="install.conf.default";

function buildConfig {

	if [ -f "$CONFIG_FILE" ]; then
		echo "";
		echo "Using existing config file \"$CONFIG_FILE\""; 
		echo "To generate a new config, remove \"$CONFIG_FILE\"";
		echo "";
		sleep 3;	
		exit 0;
	fi


	if [ -f "$DEFAULT_CONFIG_FILE" ]; then
		source "$DEFAULT_CONFIG_FILE";
	fi;


	echo "";
	echo "-----------------------------------------------------------------------";
	echo "Type Enter to select the default"
	echo "-----------------------------------------------------------------------";

	prompt "Install prefix [$PREFIX] ";
	read X;
	if [ ! -z "$X" ]; then PREFIX="$X"; fi;

	prompt "Temporary files directory [$TMP] "
	read X;
	if [ ! -z "$X" ]; then TMP="$X"; fi;

	prompt "Apache2 apxs binary [$APXS2] "
	read X;
	if [ ! -z "$X" ]; then APXS2="$X"; fi;

	prompt "Apache2 headers directory [$APACHE2_HEADERS] "
	read X;
	if [ ! -z "$X" ]; then APACHE2_HEADERS="$X"; fi;

	prompt "Libxml2 headers directory [$LIBXML2_HEADERS] "
	read X;
	if [ ! -z "$X" ]; then LIBXML2_HEADERS="$X"; fi;

	prompt "Build targets [${TARGETS[@]:0}] "
	read X;
	if [ ! -z "$X" ]; then TARGETS=("$X"); fi;


	cat <<-WORDS

	-----------------------------------------------------------------------
	Verify the following install directories are sane.
	Note: * indicates that you must have write privelages for the location
	-----------------------------------------------------------------------

	-----------------------------------------------------------------------
	Install prefix             [$PREFIX]*
	Temporary files directory  [$TMP]*
	Apache2 apxs binary        [$APXS2]
	Apache2 headers directory  [$APACHE2_HEADERS]
	Libxml2 headers directory  [$LIBXML2_HEADERS]
	Build targets              [${TARGETS[@]:0}]
	-----------------------------------------------------------------------

	If these are not OK, use control-c to break out rerun this script.
	Otherwise, type enter.

	WORDS

	read OK;

	writeConfig;
}

function prompt { echo ""; echo -n "$*"; }

function writeConfig {

	rm -f "$CONFIG_FILE";
	echo "Writing config to $CONFIG_FILE...";

	_write "PREFIX=\"$PREFIX\"";
	_write "TMP=\"$TMP\"";
	_write "APXS2=\"$APXS2\"";
	_write "APACHE2_HEADERS=\"$APACHE2_HEADERS\"";
	_write "LIBXML2_HEADERS=\"$LIBXML2_HEADERS\"";

	# print out the targets
	STR="TARGETS=(";
	for target in ${TARGETS[@]:0}; do
		STR="$STR \"$target\"";
	done;
	STR="$STR)";
	_write "$STR";

	_write "OPENSRF_DIR=\"OpenSRF/src/\"";
	_write "OPENILS_DIR=\"Open-ILS/src/\"";
	_write "EVERGREEN_DIR=\"Evergreen/\"";

}

function _write {
	echo "$*" >> "$CONFIG_FILE";
}



buildConfig;
