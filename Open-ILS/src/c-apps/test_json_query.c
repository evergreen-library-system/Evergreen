/*
Copyright (C) 2009  Georgia Public Library Service 
Scott McKellar <scott@esilibrary.com>

	This program is free software; you can redistribute it and/or
	modify it under the terms of the GNU General Public License
	as published by the Free Software Foundation; either version 2
	of the License, or (at your option) any later version.

	This program is distributed in the hope that it will be useful,
	but WITHOUT ANY WARRANTY; without even the implied warranty of
	MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
	GNU General Public License for more details.

	Description : Translates a JSON query into SQL and writes the
	results to standard output.  Synopsis:

	test_json_query [-i IDL_file] [-f file_name] [-v] query
	
	-i supplies the name of the IDL file.  If no IDL file is specified,
	   json_test_query uses the value of the environmental variable
	   OILS_IDL_FILENAME, if it is defined, or defaults to
	   "/openils/conf/fm_IDL.xml".

	-f supplies the name of a text file containing the JSON query to
	   be translated.  A file name constisting of a single hyphen
	   denotes standard input.  If this option is present, all
	   non-option arguments are ignored.

	-v verbose; outputs the name of the IDL file and the text of the
	   JSON query.

	If there is no -f option supplied, json_query translates the 
	first non-option parameter.  This parameter is subject to the
	usual mangling by the shell.  In most cases it will be sufficient
	to enclose it in single quotes, but of course any single quotes
	embedded within the query will need to be escaped.
*/

#include <stdlib.h>
#include <stdio.h>
#include <unistd.h>
#include <dbi/dbi.h>
#include "opensrf/utils.h"
#include "opensrf/osrf_json.h"
#include "opensrf/osrf_application.h"
#include "opensrf/osrf_app_session.h"
#include "openils/oils_idl.h"
#include "openils/oils_sql.h"

#define DISABLE_I18N    2
#define SELECT_DISTINCT 1

static int obj_is_true( const jsonObject* obj );
static int test_json_query( const char* json_query );
static char* load_query( const char* filename );

int main( int argc, char* argv[] ) {

	// Parse command line

	const char* idl_file_name = NULL;
	const char* query_file_name = NULL;
	int verbose = 0;                        // boolean

	int opt;
	opterr = 0;
	const char optstring[] = ":f:i:v";

	while( ( opt = getopt( argc, argv, optstring ) ) != -1 ) {
		switch( opt )
		{
			case 'f' :  // get file name of query
				if( query_file_name ) {
					fprintf( stderr, "Multiple input files not allowed\n" );
					return EXIT_FAILURE;
				}
				else
					query_file_name = optarg;
				break;
			case 'i' :  // get name of IDL file
				if( idl_file_name ) {
					fprintf( stderr, "Multiple IDL file names not allowed\n" );
					return EXIT_FAILURE;
				}
				else
					idl_file_name = optarg;
				break;
			case 'v' :  // Verbose
				verbose = 1;
				break;
			case '?' :  // Invalid option
				fprintf( stderr, "Invalid option '-%c' on command line\n",
						 (char) optopt );
				return EXIT_FAILURE;
			default :  // Huh?
				fprintf( stderr, "Internal error: unexpected value '%c'"
						"for optopt", (char) optopt );
				return EXIT_FAILURE;

		}
	}

	// If the command line doesn't specify an IDL file, get it
	// from an environmental variable, or apply a default
	if( NULL == idl_file_name ) {
		idl_file_name = getenv( "OILS_IDL_FILENAME" );
		if( NULL == idl_file_name )
			idl_file_name = "/openils/conf/fm_IDL.xml";
	}

	if( verbose )
		printf( "IDL file: %s\n", idl_file_name );

	char* loaded_json = NULL;
	const char* json_query = NULL;

	// Get the JSON query into a string
	if( query_file_name ) {   // Got a file?  Load it
		if( optind < argc )
			fprintf( stderr, "Extra parameter(s) ignored\n" );
		loaded_json = load_query( query_file_name );
		if( !loaded_json )
			return EXIT_FAILURE;
		json_query = loaded_json;
	} else {                  // No file?  Use command line parameter
		if ( optind == argc ) {
			fprintf( stderr, "No JSON query specified\n" );
			return EXIT_FAILURE;
		} else
			json_query = argv[ optind ];
	}

	if( verbose )
		printf( "JSON query: %s\n", json_query );

	osrfLogSetLevel( OSRF_LOG_WARNING );    // Suppress informational messages
	(void) oilsIDLInit( idl_file_name );    // Load IDL into memory

	// Load a database driver, connect to it, and install the connection in
	// the cstore module.  We don't actually connect to a database, but we
	// need the driver to process quoted strings correctly.
	dbi_inst instance;
	if( dbi_initialize_r( NULL, &instance ) < 0 ) {
		printf( "Unable to load database driver\n" );
		return EXIT_FAILURE;
	};

	dbi_conn conn = dbi_conn_new_r( "pgsql", instance );  // change string if ever necessary
	if( !conn ) {
		printf( "Unable to establish dbi connection\n" );
		dbi_shutdown_r(instance);
		return EXIT_FAILURE;
	}

	oilsSetDBConnection( conn );

	// The foregoing is an inelegant kludge.  The true, proper, and uniquely
	// correct thing to do is to load the system settings and then call
	// osrfAppInitialize() and osrfAppChildInit().  Maybe we'll actually
	// do that some day, but this will do for now.

	// Translate the JSON into SQL
	int rc = test_json_query( json_query );

	dbi_conn_close( conn );
	dbi_shutdown_r( instance );
	if( loaded_json )
		free( loaded_json );

	return rc ? EXIT_FAILURE : EXIT_SUCCESS;
}

static int test_json_query( const char* json_query ) {

	jsonObject* hash = jsonParse( json_query );
	if( !hash ) {
		fprintf( stderr, "Invalid JSON\n" );
		return -1;
	}

	int flags = 0;

	if ( obj_is_true( jsonObjectGetKeyConst( hash, "distinct" )))
		flags |= SELECT_DISTINCT;

	if ( obj_is_true( jsonObjectGetKeyConst( hash, "no_i18n" )))
		flags |= DISABLE_I18N;

	char* sql_query = buildQuery( NULL, hash, flags );

	if ( !sql_query ) {
		fprintf( stderr, "Invalid query\n" );
		return -1;
	}
	else
		printf( "%s\n", sql_query );

	free( sql_query );
	jsonObjectFree( hash );
	return 0;
}

// Interpret a jsonObject as true or false
static int obj_is_true( const jsonObject* obj ) {
	if( !obj )
		return 0;
	else switch( obj->type )
	{
		case JSON_BOOL :
			if( obj->value.b )
				return 1;
			else
				return 0;
		case JSON_STRING :
			if( strcasecmp( obj->value.s, "true" ) )
				return 0;
			else
				return 1;
			case JSON_NUMBER :          // Support 1/0 for perl's sake
				if( jsonObjectGetNumber( obj ) == 1.0 )
					return 1;
				else
					return 0;
		default :
			return 0;
	}
}

static char* load_query( const char* filename ) {
	FILE* fp;

	// Sanity check
	if( ! filename || ! *filename ) {
		fprintf( stderr, "Name of query file is empty or missing\n" );
		return NULL;
	}

	// Open query file, or use standard input
	if( ! strcmp( filename, "-" ) )
		fp = stdin;
	else {
		fp = fopen( filename, "r" );
		if( !fp ) {
			fprintf( stderr, "Unable to open query file \"%s\"\n", filename );
			return NULL;
		}
	}

	// Load file into a growing_buffer
	size_t num_read;
	char buf[ BUFSIZ + 1 ];
	growing_buffer* gb = osrf_buffer_init( sizeof( buf ) );

	while( ( num_read = fread( buf, 1, sizeof( buf ) - 1, fp ) ) ) {
		buf[ num_read ] = '\0';
		osrf_buffer_add( gb, buf );
	}

	if( fp != stdin )
		fclose( fp );

	return osrf_buffer_release( gb );
}
