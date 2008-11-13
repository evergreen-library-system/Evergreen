#include "opensrf/osrf_application.h"
#include "opensrf/osrf_settings.h"
#include "opensrf/osrf_message.h"
#include "opensrf/utils.h"
#include "opensrf/osrf_json.h"
#include "opensrf/log.h"
#include "openils/oils_idl.h"
#include <dbi/dbi.h>

#include <time.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#ifdef RSTORE
#  define MODULENAME "open-ils.reporter-store"
#else
#  define MODULENAME "open-ils.cstore"
#endif

#define SUBSELECT	4
#define DISABLE_I18N	2
#define SELECT_DISTINCT	1
#define AND_OP_JOIN     0
#define OR_OP_JOIN      1

int osrfAppChildInit();
int osrfAppInitialize();
void osrfAppChildExit();

static int verifyObjectClass ( osrfMethodContext*, const jsonObject* );

int beginTransaction ( osrfMethodContext* );
int commitTransaction ( osrfMethodContext* );
int rollbackTransaction ( osrfMethodContext* );

int setSavepoint ( osrfMethodContext* );
int releaseSavepoint ( osrfMethodContext* );
int rollbackSavepoint ( osrfMethodContext* );

int doJSONSearch ( osrfMethodContext* );

int dispatchCRUDMethod ( osrfMethodContext* );
static jsonObject* doCreate ( osrfMethodContext*, int* );
static jsonObject* doRetrieve ( osrfMethodContext*, int* );
static jsonObject* doUpdate ( osrfMethodContext*, int* );
static jsonObject* doDelete ( osrfMethodContext*, int* );
static jsonObject* doFieldmapperSearch ( osrfMethodContext*, osrfHash*,
		const jsonObject*, int* );
static jsonObject* oilsMakeFieldmapperFromResult( dbi_result, osrfHash* );
static jsonObject* oilsMakeJSONFromResult( dbi_result );

static char* searchWriteSimplePredicate ( const char*, osrfHash*,
	const char*, const char*, const char* );
static char* searchSimplePredicate ( const char*, const char*, osrfHash*, const jsonObject* );
static char* searchFunctionPredicate ( const char*, osrfHash*, const jsonObject*, const char* );
static char* searchFieldTransform ( const char*, osrfHash*, const jsonObject*);
static char* searchFieldTransformPredicate ( const char*, osrfHash*, jsonObject*, const char* );
static char* searchBETWEENPredicate ( const char*, osrfHash*, jsonObject* );
static char* searchINPredicate ( const char*, osrfHash*, const jsonObject*, const char* );
static char* searchPredicate ( const char*, osrfHash*, jsonObject* );
static char* searchJOIN ( const jsonObject*, osrfHash* );
static char* searchWHERE ( const jsonObject*, osrfHash*, int, osrfMethodContext* );
static char* buildSELECT ( jsonObject*, jsonObject*, osrfHash*, osrfMethodContext* );

static char* SELECT ( osrfMethodContext*, jsonObject*, jsonObject*, jsonObject*, jsonObject*, jsonObject*, jsonObject*, jsonObject*, int );

void userDataFree( void* );
static void sessionDataFree( char*, void* );
static char* getSourceDefinition( osrfHash* );

static dbi_conn writehandle; /* our MASTER db connection */
static dbi_conn dbhandle; /* our CURRENT db connection */
//static osrfHash * readHandles;
static jsonObject* jsonNULL = NULL; // 
static int max_flesh_depth = 100;

/* called when this process is about to exit */
void osrfAppChildExit() {
	osrfLogDebug(OSRF_LOG_MARK, "Child is exiting, disconnecting from database...");

    int same = 0;
    if (writehandle == dbhandle) same = 1;
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

int osrfAppInitialize() {
	growing_buffer* method_name;

	osrfLogInfo(OSRF_LOG_MARK, "Initializing the CStore Server...");
	osrfLogInfo(OSRF_LOG_MARK, "Finding XML file...");

	if (!oilsIDLInit( osrf_settings_host_value("/IDL") )) return 1; /* return non-zero to indicate error */

	// Generic search thingy
	method_name =  buffer_init(64);
	buffer_fadd(method_name, "%s.json_query", MODULENAME);
	char* method_str = buffer_data(method_name);
	osrfAppRegisterMethod( MODULENAME, method_str, "doJSONSearch", "", 1, OSRF_METHOD_STREAMING );
	free(method_str);

	// first we register all the transaction and savepoint methods
	buffer_reset(method_name);
	buffer_fadd(method_name, "%s.transaction.begin", MODULENAME);
	method_str = buffer_data(method_name);
	osrfAppRegisterMethod( MODULENAME, method_str, "beginTransaction", "", 0, 0 );
	free(method_str);

	buffer_reset(method_name);
	buffer_fadd(method_name, "%s.transaction.commit", MODULENAME);
	method_str = buffer_data(method_name);
	osrfAppRegisterMethod( MODULENAME, method_str, "commitTransaction", "", 0, 0 );
	free(method_str);

	buffer_reset(method_name);
	buffer_fadd(method_name, "%s.transaction.rollback", MODULENAME);
	method_str = buffer_data(method_name);
	osrfAppRegisterMethod( MODULENAME, method_str, "rollbackTransaction", "", 0, 0 );
	free(method_str);

	buffer_reset(method_name);
	buffer_fadd(method_name, "%s.savepoint.set", MODULENAME);
	method_str = buffer_data(method_name);
	osrfAppRegisterMethod( MODULENAME, method_str, "setSavepoint", "", 1, 0 );
	free(method_str);

	buffer_reset(method_name);
	buffer_fadd(method_name, "%s.savepoint.release", MODULENAME);
	method_str = buffer_data(method_name);
	osrfAppRegisterMethod( MODULENAME, method_str, "releaseSavepoint", "", 1, 0 );
	free(method_str);

	buffer_reset(method_name);
	buffer_fadd(method_name, "%s.savepoint.rollback", MODULENAME);
	method_str = buffer_data(method_name);
	osrfAppRegisterMethod( MODULENAME, method_str, "rollbackSavepoint", "", 1, 0 );
	free(method_str);

	buffer_free(method_name);

	osrfStringArray* global_methods = osrfNewStringArray(6);

	osrfStringArrayAdd( global_methods, "create" );
	osrfStringArrayAdd( global_methods, "retrieve" );
	osrfStringArrayAdd( global_methods, "update" );
	osrfStringArrayAdd( global_methods, "delete" );
	osrfStringArrayAdd( global_methods, "search" );
	osrfStringArrayAdd( global_methods, "id_list" );

	int c_index = 0; 
	char* classname;
	osrfStringArray* classes = osrfHashKeys( oilsIDL() );
	osrfLogDebug(OSRF_LOG_MARK, "%d classes loaded", classes->size );
	osrfLogDebug(OSRF_LOG_MARK, "At least %d methods will be generated", classes->size * global_methods->size);
	
	while ( (classname = osrfStringArrayGetString(classes, c_index++)) ) {
		osrfLogInfo(OSRF_LOG_MARK, "Generating class methods for %s", classname);
		
		osrfHash* idlClass = osrfHashGet(oilsIDL(), classname);

		if (!osrfStringArrayContains( osrfHashGet(idlClass, "controller"), MODULENAME )) {
			osrfLogInfo(OSRF_LOG_MARK, "%s is not listed as a controller for %s, moving on", MODULENAME, classname);
			continue;
		}

		char* virt = osrfHashGet(idlClass, "virtual");
		if (virt && !strcmp( virt, "true")) {
			osrfLogDebug(OSRF_LOG_MARK, "Class %s is virtual, skipping", classname );
			continue;
		}

		int i = 0; 
		char* method_type;
		char* st_tmp = NULL;
		char* _fm;
		char* part;
		osrfHash* method_meta;
		while ( (method_type = osrfStringArrayGetString(global_methods, i++)) ) {
			osrfLogDebug(OSRF_LOG_MARK, "Using files to build %s class methods for %s", method_type, classname);

			if (!osrfHashGet(idlClass, "fieldmapper")) continue;

			char* readonly = osrfHashGet(idlClass, "readonly");
			if (	readonly &&
				!strncasecmp( "true", readonly, 4) &&
				( *method_type == 'c' || *method_type == 'u' || *method_type == 'd')
			) continue;

			method_meta = osrfNewHash();
			osrfHashSet(method_meta, idlClass, "class");

			_fm = strdup( (char*)osrfHashGet(idlClass, "fieldmapper") );
			part = strtok_r(_fm, ":", &st_tmp);

			growing_buffer* method_name =  buffer_init(64);
			buffer_fadd(method_name, "%s.direct.%s", MODULENAME, part);

			while ((part = strtok_r(NULL, ":", &st_tmp))) {
				buffer_fadd(method_name, ".%s", part);
			}
			buffer_fadd(method_name, ".%s", method_type);


			char* method = buffer_release(method_name);
			free(_fm);

			osrfHashSet( method_meta, method, "methodname" );
			osrfHashSet( method_meta, strdup(method_type), "methodtype" );

			int flags = 0;
			if (!(strcmp( method_type, "search" )) || !(strcmp( method_type, "id_list" ))) {
				flags = flags | OSRF_METHOD_STREAMING;
			}

			osrfAppRegisterExtendedMethod(
				MODULENAME,
				method,
				"dispatchCRUDMethod",
				"",
				1,
				flags,
				(void*)method_meta
			);

			free(method);
		}
	}

	osrfStringArrayFree( global_methods );
	return 0;
}

static char* getSourceDefinition( osrfHash* class ) {

	char* tabledef = osrfHashGet(class, "tablename");

	if (!tabledef) {
		growing_buffer* tablebuf = buffer_init(128);
		tabledef = osrfHashGet(class, "source_definition");
		if( !tabledef )
			tabledef = "(null)";
		buffer_fadd( tablebuf, "(%s)", tabledef );
		tabledef = buffer_release(tablebuf);
	} else {
		tabledef = strdup(tabledef);
	}

	return tabledef;
}

/**
 * Connects to the database 
 */
int osrfAppChildInit() {

	osrfLogDebug(OSRF_LOG_MARK, "Attempting to initialize libdbi...");
	dbi_initialize(NULL);
	osrfLogDebug(OSRF_LOG_MARK, "... libdbi initialized.");

	char* driver	= osrf_settings_host_value("/apps/%s/app_settings/driver", MODULENAME);
	char* user	= osrf_settings_host_value("/apps/%s/app_settings/database/user", MODULENAME);
	char* host	= osrf_settings_host_value("/apps/%s/app_settings/database/host", MODULENAME);
	char* port	= osrf_settings_host_value("/apps/%s/app_settings/database/port", MODULENAME);
	char* db	= osrf_settings_host_value("/apps/%s/app_settings/database/db", MODULENAME);
	char* pw	= osrf_settings_host_value("/apps/%s/app_settings/database/pw", MODULENAME);
	char* md	= osrf_settings_host_value("/apps/%s/app_settings/max_query_recursion", MODULENAME);

	osrfLogDebug(OSRF_LOG_MARK, "Attempting to load the database driver [%s]...", driver);
	writehandle = dbi_conn_new(driver);

	if(!writehandle) {
		osrfLogError(OSRF_LOG_MARK, "Error loading database driver [%s]", driver);
		return -1;
	}
	osrfLogDebug(OSRF_LOG_MARK, "Database driver [%s] seems OK", driver);

	osrfLogInfo(OSRF_LOG_MARK, "%s connecting to database.  host=%s, "
		"port=%s, user=%s, pw=%s, db=%s", MODULENAME, host, port, user, pw, db );

	if(host) dbi_conn_set_option(writehandle, "host", host );
	if(port) dbi_conn_set_option_numeric( writehandle, "port", atoi(port) );
	if(user) dbi_conn_set_option(writehandle, "username", user);
	if(pw) dbi_conn_set_option(writehandle, "password", pw );
	if(db) dbi_conn_set_option(writehandle, "dbname", db );

	if(md) max_flesh_depth = atoi(md);
	if(max_flesh_depth < 0) max_flesh_depth = 1;
	if(max_flesh_depth > 1000) max_flesh_depth = 1000;

	free(user);
	free(host);
	free(port);
	free(db);
	free(pw);

	const char* err;
	if (dbi_conn_connect(writehandle) < 0) {
		sleep(1);
		if (dbi_conn_connect(writehandle) < 0) {
			dbi_conn_error(writehandle, &err);
			osrfLogError( OSRF_LOG_MARK, "Error connecting to database: %s", err);
			return -1;
		}
	}

	osrfLogInfo(OSRF_LOG_MARK, "%s successfully connected to the database", MODULENAME);

	int attr;
	unsigned short type;
	int i = 0; 
	char* classname;
	osrfStringArray* classes = osrfHashKeys( oilsIDL() );
	
	while ( (classname = osrfStringArrayGetString(classes, i++)) ) {
		osrfHash* class = osrfHashGet( oilsIDL(), classname );
		osrfHash* fields = osrfHashGet( class, "fields" );

		char* virt = osrfHashGet(class, "virtual");
		if (virt && !strcmp( virt, "true")) {
			osrfLogDebug(OSRF_LOG_MARK, "Class %s is virtual, skipping", classname );
			continue;
		}

		char* tabledef = getSourceDefinition(class);

		growing_buffer* sql_buf = buffer_init(32);
		buffer_fadd( sql_buf, "SELECT * FROM %s AS x WHERE 1=0;", tabledef );

		free(tabledef);

		char* sql = buffer_release(sql_buf);
		osrfLogDebug(OSRF_LOG_MARK, "%s Investigatory SQL = %s", MODULENAME, sql);

		dbi_result result = dbi_conn_query(writehandle, sql);
		free(sql);

		if (result) {

			int columnIndex = 1;
			const char* columnName;
			osrfHash* _f;
			while( (columnName = dbi_result_get_field_name(result, columnIndex++)) ) {

				osrfLogInternal(OSRF_LOG_MARK, "Looking for column named [%s]...", (char*)columnName);

				/* fetch the fieldmapper index */
				if( (_f = osrfHashGet(fields, (char*)columnName)) ) {

					osrfLogDebug(OSRF_LOG_MARK, "Found [%s] in IDL hash...", (char*)columnName);

					/* determine the field type and storage attributes */
					type = dbi_result_get_field_type(result, columnName);
					attr = dbi_result_get_field_attribs(result, columnName);

					switch( type ) {

						case DBI_TYPE_INTEGER :

							if ( !osrfHashGet(_f, "primitive") )
								osrfHashSet(_f,"number", "primitive");

							if( attr & DBI_INTEGER_SIZE8 ) 
								osrfHashSet(_f,"INT8", "datatype");
							else 
								osrfHashSet(_f,"INT", "datatype");
							break;

						case DBI_TYPE_DECIMAL :
							if ( !osrfHashGet(_f, "primitive") )
								osrfHashSet(_f,"number", "primitive");

							osrfHashSet(_f,"NUMERIC", "datatype");
							break;

						case DBI_TYPE_STRING :
							if ( !osrfHashGet(_f, "primitive") )
								osrfHashSet(_f,"string", "primitive");
							osrfHashSet(_f,"TEXT", "datatype");
							break;

						case DBI_TYPE_DATETIME :
							if ( !osrfHashGet(_f, "primitive") )
								osrfHashSet(_f,"string", "primitive");

							osrfHashSet(_f,"TIMESTAMP", "datatype");
							break;

						case DBI_TYPE_BINARY :
							if ( !osrfHashGet(_f, "primitive") )
								osrfHashSet(_f,"string", "primitive");

							osrfHashSet(_f,"BYTEA", "datatype");
					}

					osrfLogDebug(
						OSRF_LOG_MARK,
						"Setting [%s] to primitive [%s] and datatype [%s]...",
						(char*)columnName,
						osrfHashGet(_f, "primitive"),
						osrfHashGet(_f, "datatype")
					);
				}
			}
			dbi_result_free(result);
		} else {
			osrfLogDebug(OSRF_LOG_MARK, "No data found for class [%s]...", (char*)classname);
		}
	}

	osrfStringArrayFree(classes);

	return 0;
}

void userDataFree( void* blob ) {
	osrfHashFree( (osrfHash*)blob );
	return;
}

static void sessionDataFree( char* key, void* item ) {
	if (!(strcmp(key,"xact_id"))) {
		if (writehandle)
			dbi_conn_query(writehandle, "ROLLBACK;");
		free(item);
	}

	return;
}

int beginTransaction ( osrfMethodContext* ctx ) {
	OSRF_METHOD_VERIFY_CONTEXT(ctx);

	dbi_result result = dbi_conn_query(writehandle, "START TRANSACTION;");
	if (!result) {
		osrfLogError(OSRF_LOG_MARK, "%s: Error starting transaction", MODULENAME );
		osrfAppSessionStatus( ctx->session, OSRF_STATUS_INTERNALSERVERERROR, "osrfMethodException", ctx->request, "Error starting transaction" );
		return -1;
	} else {
		jsonObject* ret = jsonNewObject(ctx->session->session_id);
		osrfAppRespondComplete( ctx, ret );
		jsonObjectFree(ret);
		
		if (!ctx->session->userData) {
			ctx->session->userData = osrfNewHash();
			osrfHashSetCallback((osrfHash*)ctx->session->userData, &sessionDataFree);
		}

		osrfHashSet( (osrfHash*)ctx->session->userData, strdup( ctx->session->session_id ), "xact_id" );
		ctx->session->userDataFree = &userDataFree;
		
	}
	return 0;
}

int setSavepoint ( osrfMethodContext* ctx ) {
	OSRF_METHOD_VERIFY_CONTEXT(ctx);

	if (!osrfHashGet( (osrfHash*)ctx->session->userData, "xact_id" )) {
		osrfAppSessionStatus(
			ctx->session,
			OSRF_STATUS_INTERNALSERVERERROR,
			"osrfMethodException",
			ctx->request,
			"No active transaction -- required for savepoints"
		);
		return -1;
	}

	char* spName = jsonObjectToSimpleString(jsonObjectGetIndex(ctx->params, 0));

	dbi_result result = dbi_conn_queryf(writehandle, "SAVEPOINT \"%s\";", spName);
	if (!result) {
		osrfLogError(
			OSRF_LOG_MARK,
			"%s: Error creating savepoint %s in transaction %s",
			MODULENAME,
			spName,
			osrfHashGet( (osrfHash*)ctx->session->userData, "xact_id" )
		);
		osrfAppSessionStatus( ctx->session, OSRF_STATUS_INTERNALSERVERERROR, "osrfMethodException", ctx->request, "Error creating savepoint" );
		free(spName);
		return -1;
	} else {
		jsonObject* ret = jsonNewObject(spName);
		osrfAppRespondComplete( ctx, ret );
		jsonObjectFree(ret);
	}
	free(spName);
	return 0;
}

int releaseSavepoint ( osrfMethodContext* ctx ) {
	OSRF_METHOD_VERIFY_CONTEXT(ctx);

	if (!osrfHashGet( (osrfHash*)ctx->session->userData, "xact_id" )) {
		osrfAppSessionStatus(
			ctx->session,
			OSRF_STATUS_INTERNALSERVERERROR,
			"osrfMethodException",
			ctx->request,
			"No active transaction -- required for savepoints"
		);
		return -1;
	}

	char* spName = jsonObjectToSimpleString(jsonObjectGetIndex(ctx->params, 0));

	dbi_result result = dbi_conn_queryf(writehandle, "RELEASE SAVEPOINT \"%s\";", spName);
	if (!result) {
		osrfLogError(
			OSRF_LOG_MARK,
			"%s: Error releasing savepoint %s in transaction %s",
			MODULENAME,
			spName,
			osrfHashGet( (osrfHash*)ctx->session->userData, "xact_id" )
		);
		osrfAppSessionStatus( ctx->session, OSRF_STATUS_INTERNALSERVERERROR, "osrfMethodException", ctx->request, "Error releasing savepoint" );
		free(spName);
		return -1;
	} else {
		jsonObject* ret = jsonNewObject(spName);
		osrfAppRespondComplete( ctx, ret );
		jsonObjectFree(ret);
	}
	free(spName);
	return 0;
}

int rollbackSavepoint ( osrfMethodContext* ctx ) {
	OSRF_METHOD_VERIFY_CONTEXT(ctx);

	if (!osrfHashGet( (osrfHash*)ctx->session->userData, "xact_id" )) {
		osrfAppSessionStatus(
			ctx->session,
			OSRF_STATUS_INTERNALSERVERERROR,
			"osrfMethodException",
			ctx->request,
			"No active transaction -- required for savepoints"
		);
		return -1;
	}

	char* spName = jsonObjectToSimpleString(jsonObjectGetIndex(ctx->params, 0));

	dbi_result result = dbi_conn_queryf(writehandle, "ROLLBACK TO SAVEPOINT \"%s\";", spName);
	if (!result) {
		osrfLogError(
			OSRF_LOG_MARK,
			"%s: Error rolling back savepoint %s in transaction %s",
			MODULENAME,
			spName,
			osrfHashGet( (osrfHash*)ctx->session->userData, "xact_id" )
		);
		osrfAppSessionStatus( ctx->session, OSRF_STATUS_INTERNALSERVERERROR, "osrfMethodException", ctx->request, "Error rolling back savepoint" );
		free(spName);
		return -1;
	} else {
		jsonObject* ret = jsonNewObject(spName);
		osrfAppRespondComplete( ctx, ret );
		jsonObjectFree(ret);
	}
	free(spName);
	return 0;
}

int commitTransaction ( osrfMethodContext* ctx ) {
	OSRF_METHOD_VERIFY_CONTEXT(ctx);

	if (!osrfHashGet( (osrfHash*)ctx->session->userData, "xact_id" )) {
		osrfAppSessionStatus( ctx->session, OSRF_STATUS_INTERNALSERVERERROR, "osrfMethodException", ctx->request, "No active transaction to commit" );
		return -1;
	}

	dbi_result result = dbi_conn_query(writehandle, "COMMIT;");
	if (!result) {
		osrfLogError(OSRF_LOG_MARK, "%s: Error committing transaction", MODULENAME );
		osrfAppSessionStatus( ctx->session, OSRF_STATUS_INTERNALSERVERERROR, "osrfMethodException", ctx->request, "Error committing transaction" );
		return -1;
	} else {
		osrfHashRemove(ctx->session->userData, "xact_id");
		jsonObject* ret = jsonNewObject(ctx->session->session_id);
		osrfAppRespondComplete( ctx, ret );
		jsonObjectFree(ret);
	}
	return 0;
}

int rollbackTransaction ( osrfMethodContext* ctx ) {
	OSRF_METHOD_VERIFY_CONTEXT(ctx);

	if (!osrfHashGet( (osrfHash*)ctx->session->userData, "xact_id" )) {
		osrfAppSessionStatus( ctx->session, OSRF_STATUS_INTERNALSERVERERROR, "osrfMethodException", ctx->request, "No active transaction to roll back" );
		return -1;
	}

	dbi_result result = dbi_conn_query(writehandle, "ROLLBACK;");
	if (!result) {
		osrfLogError(OSRF_LOG_MARK, "%s: Error rolling back transaction", MODULENAME );
		osrfAppSessionStatus( ctx->session, OSRF_STATUS_INTERNALSERVERERROR, "osrfMethodException", ctx->request, "Error rolling back transaction" );
		return -1;
	} else {
		osrfHashRemove(ctx->session->userData, "xact_id");
		jsonObject* ret = jsonNewObject(ctx->session->session_id);
		osrfAppRespondComplete( ctx, ret );
		jsonObjectFree(ret);
	}
	return 0;
}

int dispatchCRUDMethod ( osrfMethodContext* ctx ) {
	OSRF_METHOD_VERIFY_CONTEXT(ctx);

	osrfHash* meta = (osrfHash*) ctx->method->userData;
	osrfHash* class_obj = osrfHashGet( meta, "class" );
	
	int err = 0;

	const char* methodtype = osrfHashGet(meta, "methodtype");
	jsonObject * obj = NULL;

	if (!strcmp(methodtype, "create")) {
		obj = doCreate(ctx, &err);
		osrfAppRespondComplete( ctx, obj );
	}
	else if (!strcmp(methodtype, "retrieve")) {
		obj = doRetrieve(ctx, &err);
		osrfAppRespondComplete( ctx, obj );
	}
	else if (!strcmp(methodtype, "update")) {
		obj = doUpdate(ctx, &err);
		osrfAppRespondComplete( ctx, obj );
	}
	else if (!strcmp(methodtype, "delete")) {
		obj = doDelete(ctx, &err);
		osrfAppRespondComplete( ctx, obj );
	}
	else if (!strcmp(methodtype, "search")) {

		obj = doFieldmapperSearch(ctx, class_obj, ctx->params, &err);
		if(err) return err;

		jsonObject* cur;
		jsonIterator* itr = jsonNewIterator( obj );
		while ((cur = jsonIteratorNext( itr ))) {
			osrfAppRespond( ctx, cur );
		}
		jsonIteratorFree(itr);
		osrfAppRespondComplete( ctx, NULL );

	} else if (!strcmp(methodtype, "id_list")) {

		jsonObject* _p = jsonObjectClone( ctx->params );
		if (jsonObjectGetIndex( _p, 1 )) {
			jsonObjectRemoveKey( jsonObjectGetIndex( _p, 1 ), "flesh" );
			jsonObjectRemoveKey( jsonObjectGetIndex( _p, 1 ), "flesh_columns" );
		} else {
			jsonObjectSetIndex( _p, 1, jsonNewObjectType(JSON_HASH) );
		}

		growing_buffer* sel_list = buffer_init(64);
		buffer_fadd(sel_list, "{ \"%s\":[\"%s\"] }", osrfHashGet( class_obj, "classname" ), osrfHashGet( class_obj, "primarykey" ));
		char* _s = buffer_release(sel_list);

		jsonObjectSetKey( jsonObjectGetIndex( _p, 1 ), "select", jsonParseString(_s) );
		osrfLogDebug(OSRF_LOG_MARK, "%s: Select qualifer set to [%s]", MODULENAME, _s);
		free(_s);

		obj = doFieldmapperSearch(ctx, class_obj, _p, &err);
		jsonObjectFree(_p);
		if(err) return err;

		jsonObject* cur;
		jsonIterator* itr = jsonNewIterator( obj );
		while ((cur = jsonIteratorNext( itr ))) {
			osrfAppRespond(
				ctx,
				jsonObjectGetIndex(
					cur,
					atoi(
						osrfHashGet(
							osrfHashGet(
								osrfHashGet( class_obj, "fields" ),
								osrfHashGet( class_obj, "primarykey")
							),
							"array_position"
						)
					)
				)
			);
		}
		jsonIteratorFree(itr);
		osrfAppRespondComplete( ctx, NULL );
		
	} else {
		osrfAppRespondComplete( ctx, obj );
	}

	jsonObjectFree(obj);

	return err;
}

static int verifyObjectClass ( osrfMethodContext* ctx, const jsonObject* param ) {
	
	osrfHash* meta = (osrfHash*) ctx->method->userData;
	osrfHash* class = osrfHashGet( meta, "class" );
	
	if (!param->classname || (strcmp( osrfHashGet(class, "classname"), param->classname ))) {

		growing_buffer* msg = buffer_init(128);
		buffer_fadd(
			msg,
			"%s: %s method for type %s was passed a %s",
			MODULENAME,
			osrfHashGet(meta, "methodtype"),
			osrfHashGet(class, "classname"),
			param->classname
		);

		char* m = buffer_release(msg);
		osrfAppSessionStatus( ctx->session, OSRF_STATUS_BADREQUEST, "osrfMethodException", ctx->request, m );

		free(m);

		return 0;
	}
	return 1;
}

static jsonObject* doCreate(osrfMethodContext* ctx, int* err ) {

	osrfHash* meta = osrfHashGet( (osrfHash*) ctx->method->userData, "class" );
	jsonObject* target = jsonObjectGetIndex( ctx->params, 0 );
	jsonObject* options = jsonObjectGetIndex( ctx->params, 1 );

	if (!verifyObjectClass(ctx, target)) {
		*err = -1;
		return jsonNULL;
	}

	osrfLogDebug( OSRF_LOG_MARK, "Object seems to be of the correct type" );

	if (!ctx->session || !ctx->session->userData || !osrfHashGet( (osrfHash*)ctx->session->userData, "xact_id" )) {
		osrfLogError( OSRF_LOG_MARK, "No active transaction -- required for CREATE" );

		osrfAppSessionStatus(
			ctx->session,
			OSRF_STATUS_BADREQUEST,
			"osrfMethodException",
			ctx->request,
			"No active transaction -- required for CREATE"
		);
		*err = -1;
		return jsonNULL;
	}

	if (osrfHashGet( meta, "readonly" ) && strncasecmp("true", osrfHashGet( meta, "readonly" ), 4)) {
		osrfAppSessionStatus(
			ctx->session,
			OSRF_STATUS_BADREQUEST,
			"osrfMethodException",
			ctx->request,
			"Cannot INSERT readonly class"
		);
		*err = -1;
		return jsonNULL;
	}


	char* trans_id = osrfHashGet( (osrfHash*)ctx->session->userData, "xact_id" );

        // Set the last_xact_id
	osrfHash* last_xact_id;
	if ((last_xact_id = oilsIDLFindPath("/%s/fields/last_xact_id", target->classname))) {
		int index = atoi( osrfHashGet(last_xact_id, "array_position") );
		osrfLogDebug(OSRF_LOG_MARK, "Setting last_xact_id to %s on %s at position %d", trans_id, target->classname, index);
		jsonObjectSetIndex(target, index, jsonNewObject(trans_id));
	}       

	osrfLogDebug( OSRF_LOG_MARK, "There is a transaction running..." );

	dbhandle = writehandle;

	osrfHash* fields = osrfHashGet(meta, "fields");
	char* pkey = osrfHashGet(meta, "primarykey");
	char* seq = osrfHashGet(meta, "sequence");

	growing_buffer* table_buf = buffer_init(128);
	growing_buffer* col_buf = buffer_init(128);
	growing_buffer* val_buf = buffer_init(128);

	buffer_fadd(table_buf,"INSERT INTO %s", osrfHashGet(meta, "tablename"));
	buffer_add(col_buf,"(");
	buffer_add(val_buf,"VALUES (");


	int i = 0;
	int first = 1;
	char* field_name;
	osrfStringArray* field_list = osrfHashKeys( fields );
	while ( (field_name = osrfStringArrayGetString(field_list, i++)) ) {

		osrfHash* field = osrfHashGet( fields, field_name );

		if(!( strcmp( osrfHashGet(osrfHashGet(fields,field_name), "virtual"), "true" ) )) continue;

		jsonObject* field_object = jsonObjectGetIndex( target, atoi(osrfHashGet(field, "array_position")) );

		char* value;
		if (field_object && field_object->classname) {
			value = jsonObjectToSimpleString(
					jsonObjectGetIndex(
						field_object,
						atoi(
							osrfHashGet(
								osrfHashGet(
									oilsIDLFindPath("/%s/fields", field_object->classname),
									(char*)oilsIDLFindPath("/%s/primarykey", field_object->classname)
								),
								"array_position"
							)
						)
					)
				);

		} else {
			value = jsonObjectToSimpleString( field_object );
		}


		if (first) {
			first = 0;
		} else {
			buffer_add(col_buf, ",");
			buffer_add(val_buf, ",");
		}

		buffer_add(col_buf, field_name);

		if (!field_object || field_object->type == JSON_NULL) {
			buffer_add( val_buf, "DEFAULT" );
			
		} else if ( !strcmp(osrfHashGet(field, "primitive"), "number") ) {
			if ( !strcmp(osrfHashGet(field, "datatype"), "INT8") ) {
				buffer_fadd( val_buf, "%lld", atoll(value) );
				
			} else if ( !strcmp(osrfHashGet(field, "datatype"), "INT") ) {
				buffer_fadd( val_buf, "%d", atoi(value) );
				
			} else if ( !strcmp(osrfHashGet(field, "datatype"), "NUMERIC") ) {
				buffer_fadd( val_buf, "%f", atof(value) );
			}
		} else {
			if ( dbi_conn_quote_string(writehandle, &value) ) {
				buffer_fadd( val_buf, "%s", value );

			} else {
				osrfLogError(OSRF_LOG_MARK, "%s: Error quoting string [%s]", MODULENAME, value);
				osrfAppSessionStatus(
					ctx->session,
					OSRF_STATUS_INTERNALSERVERERROR,
					"osrfMethodException",
					ctx->request,
					"Error quoting string -- please see the error log for more details"
				);
				free(value);
				buffer_free(table_buf);
				buffer_free(col_buf);
				buffer_free(val_buf);
				*err = -1;
				return jsonNULL;
			}
		}

		free(value);
		
	}


	buffer_add(col_buf,")");
	buffer_add(val_buf,")");

	char* table_str = buffer_release(table_buf);
	char* col_str   = buffer_release(col_buf);
	char* val_str   = buffer_release(val_buf);
	growing_buffer* sql = buffer_init(128);
	buffer_fadd( sql, "%s %s %s;", table_str, col_str, val_str );
	free(table_str);
	free(col_str);
	free(val_str);

	char* query = buffer_release(sql);

	osrfLogDebug(OSRF_LOG_MARK, "%s: Insert SQL [%s]", MODULENAME, query);

	
	dbi_result result = dbi_conn_query(writehandle, query);

	jsonObject* obj = NULL;

	if (!result) {
		obj = jsonNewObject(NULL);
		osrfLogError(
			OSRF_LOG_MARK,
			"%s ERROR inserting %s object using query [%s]",
			MODULENAME,
			osrfHashGet(meta, "fieldmapper"),
			query
		);
		osrfAppSessionStatus(
			ctx->session,
			OSRF_STATUS_INTERNALSERVERERROR,
			"osrfMethodException",
			ctx->request,
			"INSERT error -- please see the error log for more details"
		);
		*err = -1;
	} else {

		int pos = atoi(osrfHashGet( osrfHashGet(fields, pkey), "array_position" ));
		char* id = jsonObjectToSimpleString(jsonObjectGetIndex(target, pos));
		if (!id) {
			unsigned long long new_id = dbi_conn_sequence_last(writehandle, seq);
			growing_buffer* _id = buffer_init(10);
			buffer_fadd(_id, "%lld", new_id);
			id = buffer_release(_id);
		}

		// Find quietness specification, if present
		char* quiet_str = NULL;
		if ( options ) {
			const jsonObject* quiet_obj = jsonObjectGetKeyConst( options, "quiet" );
			if( quiet_obj )
				quiet_str = jsonObjectToSimpleString( quiet_obj );
		}

		if( quiet_str && !strcmp( quiet_str, "true" )) {  // if quietness is specified
			obj = jsonNewObject(id);
		}
		else {

			jsonObject* fake_params = jsonNewObjectType(JSON_ARRAY);
			jsonObjectPush(fake_params, jsonNewObjectType(JSON_HASH));

			jsonObjectSetKey(
				jsonObjectGetIndex(fake_params, 0),
				osrfHashGet(meta, "primarykey"),
				jsonNewObject(id)
			);

			jsonObject* list = doFieldmapperSearch( ctx,meta, fake_params, err);

			if(*err) {
				jsonObjectFree( fake_params );
				obj = jsonNULL;
			} else {
				obj = jsonObjectClone( jsonObjectGetIndex(list, 0) );
			}

			jsonObjectFree( list );
			jsonObjectFree( fake_params );
		}

		if(quiet_str) free(quiet_str);
		free(id);
	}

	free(query);

	return obj;

}


static jsonObject* doRetrieve(osrfMethodContext* ctx, int* err ) {

	osrfHash* meta = osrfHashGet( (osrfHash*) ctx->method->userData, "class" );

	jsonObject* obj;

	char* id = jsonObjectToSimpleString(jsonObjectGetIndex(ctx->params, 0));
	jsonObject* order_hash = jsonObjectGetIndex(ctx->params, 1);

	osrfLogDebug(
		OSRF_LOG_MARK,
		"%s retrieving %s object with id %s",
		MODULENAME,
		osrfHashGet(meta, "fieldmapper"),
		id
	);

	jsonObject* fake_params = jsonNewObjectType(JSON_ARRAY);
	jsonObjectPush(fake_params, jsonNewObjectType(JSON_HASH));

	jsonObjectSetKey(
		jsonObjectGetIndex(fake_params, 0),
		osrfHashGet(meta, "primarykey"),
		jsonParseString(id)
	);

	free(id);

	if (order_hash) jsonObjectPush(fake_params, jsonObjectClone(order_hash) );

	jsonObject* list = doFieldmapperSearch( ctx,meta, fake_params, err);

	if(*err) {
		jsonObjectFree( fake_params );
		return jsonNULL;
	}

	obj = jsonObjectClone( jsonObjectGetIndex(list, 0) );

	jsonObjectFree( list );
	jsonObjectFree( fake_params );

	return obj;
}

static char* jsonNumberToDBString ( osrfHash* field, const jsonObject* value ) {
	growing_buffer* val_buf = buffer_init(32);

	if ( !strncmp(osrfHashGet(field, "datatype"), "INT", (size_t)3) ) {
		if (value->type == JSON_NUMBER) buffer_fadd( val_buf, "%ld", (long)jsonObjectGetNumber(value) );
		else {
			char* val_str = jsonObjectToSimpleString(value);
			buffer_fadd( val_buf, "%ld", atol(val_str) );
			free(val_str);
		}

	} else if ( !strcmp(osrfHashGet(field, "datatype"), "NUMERIC") ) {
		if (value->type == JSON_NUMBER) buffer_fadd( val_buf, "%f",  jsonObjectGetNumber(value) );
		else {
			char* val_str = jsonObjectToSimpleString(value);
			buffer_fadd( val_buf, "%f", atof(val_str) );
			free(val_str);
		}
	}

	return buffer_release(val_buf);
}

static char* searchINPredicate (const char* class, osrfHash* field,
		const jsonObject* node, const char* op) {
	growing_buffer* sql_buf = buffer_init(32);
	
	buffer_fadd(
		sql_buf,
		"\"%s\".%s ",
		class,
		osrfHashGet(field, "name")
	);

	if (!op) {
		buffer_add(sql_buf, "IN (");
	} else if (!(strcasecmp(op,"not in"))) {
		buffer_add(sql_buf, "NOT IN (");
	} else {
		buffer_add(sql_buf, "IN (");
	}

	int in_item_index = 0;
	int in_item_first = 1;
	jsonObject* in_item;
	while ( (in_item = jsonObjectGetIndex(node, in_item_index++)) ) {

		if (in_item_first)
			in_item_first = 0;
		else
			buffer_add(sql_buf, ", ");

		if ( !strcmp(osrfHashGet(field, "primitive"), "number") ) {
			char* val = jsonNumberToDBString( field, in_item );
			buffer_fadd( sql_buf, "%s", val );
			free(val);

		} else {
			char* key_string = jsonObjectToSimpleString(in_item);
			if ( dbi_conn_quote_string(dbhandle, &key_string) ) {
				buffer_fadd( sql_buf, "%s", key_string );
				free(key_string);
			} else {
				osrfLogError(OSRF_LOG_MARK, "%s: Error quoting key string [%s]", MODULENAME, key_string);
				free(key_string);
				buffer_free(sql_buf);
				return NULL;
			}
		}
	}

	buffer_add(
		sql_buf,
		")"
	);

	return buffer_release(sql_buf);
}

static char* searchValueTransform( const jsonObject* array ) {
	growing_buffer* sql_buf = buffer_init(32);

	char* val = NULL;
	int func_item_index = 0;
	int func_item_first = 2;
	jsonObject* func_item;
	while ( (func_item = jsonObjectGetIndex(array, func_item_index++)) ) {

		val = jsonObjectToSimpleString(func_item);

		if (func_item_first == 2) {
			buffer_fadd(sql_buf, "%s( ", val);
			free(val);
			func_item_first--;
			continue;
		}

		if (func_item_first)
			func_item_first--;
		else
			buffer_add(sql_buf, ", ");

		if (func_item->type == JSON_NULL) {
			buffer_add( sql_buf, "NULL" );
		} else if ( dbi_conn_quote_string(dbhandle, &val) ) {
			buffer_fadd( sql_buf, "%s", val );
		} else {
			osrfLogError(OSRF_LOG_MARK, "%s: Error quoting key string [%s]", MODULENAME, val);
			free(val);
			buffer_free(sql_buf);
			return NULL;
		}

		free(val);
	}

	buffer_add(
		sql_buf,
		" )"
	);

	return buffer_release(sql_buf);
}

static char* searchFunctionPredicate (const char* class, osrfHash* field,
		const jsonObject* node, const char* node_key) {
	growing_buffer* sql_buf = buffer_init(32);

	char* val = searchValueTransform(node);
	
	buffer_fadd(
		sql_buf,
		"\"%s\".%s %s %s",
		class,
		osrfHashGet(field, "name"),
		node_key,
		val
	);

	free(val);

	return buffer_release(sql_buf);
}

static char* searchFieldTransform (const char* class, osrfHash* field, const jsonObject* node) {
	growing_buffer* sql_buf = buffer_init(32);
	
	char* field_transform = jsonObjectToSimpleString( jsonObjectGetKeyConst( node, "transform" ) );
	char* transform_subcolumn = jsonObjectToSimpleString( jsonObjectGetKeyConst( node, "result_field" ) );

	if (field_transform) {
		buffer_fadd( sql_buf, "%s(\"%s\".%s", field_transform, class, osrfHashGet(field, "name"));
	    const jsonObject* array = jsonObjectGetKeyConst( node, "params" );

        if (array) {
        	int func_item_index = 0;
        	jsonObject* func_item;
        	while ( (func_item = jsonObjectGetIndex(array, func_item_index++)) ) {

	        	char* val = jsonObjectToSimpleString(func_item);

       		    if ( !val ) {
	    		    buffer_add( sql_buf, ",NULL" );
       		    } else if ( dbi_conn_quote_string(dbhandle, &val) ) {
	    		    buffer_fadd( sql_buf, ",%s", val );
        		} else {
	        		osrfLogError(OSRF_LOG_MARK, "%s: Error quoting key string [%s]", MODULENAME, val);
		    	    free(field_transform);
					free(val);
        			buffer_free(sql_buf);
	        		return NULL;
    	    	}
				free(val);
			}

        }

       	buffer_add(
        	sql_buf,
	        " )"
       	);

	} else {
		buffer_fadd( sql_buf, "\"%s\".%s", class, osrfHashGet(field, "name"));
	}

    if (transform_subcolumn) {
        char * tmp = buffer_release(sql_buf);
        sql_buf = buffer_init(32);
        buffer_fadd(
            sql_buf,
            "(%s).\"%s\"",
            tmp,
            transform_subcolumn
        );
        free(tmp);
    }
 
	if (field_transform) free(field_transform);
	if (transform_subcolumn) free(transform_subcolumn);

	return buffer_release(sql_buf);
}

static char* searchFieldTransformPredicate (const char* class, osrfHash* field, jsonObject* node, const char* node_key) {
	char* field_transform = searchFieldTransform( class, field, node );
	char* value = NULL;

	if (!jsonObjectGetKeyConst( node, "value" )) {
		value = searchWHERE( node, osrfHashGet( oilsIDL(), class ), AND_OP_JOIN, NULL );
	} else if (jsonObjectGetKeyConst( node, "value" )->type == JSON_ARRAY) {
		value = searchValueTransform(jsonObjectGetKeyConst( node, "value" ));
	} else if (jsonObjectGetKeyConst( node, "value" )->type == JSON_HASH) {
		value = searchWHERE( jsonObjectGetKeyConst( node, "value" ), osrfHashGet( oilsIDL(), class ), AND_OP_JOIN, NULL );
	} else if (jsonObjectGetKeyConst( node, "value" )->type != JSON_NULL) {
		if ( !strcmp(osrfHashGet(field, "primitive"), "number") ) {
			value = jsonNumberToDBString( field, jsonObjectGetKeyConst( node, "value" ) );
		} else {
			value = jsonObjectToSimpleString(jsonObjectGetKeyConst( node, "value" ));
			if ( !dbi_conn_quote_string(dbhandle, &value) ) {
				osrfLogError(OSRF_LOG_MARK, "%s: Error quoting key string [%s]", MODULENAME, value);
				free(value);
				free(field_transform);
				return NULL;
			}
		}
	}

	growing_buffer* sql_buf = buffer_init(32);
	
	buffer_fadd(
		sql_buf,
		"%s %s %s",
		field_transform,
		node_key,
		value
	);

	free(value);
	free(field_transform);

	return buffer_release(sql_buf);
}

static char* searchSimplePredicate (const char* orig_op, const char* class,
		osrfHash* field, const jsonObject* node) {

	char* val = NULL;

	if (node->type != JSON_NULL) {
		if ( !strcmp(osrfHashGet(field, "primitive"), "number") ) {
			val = jsonNumberToDBString( field, node );
		} else {
			val = jsonObjectToSimpleString(node);
		}
	}

	char* pred = searchWriteSimplePredicate( class, field, osrfHashGet(field, "name"), orig_op, val );

	if (val) free(val);

	return pred;
}

static char* searchWriteSimplePredicate ( const char* class, osrfHash* field,
	const char* left, const char* orig_op, const char* right ) {

	char* val = NULL;
	char* op = NULL;
	if (right == NULL) {
		val = strdup("NULL");

		if (strcmp( orig_op, "=" ))
			op = strdup("IS NOT");
		else
			op = strdup("IS");

	} else if ( !strcmp(osrfHashGet(field, "primitive"), "number") ) {
		val = strdup(right);
		op = strdup(orig_op);

	} else {
		val = strdup(right);
		if ( !dbi_conn_quote_string(dbhandle, &val) ) {
			osrfLogError(OSRF_LOG_MARK, "%s: Error quoting key string [%s]", MODULENAME, val);
			free(val);
			return NULL;
		}
		op = strdup(orig_op);
	}

	growing_buffer* sql_buf = buffer_init(16);
	buffer_fadd( sql_buf, "\"%s\".%s %s %s", class, left, op, val );
	free(val);
	free(op);

	return buffer_release(sql_buf);
}

static char* searchBETWEENPredicate (const char* class, osrfHash* field, jsonObject* node) {

	char* x_string;
	char* y_string;

	if ( !strcmp(osrfHashGet(field, "primitive"), "number") ) {
		x_string = jsonNumberToDBString(field, jsonObjectGetIndex(node,0));
		y_string = jsonNumberToDBString(field, jsonObjectGetIndex(node,1));

	} else {
		x_string = jsonObjectToSimpleString(jsonObjectGetIndex(node,0));
		y_string = jsonObjectToSimpleString(jsonObjectGetIndex(node,1));
		if ( !(dbi_conn_quote_string(dbhandle, &x_string) && dbi_conn_quote_string(dbhandle, &y_string)) ) {
			osrfLogError(OSRF_LOG_MARK, "%s: Error quoting key strings [%s] and [%s]", MODULENAME, x_string, y_string);
			free(x_string);
			free(y_string);
			return NULL;
		}
	}

	growing_buffer* sql_buf = buffer_init(32);
	buffer_fadd( sql_buf, "%s BETWEEN %s AND %s", osrfHashGet(field, "name"), x_string, y_string );
	free(x_string);
	free(y_string);

	return buffer_release(sql_buf);
}

static char* searchPredicate ( const char* class, osrfHash* field, jsonObject* node ) {

	char* pred = NULL;
	if (node->type == JSON_ARRAY) { // equality IN search
		pred = searchINPredicate( class, field, node, NULL );
	} else if (node->type == JSON_HASH) { // non-equality search
		jsonObject* pred_node;
		jsonIterator* pred_itr = jsonNewIterator( node );
		while ( (pred_node = jsonIteratorNext( pred_itr )) ) {
			if ( !(strcasecmp( pred_itr->key,"between" )) )
				pred = searchBETWEENPredicate( class, field, pred_node );
			else if ( !(strcasecmp( pred_itr->key,"in" )) || !(strcasecmp( pred_itr->key,"not in" )) )
				pred = searchINPredicate( class, field, pred_node, pred_itr->key );
			else if ( pred_node->type == JSON_ARRAY )
				pred = searchFunctionPredicate( class, field, pred_node, pred_itr->key );
			else if ( pred_node->type == JSON_HASH )
				pred = searchFieldTransformPredicate( class, field, pred_node, pred_itr->key );
			else 
				pred = searchSimplePredicate( pred_itr->key, class, field, pred_node );

			break;
		}
        jsonIteratorFree(pred_itr);
	} else if (node->type == JSON_NULL) { // IS NULL search
		growing_buffer* _p = buffer_init(64);
		buffer_fadd(
			_p,
			"\"%s\".%s IS NULL",
			class,
			osrfHashGet(field, "name")
		);
		pred = buffer_release(_p);
	} else { // equality search
		pred = searchSimplePredicate( "=", class, field, node );
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

static char* searchJOIN ( const jsonObject* join_hash, osrfHash* leftmeta ) {

	const jsonObject* working_hash;
	jsonObject* freeable_hash = NULL;

	if (join_hash->type == JSON_STRING) {
		// create a wrapper around a copy of the original
		char* _tmp = jsonObjectToSimpleString( join_hash );
		freeable_hash = jsonNewObjectType(JSON_HASH);
		jsonObjectSetKey(freeable_hash, _tmp, NULL);
		free(_tmp);
		working_hash = freeable_hash;
	}
	else
		working_hash = join_hash;

	growing_buffer* join_buf = buffer_init(128);
	char* leftclass = osrfHashGet(leftmeta, "classname");

	jsonObject* snode = NULL;
	jsonIterator* search_itr = jsonNewIterator( working_hash );
	if(freeable_hash)
		jsonObjectFree(freeable_hash);
	
	while ( (snode = jsonIteratorNext( search_itr )) ) {
		osrfHash* idlClass = osrfHashGet( oilsIDL(), search_itr->key );

		char* class = osrfHashGet(idlClass, "classname");

		char* fkey = jsonObjectToSimpleString( jsonObjectGetKeyConst( snode, "fkey" ) );
		char* field = jsonObjectToSimpleString( jsonObjectGetKeyConst( snode, "field" ) );

		if (field && !fkey) {
			fkey = (char*)oilsIDLFindPath("/%s/links/%s/key", class, field);
			if (!fkey) {
				osrfLogError(
					OSRF_LOG_MARK,
					"%s: JOIN failed.  No link defined from %s.%s to %s",
					MODULENAME,
					class,
					field,
					leftclass
				);
				buffer_free(join_buf);
				free(field);
				jsonIteratorFree(search_itr);
				return NULL;
			}
			fkey = strdup( fkey );

		} else if (!field && fkey) {
			field = (char*)oilsIDLFindPath("/%s/links/%s/key", leftclass, fkey );
			if (!field) {
				osrfLogError(
					OSRF_LOG_MARK,
					"%s: JOIN failed.  No link defined from %s.%s to %s",
					MODULENAME,
					leftclass,
					fkey,
					class
				);
				buffer_free(join_buf);
				free(fkey);
				jsonIteratorFree(search_itr);
				return NULL;
			}
			field = strdup( field );

		} else if (!field && !fkey) {
			osrfHash* _links = oilsIDLFindPath("/%s/links", leftclass);

			int i = 0;
			osrfStringArray* keys = osrfHashKeys( _links );
			while ( (fkey = osrfStringArrayGetString(keys, i++)) ) {
				fkey = strdup(osrfStringArrayGetString(keys, i++));
				if ( !strcmp( (char*)oilsIDLFindPath("/%s/links/%s/class", leftclass, fkey), class) ) {
					field = strdup( (char*)oilsIDLFindPath("/%s/links/%s/key", leftclass, fkey) );
					break;
				} else {
					free(fkey);
				}
			}
			osrfStringArrayFree(keys);

			if (!field && !fkey) {
				_links = oilsIDLFindPath("/%s/links", class);

				i = 0;
				keys = osrfHashKeys( _links );
				while ( (field = osrfStringArrayGetString(keys, i++)) ) {
					field = strdup(osrfStringArrayGetString(keys, i++));
					if ( !strcmp( (char*)oilsIDLFindPath("/%s/links/%s/class", class, field), class) ) {
						fkey = strdup( (char*)oilsIDLFindPath("/%s/links/%s/key", class, field) );
						break;
					} else {
						free(field);
					}
				}
				osrfStringArrayFree(keys);
			}

			if (!field && !fkey) {
				osrfLogError(
					OSRF_LOG_MARK,
					"%s: JOIN failed.  No link defined between %s and %s",
					MODULENAME,
					leftclass,
					class
				);
				buffer_free(join_buf);
				jsonIteratorFree(search_itr);
				return NULL;
			}

		}

		char* type = jsonObjectToSimpleString( jsonObjectGetKeyConst( snode, "type" ) );
		if (type) {
			if ( !strcasecmp(type,"left") ) {
				buffer_add(join_buf, " LEFT JOIN");
			} else if ( !strcasecmp(type,"right") ) {
				buffer_add(join_buf, " RIGHT JOIN");
			} else if ( !strcasecmp(type,"full") ) {
				buffer_add(join_buf, " FULL JOIN");
			} else {
				buffer_add(join_buf, " INNER JOIN");
			}
		} else {
			buffer_add(join_buf, " INNER JOIN");
		}
		free(type);

		char* table = getSourceDefinition(idlClass);
		buffer_fadd(join_buf, " %s AS \"%s\" ON ( \"%s\".%s = \"%s\".%s", table, class, class, field, leftclass, fkey);
		free(table);

		const jsonObject* filter = jsonObjectGetKeyConst( snode, "filter" );
		if (filter) {
			char* filter_op = jsonObjectToSimpleString( jsonObjectGetKeyConst( snode, "filter_op" ) );
			if (filter_op) {
				if (!strcasecmp("or",filter_op)) {
					buffer_add( join_buf, " OR " );
				} else {
					buffer_add( join_buf, " AND " );
				}
			} else {
				buffer_add( join_buf, " AND " );
			}

			char* jpred = searchWHERE( filter, idlClass, AND_OP_JOIN, NULL );
			buffer_fadd( join_buf, " %s", jpred );
			free(jpred);
			free(filter_op);
		}

		buffer_add(join_buf, " ) ");
		
		const jsonObject* join_filter = jsonObjectGetKeyConst( snode, "join" );
		if (join_filter) {
			char* jpred = searchJOIN( join_filter, idlClass );
			buffer_fadd( join_buf, " %s", jpred );
			free(jpred);
		}

		free(fkey);
		free(field);
	}

    jsonIteratorFree(search_itr);

	return buffer_release(join_buf);
}

/*

{ +class : { -or|-and : { field : { op : value }, ... } ... }, ... }
{ +class : { -or|-and : [ { field : { op : value }, ... }, ...] ... }, ... }
[ { +class : { -or|-and : [ { field : { op : value }, ... }, ...] ... }, ... }, ... ]

*/

static char* searchWHERE ( const jsonObject* search_hash, osrfHash* meta, int opjoin_type, osrfMethodContext* ctx ) {

	growing_buffer* sql_buf = buffer_init(128);

	jsonObject* node = NULL;

    int first = 1;
    if ( search_hash->type == JSON_ARRAY ) {
        jsonIterator* search_itr = jsonNewIterator( search_hash );
        while ( (node = jsonIteratorNext( search_itr )) ) {
            if (first) {
                first = 0;
            } else {
                if (opjoin_type == OR_OP_JOIN) buffer_add(sql_buf, " OR ");
                else buffer_add(sql_buf, " AND ");
            }

            char* subpred = searchWHERE( node, meta, opjoin_type, ctx );
            buffer_fadd(sql_buf, "( %s )", subpred);
            free(subpred);
        }
        jsonIteratorFree(search_itr);

    } else if ( search_hash->type == JSON_HASH ) {
        jsonIterator* search_itr = jsonNewIterator( search_hash );
        while ( (node = jsonIteratorNext( search_itr )) ) {

            if (first) {
                first = 0;
            } else {
                if (opjoin_type == OR_OP_JOIN) buffer_add(sql_buf, " OR ");
                else buffer_add(sql_buf, " AND ");
            }

            if ( !strncmp("+",search_itr->key,1) ) {
                if ( node->type == JSON_STRING ) {
                    char* subpred = jsonObjectToSimpleString( node );
                    buffer_fadd(sql_buf, " \"%s\".%s ", search_itr->key + 1, subpred);
                    free(subpred);
                } else {
                    char* subpred = searchWHERE( node, osrfHashGet( oilsIDL(), search_itr->key + 1 ), AND_OP_JOIN, ctx );
                    buffer_fadd(sql_buf, "( %s )", subpred);
                    free(subpred);
                }
            } else if ( !strcasecmp("-or",search_itr->key) ) {
                char* subpred = searchWHERE( node, meta, OR_OP_JOIN, ctx );
                buffer_fadd(sql_buf, "( %s )", subpred);
                free(subpred);
            } else if ( !strcasecmp("-and",search_itr->key) ) {
                char* subpred = searchWHERE( node, meta, AND_OP_JOIN, ctx );
                buffer_fadd(sql_buf, "( %s )", subpred);
                free(subpred);
            } else if ( !strcasecmp("-exists",search_itr->key) ) {
                char* subpred = SELECT(
			ctx,
			jsonObjectGetKey( node, "select" ),
			jsonObjectGetKey( node, "from" ),
			jsonObjectGetKey( node, "where" ),
			jsonObjectGetKey( node, "having" ),
			jsonObjectGetKey( node, "order_by" ),
			jsonObjectGetKey( node, "limit" ),
			jsonObjectGetKey( node, "offset" ),
			SUBSELECT
                );

                buffer_fadd(sql_buf, "EXISTS ( %s )", subpred);
                free(subpred);
            } else {

                char* class = osrfHashGet(meta, "classname");
                osrfHash* fields = osrfHashGet(meta, "fields");
                osrfHash* field = osrfHashGet( fields, search_itr->key );


                if (!field) {
                    char* table = getSourceDefinition(meta);
                    osrfLogError(
                        OSRF_LOG_MARK,
                        "%s: Attempt to reference non-existant column %s on %s (%s)",
                        MODULENAME,
                        search_itr->key,
                        table,
                        class
                    );
                    buffer_free(sql_buf);
                    free(table);
					jsonIteratorFree(search_itr);
					return NULL;
                }

                char* subpred = searchPredicate( class, field, node );
                buffer_add( sql_buf, subpred );
                free(subpred);
            }
        }
	    jsonIteratorFree(search_itr);

    } else {
        // ERROR ... only hash and array allowed at this level
        char* predicate_string = jsonObjectToJSON( search_hash );
        osrfLogError(
            OSRF_LOG_MARK,
            "%s: Invalid predicate structure: %s",
            MODULENAME,
            predicate_string
        );
        buffer_free(sql_buf);
        free(predicate_string);
        return NULL;
    }


	return buffer_release(sql_buf);
}

static char* SELECT (
		/* method context */ osrfMethodContext* ctx,
		
		/* SELECT   */ jsonObject* selhash,
		/* FROM     */ jsonObject* join_hash,
		/* WHERE    */ jsonObject* search_hash,
		/* HAVING   */ jsonObject* having_hash,
		/* ORDER BY */ jsonObject* order_hash,
		/* LIMIT    */ jsonObject* limit,
		/* OFFSET   */ jsonObject* offset,
		/* flags    */ int flags
) {
	const char* locale = osrf_message_get_last_locale();

	// in case we don't get a select list
	jsonObject* defaultselhash = NULL;

	// general tmp objects
	const jsonObject* tmp_const;
	jsonObject* _tmp = NULL;
	jsonObject* selclass = NULL;
	jsonObject* selfield = NULL;
	jsonObject* snode = NULL;
	jsonObject* onode = NULL;
	jsonObject* found = NULL;

	char* string = NULL;
	int from_function = 0;
	int first = 1;
	int gfirst = 1;
	//int hfirst = 1;

	// the core search class
	char* core_class = NULL;

	// metadata about the core search class
	osrfHash* core_meta = NULL;
	osrfHash* core_fields = NULL;
	osrfHash* idlClass = NULL;

	// punt if there's no core class
	if (!join_hash || ( join_hash->type == JSON_HASH && !join_hash->size ))
		return NULL;

	// get the core class -- the only key of the top level FROM clause, or a string
	if (join_hash->type == JSON_HASH) {
		jsonIterator* tmp_itr = jsonNewIterator( join_hash );
		snode = jsonIteratorNext( tmp_itr );
		
		core_class = strdup( tmp_itr->key );
		join_hash = snode;

		jsonIteratorFree( tmp_itr );
		snode = NULL;

	} else if (join_hash->type == JSON_ARRAY) {
        from_function = 1;
        selhash = NULL;

	} else if (join_hash->type == JSON_STRING) {
		core_class = jsonObjectToSimpleString( join_hash );
		join_hash = NULL;
	}

	// punt if we don't know about the core class (and it's not a function)
	if (!from_function && !(core_meta = osrfHashGet( oilsIDL(), core_class ))) {
		free(core_class);
		return NULL;
	}

	// if the select list is empty, or the core class field list is '*',
	// build the default select list ...
	if (!selhash) {
		selhash = defaultselhash = jsonNewObjectType(JSON_HASH);
		jsonObjectSetKey( selhash, core_class, jsonNewObjectType(JSON_ARRAY) );
	} else if ( (tmp_const = jsonObjectGetKeyConst( selhash, core_class )) && tmp_const->type == JSON_STRING ) {
		char* _x = jsonObjectToSimpleString( tmp_const );
		if (!strncmp( "*", _x, 1 )) {
			jsonObjectRemoveKey( selhash, core_class );
			jsonObjectSetKey( selhash, core_class, jsonNewObjectType(JSON_ARRAY) );
		}
		free(_x);
	}

	// the query buffer
	growing_buffer* sql_buf = buffer_init(128);

	// temp buffer for the SELECT list
	growing_buffer* select_buf = buffer_init(128);
	growing_buffer* order_buf = buffer_init(128);
	growing_buffer* group_buf = buffer_init(128);
	growing_buffer* having_buf = buffer_init(128);

	if (!from_function) 
        core_fields = osrfHashGet(core_meta, "fields");

	// ... and if we /are/ building the default list, do that
	if ( (_tmp = jsonObjectGetKey(selhash,core_class)) && !_tmp->size ) {
		
		int i = 0;
		char* field;

        if (!from_function) {
    		osrfStringArray* keys = osrfHashKeys( core_fields );
	    	while ( (field = osrfStringArrayGetString(keys, i++)) ) {
		    	if ( strncasecmp( "true", osrfHashGet( osrfHashGet( core_fields, field ), "virtual" ), 4 ) )
			    	jsonObjectPush( _tmp, jsonNewObject( field ) );
    		}
	    	osrfStringArrayFree(keys);
        }
	}

	// Now we build the actual select list
	if (!from_function) {
	    int sel_pos = 1;
	    jsonObject* is_agg = jsonObjectFindPath(selhash, "//aggregate");
	    first = 1;
	    gfirst = 1;
	    jsonIterator* selclass_itr = jsonNewIterator( selhash );
	    while ( (selclass = jsonIteratorNext( selclass_itr )) ) {

		    // round trip through the idl, just to be safe
		    idlClass = osrfHashGet( oilsIDL(), selclass_itr->key );
		    if (!idlClass) continue;
		    char* cname = osrfHashGet(idlClass, "classname");

		    // make sure the target relation is in the join tree
		    if (strcmp(core_class,cname)) {
			    if (!join_hash) continue;

			    if (join_hash->type == JSON_STRING) {
				    string = jsonObjectToSimpleString(join_hash);
				    found = strcmp(string,cname) ? NULL : jsonParseString("{\"1\":\"1\"}");
				    free(string);
			    } else {
				    found = jsonObjectFindPath(join_hash, "//%s", cname);
			    }

			    if (!found->size) {
				    jsonObjectFree(found);
				    continue;
			    }

			    jsonObjectFree(found);
		    }

		    // stitch together the column list ...
		    jsonIterator* select_itr = jsonNewIterator( selclass );
		    while ( (selfield = jsonIteratorNext( select_itr )) ) {

			    char* __column = NULL;
			    char* __alias = NULL;

			    // ... if it's a sstring, just toss it on the pile
			    if (selfield->type == JSON_STRING) {

				    // again, just to be safe
				    char* _requested_col = jsonObjectToSimpleString(selfield);
				    osrfHash* field = osrfHashGet( osrfHashGet( idlClass, "fields" ), _requested_col );
				    free(_requested_col);

				    if (!field) continue;
				    __column = strdup(osrfHashGet(field, "name"));

				    if (first) {
					    first = 0;
				    } else {
					    buffer_add(select_buf, ",");
				    }

                    if (locale) {
            		    char* i18n = osrfHashGet(field, "i18n");
			            if (flags & DISABLE_I18N)
                            i18n = NULL;

    	    		    if ( i18n && !strncasecmp("true", i18n, 4)) {
        	                char* pkey = osrfHashGet(idlClass, "primarykey");
        	                char* tname = osrfHashGet(idlClass, "tablename");

                            buffer_fadd(select_buf, " oils_i18n_xlate('%s', '%s', '%s', '%s', \"%s\".%s::TEXT, '%s') AS \"%s\"", tname, cname, __column, pkey, cname, pkey, locale, __column);
                        } else {
				            buffer_fadd(select_buf, " \"%s\".%s AS \"%s\"", cname, __column, __column);
                        }
                    } else {
				        buffer_fadd(select_buf, " \"%s\".%s AS \"%s\"", cname, __column, __column);
                    }

			    // ... but it could be an object, in which case we check for a Field Transform
			    } else {

				    __column = jsonObjectToSimpleString( jsonObjectGetKeyConst( selfield, "column" ) );

				    // again, just to be safe
				    osrfHash* field = osrfHashGet( osrfHashGet( idlClass, "fields" ), __column );
				    if (!field) continue;
				    const char* fname = osrfHashGet(field, "name");

				    if (first) {
					    first = 0;
				    } else {
					    buffer_add(select_buf, ",");
				    }

				    if ((tmp_const = jsonObjectGetKeyConst( selfield, "alias" ))) {
					    __alias = jsonObjectToSimpleString( tmp_const );
				    } else {
					    __alias = strdup(__column);
				    }

				    if (jsonObjectGetKeyConst( selfield, "transform" )) {
					    free(__column);
					    __column = searchFieldTransform(cname, field, selfield);
					    buffer_fadd(select_buf, " %s AS \"%s\"", __column, __alias);
				    } else {
                        if (locale) {
                		    char* i18n = osrfHashGet(field, "i18n");
			                if (flags & DISABLE_I18N)
                                i18n = NULL;
    
    	        		    if ( i18n && !strncasecmp("true", i18n, 4)) {
        	                    char* pkey = osrfHashGet(idlClass, "primarykey");
        	                    char* tname = osrfHashGet(idlClass, "tablename");

                                buffer_fadd(select_buf, " oils_i18n_xlate('%s', '%s', '%s', '%s', \"%s\".%s::TEXT, '%s') AS \"%s\"", tname, cname, fname, pkey, cname, pkey, locale, __alias);
                            } else {
					            buffer_fadd(select_buf, " \"%s\".%s AS \"%s\"", cname, fname, __alias);
                            }
                        } else {
					        buffer_fadd(select_buf, " \"%s\".%s AS \"%s\"", cname, fname, __alias);
                        }
				    }
			    }

			    if (is_agg->size || (flags & SELECT_DISTINCT)) {

				    if ( !(
                            jsonBoolIsTrue( jsonObjectGetKey( selfield, "aggregate" ) ) ||
	                        ((int)jsonObjectGetNumber(jsonObjectGetKey( selfield, "aggregate" ))) == 1 // support 1/0 for perl's sake
                         )
                    ) {
					    if (gfirst) {
						    gfirst = 0;
					    } else {
						    buffer_add(group_buf, ",");
					    }

					    buffer_fadd(group_buf, " %d", sel_pos);
				    /*
				    } else if (is_agg = jsonObjectGetKey( selfield, "having" )) {
					    if (gfirst) {
						    gfirst = 0;
					    } else {
						    buffer_add(group_buf, ",");
					    }

					    __column = searchFieldTransform(cname, field, selfield);
					    buffer_fadd(group_buf, " %s", __column);
					    __column = searchFieldTransform(cname, field, selfield);
				    */
				    }
			    }

			    if (__column) free(__column);
			    if (__alias) free(__alias);

			    sel_pos++;
		    }

            // jsonIteratorFree(select_itr);
	    }

        // jsonIteratorFree(selclass_itr);

	    if (is_agg) jsonObjectFree(is_agg);
    } else {
        buffer_add(select_buf, "*");
    }


	char* col_list = buffer_release(select_buf);
	char* table = NULL;
    if (!from_function) table = getSourceDefinition(core_meta);
    else table = searchValueTransform(join_hash);

	// Put it all together
	buffer_fadd(sql_buf, "SELECT %s FROM %s AS \"%s\" ", col_list, table, core_class );
	free(col_list);
	free(table);

    if (!from_function) {
	    // Now, walk the join tree and add that clause
	    if ( join_hash ) {
		    char* join_clause = searchJOIN( join_hash, core_meta );
		    buffer_add(sql_buf, join_clause);
		    free(join_clause);
	    }

	    if ( search_hash ) {
		    buffer_add(sql_buf, " WHERE ");

		    // and it's on the the WHERE clause
		    char* pred = searchWHERE( search_hash, core_meta, AND_OP_JOIN, ctx );

		    if (!pred) {
			    if (ctx) {
			        osrfAppSessionStatus(
				        ctx->session,
				        OSRF_STATUS_INTERNALSERVERERROR,
				        "osrfMethodException",
				        ctx->request,
				        "Severe query error in WHERE predicate -- see error log for more details"
			        );
			    }
			    free(core_class);
			    buffer_free(having_buf);
			    buffer_free(group_buf);
			    buffer_free(order_buf);
			    buffer_free(sql_buf);
			    if (defaultselhash) jsonObjectFree(defaultselhash);
			    return NULL;
		    } else {
			    buffer_add(sql_buf, pred);
			    free(pred);
		    }
        }

	    if ( having_hash ) {
		    buffer_add(sql_buf, " HAVING ");

		    // and it's on the the WHERE clause
		    char* pred = searchWHERE( having_hash, core_meta, AND_OP_JOIN, ctx );

		    if (!pred) {
			    if (ctx) {
			        osrfAppSessionStatus(
				        ctx->session,
				        OSRF_STATUS_INTERNALSERVERERROR,
				        "osrfMethodException",
				        ctx->request,
				        "Severe query error in HAVING predicate -- see error log for more details"
			        );
			    }
			    free(core_class);
			    buffer_free(having_buf);
			    buffer_free(group_buf);
			    buffer_free(order_buf);
			    buffer_free(sql_buf);
			    if (defaultselhash) jsonObjectFree(defaultselhash);
			    return NULL;
		    } else {
			    buffer_add(sql_buf, pred);
			    free(pred);
		    }
	    }

	    first = 1;
	    jsonIterator* class_itr = jsonNewIterator( order_hash );
	    while ( (snode = jsonIteratorNext( class_itr )) ) {

		    if (!jsonObjectGetKeyConst(selhash,class_itr->key))
			    continue;

		    if ( snode->type == JSON_HASH ) {

		        jsonIterator* order_itr = jsonNewIterator( snode );
			    while ( (onode = jsonIteratorNext( order_itr )) ) {

				    if (!oilsIDLFindPath( "/%s/fields/%s", class_itr->key, order_itr->key ))
					    continue;

				    char* direction = NULL;
				    if ( onode->type == JSON_HASH ) {
					    if ( jsonObjectGetKeyConst( onode, "transform" ) ) {
						    string = searchFieldTransform(
							    class_itr->key,
							    oilsIDLFindPath( "/%s/fields/%s", class_itr->key, order_itr->key ),
							    onode
						    );
					    } else {
						    growing_buffer* field_buf = buffer_init(16);
						    buffer_fadd(field_buf, "\"%s\".%s", class_itr->key, order_itr->key);
						    string = buffer_release(field_buf);
					    }

					    if ( (tmp_const = jsonObjectGetKeyConst( onode, "direction" )) ) {
						    direction = jsonObjectToSimpleString(tmp_const);
						    if (!strncasecmp(direction, "d", 1)) {
							    free(direction);
							    direction = " DESC";
						    } else {
							    free(direction);
							    direction = " ASC";
						    }
					    }

				    } else {
					    string = strdup(order_itr->key);
					    direction = jsonObjectToSimpleString(onode);
					    if (!strncasecmp(direction, "d", 1)) {
						    free(direction);
						    direction = " DESC";
					    } else {
						    free(direction);
						    direction = " ASC";
					    }
				    }

				    if (first) {
					    first = 0;
				    } else {
					    buffer_add(order_buf, ", ");
				    }

				    buffer_add(order_buf, string);
				    free(string);

				    if (direction) {
					    buffer_add(order_buf, direction);
				    }

			    }
                // jsonIteratorFree(order_itr);

		    } else if ( snode->type == JSON_ARRAY ) {

		        jsonIterator* order_itr = jsonNewIterator( snode );
			    while ( (onode = jsonIteratorNext( order_itr )) ) {

				    char* _f = jsonObjectToSimpleString( onode );

				    if (!oilsIDLFindPath( "/%s/fields/%s", class_itr->key, _f))
					    continue;

				    if (first) {
					    first = 0;
				    } else {
					    buffer_add(order_buf, ", ");
				    }

				    buffer_add(order_buf, _f);
				    free(_f);

			    }
                // jsonIteratorFree(order_itr);


		    // IT'S THE OOOOOOOOOOOLD STYLE!
		    } else {
			    osrfLogError(OSRF_LOG_MARK, "%s: Possible SQL injection attempt; direct order by is not allowed", MODULENAME);
			    if (ctx) {
			        osrfAppSessionStatus(
				        ctx->session,
				        OSRF_STATUS_INTERNALSERVERERROR,
				        "osrfMethodException",
				        ctx->request,
				        "Severe query error -- see error log for more details"
			        );
			    }

			    free(core_class);
			    buffer_free(having_buf);
			    buffer_free(group_buf);
			    buffer_free(order_buf);
			    buffer_free(sql_buf);
			    if (defaultselhash) jsonObjectFree(defaultselhash);
			    jsonIteratorFree(class_itr);
			    return NULL;
		    }

	    }
    }

    // jsonIteratorFree(class_itr);

	string = buffer_release(group_buf);

	if (strlen(string)) {
		buffer_fadd(
			sql_buf,
			" GROUP BY %s",
			string
		);
	}

	free(string);

 	string = buffer_release(having_buf);
 
 	if (strlen(string)) {
 		buffer_fadd(
 			sql_buf,
 			" HAVING %s",
 			string
 		);
 	}

	free(string);

	string = buffer_release(order_buf);

	if (strlen(string)) {
		buffer_fadd(
			sql_buf,
			" ORDER BY %s",
			string
		);
	}

	free(string);

	if ( limit ){
		string = jsonObjectToSimpleString(limit);
		buffer_fadd( sql_buf, " LIMIT %d", atoi(string) );
		free(string);
	}

	if (offset) {
		string = jsonObjectToSimpleString(offset);
		buffer_fadd( sql_buf, " OFFSET %d", atoi(string) );
		free(string);
	}

	if (!(flags & SUBSELECT)) buffer_add(sql_buf, ";");

	free(core_class);
	if (defaultselhash) jsonObjectFree(defaultselhash);

	return buffer_release(sql_buf);

}

static char* buildSELECT ( jsonObject* search_hash, jsonObject* order_hash, osrfHash* meta, osrfMethodContext* ctx ) {

	const char* locale = osrf_message_get_last_locale();

	osrfHash* fields = osrfHashGet(meta, "fields");
	char* core_class = osrfHashGet(meta, "classname");

	const jsonObject* join_hash = jsonObjectGetKeyConst( order_hash, "join" );

	jsonObject* node = NULL;
	jsonObject* snode = NULL;
	jsonObject* onode = NULL;
	const jsonObject* _tmp = NULL;
	jsonObject* selhash = NULL;
	jsonObject* defaultselhash = NULL;

	growing_buffer* sql_buf = buffer_init(128);
	growing_buffer* select_buf = buffer_init(128);

	if ( !(selhash = jsonObjectGetKey( order_hash, "select" )) ) {
		defaultselhash = jsonNewObjectType(JSON_HASH);
		selhash = defaultselhash;
	}
	
	if ( !jsonObjectGetKeyConst(selhash,core_class) ) {
		jsonObjectSetKey( selhash, core_class, jsonNewObjectType(JSON_ARRAY) );
		jsonObject* flist = jsonObjectGetKey( selhash, core_class );
		
		int i = 0;
		char* field;

		osrfStringArray* keys = osrfHashKeys( fields );
		while ( (field = osrfStringArrayGetString(keys, i++)) ) {
			if ( strcasecmp( "true", osrfHashGet( osrfHashGet( fields, field ), "virtual" ) ) )
				jsonObjectPush( flist, jsonNewObject( field ) );
		}
		osrfStringArrayFree(keys);
	}

	int first = 1;
	jsonIterator* class_itr = jsonNewIterator( selhash );
	while ( (snode = jsonIteratorNext( class_itr )) ) {

		osrfHash* idlClass = osrfHashGet( oilsIDL(), class_itr->key );
		if (!idlClass) continue;
		char* cname = osrfHashGet(idlClass, "classname");

		if (strcmp(core_class,class_itr->key)) {
			if (!join_hash) continue;

			jsonObject* found =  jsonObjectFindPath(join_hash, "//%s", class_itr->key);
			if (!found->size) {
				jsonObjectFree(found);
				continue;
			}

			jsonObjectFree(found);
		}

		jsonIterator* select_itr = jsonNewIterator( snode );
		while ( (node = jsonIteratorNext( select_itr )) ) {
			char* item_str = jsonObjectToSimpleString(node);
			osrfHash* field = osrfHashGet( osrfHashGet( idlClass, "fields" ), item_str );
			free(item_str);
			char* fname = osrfHashGet(field, "name");

			if (!field) continue;

			if (first) {
				first = 0;
			} else {
				buffer_add(select_buf, ",");
			}

            if (locale) {
        		char* i18n = osrfHashGet(field, "i18n");
			    if ( !(
                        jsonBoolIsTrue( jsonObjectGetKey( order_hash, "no_i18n" ) ) ||
                        ((int)jsonObjectGetNumber(jsonObjectGetKey( order_hash, "no_i18n" ))) == 1 // support 1/0 for perl's sake
                     )
                ) i18n = NULL;

    			if ( i18n && !strncasecmp("true", i18n, 4)) {
        	        char* pkey = osrfHashGet(idlClass, "primarykey");
        	        char* tname = osrfHashGet(idlClass, "tablename");

                    buffer_fadd(select_buf, " oils_i18n_xlate('%s', '%s', '%s', '%s', \"%s\".%s::TEXT, '%s') AS \"%s\"", tname, cname, fname, pkey, cname, pkey, locale, fname);
                } else {
			        buffer_fadd(select_buf, " \"%s\".%s", cname, fname);
                }
            } else {
			    buffer_fadd(select_buf, " \"%s\".%s", cname, fname);
            }
		}

        jsonIteratorFree(select_itr);
	}

    jsonIteratorFree(class_itr);

	char* col_list = buffer_release(select_buf);
	char* table = getSourceDefinition(meta);

	buffer_fadd(sql_buf, "SELECT %s FROM %s AS \"%s\"", col_list, table, core_class );
	free(col_list);
	free(table);

	if ( join_hash ) {
		char* join_clause = searchJOIN( join_hash, meta );
		buffer_fadd(sql_buf, " %s", join_clause);
		free(join_clause);
	}

	char* tmpsql = buffer_data(sql_buf);
	osrfLogDebug(OSRF_LOG_MARK, "%s pre-predicate SQL =  %s", MODULENAME, tmpsql);
	free(tmpsql);

	buffer_add(sql_buf, " WHERE ");

	char* pred = searchWHERE( search_hash, meta, AND_OP_JOIN, ctx );
	if (!pred) {
		osrfAppSessionStatus(
			ctx->session,
			OSRF_STATUS_INTERNALSERVERERROR,
				"osrfMethodException",
				ctx->request,
				"Severe query error -- see error log for more details"
			);
		buffer_free(sql_buf);
		if(defaultselhash) jsonObjectFree(defaultselhash);
		return NULL;
	} else {
		buffer_add(sql_buf, pred);
		free(pred);
	}

	if (order_hash) {
		char* string = NULL;
		if ( (_tmp = jsonObjectGetKeyConst( order_hash, "order_by" )) ){

			growing_buffer* order_buf = buffer_init(128);

			first = 1;
			jsonIterator* class_itr = jsonNewIterator( _tmp );
			while ( (snode = jsonIteratorNext( class_itr )) ) {

				if (!jsonObjectGetKeyConst(selhash,class_itr->key))
					continue;

				if ( snode->type == JSON_HASH ) {

					jsonIterator* order_itr = jsonNewIterator( snode );
					while ( (onode = jsonIteratorNext( order_itr )) ) {

						if (!oilsIDLFindPath( "/%s/fields/%s", class_itr->key, order_itr->key ))
							continue;

						char* direction = NULL;
						if ( onode->type == JSON_HASH ) {
							if ( jsonObjectGetKeyConst( onode, "transform" ) ) {
								string = searchFieldTransform(
									class_itr->key,
									oilsIDLFindPath( "/%s/fields/%s", class_itr->key, order_itr->key ),
									onode
								);
							} else {
								growing_buffer* field_buf = buffer_init(16);
								buffer_fadd(field_buf, "\"%s\".%s", class_itr->key, order_itr->key);
								string = buffer_release(field_buf);
							}

							if ( (_tmp = jsonObjectGetKeyConst( onode, "direction" )) ) {
								direction = jsonObjectToSimpleString(_tmp);
								if (!strncasecmp(direction, "d", 1)) {
									free(direction);
									direction = " DESC";
								} else {
									free(direction);
									direction = " ASC";
								}
							}

						} else {
							string = strdup(order_itr->key);
							direction = jsonObjectToSimpleString(onode);
							if (!strncasecmp(direction, "d", 1)) {
								free(direction);
								direction = " DESC";
							} else {
								free(direction);
								direction = " ASC";
							}
						}

						if (first) {
							first = 0;
						} else {
							buffer_add(order_buf, ", ");
						}

						buffer_add(order_buf, string);
						free(string);

						if (direction) {
							buffer_add(order_buf, direction);
						}

					}

                    jsonIteratorFree(order_itr);

				} else {
					string = jsonObjectToSimpleString(snode);
					buffer_add(order_buf, string);
					free(string);
					break;
				}

			}

            jsonIteratorFree(class_itr);

			string = buffer_release(order_buf);

			if (strlen(string)) {
				buffer_fadd(
					sql_buf,
					" ORDER BY %s",
					string
				);
			}

			free(string);
		}

		if ( (_tmp = jsonObjectGetKeyConst( order_hash, "limit" )) ){
			string = jsonObjectToSimpleString(_tmp);
			buffer_fadd(
				sql_buf,
				" LIMIT %d",
				atoi(string)
			);
			free(string);
		}

		_tmp = jsonObjectGetKeyConst( order_hash, "offset" );
		if (_tmp) {
			string = jsonObjectToSimpleString(_tmp);
			buffer_fadd(
				sql_buf,
				" OFFSET %d",
				atoi(string)
			);
			free(string);
		}
	}

	if (defaultselhash) jsonObjectFree(defaultselhash);

	buffer_add(sql_buf, ";");
	return buffer_release(sql_buf);
}

int doJSONSearch ( osrfMethodContext* ctx ) {
	OSRF_METHOD_VERIFY_CONTEXT(ctx);
	osrfLogDebug(OSRF_LOG_MARK, "Recieved query request");

	int err = 0;

	// XXX for now...
	dbhandle = writehandle;

	jsonObject* hash = jsonObjectGetIndex(ctx->params, 0);

    int flags = 0;

	if (jsonBoolIsTrue(jsonObjectGetKey( hash, "distinct" )))
         flags |= SELECT_DISTINCT;

	if ( ((int)jsonObjectGetNumber(jsonObjectGetKey( hash, "distinct" ))) == 1 ) // support 1/0 for perl's sake
         flags |= SELECT_DISTINCT;

	if (jsonBoolIsTrue(jsonObjectGetKey( hash, "no_i18n" )))
         flags |= DISABLE_I18N;

	if ( ((int)jsonObjectGetNumber(jsonObjectGetKey( hash, "no_i18n" ))) == 1 ) // support 1/0 for perl's sake
         flags |= DISABLE_I18N;

	osrfLogDebug(OSRF_LOG_MARK, "Building SQL ...");
	char* sql = SELECT(
			ctx,
			jsonObjectGetKey( hash, "select" ),
			jsonObjectGetKey( hash, "from" ),
			jsonObjectGetKey( hash, "where" ),
			jsonObjectGetKey( hash, "having" ),
			jsonObjectGetKey( hash, "order_by" ),
			jsonObjectGetKey( hash, "limit" ),
			jsonObjectGetKey( hash, "offset" ),
			flags
	);

	if (!sql) {
		err = -1;
		return err;
	}
	
	osrfLogDebug(OSRF_LOG_MARK, "%s SQL =  %s", MODULENAME, sql);
	dbi_result result = dbi_conn_query(dbhandle, sql);

	if(result) {
		osrfLogDebug(OSRF_LOG_MARK, "Query returned with no errors");

		if (dbi_result_first_row(result)) {
			/* JSONify the result */
			osrfLogDebug(OSRF_LOG_MARK, "Query returned at least one row");

			do {
				jsonObject* return_val = oilsMakeJSONFromResult( result );
				osrfAppRespond( ctx, return_val );
                jsonObjectFree( return_val );
			} while (dbi_result_next_row(result));

		} else {
			osrfLogDebug(OSRF_LOG_MARK, "%s returned no results for query %s", MODULENAME, sql);
		}

		osrfAppRespondComplete( ctx, NULL );

		/* clean up the query */
		dbi_result_free(result); 

	} else {
		err = -1;
		osrfLogError(OSRF_LOG_MARK, "%s: Error with query [%s]", MODULENAME, sql);
		osrfAppSessionStatus(
			ctx->session,
			OSRF_STATUS_INTERNALSERVERERROR,
			"osrfMethodException",
			ctx->request,
			"Severe query error -- see error log for more details"
		);
	}

	free(sql);
	return err;
}

static jsonObject* doFieldmapperSearch ( osrfMethodContext* ctx, osrfHash* meta,
		const jsonObject* params, int* err ) {

	// XXX for now...
	dbhandle = writehandle;

	osrfHash* links = osrfHashGet(meta, "links");
	osrfHash* fields = osrfHashGet(meta, "fields");
	char* core_class = osrfHashGet(meta, "classname");
	char* pkey = osrfHashGet(meta, "primarykey");

	const jsonObject* _tmp;
	jsonObject* obj;
	jsonObject* search_hash = jsonObjectGetIndex(params, 0);
	jsonObject* order_hash = jsonObjectGetIndex(params, 1);

	char* sql = buildSELECT( search_hash, order_hash, meta, ctx );
	if (!sql) {
		*err = -1;
		return NULL;
	}
	
	osrfLogDebug(OSRF_LOG_MARK, "%s SQL =  %s", MODULENAME, sql);
	dbi_result result = dbi_conn_query(dbhandle, sql);

	jsonObject* res_list = jsonNewObjectType(JSON_ARRAY);
	if(result) {
		osrfLogDebug(OSRF_LOG_MARK, "Query returned with no errors");
		osrfHash* dedup = osrfNewHash();

		if (dbi_result_first_row(result)) {
			/* JSONify the result */
			osrfLogDebug(OSRF_LOG_MARK, "Query returned at least one row");
			do {
				obj = oilsMakeFieldmapperFromResult( result, meta );
				int pkey_pos = atoi( osrfHashGet( osrfHashGet( fields, pkey ), "array_position" ) );
				char* pkey_val = jsonObjectToSimpleString( jsonObjectGetIndex( obj, pkey_pos ) );
				if ( osrfHashGet( dedup, pkey_val ) ) {
					jsonObjectFree(obj);
					free(pkey_val);
				} else {
					osrfHashSet( dedup, pkey_val, pkey_val );
					jsonObjectPush(res_list, obj);
				}
			} while (dbi_result_next_row(result));
		} else {
			osrfLogDebug(OSRF_LOG_MARK, "%s returned no results for query %s", MODULENAME, sql);
		}

		osrfHashFree(dedup);

		/* clean up the query */
		dbi_result_free(result); 

	} else {
		osrfLogError(OSRF_LOG_MARK, "%s: Error retrieving %s with query [%s]", MODULENAME, osrfHashGet(meta, "fieldmapper"), sql);
		osrfAppSessionStatus(
			ctx->session,
			OSRF_STATUS_INTERNALSERVERERROR,
			"osrfMethodException",
			ctx->request,
			"Severe query error -- see error log for more details"
		);
		*err = -1;
		free(sql);
		jsonObjectFree(res_list);
		return jsonNULL;

	}

	free(sql);

	if (res_list->size && order_hash) {
		_tmp = jsonObjectGetKeyConst( order_hash, "flesh" );
		if (_tmp) {
			int x = (int)jsonObjectGetNumber(_tmp);
			if (x == -1 || x > max_flesh_depth) x = max_flesh_depth;

			const jsonObject* temp_blob;
			if ((temp_blob = jsonObjectGetKeyConst( order_hash, "flesh_fields" )) && x > 0) {

				jsonObject* flesh_blob = jsonObjectClone( temp_blob );
				const jsonObject* flesh_fields = jsonObjectGetKeyConst( flesh_blob, core_class );

				osrfStringArray* link_fields = NULL;

				if (flesh_fields) {
					if (flesh_fields->size == 1) {
						char* _t = jsonObjectToSimpleString( jsonObjectGetIndex( flesh_fields, 0 ) );
						if (!strcmp(_t,"*")) link_fields = osrfHashKeys( links );
						free(_t);
					}

					if (!link_fields) {
						jsonObject* _f;
						link_fields = osrfNewStringArray(1);
						jsonIterator* _i = jsonNewIterator( flesh_fields );
						while ((_f = jsonIteratorNext( _i ))) {
							osrfStringArrayAdd( link_fields, jsonObjectToSimpleString( _f ) );
						}
                        jsonIteratorFree(_i);
					}
				}

				jsonObject* cur;
				jsonIterator* itr = jsonNewIterator( res_list );
				while ((cur = jsonIteratorNext( itr ))) {

					int i = 0;
					char* link_field;
					
					while ( (link_field = osrfStringArrayGetString(link_fields, i++)) ) {

						osrfLogDebug(OSRF_LOG_MARK, "Starting to flesh %s", link_field);

						osrfHash* kid_link = osrfHashGet(links, link_field);
						if (!kid_link) continue;

						osrfHash* field = osrfHashGet(fields, link_field);
						if (!field) continue;

						osrfHash* value_field = field;

						osrfHash* kid_idl = osrfHashGet(oilsIDL(), osrfHashGet(kid_link, "class"));
						if (!kid_idl) continue;

						if (!(strcmp( osrfHashGet(kid_link, "reltype"), "has_many" ))) { // has_many
							value_field = osrfHashGet( fields, osrfHashGet(meta, "primarykey") );
						}
							
						if (!(strcmp( osrfHashGet(kid_link, "reltype"), "might_have" ))) { // might_have
							value_field = osrfHashGet( fields, osrfHashGet(meta, "primarykey") );
						}

						osrfStringArray* link_map = osrfHashGet( kid_link, "map" );

						if (link_map->size > 0) {
							jsonObject* _kid_key = jsonNewObjectType(JSON_ARRAY);
							jsonObjectPush(
								_kid_key,
								jsonNewObject( osrfStringArrayGetString( link_map, 0 ) )
							);

							jsonObjectSetKey(
								flesh_blob,
								osrfHashGet(kid_link, "class"),
								_kid_key
							);
						};

						osrfLogDebug(
							OSRF_LOG_MARK,
							"Link field: %s, remote class: %s, fkey: %s, reltype: %s",
							osrfHashGet(kid_link, "field"),
							osrfHashGet(kid_link, "class"),
							osrfHashGet(kid_link, "key"),
							osrfHashGet(kid_link, "reltype")
						);

						jsonObject* fake_params = jsonNewObjectType(JSON_ARRAY);
						jsonObjectPush(fake_params, jsonNewObjectType(JSON_HASH)); // search hash
						jsonObjectPush(fake_params, jsonNewObjectType(JSON_HASH)); // order/flesh hash

						osrfLogDebug(OSRF_LOG_MARK, "Creating dummy params object...");

						char* search_key =
						jsonObjectToSimpleString(
							jsonObjectGetIndex(
								cur,
								atoi( osrfHashGet(value_field, "array_position") )
							)
						);

						if (!search_key) {
							osrfLogDebug(OSRF_LOG_MARK, "Nothing to search for!");
							continue;
						}
							
						jsonObjectSetKey(
							jsonObjectGetIndex(fake_params, 0),
							osrfHashGet(kid_link, "key"),
							jsonNewObject( search_key )
						);

						free(search_key);


						jsonObjectSetKey(
							jsonObjectGetIndex(fake_params, 1),
							"flesh",
							jsonNewNumberObject( (double)(x - 1 + link_map->size) )
						);

						if (flesh_blob)
							jsonObjectSetKey( jsonObjectGetIndex(fake_params, 1), "flesh_fields", jsonObjectClone(flesh_blob) );

						if (jsonObjectGetKeyConst(order_hash, "order_by")) {
							jsonObjectSetKey(
								jsonObjectGetIndex(fake_params, 1),
								"order_by",
								jsonObjectClone(jsonObjectGetKeyConst(order_hash, "order_by"))
							);
						}

						if (jsonObjectGetKeyConst(order_hash, "select")) {
							jsonObjectSetKey(
								jsonObjectGetIndex(fake_params, 1),
								"select",
								jsonObjectClone(jsonObjectGetKeyConst(order_hash, "select"))
							);
						}

						jsonObject* kids = doFieldmapperSearch(ctx, kid_idl, fake_params, err);

						if(*err) {
							jsonObjectFree( fake_params );
							osrfStringArrayFree(link_fields);
							jsonIteratorFree(itr);
							jsonObjectFree(res_list);
							jsonObjectFree(flesh_blob);
							return jsonNULL;
						}

						osrfLogDebug(OSRF_LOG_MARK, "Search for %s return %d linked objects", osrfHashGet(kid_link, "class"), kids->size);

						jsonObject* X = NULL;
						if ( link_map->size > 0 && kids->size > 0 ) {
							X = kids;
							kids = jsonNewObjectType(JSON_ARRAY);

							jsonObject* _k_node;
							jsonIterator* _k = jsonNewIterator( X );
							while ((_k_node = jsonIteratorNext( _k ))) {
								jsonObjectPush(
									kids,
									jsonObjectClone(
										jsonObjectGetIndex(
											_k_node,
											(unsigned long)atoi(
												osrfHashGet(
													osrfHashGet(
														osrfHashGet(
															osrfHashGet(
																oilsIDL(),
																osrfHashGet(kid_link, "class")
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
							}
							jsonIteratorFree(_k);
						}

						if (!(strcmp( osrfHashGet(kid_link, "reltype"), "has_a" )) || !(strcmp( osrfHashGet(kid_link, "reltype"), "might_have" ))) {
							osrfLogDebug(OSRF_LOG_MARK, "Storing fleshed objects in %s", osrfHashGet(kid_link, "field"));
							jsonObjectSetIndex(
								cur,
								(unsigned long)atoi( osrfHashGet( field, "array_position" ) ),
								jsonObjectClone( jsonObjectGetIndex(kids, 0) )
							);
						}

						if (!(strcmp( osrfHashGet(kid_link, "reltype"), "has_many" ))) { // has_many
							osrfLogDebug(OSRF_LOG_MARK, "Storing fleshed objects in %s", osrfHashGet(kid_link, "field"));
							jsonObjectSetIndex(
								cur,
								(unsigned long)atoi( osrfHashGet( field, "array_position" ) ),
								jsonObjectClone( kids )
							);
						}

						if (X) {
							jsonObjectFree(kids);
							kids = X;
						}

						jsonObjectFree( kids );
						jsonObjectFree( fake_params );

						osrfLogDebug(OSRF_LOG_MARK, "Fleshing of %s complete", osrfHashGet(kid_link, "field"));
						osrfLogDebug(OSRF_LOG_MARK, "%s", jsonObjectToJSON(cur));

					}
				}
				jsonObjectFree( flesh_blob );
				osrfStringArrayFree(link_fields);
				jsonIteratorFree(itr);
			}
		}
	}

	return res_list;
}


static jsonObject* doUpdate(osrfMethodContext* ctx, int* err ) {

	osrfHash* meta = osrfHashGet( (osrfHash*) ctx->method->userData, "class" );
	jsonObject* target = jsonObjectGetIndex(ctx->params, 0);

	if (!verifyObjectClass(ctx, target)) {
		*err = -1;
		return jsonNULL;
	}

	if (!osrfHashGet( (osrfHash*)ctx->session->userData, "xact_id" )) {
		osrfAppSessionStatus(
			ctx->session,
			OSRF_STATUS_BADREQUEST,
			"osrfMethodException",
			ctx->request,
			"No active transaction -- required for UPDATE"
		);
		*err = -1;
		return jsonNULL;
	}

	if (osrfHashGet( meta, "readonly" ) && strncasecmp("true", osrfHashGet( meta, "readonly" ), 4)) {
		osrfAppSessionStatus(
			ctx->session,
			OSRF_STATUS_BADREQUEST,
			"osrfMethodException",
			ctx->request,
			"Cannot UPDATE readonly class"
		);
		*err = -1;
		return jsonNULL;
	}

	dbhandle = writehandle;

	char* trans_id = osrfHashGet( (osrfHash*)ctx->session->userData, "xact_id" );

        // Set the last_xact_id
	osrfHash* last_xact_id;
	if ((last_xact_id = oilsIDLFindPath("/%s/fields/last_xact_id", target->classname))) {
		int index = atoi( osrfHashGet(last_xact_id, "array_position") );
		osrfLogDebug(OSRF_LOG_MARK, "Setting last_xact_id to %s on %s at position %d", trans_id, target->classname, index);
		jsonObjectSetIndex(target, index, jsonNewObject(trans_id));
	}       

	char* pkey = osrfHashGet(meta, "primarykey");
	osrfHash* fields = osrfHashGet(meta, "fields");

	char* id =
		jsonObjectToSimpleString(
			jsonObjectGetIndex(
				target,
				atoi( osrfHashGet( osrfHashGet( fields, pkey ), "array_position" ) )
			)
		);

	osrfLogDebug(
		OSRF_LOG_MARK,
		"%s updating %s object with %s = %s",
		MODULENAME,
		osrfHashGet(meta, "fieldmapper"),
		pkey,
		id
	);

	growing_buffer* sql = buffer_init(128);
	buffer_fadd(sql,"UPDATE %s SET", osrfHashGet(meta, "tablename"));

	int i = 0;
	int first = 1;
	char* field_name;
	osrfStringArray* field_list = osrfHashKeys( fields );
	while ( (field_name = osrfStringArrayGetString(field_list, i++)) ) {

		osrfHash* field = osrfHashGet( fields, field_name );

		if(!( strcmp( field_name, pkey ) )) continue;
		if(!( strcmp( osrfHashGet(osrfHashGet(fields,field_name), "virtual"), "true" ) )) continue;

		jsonObject* field_object = jsonObjectGetIndex( target, atoi(osrfHashGet(field, "array_position")) );

		char* value;
		if (field_object && field_object->classname) {
			value = jsonObjectToSimpleString(
					jsonObjectGetIndex(
						field_object,
						atoi(
							osrfHashGet(
								osrfHashGet(
									oilsIDLFindPath("/%s/fields", field_object->classname),
									(char*)oilsIDLFindPath("/%s/primarykey", field_object->classname)
								),
								"array_position"
							)
						)
					)
				);

		} else {
			value = jsonObjectToSimpleString( field_object );
		}

		osrfLogDebug( OSRF_LOG_MARK, "Updating %s object with %s = %s", osrfHashGet(meta, "fieldmapper"), field_name, value);

		if (!field_object || field_object->type == JSON_NULL) {
			if ( !(!( strcmp( osrfHashGet(meta, "classname"), "au" ) ) && !( strcmp( field_name, "passwd" ) )) ) { // arg at the special case!
				if (first) first = 0;
				else buffer_add(sql, ",");
				buffer_fadd( sql, " %s = NULL", field_name );
			}
			
		} else if ( !strcmp(osrfHashGet(field, "primitive"), "number") ) {
			if (first) first = 0;
			else buffer_add(sql, ",");

			if ( !strncmp(osrfHashGet(field, "datatype"), "INT", (size_t)3) ) {
				buffer_fadd( sql, " %s = %ld", field_name, atol(value) );
			} else if ( !strcmp(osrfHashGet(field, "datatype"), "NUMERIC") ) {
				buffer_fadd( sql, " %s = %f", field_name, atof(value) );
			}

			osrfLogDebug( OSRF_LOG_MARK, "%s is of type %s", field_name, osrfHashGet(field, "datatype"));

		} else {
			if ( dbi_conn_quote_string(dbhandle, &value) ) {
				if (first) first = 0;
				else buffer_add(sql, ",");
				buffer_fadd( sql, " %s = %s", field_name, value );

			} else {
				osrfLogError(OSRF_LOG_MARK, "%s: Error quoting string [%s]", MODULENAME, value);
				osrfAppSessionStatus(
					ctx->session,
					OSRF_STATUS_INTERNALSERVERERROR,
					"osrfMethodException",
					ctx->request,
					"Error quoting string -- please see the error log for more details"
				);
				free(value);
				free(id);
				buffer_free(sql);
				*err = -1;
				return jsonNULL;
			}
		}

		free(value);
		
	}

	jsonObject* obj = jsonParseString(id);

	if ( strcmp( osrfHashGet( osrfHashGet( osrfHashGet(meta, "fields"), pkey ), "primitive" ), "number" ) )
		dbi_conn_quote_string(dbhandle, &id);

	buffer_fadd( sql, " WHERE %s = %s;", pkey, id );

	char* query = buffer_release(sql);
	osrfLogDebug(OSRF_LOG_MARK, "%s: Update SQL [%s]", MODULENAME, query);

	dbi_result result = dbi_conn_query(dbhandle, query);
	free(query);

	if (!result) {
		jsonObjectFree(obj);
		obj = jsonNewObject(NULL);
		osrfLogError(
			OSRF_LOG_MARK,
			"%s ERROR updating %s object with %s = %s",
			MODULENAME,
			osrfHashGet(meta, "fieldmapper"),
			pkey,
			id
		);
	}

	free(id);

	return obj;
}

static jsonObject* doDelete(osrfMethodContext* ctx, int* err ) {

	osrfHash* meta = osrfHashGet( (osrfHash*) ctx->method->userData, "class" );

	if (!osrfHashGet( (osrfHash*)ctx->session->userData, "xact_id" )) {
		osrfAppSessionStatus(
			ctx->session,
			OSRF_STATUS_BADREQUEST,
			"osrfMethodException",
			ctx->request,
			"No active transaction -- required for DELETE"
		);
		*err = -1;
		return jsonNULL;
	}

	if (osrfHashGet( meta, "readonly" ) && strncasecmp("true", osrfHashGet( meta, "readonly" ), 4)) {
		osrfAppSessionStatus(
			ctx->session,
			OSRF_STATUS_BADREQUEST,
			"osrfMethodException",
			ctx->request,
			"Cannot DELETE readonly class"
		);
		*err = -1;
		return jsonNULL;
	}

	dbhandle = writehandle;

	jsonObject* obj;

	char* pkey = osrfHashGet(meta, "primarykey");

	char* id;
	if (jsonObjectGetIndex(ctx->params, 0)->classname) {
		if (!verifyObjectClass(ctx, jsonObjectGetIndex( ctx->params, 0 ))) {
			*err = -1;
			return jsonNULL;
		}

		id = jsonObjectToSimpleString(
			jsonObjectGetIndex(
				jsonObjectGetIndex(ctx->params, 0),
				atoi( osrfHashGet( osrfHashGet( osrfHashGet(meta, "fields"), pkey ), "array_position") )
			)
		);
	} else {
		id = jsonObjectToSimpleString(jsonObjectGetIndex(ctx->params, 0));
	}

	osrfLogDebug(
		OSRF_LOG_MARK,
		"%s deleting %s object with %s = %s",
		MODULENAME,
		osrfHashGet(meta, "fieldmapper"),
		pkey,
		id
	);

	obj = jsonParseString(id);

	if ( strcmp( osrfHashGet( osrfHashGet( osrfHashGet(meta, "fields"), pkey ), "primitive" ), "number" ) )
		dbi_conn_quote_string(writehandle, &id);

	dbi_result result = dbi_conn_queryf(writehandle, "DELETE FROM %s WHERE %s = %s;", osrfHashGet(meta, "tablename"), pkey, id);

	if (!result) {
		jsonObjectFree(obj);
		obj = jsonNewObject(NULL);
		osrfLogError(
			OSRF_LOG_MARK,
			"%s ERROR deleting %s object with %s = %s",
			MODULENAME,
			osrfHashGet(meta, "fieldmapper"),
			pkey,
			id
		);
	}

	free(id);

	return obj;

}


static jsonObject* oilsMakeFieldmapperFromResult( dbi_result result, osrfHash* meta) {
	if(!(result && meta)) return jsonNULL;

	jsonObject* object = jsonNewObject(NULL);
	jsonObjectSetClass(object, osrfHashGet(meta, "classname"));

	osrfHash* fields = osrfHashGet(meta, "fields");

	osrfLogInternal(OSRF_LOG_MARK, "Setting object class to %s ", object->classname);

	osrfHash* _f;
	time_t _tmp_dt;
	char dt_string[256];
	struct tm gmdt;

	int fmIndex;
	int columnIndex = 1;
	int attr;
	unsigned short type;
	const char* columnName;

	/* cycle through the column list */
	while( (columnName = dbi_result_get_field_name(result, columnIndex++)) ) {

		osrfLogInternal(OSRF_LOG_MARK, "Looking for column named [%s]...", (char*)columnName);

		fmIndex = -1; // reset the position
		
		/* determine the field type and storage attributes */
		type = dbi_result_get_field_type(result, columnName);
		attr = dbi_result_get_field_attribs(result, columnName);

		/* fetch the fieldmapper index */
		if( (_f = osrfHashGet(fields, (char*)columnName)) ) {
			char* virt = (char*)osrfHashGet(_f, "virtual");
			char* pos = (char*)osrfHashGet(_f, "array_position");

			if ( !virt || !pos || !(strcmp( virt, "true" )) ) continue;

			fmIndex = atoi( pos );
			osrfLogInternal(OSRF_LOG_MARK, "... Found column at position [%s]...", pos);
		} else {
			continue;
		}

		if (dbi_result_field_is_null(result, columnName)) {
			jsonObjectSetIndex( object, fmIndex, jsonNewObject(NULL) );
		} else {

			switch( type ) {

				case DBI_TYPE_INTEGER :

					if( attr & DBI_INTEGER_SIZE8 ) 
						jsonObjectSetIndex( object, fmIndex, 
							jsonNewNumberObject(dbi_result_get_longlong(result, columnName)));
					else 
						jsonObjectSetIndex( object, fmIndex, 
							jsonNewNumberObject(dbi_result_get_int(result, columnName)));

					break;

				case DBI_TYPE_DECIMAL :
					jsonObjectSetIndex( object, fmIndex, 
							jsonNewNumberObject(dbi_result_get_double(result, columnName)));
					break;

				case DBI_TYPE_STRING :


					jsonObjectSetIndex(
						object,
						fmIndex,
						jsonNewObject( dbi_result_get_string(result, columnName) )
					);

					break;

				case DBI_TYPE_DATETIME :

					memset(dt_string, '\0', sizeof(dt_string));
					memset(&gmdt, '\0', sizeof(gmdt));

					_tmp_dt = dbi_result_get_datetime(result, columnName);


					if (!(attr & DBI_DATETIME_DATE)) {
						gmtime_r( &_tmp_dt, &gmdt );
						strftime(dt_string, sizeof(dt_string), "%T", &gmdt);
					} else if (!(attr & DBI_DATETIME_TIME)) {
						localtime_r( &_tmp_dt, &gmdt );
						strftime(dt_string, sizeof(dt_string), "%F", &gmdt);
					} else {
						localtime_r( &_tmp_dt, &gmdt );
						strftime(dt_string, sizeof(dt_string), "%FT%T%z", &gmdt);
					}

					jsonObjectSetIndex( object, fmIndex, jsonNewObject(dt_string) );

					break;

				case DBI_TYPE_BINARY :
					osrfLogError( OSRF_LOG_MARK, 
						"Can't do binary at column %s : index %d", columnName, columnIndex - 1);
			}
		}
	}

	return object;
}

static jsonObject* oilsMakeJSONFromResult( dbi_result result ) {
	if(!result) return jsonNULL;

	jsonObject* object = jsonNewObject(NULL);

	time_t _tmp_dt;
	char dt_string[256];
	struct tm gmdt;

	int fmIndex;
	int columnIndex = 1;
	int attr;
	unsigned short type;
	const char* columnName;

	/* cycle through the column list */
	while( (columnName = dbi_result_get_field_name(result, columnIndex++)) ) {

		osrfLogInternal(OSRF_LOG_MARK, "Looking for column named [%s]...", (char*)columnName);

		fmIndex = -1; // reset the position
		
		/* determine the field type and storage attributes */
		type = dbi_result_get_field_type(result, columnName);
		attr = dbi_result_get_field_attribs(result, columnName);

		if (dbi_result_field_is_null(result, columnName)) {
			jsonObjectSetKey( object, columnName, jsonNewObject(NULL) );
		} else {

			switch( type ) {

				case DBI_TYPE_INTEGER :

					if( attr & DBI_INTEGER_SIZE8 ) 
						jsonObjectSetKey( object, columnName, jsonNewNumberObject(dbi_result_get_longlong(result, columnName)) );
					else 
						jsonObjectSetKey( object, columnName, jsonNewNumberObject(dbi_result_get_int(result, columnName)) );
					break;

				case DBI_TYPE_DECIMAL :
					jsonObjectSetKey( object, columnName, jsonNewNumberObject(dbi_result_get_double(result, columnName)) );
					break;

				case DBI_TYPE_STRING :
					jsonObjectSetKey( object, columnName, jsonNewObject(dbi_result_get_string(result, columnName)) );
					break;

				case DBI_TYPE_DATETIME :

					memset(dt_string, '\0', sizeof(dt_string));
					memset(&gmdt, '\0', sizeof(gmdt));

					_tmp_dt = dbi_result_get_datetime(result, columnName);


					if (!(attr & DBI_DATETIME_DATE)) {
						gmtime_r( &_tmp_dt, &gmdt );
						strftime(dt_string, sizeof(dt_string), "%T", &gmdt);
					} else if (!(attr & DBI_DATETIME_TIME)) {
						localtime_r( &_tmp_dt, &gmdt );
						strftime(dt_string, sizeof(dt_string), "%F", &gmdt);
					} else {
						localtime_r( &_tmp_dt, &gmdt );
						strftime(dt_string, sizeof(dt_string), "%FT%T%z", &gmdt);
					}

					jsonObjectSetKey( object, columnName, jsonNewObject(dt_string) );
					break;

				case DBI_TYPE_BINARY :
					osrfLogError( OSRF_LOG_MARK, 
						"Can't do binary at column %s : index %d", columnName, columnIndex - 1);
			}
		}
	}

	return object;
}

