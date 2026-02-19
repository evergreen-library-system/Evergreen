/**
	@file test_qstore.c
	@brief Test driver for routines to build queries from tables in the query schema.

	This command-line utility exercises most of the code used in the qstore server, but
	without the complications of sending and receiving OSRF messages.

	Synopsis:

	test_qstore  [options]  query_id

	Query_id is the id of a row in the query.stored_query table, defining a stored query.

	The program reads the specified row in query.stored_query, along with associated rows
	in other tables, and displays the corresponding query as an SQL command.  Optionally it
	may execute the query, display the column names of the query result, and/or display the
	bind variables.

	In order to connect to the database, test_qstore uses various connection parameters
	that may be specified on the command line.  Any connection parameter not specified
	reverts to a plausible default.

	The database password may be read from a specified file or entered from the keyboard.

	Options:

	-b  Boolean; Display the name of any bind variables, and their default values.

	-D  Specifies the name of the database driver; defaults to "pgsql".

	-c  Boolean; display column names of the query results, as assigned by PostgreSQL.

	-d  Specifies the database name; defaults to "evergreen".

	-h  Specifies the hostname of the database; defaults to "localhost".

	-i  Specifies the name of the IDL file; defaults to "/openils/conf/fm_IDL.xml".

	-p  Specifies the port number of the database; defaults to 5432.

	-u  Specifies the database user name; defaults to "evergreen".

	-v  Boolean; Run in verbose mode, spewing various detailed messages.  This option is not
		likely to be useful unless you are troubleshooting the code that loads the stored
		query.

	-w  Specifies the name of a file containing the database password (no default).

	-x  Boolean: Execute the query and display the results.

	Copyright (C) 2010  Equinox Software Inc.
	Scott McKellar <scott@esilibrary.com>
*/

#include <stdlib.h>
#include <stdio.h>
#include <errno.h>
#include <ctype.h>
#include <unistd.h>
#include <termios.h>
#include <dbi/dbi.h>
#include "opensrf/utils.h"
#include "opensrf/string_array.h"
#include "opensrf/osrf_json.h"
#include "openils/oils_idl.h"
#include "openils/oils_buildq.h"

typedef struct {
	int new_argc;
	char ** new_argv;

	int   bind;
	char* driver;
	int   driver_found;
	char* database;
	int   database_found;
	char* host;
	int   host_found;
	char* idl;
	int   idl_found;
	unsigned long port;
	int   port_found;
	char* user;
	int   user_found;
	char* password_file;
	int   password_file_found;
	int   verbose;
	int   columns;
	int   execute;
} Opts;

static void show_bind_variables( osrfHash* vars );
static void show_msgs( const osrfStringArray* sa );
static dbi_conn connect_db( Opts* opts, dbi_inst* instance );
static int load_pw( growing_buffer* buf, FILE* in );
static int prompt_password( growing_buffer* buf );
static void initialize_opts( Opts * pOpts );
static int get_Opts( int argc, char * argv[], Opts * pOpts );

int main( int argc, char* argv[] ) {

	// Parse the command line
	printf( "\n" );
	Opts opts;
	if( get_Opts( argc, argv, &opts )) {
		fprintf( stderr, "Unable to parse command line\n" );
		return EXIT_FAILURE;
	}

	// Connect to the database
	dbi_inst instance;
	dbi_initialize_r(NULL, &instance);
	dbi_conn dbhandle = connect_db( &opts, &instance );
	if( NULL == dbhandle )
		return EXIT_FAILURE;

	if( opts.verbose )
		oilsStoredQSetVerbose();

	osrfLogSetLevel( OSRF_LOG_WARNING );

	// Load the IDL
	if ( !oilsIDLInit( opts.idl )) {
		fprintf( stderr, "Unable to load IDL at %s\n", opts.idl );
		return EXIT_FAILURE;
	}

	// Load the stored query
	BuildSQLState* state = buildSQLStateNew( dbhandle );
	state->defaults_usable = 1;
	state->values_required = 0;
	StoredQ* sq = getStoredQuery( state, atoi( opts.new_argv[ 1 ] ));

	if( !sq ) {
		show_msgs( state->error_msgs );
		printf( "Unable to build query\n" );
	} else {
		// If so requested, show the bind variables
		if( opts.bind )
			show_bind_variables( state->bindvar_list );

		// Build the SQL query
		if( buildSQL( state, sq )) {
			show_msgs( state->error_msgs );
			fprintf( stderr, "Unable to build SQL statement\n" );
		}
		else {
			printf( "%s\n", OSRF_BUFFER_C_STR( state->sql ));

			// If so requested, get the column names and display them
			if( opts.columns ) {
				jsonObject* cols = oilsGetColNames( state, sq );
				if( cols ) {
					printf( "Column names:\n" );
					char* cols_str = jsonObjectToJSON( cols );
					char* cols_out = jsonFormatString( cols_str );
					printf( "%s\n\n", cols_out );
					free( cols_out );
					free( cols_str );
					jsonObjectFree( cols );
				} else
					fprintf( stderr, "Unable to get column names\n\n" );
			}

			// If so requested, execute the query and display the results
			if( opts.execute ) {
				jsonObject* row = oilsFirstRow( state );
				if( state->error ) {
					show_msgs( state->error_msgs );
					fprintf( stderr, "Unable to execute query\n" );
				} else {
					printf( "[" );
					int first = 1;         // boolean
					while( row ) {

						if( first ) {
							printf( "\n\t" );
							first = 0;
						} else
							printf( ",\n\t" );

						char* json = jsonObjectToJSON( row );
						printf( "%s", json );
						free( json );
						row = oilsNextRow( state );
					}
					if( state->error ) {
						show_msgs( state->error_msgs );
						fprintf( stderr, "Unable to fetch row\n" );
					}
					printf( "\n]\n" );
				}
			}
		}
	}

	storedQFree( sq );
	buildSQLStateFree( state );

	buildSQLCleanup();
	if ( dbhandle )
		dbi_conn_close( dbhandle );

	return EXIT_SUCCESS;
}

/**
	@brief Display the bind variables.
	@param vars Pointer to a hash keyed on bind variable name.

	The data for each hash entry is a BindVar, a C struct whose members define the
	attributes of the bind variable.
*/
static void show_bind_variables( osrfHash* vars ) {
	printf( "Bind variables:\n\n" );
	BindVar* bind = NULL;
	osrfHashIterator* iter = osrfNewHashIterator( vars );

	// Traverse the hash of bind variables
	while(( bind = osrfHashIteratorNext( iter ))) {
		const char* type = NULL;
		switch( bind->type ) {
			case BIND_STR :
				type = "string";
				break;
			case BIND_NUM :
				type = "number";
				break;
			case BIND_STR_LIST :
				type = "string list";
				break;
			case BIND_NUM_LIST :
				type = "number list";
				break;
			default :
				type = "(unrecognized)";
				break;
		}

		// The default and actual values are in the form of jsonObjects.
		// Transform them back into raw JSON.
		char* default_value = NULL;
		if( bind->default_value )
			default_value = jsonObjectToJSONRaw( bind->default_value );

		char* actual_value = NULL;
		if( bind->actual_value )
			actual_value = jsonObjectToJSONRaw( bind->actual_value );

		// Display the attributes of the current bind variable.
		printf( "Name:    %s\n", bind->name );
		printf( "Label:   %s\n", bind->label );
		printf( "Type:    %s\n", type );
		printf( "Desc:    %s\n", bind->description ? bind->description : "(none)" );
		printf( "Default: %s\n", default_value ? default_value : "(none)" );
		printf( "Actual:  %s\n", actual_value ? actual_value : "(none)" );
		printf( "\n" );

		if( default_value )
			free( default_value );

		if( actual_value )
			free( actual_value );
	} // end while

	osrfHashIteratorFree( iter );
}

/**
	@brief Write a series of strings to standard output.
	@param sa Array of strings.

	Display messages emitted by the query-building machinery.
*/
static void show_msgs( const osrfStringArray* sa ) {
	if( sa ) {
		int i;
		for( i = 0; i < sa->size; ++i ) {
			const char* s = osrfStringArrayGetString( sa, i );
			if( s )
				printf( "%s\n", s );
		}
	}
}

/**
	@brief Connect to the database.
	@return If successful, a database handle; otherwise NULL;
*/
static dbi_conn connect_db( Opts* opts, dbi_inst* instance ) {
	// Get a database handle
	dbi_conn dbhandle = dbi_conn_new_r( opts->driver, *instance );
	if( !dbhandle ) {
		fprintf( stderr, "Error loading database driver [%s]", opts->driver );
		return NULL;
	}

	char* pw = NULL;
	growing_buffer* buf = osrf_buffer_init( 32 );

	// Get the database password, either from a designated file
	// or from the terminal.
	if( opts->password_file_found ) {
		FILE* pwfile = fopen( opts->password_file, "r" );
		if( !pwfile ) {
			fprintf( stderr, "Unable to open password file %s\n", opts->password_file );
			osrf_buffer_free( buf );
			return NULL;
		} else {
			if( load_pw( buf, pwfile )) {
				fprintf( stderr, "Unable to load password file %s\n", opts->password_file );
				osrf_buffer_free( buf );
				return NULL;
			} else
				pw = osrf_buffer_release( buf );
		}
	} else {
		if( prompt_password( buf )) {
			fprintf( stderr, "Unable to get password\n" );
			osrf_buffer_free( buf );
			return NULL;
		} else
			pw = osrf_buffer_release( buf );
	}

	// Set database connection options
	dbi_conn_set_option( dbhandle, "host", opts->host );
	dbi_conn_set_option_numeric( dbhandle, "port", opts->port );
	dbi_conn_set_option( dbhandle, "username", opts->user );
	dbi_conn_set_option( dbhandle, "password", pw );
	dbi_conn_set_option( dbhandle, "dbname", opts->database );

	// Connect to the database
	const char* err;
	if( dbi_conn_connect( dbhandle) < 0 ) {
		sleep( 1 );
		if ( dbi_conn_connect( dbhandle ) < 0 ) {
			dbi_conn_error( dbhandle, &err );
			fprintf( stderr, "Error connecting to database: %s", err );
			dbi_conn_close( dbhandle );
			free( pw );
			return NULL;
		}
	}

	free( pw );
	return dbhandle;
}

/**
	@brief Load one line from an input stream into a growing_buffer.
	@param buf Pointer to the receiving buffer.
	@param in Pointer to the input stream.
	@return 0 in all cases.  If there's ever a way to fail, return 1 for failure.

	Intended for use in loading a password.
*/
static int load_pw( growing_buffer* buf, FILE* in ) {
	osrf_buffer_reset( buf );
	while( 1 ) {
		int c = getc( in );
		if( '\n' == c || EOF == c )
			break;
		else if( '\b' == c )
			osrf_buffer_chomp( buf );
		else
			OSRF_BUFFER_ADD_CHAR( buf, c );
	}
	return 0;
}

/**
	@brief Read a password from the terminal, with echo turned off.
	@param buf Pointer to the receiving buffer.
	@return 0 if successful, or 1 if not.

	Read from /dev/tty if possible, or from stdin if not.
*/
static int prompt_password( growing_buffer* buf ) {
	struct termios oldterm;

	printf( "Password: " );
	fflush( stdout );

	FILE* term = fopen( "//dev//tty", "rw" );
	if( NULL == term )
		term = stdin;

	// Capture the current state of the terminal
	if( tcgetattr( fileno( term ), &oldterm ))
		return 1;

	// Turn off echo
	struct termios newterm = oldterm;
	newterm.c_lflag &= ~ECHO;
	if( tcsetattr( fileno( term ), TCSAFLUSH, &newterm ))
		return 1;

	// Read the password
	int rc = load_pw( buf, term );

	// Turn echo back on
	(void) tcsetattr( fileno( term ), TCSAFLUSH, &oldterm );  // restore echo

	if( term != stdin )
		fclose( term );

	return rc;
}

/**
	@brief Initialize an Opts structure.
	@param pOpts Pointer to the Opts to be initialized.
*/
static void initialize_opts( Opts * pOpts ) {
	pOpts->new_argc = 0;
	pOpts->new_argv = NULL;

	pOpts->bind = 0;
	pOpts->driver_found = 0;
	pOpts->driver = NULL;
	pOpts->database_found = 0;
	pOpts->database = NULL;
	pOpts->host_found = 0;
	pOpts->host = NULL;
	pOpts->idl_found = 0;
	pOpts->idl = NULL;
	pOpts->port_found = 0;
	pOpts->port = 0;
	pOpts->user_found = 0;
	pOpts->user = NULL;
	pOpts->password_file_found = 0;
	pOpts->password_file = NULL;
	pOpts->verbose = 0;
	pOpts->columns = 0;
	pOpts->execute = 0;
}

/**
	@brief Parse the command line.
	@param argc argc from the command line.
	@param argv argv from the command line.
	@param pOpts Pointer to the Opts to be populated.
	@return Zero if successful, or 1 if not.
*/
static int get_Opts( int argc, char * argv[], Opts * pOpts ) {
	int rc = 0; /* return code */
	unsigned long port_value = 0;
	char * tail = NULL;
	int opt;

	/* Define valid option characters */

	const char optstring[] = ":bD:cd:h:i:p:u:vw:x";

	/* Initialize members of struct */

	initialize_opts( pOpts );

	/* Suppress error messages from getopt() */

	opterr = 0;

	/* Examine command line options */

	while( ( opt = getopt( argc, argv, optstring )) != -1 )
	{
		switch( opt )
		{
			case 'b' :   /* Display bind variables */
				pOpts->bind = 1;
				break;
			case 'c' :   /* Display column names */
				pOpts->columns = 1;
				break;
			case 'D' :   /* Get database driver */
				if( pOpts->driver_found )
				{
					fprintf( stderr, "Only one occurrence of -D option allowed\n" );
					rc = 1;
					break;
				}
				pOpts->driver_found = 1;

				pOpts->driver = optarg;
				break;
			case 'd' :   /* Get database name */
				if( pOpts->database_found )
				{
					fprintf( stderr, "Only one occurrence of -d option allowed\n" );
					rc = 1;
					break;
				}
				pOpts->database_found = 1;

				pOpts->database = optarg;
				break;
			case 'h' :   /* Get hostname of database */
				if( pOpts->host_found )
				{
					fprintf( stderr, "Only one occurrence of -h option allowed\n" );
					rc = 1;
					break;
				}
				pOpts->host_found = 1;

				pOpts->host = optarg;
				break;
			case 'i' :   /* Get name of IDL file */
				if( pOpts->idl_found )
				{
					fprintf( stderr, "Only one occurrence of -i option allowed\n" );
					rc = 1;
					break;
				}
				pOpts->idl_found = 1;

				pOpts->idl = optarg;
				break;
			case 'p' :   /* Get port number of database */
				if( pOpts->port_found )
				{
					fprintf( stderr, "Only one occurrence of -p option allowed\n" );
					rc = 1;
					break;
				}
				pOpts->port_found = 1;

				/* Skip white space; check for negative */

				while( isspace( (unsigned char) *optarg ))
					++optarg;

				if( '-' == *optarg )
				{
					fprintf( stderr, "Negative argument not allowed for "
						"-p option: \"%s\"\n", optarg );
					rc = 1;
					break;
				}

				/* Convert to numeric value */

				errno = 0;
				port_value = strtoul( optarg, &tail, 10 );
				if( *tail != '\0' )
				{
					fprintf( stderr, "Invalid or non-numeric argument "
							"to -p option: \"%s\"\n", optarg );
					rc = 1;
					break;
				}
				else if( errno != 0 )
				{
					fprintf( stderr, "Too large argument "
						"to -p option: \"%s\"\n", optarg );
					rc = 1;
					break;
				}

				pOpts->port = port_value;
				break;
			case 'u' :   /* Get username of database account */
				if( pOpts->user_found )
				{
					fprintf( stderr, "Only one occurrence of -u option allowed\n" );
					rc = 1;
					break;
				}
				pOpts->user_found = 1;

				pOpts->user = optarg;
				break;
			case 'v' :   /* Set verbose mode */
				pOpts->verbose = 1;
				break;
			case 'w' :   /* Get name of password_file */
				if( pOpts->password_file_found )
				{
					fprintf( stderr, "Only one occurrence of -w option allowed\n" );
					rc = 1;
					break;
				}
				pOpts->password_file_found = 1;

				pOpts->password_file = optarg;
				break;
			case 'x' :   /* Set execute */
				pOpts->execute = 1;
				break;
			case ':' : /* Missing argument */
				fprintf( stderr, "Required argument missing on -%c option\n",
					 (char) optopt );
				rc = 1;
				break;
			case '?' : /* Invalid option */
				fprintf( stderr, "Invalid option '-%c' on command line\n",
					(char) optopt );
				rc = 1;
				break;
			default :  /* Programmer error */
				fprintf( stderr, "Internal error: unexpected value '-%c'"
						"for optopt", (char) optopt );
				rc = 1;
				break;
		} /* end switch */
	} /* end while */

	/* See if required options were supplied; apply defaults */

	if( ! pOpts->driver_found )
		pOpts->driver = "pgsql";

	if( ! pOpts->database_found )
		pOpts->database = "evergreen";

	if( ! pOpts->host_found )
		pOpts->host = "localhost";

	if( ! pOpts->idl_found )
		pOpts->idl = "/openils/conf/fm_IDL.xml";

	if( ! pOpts->port_found )
		pOpts->port = 5432;

	if( ! pOpts->user_found )
		pOpts->user = "evergreen";

	if( optind > argc )
	{
		/* This should never happen! */

		fprintf( stderr, "Program error: found more arguments than expected\n" );
		rc = 1;
	}
	else
	{
		/* Calculate new_argcv and new_argc to reflect */
		/* the number of arguments consumed */

		pOpts->new_argc = argc - optind + 1;
		pOpts->new_argv = argv + optind - 1;

		if( pOpts->new_argc < 2UL )
		{
			fprintf( stderr, "Not enough arguments beyond options; must be at least 1\n" );
			rc = 1;
		}
	}

	return rc;
}
