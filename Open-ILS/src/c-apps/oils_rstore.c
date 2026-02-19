/**
	@file oils_rstore.c
	@brief As a server, perform database operations at the request of clients.
*/

#include <stdlib.h>
#include <string.h>
#include <ctype.h>
#include <dbi/dbi.h>
#include "opensrf/utils.h"
#include "opensrf/log.h"
#include "opensrf/osrf_application.h"
#include "openils/oils_utils.h"
#include "openils/oils_sql.h"

static dbi_inst instance;
static dbi_conn writehandle; /* our MASTER db connection */
static dbi_conn dbhandle; /* our CURRENT db connection */

static const int enforce_pcrud = 0;     // Boolean
static const char modulename[] = "open-ils.reporter-store";

/**
	@brief Disconnect from the database.

	This function is called when the server drone is about to terminate.
*/
void osrfAppChildExit( void ) {
	osrfLogDebug(OSRF_LOG_MARK, "Child is exiting, disconnecting from database...");

	int same = 0;
	if (writehandle == dbhandle)
		same = 1;

	if (writehandle) {
		dbi_conn_query(writehandle, "ROLLBACK;");
		dbi_conn_close(writehandle);
		writehandle = NULL;
	}
	if (dbhandle && !same)
		dbi_conn_close(dbhandle);

	// XXX add cleanup of readHandles whenever that gets used

	return;
}

/**
	@brief Initialize the application.
	@return Zero if successful, or non-zero if not.

	Load the IDL file into an internal data structure for future reference.  Each non-virtual
	class in the IDL corresponds to a table or view in the database, or to a subquery defined
	in the IDL.  Ignore all virtual tables and virtual fields.

	Register a number of methods, some of them general-purpose and others specific for
	particular classes.

	The name of the application is given by the MODULENAME macro, whose value depends on
	conditional compilation.  The method names also incorporate MODULENAME, followed by a
	dot, as a prefix.

	The general-purpose methods are as follows (minus their MODULENAME prefixes):

	- json_query
	- transaction.begin
	- transaction.commit
	- transaction.rollback
	- savepoint.set
	- savepoint.release
	- savepoint.rollback
	- set_audit_info

	For each non-virtual class, create up to eight class-specific methods:

	- create    (not for readonly classes)
	- retrieve
	- update    (not for readonly classes)
	- delete    (not for readonly classes
	- search    (atomic and non-atomic versions)
	- id_list   (atomic and non-atomic versions)

	The full method names follow the pattern "MODULENAME.direct.XXX.method_type", where XXX
	is the fieldmapper name from the IDL, with every run of one or more consecutive colons
	replaced by a period.  In addition, the names of atomic methods have a suffix of ".atomic".

	This function is called when the registering the application, and is executed by the
	listener before spawning the drones.
*/
int osrfAppInitialize( void ) {

	osrfLogInfo(OSRF_LOG_MARK, "Initializing the RStore Server...");
	osrfLogInfo(OSRF_LOG_MARK, "Finding XML file...");

	if ( !oilsIDLInit( osrf_settings_host_value( "/IDL" )))
		return 1; /* return non-zero to indicate error */

	if ( !oilsInitializeDbiInstance( &instance ) )
		return 1;

	// Open the database temporarily.  Look up the datatypes of all
	// the non-virtual fields and record them with the IDL data.
	dbi_conn handle = oilsConnectDB( modulename, &instance );
	if( !handle )
		return -1;
	else if( oilsExtendIDL( handle )) {
		osrfLogError( OSRF_LOG_MARK, "Error extending the IDL" );
		return -1;
	}
	dbi_conn_close( handle );

	// Get the maximum flesh depth from the settings
	char* md = osrf_settings_host_value(
		"/apps/%s/app_settings/max_query_recursion", modulename );
	int max_flesh_depth = 100;
	if( md )
		max_flesh_depth = atoi( md );
	if( max_flesh_depth < 0 )
		max_flesh_depth = 1;
	else if( max_flesh_depth > 1000 )
		max_flesh_depth = 1000;
	free( md );

	oilsSetSQLOptions( modulename, enforce_pcrud, max_flesh_depth );

	// Now register all the methods
	growing_buffer* method_name = osrf_buffer_init(64);

	// Generic search thingy
	osrf_buffer_add( method_name, modulename );
	osrf_buffer_add( method_name, ".json_query" );
	osrfAppRegisterMethod( modulename, OSRF_BUFFER_C_STR( method_name ),
		"doJSONSearch", "", 1, OSRF_METHOD_STREAMING );

	// first we register all the transaction and savepoint methods
	osrf_buffer_reset(method_name);
	OSRF_BUFFER_ADD(method_name, modulename );
	OSRF_BUFFER_ADD(method_name, ".transaction.begin");
	osrfAppRegisterMethod( modulename, OSRF_BUFFER_C_STR( method_name ),
			"beginTransaction", "", 0, 0 );

	osrf_buffer_reset(method_name);
	OSRF_BUFFER_ADD(method_name, modulename );
	OSRF_BUFFER_ADD(method_name, ".transaction.commit");
	osrfAppRegisterMethod( modulename, OSRF_BUFFER_C_STR(method_name),
			"commitTransaction", "", 0, 0 );

	osrf_buffer_reset(method_name);
	OSRF_BUFFER_ADD(method_name, modulename );
	OSRF_BUFFER_ADD(method_name, ".transaction.rollback");
	osrfAppRegisterMethod( modulename, OSRF_BUFFER_C_STR(method_name),
			"rollbackTransaction", "", 0, 0 );

	osrf_buffer_reset(method_name);
	OSRF_BUFFER_ADD(method_name, modulename );
	OSRF_BUFFER_ADD(method_name, ".savepoint.set");
	osrfAppRegisterMethod( modulename, OSRF_BUFFER_C_STR(method_name),
			"setSavepoint", "", 1, 0 );

	osrf_buffer_reset(method_name);
	OSRF_BUFFER_ADD(method_name, modulename );
	OSRF_BUFFER_ADD(method_name, ".savepoint.release");
	osrfAppRegisterMethod( modulename, OSRF_BUFFER_C_STR(method_name),
			"releaseSavepoint", "", 1, 0 );

	osrf_buffer_reset(method_name);
	OSRF_BUFFER_ADD(method_name, modulename );
	OSRF_BUFFER_ADD(method_name, ".savepoint.rollback");
	osrfAppRegisterMethod( modulename, OSRF_BUFFER_C_STR(method_name),
			"rollbackSavepoint", "", 1, 0 );

	osrf_buffer_reset(method_name);
	OSRF_BUFFER_ADD(method_name, modulename );
	OSRF_BUFFER_ADD(method_name, ".set_audit_info");
	osrfAppRegisterMethod( modulename, OSRF_BUFFER_C_STR(method_name),
			"setAuditInfo", "", 3, 0 );

	static const char* global_method[] = {
		"create",
		"retrieve",
		"update",
		"delete",
		"search",
		"id_list"
	};
	const int global_method_count
		= sizeof( global_method ) / sizeof ( global_method[0] );

	unsigned long class_count = osrfHashGetCount( oilsIDL() );
	osrfLogDebug(OSRF_LOG_MARK, "%lu classes loaded", class_count );
	osrfLogDebug(OSRF_LOG_MARK,
		"At most %lu methods will be generated",
		(unsigned long) (class_count * global_method_count) );

	osrfHashIterator* class_itr = osrfNewHashIterator( oilsIDL() );
	osrfHash* idlClass = NULL;

	// For each class in the IDL...
	while( (idlClass = osrfHashIteratorNext( class_itr ) ) ) {

		const char* classname = osrfHashIteratorKey( class_itr );
		osrfLogInfo(OSRF_LOG_MARK, "Generating class methods for %s", classname);

		if (!osrfStringArrayContains( osrfHashGet(idlClass, "controller"), modulename )) {
			osrfLogInfo(OSRF_LOG_MARK, "%s is not listed as a controller for %s, moving on",
					modulename, classname);
			continue;
		}

		if ( str_is_true( osrfHashGet(idlClass, "virtual") ) ) {
			osrfLogDebug(OSRF_LOG_MARK, "Class %s is virtual, skipping", classname );
			continue;
		}

		// Look up some other attributes of the current class
		const char* idlClass_fieldmapper = osrfHashGet(idlClass, "fieldmapper");
		if( !idlClass_fieldmapper ) {
			osrfLogDebug( OSRF_LOG_MARK, "Skipping class \"%s\"; no fieldmapper in IDL",
					classname );
			continue;
		}

		const char* readonly = osrfHashGet(idlClass, "readonly");

		int i;
		for( i = 0; i < global_method_count; ++i ) {  // for each global method
			const char* method_type = global_method[ i ];
			osrfLogDebug(OSRF_LOG_MARK,
				"Using files to build %s class methods for %s", method_type, classname);

			// No create, update, or delete methods for a readonly class
			if ( str_is_true( readonly )
				&& ( *method_type == 'c' || *method_type == 'u' || *method_type == 'd') )
				continue;

			osrf_buffer_reset( method_name );

			// Build the method name: MODULENAME.MODULENAME.direct.XXX.method_type
			// where XXX is the fieldmapper name from the IDL, with every run of
			// one or more consecutive colons replaced by a period.
			char* st_tmp = NULL;
			char* part = NULL;
			char* _fm = strdup( idlClass_fieldmapper );
			part = strtok_r(_fm, ":", &st_tmp);

			osrf_buffer_fadd(method_name, "%s.direct.%s", modulename, part);

			while ((part = strtok_r(NULL, ":", &st_tmp))) {
				OSRF_BUFFER_ADD_CHAR(method_name, '.');
				OSRF_BUFFER_ADD(method_name, part);
			}
			OSRF_BUFFER_ADD_CHAR(method_name, '.');
			OSRF_BUFFER_ADD(method_name, method_type);
			free(_fm);

			// For an id_list or search method we specify the OSRF_METHOD_STREAMING option.
			// The consequence is that we implicitly create an atomic method in addition to
			// the usual non-atomic method.
			int flags = 0;
			if (*method_type == 'i' || *method_type == 's') {  // id_list or search
				flags = flags | OSRF_METHOD_STREAMING;
			}

			osrfHash* method_meta = osrfNewHash();
			osrfHashSet( method_meta, idlClass, "class");
			osrfHashSet( method_meta, osrf_buffer_data( method_name ), "methodname" );
			osrfHashSet( method_meta, strdup(method_type), "methodtype" );

			// Register the method, with a pointer to an osrfHash to tell the method
			// its name, type, and class.
			osrfAppRegisterExtendedMethod(
				modulename,
				OSRF_BUFFER_C_STR( method_name ),
				"dispatchCRUDMethod",
				"",
				1,
				flags,
				(void*)method_meta
			);

		} // end for each global method
		free( (void *)readonly );
	} // end for each class in IDL

	osrf_buffer_free( method_name );
	osrfHashIteratorFree( class_itr );

	return 0;
}

/**
	@brief Initialize a server drone.
	@return Zero if successful, -1 if not.

	Connect to the database.

	This function is called by a server drone shortly after it is spawned by the listener.
*/
int osrfAppChildInit( void ) {

	writehandle = oilsConnectDB( modulename, &instance );
	if( !writehandle )
		return -1;

	oilsSetDBConnection( writehandle );

	return 0;
}

/**
	@brief Implement the class-specific methods.
	@param ctx Pointer to the method context.
	@return Zero if successful, or -1 if not.

	Branch on the method type: create, retrieve, update, delete, search, or id_list.

	The method parameters and the type of value returned to the client depend on the method
	type.
*/
int dispatchCRUDMethod( osrfMethodContext* ctx ) {

	// Get the method type, then can branch on it
	osrfHash* method_meta = (osrfHash*) ctx->method->userData;
	const char* methodtype = osrfHashGet( method_meta, "methodtype" );

	if( !strcmp( methodtype, "create" ))
		return doCreate( ctx );
	else if( !strcmp(methodtype, "retrieve" ))
		return doRetrieve( ctx );
	else if( !strcmp(methodtype, "update" ))
		return doUpdate( ctx );
	else if( !strcmp(methodtype, "delete" ))
		return doDelete( ctx );
	else if( !strcmp(methodtype, "search" ))
		return doSearch( ctx );
	else if( !strcmp(methodtype, "id_list" ))
		return doIdList( ctx );
	else {
		osrfAppRespondComplete( ctx, NULL );      // should be unreachable...
		return 0;
	}
}
