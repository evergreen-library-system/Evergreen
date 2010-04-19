/**
	@file oils_qstore.c
	@brief As a server, perform database queries as defined in the database itself.
*/

#include <stdlib.h>
#include <string.h>
#include <ctype.h>
#include <dbi/dbi.h>
#include "opensrf/utils.h"
#include "opensrf/log.h"
#include "opensrf/osrf_json.h"
#include "opensrf/osrf_application.h"
#include "openils/oils_utils.h"
#include "openils/oils_sql.h"

static dbi_conn dbhandle; /* our db connection */

static const char modulename[] = "open-ils.qstore";

int doPrepare( osrfMethodContext* ctx );
int doExecute( osrfMethodContext* ctx );
int doSql( osrfMethodContext* ctx );

/**
	@brief Disconnect from the database.

	This function is called when the server drone is about to terminate.
*/
void osrfAppChildExit() {
	osrfLogDebug( OSRF_LOG_MARK, "Child is exiting, disconnecting from database..." );

	if ( dbhandle ) {
		dbi_conn_query( dbhandle, "ROLLBACK;" );
		dbi_conn_close( dbhandle );
		dbhandle = NULL;
	}
}

/**
	@brief Initialize the application.
	@return Zero if successful, or non-zero if not.

	Load the IDL file into an internal data structure for future reference.  Each non-virtual
	class in the IDL corresponds to a table or view in the database, or to a subquery defined
	in the IDL.  Ignore all virtual tables and virtual fields.

	Register the functions for remote procedure calls.

	This function is called when the registering the application, and is executed by the
	listener before spawning the drones.
*/
int osrfAppInitialize() {

	osrfLogInfo( OSRF_LOG_MARK, "Initializing the QStore Server..." );
	osrfLogInfo( OSRF_LOG_MARK, "Finding XML file..." );

	if ( !oilsIDLInit( osrf_settings_host_value( "/IDL" )))
		return 1; /* return non-zero to indicate error */

	growing_buffer* method_name = buffer_init( 64 );

	OSRF_BUFFER_ADD( method_name, modulename );
	OSRF_BUFFER_ADD( method_name, ".prepare" );
	osrfAppRegisterMethod( modulename, OSRF_BUFFER_C_STR( method_name ),
			"doBuild", "", 1, 0 );

	buffer_reset( method_name );
	OSRF_BUFFER_ADD( method_name, modulename );
	OSRF_BUFFER_ADD( method_name, ".execute" );
	osrfAppRegisterMethod( modulename, OSRF_BUFFER_C_STR( method_name ),
			"doExecute", "", 1, OSRF_METHOD_STREAMING );

	buffer_reset( method_name );
	OSRF_BUFFER_ADD( method_name, modulename );
	OSRF_BUFFER_ADD( method_name, ".sql" );
	osrfAppRegisterMethod( modulename, OSRF_BUFFER_C_STR( method_name ),
			"doSql", "", 1, OSRF_METHOD_STREAMING );

	return 0;
}

/**
	@brief Initialize a server drone.
	@return Zero if successful, -1 if not.

	Connect to the database.  For each non-virtual class in the IDL, execute a dummy "SELECT * "
	query to get the datatype of each column.  Record the datatypes in the loaded IDL.

	This function is called by a server drone shortly after it is spawned by the listener.
*/
int osrfAppChildInit() {

	osrfLogDebug( OSRF_LOG_MARK, "Attempting to initialize libdbi..." );
	dbi_initialize( NULL );
	osrfLogDebug( OSRF_LOG_MARK, "... libdbi initialized." );

	char* driver = osrf_settings_host_value( "/apps/%s/app_settings/driver", modulename );
	char* user   = osrf_settings_host_value( "/apps/%s/app_settings/database/user", modulename );
	char* host   = osrf_settings_host_value( "/apps/%s/app_settings/database/host", modulename );
	char* port   = osrf_settings_host_value( "/apps/%s/app_settings/database/port", modulename );
	char* db     = osrf_settings_host_value( "/apps/%s/app_settings/database/db", modulename );
	char* pw     = osrf_settings_host_value( "/apps/%s/app_settings/database/pw", modulename );

	osrfLogDebug( OSRF_LOG_MARK, "Attempting to load the database driver [%s]...", driver );
	dbhandle = dbi_conn_new( driver );

	if( !dbhandle ) {
		osrfLogError( OSRF_LOG_MARK, "Error loading database driver [%s]", driver );
		return -1;
	}
	osrfLogDebug( OSRF_LOG_MARK, "Database driver [%s] seems OK", driver );

	osrfLogInfo(OSRF_LOG_MARK, "%s connecting to database.  host=%s, "
			"port=%s, user=%s, db=%s", modulename, host, port, user, db );

	if( host ) dbi_conn_set_option( dbhandle, "host", host );
	if( port ) dbi_conn_set_option_numeric( dbhandle, "port", atoi( port ) );
	if( user ) dbi_conn_set_option( dbhandle, "username", user );
	if( pw )   dbi_conn_set_option( dbhandle, "password", pw );
	if( db )   dbi_conn_set_option( dbhandle, "dbname", db );

	free( user );
	free( host );
	free( port );
	free( db );
	free( pw );

	const char* err;
	if( dbi_conn_connect( dbhandle ) < 0 ) {
		sleep( 1 );
		if( dbi_conn_connect( dbhandle ) < 0 ) {
			dbi_conn_error( dbhandle, &err );
			osrfLogError( OSRF_LOG_MARK, "Error connecting to database: %s", err );
			return -1;
		}
	}

	oilsSetDBConnection( dbhandle );
	osrfLogInfo( OSRF_LOG_MARK, "%s successfully connected to the database", modulename );

	// Add datatypes from database to the fields in the IDL
	if( oilsExtendIDL() ) {
		osrfLogError( OSRF_LOG_MARK, "Error extending the IDL" );
		return -1;
	}
	else
		return 0;
}

int doPrepare( osrfMethodContext* ctx ) {
	if(osrfMethodVerifyContext( ctx )) {
		osrfLogError( OSRF_LOG_MARK,  "Invalid method context" );
		return -1;
	}

	// Get the query id from a method parameter
	const jsonObject* query_id_obj = jsonObjectGetIndex( ctx->params, 0 );
	if( query_id_obj->type != JSON_NUMBER ) {
		osrfAppSessionStatus( ctx->session, OSRF_STATUS_BADREQUEST, "osrfMethodException",
			ctx->request, "Invalid parameter; query id must be a number" );
		return -1;
	}
	int query_id = atoi( jsonObjectGetString( query_id_obj ));
	if( query_id <= 0 ) {
		osrfAppSessionStatus( ctx->session, OSRF_STATUS_BADREQUEST, "osrfMethodException",
			ctx->request, "Invalid parameter: query id must be greater than zero" );
		return -1;
	}

	osrfLogInfo( OSRF_LOG_MARK, "Building query for id # %d", query_id );

	osrfAppRespondComplete( ctx, jsonNewObject( "build method not yet implemented" ));
	return 0;
}

int doExecute( osrfMethodContext* ctx ) {
	if(osrfMethodVerifyContext( ctx )) {
		osrfLogError( OSRF_LOG_MARK,  "Invalid method context" );
		return -1;
	}

	// Get the query token
	const jsonObject* token_obj = jsonObjectGetIndex( ctx->params, 0 );
	if( token_obj->type != JSON_STRING ) {
		osrfAppSessionStatus( ctx->session, OSRF_STATUS_BADREQUEST, "osrfMethodException",
			ctx->request, "Invalid parameter; query id must be a string" );
		return -1;
	}
	const char* token = jsonObjectGetString( token_obj );

	// Get the list of bind variables, if there is one
	jsonObject* bind_map = jsonObjectGetIndex( ctx->params, 1 );
	if( bind_map && bind_map->type != JSON_HASH ) {
		osrfAppSessionStatus( ctx->session, OSRF_STATUS_BADREQUEST, "osrfMethodException",
			ctx->request, "Invalid parameter; bind map must be a JSON object" );
		return -1;
	}

	osrfLogInfo( OSRF_LOG_MARK, "Executing query for token \"%s\"", token );

	osrfAppRespondComplete( ctx, jsonNewObject( "execute method not yet implemented" ));
	return 0;
}

int doSql( osrfMethodContext* ctx ) {
	if(osrfMethodVerifyContext( ctx )) {
		osrfLogError( OSRF_LOG_MARK,  "Invalid method context" );
		return -1;
	}

	// Get the query token
	const jsonObject* token_obj = jsonObjectGetIndex( ctx->params, 0 );
	if( token_obj->type != JSON_STRING ) {
		osrfAppSessionStatus( ctx->session, OSRF_STATUS_BADREQUEST, "osrfMethodException",
			ctx->request, "Invalid parameter; query id must be a string" );
		return -1;
	}
	const char* token = jsonObjectGetString( token_obj );

	// Get the list of bind variables, if there is one
	jsonObject* bind_map = jsonObjectGetIndex( ctx->params, 1 );
	if( bind_map && bind_map->type != JSON_HASH ) {
		osrfAppSessionStatus( ctx->session, OSRF_STATUS_BADREQUEST, "osrfMethodException",
			ctx->request, "Invalid parameter; bind map must be a JSON object" );
		return -1;
	}

	osrfLogInfo( OSRF_LOG_MARK, "Returning SQL for token \"%s\"", token );

	osrfAppRespondComplete( ctx, jsonNewObject( "sql method not yet implemented" ));
	return 0;
}
