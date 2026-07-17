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
#include "openils/oils_buildq.h"

/**
	@brief Information about a previously prepared query.

	We store an osrfHash of CachedQueries in the userData area of the application session,
	keyed on query token.  That way we can fetch what a previous call to the prepare method
	has prepared.
*/
typedef struct {
	BuildSQLState* state;
	StoredQ*       query;
} CachedQuery;

static dbi_inst instance;
static dbi_conn dbhandle; /* our db connection */

static const char modulename[] = "open-ils.qstore";

int doPrepare( osrfMethodContext* ctx );
int doExecute( osrfMethodContext* ctx );
int doSql( osrfMethodContext* ctx );

static const char* save_query(
	osrfMethodContext* ctx, BuildSQLState* state, StoredQ* query );
static void free_cached_query( char* key, void* data );
static void userDataFree( void* blob );
static CachedQuery* search_token( osrfMethodContext* ctx, const char* token );

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

	if ( !oilsInitializeDbiInstance( &instance ) )
		return 1;

	// Set the SQL options.  Here the second and third parameters are irrelevant, but we need
	// to set the module name for use in error messages.
	oilsSetSQLOptions( modulename, 0, 100, 0 );

	growing_buffer* method_name = osrf_buffer_init( 64 );

	OSRF_BUFFER_ADD( method_name, modulename );
	OSRF_BUFFER_ADD( method_name, ".prepare" );
	osrfAppRegisterMethod( modulename, OSRF_BUFFER_C_STR( method_name ),
		"doPrepare", "", 1, 0 );

	osrf_buffer_reset( method_name );
	OSRF_BUFFER_ADD( method_name, modulename );
	OSRF_BUFFER_ADD( method_name, ".columns" );
	osrfAppRegisterMethod( modulename, OSRF_BUFFER_C_STR( method_name ),
		"doColumns", "", 1, 0 );

	osrf_buffer_reset( method_name );
	OSRF_BUFFER_ADD( method_name, modulename );
	OSRF_BUFFER_ADD( method_name, ".param_list" );
	osrfAppRegisterMethod( modulename, OSRF_BUFFER_C_STR( method_name ),
		"doParamList", "", 1, 0 );

	osrf_buffer_reset( method_name );
	OSRF_BUFFER_ADD( method_name, modulename );
	OSRF_BUFFER_ADD( method_name, ".bind_param" );
	osrfAppRegisterMethod( modulename, OSRF_BUFFER_C_STR( method_name ),
		"doBindParam", "", 2, 0 );

	osrf_buffer_reset( method_name );
	OSRF_BUFFER_ADD( method_name, modulename );
	OSRF_BUFFER_ADD( method_name, ".execute" );
	osrfAppRegisterMethod( modulename, OSRF_BUFFER_C_STR( method_name ),
		"doExecute", "", 1, OSRF_METHOD_STREAMING );

	osrf_buffer_reset( method_name );
	OSRF_BUFFER_ADD( method_name, modulename );
	OSRF_BUFFER_ADD( method_name, ".sql" );
	osrfAppRegisterMethod( modulename, OSRF_BUFFER_C_STR( method_name ),
		"doSql", "", 1, OSRF_METHOD_STREAMING );

	osrf_buffer_reset( method_name );
	OSRF_BUFFER_ADD( method_name, modulename );
	OSRF_BUFFER_ADD( method_name, ".finish" );
	osrfAppRegisterMethod( modulename, OSRF_BUFFER_C_STR( method_name ),
		"doFinish", "", 1, 0 );

	osrf_buffer_reset( method_name );
	OSRF_BUFFER_ADD( method_name, modulename );
	OSRF_BUFFER_ADD( method_name, ".messages" );
	osrfAppRegisterMethod( modulename, OSRF_BUFFER_C_STR( method_name ),
		"doMessages", "", 1, 0 );

	return 0;
}

/**
	@brief Initialize a server drone.
	@return Zero if successful, -1 if not.

	Connect to the database.  For each non-virtual class in the IDL, execute a dummy "SELECT * "
	query to get the datatype of each column.  Record the datatypes in the loaded IDL.

	This function is called by a server drone shortly after it is spawned by the listener.
*/
int osrfAppChildInit( void ) {

	dbhandle = oilsConnectDB( modulename, &instance );
	if( !dbhandle )
		return -1;
	else {
		oilsSetDBConnection( dbhandle );
		osrfLogInfo( OSRF_LOG_MARK, "%s successfully connected to the database", modulename );

		// Apply datatypes from database to the fields in the IDL
		//if( oilsExtendIDL() ) {
		//	osrfLogError( OSRF_LOG_MARK, "Error extending the IDL" );
		//	return -1;
		//}
		//else
		return 0;
	}
}

/**
	@brief Load a specified query from the database query tables.
	@param ctx Pointer to the current method context.
	@return Zero if successful, or -1 if not.

	Method parameters:
	- query id (key of query.stored_query table)

	Returns: a hash with two entries:
	- "token": A character string serving as a token for future references to the query.
	- "bind_variables" A hash of bind variables; see notes for doParamList().
*/
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

	osrfLogInfo( OSRF_LOG_MARK, "Loading query for id # %d", query_id );

	BuildSQLState* state = buildSQLStateNew( dbhandle );
	state->defaults_usable = 1;
	state->values_required = 0;
	StoredQ* query = getStoredQuery( state, query_id );
	if( state->error ) {
		osrfLogWarning( OSRF_LOG_MARK, "Unable to load stored query # %d", query_id );
		osrfAppSessionStatus( ctx->session, OSRF_STATUS_BADREQUEST, "osrfMethodException",
			ctx->request, "Unable to load stored query" );
		if( state->panic ) {
			osrfLogError( OSRF_LOG_MARK, sqlAddMsg( state, 
				"Database connection isn't working" ));
			osrfAppSessionPanic( ctx->session );
		}
		return -1;
	}

	const char* token = save_query( ctx, state, query );

	osrfLogInfo( OSRF_LOG_MARK, "Token for query id # %d is \"%s\"", query_id, token );

	// Build an object to return.  It will be a hash containing the query token and a
	// list of bind variables.
	jsonObject* returned_obj = jsonNewObjectType( JSON_HASH );
	jsonObjectSetKey( returned_obj, "token", jsonNewObject( token ));
	jsonObjectSetKey( returned_obj, "bind_variables",
		oilsBindVarList( state->bindvar_list ));

	osrfAppRespondComplete( ctx, returned_obj );
	return 0;
}

/**
	@brief Return a list of column names for the SELECT list.
	@param ctx Pointer to the current method context.
	@return Zero if successful, or -1 if not.

	Method parameters:
	- query token, as previously returned by the .prepare method.

	Returns: An array of column names; unavailable names are represented as nulls.
*/
int doColumns( osrfMethodContext* ctx ) {
	if(osrfMethodVerifyContext( ctx )) {
		osrfLogError( OSRF_LOG_MARK,  "Invalid method context" );
		return -1;
	}

	// Get the query token from a method parameter
	const jsonObject* token_obj = jsonObjectGetIndex( ctx->params, 0 );
	if( token_obj->type != JSON_STRING ) {
		osrfAppSessionStatus( ctx->session, OSRF_STATUS_BADREQUEST, "osrfMethodException",
			ctx->request, "Invalid parameter; query token must be a string" );
		return -1;
	}
	const char* token = jsonObjectGetString( token_obj );

	// Look up the query token in the session-level userData
	CachedQuery* query = search_token( ctx, token );
	if( !query ) {
		osrfAppSessionStatus( ctx->session, OSRF_STATUS_BADREQUEST, "osrfMethodException",
			ctx->request, "Invalid query token" );
		return -1;
	}

	osrfLogInfo( OSRF_LOG_MARK, "Listing column names for token %s", token );

	jsonObject* col_list = oilsGetColNames( query->state, query->query );
	if( query->state->error ) {
		osrfAppSessionStatus( ctx->session, OSRF_STATUS_BADREQUEST, "osrfMethodException",
			ctx->request, "Unable to get column names" );
		if( query->state->panic ) {
			osrfLogError( OSRF_LOG_MARK, sqlAddMsg( query->state,
				"Database connection isn't working" ));
			osrfAppSessionPanic( ctx->session );
		}
		return -1;
	} else {
		osrfAppRespondComplete( ctx, col_list );
		return 0;
	}
}

/**
	@brief Implement the param_list method.
	@param ctx Pointer to the current method context.
	@return Zero if successful, or -1 if not.

	Provide a list of bind variables for a specified query, along with their various
	attributes.

	Method parameters:
	- query token, as previously returned by the .prepare method.

	Returns: A (possibly empty) JSON_HASH, keyed on the names of the bind variables.
	The data for each is another level of JSON_HASH with a fixed set of tags:
	- "label"
	- "type"
	- "description"
	- "default_value" (as a jsonObject)
	- "actual_value" (as a jsonObject)

	Any non-existent values are represented as JSON_NULLs.
*/
int doParamList( osrfMethodContext* ctx ) {
	if(osrfMethodVerifyContext( ctx )) {
		osrfLogError( OSRF_LOG_MARK,  "Invalid method context" );
		return -1;
	}

	// Get the query token from a method parameter
	const jsonObject* token_obj = jsonObjectGetIndex( ctx->params, 0 );
	if( token_obj->type != JSON_STRING ) {
		osrfAppSessionStatus( ctx->session, OSRF_STATUS_BADREQUEST, "osrfMethodException",
			ctx->request, "Invalid parameter; query token must be a string" );
		return -1;
	}
	const char* token = jsonObjectGetString( token_obj );

	// Look up the query token in the session-level userData
	CachedQuery* query = search_token( ctx, token );
	if( !query ) {
		osrfAppSessionStatus( ctx->session, OSRF_STATUS_BADREQUEST, "osrfMethodException",
			ctx->request, "Invalid query token" );
		return -1;
	}

	osrfLogInfo( OSRF_LOG_MARK, "Returning list of bind variables for token %s", token );

	osrfAppRespondComplete( ctx, oilsBindVarList( query->state->bindvar_list ) );
	return 0;
}

/**
	@brief Implement the bind_param method.
	@param ctx Pointer to the current method context.
	@return Zero if successful, or -1 if not.

	Apply values to bind variables, overriding the defaults, if any.

	Method parameters:
	- query token, as previously returned by the .prepare method.
	- hash of bind variable values, keyed on bind variable names.

	Returns: Nothing.
*/
int doBindParam( osrfMethodContext* ctx ) {
	if(osrfMethodVerifyContext( ctx )) {
		osrfLogError( OSRF_LOG_MARK,  "Invalid method context" );
		return -1;
	}

	// Get the query token from a method parameter
	const jsonObject* token_obj = jsonObjectGetIndex( ctx->params, 0 );
	if( token_obj->type != JSON_STRING ) {
		osrfAppSessionStatus( ctx->session, OSRF_STATUS_BADREQUEST, "osrfMethodException",
			ctx->request, "Invalid parameter; query token must be a string" );
		return -1;
	}
	const char* token = jsonObjectGetString( token_obj );

	// Look up the query token in the session-level userData
	CachedQuery* query = search_token( ctx, token );
	if( !query ) {
		osrfAppSessionStatus( ctx->session, OSRF_STATUS_BADREQUEST, "osrfMethodException",
			ctx->request, "Invalid query token" );
		return -1;
	}

	osrfLogInfo( OSRF_LOG_MARK, "Binding parameter(s) for token %s", token );

	jsonObject* bindings = jsonObjectGetIndex( ctx->params, 1 );
	if( !bindings ) {
		osrfAppSessionStatus( ctx->session, OSRF_STATUS_BADREQUEST, "osrfMethodException",
			ctx->request, "No parameter provided for bind variable values" );
		return -1;
	} else if( bindings->type != JSON_HASH ) {
		osrfAppSessionStatus( ctx->session, OSRF_STATUS_BADREQUEST, "osrfMethodException",
			ctx->request, "Invalid parameter for bind variable values: not a hash" );
		return -1;
	}

	if( 0 == bindings->size ) {
		// No values to assign; we're done.
		osrfAppRespondComplete( ctx, NULL );
		return 0;
	}

	osrfHash* bindvar_list = query->state->bindvar_list;
	if( !bindvar_list || osrfHashGetCount( bindvar_list ) == 0 ) {
		osrfAppSessionStatus( ctx->session, OSRF_STATUS_BADREQUEST, "osrfMethodException",
			ctx->request, "There are no bind variables to which to assign values" );
		return -1;
	}

	if( oilsApplyBindValues( query->state, bindings )) {
		osrfAppSessionStatus( ctx->session, OSRF_STATUS_BADREQUEST, "osrfMethodException",
			ctx->request, "Unable to apply values to bind variables" );
		return -1;
	} else {
		osrfAppRespondComplete( ctx, NULL );
		return 0;
	}
}

/**
	@brief Execute an SQL query and return a result set.
	@param ctx Pointer to the current method context.
	@return Zero if successful, or -1 if not.

	Method parameters:
	- query token, as previously returned by the .prepare method.

	Returns: A series of responses, each of them a row represented as an array of column values.
*/
int doExecute( osrfMethodContext* ctx ) {
	if(osrfMethodVerifyContext( ctx )) {
		osrfLogError( OSRF_LOG_MARK,  "Invalid method context" );
		return -1;
	}

	// Get the query token
	const jsonObject* token_obj = jsonObjectGetIndex( ctx->params, 0 );
	if( token_obj->type != JSON_STRING ) {
		osrfAppSessionStatus( ctx->session, OSRF_STATUS_BADREQUEST, "osrfMethodException",
			ctx->request, "Invalid parameter; query token must be a string" );
		return -1;
	}
	const char* token = jsonObjectGetString( token_obj );

	// Look up the query token in the session-level userData
	CachedQuery* query = search_token( ctx, token );
	if( !query ) {
		osrfAppSessionStatus( ctx->session, OSRF_STATUS_BADREQUEST, "osrfMethodException",
			ctx->request, "Invalid query token" );
		return -1;
	}

	osrfLogInfo( OSRF_LOG_MARK, "Executing query for token \"%s\"", token );
	if( query->state->error ) {
		osrfLogWarning( OSRF_LOG_MARK, sqlAddMsg( query->state,
			"No valid prepared query available for query id # %d", query->query->id ));
		osrfAppSessionStatus( ctx->session, OSRF_STATUS_BADREQUEST, "osrfMethodException",
							  ctx->request, "No valid prepared query available" );
		return -1;
	} else if( buildSQL( query->state, query->query )) {
		osrfLogWarning( OSRF_LOG_MARK, sqlAddMsg( query->state,
			"Unable to build SQL statement for query id # %d", query->query->id ));
		osrfAppSessionStatus( ctx->session, OSRF_STATUS_BADREQUEST, "osrfMethodException",
			ctx->request, "Unable to build SQL statement" );
		return -1;
	}

	jsonObject* row = oilsFirstRow( query->state );
	while( row ) {
		osrfAppRespond( ctx, row );
		row = oilsNextRow( query->state );
	}

	if( query->state->error ) {
		osrfLogWarning( OSRF_LOG_MARK, sqlAddMsg( query->state,
			"Unable to execute SQL statement for query id # %d", query->query->id ));
		osrfAppSessionStatus( ctx->session, OSRF_STATUS_BADREQUEST, "osrfMethodException",
			ctx->request, "Unable to execute SQL statement" );
		if( query->state->panic ) {
			osrfLogError( OSRF_LOG_MARK, sqlAddMsg( query->state,
				"Database connection isn't working" ));
			osrfAppSessionPanic( ctx->session );
		}
		return -1;
	}

	osrfAppRespondComplete( ctx, NULL );
	return 0;
}

/**
	@brief Construct an SQL query, but without executing it.
	@param ctx Pointer to the current method context.
	@return Zero if successful, or -1 if not.

	Method parameters:
	- query token, as previously returned by the .prepare method.

	Returns: A string containing an SQL query..
*/
int doSql( osrfMethodContext* ctx ) {
	if(osrfMethodVerifyContext( ctx )) {
		osrfLogError( OSRF_LOG_MARK,  "Invalid method context" );
		return -1;
	}

	// Get the query token
	const jsonObject* token_obj = jsonObjectGetIndex( ctx->params, 0 );
	if( token_obj->type != JSON_STRING ) {
		osrfAppSessionStatus( ctx->session, OSRF_STATUS_BADREQUEST, "osrfMethodException",
			ctx->request, "Invalid parameter; query token must be a string" );
		return -1;
	}
	const char* token = jsonObjectGetString( token_obj );

	// Look up the query token in the session-level userData
	CachedQuery* query = search_token( ctx, token );
	if( !query ) {
		osrfAppSessionStatus( ctx->session, OSRF_STATUS_BADREQUEST, "osrfMethodException",
			ctx->request, "Invalid query token" );
		return -1;
	}

	osrfLogInfo( OSRF_LOG_MARK, "Returning SQL for token \"%s\"", token );
	if( query->state->error ) {
		osrfLogWarning( OSRF_LOG_MARK, sqlAddMsg( query->state,
			"No valid prepared query available for query id # %d", query->query->id ));
		osrfAppSessionStatus( ctx->session, OSRF_STATUS_BADREQUEST, "osrfMethodException",
			ctx->request, "No valid prepared query available" );
		return -1;
	} else if( buildSQL( query->state, query->query )) {
		osrfLogWarning( OSRF_LOG_MARK, sqlAddMsg( query->state,
			"Unable to build SQL statement for query id # %d", query->query->id ));
		osrfAppSessionStatus( ctx->session, OSRF_STATUS_BADREQUEST, "osrfMethodException",
			ctx->request, "Unable to build SQL statement" );
		return -1;
	}

	osrfAppRespondComplete( ctx, jsonNewObject( OSRF_BUFFER_C_STR( query->state->sql )));
	return 0;
}

/**
	@brief Return a list of previously generated error messages for a specified query.
	@param ctx Pointer to the current method context.
	@return Zero if successful, or -1 if not.

	Method parameters:
	- query token, as previously returned by the .prepare method.

	Returns: A (possibly empty) array of strings, each one an error message generated during
	previous operations in connection with the specified query.
*/
int doMessages( osrfMethodContext* ctx ) {
	if(osrfMethodVerifyContext( ctx )) {
		osrfLogError( OSRF_LOG_MARK,  "Invalid method context" );
		return -1;
	}

	// Get the query token from a method parameter
	const jsonObject* token_obj = jsonObjectGetIndex( ctx->params, 0 );
	if( token_obj->type != JSON_STRING ) {
		osrfAppSessionStatus( ctx->session, OSRF_STATUS_BADREQUEST, "osrfMethodException",
			ctx->request, "Invalid parameter; query token must be a string" );
		return -1;
	}
	const char* token = jsonObjectGetString( token_obj );

	// Look up the query token in the session-level userData
	CachedQuery* query = search_token( ctx, token );
	if( !query ) {
		osrfAppSessionStatus( ctx->session, OSRF_STATUS_BADREQUEST, "osrfMethodException",
			ctx->request, "Invalid query token" );
		return -1;
	}

	osrfLogInfo( OSRF_LOG_MARK, "Returning messages for token %s", token );

	jsonObject* msgs = jsonNewObjectType( JSON_ARRAY );
	const osrfStringArray* error_msgs = query->state->error_msgs;
	int i;
	for( i = 0; i < error_msgs->size; ++i ) {
		jsonObject* msg = jsonNewObject( osrfStringArrayGetString( error_msgs, i ));
		jsonObjectPush( msgs, msg );
	}

	osrfAppRespondComplete( ctx, msgs );
	return 0;
}

/**
	@brief Discard a previously stored query, as identified by a token.
	@param ctx Pointer to the current method context.
	@return Zero if successful, or -1 if not.

	Method parameters:
	- query token, as previously returned by the .prepare method.

	Returns: Nothing.
*/
int doFinish( osrfMethodContext* ctx ) {
	if(osrfMethodVerifyContext( ctx )) {
		osrfLogError( OSRF_LOG_MARK,  "Invalid method context" );
		return -1;
	}

	// Get the query token.
	const jsonObject* token_obj = jsonObjectGetIndex( ctx->params, 0 );
	if( token_obj->type != JSON_STRING ) {
		osrfAppSessionStatus( ctx->session, OSRF_STATUS_BADREQUEST, "osrfMethodException",
							  ctx->request, "Invalid parameter; query token must be a string" );
		return -1;
	}
	const char* token = jsonObjectGetString( token_obj );

	// Delete the corresponding entry from the cache.  If there is no cache, or no such entry,
	// just ignore the problem and report success.
	osrfHash* cache = ctx->session->userData;
	if( cache )
		osrfHashRemove( cache, token );

	osrfAppRespondComplete( ctx, NULL );
	return 0;
}

/**
	@brief Save a query in session-level userData for reference in future method calls.
	@param ctx Pointer to the current method context.
	@param state Pointer to the state of the query.
	@param query Pointer to the abstract representation of the query.
	@return Pointer to an identifying token to be returned to the client.
*/
static const char* save_query(
	osrfMethodContext* ctx, BuildSQLState* state, StoredQ* query ) {

	CachedQuery* cached_query = safe_malloc( sizeof( CachedQuery ));
	cached_query->state       = state;
	cached_query->query       = query;

	// Get the cache.  If we don't have one yet, make one.
	osrfHash* cache = ctx->session->userData;
	if( !cache ) {
		cache = osrfNewHash();
		osrfHashSetCallback( cache, free_cached_query );
		ctx->session->userData = cache;
		ctx->session->userDataFree = userDataFree;  // arrange to free it at end of session
	}

	// Create a token string to be used as a key
	static unsigned int token_count = 0;
	char* token = va_list_to_string(
		"%u_%ld_%ld", ++token_count, (long) time( NULL ), (long) getpid() );

	osrfHashSet( cache, cached_query, token );
	return token;
}

/**
	@brief Free a CachedQuery
	@param Pointer to the CachedQuery to be freed.
*/
static void free_cached_query( char* key, void* data ) {
	if( data ) {
		CachedQuery* cached_query = data;
		buildSQLStateFree( cached_query->state );
		storedQFree( cached_query->query );
	}
}

/**
	@brief Callback for freeing session-level userData.
	@param blob Opaque pointer t userData.
*/
static void userDataFree( void* blob ) {
	osrfHashFree( (osrfHash*) blob );
}

/**
	@brief Search for the cached query corresponding to a given token.
	@param ctx Pointer to the current method context.
	@param token Token string from a previous call to the prepare method.
	@return A pointer to the cached query, if found, or NULL if not.
*/
static CachedQuery* search_token( osrfMethodContext* ctx, const char* token ) {
	if( ctx && ctx->session->userData && token ) {
		osrfHash* cache = ctx->session->userData;
		return osrfHashGet( cache, token );
	} else
		return NULL;
}
