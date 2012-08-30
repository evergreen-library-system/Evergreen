/**
	@file oils_sql.c
	@brief Utility routines for translating JSON into SQL.
*/

#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <ctype.h>
#include <dbi/dbi.h>
#include "opensrf/utils.h"
#include "opensrf/log.h"
#include "opensrf/osrf_application.h"
#include "openils/oils_utils.h"
#include "openils/oils_sql.h"

// The next four macros are OR'd together as needed to form a set
// of bitflags.  SUBCOMBO enables an extra pair of parentheses when
// nesting one UNION, INTERSECT or EXCEPT inside another.
// SUBSELECT tells us we're in a subquery, so don't add the
// terminal semicolon yet.
#define SUBCOMBO    8
#define SUBSELECT   4
#define DISABLE_I18N    2
#define SELECT_DISTINCT 1

#define AND_OP_JOIN     0
#define OR_OP_JOIN      1

struct ClassInfoStruct;
typedef struct ClassInfoStruct ClassInfo;

#define ALIAS_STORE_SIZE 16
#define CLASS_NAME_STORE_SIZE 16

struct ClassInfoStruct {
	char* alias;
	char* class_name;
	char* source_def;
	osrfHash* class_def;      // Points into IDL
	osrfHash* fields;         // Points into IDL
	osrfHash* links;          // Points into IDL

	// The remaining members are private and internal.  Client code should not
	// access them directly.

	ClassInfo* next;          // Supports linked list of joined classes
	int in_use;               // boolean

	// We usually store the alias and class name in the following arrays, and
	// point the corresponding pointers at them.  When the string is too big
	// for the array (which will probably never happen in practice), we strdup it.

	char alias_store[ ALIAS_STORE_SIZE + 1 ];
	char class_name_store[ CLASS_NAME_STORE_SIZE + 1 ];
};

struct QueryFrameStruct;
typedef struct QueryFrameStruct QueryFrame;

struct QueryFrameStruct {
	ClassInfo core;
	ClassInfo* join_list;  // linked list of classes joined to the core class
	QueryFrame* next;      // implements stack as linked list
	int in_use;            // boolean
};

static int timeout_needs_resetting;
static time_t time_next_reset;

static int verifyObjectClass ( osrfMethodContext*, const jsonObject* );

static void setXactId( osrfMethodContext* ctx );
static inline const char* getXactId( osrfMethodContext* ctx );
static inline void clearXactId( osrfMethodContext* ctx );

static jsonObject* doFieldmapperSearch ( osrfMethodContext* ctx, osrfHash* class_meta,
		jsonObject* where_hash, jsonObject* query_hash, int* err );
static jsonObject* oilsMakeFieldmapperFromResult( dbi_result, osrfHash* );
static jsonObject* oilsMakeJSONFromResult( dbi_result );

static char* searchSimplePredicate ( const char* op, const char* class_alias,
				osrfHash* field, const jsonObject* node );
static char* searchFunctionPredicate ( const char*, osrfHash*, const jsonObject*, const char* );
static char* searchFieldTransform ( const char*, osrfHash*, const jsonObject* );
static char* searchFieldTransformPredicate ( const ClassInfo*, osrfHash*, const jsonObject*,
		const char* );
static char* searchBETWEENPredicate ( const char*, osrfHash*, const jsonObject* );
static char* searchINPredicate ( const char*, osrfHash*,
								 jsonObject*, const char*, osrfMethodContext* );
static char* searchPredicate ( const ClassInfo*, osrfHash*, jsonObject*, osrfMethodContext* );
static char* searchJOIN ( const jsonObject*, const ClassInfo* left_info );
static char* searchWHERE ( const jsonObject* search_hash, const ClassInfo*, int, osrfMethodContext* );
static char* buildSELECT( const jsonObject*, jsonObject* rest_of_query,
	osrfHash* meta, osrfMethodContext* ctx );
static char* buildOrderByFromArray( osrfMethodContext* ctx, const jsonObject* order_array );

char* buildQuery( osrfMethodContext* ctx, jsonObject* query, int flags );

char* SELECT ( osrfMethodContext*, jsonObject*, const jsonObject*, const jsonObject*,
	const jsonObject*, const jsonObject*, const jsonObject*, const jsonObject*, int );

static osrfStringArray* getPermLocationCache( osrfMethodContext*, const char* );
static void setPermLocationCache( osrfMethodContext*, const char*, osrfStringArray* );

void userDataFree( void* );
static void sessionDataFree( char*, void* );
static void pcacheFree( char*, void* );
static int obj_is_true( const jsonObject* obj );
static const char* json_type( int code );
static const char* get_primitive( osrfHash* field );
static const char* get_datatype( osrfHash* field );
static void pop_query_frame( void );
static void push_query_frame( void );
static int add_query_core( const char* alias, const char* class_name );
static inline ClassInfo* search_alias( const char* target );
static ClassInfo* search_all_alias( const char* target );
static ClassInfo* add_joined_class( const char* alias, const char* classname );
static void clear_query_stack( void );

static const jsonObject* verifyUserPCRUD( osrfMethodContext* );
static int verifyObjectPCRUD( osrfMethodContext*, osrfHash*, const jsonObject*, int );
static const char* org_tree_root( osrfMethodContext* ctx );
static jsonObject* single_hash( const char* key, const char* value );

static int child_initialized = 0;   /* boolean */

static dbi_conn writehandle; /* our MASTER db connection */
static dbi_conn dbhandle; /* our CURRENT db connection */
//static osrfHash * readHandles;

// The following points to the top of a stack of QueryFrames.  It's a little
// confusing because the top level of the query is at the bottom of the stack.
static QueryFrame* curr_query = NULL;

static dbi_conn writehandle; /* our MASTER db connection */
static dbi_conn dbhandle; /* our CURRENT db connection */
//static osrfHash * readHandles;

static int max_flesh_depth = 100;

static int perm_at_threshold = 5;
static int enforce_pcrud = 0;     // Boolean
static char* modulename = NULL;

int writeAuditInfo( osrfMethodContext* ctx, const char* user_id, const char* ws_id);

/**
	@brief Connect to the database.
	@return A database connection if successful, or NULL if not.
*/
dbi_conn oilsConnectDB( const char* mod_name ) {

	osrfLogDebug( OSRF_LOG_MARK, "Attempting to initialize libdbi..." );
	if( dbi_initialize( NULL ) == -1 ) {
		osrfLogError( OSRF_LOG_MARK, "Unable to initialize libdbi" );
		return NULL;
	} else
		osrfLogDebug( OSRF_LOG_MARK, "... libdbi initialized." );

	char* driver = osrf_settings_host_value( "/apps/%s/app_settings/driver", mod_name );
	char* user   = osrf_settings_host_value( "/apps/%s/app_settings/database/user", mod_name );
	char* host   = osrf_settings_host_value( "/apps/%s/app_settings/database/host", mod_name );
	char* port   = osrf_settings_host_value( "/apps/%s/app_settings/database/port", mod_name );
	char* db     = osrf_settings_host_value( "/apps/%s/app_settings/database/db", mod_name );
	char* pw     = osrf_settings_host_value( "/apps/%s/app_settings/database/pw", mod_name );

	osrfLogDebug( OSRF_LOG_MARK, "Attempting to load the database driver [%s]...", driver );
	dbi_conn handle = dbi_conn_new( driver );

	if( !handle ) {
		osrfLogError( OSRF_LOG_MARK, "Error loading database driver [%s]", driver );
		return NULL;
	}
	osrfLogDebug( OSRF_LOG_MARK, "Database driver [%s] seems OK", driver );

	osrfLogInfo(OSRF_LOG_MARK, "%s connecting to database.  host=%s, "
		"port=%s, user=%s, db=%s", mod_name, host, port, user, db );

	if( host ) dbi_conn_set_option( handle, "host", host );
	if( port ) dbi_conn_set_option_numeric( handle, "port", atoi( port ));
	if( user ) dbi_conn_set_option( handle, "username", user );
	if( pw )   dbi_conn_set_option( handle, "password", pw );
	if( db )   dbi_conn_set_option( handle, "dbname", db );

	free( user );
	free( host );
	free( port );
	free( db );
	free( pw );

	if( dbi_conn_connect( handle ) < 0 ) {
		sleep( 1 );
		if( dbi_conn_connect( handle ) < 0 ) {
			const char* msg;
			dbi_conn_error( handle, &msg );
			osrfLogError( OSRF_LOG_MARK, "Error connecting to database: %s",
				msg ? msg : "(No description available)" );
			return NULL;
		}
	}

	osrfLogInfo( OSRF_LOG_MARK, "%s successfully connected to the database", mod_name );

	return handle;
}

/**
	@brief Select some options.
	@param module_name: Name of the server.
	@param do_pcrud: Boolean.  True if we are to enforce PCRUD permissions.

	This source file is used (at this writing) to implement three different servers:
	- open-ils.reporter-store
	- open-ils.pcrud
	- open-ils.cstore

	These servers behave mostly the same, but they implement different combinations of
	methods, and open-ils.pcrud enforces a permissions scheme that the other two don't.

	Here we use the server name in messages to identify which kind of server issued them.
	We use do_crud as a boolean to control whether or not to enforce the permissions scheme.
*/
void oilsSetSQLOptions( const char* module_name, int do_pcrud, int flesh_depth ) {
	if( !module_name )
		module_name = "open-ils.cstore";   // bulletproofing with a default

	if( modulename )
		free( modulename );

	modulename = strdup( module_name );
	enforce_pcrud = do_pcrud;
	max_flesh_depth = flesh_depth;
}

/**
	@brief Install a database connection.
	@param conn Pointer to a database connection.

	In some contexts, @a conn may merely provide a driver so that we can process strings
	properly, without providing an open database connection.
*/
void oilsSetDBConnection( dbi_conn conn ) {
	dbhandle = writehandle = conn;
}

/**
	@brief Determine whether a database connection is alive.
	@param handle Handle for a database connection.
	@return 1 if the connection is alive, or zero if it isn't.
*/
int oilsIsDBConnected( dbi_conn handle ) {
	// Do an innocuous SELECT.  If it succeeds, the database connection is still good.
	dbi_result result = dbi_conn_query( handle, "SELECT 1;" );
	if( result ) {
		dbi_result_free( result );
		return 1;
	} else {
		// This is a terrible, horrible, no good, very bad kludge.
		// Sometimes the SELECT 1 query fails, not because the database connection is dead,
		// but because (due to a previous error) the database is ignoring all commands,
		// even innocuous SELECTs, until the current transaction is rolled back.  The only
		// known way to detect this condition via the dbi library is by looking at the error
		// message.  This approach will break if the language or wording of the message ever
		// changes.
		// Note: the dbi_conn_ping function purports to determine whether the database
		// connection is live, but at this writing this function is unreliable and useless.
		static const char* ok_msg = "ERROR:  current transaction is aborted, commands "
			"ignored until end of transaction block\n";
		const char* msg;
		dbi_conn_error( handle, &msg );
		if( strcmp( msg, ok_msg )) {
			osrfLogError( OSRF_LOG_MARK, "Database connection isn't working" );
			return 0;
		} else
			return 1;   // ignoring SELECT due to previous error; that's okay
	}
}

/**
	@brief Get a table name, view name, or subquery for use in a FROM clause.
	@param class Pointer to the IDL class entry.
	@return A table name, a view name, or a subquery in parentheses.

	In some cases the IDL defines a class, not with a table name or a view name, but with
	a SELECT statement, which may be used as a subquery.
*/
char* oilsGetRelation( osrfHash* classdef ) {

	char* source_def = NULL;
	const char* tabledef = osrfHashGet( classdef, "tablename" );

	if( tabledef ) {
		source_def = strdup( tabledef );   // Return the name of a table or view
	} else {
		tabledef = osrfHashGet( classdef, "source_definition" );
		if( tabledef ) {
			// Return a subquery, enclosed in parentheses
			source_def = safe_malloc( strlen( tabledef ) + 3 );
			source_def[ 0 ] = '(';
			strcpy( source_def + 1, tabledef );
			strcat( source_def, ")" );
		} else {
			// Not found: return an error
			const char* classname = osrfHashGet( classdef, "classname" );
			if( !classname )
				classname = "???";
			osrfLogError(
				OSRF_LOG_MARK,
				"%s ERROR No tablename or source_definition for class \"%s\"",
				modulename,
				classname
			);
		}
	}

	return source_def;
}

/**
	@brief Add datatypes from the database to the fields in the IDL.
	@param handle Handle for a database connection
	@return Zero if successful, or 1 upon error.

	For each relevant class in the IDL: ask the database for the datatype of every field.
	In particular, determine which fields are text fields and which fields are numeric
	fields, so that we know whether to enclose their values in quotes.
*/
int oilsExtendIDL( dbi_conn handle ) {
	osrfHashIterator* class_itr = osrfNewHashIterator( oilsIDL() );
	osrfHash* class = NULL;
	growing_buffer* query_buf = buffer_init( 64 );
	int results_found = 0;   // boolean

	// For each class in the IDL...
	while( (class = osrfHashIteratorNext( class_itr ) ) ) {
		const char* classname = osrfHashIteratorKey( class_itr );
		osrfHash* fields = osrfHashGet( class, "fields" );

		// If the class is virtual, ignore it
		if( str_is_true( osrfHashGet(class, "virtual") ) ) {
			osrfLogDebug(OSRF_LOG_MARK, "Class %s is virtual, skipping", classname );
			continue;
		}

		char* tabledef = oilsGetRelation( class );
		if( !tabledef )
			continue;   // No such relation -- a query of it would be doomed to failure

		buffer_reset( query_buf );
		buffer_fadd( query_buf, "SELECT * FROM %s AS x WHERE 1=0;", tabledef );

		free(tabledef );

		osrfLogDebug( OSRF_LOG_MARK, "%s Investigatory SQL = %s",
				modulename, OSRF_BUFFER_C_STR( query_buf ) );

		dbi_result result = dbi_conn_query( handle, OSRF_BUFFER_C_STR( query_buf ) );
		if( result ) {

			results_found = 1;
			int columnIndex = 1;
			const char* columnName;
			while( (columnName = dbi_result_get_field_name(result, columnIndex)) ) {

				osrfLogInternal( OSRF_LOG_MARK, "Looking for column named [%s]...",
						columnName );

				/* fetch the fieldmapper index */
				osrfHash* _f = osrfHashGet(fields, columnName);
				if( _f ) {

					osrfLogDebug(OSRF_LOG_MARK, "Found [%s] in IDL hash...", columnName);

					/* determine the field type and storage attributes */

					switch( dbi_result_get_field_type_idx( result, columnIndex )) {

						case DBI_TYPE_INTEGER : {

							if( !osrfHashGet(_f, "primitive") )
								osrfHashSet(_f, "number", "primitive");

							int attr = dbi_result_get_field_attribs_idx( result, columnIndex );
							if( attr & DBI_INTEGER_SIZE8 )
								osrfHashSet( _f, "INT8", "datatype" );
							else
								osrfHashSet( _f, "INT", "datatype" );
							break;
						}
						case DBI_TYPE_DECIMAL :
							if( !osrfHashGet( _f, "primitive" ))
								osrfHashSet( _f, "number", "primitive" );

							osrfHashSet( _f, "NUMERIC", "datatype" );
							break;

						case DBI_TYPE_STRING :
							if( !osrfHashGet( _f, "primitive" ))
								osrfHashSet( _f, "string", "primitive" );

							osrfHashSet( _f,"TEXT", "datatype" );
							break;

						case DBI_TYPE_DATETIME :
							if( !osrfHashGet( _f, "primitive" ))
								osrfHashSet( _f, "string", "primitive" );

							osrfHashSet( _f, "TIMESTAMP", "datatype" );
							break;

						case DBI_TYPE_BINARY :
							if( !osrfHashGet( _f, "primitive" ))
								osrfHashSet( _f, "string", "primitive" );

							osrfHashSet( _f, "BYTEA", "datatype" );
					}

					osrfLogDebug(
						OSRF_LOG_MARK,
						"Setting [%s] to primitive [%s] and datatype [%s]...",
						columnName,
						osrfHashGet( _f, "primitive" ),
						osrfHashGet( _f, "datatype" )
					);
				}
				++columnIndex;
			} // end while loop for traversing columns of result
			dbi_result_free( result  );
		} else {
			const char* msg;
			int errnum = dbi_conn_error( handle, &msg );
			osrfLogDebug( OSRF_LOG_MARK, "No data found for class [%s]: %d, %s", classname,
				errnum, msg ? msg : "(No description available)" );
			// We don't check the database connection here.  It's routine to get failures at
			// this point; we routinely try to query tables that don't exist, because they
			// are defined in the IDL but not in the database.
		}
	} // end for each class in IDL

	buffer_free( query_buf );
	osrfHashIteratorFree( class_itr );
	child_initialized = 1;

	if( !results_found ) {
		osrfLogError( OSRF_LOG_MARK,
			"No results found for any class -- bad database connection?" );
		return 1;
	} else if( ! oilsIsDBConnected( handle )) {
		osrfLogError( OSRF_LOG_MARK,
			"Unable to extend IDL: database connection isn't working" );
		return 1;
	}
	else
		return 0;
}

/**
	@brief Free an osrfHash that stores a transaction ID.
	@param blob A pointer to the osrfHash to be freed, cast to a void pointer.

	This function is a callback, to be called by the application session when it ends.
	The application session stores the osrfHash via an opaque pointer.

	If the osrfHash contains an entry for the key "xact_id", it means that an
	uncommitted transaction is pending.  Roll it back.
*/
void userDataFree( void* blob ) {
	osrfHash* hash = (osrfHash*) blob;
	if( osrfHashGet( hash, "xact_id" ) && writehandle ) {
		if( !dbi_conn_query( writehandle, "ROLLBACK;" )) {
			const char* msg;
			int errnum = dbi_conn_error( writehandle, &msg );
			osrfLogWarning( OSRF_LOG_MARK, "Unable to perform rollback: %d %s",
				errnum, msg ? msg : "(No description available)" );
		};
	}
	if( writehandle ) {
		if( !dbi_conn_query( writehandle, "SELECT auditor.clear_audit_info();" ) ) {
			const char* msg;
			int errnum = dbi_conn_error( writehandle, &msg );
			osrfLogWarning( OSRF_LOG_MARK, "Unable to perform audit info clearing: %d %s",
				errnum, msg ? msg : "(No description available)" );
		}
	}

	osrfHashFree( hash );
}

/**
	@name Managing session data
	@brief Maintain data stored via the userData pointer of the application session.

	Currently, session-level data is stored in an osrfHash.  Other arrangements are
	possible, and some would be more efficient.  The application session calls a
	callback function to free userData before terminating.

	Currently, the only data we store at the session level is the transaction id.  By this
	means we can ensure that any pending transactions are rolled back before the application
	session terminates.
*/
/*@{*/

/**
	@brief Free an item in the application session's userData.
	@param key The name of a key for an osrfHash.
	@param item An opaque pointer to the item associated with the key.

	We store an osrfHash as userData with the application session, and arrange (by
	installing userDataFree() as a different callback) for the session to free that
	osrfHash before terminating.

	This function is a callback for freeing items in the osrfHash.  Currently we store
	two things:
	- Transaction id of a pending transaction; a character string.  Key: "xact_id".
	- Authkey; a character string.  Key: "authkey".
	- User object from the authentication server; a jsonObject.  Key: "user_login".

	If we ever store anything else in userData, we will need to revisit this function so
	that it will free whatever else needs freeing.
*/
static void sessionDataFree( char* key, void* item ) {
	if( !strcmp( key, "xact_id" ) || !strcmp( key, "authkey" ) || !strncmp( key, "rs_size_", 8) ) 
		free( item );
	else if( !strcmp( key, "user_login" ) )
		jsonObjectFree( (jsonObject*) item );
	else if( !strcmp( key, "pcache" ) )
		osrfHashFree( (osrfHash*) item );
}

static void pcacheFree( char* key, void* item ) {
	osrfStringArrayFree( (osrfStringArray*) item );
}

/**
	@brief Initialize session cache.
	@param ctx Pointer to the method context.

	Create a cache for the session by making the session's userData member point
	to an osrfHash instance.
*/
static osrfHash* initSessionCache( osrfMethodContext* ctx ) {
	ctx->session->userData = osrfNewHash();
	osrfHashSetCallback( (osrfHash*) ctx->session->userData, &sessionDataFree );
	ctx->session->userDataFree = &userDataFree;
	return ctx->session->userData;
}

/**
	@brief Save a transaction id.
	@param ctx Pointer to the method context.

	Save the session_id of the current application session as a transaction id.
*/
static void setXactId( osrfMethodContext* ctx ) {
	if( ctx && ctx->session ) {
		osrfAppSession* session = ctx->session;

		osrfHash* cache = session->userData;

		// If the session doesn't already have a hash, create one.  Make sure
		// that the application session frees the hash when it terminates.
		if( NULL == cache )
			cache = initSessionCache( ctx );

		// Save the transaction id in the hash, with the key "xact_id"
		osrfHashSet( cache, strdup( session->session_id ), "xact_id" );
	}
}

/**
	@brief Get the transaction ID for the current transaction, if any.
	@param ctx Pointer to the method context.
	@return Pointer to the transaction ID.

	The return value points to an internal buffer, and will become invalid upon issuing
	a commit or rollback.
*/
static inline const char* getXactId( osrfMethodContext* ctx ) {
	if( ctx && ctx->session && ctx->session->userData )
		return osrfHashGet( (osrfHash*) ctx->session->userData, "xact_id" );
	else
		return NULL;
}

/**
	@brief Clear the current transaction id.
	@param ctx Pointer to the method context.
*/
static inline void clearXactId( osrfMethodContext* ctx ) {
	if( ctx && ctx->session && ctx->session->userData )
		osrfHashRemove( ctx->session->userData, "xact_id" );
}
/*@}*/

/**
	@brief Stash the location for a particular perm in the sessionData cache
	@param ctx Pointer to the method context.
	@param perm Name of the permission we're looking at
	@param array StringArray of perm location ids
*/
static void setPermLocationCache( osrfMethodContext* ctx, const char* perm, osrfStringArray* locations ) {
	if( ctx && ctx->session ) {
		osrfAppSession* session = ctx->session;

		osrfHash* cache = session->userData;

		// If the session doesn't already have a hash, create one.  Make sure
		// that the application session frees the hash when it terminates.
		if( NULL == cache )
			cache = initSessionCache( ctx );

		osrfHash* pcache = osrfHashGet(cache, "pcache");

		if( NULL == pcache ) {
			pcache = osrfNewHash();
			osrfHashSetCallback( pcache, &pcacheFree );
			osrfHashSet( cache, pcache, "pcache" );
		}

		if( perm && locations )
			osrfHashSet( pcache, locations, strdup(perm) );
	}
}

/**
	@brief Grab stashed location for a particular perm in the sessionData cache
	@param ctx Pointer to the method context.
	@param perm Name of the permission we're looking at
*/
static osrfStringArray* getPermLocationCache( osrfMethodContext* ctx, const char* perm ) {
	if( ctx && ctx->session ) {
		osrfAppSession* session = ctx->session;
		osrfHash* cache = session->userData;
		if( cache ) {
			osrfHash* pcache = osrfHashGet(cache, "pcache");
			if( pcache ) {
				return osrfHashGet( pcache, perm );
			}
		}
	}

	return NULL;
}

/**
	@brief Save the user's login in the userData for the current application session.
	@param ctx Pointer to the method context.
	@param user_login Pointer to the user login object to be cached (we cache the original,
	not a copy of it).

	If @a user_login is NULL, remove the user login if one is already cached.
*/
static void setUserLogin( osrfMethodContext* ctx, jsonObject* user_login ) {
	if( ctx && ctx->session ) {
		osrfAppSession* session = ctx->session;

		osrfHash* cache = session->userData;

		// If the session doesn't already have a hash, create one.  Make sure
		// that the application session frees the hash when it terminates.
		if( NULL == cache )
			cache = initSessionCache( ctx );

		if( user_login )
			osrfHashSet( cache, user_login, "user_login" );
		else
			osrfHashRemove( cache, "user_login" );
	}
}

/**
	@brief Get the user login object for the current application session, if any.
	@param ctx Pointer to the method context.
	@return Pointer to the user login object if found; otherwise NULL.

	The user login object was returned from the authentication server, and then cached so
	we don't have to call the authentication server again for the same user.
*/
static const jsonObject* getUserLogin( osrfMethodContext* ctx ) {
	if( ctx && ctx->session && ctx->session->userData )
		return osrfHashGet( (osrfHash*) ctx->session->userData, "user_login" );
	else
		return NULL;
}

/**
	@brief Save a copy of an authkey in the userData of the current application session.
	@param ctx Pointer to the method context.
	@param authkey The authkey to be saved.

	If @a authkey is NULL, remove the authkey if one is already cached.
*/
static void setAuthkey( osrfMethodContext* ctx, const char* authkey ) {
	if( ctx && ctx->session && authkey ) {
		osrfAppSession* session = ctx->session;
		osrfHash* cache = session->userData;

		// If the session doesn't already have a hash, create one.  Make sure
		// that the application session frees the hash when it terminates.
		if( NULL == cache )
			cache = initSessionCache( ctx );

		// Save the transaction id in the hash, with the key "xact_id"
		if( authkey && *authkey )
			osrfHashSet( cache, strdup( authkey ), "authkey" );
		else
			osrfHashRemove( cache, "authkey" );
	}
}

/**
	@brief Reset the login timeout.
	@param authkey The authentication key for the current login session.
	@param now The current time.
	@return Zero if successful, or 1 if not.

	Tell the authentication server to reset the timeout so that the login session won't
	expire for a while longer.

	We could dispense with the @a now parameter by calling time().  But we just called
	time() in order to decide whether to reset the timeout, so we might as well reuse
	the result instead of calling time() again.
*/
static int reset_timeout( const char* authkey, time_t now ) {
	jsonObject* auth_object = jsonNewObject( authkey );

	// Ask the authentication server to reset the timeout.  It returns an event
	// indicating success or failure.
	jsonObject* result = oilsUtilsQuickReq( "open-ils.auth",
		"open-ils.auth.session.reset_timeout", auth_object );
	jsonObjectFree( auth_object );

	if( !result || result->type != JSON_HASH ) {
		osrfLogError( OSRF_LOG_MARK,
			 "Unexpected object type receieved from open-ils.auth.session.reset_timeout" );
		jsonObjectFree( result );
		return 1;       // Not the right sort of object returned
	}

	const jsonObject* ilsevent = jsonObjectGetKeyConst( result, "ilsevent" );
	if( !ilsevent || ilsevent->type != JSON_NUMBER ) {
		osrfLogError( OSRF_LOG_MARK, "ilsevent is absent or malformed" );
		jsonObjectFree( result );
		return 1;    // Return code from method not available
	}

	if( jsonObjectGetNumber( ilsevent ) != 0.0 ) {
		const char* desc = jsonObjectGetString( jsonObjectGetKeyConst( result, "desc" ));
		if( !desc )
			desc = "(No reason available)";    // failsafe; shouldn't happen
		osrfLogInfo( OSRF_LOG_MARK, "Failure to reset timeout: %s", desc );
		jsonObjectFree( result );
		return 1;
	}

	// Revise our local proxy for the timeout deadline
	// by a smallish fraction of the timeout interval
	const char* timeout = jsonObjectGetString( jsonObjectGetKeyConst( result, "payload" ));
	if( !timeout )
		timeout = "1";   // failsafe; shouldn't happen
	time_next_reset = now + atoi( timeout ) / 15;

	jsonObjectFree( result );
	return 0;     // Successfully reset timeout
}

/**
	@brief Get the authkey string for the current application session, if any.
	@param ctx Pointer to the method context.
	@return Pointer to the cached authkey if found; otherwise NULL.

	If present, the authkey string was cached from a previous method call.
*/
static const char* getAuthkey( osrfMethodContext* ctx ) {
	if( ctx && ctx->session && ctx->session->userData ) {
		const char* authkey = osrfHashGet( (osrfHash*) ctx->session->userData, "authkey" );
        // LFW recent changes mean the userData hash gets set up earlier, but
        // doesn't necessarily have an authkey yet
        if (!authkey)
            return NULL;

		// Possibly reset the authentication timeout to keep the login alive.  We do so
		// no more than once per method call, and not at all if it has been only a short
		// time since the last reset.

		// Here we reset explicitly, if at all.  We also implicitly reset the timeout
		// whenever we call the "open-ils.auth.session.retrieve" method.
		if( timeout_needs_resetting ) {
			time_t now = time( NULL );
			if( now >= time_next_reset && reset_timeout( authkey, now ) )
				authkey = NULL;    // timeout has apparently expired already
		}

		timeout_needs_resetting = 0;
		return authkey;
	}
	else
		return NULL;
}

/**
	@brief Implement the transaction.begin method.
	@param ctx Pointer to the method context.
	@return Zero if successful, or -1 upon error.

	Start a transaction.  Save a transaction ID for future reference.

	Method parameters:
	- authkey (PCRUD only)

	Return to client: Transaction ID
*/
int beginTransaction( osrfMethodContext* ctx ) {
	if(osrfMethodVerifyContext( ctx )) {
		osrfLogError( OSRF_LOG_MARK,  "Invalid method context" );
		return -1;
	}

	if( enforce_pcrud ) {
		timeout_needs_resetting = 1;
		const jsonObject* user = verifyUserPCRUD( ctx );
		if( !user )
			return -1;
	}

	dbi_result result = dbi_conn_query( writehandle, "START TRANSACTION;" );
	if( !result ) {
		const char* msg;
		int errnum = dbi_conn_error( writehandle, &msg );
		osrfLogError( OSRF_LOG_MARK, "%s: Error starting transaction: %d %s",
			modulename, errnum, msg ? msg : "(No description available)" );
		osrfAppSessionStatus( ctx->session, OSRF_STATUS_INTERNALSERVERERROR,
			"osrfMethodException", ctx->request, "Error starting transaction" );
		if( !oilsIsDBConnected( writehandle ))
			osrfAppSessionPanic( ctx->session );
		return -1;
	} else {
		dbi_result_free( result );
		setXactId( ctx );
		jsonObject* ret = jsonNewObject( getXactId( ctx ) );
		osrfAppRespondComplete( ctx, ret );
		jsonObjectFree( ret );
		return 0;
	}
}

/**
	@brief Implement the savepoint.set method.
	@param ctx Pointer to the method context.
	@return Zero if successful, or -1 if not.

	Issue a SAVEPOINT to the database server.

	Method parameters:
	- authkey (PCRUD only)
	- savepoint name

	Return to client: Savepoint name
*/
int setSavepoint( osrfMethodContext* ctx ) {
	if(osrfMethodVerifyContext( ctx )) {
		osrfLogError( OSRF_LOG_MARK,  "Invalid method context" );
		return -1;
	}

	int spNamePos = 0;
	if( enforce_pcrud ) {
		spNamePos = 1;
		timeout_needs_resetting = 1;
		const jsonObject* user = verifyUserPCRUD( ctx );
		if( !user )
			return -1;
	}

	// Verify that a transaction is pending
	const char* trans_id = getXactId( ctx );
	if( NULL == trans_id ) {
		osrfAppSessionStatus(
			ctx->session,
			OSRF_STATUS_INTERNALSERVERERROR,
			"osrfMethodException",
			ctx->request,
			"No active transaction -- required for savepoints"
		);
		return -1;
	}

	// Get the savepoint name from the method params
	const char* spName = jsonObjectGetString( jsonObjectGetIndex(ctx->params, spNamePos) );

	dbi_result result = dbi_conn_queryf( writehandle, "SAVEPOINT \"%s\";", spName );
	if( !result ) {
		const char* msg;
		int errnum = dbi_conn_error( writehandle, &msg );
		osrfLogError(
			OSRF_LOG_MARK,
			"%s: Error creating savepoint %s in transaction %s: %d %s",
			modulename,
			spName,
			trans_id,
			errnum,
			msg ? msg : "(No description available)"
		);
		osrfAppSessionStatus( ctx->session, OSRF_STATUS_INTERNALSERVERERROR,
			"osrfMethodException", ctx->request, "Error creating savepoint" );
		if( !oilsIsDBConnected( writehandle ))
			osrfAppSessionPanic( ctx->session );
		return -1;
	} else {
		dbi_result_free( result );
		jsonObject* ret = jsonNewObject( spName );
		osrfAppRespondComplete( ctx, ret );
		jsonObjectFree( ret  );
		return 0;
	}
}

/**
	@brief Implement the savepoint.release method.
	@param ctx Pointer to the method context.
	@return Zero if successful, or -1 if not.

	Issue a RELEASE SAVEPOINT to the database server.

	Method parameters:
	- authkey (PCRUD only)
	- savepoint name

	Return to client: Savepoint name
*/
int releaseSavepoint( osrfMethodContext* ctx ) {
	if(osrfMethodVerifyContext( ctx )) {
		osrfLogError( OSRF_LOG_MARK,  "Invalid method context" );
		return -1;
	}

	int spNamePos = 0;
	if( enforce_pcrud ) {
		spNamePos = 1;
		timeout_needs_resetting = 1;
		const jsonObject* user = verifyUserPCRUD( ctx );
		if(  !user )
			return -1;
	}

	// Verify that a transaction is pending
	const char* trans_id = getXactId( ctx );
	if( NULL == trans_id ) {
		osrfAppSessionStatus(
			ctx->session,
			OSRF_STATUS_INTERNALSERVERERROR,
			"osrfMethodException",
			ctx->request,
			"No active transaction -- required for savepoints"
		);
		return -1;
	}

	// Get the savepoint name from the method params
	const char* spName = jsonObjectGetString( jsonObjectGetIndex(ctx->params, spNamePos) );

	dbi_result result = dbi_conn_queryf( writehandle, "RELEASE SAVEPOINT \"%s\";", spName );
	if( !result ) {
		const char* msg;
		int errnum = dbi_conn_error( writehandle, &msg );
		osrfLogError(
			OSRF_LOG_MARK,
			"%s: Error releasing savepoint %s in transaction %s: %d %s",
			modulename,
			spName,
			trans_id,
			errnum,
			msg ? msg : "(No description available)"
		);
		osrfAppSessionStatus( ctx->session, OSRF_STATUS_INTERNALSERVERERROR,
			"osrfMethodException", ctx->request, "Error releasing savepoint" );
		if( !oilsIsDBConnected( writehandle ))
			osrfAppSessionPanic( ctx->session );
		return -1;
	} else {
		dbi_result_free( result );
		jsonObject* ret = jsonNewObject( spName );
		osrfAppRespondComplete( ctx, ret );
		jsonObjectFree( ret );
		return 0;
	}
}

/**
	@brief Implement the savepoint.rollback method.
	@param ctx Pointer to the method context.
	@return Zero if successful, or -1 if not.

	Issue a ROLLBACK TO SAVEPOINT to the database server.

	Method parameters:
	- authkey (PCRUD only)
	- savepoint name

	Return to client: Savepoint name
*/
int rollbackSavepoint( osrfMethodContext* ctx ) {
	if(osrfMethodVerifyContext( ctx )) {
		osrfLogError( OSRF_LOG_MARK,  "Invalid method context" );
		return -1;
	}

	int spNamePos = 0;
	if( enforce_pcrud ) {
		spNamePos = 1;
		timeout_needs_resetting = 1;
		const jsonObject* user = verifyUserPCRUD( ctx );
		if( !user )
			return -1;
	}

	// Verify that a transaction is pending
	const char* trans_id = getXactId( ctx );
	if( NULL == trans_id ) {
		osrfAppSessionStatus(
			ctx->session,
			OSRF_STATUS_INTERNALSERVERERROR,
			"osrfMethodException",
			ctx->request,
			"No active transaction -- required for savepoints"
		);
		return -1;
	}

	// Get the savepoint name from the method params
	const char* spName = jsonObjectGetString( jsonObjectGetIndex(ctx->params, spNamePos) );

	dbi_result result = dbi_conn_queryf( writehandle, "ROLLBACK TO SAVEPOINT \"%s\";", spName );
	if( !result ) {
		const char* msg;
		int errnum = dbi_conn_error( writehandle, &msg );
		osrfLogError(
			OSRF_LOG_MARK,
			"%s: Error rolling back savepoint %s in transaction %s: %d %s",
			modulename,
			spName,
			trans_id,
			errnum,
			msg ? msg : "(No description available)"
		);
		osrfAppSessionStatus( ctx->session, OSRF_STATUS_INTERNALSERVERERROR,
			"osrfMethodException", ctx->request, "Error rolling back savepoint" );
		if( !oilsIsDBConnected( writehandle ))
			osrfAppSessionPanic( ctx->session );
		return -1;
	} else {
		dbi_result_free( result );
		jsonObject* ret = jsonNewObject( spName );
		osrfAppRespondComplete( ctx, ret );
		jsonObjectFree( ret );
		return 0;
	}
}

/**
	@brief Implement the transaction.commit method.
	@param ctx Pointer to the method context.
	@return Zero if successful, or -1 if not.

	Issue a COMMIT to the database server.

	Method parameters:
	- authkey (PCRUD only)

	Return to client: Transaction ID.
*/
int commitTransaction( osrfMethodContext* ctx ) {
	if(osrfMethodVerifyContext( ctx )) {
		osrfLogError( OSRF_LOG_MARK, "Invalid method context" );
		return -1;
	}

	if( enforce_pcrud ) {
		timeout_needs_resetting = 1;
		const jsonObject* user = verifyUserPCRUD( ctx );
		if( !user )
			return -1;
	}

	// Verify that a transaction is pending
	const char* trans_id = getXactId( ctx );
	if( NULL == trans_id ) {
		osrfAppSessionStatus( ctx->session, OSRF_STATUS_INTERNALSERVERERROR,
				"osrfMethodException", ctx->request, "No active transaction to commit" );
		return -1;
	}

	dbi_result result = dbi_conn_query( writehandle, "COMMIT;" );
	if( !result ) {
		const char* msg;
		int errnum = dbi_conn_error( writehandle, &msg );
		osrfLogError( OSRF_LOG_MARK, "%s: Error committing transaction: %d %s",
			modulename, errnum, msg ? msg : "(No description available)" );
		osrfAppSessionStatus( ctx->session, OSRF_STATUS_INTERNALSERVERERROR,
			"osrfMethodException", ctx->request, "Error committing transaction" );
		if( !oilsIsDBConnected( writehandle ))
			osrfAppSessionPanic( ctx->session );
		return -1;
	} else {
		dbi_result_free( result );
		jsonObject* ret = jsonNewObject( trans_id );
		osrfAppRespondComplete( ctx, ret );
		jsonObjectFree( ret );
		clearXactId( ctx );
		return 0;
	}
}

/**
	@brief Implement the transaction.rollback method.
	@param ctx Pointer to the method context.
	@return Zero if successful, or -1 if not.

	Issue a ROLLBACK to the database server.

	Method parameters:
	- authkey (PCRUD only)

	Return to client: Transaction ID
*/
int rollbackTransaction( osrfMethodContext* ctx ) {
	if( osrfMethodVerifyContext( ctx )) {
		osrfLogError( OSRF_LOG_MARK,  "Invalid method context" );
		return -1;
	}

	if( enforce_pcrud ) {
		timeout_needs_resetting = 1;
		const jsonObject* user = verifyUserPCRUD( ctx );
		if( !user )
			return -1;
	}

	// Verify that a transaction is pending
	const char* trans_id = getXactId( ctx );
	if( NULL == trans_id ) {
		osrfAppSessionStatus( ctx->session, OSRF_STATUS_INTERNALSERVERERROR,
				"osrfMethodException", ctx->request, "No active transaction to roll back" );
		return -1;
	}

	dbi_result result = dbi_conn_query( writehandle, "ROLLBACK;" );
	if( !result ) {
		const char* msg;
		int errnum = dbi_conn_error( writehandle, &msg );
		osrfLogError( OSRF_LOG_MARK, "%s: Error rolling back transaction: %d %s",
			modulename, errnum, msg ? msg : "(No description available)" );
		osrfAppSessionStatus( ctx->session, OSRF_STATUS_INTERNALSERVERERROR,
			"osrfMethodException", ctx->request, "Error rolling back transaction" );
		if( !oilsIsDBConnected( writehandle ))
			osrfAppSessionPanic( ctx->session );
		return -1;
	} else {
		dbi_result_free( result );
		jsonObject* ret = jsonNewObject( trans_id );
		osrfAppRespondComplete( ctx, ret );
		jsonObjectFree( ret );
		clearXactId( ctx );
		return 0;
	}
}

/**
	@brief Implement the "search" method.
	@param ctx Pointer to the method context.
	@return Zero if successful, or -1 if not.

	Method parameters:
	- authkey (PCRUD only)
	- WHERE clause, as jsonObject
	- Other SQL clause(s), as a JSON_HASH: joins, SELECT list, LIMIT, etc.

	Return to client: rows of the specified class that satisfy a specified WHERE clause.
	Optionally flesh linked fields.
*/
int doSearch( osrfMethodContext* ctx ) {
	if( osrfMethodVerifyContext( ctx )) {
		osrfLogError( OSRF_LOG_MARK, "Invalid method context" );
		return -1;
	}

	if( enforce_pcrud )
		timeout_needs_resetting = 1;

	jsonObject* where_clause;
	jsonObject* rest_of_query;

	if( enforce_pcrud ) {
		where_clause  = jsonObjectGetIndex( ctx->params, 1 );
		rest_of_query = jsonObjectGetIndex( ctx->params, 2 );
	} else {
		where_clause  = jsonObjectGetIndex( ctx->params, 0 );
		rest_of_query = jsonObjectGetIndex( ctx->params, 1 );
	}

	if( !where_clause ) { 
		osrfLogError( OSRF_LOG_MARK, "No WHERE clause parameter supplied" );
		return -1;
	}

	// Get the class metadata
	osrfHash* method_meta = (osrfHash*) ctx->method->userData;
	osrfHash* class_meta = osrfHashGet( method_meta, "class" );

	// Do the query
	int err = 0;
	jsonObject* obj = doFieldmapperSearch( ctx, class_meta, where_clause, rest_of_query, &err );
	if( err ) {
		osrfAppRespondComplete( ctx, NULL );
		return -1;
	}

	// doFieldmapperSearch() now takes care of our responding for us
//	// Return each row to the client
//	jsonObject* cur = 0;
//	unsigned long res_idx = 0;
//
//	while((cur = jsonObjectGetIndex( obj, res_idx++ ) )) {
//		// We used to discard based on perms here, but now that's
//		// inside doFieldmapperSearch()
//		osrfAppRespond( ctx, cur );
//	}

	jsonObjectFree( obj );

	osrfAppRespondComplete( ctx, NULL );
	return 0;
}

/**
	@brief Implement the "id_list" method.
	@param ctx Pointer to the method context.
	@param err Pointer through which to return an error code.
	@return Zero if successful, or -1 if not.

	Method parameters:
	- authkey (PCRUD only)
	- WHERE clause, as jsonObject
	- Other SQL clause(s), as a JSON_HASH: joins, LIMIT, etc.

	Return to client: The primary key values for all rows of the relevant class that
	satisfy a specified WHERE clause.

	This method relies on the assumption that every class has a primary key consisting of
	a single column.
*/
int doIdList( osrfMethodContext* ctx ) {
	if( osrfMethodVerifyContext( ctx )) {
		osrfLogError( OSRF_LOG_MARK, "Invalid method context" );
		return -1;
	}

	if( enforce_pcrud )
		timeout_needs_resetting = 1;

	jsonObject* where_clause;
	jsonObject* rest_of_query;

	// We use the where clause without change.  But we need to massage the rest of the
	// query, so we work with a copy of it instead of modifying the original.

	if( enforce_pcrud ) {
		where_clause  = jsonObjectGetIndex( ctx->params, 1 );
		rest_of_query = jsonObjectClone( jsonObjectGetIndex( ctx->params, 2 ) );
	} else {
		where_clause  = jsonObjectGetIndex( ctx->params, 0 );
		rest_of_query = jsonObjectClone( jsonObjectGetIndex( ctx->params, 1 ) );
	}

	if( !where_clause ) { 
		osrfLogError( OSRF_LOG_MARK, "No WHERE clause parameter supplied" );
		return -1;
	}

	// Eliminate certain SQL clauses, if present.
	if( rest_of_query ) {
		jsonObjectRemoveKey( rest_of_query, "select" );
		jsonObjectRemoveKey( rest_of_query, "no_i18n" );
		jsonObjectRemoveKey( rest_of_query, "flesh" );
		jsonObjectRemoveKey( rest_of_query, "flesh_fields" );
	} else {
		rest_of_query = jsonNewObjectType( JSON_HASH );
	}

	jsonObjectSetKey( rest_of_query, "no_i18n", jsonNewBoolObject( 1 ) );

	// Get the class metadata
	osrfHash* method_meta = (osrfHash*) ctx->method->userData;
	osrfHash* class_meta = osrfHashGet( method_meta, "class" );

	// Build a SELECT list containing just the primary key,
	// i.e. like { "classname":["keyname"] }
	jsonObject* col_list_obj = jsonNewObjectType( JSON_ARRAY );

	// Load array with name of primary key
	jsonObjectPush( col_list_obj, jsonNewObject( osrfHashGet( class_meta, "primarykey" ) ) );
	jsonObject* select_clause = jsonNewObjectType( JSON_HASH );
	jsonObjectSetKey( select_clause, osrfHashGet( class_meta, "classname" ), col_list_obj );

	jsonObjectSetKey( rest_of_query, "select", select_clause );

	// Do the query
	int err = 0;
	jsonObject* obj =
		doFieldmapperSearch( ctx, class_meta, where_clause, rest_of_query, &err );

	jsonObjectFree( rest_of_query );
	if( err ) {
		osrfAppRespondComplete( ctx, NULL );
		return -1;
	}

	// Return each primary key value to the client
	jsonObject* cur;
	unsigned long res_idx = 0;
	while((cur = jsonObjectGetIndex( obj, res_idx++ ) )) {
		// We used to discard based on perms here, but now that's
		// inside doFieldmapperSearch()
		osrfAppRespond( ctx,
			oilsFMGetObject( cur, osrfHashGet( class_meta, "primarykey" ) ) );
	}

	jsonObjectFree( obj );
	osrfAppRespondComplete( ctx, NULL );
	return 0;
}

/**
	@brief Verify that we have a valid class reference.
	@param ctx Pointer to the method context.
	@param param Pointer to the method parameters.
	@return 1 if the class reference is valid, or zero if it isn't.

	The class of the method params must match the class to which the method id devoted.
	For PCRUD there are additional restrictions.
*/
static int verifyObjectClass ( osrfMethodContext* ctx, const jsonObject* param ) {

	osrfHash* method_meta = (osrfHash*) ctx->method->userData;
	osrfHash* class = osrfHashGet( method_meta, "class" );

	// Compare the method's class to the parameters' class
	if( !param->classname || (strcmp( osrfHashGet(class, "classname"), param->classname ))) {

		// Oops -- they don't match.  Complain.
		growing_buffer* msg = buffer_init( 128 );
		buffer_fadd(
			msg,
			"%s: %s method for type %s was passed a %s",
			modulename,
			osrfHashGet( method_meta, "methodtype" ),
			osrfHashGet( class, "classname" ),
			param->classname ? param->classname : "(null)"
		);

		char* m = buffer_release( msg );
		osrfAppSessionStatus( ctx->session, OSRF_STATUS_BADREQUEST, "osrfMethodException",
				ctx->request, m );
		free( m );

		return 0;
	}

	if( enforce_pcrud )
		return verifyObjectPCRUD( ctx, class, param, 1 );
	else
		return 1;
}

/**
	@brief (PCRUD only) Verify that the user is properly logged in.
	@param ctx Pointer to the method context.
	@return If the user is logged in, a pointer to the user object from the authentication
	server; otherwise NULL.
*/
static const jsonObject* verifyUserPCRUD( osrfMethodContext* ctx ) {

	// Get the authkey (the first method parameter)
	const char* auth = jsonObjectGetString( jsonObjectGetIndex( ctx->params, 0 ) );

	// See if we have the same authkey, and a user object,
	// locally cached from a previous call
	const char* cached_authkey = getAuthkey( ctx );
	if( cached_authkey && !strcmp( cached_authkey, auth ) ) {
		const jsonObject* cached_user = getUserLogin( ctx );
		if( cached_user )
			return cached_user;
	}

	// We have no matching authentication data in the cache.  Authenticate from scratch.
	jsonObject* auth_object = jsonNewObject( auth );

	// Fetch the user object from the authentication server
	jsonObject* user = oilsUtilsQuickReq( "open-ils.auth", "open-ils.auth.session.retrieve",
			auth_object );
	jsonObjectFree( auth_object );

	if( !user->classname || strcmp(user->classname, "au" )) {

		growing_buffer* msg = buffer_init( 128 );
		buffer_fadd(
			msg,
			"%s: permacrud received a bad auth token: %s",
			modulename,
			auth
		);

		char* m = buffer_release( msg );
		osrfAppSessionStatus( ctx->session, OSRF_STATUS_UNAUTHORIZED, "osrfMethodException",
				ctx->request, m );

		free( m );
		jsonObjectFree( user );
		user = NULL;
	} else if( writeAuditInfo( ctx, oilsFMGetStringConst( user, "id" ), oilsFMGetStringConst( user, "wsid" ) ) ) {
		// Failed to set audit information - But note that write_audit_info already set error information.
		jsonObjectFree( user );
		user = NULL;
	}

	setUserLogin( ctx, user );
	setAuthkey( ctx, auth );

	// Allow ourselves up to a second before we have to reset the login timeout.
	// It would be nice to use some fraction of the timeout interval enforced by the
	// authentication server, but that value is not readily available at this point.
	// Instead, we use a conservative default interval.
	time_next_reset = time( NULL ) + 1;

	return user;
}

/**
	@brief For PCRUD: Determine whether the current user may access the current row.
	@param ctx Pointer to the method context.
	@param class Same as ctx->method->userData's item for key "class" except when called in recursive doFieldmapperSearch
	@param obj Pointer to the row being potentially accessed.
	@return 1 if access is permitted, or 0 if it isn't.

	The @a obj parameter points to a JSON_HASH of column values, keyed on column name.
*/
static int verifyObjectPCRUD ( osrfMethodContext* ctx, osrfHash *class, const jsonObject* obj, int rs_size ) {

	dbhandle = writehandle;

	// Figure out what class and method are involved
	osrfHash* method_metadata = (osrfHash*) ctx->method->userData;
	const char* method_type = osrfHashGet( method_metadata, "methodtype" );

	if (!rs_size) {
		int *rs_size_from_hash = osrfHashGetFmt( (osrfHash *) ctx->session->userData, "rs_size_req_%d", ctx->request );
		if (rs_size_from_hash) {
			rs_size = *rs_size_from_hash;
			osrfLogDebug(OSRF_LOG_MARK, "used rs_size from request-scoped hash: %d", rs_size);
		}
	}

	// Set fetch to 1 in all cases except for inserts, meaning that for local or foreign
	// contexts we will do another lookup of the current row, even if we already have a
	// previously fetched row image, because the row image in hand may not include the
	// foreign key(s) that we need.

	// This is a quick fix with a bludgeon.  There are ways to avoid the extra lookup,
	// but they aren't implemented yet.

	int fetch = 0;
	if( *method_type == 's' || *method_type == 'i' ) {
		method_type = "retrieve"; // search and id_list are equivalent to retrieve for this
		fetch = 1;
	} else if( *method_type == 'u' || *method_type == 'd' ) {
		fetch = 1; // MUST go to the db for the object for update and delete
	}

	// Get the appropriate permacrud entry from the IDL, depending on method type
	osrfHash* pcrud = osrfHashGet( osrfHashGet( class, "permacrud" ), method_type );
	if( !pcrud ) {
		// No permacrud for this method type on this class

		growing_buffer* msg = buffer_init( 128 );
		buffer_fadd(
			msg,
			"%s: %s on class %s has no permacrud IDL entry",
			modulename,
			osrfHashGet( method_metadata, "methodtype" ),
			osrfHashGet( class, "classname" )
		);

		char* m = buffer_release( msg );
		osrfAppSessionStatus( ctx->session, OSRF_STATUS_FORBIDDEN,
				"osrfMethodException", ctx->request, m );

		free( m );

		return 0;
	}

	// Get the user id, and make sure the user is logged in
	const jsonObject* user = verifyUserPCRUD( ctx );
	if( !user )
		return 0;    // Not logged in?  No access.

	int userid = atoi( oilsFMGetStringConst( user, "id" ) );

	// Get a list of permissions from the permacrud entry.
	osrfStringArray* permission = osrfHashGet( pcrud, "permission" );
	if( permission->size == 0 ) {
		osrfLogDebug(
			OSRF_LOG_MARK,
			"No permissions required for this action (class %s), passing through",
			osrfHashGet(class, "classname")
		);
		return 1;
	}

	// Build a list of org units that own the row.  This is fairly convoluted because there
	// are several different ways that an org unit may own the row, as defined by the
	// permacrud entry.

	// Local context means that the row includes a foreign key pointing to actor.org_unit,
	// identifying an owning org_unit..
	osrfStringArray* local_context = osrfHashGet( pcrud, "local_context" );

	// Foreign context adds a layer of indirection.  The row points to some other row that
	// an org unit may own.  The "jump" attribute, if present, adds another layer of
	// indirection.
	osrfHash* foreign_context = osrfHashGet( pcrud, "foreign_context" );

	// The following string array stores the list of org units.  (We don't have a thingie
	// for storing lists of integers, so we fake it with a list of strings.)
	osrfStringArray* context_org_array = osrfNewStringArray( 1 );

	int err = 0;
	const char* pkey_value = NULL;
	if( str_is_true( osrfHashGet(pcrud, "global_required") ) ) {
		// If the global_required attribute is present and true, then the only owning
		// org unit is the root org unit, i.e. the one with no parent.
		osrfLogDebug( OSRF_LOG_MARK,
				"global-level permissions required, fetching top of the org tree" );

		// no need to check perms for org tree root retrieval
		osrfHashSet((osrfHash*) ctx->session->userData, "1", "inside_verify");
		// check for perm at top of org tree
		const char* org_tree_root_id = org_tree_root( ctx );
		osrfHashSet((osrfHash*) ctx->session->userData, "0", "inside_verify");

		if( org_tree_root_id ) {
			osrfStringArrayAdd( context_org_array, org_tree_root_id );
			osrfLogDebug( OSRF_LOG_MARK, "top of the org tree is %s", org_tree_root_id );
		} else  {
			osrfStringArrayFree( context_org_array );
			return 0;
		}

	} else {
		// If the global_required attribute is absent or false, then we look for
		// local and/or foreign context.  In order to find the relevant foreign
		// keys, we must either read the relevant row from the database, or look at
		// the image of the row that we already have in memory.

		// Even if we have an image of the row in memory, that image may not include the
		// foreign key column(s) that we need.  So whenever possible, we do a fresh read
		// of the row to make sure that we have what we need.

	    osrfLogDebug( OSRF_LOG_MARK, "global-level permissions not required, "
				"fetching context org ids" );
	    const char* pkey = osrfHashGet( class, "primarykey" );
		jsonObject *param = NULL;

		if( !pkey ) {
			// There is no primary key, so we can't do a fresh lookup.  Use the row
			// image that we already have.  If it doesn't have everything we need, too bad.
			fetch = 0;
			param = jsonObjectClone( obj );
			osrfLogDebug( OSRF_LOG_MARK, "No primary key; using clone of object" );
		} else if( obj->classname ) {
			pkey_value = oilsFMGetStringConst( obj, pkey );
			if( !fetch )
				param = jsonObjectClone( obj );
			osrfLogDebug( OSRF_LOG_MARK, "Object supplied, using primary key value of %s",
				pkey_value );
		} else {
			pkey_value = jsonObjectGetString( obj );
			fetch = 1;
			osrfLogDebug( OSRF_LOG_MARK, "Object not supplied, using primary key value "
				"of %s and retrieving from the database", pkey_value );
		}

		if( fetch ) {
			// Fetch the row so that we can look at the foreign key(s)
			osrfHashSet((osrfHash*) ctx->session->userData, "1", "inside_verify");
			jsonObject* _tmp_params = single_hash( pkey, pkey_value );
			jsonObject* _list = doFieldmapperSearch( ctx, class, _tmp_params, NULL, &err );
			jsonObjectFree( _tmp_params );
			osrfHashSet((osrfHash*) ctx->session->userData, "0", "inside_verify");

			param = jsonObjectExtractIndex( _list, 0 );
			jsonObjectFree( _list );
		}

		if( !param ) {
			// The row doesn't exist.  Complain, and deny access.
			osrfLogDebug( OSRF_LOG_MARK,
					"Object not found in the database with primary key %s of %s",
					pkey, pkey_value );

			growing_buffer* msg = buffer_init( 128 );
			buffer_fadd(
				msg,
				"%s: no object found with primary key %s of %s",
				modulename,
				pkey,
				pkey_value
			);

			char* m = buffer_release( msg );
			osrfAppSessionStatus(
				ctx->session,
				OSRF_STATUS_INTERNALSERVERERROR,
				"osrfMethodException",
				ctx->request,
				m
			);

			free( m );
			return 0;
		}

		if( local_context && local_context->size > 0 ) {
			// The IDL provides a list of column names for the foreign keys denoting
			// local context, i.e. columns identifying owing org units directly.  Look up
			// the value of each one, and if it isn't null, add it to the list of org units.
			osrfLogDebug( OSRF_LOG_MARK, "%d class-local context field(s) specified",
				local_context->size );
			int i = 0;
			const char* lcontext = NULL;
			while ( (lcontext = osrfStringArrayGetString(local_context, i++)) ) {
				const char* fkey_value = oilsFMGetStringConst( param, lcontext );
				if( fkey_value ) {    // if not null
					osrfStringArrayAdd( context_org_array, fkey_value );
					osrfLogDebug(
						OSRF_LOG_MARK,
						"adding class-local field %s (value: %s) to the context org list",
						lcontext,
						osrfStringArrayGetString( context_org_array, context_org_array->size - 1 )
					);
				}
			}
		}

		if( foreign_context ) {
			unsigned long class_count = osrfHashGetCount( foreign_context );
			osrfLogDebug( OSRF_LOG_MARK, "%d foreign context classes(s) specified", class_count );

			if( class_count > 0 ) {

				// The IDL provides a list of foreign key columns pointing to rows that
				// an org unit may own.  Follow each link, identify the owning org unit,
				// and add it to the list.
				osrfHash* fcontext = NULL;
				osrfHashIterator* class_itr = osrfNewHashIterator( foreign_context );
				while( (fcontext = osrfHashIteratorNext( class_itr )) ) {
					// For each class to which a foreign key points:
					const char* class_name = osrfHashIteratorKey( class_itr );
					osrfHash* fcontext = osrfHashGet( foreign_context, class_name );

					osrfLogDebug(
						OSRF_LOG_MARK,
						"%d foreign context fields(s) specified for class %s",
						((osrfStringArray*)osrfHashGet(fcontext,"context"))->size,
						class_name
					);

					// Get the name of the key field in the foreign table
					const char* foreign_pkey = osrfHashGet( fcontext, "field" );

					// Get the value of the foreign key pointing to the foreign table
					char* foreign_pkey_value =
							oilsFMGetString( param, osrfHashGet( fcontext, "fkey" ));
					if( !foreign_pkey_value )
						continue;    // Foreign key value is null; skip it

					// Look up the row to which the foreign key points
					jsonObject* _tmp_params = single_hash( foreign_pkey, foreign_pkey_value );

					osrfHashSet((osrfHash*) ctx->session->userData, "1", "inside_verify");
					jsonObject* _list = doFieldmapperSearch(
						ctx, osrfHashGet( oilsIDL(), class_name ), _tmp_params, NULL, &err );
					osrfHashSet((osrfHash*) ctx->session->userData, "0", "inside_verify");

					jsonObject* _fparam = NULL;
					if( _list && JSON_ARRAY == _list->type && _list->size > 0 )
						_fparam = jsonObjectExtractIndex( _list, 0 );

					jsonObjectFree( _tmp_params );
					jsonObjectFree( _list );

					// At this point _fparam either points to the row identified by the
					// foreign key, or it's NULL (no such row found).

					osrfStringArray* jump_list = osrfHashGet( fcontext, "jump" );

					const char* bad_class = NULL;  // For noting failed lookups
					if( ! _fparam )
						bad_class = class_name;    // Referenced row not found
					else if( jump_list ) {
						// Follow a chain of rows, linked by foreign keys, to find an owner
						const char* flink = NULL;
						int k = 0;
						while ( (flink = osrfStringArrayGetString(jump_list, k++)) && _fparam ) {
							// For each entry in the jump list.  Each entry (i.e. flink) is
							// the name of a foreign key column in the current row.

							// From the IDL, get the linkage information for the next jump
							osrfHash* foreign_link_hash =
									oilsIDLFindPath( "/%s/links/%s", _fparam->classname, flink );

							// Get the class metadata for the class
							// to which the foreign key points
							osrfHash* foreign_class_meta = osrfHashGet( oilsIDL(),
									osrfHashGet( foreign_link_hash, "class" ));

							// Get the name of the referenced key of that class
							foreign_pkey = osrfHashGet( foreign_link_hash, "key" );

							// Get the value of the foreign key pointing to that class
							free( foreign_pkey_value );
							foreign_pkey_value = oilsFMGetString( _fparam, flink );
							if( !foreign_pkey_value )
								break;    // Foreign key is null; quit looking

							// Build a WHERE clause for the lookup
							_tmp_params = single_hash( foreign_pkey, foreign_pkey_value );

							// Do the lookup
							_list = doFieldmapperSearch( ctx, foreign_class_meta,
									_tmp_params, NULL, &err );

							// Get the resulting row
							jsonObjectFree( _fparam );
							if( _list && JSON_ARRAY == _list->type && _list->size > 0 )
								_fparam = jsonObjectExtractIndex( _list, 0 );
							else {
								// Referenced row not found
								_fparam = NULL;
								bad_class = osrfHashGet( foreign_link_hash, "class" );
							}

							jsonObjectFree( _tmp_params );
							jsonObjectFree( _list );
						}
					}

					if( bad_class ) {

						// We had a foreign key pointing to such-and-such a row, but then
						// we couldn't fetch that row.  The data in the database are in an
						// inconsistent state; the database itself may even be corrupted.
						growing_buffer* msg = buffer_init( 128 );
						buffer_fadd(
							msg,
							"%s: no object of class %s found with primary key %s of %s",
							modulename,
							bad_class,
							foreign_pkey,
							foreign_pkey_value ? foreign_pkey_value : "(null)"
						);

						char* m = buffer_release( msg );
						osrfAppSessionStatus(
							ctx->session,
							OSRF_STATUS_INTERNALSERVERERROR,
							"osrfMethodException",
							ctx->request,
							m
						);

						free( m );
						osrfHashIteratorFree( class_itr );
						free( foreign_pkey_value );
						jsonObjectFree( param );

						return 0;
					}

					free( foreign_pkey_value );

					if( _fparam ) {
						// Examine each context column of the foreign row,
						// and add its value to the list of org units.
						int j = 0;
						const char* foreign_field = NULL;
						osrfStringArray* ctx_array = osrfHashGet( fcontext, "context" );
						while ( (foreign_field = osrfStringArrayGetString( ctx_array, j++ )) ) {
							osrfStringArrayAdd( context_org_array,
								oilsFMGetStringConst( _fparam, foreign_field ));
							osrfLogDebug( OSRF_LOG_MARK,
								"adding foreign class %s field %s (value: %s) "
									"to the context org list",
								class_name,
								foreign_field,
								osrfStringArrayGetString(
									context_org_array, context_org_array->size - 1 )
							);
						}

						jsonObjectFree( _fparam );
					}
				}

				osrfHashIteratorFree( class_itr );
			}
		}

		jsonObjectFree( param );
	}

	const char* context_org = NULL;
	const char* perm = NULL;
	int OK = 0;

	// For every combination of permission and context org unit: call a stored procedure
	// to determine if the user has this permission in the context of this org unit.
	// If the answer is yes at any point, then we're done, and the user has permission.
	// In other words permissions are additive.
	int i = 0;
	while( (perm = osrfStringArrayGetString(permission, i++)) ) {
		dbi_result result;

        osrfStringArray* pcache = NULL;
        if (rs_size > perm_at_threshold) { // grab and cache locations of user perms
			pcache = getPermLocationCache(ctx, perm);

			if (!pcache) {
        		pcache = osrfNewStringArray(0);
	
				result = dbi_conn_queryf(
					writehandle,
					"SELECT permission.usr_has_perm_at_all(%d, '%s') AS at;",
					userid,
					perm
				);
		
				if( result ) {
					osrfLogDebug(
						OSRF_LOG_MARK,
						"Received a result for permission [%s] for user %d",
						perm,
						userid
					);
		
					if( dbi_result_first_row( result )) {
	                    do {
	    					jsonObject* return_val = oilsMakeJSONFromResult( result );
		    				osrfStringArrayAdd( pcache, jsonObjectGetString( jsonObjectGetKeyConst( return_val, "at" ) ) );
	                        jsonObjectFree( return_val );
					    } while( dbi_result_next_row( result ));

						setPermLocationCache(ctx, perm, pcache);
					}
		
					dbi_result_free( result );
	            }
			}
        }

		int j = 0;
		while( (context_org = osrfStringArrayGetString( context_org_array, j++ )) ) {

            if (rs_size > perm_at_threshold) {
                if (osrfStringArrayContains( pcache, context_org )) {
                    OK = 1;
                    break;
                }
            }

			if( pkey_value ) {
				osrfLogDebug(
					OSRF_LOG_MARK,
					"Checking object permission [%s] for user %d "
							"on object %s (class %s) at org %d",
					perm,
					userid,
					pkey_value,
					osrfHashGet( class, "classname" ),
					atoi( context_org )
				);

				result = dbi_conn_queryf(
					writehandle,
					"SELECT permission.usr_has_object_perm(%d, '%s', '%s', '%s', %d) AS has_perm;",
					userid,
					perm,
					osrfHashGet( class, "classname" ),
					pkey_value,
					atoi( context_org )
				);

				if( result ) {
					osrfLogDebug(
						OSRF_LOG_MARK,
						"Received a result for object permission [%s] "
								"for user %d on object %s (class %s) at org %d",
						perm,
						userid,
						pkey_value,
						osrfHashGet( class, "classname" ),
						atoi( context_org )
					);

					if( dbi_result_first_row( result )) {
						jsonObject* return_val = oilsMakeJSONFromResult( result );
						const char* has_perm = jsonObjectGetString(
								jsonObjectGetKeyConst( return_val, "has_perm" ));

						osrfLogDebug(
							OSRF_LOG_MARK,
							"Status of object permission [%s] for user %d "
									"on object %s (class %s) at org %d is %s",
							perm,
							userid,
							pkey_value,
							osrfHashGet(class, "classname"),
							atoi(context_org),
							has_perm
						);

						if( *has_perm == 't' )
							OK = 1;
						jsonObjectFree( return_val );
					}

					dbi_result_free( result );
					if( OK )
						break;
				} else {
					const char* msg;
					int errnum = dbi_conn_error( writehandle, &msg );
					osrfLogWarning( OSRF_LOG_MARK,
						"Unable to call check object permissions: %d, %s",
						errnum, msg ? msg : "(No description available)" );
					if( !oilsIsDBConnected( writehandle ))
						osrfAppSessionPanic( ctx->session );
				}
			}

            if (rs_size > perm_at_threshold) break;

			osrfLogDebug( OSRF_LOG_MARK,
					"Checking non-object permission [%s] for user %d at org %d",
					perm, userid, atoi(context_org) );
			result = dbi_conn_queryf(
				writehandle,
				"SELECT permission.usr_has_perm(%d, '%s', %d) AS has_perm;",
				userid,
				perm,
				atoi( context_org )
			);

			if( result ) {
				osrfLogDebug( OSRF_LOG_MARK,
					"Received a result for permission [%s] for user %d at org %d",
					perm, userid, atoi( context_org ));
				if( dbi_result_first_row( result )) {
					jsonObject* return_val = oilsMakeJSONFromResult( result );
					const char* has_perm = jsonObjectGetString(
						jsonObjectGetKeyConst( return_val, "has_perm" ));
					osrfLogDebug( OSRF_LOG_MARK,
						"Status of permission [%s] for user %d at org %d is [%s]",
						perm, userid, atoi( context_org ), has_perm );
					if( *has_perm == 't' )
						OK = 1;
					jsonObjectFree( return_val );
				}

				dbi_result_free( result );
				if( OK )
					break;
			} else {
				const char* msg;
				int errnum = dbi_conn_error( writehandle, &msg );
				osrfLogWarning( OSRF_LOG_MARK, "Unable to call user object permissions: %d, %s",
					errnum, msg ? msg : "(No description available)" );
				if( !oilsIsDBConnected( writehandle ))
					osrfAppSessionPanic( ctx->session );
			}

		}

		if( OK )
			break;
	}

	osrfStringArrayFree( context_org_array );

	return OK;
}

/**
	@brief Look up the root of the org_unit tree.
	@param ctx Pointer to the method context.
	@return The id of the root org unit, as a character string.

	Query actor.org_unit where parent_ou is null, and return the id as a string.

	This function assumes that there is only one root org unit, i.e. that we
	have a single tree, not a forest.

	The calling code is responsible for freeing the returned string.
*/
static const char* org_tree_root( osrfMethodContext* ctx ) {

	static char cached_root_id[ 32 ] = "";  // extravagantly large buffer
	static time_t last_lookup_time = 0;
	time_t current_time = time( NULL );

	if( cached_root_id[ 0 ] && ( current_time - last_lookup_time < 3600 ) ) {
		// We successfully looked this up less than an hour ago.
		// It's not likely to have changed since then.
		return strdup( cached_root_id );
	}
	last_lookup_time = current_time;

	int err = 0;
	jsonObject* where_clause = single_hash( "parent_ou", NULL );
	jsonObject* result = doFieldmapperSearch(
		ctx, osrfHashGet( oilsIDL(), "aou" ), where_clause, NULL, &err );
	jsonObjectFree( where_clause );

	jsonObject* tree_top = jsonObjectGetIndex( result, 0 );

	if( !tree_top ) {
		jsonObjectFree( result );

		growing_buffer* msg = buffer_init( 128 );
		OSRF_BUFFER_ADD( msg, modulename );
		OSRF_BUFFER_ADD( msg,
				": Internal error, could not find the top of the org tree (parent_ou = NULL)" );

		char* m = buffer_release( msg );
		osrfAppSessionStatus( ctx->session,
				OSRF_STATUS_INTERNALSERVERERROR, "osrfMethodException", ctx->request, m );
		free( m );

		cached_root_id[ 0 ] = '\0';
		return NULL;
	}

	const char* root_org_unit_id = oilsFMGetStringConst( tree_top, "id" );
	osrfLogDebug( OSRF_LOG_MARK, "Top of the org tree is %s", root_org_unit_id );

	strcpy( cached_root_id, root_org_unit_id );
	jsonObjectFree( result );
	return cached_root_id;
}

/**
	@brief Create a JSON_HASH with a single key/value pair.
	@param key The key of the key/value pair.
	@param value the value of the key/value pair.
	@return Pointer to a newly created jsonObject of type JSON_HASH.

	The value of the key/value is either a string or (if @a value is NULL) a null.
*/
static jsonObject* single_hash( const char* key, const char* value ) {
	// Sanity check
	if( ! key ) key = "";

	jsonObject* hash = jsonNewObjectType( JSON_HASH );
	jsonObjectSetKey( hash, key, jsonNewObject( value ) );
	return hash;
}


int doCreate( osrfMethodContext* ctx ) {
	if(osrfMethodVerifyContext( ctx )) {
		osrfLogError( OSRF_LOG_MARK, "Invalid method context" );
		return -1;
	}

	if( enforce_pcrud )
		timeout_needs_resetting = 1;

	osrfHash* meta = osrfHashGet( (osrfHash*) ctx->method->userData, "class" );
	jsonObject* target = NULL;
	jsonObject* options = NULL;

	if( enforce_pcrud ) {
		target = jsonObjectGetIndex( ctx->params, 1 );
		options = jsonObjectGetIndex( ctx->params, 2 );
	} else {
		target = jsonObjectGetIndex( ctx->params, 0 );
		options = jsonObjectGetIndex( ctx->params, 1 );
	}

	if( !verifyObjectClass( ctx, target )) {
		osrfAppRespondComplete( ctx, NULL );
		return -1;
	}

	osrfLogDebug( OSRF_LOG_MARK, "Object seems to be of the correct type" );

	const char* trans_id = getXactId( ctx );
	if( !trans_id ) {
		osrfLogError( OSRF_LOG_MARK, "No active transaction -- required for CREATE" );

		osrfAppSessionStatus(
			ctx->session,
			OSRF_STATUS_BADREQUEST,
			"osrfMethodException",
			ctx->request,
			"No active transaction -- required for CREATE"
		);
		osrfAppRespondComplete( ctx, NULL );
		return -1;
	}

	// The following test is harmless but redundant.  If a class is
	// readonly, we don't register a create method for it.
	if( str_is_true( osrfHashGet( meta, "readonly" ) ) ) {
		osrfAppSessionStatus(
			ctx->session,
			OSRF_STATUS_BADREQUEST,
			"osrfMethodException",
			ctx->request,
			"Cannot INSERT readonly class"
		);
		osrfAppRespondComplete( ctx, NULL );
		return -1;
	}

	// Set the last_xact_id
	int index = oilsIDL_ntop( target->classname, "last_xact_id" );
	if( index > -1 ) {
		osrfLogDebug(OSRF_LOG_MARK, "Setting last_xact_id to %s on %s at position %d",
			trans_id, target->classname, index);
		jsonObjectSetIndex( target, index, jsonNewObject( trans_id ));
	}

	osrfLogDebug( OSRF_LOG_MARK, "There is a transaction running..." );

	dbhandle = writehandle;

	osrfHash* fields = osrfHashGet( meta, "fields" );
	char* pkey       = osrfHashGet( meta, "primarykey" );
	char* seq        = osrfHashGet( meta, "sequence" );

	growing_buffer* table_buf = buffer_init( 128 );
	growing_buffer* col_buf   = buffer_init( 128 );
	growing_buffer* val_buf   = buffer_init( 128 );

	OSRF_BUFFER_ADD( table_buf, "INSERT INTO " );
	OSRF_BUFFER_ADD( table_buf, osrfHashGet( meta, "tablename" ));
	OSRF_BUFFER_ADD_CHAR( col_buf, '(' );
	buffer_add( val_buf,"VALUES (" );


	int first = 1;
	osrfHash* field = NULL;
	osrfHashIterator* field_itr = osrfNewHashIterator( fields );
	while( (field = osrfHashIteratorNext( field_itr ) ) ) {

		const char* field_name = osrfHashIteratorKey( field_itr );

		if( str_is_true( osrfHashGet( field, "virtual" ) ) )
			continue;

		const jsonObject* field_object = oilsFMGetObject( target, field_name );

		char* value;
		if( field_object && field_object->classname ) {
			value = oilsFMGetString(
				field_object,
				(char*)oilsIDLFindPath( "/%s/primarykey", field_object->classname )
			);
		} else if( field_object && JSON_BOOL == field_object->type ) {
			if( jsonBoolIsTrue( field_object ) )
				value = strdup( "t" );
			else
				value = strdup( "f" );
		} else {
			value = jsonObjectToSimpleString( field_object );
		}

		if( first ) {
			first = 0;
		} else {
			OSRF_BUFFER_ADD_CHAR( col_buf, ',' );
			OSRF_BUFFER_ADD_CHAR( val_buf, ',' );
		}

		buffer_add( col_buf, field_name );

		if( !field_object || field_object->type == JSON_NULL ) {
			buffer_add( val_buf, "DEFAULT" );

		} else if( !strcmp( get_primitive( field ), "number" )) {
			const char* numtype = get_datatype( field );
			if( !strcmp( numtype, "INT8" )) {
				buffer_fadd( val_buf, "%lld", atoll( value ));

			} else if( !strcmp( numtype, "INT" )) {
				buffer_fadd( val_buf, "%d", atoi( value ));

			} else if( !strcmp( numtype, "NUMERIC" )) {
				buffer_fadd( val_buf, "%f", atof( value ));
			}
		} else {
			if( dbi_conn_quote_string( writehandle, &value )) {
				OSRF_BUFFER_ADD( val_buf, value );

			} else {
				osrfLogError( OSRF_LOG_MARK, "%s: Error quoting string [%s]", modulename, value );
				osrfAppSessionStatus(
					ctx->session,
					OSRF_STATUS_INTERNALSERVERERROR,
					"osrfMethodException",
					ctx->request,
					"Error quoting string -- please see the error log for more details"
				);
				free( value );
				buffer_free( table_buf );
				buffer_free( col_buf );
				buffer_free( val_buf );
				osrfAppRespondComplete( ctx, NULL );
				return -1;
			}
		}

		free( value );
	}

	osrfHashIteratorFree( field_itr );

	OSRF_BUFFER_ADD_CHAR( col_buf, ')' );
	OSRF_BUFFER_ADD_CHAR( val_buf, ')' );

	char* table_str = buffer_release( table_buf );
	char* col_str   = buffer_release( col_buf );
	char* val_str   = buffer_release( val_buf );
	growing_buffer* sql = buffer_init( 128 );
	buffer_fadd( sql, "%s %s %s;", table_str, col_str, val_str );
	free( table_str );
	free( col_str );
	free( val_str );

	char* query = buffer_release( sql );

	osrfLogDebug( OSRF_LOG_MARK, "%s: Insert SQL [%s]", modulename, query );

	jsonObject* obj = NULL;
	int rc = 0;

	dbi_result result = dbi_conn_query( writehandle, query );
	if( !result ) {
		obj = jsonNewObject( NULL );
		const char* msg;
		int errnum = dbi_conn_error( writehandle, &msg );
		osrfLogError(
			OSRF_LOG_MARK,
			"%s ERROR inserting %s object using query [%s]: %d %s",
			modulename,
			osrfHashGet(meta, "fieldmapper"),
			query,
			errnum,
			msg ? msg : "(No description available)"
		);
		osrfAppSessionStatus(
			ctx->session,
			OSRF_STATUS_INTERNALSERVERERROR,
			"osrfMethodException",
			ctx->request,
			"INSERT error -- please see the error log for more details"
		);
		if( !oilsIsDBConnected( writehandle ))
			osrfAppSessionPanic( ctx->session );
		rc = -1;
	} else {
		dbi_result_free( result );

		char* id = oilsFMGetString( target, pkey );
		if( !id ) {
			unsigned long long new_id = dbi_conn_sequence_last( writehandle, seq );
			growing_buffer* _id = buffer_init( 10 );
			buffer_fadd( _id, "%lld", new_id );
			id = buffer_release( _id );
		}

		// Find quietness specification, if present
		const char* quiet_str = NULL;
		if( options ) {
			const jsonObject* quiet_obj = jsonObjectGetKeyConst( options, "quiet" );
			if( quiet_obj )
				quiet_str = jsonObjectGetString( quiet_obj );
		}

		if( str_is_true( quiet_str )) {  // if quietness is specified
			obj = jsonNewObject( id );
		}
		else {

			// Fetch the row that we just inserted, so that we can return it to the client
			jsonObject* where_clause = jsonNewObjectType( JSON_HASH );
			jsonObjectSetKey( where_clause, pkey, jsonNewObject( id ));

			int err = 0;
			jsonObject* list = doFieldmapperSearch( ctx, meta, where_clause, NULL, &err );
			if( err )
				rc = -1;
			else
				obj = jsonObjectClone( jsonObjectGetIndex( list, 0 ));

			jsonObjectFree( list );
			jsonObjectFree( where_clause );
		}

		free( id );
	}

	free( query );
	osrfAppRespondComplete( ctx, obj );
	jsonObjectFree( obj );
	return rc;
}

/**
	@brief Implement the retrieve method.
	@param ctx Pointer to the method context.
	@param err Pointer through which to return an error code.
	@return If successful, a pointer to the result to be returned to the client;
	otherwise NULL.

	From the method's class, fetch a row with a specified value in the primary key.  This
	method relies on the database design convention that a primary key consists of a single
	column.

	Method parameters:
	- authkey (PCRUD only)
	- value of the primary key for the desired row, for building the WHERE clause
	- a JSON_HASH containing any other SQL clauses: select, join, etc.

	Return to client: One row from the query.
*/
int doRetrieve( osrfMethodContext* ctx ) {
	if(osrfMethodVerifyContext( ctx )) {
		osrfLogError( OSRF_LOG_MARK, "Invalid method context" );
		return -1;
	}

	if( enforce_pcrud )
		timeout_needs_resetting = 1;

	int id_pos = 0;
	int order_pos = 1;

	if( enforce_pcrud ) {
		id_pos = 1;
		order_pos = 2;
	}

	// Get the class metadata
	osrfHash* class_def = osrfHashGet( (osrfHash*) ctx->method->userData, "class" );

	// Get the value of the primary key, from a method parameter
	const jsonObject* id_obj = jsonObjectGetIndex( ctx->params, id_pos );

	osrfLogDebug(
		OSRF_LOG_MARK,
		"%s retrieving %s object with primary key value of %s",
		modulename,
		osrfHashGet( class_def, "fieldmapper" ),
		jsonObjectGetString( id_obj )
	);

	// Build a WHERE clause based on the key value
	jsonObject* where_clause = jsonNewObjectType( JSON_HASH );
	jsonObjectSetKey(
		where_clause,
		osrfHashGet( class_def, "primarykey" ),  // name of key column
		jsonObjectClone( id_obj )                // value of key column
	);

	jsonObject* rest_of_query = jsonObjectGetIndex( ctx->params, order_pos );

	// Do the query
	int err = 0;
	jsonObject* list = doFieldmapperSearch( ctx, class_def, where_clause, rest_of_query, &err );

	jsonObjectFree( where_clause );
	if( err ) {
		osrfAppRespondComplete( ctx, NULL );
		return -1;
	}

	jsonObject* obj = jsonObjectExtractIndex( list, 0 );
	jsonObjectFree( list );

	if( enforce_pcrud ) {
		// no result, skip this entirely
		if(NULL != obj && !verifyObjectPCRUD( ctx, class_def, obj, 1 )) {
			jsonObjectFree( obj );

			growing_buffer* msg = buffer_init( 128 );
			OSRF_BUFFER_ADD( msg, modulename );
			OSRF_BUFFER_ADD( msg, ": Insufficient permissions to retrieve object" );

			char* m = buffer_release( msg );
			osrfAppSessionStatus( ctx->session, OSRF_STATUS_NOTALLOWED, "osrfMethodException",
					ctx->request, m );
			free( m );

			osrfAppRespondComplete( ctx, NULL );
			return -1;
		}
	}

	// doFieldmapperSearch() now does the responding for us
	//osrfAppRespondComplete( ctx, obj );
	osrfAppRespondComplete( ctx, NULL );

	jsonObjectFree( obj );
	return 0;
}

/**
	@brief Translate a numeric value to a string representation for the database.
	@param field Pointer to the IDL field definition.
	@param value Pointer to a jsonObject holding the value of a field.
	@return Pointer to a newly allocated string.

	The input object is typically a JSON_NUMBER, but it may be a JSON_STRING as long as
	its contents are numeric.  A non-numeric string is likely to result in invalid SQL,
	or (what is worse) valid SQL that is wrong.

	If the datatype of the receiving field is not numeric, wrap the value in quotes.

	The calling code is responsible for freeing the resulting string by calling free().
*/
static char* jsonNumberToDBString( osrfHash* field, const jsonObject* value ) {
	growing_buffer* val_buf = buffer_init( 32 );
	const char* numtype = get_datatype( field );

	// For historical reasons the following contains cruft that could be cleaned up.
	if( !strncmp( numtype, "INT", 3 ) ) {
		if( value->type == JSON_NUMBER )
			//buffer_fadd( val_buf, "%ld", (long)jsonObjectGetNumber(value) );
			buffer_fadd( val_buf, jsonObjectGetString( value ) );
		else {
			buffer_fadd( val_buf, jsonObjectGetString( value ) );
		}

	} else if( !strcmp( numtype, "NUMERIC" )) {
		if( value->type == JSON_NUMBER )
			buffer_fadd( val_buf, jsonObjectGetString( value ));
		else {
			buffer_fadd( val_buf, jsonObjectGetString( value ));
		}

	} else {
		// Presumably this was really intended to be a string, so quote it
		char* str = jsonObjectToSimpleString( value );
		if( dbi_conn_quote_string( dbhandle, &str )) {
			OSRF_BUFFER_ADD( val_buf, str );
			free( str );
		} else {
			osrfLogError( OSRF_LOG_MARK, "%s: Error quoting key string [%s]", modulename, str );
			free( str );
			buffer_free( val_buf );
			return NULL;
		}
	}

	return buffer_release( val_buf );
}

static char* searchINPredicate( const char* class_alias, osrfHash* field,
		jsonObject* node, const char* op, osrfMethodContext* ctx ) {
	growing_buffer* sql_buf = buffer_init( 32 );

	buffer_fadd(
		sql_buf,
		"\"%s\".%s ",
		class_alias,
		osrfHashGet( field, "name" )
	);

	if( !op ) {
		buffer_add( sql_buf, "IN (" );
	} else if( !strcasecmp( op,"not in" )) {
		buffer_add( sql_buf, "NOT IN (" );
	} else {
		buffer_add( sql_buf, "IN (" );
	}

	if( node->type == JSON_HASH ) {
		// subquery predicate
		char* subpred = buildQuery( ctx, node, SUBSELECT );
		if( ! subpred ) {
			buffer_free( sql_buf );
			return NULL;
		}

		buffer_add( sql_buf, subpred );
		free( subpred );

	} else if( node->type == JSON_ARRAY ) {
		// literal value list
		int in_item_index = 0;
		int in_item_first = 1;
		const jsonObject* in_item;
		while( (in_item = jsonObjectGetIndex( node, in_item_index++ )) ) {

			if( in_item_first )
				in_item_first = 0;
			else
				buffer_add( sql_buf, ", " );

			// Sanity check
			if( in_item->type != JSON_STRING && in_item->type != JSON_NUMBER ) {
				osrfLogError( OSRF_LOG_MARK,
						"%s: Expected string or number within IN list; found %s",
						modulename, json_type( in_item->type ) );
				buffer_free( sql_buf );
				return NULL;
			}

			// Append the literal value -- quoted if not a number
			if( JSON_NUMBER == in_item->type ) {
				char* val = jsonNumberToDBString( field, in_item );
				OSRF_BUFFER_ADD( sql_buf, val );
				free( val );

			} else if( !strcmp( get_primitive( field ), "number" )) {
				char* val = jsonNumberToDBString( field, in_item );
				OSRF_BUFFER_ADD( sql_buf, val );
				free( val );

			} else {
				char* key_string = jsonObjectToSimpleString( in_item );
				if( dbi_conn_quote_string( dbhandle, &key_string )) {
					OSRF_BUFFER_ADD( sql_buf, key_string );
					free( key_string );
				} else {
					osrfLogError( OSRF_LOG_MARK,
							"%s: Error quoting key string [%s]", modulename, key_string );
					free( key_string );
					buffer_free( sql_buf );
					return NULL;
				}
			}
		}

		if( in_item_first ) {
			osrfLogError(OSRF_LOG_MARK, "%s: Empty IN list", modulename );
			buffer_free( sql_buf );
			return NULL;
		}
	} else {
		osrfLogError( OSRF_LOG_MARK, "%s: Expected object or array for IN clause; found %s",
			modulename, json_type( node->type ));
		buffer_free( sql_buf );
		return NULL;
	}

	OSRF_BUFFER_ADD_CHAR( sql_buf, ')' );

	return buffer_release( sql_buf );
}

// Receive a JSON_ARRAY representing a function call.  The first
// entry in the array is the function name.  The rest are parameters.
static char* searchValueTransform( const jsonObject* array ) {

	if( array->size < 1 ) {
		osrfLogError( OSRF_LOG_MARK, "%s: Empty array for value transform", modulename );
		return NULL;
	}

	// Get the function name
	jsonObject* func_item = jsonObjectGetIndex( array, 0 );
	if( func_item->type != JSON_STRING ) {
		osrfLogError( OSRF_LOG_MARK, "%s: Error: expected function name, found %s",
			modulename, json_type( func_item->type ));
		return NULL;
	}

	growing_buffer* sql_buf = buffer_init( 32 );

	OSRF_BUFFER_ADD( sql_buf, jsonObjectGetString( func_item ) );
	OSRF_BUFFER_ADD( sql_buf, "( " );

	// Get the parameters
	int func_item_index = 1;   // We already grabbed the zeroth entry
	while( (func_item = jsonObjectGetIndex( array, func_item_index++ )) ) {

		// Add a separator comma, if we need one
		if( func_item_index > 2 )
			buffer_add( sql_buf, ", " );

		// Add the current parameter
		if( func_item->type == JSON_NULL ) {
			buffer_add( sql_buf, "NULL" );
		} else {
			if( func_item->type == JSON_BOOL ) {
				if( jsonBoolIsTrue(func_item) ) {
					buffer_add( sql_buf, "TRUE" );
				} else {
					buffer_add( sql_buf, "FALSE" );
				}
			} else {
				char* val = jsonObjectToSimpleString( func_item );
				if( dbi_conn_quote_string( dbhandle, &val )) {
					OSRF_BUFFER_ADD( sql_buf, val );
					free( val );
				} else {
					osrfLogError( OSRF_LOG_MARK, 
						"%s: Error quoting key string [%s]", modulename, val );
					buffer_free( sql_buf );
					free( val );
					return NULL;
				}
			}
		}
	}

	buffer_add( sql_buf, " )" );

	return buffer_release( sql_buf );
}

static char* searchFunctionPredicate( const char* class_alias, osrfHash* field,
		const jsonObject* node, const char* op ) {

	if( ! is_good_operator( op ) ) {
		osrfLogError( OSRF_LOG_MARK, "%s: Invalid operator [%s]", modulename, op );
		return NULL;
	}

	char* val = searchValueTransform( node );
	if( !val )
		return NULL;

	growing_buffer* sql_buf = buffer_init( 32 );
	buffer_fadd(
		sql_buf,
		"\"%s\".%s %s %s",
		class_alias,
		osrfHashGet( field, "name" ),
		op,
		val
	);

	free( val );

	return buffer_release( sql_buf );
}

// class_alias is a class name or other table alias
// field is a field definition as stored in the IDL
// node comes from the method parameter, and may represent an entry in the SELECT list
static char* searchFieldTransform( const char* class_alias, osrfHash* field,
		const jsonObject* node ) {
	growing_buffer* sql_buf = buffer_init( 32 );

	const char* field_transform = jsonObjectGetString(
		jsonObjectGetKeyConst( node, "transform" ) );
	const char* transform_subcolumn = jsonObjectGetString(
		jsonObjectGetKeyConst( node, "result_field" ) );

	if( transform_subcolumn ) {
		if( ! is_identifier( transform_subcolumn ) ) {
			osrfLogError( OSRF_LOG_MARK, "%s: Invalid subfield name: \"%s\"\n",
					modulename, transform_subcolumn );
			buffer_free( sql_buf );
			return NULL;
		}
		OSRF_BUFFER_ADD_CHAR( sql_buf, '(' );    // enclose transform in parentheses
	}

	if( field_transform ) {

		if( ! is_identifier( field_transform ) ) {
			osrfLogError( OSRF_LOG_MARK, "%s: Expected function name, found \"%s\"\n",
					modulename, field_transform );
			buffer_free( sql_buf );
			return NULL;
		}

		if( obj_is_true( jsonObjectGetKeyConst( node, "distinct" ) ) ) {
			buffer_fadd( sql_buf, "%s(DISTINCT \"%s\".%s",
				field_transform, class_alias, osrfHashGet( field, "name" ));
		} else {
			buffer_fadd( sql_buf, "%s(\"%s\".%s",
				field_transform, class_alias, osrfHashGet( field, "name" ));
		}

		const jsonObject* array = jsonObjectGetKeyConst( node, "params" );

		if( array ) {
			if( array->type != JSON_ARRAY ) {
				osrfLogError( OSRF_LOG_MARK,
					"%s: Expected JSON_ARRAY for function params; found %s",
					modulename, json_type( array->type ) );
				buffer_free( sql_buf );
				return NULL;
			}
			int func_item_index = 0;
			jsonObject* func_item;
			while( (func_item = jsonObjectGetIndex( array, func_item_index++ ))) {

				char* val = jsonObjectToSimpleString( func_item );

				if( !val ) {
					buffer_add( sql_buf, ",NULL" );
				} else if( dbi_conn_quote_string( dbhandle, &val )) {
					OSRF_BUFFER_ADD_CHAR( sql_buf, ',' );
					OSRF_BUFFER_ADD( sql_buf, val );
				} else {
					osrfLogError( OSRF_LOG_MARK,
							"%s: Error quoting key string [%s]", modulename, val );
					free( val );
					buffer_free( sql_buf );
					return NULL;
				}
				free( val );
			}
		}

		buffer_add( sql_buf, " )" );

	} else {
		buffer_fadd( sql_buf, "\"%s\".%s", class_alias, osrfHashGet( field, "name" ));
	}

	if( transform_subcolumn )
		buffer_fadd( sql_buf, ").\"%s\"", transform_subcolumn );

	return buffer_release( sql_buf );
}

static char* searchFieldTransformPredicate( const ClassInfo* class_info, osrfHash* field,
		const jsonObject* node, const char* op ) {

	if( ! is_good_operator( op ) ) {
		osrfLogError( OSRF_LOG_MARK, "%s: Error: Invalid operator %s", modulename, op );
		return NULL;
	}

	char* field_transform = searchFieldTransform( class_info->alias, field, node );
	if( ! field_transform )
		return NULL;
	char* value = NULL;
	int extra_parens = 0;   // boolean

	const jsonObject* value_obj = jsonObjectGetKeyConst( node, "value" );
	if( ! value_obj ) {
		value = searchWHERE( node, class_info, AND_OP_JOIN, NULL );
		if( !value ) {
			osrfLogError( OSRF_LOG_MARK, "%s: Error building condition for field transform",
				modulename );
			free( field_transform );
			return NULL;
		}
		extra_parens = 1;
	} else if( value_obj->type == JSON_ARRAY ) {
		value = searchValueTransform( value_obj );
		if( !value ) {
			osrfLogError( OSRF_LOG_MARK,
				"%s: Error building value transform for field transform", modulename );
			free( field_transform );
			return NULL;
		}
	} else if( value_obj->type == JSON_HASH ) {
		value = searchWHERE( value_obj, class_info, AND_OP_JOIN, NULL );
		if( !value ) {
			osrfLogError( OSRF_LOG_MARK, "%s: Error building predicate for field transform",
				modulename );
			free( field_transform );
			return NULL;
		}
		extra_parens = 1;
	} else if( value_obj->type == JSON_NUMBER ) {
		value = jsonNumberToDBString( field, value_obj );
	} else if( value_obj->type == JSON_NULL ) {
		osrfLogError( OSRF_LOG_MARK,
			"%s: Error building predicate for field transform: null value", modulename );
		free( field_transform );
		return NULL;
	} else if( value_obj->type == JSON_BOOL ) {
		osrfLogError( OSRF_LOG_MARK,
			"%s: Error building predicate for field transform: boolean value", modulename );
		free( field_transform );
		return NULL;
	} else {
		if( !strcmp( get_primitive( field ), "number") ) {
			value = jsonNumberToDBString( field, value_obj );
		} else {
			value = jsonObjectToSimpleString( value_obj );
			if( !dbi_conn_quote_string( dbhandle, &value )) {
				osrfLogError( OSRF_LOG_MARK, "%s: Error quoting key string [%s]",
					modulename, value );
				free( value );
				free( field_transform );
				return NULL;
			}
		}
	}

	const char* left_parens  = "";
	const char* right_parens = "";

	if( extra_parens ) {
		left_parens  = "(";
		right_parens = ")";
	}

	const char* right_percent = "";
	const char* real_op       = op;

	if( !strcasecmp( op, "startwith") ) {
		real_op = "like";
		right_percent = "|| '%'";
	}

	growing_buffer* sql_buf = buffer_init( 32 );

	buffer_fadd(
		sql_buf,
		"%s%s %s %s %s%s %s%s",
		left_parens,
		field_transform,
		real_op,
		left_parens,
		value,
		right_percent,
		right_parens,
		right_parens
	);

	free( value );
	free( field_transform );

	return buffer_release( sql_buf );
}

static char* searchSimplePredicate( const char* op, const char* class_alias,
		osrfHash* field, const jsonObject* node ) {

	if( ! is_good_operator( op ) ) {
		osrfLogError( OSRF_LOG_MARK, "%s: Invalid operator [%s]", modulename, op );
		return NULL;
	}

	char* val = NULL;

	// Get the value to which we are comparing the specified column
	if( node->type != JSON_NULL ) {
		if( node->type == JSON_NUMBER ) {
			val = jsonNumberToDBString( field, node );
		} else if( !strcmp( get_primitive( field ), "number" ) ) {
			val = jsonNumberToDBString( field, node );
		} else {
			val = jsonObjectToSimpleString( node );
		}
	}

	if( val ) {
		if( JSON_NUMBER != node->type && strcmp( get_primitive( field ), "number") ) {
			// Value is not numeric; enclose it in quotes
			if( !dbi_conn_quote_string( dbhandle, &val ) ) {
				osrfLogError( OSRF_LOG_MARK, "%s: Error quoting key string [%s]",
					modulename, val );
				free( val );
				return NULL;
			}
		}
	} else {
		// Compare to a null value
		val = strdup( "NULL" );
		if( strcmp( op, "=" ))
			op = "IS NOT";
		else
			op = "IS";
	}

	growing_buffer* sql_buf = buffer_init( 32 );
	buffer_fadd( sql_buf, "\"%s\".%s %s %s", class_alias, osrfHashGet(field, "name"), op, val );
	char* pred = buffer_release( sql_buf );

	free( val );

	return pred;
}

static char* searchBETWEENPredicate( const char* class_alias,
		osrfHash* field, const jsonObject* node ) {

	const jsonObject* x_node = jsonObjectGetIndex( node, 0 );
	const jsonObject* y_node = jsonObjectGetIndex( node, 1 );

	if( NULL == y_node ) {
		osrfLogError( OSRF_LOG_MARK, "%s: Not enough operands for BETWEEN operator", modulename );
		return NULL;
	}
	else if( NULL != jsonObjectGetIndex( node, 2 ) ) {
		osrfLogError( OSRF_LOG_MARK, "%s: Too many operands for BETWEEN operator", modulename );
		return NULL;
	}

	char* x_string;
	char* y_string;

	if( !strcmp( get_primitive( field ), "number") ) {
		x_string = jsonNumberToDBString( field, x_node );
		y_string = jsonNumberToDBString( field, y_node );

	} else {
		x_string = jsonObjectToSimpleString( x_node );
		y_string = jsonObjectToSimpleString( y_node );
		if( !(dbi_conn_quote_string( dbhandle, &x_string )
			&& dbi_conn_quote_string( dbhandle, &y_string )) ) {
			osrfLogError( OSRF_LOG_MARK, "%s: Error quoting key strings [%s] and [%s]",
					modulename, x_string, y_string );
			free( x_string );
			free( y_string );
			return NULL;
		}
	}

	growing_buffer* sql_buf = buffer_init( 32 );
	buffer_fadd( sql_buf, "\"%s\".%s BETWEEN %s AND %s",
			class_alias, osrfHashGet( field, "name" ), x_string, y_string );
	free( x_string );
	free( y_string );

	return buffer_release( sql_buf );
}

static char* searchPredicate( const ClassInfo* class_info, osrfHash* field,
							  jsonObject* node, osrfMethodContext* ctx ) {

	char* pred = NULL;
	if( node->type == JSON_ARRAY ) { // equality IN search
		pred = searchINPredicate( class_info->alias, field, node, NULL, ctx );
	} else if( node->type == JSON_HASH ) { // other search
		jsonIterator* pred_itr = jsonNewIterator( node );
		if( !jsonIteratorHasNext( pred_itr ) ) {
			osrfLogError( OSRF_LOG_MARK, "%s: Empty predicate for field \"%s\"",
					modulename, osrfHashGet(field, "name" ));
		} else {
			jsonObject* pred_node = jsonIteratorNext( pred_itr );

			// Verify that there are no additional predicates
			if( jsonIteratorHasNext( pred_itr ) ) {
				osrfLogError( OSRF_LOG_MARK, "%s: Multiple predicates for field \"%s\"",
						modulename, osrfHashGet(field, "name" ));
			} else if( !(strcasecmp( pred_itr->key,"between" )) )
				pred = searchBETWEENPredicate( class_info->alias, field, pred_node );
			else if( !(strcasecmp( pred_itr->key,"in" ))
					|| !(strcasecmp( pred_itr->key,"not in" )) )
				pred = searchINPredicate(
					class_info->alias, field, pred_node, pred_itr->key, ctx );
			else if( pred_node->type == JSON_ARRAY )
				pred = searchFunctionPredicate(
					class_info->alias, field, pred_node, pred_itr->key );
			else if( pred_node->type == JSON_HASH )
				pred = searchFieldTransformPredicate(
					class_info, field, pred_node, pred_itr->key );
			else
				pred = searchSimplePredicate( pred_itr->key, class_info->alias, field, pred_node );
		}
		jsonIteratorFree( pred_itr );

	} else if( node->type == JSON_NULL ) { // IS NULL search
		growing_buffer* _p = buffer_init( 64 );
		buffer_fadd(
			_p,
			"\"%s\".%s IS NULL",
			class_info->alias,
			osrfHashGet( field, "name" )
		);
		pred = buffer_release( _p );
	} else { // equality search
		pred = searchSimplePredicate( "=", class_info->alias, field, node );
	}

	return pred;

}


/*

join : {
	acn : {
		field : record,
		fkey : id
		type : left
		filter_op : or
		filter : { ... },
		join : {
			acp : {
				field : call_number,
				fkey : id,
				filter : { ... },
			},
		},
	},
	mrd : {
		field : record,
		type : inner
		fkey : id,
		filter : { ... },
	}
}

*/

static char* searchJOIN( const jsonObject* join_hash, const ClassInfo* left_info ) {

	const jsonObject* working_hash;
	jsonObject* freeable_hash = NULL;

	if( join_hash->type == JSON_HASH ) {
		working_hash = join_hash;
	} else if( join_hash->type == JSON_STRING ) {
		// turn it into a JSON_HASH by creating a wrapper
		// around a copy of the original
		const char* _tmp = jsonObjectGetString( join_hash );
		freeable_hash = jsonNewObjectType( JSON_HASH );
		jsonObjectSetKey( freeable_hash, _tmp, NULL );
		working_hash = freeable_hash;
	} else {
		osrfLogError(
			OSRF_LOG_MARK,
			"%s: JOIN failed; expected JSON object type not found",
			modulename
		);
		return NULL;
	}

	growing_buffer* join_buf = buffer_init( 128 );
	const char* leftclass = left_info->class_name;

	jsonObject* snode = NULL;
	jsonIterator* search_itr = jsonNewIterator( working_hash );

	while ( (snode = jsonIteratorNext( search_itr )) ) {
		const char* right_alias = search_itr->key;
		const char* class =
				jsonObjectGetString( jsonObjectGetKeyConst( snode, "class" ) );
		if( ! class )
			class = right_alias;

		const ClassInfo* right_info = add_joined_class( right_alias, class );
		if( !right_info ) {
			osrfLogError(
				OSRF_LOG_MARK,
				"%s: JOIN failed.  Class \"%s\" not resolved in IDL",
				modulename,
				search_itr->key
			);
			jsonIteratorFree( search_itr );
			buffer_free( join_buf );
			if( freeable_hash )
				jsonObjectFree( freeable_hash );
			return NULL;
		}
		osrfHash* links    = right_info->links;
		const char* table  = right_info->source_def;

		const char* fkey  = jsonObjectGetString( jsonObjectGetKeyConst( snode, "fkey" ) );
		const char* field = jsonObjectGetString( jsonObjectGetKeyConst( snode, "field" ) );

		if( field && !fkey ) {
			// Look up the corresponding join column in the IDL.
			// The link must be defined in the child table,
			// and point to the right parent table.
			osrfHash* idl_link = (osrfHash*) osrfHashGet( links, field );
			const char* reltype = NULL;
			const char* other_class = NULL;
			reltype = osrfHashGet( idl_link, "reltype" );
			if( reltype && strcmp( reltype, "has_many" ) )
				other_class = osrfHashGet( idl_link, "class" );
			if( other_class && !strcmp( other_class, leftclass ) )
				fkey = osrfHashGet( idl_link, "key" );
			if( !fkey ) {
				osrfLogError(
					OSRF_LOG_MARK,
					"%s: JOIN failed.  No link defined from %s.%s to %s",
					modulename,
					class,
					field,
					leftclass
				);
				buffer_free( join_buf );
				if( freeable_hash )
					jsonObjectFree( freeable_hash );
				jsonIteratorFree( search_itr );
				return NULL;
			}

		} else if( !field && fkey ) {
			// Look up the corresponding join column in the IDL.
			// The link must be defined in the child table,
			// and point to the right parent table.
			osrfHash* left_links = left_info->links;
			osrfHash* idl_link = (osrfHash*) osrfHashGet( left_links, fkey );
			const char* reltype = NULL;
			const char* other_class = NULL;
			reltype = osrfHashGet( idl_link, "reltype" );
			if( reltype && strcmp( reltype, "has_many" ) )
				other_class = osrfHashGet( idl_link, "class" );
			if( other_class && !strcmp( other_class, class ) )
				field = osrfHashGet( idl_link, "key" );
			if( !field ) {
				osrfLogError(
					OSRF_LOG_MARK,
					"%s: JOIN failed.  No link defined from %s.%s to %s",
					modulename,
					leftclass,
					fkey,
					class
				);
				buffer_free( join_buf );
				if( freeable_hash )
					jsonObjectFree( freeable_hash );
				jsonIteratorFree( search_itr );
				return NULL;
			}

		} else if( !field && !fkey ) {
			osrfHash* left_links = left_info->links;

			// For each link defined for the left class:
			// see if the link references the joined class
			osrfHashIterator* itr = osrfNewHashIterator( left_links );
			osrfHash* curr_link = NULL;
			while( (curr_link = osrfHashIteratorNext( itr ) ) ) {
				const char* other_class = osrfHashGet( curr_link, "class" );
				if( other_class && !strcmp( other_class, class ) ) {

					// In the IDL, the parent class doesn't always know then names of the child
					// columns that are pointing to it, so don't use that end of the link
					const char* reltype = osrfHashGet( curr_link, "reltype" );
					if( reltype && strcmp( reltype, "has_many" ) ) {
						// Found a link between the classes
						fkey = osrfHashIteratorKey( itr );
						field = osrfHashGet( curr_link, "key" );
						break;
					}
				}
			}
			osrfHashIteratorFree( itr );

			if( !field || !fkey ) {
				// Do another such search, with the classes reversed

				// For each link defined for the joined class:
				// see if the link references the left class
				osrfHashIterator* itr = osrfNewHashIterator( links );
				osrfHash* curr_link = NULL;
				while( (curr_link = osrfHashIteratorNext( itr ) ) ) {
					const char* other_class = osrfHashGet( curr_link, "class" );
					if( other_class && !strcmp( other_class, leftclass ) ) {

						// In the IDL, the parent class doesn't know then names of the child
						// columns that are pointing to it, so don't use that end of the link
						const char* reltype = osrfHashGet( curr_link, "reltype" );
						if( reltype && strcmp( reltype, "has_many" ) ) {
							// Found a link between the classes
							field = osrfHashIteratorKey( itr );
							fkey = osrfHashGet( curr_link, "key" );
							break;
						}
					}
				}
				osrfHashIteratorFree( itr );
			}

			if( !field || !fkey ) {
				osrfLogError(
					OSRF_LOG_MARK,
					"%s: JOIN failed.  No link defined between %s and %s",
					modulename,
					leftclass,
					class
				);
				buffer_free( join_buf );
				if( freeable_hash )
					jsonObjectFree( freeable_hash );
				jsonIteratorFree( search_itr );
				return NULL;
			}
		}

		const char* type = jsonObjectGetString( jsonObjectGetKeyConst( snode, "type" ) );
		if( type ) {
			if( !strcasecmp( type,"left" )) {
				buffer_add( join_buf, " LEFT JOIN" );
			} else if( !strcasecmp( type,"right" )) {
				buffer_add( join_buf, " RIGHT JOIN" );
			} else if( !strcasecmp( type,"full" )) {
				buffer_add( join_buf, " FULL JOIN" );
			} else {
				buffer_add( join_buf, " INNER JOIN" );
			}
		} else {
			buffer_add( join_buf, " INNER JOIN" );
		}

		buffer_fadd( join_buf, " %s AS \"%s\" ON ( \"%s\".%s = \"%s\".%s",
					table, right_alias, right_alias, field, left_info->alias, fkey );

		// Add any other join conditions as specified by "filter"
		const jsonObject* filter = jsonObjectGetKeyConst( snode, "filter" );
		if( filter ) {
			const char* filter_op = jsonObjectGetString(
				jsonObjectGetKeyConst( snode, "filter_op" ) );
			if( filter_op && !strcasecmp( "or",filter_op )) {
				buffer_add( join_buf, " OR " );
			} else {
				buffer_add( join_buf, " AND " );
			}

			char* jpred = searchWHERE( filter, right_info, AND_OP_JOIN, NULL );
			if( jpred ) {
				OSRF_BUFFER_ADD_CHAR( join_buf, ' ' );
				OSRF_BUFFER_ADD( join_buf, jpred );
				free( jpred );
			} else {
				osrfLogError(
					OSRF_LOG_MARK,
					"%s: JOIN failed.  Invalid conditional expression.",
					modulename
				);
				jsonIteratorFree( search_itr );
				buffer_free( join_buf );
				if( freeable_hash )
					jsonObjectFree( freeable_hash );
				return NULL;
			}
		}

		buffer_add( join_buf, " ) " );

		// Recursively add a nested join, if one is present
		const jsonObject* join_filter = jsonObjectGetKeyConst( snode, "join" );
		if( join_filter ) {
			char* jpred = searchJOIN( join_filter, right_info );
			if( jpred ) {
				OSRF_BUFFER_ADD_CHAR( join_buf, ' ' );
				OSRF_BUFFER_ADD( join_buf, jpred );
				free( jpred );
			} else {
				osrfLogError( OSRF_LOG_MARK, "%s: Invalid nested join.", modulename );
				jsonIteratorFree( search_itr );
				buffer_free( join_buf );
				if( freeable_hash )
					jsonObjectFree( freeable_hash );
				return NULL;
			}
		}
	}

	if( freeable_hash )
		jsonObjectFree( freeable_hash );
	jsonIteratorFree( search_itr );

	return buffer_release( join_buf );
}

/*

{ +class : { -or|-and : { field : { op : value }, ... } ... }, ... }
{ +class : { -or|-and : [ { field : { op : value }, ... }, ...] ... }, ... }
[ { +class : { -or|-and : [ { field : { op : value }, ... }, ...] ... }, ... }, ... ]

Generate code to express a set of conditions, as for a WHERE clause.  Parameters:

search_hash is the JSON expression of the conditions.
meta is the class definition from the IDL, for the relevant table.
opjoin_type indicates whether multiple conditions, if present, should be
	connected by AND or OR.
osrfMethodContext is loaded with all sorts of stuff, but all we do with it here is
	to pass it to other functions -- and all they do with it is to use the session
	and request members to send error messages back to the client.

*/

static char* searchWHERE( const jsonObject* search_hash, const ClassInfo* class_info,
		int opjoin_type, osrfMethodContext* ctx ) {

	osrfLogDebug(
		OSRF_LOG_MARK,
		"%s: Entering searchWHERE; search_hash addr = %p, meta addr = %p, "
		"opjoin_type = %d, ctx addr = %p",
		modulename,
		search_hash,
		class_info->class_def,
		opjoin_type,
		ctx
	);

	growing_buffer* sql_buf = buffer_init( 128 );

	jsonObject* node = NULL;

	int first = 1;
	if( search_hash->type == JSON_ARRAY ) {
		if( 0 == search_hash->size ) {
			osrfLogError(
				OSRF_LOG_MARK,
				"%s: Invalid predicate structure: empty JSON array",
				modulename
			);
			buffer_free( sql_buf );
			return NULL;
		}

		unsigned long i = 0;
		while(( node = jsonObjectGetIndex( search_hash, i++ ) )) {
			if( first ) {
				first = 0;
			} else {
				if( opjoin_type == OR_OP_JOIN )
					buffer_add( sql_buf, " OR " );
				else
					buffer_add( sql_buf, " AND " );
			}

			char* subpred = searchWHERE( node, class_info, opjoin_type, ctx );
			if( ! subpred ) {
				buffer_free( sql_buf );
				return NULL;
			}

			buffer_fadd( sql_buf, "( %s )", subpred );
			free( subpred );
		}

	} else if( search_hash->type == JSON_HASH ) {
		osrfLogDebug( OSRF_LOG_MARK,
			"%s: In WHERE clause, condition type is JSON_HASH", modulename );
		jsonIterator* search_itr = jsonNewIterator( search_hash );
		if( !jsonIteratorHasNext( search_itr ) ) {
			osrfLogError(
				OSRF_LOG_MARK,
				"%s: Invalid predicate structure: empty JSON object",
				modulename
			);
			jsonIteratorFree( search_itr );
			buffer_free( sql_buf );
			return NULL;
		}

		while( (node = jsonIteratorNext( search_itr )) ) {

			if( first ) {
				first = 0;
			} else {
				if( opjoin_type == OR_OP_JOIN )
					buffer_add( sql_buf, " OR " );
				else
					buffer_add( sql_buf, " AND " );
			}

			if( '+' == search_itr->key[ 0 ] ) {

				// This plus sign prefixes a class name or other table alias;
				// make sure the table alias is in scope
				ClassInfo* alias_info = search_all_alias( search_itr->key + 1 );
				if( ! alias_info ) {
					osrfLogError(
							 OSRF_LOG_MARK,
							"%s: Invalid table alias \"%s\" in WHERE clause",
							modulename,
							search_itr->key + 1
					);
					jsonIteratorFree( search_itr );
					buffer_free( sql_buf );
					return NULL;
				}

				if( node->type == JSON_STRING ) {
					// It's the name of a column; make sure it belongs to the class
					const char* fieldname = jsonObjectGetString( node );
					if( ! osrfHashGet( alias_info->fields, fieldname ) ) {
						osrfLogError(
							OSRF_LOG_MARK,
							"%s: Invalid column name \"%s\" in WHERE clause "
							"for table alias \"%s\"",
							modulename,
							fieldname,
							alias_info->alias
						);
						jsonIteratorFree( search_itr );
						buffer_free( sql_buf );
						return NULL;
					}

					buffer_fadd( sql_buf, " \"%s\".%s ", alias_info->alias, fieldname );
				} else {
					// It's something more complicated
					char* subpred = searchWHERE( node, alias_info, AND_OP_JOIN, ctx );
					if( ! subpred ) {
						jsonIteratorFree( search_itr );
						buffer_free( sql_buf );
						return NULL;
					}

					buffer_fadd( sql_buf, "( %s )", subpred );
					free( subpred );
				}
			} else if( '-' == search_itr->key[ 0 ] ) {
				if( !strcasecmp( "-or", search_itr->key )) {
					char* subpred = searchWHERE( node, class_info, OR_OP_JOIN, ctx );
					if( ! subpred ) {
						jsonIteratorFree( search_itr );
						buffer_free( sql_buf );
						return NULL;
					}

					buffer_fadd( sql_buf, "( %s )", subpred );
					free( subpred );
				} else if( !strcasecmp( "-and", search_itr->key )) {
					char* subpred = searchWHERE( node, class_info, AND_OP_JOIN, ctx );
					if( ! subpred ) {
						jsonIteratorFree( search_itr );
						buffer_free( sql_buf );
						return NULL;
					}

					buffer_fadd( sql_buf, "( %s )", subpred );
					free( subpred );
				} else if( !strcasecmp("-not",search_itr->key) ) {
					char* subpred = searchWHERE( node, class_info, AND_OP_JOIN, ctx );
					if( ! subpred ) {
						jsonIteratorFree( search_itr );
						buffer_free( sql_buf );
						return NULL;
					}

					buffer_fadd( sql_buf, " NOT ( %s )", subpred );
					free( subpred );
				} else if( !strcasecmp( "-exists", search_itr->key )) {
					char* subpred = buildQuery( ctx, node, SUBSELECT );
					if( ! subpred ) {
						jsonIteratorFree( search_itr );
						buffer_free( sql_buf );
						return NULL;
					}

					buffer_fadd( sql_buf, "EXISTS ( %s )", subpred );
					free( subpred );
				} else if( !strcasecmp("-not-exists", search_itr->key )) {
					char* subpred = buildQuery( ctx, node, SUBSELECT );
					if( ! subpred ) {
						jsonIteratorFree( search_itr );
						buffer_free( sql_buf );
						return NULL;
					}

					buffer_fadd( sql_buf, "NOT EXISTS ( %s )", subpred );
					free( subpred );
				} else {     // Invalid "minus" operator
					osrfLogError(
							 OSRF_LOG_MARK,
							"%s: Invalid operator \"%s\" in WHERE clause",
							modulename,
							search_itr->key
					);
					jsonIteratorFree( search_itr );
					buffer_free( sql_buf );
					return NULL;
				}

			} else {

				const char* class = class_info->class_name;
				osrfHash* fields = class_info->fields;
				osrfHash* field = osrfHashGet( fields, search_itr->key );

				if( !field ) {
					const char* table = class_info->source_def;
					osrfLogError(
						OSRF_LOG_MARK,
						"%s: Attempt to reference non-existent column \"%s\" on %s (%s)",
						modulename,
						search_itr->key,
						table ? table : "?",
						class ? class : "?"
					);
					jsonIteratorFree( search_itr );
					buffer_free( sql_buf );
					return NULL;
				}

				char* subpred = searchPredicate( class_info, field, node, ctx );
				if( ! subpred ) {
					buffer_free( sql_buf );
					jsonIteratorFree( search_itr );
					return NULL;
				}

				buffer_add( sql_buf, subpred );
				free( subpred );
			}
		}
		jsonIteratorFree( search_itr );

	} else {
		// ERROR ... only hash and array allowed at this level
		char* predicate_string = jsonObjectToJSON( search_hash );
		osrfLogError(
			OSRF_LOG_MARK,
			"%s: Invalid predicate structure: %s",
			modulename,
			predicate_string
		);
		buffer_free( sql_buf );
		free( predicate_string );
		return NULL;
	}

	return buffer_release( sql_buf );
}

/* Build a JSON_ARRAY of field names for a given table alias
*/
static jsonObject* defaultSelectList( const char* table_alias ) {

	if( ! table_alias )
		table_alias = "";

	ClassInfo* class_info = search_all_alias( table_alias );
	if( ! class_info ) {
		osrfLogError(
			OSRF_LOG_MARK,
			"%s: Can't build default SELECT clause for \"%s\"; no such table alias",
			modulename,
			table_alias
		);
		return NULL;
	}

	jsonObject* array = jsonNewObjectType( JSON_ARRAY );
	osrfHash* field_def = NULL;
	osrfHashIterator* field_itr = osrfNewHashIterator( class_info->fields );
	while( ( field_def = osrfHashIteratorNext( field_itr ) ) ) {
		const char* field_name = osrfHashIteratorKey( field_itr );
		if( ! str_is_true( osrfHashGet( field_def, "virtual" ) ) ) {
			jsonObjectPush( array, jsonNewObject( field_name ) );
		}
	}
	osrfHashIteratorFree( field_itr );

	return array;
}

// Translate a jsonObject into a UNION, INTERSECT, or EXCEPT query.
// The jsonObject must be a JSON_HASH with an single entry for "union",
// "intersect", or "except".  The data associated with this key must be an
// array of hashes, each hash being a query.
// Also allowed but currently ignored: entries for "order_by" and "alias".
static char* doCombo( osrfMethodContext* ctx, jsonObject* combo, int flags ) {
	// Sanity check
	if( ! combo || combo->type != JSON_HASH )
		return NULL;      // should be impossible; validated by caller

	const jsonObject* query_array = NULL;   // array of subordinate queries
	const char* op = NULL;     // name of operator, e.g. UNION
	const char* alias = NULL;  // alias for the query (needed for ORDER BY)
	int op_count = 0;          // for detecting conflicting operators
	int excepting = 0;         // boolean
	int all = 0;               // boolean
	jsonObject* order_obj = NULL;

	// Identify the elements in the hash
	jsonIterator* query_itr = jsonNewIterator( combo );
	jsonObject* curr_obj = NULL;
	while( (curr_obj = jsonIteratorNext( query_itr ) ) ) {
		if( ! strcmp( "union", query_itr->key ) ) {
			++op_count;
			op = " UNION ";
			query_array = curr_obj;
		} else if( ! strcmp( "intersect", query_itr->key ) ) {
			++op_count;
			op = " INTERSECT ";
			query_array = curr_obj;
		} else if( ! strcmp( "except", query_itr->key ) ) {
			++op_count;
			op = " EXCEPT ";
			excepting = 1;
			query_array = curr_obj;
		} else if( ! strcmp( "order_by", query_itr->key ) ) {
			osrfLogWarning(
				OSRF_LOG_MARK,
				"%s: ORDER BY not supported for UNION, INTERSECT, or EXCEPT",
				modulename
			);
			order_obj = curr_obj;
		} else if( ! strcmp( "alias", query_itr->key ) ) {
			if( curr_obj->type != JSON_STRING ) {
				jsonIteratorFree( query_itr );
				return NULL;
			}
			alias = jsonObjectGetString( curr_obj );
		} else if( ! strcmp( "all", query_itr->key ) ) {
			if( obj_is_true( curr_obj ) )
				all = 1;
		} else {
			if( ctx )
				osrfAppSessionStatus(
					ctx->session,
					OSRF_STATUS_INTERNALSERVERERROR,
					"osrfMethodException",
					ctx->request,
					"Malformed query; unexpected entry in query object"
				);
			osrfLogError(
				OSRF_LOG_MARK,
				"%s: Unexpected entry for \"%s\" in%squery",
				modulename,
				query_itr->key,
				op
			);
			jsonIteratorFree( query_itr );
			return NULL;
		}
	}
	jsonIteratorFree( query_itr );

	// More sanity checks
	if( ! query_array ) {
		if( ctx )
			osrfAppSessionStatus(
				ctx->session,
				OSRF_STATUS_INTERNALSERVERERROR,
				"osrfMethodException",
				ctx->request,
				"Expected UNION, INTERSECT, or EXCEPT operator not found"
			);
		osrfLogError(
			OSRF_LOG_MARK,
			"%s: Expected UNION, INTERSECT, or EXCEPT operator not found",
			modulename
		);
		return NULL;        // should be impossible...
	} else if( op_count > 1 ) {
		if( ctx )
				osrfAppSessionStatus(
				ctx->session,
				OSRF_STATUS_INTERNALSERVERERROR,
				"osrfMethodException",
				ctx->request,
				"Found more than one of UNION, INTERSECT, and EXCEPT in same query"
			);
		osrfLogError(
			OSRF_LOG_MARK,
			"%s: Found more than one of UNION, INTERSECT, and EXCEPT in same query",
			modulename
		);
		return NULL;
	} if( query_array->type != JSON_ARRAY ) {
		if( ctx )
				osrfAppSessionStatus(
				ctx->session,
				OSRF_STATUS_INTERNALSERVERERROR,
				"osrfMethodException",
				ctx->request,
				"Malformed query: expected array of queries under UNION, INTERSECT or EXCEPT"
			);
		osrfLogError(
			OSRF_LOG_MARK,
			"%s: Expected JSON_ARRAY of queries for%soperator; found %s",
			modulename,
			op,
			json_type( query_array->type )
		);
		return NULL;
	} if( query_array->size < 2 ) {
		if( ctx )
			osrfAppSessionStatus(
				ctx->session,
				OSRF_STATUS_INTERNALSERVERERROR,
				"osrfMethodException",
				ctx->request,
				"UNION, INTERSECT or EXCEPT requires multiple queries as operands"
			);
		osrfLogError(
			OSRF_LOG_MARK,
			"%s:%srequires multiple queries as operands",
			modulename,
			op
		);
		return NULL;
	} else if( excepting && query_array->size > 2 ) {
		if( ctx )
			osrfAppSessionStatus(
				ctx->session,
				OSRF_STATUS_INTERNALSERVERERROR,
				"osrfMethodException",
				ctx->request,
				"EXCEPT operator has too many queries as operands"
			);
		osrfLogError(
			OSRF_LOG_MARK,
			"%s:EXCEPT operator has too many queries as operands",
			modulename
		);
		return NULL;
	} else if( order_obj && ! alias ) {
		if( ctx )
			osrfAppSessionStatus(
				ctx->session,
				OSRF_STATUS_INTERNALSERVERERROR,
				"osrfMethodException",
				ctx->request,
				"ORDER BY requires an alias for a UNION, INTERSECT, or EXCEPT"
			);
		osrfLogError(
			OSRF_LOG_MARK,
			"%s:ORDER BY requires an alias for a UNION, INTERSECT, or EXCEPT",
			modulename
		);
		return NULL;
	}

	// So far so good.  Now build the SQL.
	growing_buffer* sql = buffer_init( 256 );

	// If we nested inside another UNION, INTERSECT, or EXCEPT,
	// Add a layer of parentheses
	if( flags & SUBCOMBO )
		OSRF_BUFFER_ADD( sql, "( " );

	// Traverse the query array.  Each entry should be a hash.
	int first = 1;   // boolean
	int i = 0;
	jsonObject* query = NULL;
	while( (query = jsonObjectGetIndex( query_array, i++ )) ) {
		if( query->type != JSON_HASH ) {
			if( ctx )
				osrfAppSessionStatus(
					ctx->session,
					OSRF_STATUS_INTERNALSERVERERROR,
					"osrfMethodException",
					ctx->request,
					"Malformed query under UNION, INTERSECT or EXCEPT"
				);
			osrfLogError(
				OSRF_LOG_MARK,
				"%s: Malformed query under%s -- expected JSON_HASH, found %s",
				modulename,
				op,
				json_type( query->type )
			);
			buffer_free( sql );
			return NULL;
		}

		if( first )
			first = 0;
		else {
			OSRF_BUFFER_ADD( sql, op );
			if( all )
				OSRF_BUFFER_ADD( sql, "ALL " );
		}

		char* query_str = buildQuery( ctx, query, SUBSELECT | SUBCOMBO );
		if( ! query_str ) {
			osrfLogError(
				OSRF_LOG_MARK,
				"%s: Error building query under%s",
				modulename,
				op
			);
			buffer_free( sql );
			return NULL;
		}

		OSRF_BUFFER_ADD( sql, query_str );
	}

	if( flags & SUBCOMBO )
		OSRF_BUFFER_ADD_CHAR( sql, ')' );

	if( !(flags & SUBSELECT) )
		OSRF_BUFFER_ADD_CHAR( sql, ';' );

	return buffer_release( sql );
}

// Translate a jsonObject into a SELECT, UNION, INTERSECT, or EXCEPT query.
// The jsonObject must be a JSON_HASH with an entry for "from", "union", "intersect",
// or "except" to indicate the type of query.
char* buildQuery( osrfMethodContext* ctx, jsonObject* query, int flags ) {
	// Sanity checks
	if( ! query ) {
		if( ctx )
			osrfAppSessionStatus(
				ctx->session,
				OSRF_STATUS_INTERNALSERVERERROR,
				"osrfMethodException",
				ctx->request,
				"Malformed query; no query object"
			);
		osrfLogError( OSRF_LOG_MARK, "%s: Null pointer to query object", modulename );
		return NULL;
	} else if( query->type != JSON_HASH ) {
		if( ctx )
			osrfAppSessionStatus(
				ctx->session,
				OSRF_STATUS_INTERNALSERVERERROR,
				"osrfMethodException",
				ctx->request,
				"Malformed query object"
			);
		osrfLogError(
			OSRF_LOG_MARK,
			"%s: Query object is %s instead of JSON_HASH",
			modulename,
			json_type( query->type )
		);
		return NULL;
	}

	// Determine what kind of query it purports to be, and dispatch accordingly.
	if( jsonObjectGetKeyConst( query, "union" ) ||
		jsonObjectGetKeyConst( query, "intersect" ) ||
		jsonObjectGetKeyConst( query, "except" )) {
		return doCombo( ctx, query, flags );
	} else {
		// It is presumably a SELECT query

		// Push a node onto the stack for the current query.  Every level of
		// subquery gets its own QueryFrame on the Stack.
		push_query_frame();

		// Build an SQL SELECT statement
		char* sql = SELECT(
			ctx,
			jsonObjectGetKey( query, "select" ),
			jsonObjectGetKeyConst( query, "from" ),
			jsonObjectGetKeyConst( query, "where" ),
			jsonObjectGetKeyConst( query, "having" ),
			jsonObjectGetKeyConst( query, "order_by" ),
			jsonObjectGetKeyConst( query, "limit" ),
			jsonObjectGetKeyConst( query, "offset" ),
			flags
		);
		pop_query_frame();
		return sql;
	}
}

char* SELECT (
		/* method context */ osrfMethodContext* ctx,

		/* SELECT   */ jsonObject* selhash,
		/* FROM     */ const jsonObject* join_hash,
		/* WHERE    */ const jsonObject* search_hash,
		/* HAVING   */ const jsonObject* having_hash,
		/* ORDER BY */ const jsonObject* order_hash,
		/* LIMIT    */ const jsonObject* limit,
		/* OFFSET   */ const jsonObject* offset,
		/* flags    */ int flags
) {
	const char* locale = osrf_message_get_last_locale();

	// general tmp objects
	const jsonObject* tmp_const;
	jsonObject* selclass = NULL;
	jsonObject* snode = NULL;
	jsonObject* onode = NULL;

	char* string = NULL;
	int from_function = 0;
	int first = 1;
	int gfirst = 1;
	//int hfirst = 1;

	osrfLogDebug(OSRF_LOG_MARK, "cstore SELECT locale: %s", locale ? locale : "(none)" );

	// punt if there's no FROM clause
	if( !join_hash || ( join_hash->type == JSON_HASH && !join_hash->size )) {
		osrfLogError(
			OSRF_LOG_MARK,
			"%s: FROM clause is missing or empty",
			modulename
		);
		if( ctx )
			osrfAppSessionStatus(
				ctx->session,
				OSRF_STATUS_INTERNALSERVERERROR,
				"osrfMethodException",
				ctx->request,
				"FROM clause is missing or empty in JSON query"
			);
		return NULL;
	}

	// the core search class
	const char* core_class = NULL;

	// get the core class -- the only key of the top level FROM clause, or a string
	if( join_hash->type == JSON_HASH ) {
		jsonIterator* tmp_itr = jsonNewIterator( join_hash );
		snode = jsonIteratorNext( tmp_itr );

		// Populate the current QueryFrame with information
		// about the core class
		if( add_query_core( NULL, tmp_itr->key ) ) {
			if( ctx )
				osrfAppSessionStatus(
					ctx->session,
					OSRF_STATUS_INTERNALSERVERERROR,
					"osrfMethodException",
					ctx->request,
					"Unable to look up core class"
				);
			return NULL;
		}
		core_class = curr_query->core.class_name;
		join_hash = snode;

		jsonObject* extra = jsonIteratorNext( tmp_itr );

		jsonIteratorFree( tmp_itr );
		snode = NULL;

		// There shouldn't be more than one entry in join_hash
		if( extra ) {
			osrfLogError(
				OSRF_LOG_MARK,
				"%s: Malformed FROM clause: extra entry in JSON_HASH",
				modulename
			);
			if( ctx )
				osrfAppSessionStatus(
					ctx->session,
					OSRF_STATUS_INTERNALSERVERERROR,
					"osrfMethodException",
					ctx->request,
					"Malformed FROM clause in JSON query"
				);
			return NULL;    // Malformed join_hash; extra entry
		}
	} else if( join_hash->type == JSON_ARRAY ) {
		// We're selecting from a function, not from a table
		from_function = 1;
		core_class = jsonObjectGetString( jsonObjectGetIndex( join_hash, 0 ));
		selhash = NULL;

	} else if( join_hash->type == JSON_STRING ) {
		// Populate the current QueryFrame with information
		// about the core class
		core_class = jsonObjectGetString( join_hash );
		join_hash = NULL;
		if( add_query_core( NULL, core_class ) ) {
			if( ctx )
				osrfAppSessionStatus(
					ctx->session,
					OSRF_STATUS_INTERNALSERVERERROR,
					"osrfMethodException",
					ctx->request,
					"Unable to look up core class"
				);
			return NULL;
		}
	}
	else {
		osrfLogError(
			OSRF_LOG_MARK,
			"%s: FROM clause is unexpected JSON type: %s",
			modulename,
			json_type( join_hash->type )
		);
		if( ctx )
			osrfAppSessionStatus(
				ctx->session,
				OSRF_STATUS_INTERNALSERVERERROR,
				"osrfMethodException",
				ctx->request,
				"Ill-formed FROM clause in JSON query"
			);
		return NULL;
	}

	// Build the join clause, if any, while filling out the list
	// of joined classes in the current QueryFrame.
	char* join_clause = NULL;
	if( join_hash && ! from_function ) {

		join_clause = searchJOIN( join_hash, &curr_query->core );
		if( ! join_clause ) {
			if( ctx )
				osrfAppSessionStatus(
					ctx->session,
					OSRF_STATUS_INTERNALSERVERERROR,
					"osrfMethodException",
					ctx->request,
					"Unable to construct JOIN clause(s)"
				);
			return NULL;
		}
	}

	// For in case we don't get a select list
	jsonObject* defaultselhash = NULL;

	// if there is no select list, build a default select list ...
	if( !selhash && !from_function ) {
		jsonObject* default_list = defaultSelectList( core_class );
		if( ! default_list ) {
			if( ctx ) {
				osrfAppSessionStatus(
					ctx->session,
					OSRF_STATUS_INTERNALSERVERERROR,
					"osrfMethodException",
					ctx->request,
					"Unable to build default SELECT clause in JSON query"
				);
				free( join_clause );
				return NULL;
			}
		}

		selhash = defaultselhash = jsonNewObjectType( JSON_HASH );
		jsonObjectSetKey( selhash, core_class, default_list );
	}

	// The SELECT clause can be encoded only by a hash
	if( !from_function && selhash->type != JSON_HASH ) {
		osrfLogError(
			OSRF_LOG_MARK,
			"%s: Expected JSON_HASH for SELECT clause; found %s",
			modulename,
			json_type( selhash->type )
		);

		if( ctx )
			osrfAppSessionStatus(
				ctx->session,
				OSRF_STATUS_INTERNALSERVERERROR,
				"osrfMethodException",
				ctx->request,
				"Malformed SELECT clause in JSON query"
			);
		free( join_clause );
		return NULL;
	}

	// If you see a null or wild card specifier for the core class, or an
	// empty array, replace it with a default SELECT list
	tmp_const = jsonObjectGetKeyConst( selhash, core_class );
	if( tmp_const ) {
		int default_needed = 0;   // boolean
		if( JSON_STRING == tmp_const->type
			&& !strcmp( "*", jsonObjectGetString( tmp_const ) ))
				default_needed = 1;
		else if( JSON_NULL == tmp_const->type )
			default_needed = 1;

		if( default_needed ) {
			// Build a default SELECT list
			jsonObject* default_list = defaultSelectList( core_class );
			if( ! default_list ) {
				if( ctx ) {
					osrfAppSessionStatus(
						ctx->session,
						OSRF_STATUS_INTERNALSERVERERROR,
						"osrfMethodException",
						ctx->request,
						"Can't build default SELECT clause in JSON query"
					);
					free( join_clause );
					return NULL;
				}
			}

			jsonObjectSetKey( selhash, core_class, default_list );
		}
	}

	// temp buffers for the SELECT list and GROUP BY clause
	growing_buffer* select_buf = buffer_init( 128 );
	growing_buffer* group_buf  = buffer_init( 128 );

	int aggregate_found = 0;     // boolean

	// Build a select list
	if( from_function )   // From a function we select everything
		OSRF_BUFFER_ADD_CHAR( select_buf, '*' );
	else {

		// Build the SELECT list as SQL
	    int sel_pos = 1;
	    first = 1;
	    gfirst = 1;
	    jsonIterator* selclass_itr = jsonNewIterator( selhash );
	    while ( (selclass = jsonIteratorNext( selclass_itr )) ) {    // For each class

			const char* cname = selclass_itr->key;

			// Make sure the target relation is in the FROM clause.

			// At this point join_hash is a step down from the join_hash we
			// received as a parameter.  If the original was a JSON_STRING,
			// then json_hash is now NULL.  If the original was a JSON_HASH,
			// then json_hash is now the first (and only) entry in it,
			// denoting the core class.  We've already excluded the
			// possibility that the original was a JSON_ARRAY, because in
			// that case from_function would be non-NULL, and we wouldn't
			// be here.

			// If the current table alias isn't in scope, bail out
			ClassInfo* class_info = search_alias( cname );
			if( ! class_info ) {
				osrfLogError(
					OSRF_LOG_MARK,
					"%s: SELECT clause references class not in FROM clause: \"%s\"",
					modulename,
					cname
				);
				if( ctx )
					osrfAppSessionStatus(
						ctx->session,
						OSRF_STATUS_INTERNALSERVERERROR,
						"osrfMethodException",
						ctx->request,
						"Selected class not in FROM clause in JSON query"
					);
				jsonIteratorFree( selclass_itr );
				buffer_free( select_buf );
				buffer_free( group_buf );
				if( defaultselhash )
					jsonObjectFree( defaultselhash );
				free( join_clause );
				return NULL;
			}

			if( selclass->type != JSON_ARRAY ) {
				osrfLogError(
					OSRF_LOG_MARK,
					"%s: Malformed SELECT list for class \"%s\"; not an array",
					modulename,
					cname
				);
				if( ctx )
					osrfAppSessionStatus(
						ctx->session,
						OSRF_STATUS_INTERNALSERVERERROR,
						"osrfMethodException",
						ctx->request,
						"Selected class not in FROM clause in JSON query"
					);

				jsonIteratorFree( selclass_itr );
				buffer_free( select_buf );
				buffer_free( group_buf );
				if( defaultselhash )
					jsonObjectFree( defaultselhash );
				free( join_clause );
				return NULL;
			}

			// Look up some attributes of the current class
			osrfHash* idlClass        = class_info->class_def;
			osrfHash* class_field_set = class_info->fields;
			const char* class_pkey    = osrfHashGet( idlClass, "primarykey" );
			const char* class_tname   = osrfHashGet( idlClass, "tablename" );

			if( 0 == selclass->size ) {
				osrfLogWarning(
					OSRF_LOG_MARK,
					"%s: No columns selected from \"%s\"",
					modulename,
					cname
				);
			}

			// stitch together the column list for the current table alias...
			unsigned long field_idx = 0;
			jsonObject* selfield = NULL;
			while(( selfield = jsonObjectGetIndex( selclass, field_idx++ ) )) {

				// If we need a separator comma, add one
				if( first ) {
					first = 0;
				} else {
					OSRF_BUFFER_ADD_CHAR( select_buf, ',' );
				}

				// if the field specification is a string, add it to the list
				if( selfield->type == JSON_STRING ) {

					// Look up the field in the IDL
					const char* col_name = jsonObjectGetString( selfield );
					osrfHash* field_def = osrfHashGet( class_field_set, col_name );
					if( !field_def ) {
						// No such field in current class
						osrfLogError(
							OSRF_LOG_MARK,
							"%s: Selected column \"%s\" not defined in IDL for class \"%s\"",
							modulename,
							col_name,
							cname
						);
						if( ctx )
							osrfAppSessionStatus(
								ctx->session,
								OSRF_STATUS_INTERNALSERVERERROR,
								"osrfMethodException",
								ctx->request,
								"Selected column not defined in JSON query"
							);
						jsonIteratorFree( selclass_itr );
						buffer_free( select_buf );
						buffer_free( group_buf );
						if( defaultselhash )
							jsonObjectFree( defaultselhash );
						free( join_clause );
						return NULL;
					} else if( str_is_true( osrfHashGet( field_def, "virtual" ) ) ) {
						// Virtual field not allowed
						osrfLogError(
							OSRF_LOG_MARK,
							"%s: Selected column \"%s\" for class \"%s\" is virtual",
							modulename,
							col_name,
							cname
						);
						if( ctx )
							osrfAppSessionStatus(
								ctx->session,
								OSRF_STATUS_INTERNALSERVERERROR,
								"osrfMethodException",
								ctx->request,
								"Selected column may not be virtual in JSON query"
							);
						jsonIteratorFree( selclass_itr );
						buffer_free( select_buf );
						buffer_free( group_buf );
						if( defaultselhash )
							jsonObjectFree( defaultselhash );
						free( join_clause );
						return NULL;
					}

					if( locale ) {
						const char* i18n;
						if( flags & DISABLE_I18N )
							i18n = NULL;
						else
							i18n = osrfHashGet( field_def, "i18n" );

						if( str_is_true( i18n ) ) {
							buffer_fadd( select_buf, " oils_i18n_xlate('%s', '%s', '%s', "
								"'%s', \"%s\".%s::TEXT, '%s') AS \"%s\"",
								class_tname, cname, col_name, class_pkey,
								cname, class_pkey, locale, col_name );
						} else {
							buffer_fadd( select_buf, " \"%s\".%s AS \"%s\"",
								cname, col_name, col_name );
						}
					} else {
						buffer_fadd( select_buf, " \"%s\".%s AS \"%s\"",
								cname, col_name, col_name );
					}

				// ... but it could be an object, in which case we check for a Field Transform
				} else if( selfield->type == JSON_HASH ) {

					const char* col_name = jsonObjectGetString(
							jsonObjectGetKeyConst( selfield, "column" ) );

					// Get the field definition from the IDL
					osrfHash* field_def = osrfHashGet( class_field_set, col_name );
					if( !field_def ) {
						// No such field in current class
						osrfLogError(
							OSRF_LOG_MARK,
							"%s: Selected column \"%s\" is not defined in IDL for class \"%s\"",
							modulename,
							col_name,
							cname
						);
						if( ctx )
							osrfAppSessionStatus(
								ctx->session,
								OSRF_STATUS_INTERNALSERVERERROR,
								"osrfMethodException",
								ctx->request,
								"Selected column is not defined in JSON query"
							);
						jsonIteratorFree( selclass_itr );
						buffer_free( select_buf );
						buffer_free( group_buf );
						if( defaultselhash )
							jsonObjectFree( defaultselhash );
						free( join_clause );
						return NULL;
					} else if( str_is_true( osrfHashGet( field_def, "virtual" ))) {
						// No such field in current class
						osrfLogError(
							OSRF_LOG_MARK,
							"%s: Selected column \"%s\" is virtual for class \"%s\"",
							modulename,
							col_name,
							cname
						);
						if( ctx )
							osrfAppSessionStatus(
								ctx->session,
								OSRF_STATUS_INTERNALSERVERERROR,
								"osrfMethodException",
								ctx->request,
								"Selected column is virtual in JSON query"
							);
						jsonIteratorFree( selclass_itr );
						buffer_free( select_buf );
						buffer_free( group_buf );
						if( defaultselhash )
							jsonObjectFree( defaultselhash );
						free( join_clause );
						return NULL;
					}

					// Decide what to use as a column alias
					const char* _alias;
					if((tmp_const = jsonObjectGetKeyConst( selfield, "alias" ))) {
						_alias = jsonObjectGetString( tmp_const );
					} else if((tmp_const = jsonObjectGetKeyConst( selfield, "result_field" ))) { // Use result_field name as the alias
						_alias = jsonObjectGetString( tmp_const );
					} else {         // Use field name as the alias
						_alias = col_name;
					}

					if( jsonObjectGetKeyConst( selfield, "transform" )) {
						char* transform_str = searchFieldTransform(
							class_info->alias, field_def, selfield );
						if( transform_str ) {
							buffer_fadd( select_buf, " %s AS \"%s\"", transform_str, _alias );
							free( transform_str );
						} else {
							if( ctx )
								osrfAppSessionStatus(
									ctx->session,
									OSRF_STATUS_INTERNALSERVERERROR,
									"osrfMethodException",
									ctx->request,
									"Unable to generate transform function in JSON query"
								);
							jsonIteratorFree( selclass_itr );
							buffer_free( select_buf );
							buffer_free( group_buf );
							if( defaultselhash )
								jsonObjectFree( defaultselhash );
							free( join_clause );
							return NULL;
						}
					} else {

						if( locale ) {
							const char* i18n;
							if( flags & DISABLE_I18N )
								i18n = NULL;
							else
								i18n = osrfHashGet( field_def, "i18n" );

							if( str_is_true( i18n ) ) {
								buffer_fadd( select_buf,
									" oils_i18n_xlate('%s', '%s', '%s', '%s', "
									"\"%s\".%s::TEXT, '%s') AS \"%s\"",
									class_tname, cname, col_name, class_pkey, cname,
									class_pkey, locale, _alias );
							} else {
								buffer_fadd( select_buf, " \"%s\".%s AS \"%s\"",
									cname, col_name, _alias );
							}
						} else {
							buffer_fadd( select_buf, " \"%s\".%s AS \"%s\"",
								cname, col_name, _alias );
						}
					}
				}
				else {
					osrfLogError(
						OSRF_LOG_MARK,
						"%s: Selected item is unexpected JSON type: %s",
						modulename,
						json_type( selfield->type )
					);
					if( ctx )
						osrfAppSessionStatus(
							ctx->session,
							OSRF_STATUS_INTERNALSERVERERROR,
							"osrfMethodException",
							ctx->request,
							"Ill-formed SELECT item in JSON query"
						);
					jsonIteratorFree( selclass_itr );
					buffer_free( select_buf );
					buffer_free( group_buf );
					if( defaultselhash )
						jsonObjectFree( defaultselhash );
					free( join_clause );
					return NULL;
				}

				const jsonObject* agg_obj = jsonObjectGetKeyConst( selfield, "aggregate" );
				if( obj_is_true( agg_obj ) )
					aggregate_found = 1;
				else {
					// Append a comma (except for the first one)
					// and add the column to a GROUP BY clause
					if( gfirst )
						gfirst = 0;
					else
						OSRF_BUFFER_ADD_CHAR( group_buf, ',' );

					buffer_fadd( group_buf, " %d", sel_pos );
				}

#if 0
			    if (is_agg->size || (flags & SELECT_DISTINCT)) {

					const jsonObject* aggregate_obj = jsonObjectGetKeyConst( elfield, "aggregate");
				    if ( ! obj_is_true( aggregate_obj ) ) {
					    if (gfirst) {
						    gfirst = 0;
					    } else {
							OSRF_BUFFER_ADD_CHAR( group_buf, ',' );
					    }

					    buffer_fadd(group_buf, " %d", sel_pos);

					/*
				    } else if (is_agg = jsonObjectGetKeyConst( selfield, "having" )) {
					    if (gfirst) {
						    gfirst = 0;
					    } else {
							OSRF_BUFFER_ADD_CHAR( group_buf, ',' );
					    }

					    _column = searchFieldTransform(class_info->alias, field, selfield);
						OSRF_BUFFER_ADD_CHAR(group_buf, ' ');
						OSRF_BUFFER_ADD(group_buf, _column);
					    _column = searchFieldTransform(class_info->alias, field, selfield);
					*/
				    }
			    }
#endif

				sel_pos++;
			} // end while -- iterating across SELECT columns

		} // end while -- iterating across classes

		jsonIteratorFree( selclass_itr );
	}

	char* col_list = buffer_release( select_buf );

	// Make sure the SELECT list isn't empty.  This can happen, for example,
	// if we try to build a default SELECT clause from a non-core table.

	if( ! *col_list ) {
		osrfLogError( OSRF_LOG_MARK, "%s: SELECT clause is empty", modulename );
		if( ctx )
			osrfAppSessionStatus(
				ctx->session,
				OSRF_STATUS_INTERNALSERVERERROR,
				"osrfMethodException",
				ctx->request,
				"SELECT list is empty"
		);
		free( col_list );
		buffer_free( group_buf );
		if( defaultselhash )
			jsonObjectFree( defaultselhash );
		free( join_clause );
		return NULL;
	}

	char* table = NULL;
	if( from_function )
		table = searchValueTransform( join_hash );
	else
		table = strdup( curr_query->core.source_def );

	if( !table ) {
		if( ctx )
			osrfAppSessionStatus(
				ctx->session,
				OSRF_STATUS_INTERNALSERVERERROR,
				"osrfMethodException",
				ctx->request,
				"Unable to identify table for core class"
			);
		free( col_list );
		buffer_free( group_buf );
		if( defaultselhash )
			jsonObjectFree( defaultselhash );
		free( join_clause );
		return NULL;
	}

	// Put it all together
	growing_buffer* sql_buf = buffer_init( 128 );
	buffer_fadd(sql_buf, "SELECT %s FROM %s AS \"%s\" ", col_list, table, core_class );
	free( col_list );
	free( table );

	// Append the join clause, if any
	if( join_clause ) {
		buffer_add(sql_buf, join_clause );
		free( join_clause );
	}

	char* order_by_list = NULL;
	char* having_buf = NULL;

	if( !from_function ) {

		// Build a WHERE clause, if there is one
		if( search_hash ) {
			buffer_add( sql_buf, " WHERE " );

			// and it's on the WHERE clause
			char* pred = searchWHERE( search_hash, &curr_query->core, AND_OP_JOIN, ctx );
			if( ! pred ) {
				if( ctx ) {
					osrfAppSessionStatus(
						ctx->session,
						OSRF_STATUS_INTERNALSERVERERROR,
						"osrfMethodException",
						ctx->request,
						"Severe query error in WHERE predicate -- see error log for more details"
					);
				}
				buffer_free( group_buf );
				buffer_free( sql_buf );
				if( defaultselhash )
					jsonObjectFree( defaultselhash );
				return NULL;
			}

			buffer_add( sql_buf, pred );
			free( pred );
		}

		// Build a HAVING clause, if there is one
		if( having_hash ) {

			// and it's on the the WHERE clause
			having_buf = searchWHERE( having_hash, &curr_query->core, AND_OP_JOIN, ctx );

			if( ! having_buf ) {
				if( ctx ) {
						osrfAppSessionStatus(
						ctx->session,
						OSRF_STATUS_INTERNALSERVERERROR,
						"osrfMethodException",
						ctx->request,
						"Severe query error in HAVING predicate -- see error log for more details"
					);
				}
				buffer_free( group_buf );
				buffer_free( sql_buf );
				if( defaultselhash )
					jsonObjectFree( defaultselhash );
				return NULL;
			}
		}

		// Build an ORDER BY clause, if there is one
		if( NULL == order_hash )
			;  // No ORDER BY? do nothing
		else if( JSON_ARRAY == order_hash->type ) {
			order_by_list = buildOrderByFromArray( ctx, order_hash );
			if( !order_by_list ) {
				free( having_buf );
				buffer_free( group_buf );
				buffer_free( sql_buf );
				if( defaultselhash )
					jsonObjectFree( defaultselhash );
				return NULL;
			}
		} else if( JSON_HASH == order_hash->type ) {
			// This hash is keyed on class alias.  Each class has either
			// an array of field names or a hash keyed on field name.
			growing_buffer* order_buf = NULL;  // to collect ORDER BY list
			jsonIterator* class_itr = jsonNewIterator( order_hash );
			while( (snode = jsonIteratorNext( class_itr )) ) {

				ClassInfo* order_class_info = search_alias( class_itr->key );
				if( ! order_class_info ) {
					osrfLogError( OSRF_LOG_MARK,
						"%s: Invalid class \"%s\" referenced in ORDER BY clause",
						modulename, class_itr->key );
					if( ctx )
						osrfAppSessionStatus(
							ctx->session,
							OSRF_STATUS_INTERNALSERVERERROR,
							"osrfMethodException",
							ctx->request,
							"Invalid class referenced in ORDER BY clause -- "
								"see error log for more details"
						);
					jsonIteratorFree( class_itr );
					buffer_free( order_buf );
					free( having_buf );
					buffer_free( group_buf );
					buffer_free( sql_buf );
					if( defaultselhash )
						jsonObjectFree( defaultselhash );
					return NULL;
				}

				osrfHash* field_list_def = order_class_info->fields;

				if( snode->type == JSON_HASH ) {

					// Hash is keyed on field names from the current class.  For each field
					// there is another layer of hash to define the sorting details, if any,
					// or a string to indicate direction of sorting.
					jsonIterator* order_itr = jsonNewIterator( snode );
					while( (onode = jsonIteratorNext( order_itr )) ) {

						osrfHash* field_def = osrfHashGet( field_list_def, order_itr->key );
						if( !field_def ) {
							osrfLogError( OSRF_LOG_MARK,
								"%s: Invalid field \"%s\" in ORDER BY clause",
								modulename, order_itr->key );
							if( ctx )
								osrfAppSessionStatus(
									ctx->session,
									OSRF_STATUS_INTERNALSERVERERROR,
									"osrfMethodException",
									ctx->request,
									"Invalid field in ORDER BY clause -- "
									"see error log for more details"
								);
							jsonIteratorFree( order_itr );
							jsonIteratorFree( class_itr );
							buffer_free( order_buf );
							free( having_buf );
							buffer_free( group_buf );
							buffer_free( sql_buf );
							if( defaultselhash )
								jsonObjectFree( defaultselhash );
							return NULL;
						} else if( str_is_true( osrfHashGet( field_def, "virtual" ) ) ) {
							osrfLogError( OSRF_LOG_MARK,
								"%s: Virtual field \"%s\" in ORDER BY clause",
								modulename, order_itr->key );
							if( ctx )
								osrfAppSessionStatus(
									ctx->session,
									OSRF_STATUS_INTERNALSERVERERROR,
									"osrfMethodException",
									ctx->request,
									"Virtual field in ORDER BY clause -- "
									"see error log for more details"
							);
							jsonIteratorFree( order_itr );
							jsonIteratorFree( class_itr );
							buffer_free( order_buf );
							free( having_buf );
							buffer_free( group_buf );
							buffer_free( sql_buf );
							if( defaultselhash )
								jsonObjectFree( defaultselhash );
							return NULL;
						}

						const char* direction = NULL;
						if( onode->type == JSON_HASH ) {
							if( jsonObjectGetKeyConst( onode, "transform" ) ) {
								string = searchFieldTransform(
									class_itr->key,
									osrfHashGet( field_list_def, order_itr->key ),
									onode
								);
								if( ! string ) {
									if( ctx ) osrfAppSessionStatus(
										ctx->session,
										OSRF_STATUS_INTERNALSERVERERROR,
										"osrfMethodException",
										ctx->request,
										"Severe query error in ORDER BY clause -- "
										"see error log for more details"
									);
									jsonIteratorFree( order_itr );
									jsonIteratorFree( class_itr );
									free( having_buf );
									buffer_free( group_buf );
									buffer_free( order_buf);
									buffer_free( sql_buf );
									if( defaultselhash )
										jsonObjectFree( defaultselhash );
									return NULL;
								}
							} else {
								growing_buffer* field_buf = buffer_init( 16 );
								buffer_fadd( field_buf, "\"%s\".%s",
									class_itr->key, order_itr->key );
								string = buffer_release( field_buf );
							}

							if( (tmp_const = jsonObjectGetKeyConst( onode, "direction" )) ) {
								const char* dir = jsonObjectGetString( tmp_const );
								if(!strncasecmp( dir, "d", 1 )) {
									direction = " DESC";
								} else {
									direction = " ASC";
								}
							}

						} else if( JSON_NULL == onode->type || JSON_ARRAY == onode->type ) {
							osrfLogError( OSRF_LOG_MARK,
								"%s: Expected JSON_STRING in ORDER BY clause; found %s",
								modulename, json_type( onode->type ) );
							if( ctx )
								osrfAppSessionStatus(
									ctx->session,
									OSRF_STATUS_INTERNALSERVERERROR,
									"osrfMethodException",
									ctx->request,
									"Malformed ORDER BY clause -- see error log for more details"
								);
							jsonIteratorFree( order_itr );
							jsonIteratorFree( class_itr );
							free( having_buf );
							buffer_free( group_buf );
							buffer_free( order_buf );
							buffer_free( sql_buf );
							if( defaultselhash )
								jsonObjectFree( defaultselhash );
							return NULL;

						} else {
							string = strdup( order_itr->key );
							const char* dir = jsonObjectGetString( onode );
							if( !strncasecmp( dir, "d", 1 )) {
								direction = " DESC";
							} else {
								direction = " ASC";
							}
						}

						if( order_buf )
							OSRF_BUFFER_ADD( order_buf, ", " );
						else
							order_buf = buffer_init( 128 );

						OSRF_BUFFER_ADD( order_buf, string );
						free( string );

						if( direction ) {
							 OSRF_BUFFER_ADD( order_buf, direction );
						}

					} // end while
					jsonIteratorFree( order_itr );

				} else if( snode->type == JSON_ARRAY ) {

					// Array is a list of fields from the current class
					unsigned long order_idx = 0;
					while(( onode = jsonObjectGetIndex( snode, order_idx++ ) )) {

						const char* _f = jsonObjectGetString( onode );

						osrfHash* field_def = osrfHashGet( field_list_def, _f );
						if( !field_def ) {
							osrfLogError( OSRF_LOG_MARK,
									"%s: Invalid field \"%s\" in ORDER BY clause",
									modulename, _f );
							if( ctx )
								osrfAppSessionStatus(
									ctx->session,
									OSRF_STATUS_INTERNALSERVERERROR,
									"osrfMethodException",
									ctx->request,
									"Invalid field in ORDER BY clause -- "
									"see error log for more details"
								);
							jsonIteratorFree( class_itr );
							buffer_free( order_buf );
							free( having_buf );
							buffer_free( group_buf );
							buffer_free( sql_buf );
							if( defaultselhash )
								jsonObjectFree( defaultselhash );
							return NULL;
						} else if( str_is_true( osrfHashGet( field_def, "virtual" ) ) ) {
							osrfLogError( OSRF_LOG_MARK,
								"%s: Virtual field \"%s\" in ORDER BY clause",
								modulename, _f );
							if( ctx )
								osrfAppSessionStatus(
									ctx->session,
									OSRF_STATUS_INTERNALSERVERERROR,
									"osrfMethodException",
									ctx->request,
									"Virtual field in ORDER BY clause -- "
									"see error log for more details"
								);
							jsonIteratorFree( class_itr );
							buffer_free( order_buf );
							free( having_buf );
							buffer_free( group_buf );
							buffer_free( sql_buf );
							if( defaultselhash )
								jsonObjectFree( defaultselhash );
							return NULL;
						}

						if( order_buf )
							OSRF_BUFFER_ADD( order_buf, ", " );
						else
							order_buf = buffer_init( 128 );

						buffer_fadd( order_buf, "\"%s\".%s", class_itr->key, _f );

					} // end while

				// IT'S THE OOOOOOOOOOOLD STYLE!
				} else {
					osrfLogError( OSRF_LOG_MARK,
						"%s: Possible SQL injection attempt; direct order by is not allowed",
						modulename );
					if(ctx) {
						osrfAppSessionStatus(
							ctx->session,
							OSRF_STATUS_INTERNALSERVERERROR,
							"osrfMethodException",
							ctx->request,
							"Severe query error -- see error log for more details"
						);
					}

					free( having_buf );
					buffer_free( group_buf );
					buffer_free( order_buf );
					buffer_free( sql_buf );
					if( defaultselhash )
						jsonObjectFree( defaultselhash );
					jsonIteratorFree( class_itr );
					return NULL;
				}
			} // end while
			jsonIteratorFree( class_itr );
			if( order_buf )
				order_by_list = buffer_release( order_buf );
		} else {
			osrfLogError( OSRF_LOG_MARK,
				"%s: Malformed ORDER BY clause; expected JSON_HASH or JSON_ARRAY, found %s",
				modulename, json_type( order_hash->type ) );
			if( ctx )
				osrfAppSessionStatus(
					ctx->session,
					OSRF_STATUS_INTERNALSERVERERROR,
					"osrfMethodException",
					ctx->request,
					"Malformed ORDER BY clause -- see error log for more details"
				);
			free( having_buf );
			buffer_free( group_buf );
			buffer_free( sql_buf );
			if( defaultselhash )
				jsonObjectFree( defaultselhash );
			return NULL;
		}
	}

	string = buffer_release( group_buf );

	if( *string && ( aggregate_found || (flags & SELECT_DISTINCT) ) ) {
		OSRF_BUFFER_ADD( sql_buf, " GROUP BY " );
		OSRF_BUFFER_ADD( sql_buf, string );
	}

	free( string );

	if( having_buf && *having_buf ) {
		OSRF_BUFFER_ADD( sql_buf, " HAVING " );
		OSRF_BUFFER_ADD( sql_buf, having_buf );
		free( having_buf );
	}

	if( order_by_list ) {

		if( *order_by_list ) {
			OSRF_BUFFER_ADD( sql_buf, " ORDER BY " );
			OSRF_BUFFER_ADD( sql_buf, order_by_list );
		}

		free( order_by_list );
	}

	if( limit ){
		const char* str = jsonObjectGetString( limit );
		if (str) { // limit could be JSON_NULL, etc.
			buffer_fadd( sql_buf, " LIMIT %d", atoi( str ));
		}
	}

	if( offset ) {
		const char* str = jsonObjectGetString( offset );
		if (str) {
			buffer_fadd( sql_buf, " OFFSET %d", atoi( str ));
		}
	}

	if( !(flags & SUBSELECT) )
		OSRF_BUFFER_ADD_CHAR( sql_buf, ';' );

	if( defaultselhash )
		 jsonObjectFree( defaultselhash );

	return buffer_release( sql_buf );

} // end of SELECT()

/**
	@brief Build a list of ORDER BY expressions.
	@param ctx Pointer to the method context.
	@param order_array Pointer to a JSON_ARRAY of field specifications.
	@return Pointer to a string containing a comma-separated list of ORDER BY expressions.
	Each expression may be either a column reference or a function call whose first parameter
	is a column reference.

	Each entry in @a order_array must be a JSON_HASH with values for "class" and "field".
	It may optionally include entries for "direction" and/or "transform".

	The calling code is responsible for freeing the returned string.
*/
static char* buildOrderByFromArray( osrfMethodContext* ctx, const jsonObject* order_array ) {
	if( ! order_array ) {
		osrfLogError( OSRF_LOG_MARK, "%s: Logic error: NULL pointer for ORDER BY clause",
			modulename );
		if( ctx )
			osrfAppSessionStatus(
				ctx->session,
				OSRF_STATUS_INTERNALSERVERERROR,
				"osrfMethodException",
				ctx->request,
				"Logic error: ORDER BY clause expected, not found; "
					"see error log for more details"
			);
		return NULL;
	} else if( order_array->type != JSON_ARRAY ) {
		osrfLogError( OSRF_LOG_MARK,
			"%s: Logic error: Expected JSON_ARRAY for ORDER BY clause, not found", modulename );
		if( ctx )
			osrfAppSessionStatus(
			ctx->session,
			OSRF_STATUS_INTERNALSERVERERROR,
			"osrfMethodException",
			ctx->request,
			"Logic error: Unexpected format for ORDER BY clause; see error log for more details" );
		return NULL;
	}

	growing_buffer* order_buf = buffer_init( 128 );
	int first = 1;        // boolean
	int order_idx = 0;
	jsonObject* order_spec;
	while( (order_spec = jsonObjectGetIndex( order_array, order_idx++ ))) {

		if( JSON_HASH != order_spec->type ) {
			osrfLogError( OSRF_LOG_MARK,
				"%s: Malformed field specification in ORDER BY clause; "
				"expected JSON_HASH, found %s",
				modulename, json_type( order_spec->type ) );
			if( ctx )
				osrfAppSessionStatus(
					 ctx->session,
					OSRF_STATUS_INTERNALSERVERERROR,
					"osrfMethodException",
					ctx->request,
					"Malformed ORDER BY clause -- see error log for more details"
				);
			buffer_free( order_buf );
			return NULL;
		}

		const char* class_alias =
			jsonObjectGetString( jsonObjectGetKeyConst( order_spec, "class" ));
		const char* field =
			jsonObjectGetString( jsonObjectGetKeyConst( order_spec, "field" ));

		jsonObject* compare_to = jsonObjectGetKeyConst( order_spec, "compare" );

		if( !field || !class_alias ) {
			osrfLogError( OSRF_LOG_MARK,
				"%s: Missing class or field name in field specification of ORDER BY clause",
				modulename );
			if( ctx )
				osrfAppSessionStatus(
					ctx->session,
					OSRF_STATUS_INTERNALSERVERERROR,
					"osrfMethodException",
					ctx->request,
					"Malformed ORDER BY clause -- see error log for more details"
				);
			buffer_free( order_buf );
			return NULL;
		}

		const ClassInfo* order_class_info = search_alias( class_alias );
		if( ! order_class_info ) {
			osrfLogInternal( OSRF_LOG_MARK, "%s: ORDER BY clause references class \"%s\" "
				"not in FROM clause, skipping it", modulename, class_alias );
			continue;
		}

		// Add a separating comma, except at the beginning
		if( first )
			first = 0;
		else
			OSRF_BUFFER_ADD( order_buf, ", " );

		osrfHash* field_def = osrfHashGet( order_class_info->fields, field );
		if( !field_def ) {
			osrfLogError( OSRF_LOG_MARK,
				"%s: Invalid field \"%s\".%s referenced in ORDER BY clause",
				modulename, class_alias, field );
			if( ctx )
				osrfAppSessionStatus(
					ctx->session,
					OSRF_STATUS_INTERNALSERVERERROR,
					"osrfMethodException",
					ctx->request,
					"Invalid field referenced in ORDER BY clause -- "
					"see error log for more details"
				);
			free( order_buf );
			return NULL;
		} else if( str_is_true( osrfHashGet( field_def, "virtual" ) ) ) {
			osrfLogError( OSRF_LOG_MARK, "%s: Virtual field \"%s\" in ORDER BY clause",
				modulename, field );
			if( ctx )
				osrfAppSessionStatus(
					ctx->session,
					OSRF_STATUS_INTERNALSERVERERROR,
					"osrfMethodException",
					ctx->request,
					"Virtual field in ORDER BY clause -- see error log for more details"
				);
			buffer_free( order_buf );
			return NULL;
		}

		if( jsonObjectGetKeyConst( order_spec, "transform" )) {
			char* transform_str = searchFieldTransform( class_alias, field_def, order_spec );
			if( ! transform_str ) {
				if( ctx )
					osrfAppSessionStatus(
						ctx->session,
						OSRF_STATUS_INTERNALSERVERERROR,
						"osrfMethodException",
						ctx->request,
						"Severe query error in ORDER BY clause -- "
						"see error log for more details"
					);
				buffer_free( order_buf );
				return NULL;
			}

			OSRF_BUFFER_ADD( order_buf, transform_str );
			free( transform_str );
		} else if( compare_to ) {
			char* compare_str = searchPredicate( order_class_info, field_def, compare_to, ctx );
			if( ! compare_str ) {
				if( ctx )
					osrfAppSessionStatus(
						ctx->session,
						OSRF_STATUS_INTERNALSERVERERROR,
						"osrfMethodException",
						ctx->request,
						"Severe query error in ORDER BY clause -- "
						"see error log for more details"
					);
				buffer_free( order_buf );
				return NULL;
			}

			buffer_fadd( order_buf, "(%s)", compare_str );
			free( compare_str );
		}
		else
			buffer_fadd( order_buf, "\"%s\".%s", class_alias, field );

		const char* direction =
			jsonObjectGetString( jsonObjectGetKeyConst( order_spec, "direction" ) );
		if( direction ) {
			if( direction[ 0 ] && ( 'd' == direction[ 0 ] || 'D' == direction[ 0 ] ) )
				OSRF_BUFFER_ADD( order_buf, " DESC" );
			else
				OSRF_BUFFER_ADD( order_buf, " ASC" );
		}
	}

	return buffer_release( order_buf );
}

/**
	@brief Build a SELECT statement.
	@param search_hash Pointer to a JSON_HASH or JSON_ARRAY encoding the WHERE clause.
	@param rest_of_query Pointer to a JSON_HASH containing any other SQL clauses.
	@param meta Pointer to the class metadata for the core class.
	@param ctx Pointer to the method context.
	@return Pointer to a character string containing the WHERE clause; or NULL upon error.

	Within the rest_of_query hash, the meaningful keys are "join", "select", "no_i18n",
	"order_by", "limit", and "offset".

	The SELECT statements built here are distinct from those built for the json_query method.
*/
static char* buildSELECT ( const jsonObject* search_hash, jsonObject* rest_of_query,
	osrfHash* meta, osrfMethodContext* ctx ) {

	const char* locale = osrf_message_get_last_locale();

	osrfHash* fields = osrfHashGet( meta, "fields" );
	const char* core_class = osrfHashGet( meta, "classname" );

	const jsonObject* join_hash = jsonObjectGetKeyConst( rest_of_query, "join" );

	jsonObject* selhash = NULL;
	jsonObject* defaultselhash = NULL;

	growing_buffer* sql_buf = buffer_init( 128 );
	growing_buffer* select_buf = buffer_init( 128 );

	if( !(selhash = jsonObjectGetKey( rest_of_query, "select" )) ) {
		defaultselhash = jsonNewObjectType( JSON_HASH );
		selhash = defaultselhash;
	}

	// If there's no SELECT list for the core class, build one
	if( !jsonObjectGetKeyConst( selhash, core_class ) ) {
		jsonObject* field_list = jsonNewObjectType( JSON_ARRAY );

		// Add every non-virtual field to the field list
		osrfHash* field_def = NULL;
		osrfHashIterator* field_itr = osrfNewHashIterator( fields );
		while( ( field_def = osrfHashIteratorNext( field_itr ) ) ) {
			if( ! str_is_true( osrfHashGet( field_def, "virtual" ) ) ) {
				const char* field = osrfHashIteratorKey( field_itr );
				jsonObjectPush( field_list, jsonNewObject( field ) );
			}
		}
		osrfHashIteratorFree( field_itr );
		jsonObjectSetKey( selhash, core_class, field_list );
	}

	// Build a list of columns for the SELECT clause
	int first = 1;
	const jsonObject* snode = NULL;
	jsonIterator* class_itr = jsonNewIterator( selhash );
	while( (snode = jsonIteratorNext( class_itr )) ) {        // For each class

		// If the class isn't in the IDL, ignore it
		const char* cname = class_itr->key;
		osrfHash* idlClass = osrfHashGet( oilsIDL(), cname );
		if( !idlClass )
			continue;

		// If the class isn't the core class, and isn't in the JOIN clause, ignore it
		if( strcmp( core_class, class_itr->key )) {
			if( !join_hash )
				continue;

			jsonObject* found = jsonObjectFindPath( join_hash, "//%s", class_itr->key );
			if( !found->size ) {
				jsonObjectFree( found );
				continue;
			}

			jsonObjectFree( found );
		}

		const jsonObject* node = NULL;
		jsonIterator* select_itr = jsonNewIterator( snode );
		while( (node = jsonIteratorNext( select_itr )) ) {
			const char* item_str = jsonObjectGetString( node );
			osrfHash* field = osrfHashGet( osrfHashGet( idlClass, "fields" ), item_str );
			char* fname = osrfHashGet( field, "name" );

			if( !field )
				continue;

			if( first ) {
				first = 0;
			} else {
				OSRF_BUFFER_ADD_CHAR( select_buf, ',' );
			}

			if( locale ) {
				const char* i18n;
				const jsonObject* no_i18n_obj = jsonObjectGetKeyConst( rest_of_query, "no_i18n" );
				if( obj_is_true( no_i18n_obj ) )    // Suppress internationalization?
					i18n = NULL;
				else
					i18n = osrfHashGet( field, "i18n" );

				if( str_is_true( i18n ) ) {
					char* pkey = osrfHashGet( idlClass, "primarykey" );
					char* tname = osrfHashGet( idlClass, "tablename" );

					buffer_fadd( select_buf, " oils_i18n_xlate('%s', '%s', '%s', "
							"'%s', \"%s\".%s::TEXT, '%s') AS \"%s\"",
							tname, cname, fname, pkey, cname, pkey, locale, fname );
				} else {
					buffer_fadd( select_buf, " \"%s\".%s", cname, fname );
				}
			} else {
				buffer_fadd( select_buf, " \"%s\".%s", cname, fname );
			}
		}

		jsonIteratorFree( select_itr );
	}

	jsonIteratorFree( class_itr );

	char* col_list = buffer_release( select_buf );
	char* table = oilsGetRelation( meta );
	if( !table )
		table = strdup( "(null)" );

	buffer_fadd( sql_buf, "SELECT %s FROM %s AS \"%s\"", col_list, table, core_class );
	free( col_list );
	free( table );

	// Clear the query stack (as a fail-safe precaution against possible
	// leftover garbage); then push the first query frame onto the stack.
	clear_query_stack();
	push_query_frame();
	if( add_query_core( NULL, core_class ) ) {
		if( ctx )
			osrfAppSessionStatus(
				ctx->session,
				OSRF_STATUS_INTERNALSERVERERROR,
				"osrfMethodException",
				ctx->request,
				"Unable to build query frame for core class"
			);
		buffer_free( sql_buf );
		if( defaultselhash )
			jsonObjectFree( defaultselhash );
		return NULL;
	}

	// Add the JOIN clauses, if any
	if( join_hash ) {
		char* join_clause = searchJOIN( join_hash, &curr_query->core );
		OSRF_BUFFER_ADD_CHAR( sql_buf, ' ' );
		OSRF_BUFFER_ADD( sql_buf, join_clause );
		free( join_clause );
	}

	osrfLogDebug( OSRF_LOG_MARK, "%s pre-predicate SQL =  %s",
		modulename, OSRF_BUFFER_C_STR( sql_buf ));

	OSRF_BUFFER_ADD( sql_buf, " WHERE " );

	// Add the conditions in the WHERE clause
	char* pred = searchWHERE( search_hash, &curr_query->core, AND_OP_JOIN, ctx );
	if( !pred ) {
		osrfAppSessionStatus(
			ctx->session,
			OSRF_STATUS_INTERNALSERVERERROR,
				"osrfMethodException",
				ctx->request,
				"Severe query error -- see error log for more details"
			);
		buffer_free( sql_buf );
		if( defaultselhash )
			jsonObjectFree( defaultselhash );
		clear_query_stack();
		return NULL;
	} else {
		buffer_add( sql_buf, pred );
		free( pred );
	}

	// Add the ORDER BY, LIMIT, and/or OFFSET clauses, if present
	if( rest_of_query ) {
		const jsonObject* order_by = NULL;
		if( ( order_by = jsonObjectGetKeyConst( rest_of_query, "order_by" )) ){

			char* order_by_list = NULL;

			if( JSON_ARRAY == order_by->type ) {
				order_by_list = buildOrderByFromArray( ctx, order_by );
				if( !order_by_list ) {
					buffer_free( sql_buf );
					if( defaultselhash )
						jsonObjectFree( defaultselhash );
					clear_query_stack();
					return NULL;
				}
			} else if( JSON_HASH == order_by->type ) {
				// We expect order_by to be a JSON_HASH keyed on class names.  Traverse it
				// and build a list of ORDER BY expressions.
				growing_buffer* order_buf = buffer_init( 128 );
				first = 1;
				jsonIterator* class_itr = jsonNewIterator( order_by );
				while( (snode = jsonIteratorNext( class_itr )) ) {  // For each class:

					ClassInfo* order_class_info = search_alias( class_itr->key );
					if( ! order_class_info )
						continue;    // class not referenced by FROM clause?  Ignore it.

					if( JSON_HASH == snode->type ) {

						// If the data for the current class is a JSON_HASH, then it is
						// keyed on field name.

						const jsonObject* onode = NULL;
						jsonIterator* order_itr = jsonNewIterator( snode );
						while( (onode = jsonIteratorNext( order_itr )) ) {  // For each field

							osrfHash* field_def = osrfHashGet(
								order_class_info->fields, order_itr->key );
							if( !field_def )
								continue;    // Field not defined in IDL?  Ignore it.
							if( str_is_true( osrfHashGet( field_def, "virtual")))
								continue;    // Field is virtual?  Ignore it.

							char* field_str = NULL;
							char* direction = NULL;
							if( onode->type == JSON_HASH ) {
								if( jsonObjectGetKeyConst( onode, "transform" ) ) {
									field_str = searchFieldTransform(
										class_itr->key, field_def, onode );
									if( ! field_str ) {
										osrfAppSessionStatus(
											ctx->session,
											OSRF_STATUS_INTERNALSERVERERROR,
											"osrfMethodException",
											ctx->request,
											"Severe query error in ORDER BY clause -- "
											"see error log for more details"
										);
										jsonIteratorFree( order_itr );
										jsonIteratorFree( class_itr );
										buffer_free( order_buf );
										buffer_free( sql_buf );
										if( defaultselhash )
											jsonObjectFree( defaultselhash );
										clear_query_stack();
										return NULL;
									}
								} else {
									growing_buffer* field_buf = buffer_init( 16 );
									buffer_fadd( field_buf, "\"%s\".%s",
										class_itr->key, order_itr->key );
									field_str = buffer_release( field_buf );
								}

								if( ( order_by = jsonObjectGetKeyConst( onode, "direction" )) ) {
									const char* dir = jsonObjectGetString( order_by );
									if(!strncasecmp( dir, "d", 1 )) {
										direction = " DESC";
									}
								}
							} else {
								field_str = strdup( order_itr->key );
								const char* dir = jsonObjectGetString( onode );
								if( !strncasecmp( dir, "d", 1 )) {
									direction = " DESC";
								} else {
									direction = " ASC";
								}
							}

							if( first ) {
								first = 0;
							} else {
								buffer_add( order_buf, ", " );
							}

							buffer_add( order_buf, field_str );
							free( field_str );

							if( direction ) {
								buffer_add( order_buf, direction );
							}
						} // end while; looping over ORDER BY expressions

						jsonIteratorFree( order_itr );

					} else if( JSON_STRING == snode->type ) {
						// We expect a comma-separated list of sort fields.
						const char* str = jsonObjectGetString( snode );
						if( strchr( str, ';' )) {
							// No semicolons allowed.  It is theoretically possible for a
							// legitimate semicolon to occur within quotes, but it's not likely
							// to occur in practice in the context of an ORDER BY list.
							osrfLogError( OSRF_LOG_MARK, "%s: Possible attempt at SOL injection -- "
								"semicolon found in ORDER BY list: \"%s\"", modulename, str );
							if( ctx ) {
								osrfAppSessionStatus(
									ctx->session,
									OSRF_STATUS_INTERNALSERVERERROR,
									"osrfMethodException",
									ctx->request,
									"Possible attempt at SOL injection -- "
										"semicolon found in ORDER BY list"
								);
							}
							jsonIteratorFree( class_itr );
							buffer_free( order_buf );
							buffer_free( sql_buf );
							if( defaultselhash )
								jsonObjectFree( defaultselhash );
							clear_query_stack();
							return NULL;
						}
						buffer_add( order_buf, str );
						break;
					}

				} // end while; looping over order_by classes

				jsonIteratorFree( class_itr );
				order_by_list = buffer_release( order_buf );

			} else {
				osrfLogWarning( OSRF_LOG_MARK,
					"\"order_by\" object in a query is not a JSON_HASH or JSON_ARRAY;"
					"no ORDER BY generated" );
			}

			if( order_by_list && *order_by_list ) {
				OSRF_BUFFER_ADD( sql_buf, " ORDER BY " );
				OSRF_BUFFER_ADD( sql_buf, order_by_list );
			}

			free( order_by_list );
		}

		const jsonObject* limit = jsonObjectGetKeyConst( rest_of_query, "limit" );
		if( limit ) {
			const char* str = jsonObjectGetString( limit );
			if (str) {
				buffer_fadd(
					sql_buf,
					" LIMIT %d",
					atoi(str)
				);
			}
		}

		const jsonObject* offset = jsonObjectGetKeyConst( rest_of_query, "offset" );
		if( offset ) {
			const char* str = jsonObjectGetString( offset );
			if (str) {
				buffer_fadd(
					sql_buf,
					" OFFSET %d",
					atoi( str )
				);
			}
		}
	}

	if( defaultselhash )
		jsonObjectFree( defaultselhash );
	clear_query_stack();

	OSRF_BUFFER_ADD_CHAR( sql_buf, ';' );
	return buffer_release( sql_buf );
}

int doJSONSearch ( osrfMethodContext* ctx ) {
	if(osrfMethodVerifyContext( ctx )) {
		osrfLogError( OSRF_LOG_MARK,  "Invalid method context" );
		return -1;
	}

	osrfLogDebug( OSRF_LOG_MARK, "Received query request" );

	int err = 0;

	jsonObject* hash = jsonObjectGetIndex( ctx->params, 0 );

	int flags = 0;

	if( obj_is_true( jsonObjectGetKeyConst( hash, "distinct" )))
		flags |= SELECT_DISTINCT;

	if( obj_is_true( jsonObjectGetKeyConst( hash, "no_i18n" )))
		flags |= DISABLE_I18N;

	osrfLogDebug( OSRF_LOG_MARK, "Building SQL ..." );
	clear_query_stack();       // a possibly needless precaution
	char* sql = buildQuery( ctx, hash, flags );
	clear_query_stack();

	if( !sql ) {
		err = -1;
		return err;
	}

	osrfLogDebug( OSRF_LOG_MARK, "%s SQL =  %s", modulename, sql );

	// XXX for now...
	dbhandle = writehandle;

	dbi_result result = dbi_conn_query( dbhandle, sql );

	if( result ) {
		osrfLogDebug( OSRF_LOG_MARK, "Query returned with no errors" );

		if( dbi_result_first_row( result )) {
			/* JSONify the result */
			osrfLogDebug( OSRF_LOG_MARK, "Query returned at least one row" );

			do {
				jsonObject* return_val = oilsMakeJSONFromResult( result );
				osrfAppRespond( ctx, return_val );
				jsonObjectFree( return_val );
			} while( dbi_result_next_row( result ));

		} else {
			osrfLogDebug( OSRF_LOG_MARK, "%s returned no results for query %s", modulename, sql );
		}

		osrfAppRespondComplete( ctx, NULL );

		/* clean up the query */
		dbi_result_free( result );

	} else {
		err = -1;
		const char* msg;
		int errnum = dbi_conn_error( dbhandle, &msg );
		osrfLogError( OSRF_LOG_MARK, "%s: Error with query [%s]: %d %s",
			modulename, sql, errnum, msg ? msg : "(No description available)" );
		osrfAppSessionStatus(
			ctx->session,
			OSRF_STATUS_INTERNALSERVERERROR,
			"osrfMethodException",
			ctx->request,
			"Severe query error -- see error log for more details"
		);
		if( !oilsIsDBConnected( dbhandle ))
			osrfAppSessionPanic( ctx->session );
	}

	free( sql );
	return err;
}

// The last parameter, err, is used to report an error condition by updating an int owned by
// the calling code.

// In case of an error, we set *err to -1.  If there is no error, *err is left unchanged.
// It is the responsibility of the calling code to initialize *err before the
// call, so that it will be able to make sense of the result.

// Note also that we return NULL if and only if we set *err to -1.  So the err parameter is
// redundant anyway.
static jsonObject* doFieldmapperSearch( osrfMethodContext* ctx, osrfHash* class_meta,
		jsonObject* where_hash, jsonObject* query_hash, int* err ) {

	// XXX for now...
	dbhandle = writehandle;

	char* core_class = osrfHashGet( class_meta, "classname" );
	osrfLogDebug( OSRF_LOG_MARK, "entering doFieldmapperSearch() with core_class %s", core_class );

	char* pkey = osrfHashGet( class_meta, "primarykey" );

	if (!ctx->session->userData)
		(void) initSessionCache( ctx );

	char *methodtype = osrfHashGet( (osrfHash *) ctx->method->userData, "methodtype" );
	char *inside_verify = osrfHashGet( (osrfHash*) ctx->session->userData, "inside_verify" );
	int need_to_verify = (inside_verify ? !atoi(inside_verify) : 1);

	int i_respond_directly = 0;
	int flesh_depth = 0;

	char* sql = buildSELECT( where_hash, query_hash, class_meta, ctx );
	if( !sql ) {
		osrfLogDebug( OSRF_LOG_MARK, "Problem building query, returning NULL" );
		*err = -1;
		return NULL;
	}

	osrfLogDebug( OSRF_LOG_MARK, "%s SQL =  %s", modulename, sql );

	dbi_result result = dbi_conn_query( dbhandle, sql );
	if( NULL == result ) {
		const char* msg;
		int errnum = dbi_conn_error( dbhandle, &msg );
		osrfLogError(OSRF_LOG_MARK, "%s: Error retrieving %s with query [%s]: %d %s",
			modulename, osrfHashGet( class_meta, "fieldmapper" ), sql, errnum,
			msg ? msg : "(No description available)" );
		if( !oilsIsDBConnected( dbhandle ))
			osrfAppSessionPanic( ctx->session );
		osrfAppSessionStatus(
			ctx->session,
			OSRF_STATUS_INTERNALSERVERERROR,
			"osrfMethodException",
			ctx->request,
			"Severe query error -- see error log for more details"
		);
		*err = -1;
		free( sql );
		return NULL;

	} else {
		osrfLogDebug( OSRF_LOG_MARK, "Query returned with no errors" );
	}

	jsonObject* res_list = jsonNewObjectType( JSON_ARRAY );
	jsonObject* row_obj = NULL;

	// The following two steps are for verifyObjectPCRUD()'s benefit.
	// 1. get the flesh depth
	const jsonObject* _tmp = jsonObjectGetKeyConst( query_hash, "flesh" );
	if( _tmp ) {
		flesh_depth = (int) jsonObjectGetNumber( _tmp );
		if( flesh_depth == -1 || flesh_depth > max_flesh_depth )
			flesh_depth = max_flesh_depth;
	}

	// 2. figure out one consistent rs_size for verifyObjectPCRUD to use
	// over the whole life of this request.  This means if we've already set
	// up a rs_size_req_%d, do nothing.
	//	a. Incidentally, we can also use this opportunity to set i_respond_directly
	int *rs_size = osrfHashGetFmt( (osrfHash *) ctx->session->userData, "rs_size_req_%d", ctx->request );
	if( !rs_size ) {	// pointer null, so value not set in hash
		// i_respond_directly can only be true at the /top/ of a recursive search, if even that.
		i_respond_directly = ( *methodtype == 'r' || *methodtype == 'i' || *methodtype == 's' );

		rs_size = (int *) safe_malloc( sizeof(int) );	// will be freed by sessionDataFree()
		unsigned long long result_count = dbi_result_get_numrows( result );
		*rs_size = (int) result_count * (flesh_depth + 1);	// yes, we could lose some bits, but come on
		osrfHashSet( (osrfHash *) ctx->session->userData, rs_size, "rs_size_req_%d", ctx->request );
	}

	if( dbi_result_first_row( result )) {

		// Convert each row to a JSON_ARRAY of column values, and enclose those objects
		// in a JSON_ARRAY of rows.  If two or more rows have the same key value, then
		// eliminate the duplicates.
		osrfLogDebug( OSRF_LOG_MARK, "Query returned at least one row" );
		osrfHash* dedup = osrfNewHash();
		do {
			row_obj = oilsMakeFieldmapperFromResult( result, class_meta );
			char* pkey_val = oilsFMGetString( row_obj, pkey );
			if( osrfHashGet( dedup, pkey_val ) ) {
				jsonObjectFree( row_obj );
				free( pkey_val );
			} else {
				if( !enforce_pcrud || !need_to_verify ||
						verifyObjectPCRUD( ctx, class_meta, row_obj, 0 /* means check user data for rs_size */ )) {
					osrfHashSet( dedup, pkey_val, pkey_val );
					jsonObjectPush( res_list, row_obj );
				}
			}
		} while( dbi_result_next_row( result ));
		osrfHashFree( dedup );

	} else {
		osrfLogDebug( OSRF_LOG_MARK, "%s returned no results for query %s",
			modulename, sql );
	}

	/* clean up the query */
	dbi_result_free( result );
	free( sql );

	// If we're asked to flesh, and there's anything to flesh, then flesh it
	// (formerly we would skip fleshing if in pcrud mode, but now we support
	// fleshing even in PCRUD).
	if( res_list->size ) {
		jsonObject* temp_blob;	// We need a non-zero flesh depth, and a list of fields to flesh
		jsonObject* flesh_fields; 
		jsonObject* flesh_blob = NULL;
		osrfStringArray* link_fields = NULL;
		osrfHash* links = NULL;
		int want_flesh = 0;

		if( query_hash ) {
			temp_blob = jsonObjectGetKey( query_hash, "flesh_fields" );
			if( temp_blob && flesh_depth > 0 ) {

				flesh_blob = jsonObjectClone( temp_blob );
				flesh_fields = jsonObjectGetKey( flesh_blob, core_class );

				links = osrfHashGet( class_meta, "links" );

				// Make an osrfStringArray of the names of fields to be fleshed
				if( flesh_fields ) {
					if( flesh_fields->size == 1 ) {
						const char* _t = jsonObjectGetString(
							jsonObjectGetIndex( flesh_fields, 0 ) );
						if( !strcmp( _t, "*" ))
							link_fields = osrfHashKeys( links );
					}

					if( !link_fields ) {
						jsonObject* _f;
						link_fields = osrfNewStringArray( 1 );
						jsonIterator* _i = jsonNewIterator( flesh_fields );
						while ((_f = jsonIteratorNext( _i ))) {
							osrfStringArrayAdd( link_fields, jsonObjectGetString( _f ) );
						}
						jsonIteratorFree( _i );
					}
				}
				want_flesh = link_fields ? 1 : 0;
			}
		}

		osrfHash* fields = osrfHashGet( class_meta, "fields" );

		// Iterate over the JSON_ARRAY of rows
		jsonObject* cur;
		unsigned long res_idx = 0;
		while((cur = jsonObjectGetIndex( res_list, res_idx++ ) )) {

			int i = 0;
			const char* link_field;

			// Iterate over the list of fleshable fields
			if ( want_flesh ) {
				while( (link_field = osrfStringArrayGetString(link_fields, i++)) ) {

					osrfLogDebug( OSRF_LOG_MARK, "Starting to flesh %s", link_field );

					osrfHash* kid_link = osrfHashGet( links, link_field );
					if( !kid_link )
						continue;     // Not a link field; skip it

					osrfHash* field = osrfHashGet( fields, link_field );
					if( !field )
						continue;     // Not a field at all; skip it (IDL is ill-formed)

					osrfHash* kid_idl = osrfHashGet( oilsIDL(),
						osrfHashGet( kid_link, "class" ));
					if( !kid_idl )
						continue;   // The class it links to doesn't exist; skip it

					const char* reltype = osrfHashGet( kid_link, "reltype" );
					if( !reltype )
						continue;   // No reltype; skip it (IDL is ill-formed)

					osrfHash* value_field = field;

					if(    !strcmp( reltype, "has_many" )
						|| !strcmp( reltype, "might_have" ) ) { // has_many or might_have
						value_field = osrfHashGet(
							fields, osrfHashGet( class_meta, "primarykey" ) );
					}

					int kid_has_controller = osrfStringArrayContains( osrfHashGet(kid_idl, "controller"), modulename );
					// fleshing pcrud case: we require the controller in need_to_verify mode
					if ( !kid_has_controller && enforce_pcrud && need_to_verify ) {
						osrfLogInfo( OSRF_LOG_MARK, "%s is not listed as a controller for %s; moving on", modulename, core_class );

						jsonObjectSetIndex(
							cur,
							(unsigned long) atoi( osrfHashGet(field, "array_position") ),
							jsonNewObjectType(
								!strcmp( reltype, "has_many" ) ? JSON_ARRAY : JSON_NULL
							)
						);
						continue;
					}

					osrfStringArray* link_map = osrfHashGet( kid_link, "map" );

					if( link_map->size > 0 ) {
						jsonObject* _kid_key = jsonNewObjectType( JSON_ARRAY );
						jsonObjectPush(
							_kid_key,
							jsonNewObject( osrfStringArrayGetString( link_map, 0 ) )
						);

						jsonObjectSetKey(
							flesh_blob,
							osrfHashGet( kid_link, "class" ),
							_kid_key
						);
					};

					osrfLogDebug(
						OSRF_LOG_MARK,
						"Link field: %s, remote class: %s, fkey: %s, reltype: %s",
						osrfHashGet( kid_link, "field" ),
						osrfHashGet( kid_link, "class" ),
						osrfHashGet( kid_link, "key" ),
						osrfHashGet( kid_link, "reltype" )
					);

					const char* search_key = jsonObjectGetString(
						jsonObjectGetIndex( cur,
							atoi( osrfHashGet( value_field, "array_position" ) )
						)
					);

					if( !search_key ) {
						osrfLogDebug( OSRF_LOG_MARK, "Nothing to search for!" );
						continue;
					}

					osrfLogDebug( OSRF_LOG_MARK, "Creating param objects..." );

					// construct WHERE clause
					jsonObject* where_clause  = jsonNewObjectType( JSON_HASH );
					jsonObjectSetKey(
						where_clause,
						osrfHashGet( kid_link, "key" ),
						jsonNewObject( search_key )
					);

					// construct the rest of the query, mostly
					// by copying pieces of the previous level of query
					jsonObject* rest_of_query = jsonNewObjectType( JSON_HASH );
					jsonObjectSetKey( rest_of_query, "flesh",
						jsonNewNumberObject( flesh_depth - 1 + link_map->size )
					);

					if( flesh_blob )
						jsonObjectSetKey( rest_of_query, "flesh_fields",
							jsonObjectClone( flesh_blob ));

					if( jsonObjectGetKeyConst( query_hash, "order_by" )) {
						jsonObjectSetKey( rest_of_query, "order_by",
							jsonObjectClone( jsonObjectGetKeyConst( query_hash, "order_by" ))
						);
					}

					if( jsonObjectGetKeyConst( query_hash, "select" )) {
						jsonObjectSetKey( rest_of_query, "select",
							jsonObjectClone( jsonObjectGetKeyConst( query_hash, "select" ))
						);
					}

					// do the query, recursively, to expand the fleshable field
					jsonObject* kids = doFieldmapperSearch( ctx, kid_idl,
						where_clause, rest_of_query, err );

					jsonObjectFree( where_clause );
					jsonObjectFree( rest_of_query );

					if( *err ) {
						osrfStringArrayFree( link_fields );
						jsonObjectFree( res_list );
						jsonObjectFree( flesh_blob );
						return NULL;
					}

					osrfLogDebug( OSRF_LOG_MARK, "Search for %s return %d linked objects",
						osrfHashGet( kid_link, "class" ), kids->size );

					// Traverse the result set
					jsonObject* X = NULL;
					if( link_map->size > 0 && kids->size > 0 ) {
						X = kids;
						kids = jsonNewObjectType( JSON_ARRAY );

						jsonObject* _k_node;
						unsigned long res_idx = 0;
						while((_k_node = jsonObjectGetIndex( X, res_idx++ ) )) {
							jsonObjectPush(
								kids,
								jsonObjectClone(
									jsonObjectGetIndex(
										_k_node,
										(unsigned long) atoi(
											osrfHashGet(
												osrfHashGet(
													osrfHashGet(
														osrfHashGet(
															oilsIDL(),
															osrfHashGet( kid_link, "class" )
														),
														"fields"
													),
													osrfStringArrayGetString( link_map, 0 )
												),
												"array_position"
											)
										)
									)
								)
							);
						} // end while loop traversing X
					}

					if (kids->size > 0) {

						if((   !strcmp( osrfHashGet( kid_link, "reltype" ), "has_a" )
							|| !strcmp( osrfHashGet( kid_link, "reltype" ), "might_have" ))
						) {
							osrfLogDebug(OSRF_LOG_MARK, "Storing fleshed objects in %s",
								osrfHashGet( kid_link, "field" ));
							jsonObjectSetIndex(
								cur,
								(unsigned long) atoi( osrfHashGet( field, "array_position" ) ),
								jsonObjectClone( jsonObjectGetIndex( kids, 0 ))
							);
						}
					}

					if( !strcmp( osrfHashGet( kid_link, "reltype" ), "has_many" )) {
						// has_many
						osrfLogDebug( OSRF_LOG_MARK, "Storing fleshed objects in %s",
							osrfHashGet( kid_link, "field" ) );
						jsonObjectSetIndex(
							cur,
							(unsigned long) atoi( osrfHashGet( field, "array_position" ) ),
							jsonObjectClone( kids )
						);
					}

					if( X ) {
						jsonObjectFree( kids );
						kids = X;
					}

					jsonObjectFree( kids );

					osrfLogDebug( OSRF_LOG_MARK, "Fleshing of %s complete",
						osrfHashGet( kid_link, "field" ) );
					osrfLogDebug( OSRF_LOG_MARK, "%s", jsonObjectToJSON( cur ));

				} // end while loop traversing list of fleshable fields
			}

			if( i_respond_directly ) {
				if ( *methodtype == 'i' ) {
					osrfAppRespond( ctx,
						oilsFMGetObject( cur, osrfHashGet( class_meta, "primarykey" ) ) );
				} else {
					osrfAppRespond( ctx, cur );
				}
			}
		} // end while loop traversing res_list
		jsonObjectFree( flesh_blob );
		osrfStringArrayFree( link_fields );
	}

	if( i_respond_directly ) {
		jsonObjectFree( res_list );
		return jsonNewObjectType( JSON_ARRAY );
	} else {
		return res_list;
	}
}


int doUpdate( osrfMethodContext* ctx ) {
	if( osrfMethodVerifyContext( ctx )) {
		osrfLogError( OSRF_LOG_MARK, "Invalid method context" );
		return -1;
	}

	if( enforce_pcrud )
		timeout_needs_resetting = 1;

	osrfHash* meta = osrfHashGet( (osrfHash*) ctx->method->userData, "class" );

	jsonObject* target = NULL;
	if( enforce_pcrud )
		target = jsonObjectGetIndex( ctx->params, 1 );
	else
		target = jsonObjectGetIndex( ctx->params, 0 );

	if(!verifyObjectClass( ctx, target )) {
		osrfAppRespondComplete( ctx, NULL );
		return -1;
	}

	if( getXactId( ctx ) == NULL ) {
		osrfAppSessionStatus(
			ctx->session,
			OSRF_STATUS_BADREQUEST,
			"osrfMethodException",
			ctx->request,
			"No active transaction -- required for UPDATE"
		);
		osrfAppRespondComplete( ctx, NULL );
		return -1;
	}

	// The following test is harmless but redundant.  If a class is
	// readonly, we don't register an update method for it.
	if( str_is_true( osrfHashGet( meta, "readonly" ) ) ) {
		osrfAppSessionStatus(
			ctx->session,
			OSRF_STATUS_BADREQUEST,
			"osrfMethodException",
			ctx->request,
			"Cannot UPDATE readonly class"
		);
		osrfAppRespondComplete( ctx, NULL );
		return -1;
	}

	const char* trans_id = getXactId( ctx );

	// Set the last_xact_id
	int index = oilsIDL_ntop( target->classname, "last_xact_id" );
	if( index > -1 ) {
		osrfLogDebug( OSRF_LOG_MARK, "Setting last_xact_id to %s on %s at position %d",
				trans_id, target->classname, index );
		jsonObjectSetIndex( target, index, jsonNewObject( trans_id ));
	}

	char* pkey = osrfHashGet( meta, "primarykey" );
	osrfHash* fields = osrfHashGet( meta, "fields" );

	char* id = oilsFMGetString( target, pkey );

	osrfLogDebug(
		OSRF_LOG_MARK,
		"%s updating %s object with %s = %s",
		modulename,
		osrfHashGet( meta, "fieldmapper" ),
		pkey,
		id
	);

	dbhandle = writehandle;
	growing_buffer* sql = buffer_init( 128 );
	buffer_fadd( sql,"UPDATE %s SET", osrfHashGet( meta, "tablename" ));

	int first = 1;
	osrfHash* field_def = NULL;
	osrfHashIterator* field_itr = osrfNewHashIterator( fields );
	while( ( field_def = osrfHashIteratorNext( field_itr ) ) ) {

		// Skip virtual fields, and the primary key
		if( str_is_true( osrfHashGet( field_def, "virtual") ) )
			continue;

		const char* field_name = osrfHashIteratorKey( field_itr );
		if( ! strcmp( field_name, pkey ) )
			continue;

		const jsonObject* field_object = oilsFMGetObject( target, field_name );

		int value_is_numeric = 0;    // boolean
		char* value;
		if( field_object && field_object->classname ) {
			value = oilsFMGetString(
				field_object,
				(char*) oilsIDLFindPath( "/%s/primarykey", field_object->classname )
			);
		} else if( field_object && JSON_BOOL == field_object->type ) {
			if( jsonBoolIsTrue( field_object ) )
				value = strdup( "t" );
			else
				value = strdup( "f" );
		} else {
			value = jsonObjectToSimpleString( field_object );
			if( field_object && JSON_NUMBER == field_object->type )
				value_is_numeric = 1;
		}

		osrfLogDebug( OSRF_LOG_MARK, "Updating %s object with %s = %s",
				osrfHashGet( meta, "fieldmapper" ), field_name, value);

		if( !field_object || field_object->type == JSON_NULL ) {
			if( !( !( strcmp( osrfHashGet( meta, "classname" ), "au" ) )
					&& !( strcmp( field_name, "passwd" ) )) ) { // arg at the special case!
				if( first )
					first = 0;
				else
					OSRF_BUFFER_ADD_CHAR( sql, ',' );
				buffer_fadd( sql, " %s = NULL", field_name );
			}

		} else if( value_is_numeric || !strcmp( get_primitive( field_def ), "number") ) {
			if( first )
				first = 0;
			else
				OSRF_BUFFER_ADD_CHAR( sql, ',' );

			const char* numtype = get_datatype( field_def );
			if( !strncmp( numtype, "INT", 3 ) ) {
				buffer_fadd( sql, " %s = %ld", field_name, atol( value ) );
			} else if( !strcmp( numtype, "NUMERIC" ) ) {
				buffer_fadd( sql, " %s = %f", field_name, atof( value ) );
			} else {
				// Must really be intended as a string, so quote it
				if( dbi_conn_quote_string( dbhandle, &value )) {
					buffer_fadd( sql, " %s = %s", field_name, value );
				} else {
					osrfLogError( OSRF_LOG_MARK, "%s: Error quoting string [%s]",
						modulename, value );
					osrfAppSessionStatus(
						ctx->session,
						OSRF_STATUS_INTERNALSERVERERROR,
						"osrfMethodException",
						ctx->request,
						"Error quoting string -- please see the error log for more details"
					);
					free( value );
					free( id );
					osrfHashIteratorFree( field_itr );
					buffer_free( sql );
					osrfAppRespondComplete( ctx, NULL );
					return -1;
				}
			}

			osrfLogDebug( OSRF_LOG_MARK, "%s is of type %s", field_name, numtype );

		} else {
			if( dbi_conn_quote_string( dbhandle, &value ) ) {
				if( first )
					first = 0;
				else
					OSRF_BUFFER_ADD_CHAR( sql, ',' );
				buffer_fadd( sql, " %s = %s", field_name, value );
			} else {
				osrfLogError( OSRF_LOG_MARK, "%s: Error quoting string [%s]", modulename, value );
				osrfAppSessionStatus(
					ctx->session,
					OSRF_STATUS_INTERNALSERVERERROR,
					"osrfMethodException",
					ctx->request,
					"Error quoting string -- please see the error log for more details"
				);
				free( value );
				free( id );
				osrfHashIteratorFree( field_itr );
				buffer_free( sql );
				osrfAppRespondComplete( ctx, NULL );
				return -1;
			}
		}

		free( value );

	} // end while

	osrfHashIteratorFree( field_itr );

	jsonObject* obj = jsonNewObject( id );

	if( strcmp( get_primitive( osrfHashGet( osrfHashGet(meta, "fields"), pkey )), "number" ))
		dbi_conn_quote_string( dbhandle, &id );

	buffer_fadd( sql, " WHERE %s = %s;", pkey, id );

	char* query = buffer_release( sql );
	osrfLogDebug( OSRF_LOG_MARK, "%s: Update SQL [%s]", modulename, query );

	dbi_result result = dbi_conn_query( dbhandle, query );
	free( query );

	int rc = 0;
	if( !result ) {
		jsonObjectFree( obj );
		obj = jsonNewObject( NULL );
		const char* msg;
		int errnum = dbi_conn_error( dbhandle, &msg );
		osrfLogError(
			OSRF_LOG_MARK,
			"%s ERROR updating %s object with %s = %s: %d %s",
			modulename,
			osrfHashGet( meta, "fieldmapper" ),
			pkey,
			id,
			errnum,
			msg ? msg : "(No description available)"
		);
		osrfAppSessionStatus(
			ctx->session,
			OSRF_STATUS_INTERNALSERVERERROR,
			"osrfMethodException",
			ctx->request,
			"Error in updating a row -- please see the error log for more details"
		);
		if( !oilsIsDBConnected( dbhandle ))
			osrfAppSessionPanic( ctx->session );
		rc = -1;
	} else
		dbi_result_free( result );

	free( id );
	osrfAppRespondComplete( ctx, obj );
	jsonObjectFree( obj );
	return rc;
}

int doDelete( osrfMethodContext* ctx ) {
	if( osrfMethodVerifyContext( ctx )) {
		osrfLogError( OSRF_LOG_MARK, "Invalid method context" );
		return -1;
	}

	if( enforce_pcrud )
		timeout_needs_resetting = 1;

	osrfHash* meta = osrfHashGet( (osrfHash*) ctx->method->userData, "class" );

	if( getXactId( ctx ) == NULL ) {
		osrfAppSessionStatus(
			ctx->session,
			OSRF_STATUS_BADREQUEST,
			"osrfMethodException",
			ctx->request,
			"No active transaction -- required for DELETE"
		);
		osrfAppRespondComplete( ctx, NULL );
		return -1;
	}

	// The following test is harmless but redundant.  If a class is
	// readonly, we don't register a delete method for it.
	if( str_is_true( osrfHashGet( meta, "readonly" ) ) ) {
		osrfAppSessionStatus(
			ctx->session,
			OSRF_STATUS_BADREQUEST,
			"osrfMethodException",
			ctx->request,
			"Cannot DELETE readonly class"
		);
		osrfAppRespondComplete( ctx, NULL );
		return -1;
	}

	dbhandle = writehandle;

	char* pkey = osrfHashGet( meta, "primarykey" );

	int _obj_pos = 0;
	if( enforce_pcrud )
		_obj_pos = 1;

	char* id;
	if( jsonObjectGetIndex( ctx->params, _obj_pos )->classname ) {
		if( !verifyObjectClass( ctx, jsonObjectGetIndex( ctx->params, _obj_pos ))) {
			osrfAppRespondComplete( ctx, NULL );
			return -1;
		}

		id = oilsFMGetString( jsonObjectGetIndex(ctx->params, _obj_pos), pkey );
	} else {
		if( enforce_pcrud && !verifyObjectPCRUD( ctx, meta, NULL, 1 )) {
			osrfAppRespondComplete( ctx, NULL );
			return -1;
		}
		id = jsonObjectToSimpleString( jsonObjectGetIndex( ctx->params, _obj_pos ));
	}

	osrfLogDebug(
		OSRF_LOG_MARK,
		"%s deleting %s object with %s = %s",
		modulename,
		osrfHashGet( meta, "fieldmapper" ),
		pkey,
		id
	);

	jsonObject* obj = jsonNewObject( id );

	if( strcmp( get_primitive( osrfHashGet( osrfHashGet(meta, "fields"), pkey ) ), "number" ) )
		dbi_conn_quote_string( writehandle, &id );

	dbi_result result = dbi_conn_queryf( writehandle, "DELETE FROM %s WHERE %s = %s;",
		osrfHashGet( meta, "tablename" ), pkey, id );

	int rc = 0;
	if( !result ) {
		rc = -1;
		jsonObjectFree( obj );
		obj = jsonNewObject( NULL );
		const char* msg;
		int errnum = dbi_conn_error( writehandle, &msg );
		osrfLogError(
			OSRF_LOG_MARK,
			"%s ERROR deleting %s object with %s = %s: %d %s",
			modulename,
			osrfHashGet( meta, "fieldmapper" ),
			pkey,
			id,
			errnum,
			msg ? msg : "(No description available)"
		);
		osrfAppSessionStatus(
			ctx->session,
			OSRF_STATUS_INTERNALSERVERERROR,
			"osrfMethodException",
			ctx->request,
			"Error in deleting a row -- please see the error log for more details"
		);
		if( !oilsIsDBConnected( writehandle ))
			osrfAppSessionPanic( ctx->session );
	} else
		dbi_result_free( result );

	free( id );

	osrfAppRespondComplete( ctx, obj );
	jsonObjectFree( obj );
	return rc;
}

/**
	@brief Translate a row returned from the database into a jsonObject of type JSON_ARRAY.
	@param result An iterator for a result set; we only look at the current row.
	@param @meta Pointer to the class metadata for the core class.
	@return Pointer to the resulting jsonObject if successful; otherwise NULL.

	If a column is not defined in the IDL, or if it has no array_position defined for it in
	the IDL, or if it is defined as virtual, ignore it.

	Otherwise, translate the column value into a jsonObject of type JSON_NULL, JSON_NUMBER,
	or JSON_STRING.  Then insert this jsonObject into the JSON_ARRAY according to its
	array_position in the IDL.

	A field defined in the IDL but not represented in the returned row will leave a hole
	in the JSON_ARRAY.  In effect it will be treated as a null value.

	In the resulting JSON_ARRAY, the field values appear in the sequence defined by the IDL,
	regardless of their sequence in the SELECT statement.  The JSON_ARRAY is assigned the
	classname corresponding to the @a meta argument.

	The calling code is responsible for freeing the the resulting jsonObject by calling
	jsonObjectFree().
*/
static jsonObject* oilsMakeFieldmapperFromResult( dbi_result result, osrfHash* meta) {
	if( !( result && meta )) return NULL;

	jsonObject* object = jsonNewObjectType( JSON_ARRAY );
	jsonObjectSetClass( object, osrfHashGet( meta, "classname" ));
	osrfLogInternal( OSRF_LOG_MARK, "Setting object class to %s ", object->classname );

	osrfHash* fields = osrfHashGet( meta, "fields" );

	int columnIndex = 1;
	const char* columnName;

	/* cycle through the columns in the row returned from the database */
	while( (columnName = dbi_result_get_field_name( result, columnIndex )) ) {

		osrfLogInternal( OSRF_LOG_MARK, "Looking for column named [%s]...", (char*) columnName );

		int fmIndex = -1;  // Will be set to the IDL's sequence number for this field

		/* determine the field type and storage attributes */
		unsigned short type = dbi_result_get_field_type_idx( result, columnIndex );
		int attr            = dbi_result_get_field_attribs_idx( result, columnIndex );

		// Fetch the IDL's sequence number for the field.  If the field isn't in the IDL,
		// or if it has no sequence number there, or if it's virtual, skip it.
		osrfHash* _f = osrfHashGet( fields, (char*) columnName );
		if( _f ) {

			if( str_is_true( osrfHashGet( _f, "virtual" )))
				continue;   // skip this column: IDL says it's virtual

			const char* pos = (char*) osrfHashGet( _f, "array_position" );
			if( !pos )      // IDL has no sequence number for it.  This shouldn't happen,
				continue;    // since we assign sequence numbers dynamically as we load the IDL.

			fmIndex = atoi( pos );
			osrfLogInternal( OSRF_LOG_MARK, "... Found column at position [%s]...", pos );
		} else {
			continue;     // This field is not defined in the IDL
		}

		// Stuff the column value into a slot in the JSON_ARRAY, indexed according to the
		// sequence number from the IDL (which is likely to be different from the sequence
		// of columns in the SELECT clause).
		if( dbi_result_field_is_null_idx( result, columnIndex )) {
			jsonObjectSetIndex( object, fmIndex, jsonNewObject( NULL ));
		} else {

			switch( type ) {

				case DBI_TYPE_INTEGER :

					if( attr & DBI_INTEGER_SIZE8 )
						jsonObjectSetIndex( object, fmIndex,
							jsonNewNumberObject(
								dbi_result_get_longlong_idx( result, columnIndex )));
					else
						jsonObjectSetIndex( object, fmIndex,
							jsonNewNumberObject( dbi_result_get_int_idx( result, columnIndex )));

					break;

				case DBI_TYPE_DECIMAL :
					jsonObjectSetIndex( object, fmIndex,
							jsonNewNumberObject( dbi_result_get_double_idx(result, columnIndex )));
					break;

				case DBI_TYPE_STRING :

					jsonObjectSetIndex(
						object,
						fmIndex,
						jsonNewObject( dbi_result_get_string_idx( result, columnIndex ))
					);

					break;

				case DBI_TYPE_DATETIME : {

					char dt_string[ 256 ] = "";
					struct tm gmdt;

					// Fetch the date column as a time_t
					time_t _tmp_dt = dbi_result_get_datetime_idx( result, columnIndex );

					// Translate the time_t to a human-readable string
					if( !( attr & DBI_DATETIME_DATE )) {
						gmtime_r( &_tmp_dt, &gmdt );
						strftime( dt_string, sizeof( dt_string ), "%T", &gmdt );
					} else if( !( attr & DBI_DATETIME_TIME )) {
						localtime_r( &_tmp_dt, &gmdt );
						strftime( dt_string, sizeof( dt_string ), "%04Y-%m-%d", &gmdt );
					} else {
						localtime_r( &_tmp_dt, &gmdt );
						strftime( dt_string, sizeof( dt_string ), "%04Y-%m-%dT%T%z", &gmdt );
					}

					jsonObjectSetIndex( object, fmIndex, jsonNewObject( dt_string ));

					break;
				}
				case DBI_TYPE_BINARY :
					osrfLogError( OSRF_LOG_MARK,
						"Can't do binary at column %s : index %d", columnName, columnIndex );
			} // End switch
		}
		++columnIndex;
	} // End while

	return object;
}

static jsonObject* oilsMakeJSONFromResult( dbi_result result ) {
	if( !result ) return NULL;

	jsonObject* object = jsonNewObject( NULL );

	time_t _tmp_dt;
	char dt_string[ 256 ];
	struct tm gmdt;

	int fmIndex;
	int columnIndex = 1;
	int attr;
	unsigned short type;
	const char* columnName;

	/* cycle through the column list */
	while(( columnName = dbi_result_get_field_name( result, columnIndex ))) {

		osrfLogInternal( OSRF_LOG_MARK, "Looking for column named [%s]...", (char*) columnName );

		fmIndex = -1; // reset the position

		/* determine the field type and storage attributes */
		type = dbi_result_get_field_type_idx( result, columnIndex );
		attr = dbi_result_get_field_attribs_idx( result, columnIndex );

		if( dbi_result_field_is_null_idx( result, columnIndex )) {
			jsonObjectSetKey( object, columnName, jsonNewObject( NULL ));
		} else {

			switch( type ) {

				case DBI_TYPE_INTEGER :

					if( attr & DBI_INTEGER_SIZE8 )
						jsonObjectSetKey( object, columnName,
								jsonNewNumberObject( dbi_result_get_longlong_idx(
										result, columnIndex )) );
					else
						jsonObjectSetKey( object, columnName, jsonNewNumberObject(
								dbi_result_get_int_idx( result, columnIndex )) );
					break;

				case DBI_TYPE_DECIMAL :
					jsonObjectSetKey( object, columnName, jsonNewNumberObject(
						dbi_result_get_double_idx( result, columnIndex )) );
					break;

				case DBI_TYPE_STRING :
					jsonObjectSetKey( object, columnName,
						jsonNewObject( dbi_result_get_string_idx( result, columnIndex )));
					break;

				case DBI_TYPE_DATETIME :

					memset( dt_string, '\0', sizeof( dt_string ));
					memset( &gmdt, '\0', sizeof( gmdt ));

					_tmp_dt = dbi_result_get_datetime_idx( result, columnIndex );

					if( !( attr & DBI_DATETIME_DATE )) {
						gmtime_r( &_tmp_dt, &gmdt );
						strftime( dt_string, sizeof( dt_string ), "%T", &gmdt );
					} else if( !( attr & DBI_DATETIME_TIME )) {
						localtime_r( &_tmp_dt, &gmdt );
						strftime( dt_string, sizeof( dt_string ), "%04Y-%m-%d", &gmdt );
					} else {
						localtime_r( &_tmp_dt, &gmdt );
						strftime( dt_string, sizeof( dt_string ), "%04Y-%m-%dT%T%z", &gmdt );
					}

					jsonObjectSetKey( object, columnName, jsonNewObject( dt_string ));
					break;

				case DBI_TYPE_BINARY :
					osrfLogError( OSRF_LOG_MARK,
						"Can't do binary at column %s : index %d", columnName, columnIndex );
			}
		}
		++columnIndex;
	} // end while loop traversing result

	return object;
}

// Interpret a string as true or false
int str_is_true( const char* str ) {
	if( NULL == str || strcasecmp( str, "true" ) )
		return 0;
	else
		return 1;
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

// Translate a numeric code into a text string identifying a type of
// jsonObject.  To be used for building error messages.
static const char* json_type( int code ) {
	switch ( code )
	{
		case 0 :
			return "JSON_HASH";
		case 1 :
			return "JSON_ARRAY";
		case 2 :
			return "JSON_STRING";
		case 3 :
			return "JSON_NUMBER";
		case 4 :
			return "JSON_NULL";
		case 5 :
			return "JSON_BOOL";
		default :
			return "(unrecognized)";
	}
}

// Extract the "primitive" attribute from an IDL field definition.
// If we haven't initialized the app, then we must be running in
// some kind of testbed.  In that case, default to "string".
static const char* get_primitive( osrfHash* field ) {
	const char* s = osrfHashGet( field, "primitive" );
	if( !s ) {
		if( child_initialized )
			osrfLogError(
				OSRF_LOG_MARK,
				"%s ERROR No \"datatype\" attribute for field \"%s\"",
				modulename,
				osrfHashGet( field, "name" )
			);

		s = "string";
	}
	return s;
}

// Extract the "datatype" attribute from an IDL field definition.
// If we haven't initialized the app, then we must be running in
// some kind of testbed.  In that case, default to to NUMERIC,
// since we look at the datatype only for numbers.
static const char* get_datatype( osrfHash* field ) {
	const char* s = osrfHashGet( field, "datatype" );
	if( !s ) {
		if( child_initialized )
			osrfLogError(
				OSRF_LOG_MARK,
				"%s ERROR No \"datatype\" attribute for field \"%s\"",
				modulename,
				osrfHashGet( field, "name" )
			);
		else
			s = "NUMERIC";
	}
	return s;
}

/**
	@brief Determine whether a string is potentially a valid SQL identifier.
	@param s The identifier to be tested.
	@return 1 if the input string is potentially a valid SQL identifier, or 0 if not.

	Purpose: to prevent certain kinds of SQL injection.  To that end we don't necessarily
	need to follow all the rules exactly, such as requiring that the first character not
	be a digit.

	We allow leading and trailing white space.  In between, we do not allow punctuation
	(except for underscores and dollar signs), control characters, or embedded white space.

	More pedantically we should allow quoted identifiers containing arbitrary characters, but
	for the foreseeable future such quoted identifiers are not likely to be an issue.
*/
int is_identifier( const char* s) {
	if( !s )
		return 0;

	// Skip leading white space
	while( isspace( (unsigned char) *s ) )
		++s;

	if( !s )
		return 0;   // Nothing but white space?  Not okay.

	// Check each character until we reach white space or
	// end-of-string.  Letters, digits, underscores, and
	// dollar signs are okay. With the exception of periods
	// (as in schema.identifier), control characters and other
	// punctuation characters are not okay.  Anything else
	// is okay -- it could for example be part of a multibyte
	// UTF8 character such as a letter with diacritical marks,
	// and those are allowed.
	do {
		if( isalnum( (unsigned char) *s )
			|| '.' == *s
			|| '_' == *s
			|| '$' == *s )
			;  // Fine; keep going
		else if(   ispunct( (unsigned char) *s )
				|| iscntrl( (unsigned char) *s ) )
			return 0;
			++s;
	} while( *s && ! isspace( (unsigned char) *s ) );

	// If we found any white space in the above loop,
	// the rest had better be all white space.

	while( isspace( (unsigned char) *s ) )
		++s;

	if( *s )
		return 0;   // White space was embedded within non-white space

	return 1;
}

/**
	@brief Determine whether to accept a character string as a comparison operator.
	@param op The candidate comparison operator.
	@return 1 if the string is acceptable as a comparison operator, or 0 if not.

	We don't validate the operator for real.  We just make sure that it doesn't contain
	any semicolons or white space (with special exceptions for a few specific operators).
	The idea is to block certain kinds of SQL injection.  If it has no semicolons or white
	space but it's still not a valid operator, then the database will complain.

	Another approach would be to compare the string against a short list of approved operators.
	We don't do that because we want to allow custom operators like ">100*", which at this
	writing would be difficult or impossible to express otherwise in a JSON query.
*/
int is_good_operator( const char* op ) {
	if( !op ) return 0;   // Sanity check

	const char* s = op;
	while( *s ) {
		if( isspace( (unsigned char) *s ) ) {
			// Special exceptions for SIMILAR TO, IS DISTINCT FROM,
			// and IS NOT DISTINCT FROM.
			if( !strcasecmp( op, "similar to" ) )
				return 1;
			else if( !strcasecmp( op, "is distinct from" ) )
				return 1;
			else if( !strcasecmp( op, "is not distinct from" ) )
				return 1;
			else
				return 0;
		}
		else if( ';' == *s )
			return 0;
		++s;
	}
	return 1;
}

/**
	@name Query Frame Management

	The following machinery supports a stack of query frames for use by SELECT().

	A query frame caches information about one level of a SELECT query.  When we enter
	a subquery, we push another query frame onto the stack, and pop it off when we leave.

	The query frame stores information about the core class, and about any joined classes
	in the FROM clause.

	The main purpose is to map table aliases to classes and tables, so that a query can
	join to the same table more than once.  A secondary goal is to reduce the number of
	lookups in the IDL by caching the results.
*/
/*@{*/

#define STATIC_CLASS_INFO_COUNT 3

static ClassInfo static_class_info[ STATIC_CLASS_INFO_COUNT ];

/**
	@brief Allocate a ClassInfo as raw memory.
	@return Pointer to the newly allocated ClassInfo.

	Except for the in_use flag, which is used only by the allocation and deallocation
	logic, we don't initialize the ClassInfo here.
*/
static ClassInfo* allocate_class_info( void ) {
	// In order to reduce the number of mallocs and frees, we return a static
	// instance of ClassInfo, if we can find one that we're not already using.
	// We rely on the fact that the compiler will implicitly initialize the
	// static instances so that in_use == 0.

	int i;
	for( i = 0; i < STATIC_CLASS_INFO_COUNT; ++i ) {
		if( ! static_class_info[ i ].in_use ) {
			static_class_info[ i ].in_use = 1;
			return static_class_info + i;
		}
	}

	// The static ones are all in use.  Malloc one.

	return safe_malloc( sizeof( ClassInfo ) );
}

/**
	@brief Free any malloc'd memory owned by a ClassInfo, returning it to a pristine state.
	@param info Pointer to the ClassInfo to be cleared.
*/
static void clear_class_info( ClassInfo* info ) {
	// Sanity check
	if( ! info )
		return;

	// Free any malloc'd strings

	if( info->alias != info->alias_store )
		free( info->alias );

	if( info->class_name != info->class_name_store )
		free( info->class_name );

	free( info->source_def );

	info->alias = info->class_name = info->source_def = NULL;
	info->next = NULL;
}

/**
	@brief Free a ClassInfo and everything it owns.
	@param info Pointer to the ClassInfo to be freed.
*/
static void free_class_info( ClassInfo* info ) {
	// Sanity check
	if( ! info )
		return;

	clear_class_info( info );

	// If it's one of the static instances, just mark it as not in use

	int i;
	for( i = 0; i < STATIC_CLASS_INFO_COUNT; ++i ) {
		if( info == static_class_info + i ) {
			static_class_info[ i ].in_use = 0;
			return;
		}
	}

	// Otherwise it must have been malloc'd, so free it

	free( info );
}

/**
	@brief Populate an already-allocated ClassInfo.
	@param info Pointer to the ClassInfo to be populated.
	@param alias Alias for the class.  If it is NULL, or an empty string, use the class
	name for an alias.
	@param class Name of the class.
	@return Zero if successful, or 1 if not.

	Populate the ClassInfo with copies of the alias and class name, and with pointers to
	the relevant portions of the IDL for the specified class.
*/
static int build_class_info( ClassInfo* info, const char* alias, const char* class ) {
	// Sanity checks
	if( ! info ){
		osrfLogError( OSRF_LOG_MARK,
					  "%s ERROR: No ClassInfo available to populate", modulename );
		info->alias = info->class_name = info->source_def = NULL;
		info->class_def = info->fields = info->links = NULL;
		return 1;
	}

	if( ! class ) {
		osrfLogError( OSRF_LOG_MARK,
					  "%s ERROR: No class name provided for lookup", modulename );
		info->alias = info->class_name = info->source_def = NULL;
		info->class_def = info->fields = info->links = NULL;
		return 1;
	}

	// Alias defaults to class name if not supplied
	if( ! alias || ! alias[ 0 ] )
		alias = class;

	// Look up class info in the IDL
	osrfHash* class_def = osrfHashGet( oilsIDL(), class );
	if( ! class_def ) {
		osrfLogError( OSRF_LOG_MARK,
					  "%s ERROR: Class %s not defined in IDL", modulename, class );
		info->alias = info->class_name = info->source_def = NULL;
		info->class_def = info->fields = info->links = NULL;
		return 1;
	} else if( str_is_true( osrfHashGet( class_def, "virtual" ) ) ) {
		osrfLogError( OSRF_LOG_MARK,
					  "%s ERROR: Class %s is defined as virtual", modulename, class );
		info->alias = info->class_name = info->source_def = NULL;
		info->class_def = info->fields = info->links = NULL;
		return 1;
	}

	osrfHash* links = osrfHashGet( class_def, "links" );
	if( ! links ) {
		osrfLogError( OSRF_LOG_MARK,
					  "%s ERROR: No links defined in IDL for class %s", modulename, class );
		info->alias = info->class_name = info->source_def = NULL;
		info->class_def = info->fields = info->links = NULL;
		return 1;
	}

	osrfHash* fields = osrfHashGet( class_def, "fields" );
	if( ! fields ) {
		osrfLogError( OSRF_LOG_MARK,
					  "%s ERROR: No fields defined in IDL for class %s", modulename, class );
		info->alias = info->class_name = info->source_def = NULL;
		info->class_def = info->fields = info->links = NULL;
		return 1;
	}

	char* source_def = oilsGetRelation( class_def );
	if( ! source_def )
		return 1;

	// We got everything we need, so populate the ClassInfo
	if( strlen( alias ) > ALIAS_STORE_SIZE )
		info->alias = strdup( alias );
	else {
		strcpy( info->alias_store, alias );
		info->alias = info->alias_store;
	}

	if( strlen( class ) > CLASS_NAME_STORE_SIZE )
		info->class_name = strdup( class );
	else {
		strcpy( info->class_name_store, class );
		info->class_name = info->class_name_store;
	}

	info->source_def = source_def;

	info->class_def = class_def;
	info->links     = links;
	info->fields    = fields;

	return 0;
}

#define STATIC_FRAME_COUNT 3

static QueryFrame static_frame[ STATIC_FRAME_COUNT ];

/**
	@brief Allocate a QueryFrame as raw memory.
	@return Pointer to the newly allocated QueryFrame.

	Except for the in_use flag, which is used only by the allocation and deallocation
	logic, we don't initialize the QueryFrame here.
*/
static QueryFrame* allocate_frame( void ) {
	// In order to reduce the number of mallocs and frees, we return a static
	// instance of QueryFrame, if we can find one that we're not already using.
	// We rely on the fact that the compiler will implicitly initialize the
	// static instances so that in_use == 0.

	int i;
	for( i = 0; i < STATIC_FRAME_COUNT; ++i ) {
		if( ! static_frame[ i ].in_use ) {
			static_frame[ i ].in_use = 1;
			return static_frame + i;
		}
	}

	// The static ones are all in use.  Malloc one.

	return safe_malloc( sizeof( QueryFrame ) );
}

/**
	@brief Free a QueryFrame, and all the memory it owns.
	@param frame Pointer to the QueryFrame to be freed.
*/
static void free_query_frame( QueryFrame* frame ) {
	// Sanity check
	if( ! frame )
		return;

	clear_class_info( &frame->core );

	// Free the join list
	ClassInfo* temp;
	ClassInfo* info = frame->join_list;
	while( info ) {
		temp = info->next;
		free_class_info( info );
		info = temp;
	}

	frame->join_list = NULL;
	frame->next = NULL;

	// If the frame is a static instance, just mark it as unused
	int i;
	for( i = 0; i < STATIC_FRAME_COUNT; ++i ) {
		if( frame == static_frame + i ) {
			static_frame[ i ].in_use = 0;
			return;
		}
	}

	// Otherwise it must have been malloc'd, so free it

	free( frame );
}

/**
	@brief Search a given QueryFrame for a specified alias.
	@param frame Pointer to the QueryFrame to be searched.
	@param target The alias for which to search.
	@return Pointer to the ClassInfo for the specified alias, if found; otherwise NULL.
*/
static ClassInfo* search_alias_in_frame( QueryFrame* frame, const char* target ) {
	if( ! frame || ! target ) {
		return NULL;
	}

	ClassInfo* found_class = NULL;

	if( !strcmp( target, frame->core.alias ) )
		return &(frame->core);
	else {
		ClassInfo* curr_class = frame->join_list;
		while( curr_class ) {
			if( strcmp( target, curr_class->alias ) )
				curr_class = curr_class->next;
			else {
				found_class = curr_class;
				break;
			}
		}
	}

	return found_class;
}

/**
	@brief Push a new (blank) QueryFrame onto the stack.
*/
static void push_query_frame( void ) {
	QueryFrame* frame = allocate_frame();
	frame->join_list = NULL;
	frame->next = curr_query;

	// Initialize the ClassInfo for the core class
	ClassInfo* core = &frame->core;
	core->alias = core->class_name = core->source_def = NULL;
	core->class_def = core->fields = core->links = NULL;

	curr_query = frame;
}

/**
	@brief Pop a QueryFrame off the stack and destroy it.
*/
static void pop_query_frame( void ) {
	// Sanity check
	if( ! curr_query )
		return;

	QueryFrame* popped = curr_query;
	curr_query = popped->next;

	free_query_frame( popped );
}

/**
	@brief Populate the ClassInfo for the core class.
	@param alias Alias for the core class.  If it is NULL or an empty string, we use the
	class name as an alias.
	@param class_name Name of the core class.
	@return Zero if successful, or 1 if not.

	Populate the ClassInfo of the core class with copies of the alias and class name, and
	with pointers to the relevant portions of the IDL for the core class.
*/
static int add_query_core( const char* alias, const char* class_name ) {

	// Sanity checks
	if( ! curr_query ) {
		osrfLogError( OSRF_LOG_MARK,
					  "%s ERROR: No QueryFrame available for class %s", modulename, class_name );
		return 1;
	} else if( curr_query->core.alias ) {
		osrfLogError( OSRF_LOG_MARK,
					  "%s ERROR: Core class %s already populated as %s",
					  modulename, curr_query->core.class_name, curr_query->core.alias );
		return 1;
	}

	build_class_info( &curr_query->core, alias, class_name );
	if( curr_query->core.alias )
		return 0;
	else {
		osrfLogError( OSRF_LOG_MARK,
					  "%s ERROR: Unable to look up core class %s", modulename, class_name );
		return 1;
	}
}

/**
	@brief Search the current QueryFrame for a specified alias.
	@param target The alias for which to search.
	@return A pointer to the corresponding ClassInfo, if found; otherwise NULL.
*/
static inline ClassInfo* search_alias( const char* target ) {
	return search_alias_in_frame( curr_query, target );
}

/**
	@brief Search all levels of query for a specified alias, starting with the current query.
	@param target The alias for which to search.
	@return A pointer to the corresponding ClassInfo, if found; otherwise NULL.
*/
static ClassInfo* search_all_alias( const char* target ) {
	ClassInfo* found_class = NULL;
	QueryFrame* curr_frame = curr_query;

	while( curr_frame ) {
		if(( found_class = search_alias_in_frame( curr_frame, target ) ))
			break;
		else
			curr_frame = curr_frame->next;
	}

	return found_class;
}

/**
	@brief Add a class to the list of classes joined to the current query.
	@param alias Alias of the class to be added.  If it is NULL or an empty string, we use
	the class name as an alias.
	@param classname The name of the class to be added.
	@return A pointer to the ClassInfo for the added class, if successful; otherwise NULL.
*/
static ClassInfo* add_joined_class( const char* alias, const char* classname ) {

	if( ! classname || ! *classname ) {    // sanity check
		osrfLogError( OSRF_LOG_MARK, "Can't join a class with no class name" );
		return NULL;
	}

	if( ! alias )
		alias = classname;

	const ClassInfo* conflict = search_alias( alias );
	if( conflict ) {
		osrfLogError( OSRF_LOG_MARK,
					  "%s ERROR: Table alias \"%s\" conflicts with class \"%s\"",
					  modulename, alias, conflict->class_name );
		return NULL;
	}

	ClassInfo* info = allocate_class_info();

	if( build_class_info( info, alias, classname ) ) {
		free_class_info( info );
		return NULL;
	}

	// Add the new ClassInfo to the join list of the current QueryFrame
	info->next = curr_query->join_list;
	curr_query->join_list = info;

	return info;
}

/**
	@brief Destroy all nodes on the query stack.
*/
static void clear_query_stack( void ) {
	while( curr_query )
		pop_query_frame();
}

/**
	@brief Implement the set_audit_info method.
	@param ctx Pointer to the method context.
	@return Zero if successful, or -1 if not.

	Issue a SAVEPOINT to the database server.

	Method parameters:
	- authkey
	- user id (int)
	- workstation id (int)

	If user id is not provided the authkey will be used.
	For PCRUD the authkey is always used, even if a user is provided.
*/
int setAuditInfo( osrfMethodContext* ctx ) {
	if(osrfMethodVerifyContext( ctx )) {
		osrfLogError( OSRF_LOG_MARK,  "Invalid method context" );
		return -1;
	}

	// Get the user id from the parameters
	const char* user_id = jsonObjectGetString( jsonObjectGetIndex(ctx->params, 1) );

	if( enforce_pcrud || !user_id ) {
		timeout_needs_resetting = 1;
		const jsonObject* user = verifyUserPCRUD( ctx );
		if( !user )
			return -1;
		osrfAppRespondComplete( ctx, NULL );
		return 0;
	}

	// Not PCRUD and have a user_id?
	int result = writeAuditInfo( ctx, user_id, jsonObjectGetString( jsonObjectGetIndex(ctx->params, 2) ) );
	osrfAppRespondComplete( ctx, NULL );
	return result;
}

/**
	@brief Save a audit info
	@param ctx Pointer to the method context.
	@param user_id User ID to write as a string
	@param ws_id Workstation ID to write as a string
*/
int writeAuditInfo( osrfMethodContext* ctx, const char* user_id, const char* ws_id) {
	if( ctx && ctx->session ) {
		osrfAppSession* session = ctx->session;

		osrfHash* cache = session->userData;

		// If the session doesn't already have a hash, create one.  Make sure
		// that the application session frees the hash when it terminates.
		if( NULL == cache ) {
			session->userData = cache = osrfNewHash();
			osrfHashSetCallback( cache, &sessionDataFree );
			ctx->session->userDataFree = &userDataFree;
		}

		dbi_result result = dbi_conn_queryf( writehandle, "SELECT auditor.set_audit_info( %s, %s );", user_id, ws_id ? ws_id : "NULL" );
		if( !result ) {
			osrfLogWarning( OSRF_LOG_MARK, "BAD RESULT" );
			const char* msg;
			int errnum = dbi_conn_error( writehandle, &msg );
			osrfLogError(
				OSRF_LOG_MARK,
				"%s: Error setting auditor information: %d %s",
				modulename,
				errnum,
				msg ? msg : "(No description available)"
			);
			osrfAppSessionStatus( ctx->session, OSRF_STATUS_INTERNALSERVERERROR,
				"osrfMethodException", ctx->request, "Error setting auditor info" );
			if( !oilsIsDBConnected( writehandle ))
				osrfAppSessionPanic( ctx->session );
			return -1;
		} else {
			dbi_result_free( result );
		}
	}
	return 0;
}

/*@}*/
