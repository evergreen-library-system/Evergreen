#include <ctype.h>
#include "opensrf/osrf_application.h"
#include "opensrf/osrf_settings.h"
#include "opensrf/osrf_message.h"
#include "opensrf/utils.h"
#include "opensrf/osrf_json.h"
#include "opensrf/log.h"
#include "openils/oils_utils.h"
#include <dbi/dbi.h>

#include <time.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#ifdef RSTORE
#  define MODULENAME "open-ils.reporter-store"
#else
#  ifdef PCRUD
#    define MODULENAME "open-ils.pcrud"
#  else
#    define MODULENAME "open-ils.cstore"
#  endif
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
static jsonObject* doFieldmapperSearch ( osrfMethodContext* ctx, osrfHash* meta,
		jsonObject* where_hash, jsonObject* query_hash, int* err );
static jsonObject* oilsMakeFieldmapperFromResult( dbi_result, osrfHash* );
static jsonObject* oilsMakeJSONFromResult( dbi_result );

static char* searchSimplePredicate ( const char* op, const char* class, 
				osrfHash* field, const jsonObject* node );
static char* searchFunctionPredicate ( const char*, osrfHash*, const jsonObject*, const char* );
static char* searchFieldTransform ( const char*, osrfHash*, const jsonObject*);
static char* searchFieldTransformPredicate ( const char*, osrfHash*, const jsonObject*, const char* );
static char* searchBETWEENPredicate ( const char*, osrfHash*, const jsonObject* );
static char* searchINPredicate ( const char*, osrfHash*,
								 jsonObject*, const char*, osrfMethodContext* );
static char* searchPredicate ( const char*, osrfHash*, jsonObject*, osrfMethodContext* );
static char* searchJOIN ( const jsonObject*, osrfHash* );
static char* searchWHERE ( const jsonObject*, osrfHash*, int, osrfMethodContext* );
static char* buildSELECT ( jsonObject*, jsonObject*, osrfHash*, osrfMethodContext* );

char* SELECT ( osrfMethodContext*, jsonObject*, jsonObject*, jsonObject*, jsonObject*, jsonObject*, jsonObject*, jsonObject*, int );

void userDataFree( void* );
static void sessionDataFree( char*, void* );
static char* getSourceDefinition( osrfHash* );
static int str_is_true( const char* str );
static int obj_is_true( const jsonObject* obj );
static const char* json_type( int code );
static const char* get_primitive( osrfHash* field );
static const char* get_datatype( osrfHash* field );
static int is_identifier( const char* s);
static int is_good_operator( const char* op );

#ifdef PCRUD
static jsonObject* verifyUserPCRUD( osrfMethodContext* );
static int verifyObjectPCRUD( osrfMethodContext*, const jsonObject* );
static jsonObject* single_hash( const char* key, const char* value );
#endif

static int child_initialized = 0;   /* boolean */

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

    osrfLogInfo(OSRF_LOG_MARK, "Initializing the CStore Server...");
    osrfLogInfo(OSRF_LOG_MARK, "Finding XML file...");

    if (!oilsIDLInit( osrf_settings_host_value("/IDL") )) return 1; /* return non-zero to indicate error */

    growing_buffer* method_name = buffer_init(64);
#ifndef PCRUD
    // Generic search thingy
    buffer_add(method_name, MODULENAME);
	buffer_add(method_name, ".json_query");
	osrfAppRegisterMethod( MODULENAME, OSRF_BUFFER_C_STR(method_name),
						   "doJSONSearch", "", 1, OSRF_METHOD_STREAMING );
#endif

    // first we register all the transaction and savepoint methods
    buffer_reset(method_name);
	OSRF_BUFFER_ADD(method_name, MODULENAME);
	OSRF_BUFFER_ADD(method_name, ".transaction.begin");
	osrfAppRegisterMethod( MODULENAME, OSRF_BUFFER_C_STR(method_name),
						   "beginTransaction", "", 0, 0 );

    buffer_reset(method_name);
	OSRF_BUFFER_ADD(method_name, MODULENAME);
	OSRF_BUFFER_ADD(method_name, ".transaction.commit");
	osrfAppRegisterMethod( MODULENAME, OSRF_BUFFER_C_STR(method_name),
						   "commitTransaction", "", 0, 0 );

    buffer_reset(method_name);
	OSRF_BUFFER_ADD(method_name, MODULENAME);
	OSRF_BUFFER_ADD(method_name, ".transaction.rollback");
	osrfAppRegisterMethod( MODULENAME, OSRF_BUFFER_C_STR(method_name),
						   "rollbackTransaction", "", 0, 0 );

    buffer_reset(method_name);
	OSRF_BUFFER_ADD(method_name, MODULENAME);
	OSRF_BUFFER_ADD(method_name, ".savepoint.set");
	osrfAppRegisterMethod( MODULENAME, OSRF_BUFFER_C_STR(method_name),
						   "setSavepoint", "", 1, 0 );

    buffer_reset(method_name);
	OSRF_BUFFER_ADD(method_name, MODULENAME);
	OSRF_BUFFER_ADD(method_name, ".savepoint.release");
	osrfAppRegisterMethod( MODULENAME, OSRF_BUFFER_C_STR(method_name),
						   "releaseSavepoint", "", 1, 0 );

    buffer_reset(method_name);
	OSRF_BUFFER_ADD(method_name, MODULENAME);
	OSRF_BUFFER_ADD(method_name, ".savepoint.rollback");
	osrfAppRegisterMethod( MODULENAME, OSRF_BUFFER_C_STR(method_name),
						   "rollbackSavepoint", "", 1, 0 );

    buffer_free(method_name);

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
	
    int c_index = 0; 
    char* classname;
    osrfStringArray* classes = osrfHashKeys( oilsIDL() );
    osrfLogDebug(OSRF_LOG_MARK, "%d classes loaded", classes->size );
    osrfLogDebug(OSRF_LOG_MARK,
		"At least %d methods will be generated", classes->size * global_method_count);

    while ( (classname = osrfStringArrayGetString(classes, c_index++)) ) {
        osrfLogInfo(OSRF_LOG_MARK, "Generating class methods for %s", classname);

        osrfHash* idlClass = osrfHashGet(oilsIDL(), classname);

        if (!osrfStringArrayContains( osrfHashGet(idlClass, "controller"), MODULENAME )) {
            osrfLogInfo(OSRF_LOG_MARK, "%s is not listed as a controller for %s, moving on", MODULENAME, classname);
            continue;
        }

		if ( str_is_true( osrfHashGet(idlClass, "virtual") ) ) {
			osrfLogDebug(OSRF_LOG_MARK, "Class %s is virtual, skipping", classname );
			continue;
		}

        // Look up some other attributes of the current class
        const char* idlClass_fieldmapper = osrfHashGet(idlClass, "fieldmapper");
		const char* readonly = osrfHashGet(idlClass, "readonly");
#ifdef PCRUD
        osrfHash* idlClass_permacrud = osrfHashGet(idlClass, "permacrud");
#endif

        int i;
        for( i = 0; i < global_method_count; ++i ) {
            const char* method_type = global_method[ i ];
            osrfLogDebug(OSRF_LOG_MARK,
                "Using files to build %s class methods for %s", method_type, classname);

            if (!idlClass_fieldmapper) continue;

#ifdef PCRUD
            if (!idlClass_permacrud) continue;

            const char* tmp_method = method_type;
            if ( *tmp_method == 'i' || *tmp_method == 's') {
                tmp_method = "retrieve";
            }
            if (!osrfHashGet( idlClass_permacrud, tmp_method )) continue;
#endif

            if (    str_is_true( readonly ) &&
                    ( *method_type == 'c' || *method_type == 'u' || *method_type == 'd')
               ) continue;

            osrfHash* method_meta = osrfNewHash();
            osrfHashSet(method_meta, idlClass, "class");

            method_name =  buffer_init(64);
#ifdef PCRUD
            buffer_fadd(method_name, "%s.%s.%s", MODULENAME, method_type, classname);
#else
            char* st_tmp = NULL;
            char* part = NULL;
            char* _fm = strdup( idlClass_fieldmapper );
            part = strtok_r(_fm, ":", &st_tmp);

            buffer_fadd(method_name, "%s.direct.%s", MODULENAME, part);

            while ((part = strtok_r(NULL, ":", &st_tmp))) {
				OSRF_BUFFER_ADD_CHAR(method_name, '.');
				OSRF_BUFFER_ADD(method_name, part);
            }
			OSRF_BUFFER_ADD_CHAR(method_name, '.');
			OSRF_BUFFER_ADD(method_name, method_type);
            free(_fm);
#endif

            char* method = buffer_release(method_name);

            osrfHashSet( method_meta, method, "methodname" );
            osrfHashSet( method_meta, strdup(method_type), "methodtype" );

            int flags = 0;
            if (*method_type == 'i' || *method_type == 's') {
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

    return 0;
}

static char* getSourceDefinition( osrfHash* class ) {

	char* tabledef = osrfHashGet(class, "tablename");

	if (tabledef) {
		tabledef = strdup(tabledef);
	} else {
		tabledef = osrfHashGet(class, "source_definition");
		if( tabledef ) {
			growing_buffer* tablebuf = buffer_init(128);
			buffer_fadd( tablebuf, "(%s)", tabledef );
			tabledef = buffer_release(tablebuf);
		} else {
			const char* classname = osrfHashGet( class, "classname" );
			if( !classname )
				classname = "???";
			osrfLogError(
				OSRF_LOG_MARK,
				"%s ERROR No tablename or source_definition for class \"%s\"",
				MODULENAME,
				classname
			);
		}
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

    unsigned short type;
    int i = 0; 
    char* classname;
    osrfStringArray* classes = osrfHashKeys( oilsIDL() );

    while ( (classname = osrfStringArrayGetString(classes, i++)) ) {
        osrfHash* class = osrfHashGet( oilsIDL(), classname );
        osrfHash* fields = osrfHashGet( class, "fields" );

		if( str_is_true( osrfHashGet(class, "virtual") ) ) {
			osrfLogDebug(OSRF_LOG_MARK, "Class %s is virtual, skipping", classname );
			continue;
		}

        char* tabledef = getSourceDefinition(class);
		if( !tabledef )
			tabledef = strdup( "(null)" );

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

                    switch( type ) {

						case DBI_TYPE_INTEGER : {

							if ( !osrfHashGet(_f, "primitive") )
								osrfHashSet(_f,"number", "primitive");

							int attr = dbi_result_get_field_attribs(result, columnName);
							if( attr & DBI_INTEGER_SIZE8 ) 
								osrfHashSet(_f,"INT8", "datatype");
							else 
								osrfHashSet(_f,"INT", "datatype");
							break;
						}
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

	child_initialized = 1;
    return 0;
}

/*
  This function is a sleazy hack intended *only* for testing and
  debugging.  Any real server process should initialize the 
  database connection by calling osrfAppChildInit().
*/
void set_cstore_dbi_conn( dbi_conn conn ) {
	dbhandle = writehandle = conn;
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
	if(osrfMethodVerifyContext( ctx )) {
		osrfLogError( OSRF_LOG_MARK,  "Invalid method context" );
		return -1;
	}

#ifdef PCRUD
    jsonObject* user = verifyUserPCRUD( ctx );
    if (!user) return -1;
    jsonObjectFree(user);
#endif

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
	if(osrfMethodVerifyContext( ctx )) {
		osrfLogError( OSRF_LOG_MARK,  "Invalid method context" );
		return -1;
	}

    int spNamePos = 0;
#ifdef PCRUD
    spNamePos = 1;
    jsonObject* user = verifyUserPCRUD( ctx );
    if (!user) return -1;
    jsonObjectFree(user);
#endif

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

	const char* spName = jsonObjectGetString(jsonObjectGetIndex(ctx->params, spNamePos));

	dbi_result result = dbi_conn_queryf(writehandle, "SAVEPOINT \"%s\";", spName);
	if (!result) {
		osrfLogError(
			OSRF_LOG_MARK,
			"%s: Error creating savepoint %s in transaction %s",
			MODULENAME,
			spName,
			osrfHashGet( (osrfHash*)ctx->session->userData, "xact_id" )
		);
		osrfAppSessionStatus( ctx->session, OSRF_STATUS_INTERNALSERVERERROR, 
				"osrfMethodException", ctx->request, "Error creating savepoint" );
		return -1;
	} else {
		jsonObject* ret = jsonNewObject(spName);
		osrfAppRespondComplete( ctx, ret );
		jsonObjectFree(ret);
	}
	return 0;
}

int releaseSavepoint ( osrfMethodContext* ctx ) {
	if(osrfMethodVerifyContext( ctx )) {
		osrfLogError( OSRF_LOG_MARK,  "Invalid method context" );
		return -1;
	}

	int spNamePos = 0;
#ifdef PCRUD
    spNamePos = 1;
    jsonObject* user = verifyUserPCRUD( ctx );
    if (!user) return -1;
    jsonObjectFree(user);
#endif

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

	const char* spName = jsonObjectGetString( jsonObjectGetIndex(ctx->params, spNamePos) );

    dbi_result result = dbi_conn_queryf(writehandle, "RELEASE SAVEPOINT \"%s\";", spName);
    if (!result) {
        osrfLogError(
                OSRF_LOG_MARK,
                "%s: Error releasing savepoint %s in transaction %s",
                MODULENAME,
                spName,
                osrfHashGet( (osrfHash*)ctx->session->userData, "xact_id" )
                );
		osrfAppSessionStatus( ctx->session, OSRF_STATUS_INTERNALSERVERERROR,
				"osrfMethodException", ctx->request, "Error releasing savepoint" );
        return -1;
    } else {
        jsonObject* ret = jsonNewObject(spName);
        osrfAppRespondComplete( ctx, ret );
        jsonObjectFree(ret);
    }
    return 0;
}

int rollbackSavepoint ( osrfMethodContext* ctx ) {
	if(osrfMethodVerifyContext( ctx )) {
		osrfLogError( OSRF_LOG_MARK,  "Invalid method context" );
		return -1;
	}

	int spNamePos = 0;
#ifdef PCRUD
    spNamePos = 1;
    jsonObject* user = verifyUserPCRUD( ctx );
    if (!user) return -1;
    jsonObjectFree(user);
#endif

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

	const char* spName = jsonObjectGetString( jsonObjectGetIndex(ctx->params, spNamePos) );

    dbi_result result = dbi_conn_queryf(writehandle, "ROLLBACK TO SAVEPOINT \"%s\";", spName);
    if (!result) {
        osrfLogError(
                OSRF_LOG_MARK,
                "%s: Error rolling back savepoint %s in transaction %s",
                MODULENAME,
                spName,
                osrfHashGet( (osrfHash*)ctx->session->userData, "xact_id" )
                );
		osrfAppSessionStatus( ctx->session, OSRF_STATUS_INTERNALSERVERERROR, 
				"osrfMethodException", ctx->request, "Error rolling back savepoint" );
        return -1;
    } else {
        jsonObject* ret = jsonNewObject(spName);
        osrfAppRespondComplete( ctx, ret );
        jsonObjectFree(ret);
    }
    return 0;
}

int commitTransaction ( osrfMethodContext* ctx ) {
	if(osrfMethodVerifyContext( ctx )) {
		osrfLogError( OSRF_LOG_MARK,  "Invalid method context" );
		return -1;
	}

#ifdef PCRUD
    jsonObject* user = verifyUserPCRUD( ctx );
    if (!user) return -1;
    jsonObjectFree(user);
#endif

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
	if(osrfMethodVerifyContext( ctx )) {
		osrfLogError( OSRF_LOG_MARK,  "Invalid method context" );
		return -1;
	}

#ifdef PCRUD
    jsonObject* user = verifyUserPCRUD( ctx );
    if (!user) return -1;
    jsonObjectFree(user);
#endif

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
	if(osrfMethodVerifyContext( ctx )) {
		osrfLogError( OSRF_LOG_MARK,  "Invalid method context" );
		return -1;
	}

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

		jsonObject* where_clause;
		jsonObject* rest_of_query;

#ifdef PCRUD
		where_clause  = jsonObjectGetIndex( ctx->params, 1 );
		rest_of_query = jsonObjectGetIndex( ctx->params, 2 );
#else
		where_clause  = jsonObjectGetIndex( ctx->params, 0 );
		rest_of_query = jsonObjectGetIndex( ctx->params, 1 );
#endif

		obj = doFieldmapperSearch( ctx, class_obj, where_clause, rest_of_query, &err );

        if(err) return err;

        jsonObject* cur;
        jsonIterator* itr = jsonNewIterator( obj );
        while ((cur = jsonIteratorNext( itr ))) {
#ifdef PCRUD
            if(!verifyObjectPCRUD(ctx, cur)) continue;
#endif
            osrfAppRespond( ctx, cur );
        }
        jsonIteratorFree(itr);
        osrfAppRespondComplete( ctx, NULL );

    } else if (!strcmp(methodtype, "id_list")) {

		jsonObject* where_clause;
		jsonObject* rest_of_query;

		// We use the where clause without change.  But we need
		// to massage the rest of the query, so we work with a copy
		// of it instead of modifying the original.
#ifdef PCRUD
		where_clause  = jsonObjectGetIndex( ctx->params, 1 );
		rest_of_query = jsonObjectClone( jsonObjectGetIndex( ctx->params, 2 ) );
#else
		where_clause  = jsonObjectGetIndex( ctx->params, 0 );
		rest_of_query = jsonObjectClone( jsonObjectGetIndex( ctx->params, 1 ) );
#endif

		if ( rest_of_query ) {
			jsonObjectRemoveKey( rest_of_query, "select" );
			jsonObjectRemoveKey( rest_of_query, "no_i18n" );
			jsonObjectRemoveKey( rest_of_query, "flesh" );
			jsonObjectRemoveKey( rest_of_query, "flesh_columns" );
		} else {
			rest_of_query = jsonNewObjectType( JSON_HASH );
		}

		jsonObjectSetKey( rest_of_query, "no_i18n", jsonNewBoolObject( 1 ) );

		jsonObjectSetKey(
			rest_of_query,
            "select",
            jsonParseStringFmt(
                "{ \"%s\":[\"%s\"] }",
                osrfHashGet( class_obj, "classname" ),
                osrfHashGet( class_obj, "primarykey" )
            )
        );

		obj = doFieldmapperSearch( ctx, class_obj, where_clause, rest_of_query, &err );

		jsonObjectFree( rest_of_query );
		if(err) return err;

        jsonObject* cur;
        jsonIterator* itr = jsonNewIterator( obj );
        while ((cur = jsonIteratorNext( itr ))) {
#ifdef PCRUD
            if(!verifyObjectPCRUD(ctx, cur)) continue;
#endif
            osrfAppRespond(
                    ctx,
                    oilsFMGetObject( cur, osrfHashGet( class_obj, "primarykey" ) )
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

    int ret = 1;
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

#ifdef PCRUD
    ret = verifyObjectPCRUD( ctx, param );
#endif

    return ret;
}

#ifdef PCRUD

static jsonObject* verifyUserPCRUD( osrfMethodContext* ctx ) {
	const char* auth = jsonObjectGetString( jsonObjectGetIndex( ctx->params, 0 ) );
    jsonObject* auth_object = jsonNewObject(auth);
    jsonObject* user = oilsUtilsQuickReq("open-ils.auth","open-ils.auth.session.retrieve", auth_object);
    jsonObjectFree(auth_object);

    if (!user->classname || strcmp(user->classname, "au")) {

        growing_buffer* msg = buffer_init(128);
        buffer_fadd(
            msg,
            "%s: permacrud received a bad auth token: %s",
            MODULENAME,
            auth
        );

        char* m = buffer_release(msg);
        osrfAppSessionStatus( ctx->session, OSRF_STATUS_UNAUTHORIZED, "osrfMethodException", ctx->request, m );

        free(m);
        jsonObjectFree(user);
        user = jsonNULL;
    }

    return user;

}

static int verifyObjectPCRUD (  osrfMethodContext* ctx, const jsonObject* obj ) {

    dbhandle = writehandle;

    osrfHash* meta = (osrfHash*) ctx->method->userData;
    osrfHash* class = osrfHashGet( meta, "class" );
    char* method_type = strdup( osrfHashGet(meta, "methodtype") );
    int fetch = 0;

    if ( ( *method_type == 's' || *method_type == 'i' ) ) {
        free(method_type);
        method_type = strdup("retrieve"); // search and id_list are equivelant to retrieve for this
    } else if ( *method_type == 'u' || *method_type == 'd' ) {
        fetch = 1; // MUST go to the db for the object for update and delete
    }

    osrfHash* pcrud = osrfHashGet( osrfHashGet(class, "permacrud"), method_type );
    free(method_type);

    if (!pcrud) {
        // No permacrud for this method type on this class

        growing_buffer* msg = buffer_init(128);
        buffer_fadd(
            msg,
            "%s: %s on class %s has no permacrud IDL entry",
            MODULENAME,
            osrfHashGet(meta, "methodtype"),
            osrfHashGet(class, "classname")
        );

        char* m = buffer_release(msg);
        osrfAppSessionStatus( ctx->session, OSRF_STATUS_FORBIDDEN, "osrfMethodException", ctx->request, m );

        free(m);

        return 0;
    }

    jsonObject* user = verifyUserPCRUD( ctx );
    if (!user) return 0;

    int userid = atoi( oilsFMGetString( user, "id" ) );
    jsonObjectFree(user);

    osrfStringArray* permission = osrfHashGet(pcrud, "permission");
    osrfStringArray* local_context = osrfHashGet(pcrud, "local_context");
    osrfHash* foreign_context = osrfHashGet(pcrud, "foreign_context");

    osrfStringArray* context_org_array = osrfNewStringArray(1);

    int err = 0;
    char* pkey_value = NULL;
	if ( str_is_true( osrfHashGet(pcrud, "global_required") ) ) {
	    osrfLogDebug( OSRF_LOG_MARK, "global-level permissions required, fetching top of the org tree" );

        // check for perm at top of org tree
        jsonObject* _tmp_params = jsonParseString("{\"parent_ou\":null}");
		jsonObject* _list = doFieldmapperSearch(ctx, osrfHashGet( oilsIDL(), "aou" ),
				_tmp_params, NULL, &err);

        jsonObject* _tree_top = jsonObjectGetIndex(_list, 0);

        if (!_tree_top) {
            jsonObjectFree(_tmp_params);
            jsonObjectFree(_list);
    
            growing_buffer* msg = buffer_init(128);
			OSRF_BUFFER_ADD( msg, MODULENAME );
			OSRF_BUFFER_ADD( msg,
				": Internal error, could not find the top of the org tree (parent_ou = NULL)" );
    
            char* m = buffer_release(msg);
            osrfAppSessionStatus( ctx->session, OSRF_STATUS_INTERNALSERVERERROR, "osrfMethodException", ctx->request, m );
            free(m);

            return 0;
        }

        osrfStringArrayAdd( context_org_array, oilsFMGetString( _tree_top, "id" ) );
	    osrfLogDebug( OSRF_LOG_MARK, "top of the org tree is %s", osrfStringArrayGetString(context_org_array, 0) );

        jsonObjectFree(_tmp_params);
        jsonObjectFree(_list);

    } else {
	    osrfLogDebug( OSRF_LOG_MARK, "global-level permissions not required, fetching context org ids" );
	    char* pkey = osrfHashGet(class, "primarykey");
        jsonObject *param = NULL;

        if (obj->classname) {
            pkey_value = oilsFMGetString( obj, pkey );
            if (!fetch) param = jsonObjectClone(obj);
	        osrfLogDebug( OSRF_LOG_MARK, "Object supplied, using primary key value of %s", pkey_value );
        } else {
            pkey_value = jsonObjectToSimpleString( obj );
            fetch = 1;
	        osrfLogDebug( OSRF_LOG_MARK, "Object not supplied, using primary key value of %s and retrieving from the database", pkey_value );
        }

        if (fetch) {
			jsonObject* _tmp_params = single_hash( pkey, pkey_value );
			jsonObject* _list = doFieldmapperSearch(
					ctx, class, _tmp_params, NULL, &err );

			param = jsonObjectClone(jsonObjectGetIndex(_list, 0));

            jsonObjectFree(_tmp_params);
            jsonObjectFree(_list);
        }

        if (!param) {
            osrfLogDebug( OSRF_LOG_MARK, "Object not found in the database with primary key %s of %s", pkey, pkey_value );

            growing_buffer* msg = buffer_init(128);
            buffer_fadd(
                msg,
                "%s: no object found with primary key %s of %s",
                MODULENAME,
                pkey,
                pkey_value
            );
        
            char* m = buffer_release(msg);
            osrfAppSessionStatus(
                ctx->session,
                OSRF_STATUS_INTERNALSERVERERROR,
                "osrfMethodException",
                ctx->request,
                m
            );
        
            free(m);
            if (pkey_value) free(pkey_value);

            return 0;
        }

        if (local_context->size > 0) {
	        osrfLogDebug( OSRF_LOG_MARK, "%d class-local context field(s) specified", local_context->size);
            int i = 0;
            char* lcontext = NULL;
            while ( (lcontext = osrfStringArrayGetString(local_context, i++)) ) {
                osrfStringArrayAdd( context_org_array, oilsFMGetString( param, lcontext ) );
	            osrfLogDebug(
                    OSRF_LOG_MARK,
                    "adding class-local field %s (value: %s) to the context org list",
                    lcontext,
                    osrfStringArrayGetString(context_org_array, context_org_array->size - 1)
                );
            }
        }

        osrfStringArray* class_list;

        if (foreign_context) {
            class_list = osrfHashKeys( foreign_context );
	        osrfLogDebug( OSRF_LOG_MARK, "%d foreign context classes(s) specified", class_list->size);

            if (class_list->size > 0) {
    
                int i = 0;
                char* class_name = NULL;
            	while ( (class_name = osrfStringArrayGetString(class_list, i++)) ) {
                    osrfHash* fcontext = osrfHashGet(foreign_context, class_name);

	                osrfLogDebug(
                        OSRF_LOG_MARK,
                        "%d foreign context fields(s) specified for class %s",
                        ((osrfStringArray*)osrfHashGet(fcontext,"context"))->size,
                        class_name
                    );
    
                    char* foreign_pkey = osrfHashGet(fcontext, "field");
                    char* foreign_pkey_value = oilsFMGetString(param, osrfHashGet(fcontext, "fkey"));

					jsonObject* _tmp_params = single_hash( foreign_pkey, foreign_pkey_value );

					jsonObject* _list = doFieldmapperSearch(
						ctx, osrfHashGet( oilsIDL(), class_name ), _tmp_params, NULL, &err );

                    jsonObject* _fparam = jsonObjectClone(jsonObjectGetIndex(_list, 0));
                    jsonObjectFree(_tmp_params);
                    jsonObjectFree(_list);
 
                    osrfStringArray* jump_list = osrfHashGet(fcontext, "jump");

                    if (_fparam && jump_list) {
                        char* flink = NULL;
                        int k = 0;
                        while ( (flink = osrfStringArrayGetString(jump_list, k++)) && _fparam ) {
                            free(foreign_pkey_value);

                            osrfHash* foreign_link_hash = oilsIDLFindPath( "/%s/links/%s", _fparam->classname, flink );

							foreign_pkey_value = oilsFMGetString(_fparam, flink);
							foreign_pkey = osrfHashGet( foreign_link_hash, "key" );

							_tmp_params = single_hash( foreign_pkey, foreign_pkey_value );

							_list = doFieldmapperSearch(
								ctx,
								osrfHashGet( oilsIDL(), osrfHashGet( foreign_link_hash, "class" ) ),
								_tmp_params,
								NULL,
								&err
							);

                            _fparam = jsonObjectClone(jsonObjectGetIndex(_list, 0));
                            jsonObjectFree(_tmp_params);
                            jsonObjectFree(_list);
                        }
                    }

           
                    if (!_fparam) {

                        growing_buffer* msg = buffer_init(128);
                        buffer_fadd(
                            msg,
                            "%s: no object found with primary key %s of %s",
                            MODULENAME,
                            foreign_pkey,
                            foreign_pkey_value
                        );
                
                        char* m = buffer_release(msg);
                        osrfAppSessionStatus(
                            ctx->session,
                            OSRF_STATUS_INTERNALSERVERERROR,
                            "osrfMethodException",
                            ctx->request,
                            m
                        );

                        free(m);
                        osrfStringArrayFree(class_list);
                        free(foreign_pkey_value);
                        jsonObjectFree(param);

                        return 0;
                    }
        
                    free(foreign_pkey_value);
    
                    int j = 0;
                    char* foreign_field = NULL;
                    while ( (foreign_field = osrfStringArrayGetString(osrfHashGet(fcontext,"context"), j++)) ) {
                        osrfStringArrayAdd( context_org_array, oilsFMGetString( _fparam, foreign_field ) );
	                    osrfLogDebug(
                            OSRF_LOG_MARK,
                            "adding foreign class %s field %s (value: %s) to the context org list",
                            class_name,
                            foreign_field,
                            osrfStringArrayGetString(context_org_array, context_org_array->size - 1)
                        );
                    }

                    jsonObjectFree(_fparam);
                }
    
                osrfStringArrayFree(class_list);
            }
        }

        jsonObjectFree(param);
    }

    char* context_org = NULL;
    char* perm = NULL;
    int OK = 0;

    if (permission->size == 0) {
	    osrfLogDebug( OSRF_LOG_MARK, "No permission specified for this action, passing through" );
        OK = 1;
    }
    
    int i = 0;
    while ( (perm = osrfStringArrayGetString(permission, i++)) ) {
        int j = 0;
        while ( (context_org = osrfStringArrayGetString(context_org_array, j++)) ) {
            dbi_result result;

            if (pkey_value) {
	            osrfLogDebug(
                    OSRF_LOG_MARK,
                    "Checking object permission [%s] for user %d on object %s (class %s) at org %d",
                    perm,
                    userid,
                    pkey_value,
                    osrfHashGet(class, "classname"),
                    atoi(context_org)
                );

                result = dbi_conn_queryf(
                    writehandle,
                    "SELECT permission.usr_has_object_perm(%d, '%s', '%s', '%s', %d) AS has_perm;",
                    userid,
                    perm,
                    osrfHashGet(class, "classname"),
                    pkey_value,
                    atoi(context_org)
                );

                if (result) {
    	            osrfLogDebug(
                        OSRF_LOG_MARK,
                        "Recieved a result for object permission [%s] for user %d on object %s (class %s) at org %d",
                        perm,
                        userid,
                        pkey_value,
                        osrfHashGet(class, "classname"),
                        atoi(context_org)
                    );

                    if (dbi_result_first_row(result)) {
                        jsonObject* return_val = oilsMakeJSONFromResult( result );
						const char* has_perm = jsonObjectGetString( jsonObjectGetKeyConst(return_val, "has_perm") );

        	            osrfLogDebug(
                            OSRF_LOG_MARK,
                            "Status of object permission [%s] for user %d on object %s (class %s) at org %d is %s",
                            perm,
                            userid,
                            pkey_value,
                            osrfHashGet(class, "classname"),
                            atoi(context_org),
                            has_perm
                        );

                        if ( *has_perm == 't' ) OK = 1;
                        jsonObjectFree(return_val);
                    }

                    dbi_result_free(result); 
                    if (OK) break;
                }
            }

	        osrfLogDebug( OSRF_LOG_MARK, "Checking non-object permission [%s] for user %d at org %d", perm, userid, atoi(context_org) );
            result = dbi_conn_queryf(
                writehandle,
                "SELECT permission.usr_has_perm(%d, '%s', %d) AS has_perm;",
                userid,
                perm,
                atoi(context_org)
            );

			if (result) {
				osrfLogDebug( OSRF_LOG_MARK, "Received a result for permission [%s] for user %d at org %d",
						perm, userid, atoi(context_org) );
				if ( dbi_result_first_row(result) ) {
					jsonObject* return_val = oilsMakeJSONFromResult( result );
					const char* has_perm = jsonObjectGetString( jsonObjectGetKeyConst(return_val, "has_perm") );
					osrfLogDebug( OSRF_LOG_MARK, "Status of permission [%s] for user %d at org %d is [%s]",
							perm, userid, atoi(context_org), has_perm );
					if ( *has_perm == 't' ) OK = 1;
					jsonObjectFree(return_val);
				}

				dbi_result_free(result); 
				if (OK) break;
			}

        }
        if (OK) break;
    }

    if (pkey_value) free(pkey_value);
    osrfStringArrayFree(context_org_array);

    return OK;
}

/*
Utility function: create a JSON_HASH with a single key/value pair.
This function is equivalent to:

	jsonParseStringFmt( "{\"%s\":\"%s\"}", key, value )

...but faster because it doesn't create and parse a JSON string.
*/
static jsonObject* single_hash( const char* key, const char* value ) {
	// Sanity checks
	if( ! key ) key = "";
	if( ! value ) value = "";

	jsonObject* hash = jsonNewObjectType( JSON_HASH );
	jsonObjectSetKey( hash, key, jsonNewObject( value ) );
	return hash;
}
#endif


static jsonObject* doCreate(osrfMethodContext* ctx, int* err ) {

	osrfHash* meta = osrfHashGet( (osrfHash*) ctx->method->userData, "class" );
#ifdef PCRUD
	jsonObject* target = jsonObjectGetIndex( ctx->params, 1 );
	jsonObject* options = jsonObjectGetIndex( ctx->params, 2 );
#else
	jsonObject* target = jsonObjectGetIndex( ctx->params, 0 );
	jsonObject* options = jsonObjectGetIndex( ctx->params, 1 );
#endif

	if (!verifyObjectClass(ctx, target)) {
		*err = -1;
		return jsonNULL;
	}

	osrfLogDebug( OSRF_LOG_MARK, "Object seems to be of the correct type" );

	char* trans_id = NULL;
	if( ctx->session && ctx->session->userData )
		trans_id = osrfHashGet( (osrfHash*)ctx->session->userData, "xact_id" );

	if ( !trans_id ) {
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
		*err = -1;
		return jsonNULL;
	}

	// Set the last_xact_id
	int index = oilsIDL_ntop( target->classname, "last_xact_id" );
	if (index > -1) {
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

	OSRF_BUFFER_ADD(table_buf, "INSERT INTO ");
	OSRF_BUFFER_ADD(table_buf, osrfHashGet(meta, "tablename"));
	OSRF_BUFFER_ADD_CHAR( col_buf, '(' );
	buffer_add(val_buf,"VALUES (");


	int i = 0;
	int first = 1;
	char* field_name;
	osrfStringArray* field_list = osrfHashKeys( fields );
	while ( (field_name = osrfStringArrayGetString(field_list, i++)) ) {

		osrfHash* field = osrfHashGet( fields, field_name );

		if( str_is_true( osrfHashGet( field, "virtual" ) ) )
			continue;

		const jsonObject* field_object = oilsFMGetObject( target, field_name );

		char* value;
		if (field_object && field_object->classname) {
			value = oilsFMGetString(
				field_object,
				(char*)oilsIDLFindPath("/%s/primarykey", field_object->classname)
			);
		} else {
			value = jsonObjectToSimpleString( field_object );
		}


		if (first) {
			first = 0;
		} else {
			OSRF_BUFFER_ADD_CHAR( col_buf, ',' );
			OSRF_BUFFER_ADD_CHAR( val_buf, ',' );
		}

		buffer_add(col_buf, field_name);

		if (!field_object || field_object->type == JSON_NULL) {
			buffer_add( val_buf, "DEFAULT" );
			
		} else if ( !strcmp(get_primitive( field ), "number") ) {
			const char* numtype = get_datatype( field );
			if ( !strcmp( numtype, "INT8") ) {
				buffer_fadd( val_buf, "%lld", atoll(value) );
				
			} else if ( !strcmp( numtype, "INT") ) {
				buffer_fadd( val_buf, "%d", atoi(value) );
				
			} else if ( !strcmp( numtype, "NUMERIC") ) {
				buffer_fadd( val_buf, "%f", atof(value) );
			}
		} else {
			if ( dbi_conn_quote_string(writehandle, &value) ) {
				OSRF_BUFFER_ADD( val_buf, value );

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


	OSRF_BUFFER_ADD_CHAR( col_buf, ')' );
	OSRF_BUFFER_ADD_CHAR( val_buf, ')' );

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

		char* id = oilsFMGetString(target, pkey);
		if (!id) {
			unsigned long long new_id = dbi_conn_sequence_last(writehandle, seq);
			growing_buffer* _id = buffer_init(10);
			buffer_fadd(_id, "%lld", new_id);
			id = buffer_release(_id);
		}

		// Find quietness specification, if present
		const char* quiet_str = NULL;
		if ( options ) {
			const jsonObject* quiet_obj = jsonObjectGetKeyConst( options, "quiet" );
			if( quiet_obj )
				quiet_str = jsonObjectGetString( quiet_obj );
		}

		if( str_is_true( quiet_str ) ) {  // if quietness is specified
			obj = jsonNewObject(id);
		}
		else {

			jsonObject* where_clause = jsonNewObjectType( JSON_HASH );
			jsonObjectSetKey( where_clause, pkey, jsonNewObject(id) );

			jsonObject* list = doFieldmapperSearch( ctx, meta, where_clause, NULL, err );

			jsonObjectFree( where_clause );

			if(*err) {
				obj = jsonNULL;
			} else {
				obj = jsonObjectClone( jsonObjectGetIndex(list, 0) );
			}

			jsonObjectFree( list );
		}

		free(id);
	}

	free(query);

	return obj;

}


static jsonObject* doRetrieve(osrfMethodContext* ctx, int* err ) {

    int id_pos = 0;
    int order_pos = 1;

#ifdef PCRUD
    id_pos = 1;
    order_pos = 2;
#endif

	osrfHash* meta = osrfHashGet( (osrfHash*) ctx->method->userData, "class" );

	const char* id = jsonObjectGetString(jsonObjectGetIndex(ctx->params, id_pos));
	jsonObject* order_hash = jsonObjectGetIndex(ctx->params, order_pos);

	osrfLogDebug(
		OSRF_LOG_MARK,
		"%s retrieving %s object with primary key value of %s",
		MODULENAME,
		osrfHashGet(meta, "fieldmapper"),
		id
	);

	jsonObject* key_param = jsonNewObjectType( JSON_HASH );
	jsonObjectSetKey( 
		key_param,
		osrfHashGet( meta, "primarykey" ),
		jsonObjectClone( jsonObjectGetIndex(ctx->params, id_pos) )
	);

	jsonObject* list = doFieldmapperSearch( ctx, meta, key_param, order_hash, err );

	if(*err) {
		jsonObjectFree( key_param );
		return jsonNULL;
	}

	jsonObject* obj = jsonObjectClone( jsonObjectGetIndex(list, 0) );

	jsonObjectFree( list );
	jsonObjectFree( key_param );

#ifdef PCRUD
	if(!verifyObjectPCRUD(ctx, obj)) {
        jsonObjectFree(obj);
        *err = -1;

        growing_buffer* msg = buffer_init(128);
		OSRF_BUFFER_ADD( msg, MODULENAME );
		OSRF_BUFFER_ADD( msg, ": Insufficient permissions to retrieve object" );

        char* m = buffer_release(msg);
        osrfAppSessionStatus( ctx->session, OSRF_STATUS_NOTALLOWED, "osrfMethodException", ctx->request, m );

        free(m);

		return jsonNULL;
	}
#endif

	return obj;
}

static char* jsonNumberToDBString ( osrfHash* field, const jsonObject* value ) {
	growing_buffer* val_buf = buffer_init(32);
	const char* numtype = get_datatype( field );

	if ( !strncmp( numtype, "INT", 3 ) ) {
		if (value->type == JSON_NUMBER)
			//buffer_fadd( val_buf, "%ld", (long)jsonObjectGetNumber(value) );
			buffer_fadd( val_buf, jsonObjectGetString( value ) );
		else {
			//const char* val_str = jsonObjectGetString( value );
			//buffer_fadd( val_buf, "%ld", atol(val_str) );
			buffer_fadd( val_buf, jsonObjectGetString( value ) );
		}

	} else if ( !strcmp( numtype, "NUMERIC" ) ) {
		if (value->type == JSON_NUMBER)
			//buffer_fadd( val_buf, "%f",  jsonObjectGetNumber(value) );
			buffer_fadd( val_buf, jsonObjectGetString( value ) );
		else {
			//const char* val_str = jsonObjectGetString( value );
			//buffer_fadd( val_buf, "%f", atof(val_str) );
			buffer_fadd( val_buf, jsonObjectGetString( value ) );
		}

	} else {
		// Presumably this was really intended ot be a string, so quote it
		char* str = jsonObjectToSimpleString( value );
		if ( dbi_conn_quote_string(dbhandle, &str) ) {
			OSRF_BUFFER_ADD( val_buf, str );
			free(str);
		} else {
			osrfLogError(OSRF_LOG_MARK, "%s: Error quoting key string [%s]", MODULENAME, str);
			free(str);
			buffer_free(val_buf);
			return NULL;
		}
	}

	return buffer_release(val_buf);
}

static char* searchINPredicate (const char* class, osrfHash* field,
		jsonObject* node, const char* op, osrfMethodContext* ctx ) {
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

    if (node->type == JSON_HASH) {
        // subquery predicate
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

		if( subpred ) {
			buffer_add(sql_buf, subpred);
			free(subpred);
		} else {
			buffer_free( sql_buf );
			return NULL;
		}

    } else if (node->type == JSON_ARRAY) {
        // literal value list
    	int in_item_index = 0;
    	int in_item_first = 1;
    	const jsonObject* in_item;
    	while ( (in_item = jsonObjectGetIndex(node, in_item_index++)) ) {

			if (in_item_first)
				in_item_first = 0;
			else
				buffer_add(sql_buf, ", ");

			// Sanity check
			if ( in_item->type != JSON_STRING && in_item->type != JSON_NUMBER ) {
				osrfLogError(OSRF_LOG_MARK, "%s: Expected string or number within IN list; found %s",
						MODULENAME, json_type( in_item->type ) );
									buffer_free(sql_buf);
				return NULL;
			}
			
			// Append the literal value -- quoted if not a number
			if ( JSON_NUMBER == in_item->type ) {
				char* val = jsonNumberToDBString( field, in_item );
				OSRF_BUFFER_ADD( sql_buf, val );
				free(val);

			} else if ( !strcmp( get_primitive( field ), "number") ) {
				char* val = jsonNumberToDBString( field, in_item );
				OSRF_BUFFER_ADD( sql_buf, val );
				free(val);

			} else {
				char* key_string = jsonObjectToSimpleString(in_item);
				if ( dbi_conn_quote_string(dbhandle, &key_string) ) {
					OSRF_BUFFER_ADD( sql_buf, key_string );
					free(key_string);
				} else {
					osrfLogError(OSRF_LOG_MARK, "%s: Error quoting key string [%s]", MODULENAME, key_string);
					free(key_string);
					buffer_free(sql_buf);
					return NULL;
				}
			}
		}

		if( in_item_first ) {
			osrfLogError(OSRF_LOG_MARK, "%s: Empty IN list", MODULENAME );
			buffer_free( sql_buf );
			return NULL;
		}
	} else {
		osrfLogError(OSRF_LOG_MARK, "%s: Expected object or array for IN clause; found %s",
			MODULENAME, json_type( node->type ) );
		buffer_free(sql_buf);
		return NULL;
	}

	OSRF_BUFFER_ADD_CHAR( sql_buf, ')' );

	return buffer_release(sql_buf);
}

// Receive a JSON_ARRAY representing a function call.  The first
// entry in the array is the function name.  The rest are parameters.
static char* searchValueTransform( const jsonObject* array ) {
	
	if( array->size < 1 ) {
		osrfLogError(OSRF_LOG_MARK, "%s: Empty array for value transform", MODULENAME);
		return NULL;
	}
	
	// Get the function name
	jsonObject* func_item = jsonObjectGetIndex( array, 0 );
	if( func_item->type != JSON_STRING ) {
		osrfLogError(OSRF_LOG_MARK, "%s: Error: expected function name, found %s",
			MODULENAME, json_type( func_item->type ) );
		return NULL;
	}
	
	growing_buffer* sql_buf = buffer_init(32);

	OSRF_BUFFER_ADD( sql_buf, jsonObjectGetString( func_item ) );
	OSRF_BUFFER_ADD( sql_buf, "( " );
	
	// Get the parameters
	int func_item_index = 1;   // We already grabbed the zeroth entry
	while ( (func_item = jsonObjectGetIndex(array, func_item_index++)) ) {

		// Add a separator comma, if we need one
		if( func_item_index > 2 )
			buffer_add( sql_buf, ", " );

		// Add the current parameter
		if (func_item->type == JSON_NULL) {
			buffer_add( sql_buf, "NULL" );
		} else {
			char* val = jsonObjectToSimpleString(func_item);
			if ( dbi_conn_quote_string(dbhandle, &val) ) {
				OSRF_BUFFER_ADD( sql_buf, val );
				free(val);
			} else {
				osrfLogError(OSRF_LOG_MARK, "%s: Error quoting key string [%s]", MODULENAME, val);
				buffer_free(sql_buf);
				free(val);
				return NULL;
			}
		}
	}

	buffer_add( sql_buf, " )" );

	return buffer_release(sql_buf);
}

static char* searchFunctionPredicate (const char* class, osrfHash* field,
		const jsonObject* node, const char* op) {

	if( ! is_good_operator( op ) ) {
		osrfLogError( OSRF_LOG_MARK, "%s: Invalid operator [%s]", MODULENAME, op );
		return NULL;
	}
	
	char* val = searchValueTransform(node);
	if( !val )
		return NULL;
	
	growing_buffer* sql_buf = buffer_init(32);
	buffer_fadd(
		sql_buf,
		"\"%s\".%s %s %s",
		class,
		osrfHashGet(field, "name"),
		op,
		val
	);

	free(val);

	return buffer_release(sql_buf);
}

// class is a class name
// field is a field definition as stored in the IDL
// node comes from the method parameter, and may represent an entry in the SELECT list
static char* searchFieldTransform (const char* class, osrfHash* field, const jsonObject* node) {
	growing_buffer* sql_buf = buffer_init(32);

	const char* field_transform = jsonObjectGetString( jsonObjectGetKeyConst( node, "transform" ) );
	const char* transform_subcolumn = jsonObjectGetString( jsonObjectGetKeyConst( node, "result_field" ) );

	if(transform_subcolumn) {
		if( ! is_identifier( transform_subcolumn ) ) {
			osrfLogError( OSRF_LOG_MARK, "%s: Invalid subfield name: \"%s\"\n",
					MODULENAME, transform_subcolumn );
			buffer_free( sql_buf );
			return NULL;
		}
		OSRF_BUFFER_ADD_CHAR( sql_buf, '(' );    // enclose transform in parentheses
	}

	if (field_transform) {
		
		if( ! is_identifier( field_transform ) ) {
			osrfLogError( OSRF_LOG_MARK, "%s: Expected function name, found \"%s\"\n",
					MODULENAME, field_transform );
			buffer_free( sql_buf );
			return NULL;
		}
		
		buffer_fadd( sql_buf, "%s(\"%s\".%s", field_transform, class, osrfHashGet(field, "name"));
		const jsonObject* array = jsonObjectGetKeyConst( node, "params" );

		if (array) {
			if( array->type != JSON_ARRAY ) {
				osrfLogError( OSRF_LOG_MARK,
					"%s: Expected JSON_ARRAY for function params; found %s",
					MODULENAME, json_type( array->type ) );
				buffer_free( sql_buf );
				return NULL;
			}
			int func_item_index = 0;
			jsonObject* func_item;
			while ( (func_item = jsonObjectGetIndex(array, func_item_index++)) ) {

				char* val = jsonObjectToSimpleString(func_item);

				if ( !val ) {
					buffer_add( sql_buf, ",NULL" );
				} else if ( dbi_conn_quote_string(dbhandle, &val) ) {
					OSRF_BUFFER_ADD_CHAR( sql_buf, ',' );
					OSRF_BUFFER_ADD( sql_buf, val );
				} else {
					osrfLogError(OSRF_LOG_MARK, "%s: Error quoting key string [%s]", MODULENAME, val);
					free(val);
					buffer_free(sql_buf);
					return NULL;
    			}
				free(val);
			}
		}

		buffer_add( sql_buf, " )" );

	} else {
		buffer_fadd( sql_buf, "\"%s\".%s", class, osrfHashGet(field, "name"));
	}

	if (transform_subcolumn)
		buffer_fadd( sql_buf, ").\"%s\"", transform_subcolumn );

	return buffer_release(sql_buf);
}

static char* searchFieldTransformPredicate (const char* class, osrfHash* field,
		const jsonObject* node, const char* op ) {

	if( ! is_good_operator( op ) ) {
		osrfLogError(OSRF_LOG_MARK, "%s: Error: Invalid operator %s", MODULENAME, op);
		return NULL;
	}

	char* field_transform = searchFieldTransform( class, field, node );
	if( ! field_transform )
		return NULL;
	char* value = NULL;
	int extra_parens = 0;   // boolean

	const jsonObject* value_obj = jsonObjectGetKeyConst( node, "value" );
	if ( ! value_obj ) {
		value = searchWHERE( node, osrfHashGet( oilsIDL(), class ), AND_OP_JOIN, NULL );
		if( !value ) {
			osrfLogError(OSRF_LOG_MARK, "%s: Error building condition for field transform", MODULENAME);
			free(field_transform);
			return NULL;
		}
		extra_parens = 1;
	} else if ( value_obj->type == JSON_ARRAY ) {
		value = searchValueTransform( value_obj );
		if( !value ) {
			osrfLogError(OSRF_LOG_MARK, "%s: Error building value transform for field transform", MODULENAME);
			free( field_transform );
			return NULL;
		}
	} else if ( value_obj->type == JSON_HASH ) {
		value = searchWHERE( value_obj, osrfHashGet( oilsIDL(), class ), AND_OP_JOIN, NULL );
		if( !value ) {
			osrfLogError(OSRF_LOG_MARK, "%s: Error building predicate for field transform", MODULENAME);
			free(field_transform);
			return NULL;
		}
		extra_parens = 1;
	} else if ( value_obj->type == JSON_NUMBER ) {
		value = jsonNumberToDBString( field, value_obj );
	} else if ( value_obj->type == JSON_NULL ) {
		osrfLogError(OSRF_LOG_MARK, "%s: Error building predicate for field transform: null value", MODULENAME);
		free(field_transform);
		return NULL;
	} else if ( value_obj->type == JSON_BOOL ) {
		osrfLogError(OSRF_LOG_MARK, "%s: Error building predicate for field transform: boolean value", MODULENAME);
		free(field_transform);
		return NULL;
	} else {
		if ( !strcmp( get_primitive( field ), "number") ) {
			value = jsonNumberToDBString( field, value_obj );
		} else {
			value = jsonObjectToSimpleString( value_obj );
			if ( !dbi_conn_quote_string(dbhandle, &value) ) {
				osrfLogError(OSRF_LOG_MARK, "%s: Error quoting key string [%s]", MODULENAME, value);
				free(value);
				free(field_transform);
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

	growing_buffer* sql_buf = buffer_init(32);

	buffer_fadd(
		sql_buf,
		"%s%s %s %s %s %s%s",
		left_parens,
		field_transform,
		op,
		left_parens,
		value,
		right_parens,
		right_parens
	);

	free(value);
	free(field_transform);

	return buffer_release(sql_buf);
}

static char* searchSimplePredicate (const char* op, const char* class,
		osrfHash* field, const jsonObject* node) {

	if( ! is_good_operator( op ) ) {
		osrfLogError( OSRF_LOG_MARK, "%s: Invalid operator [%s]", MODULENAME, op );
		return NULL;
	}

	char* val = NULL;

	// Get the value to which we are comparing the specified column
	if (node->type != JSON_NULL) {
		if ( node->type == JSON_NUMBER ) {
			val = jsonNumberToDBString( field, node );
		} else if ( !strcmp( get_primitive( field ), "number" ) ) {
			val = jsonNumberToDBString( field, node );
		} else {
			val = jsonObjectToSimpleString(node);
		}
	}

	if( val ) {
		if( JSON_NUMBER != node->type && strcmp( get_primitive( field ), "number") ) {
			// Value is not numeric; enclose it in quotes
			if ( !dbi_conn_quote_string( dbhandle, &val ) ) {
				osrfLogError( OSRF_LOG_MARK, "%s: Error quoting key string [%s]", MODULENAME, val );
				free( val );
				return NULL;
			}
		}
	} else {
		// Compare to a null value
		val = strdup( "NULL" );
		if (strcmp( op, "=" ))
			op = "IS NOT";
		else
			op = "IS";
	}

	growing_buffer* sql_buf = buffer_init(32);
	buffer_fadd( sql_buf, "\"%s\".%s %s %s", class, osrfHashGet(field, "name"), op, val );
	char* pred = buffer_release( sql_buf );

	free(val);

	return pred;
}

static char* searchBETWEENPredicate (const char* class, osrfHash* field, const jsonObject* node) {

	const jsonObject* x_node = jsonObjectGetIndex( node, 0 );
	const jsonObject* y_node = jsonObjectGetIndex( node, 1 );
	
	if( NULL == y_node ) {
		osrfLogError( OSRF_LOG_MARK, "%s: Not enough operands for BETWEEN operator", MODULENAME );
		return NULL;
	}
	else if( NULL != jsonObjectGetIndex( node, 2 ) ) {
		osrfLogError( OSRF_LOG_MARK, "%s: Too many operands for BETWEEN operator", MODULENAME );
		return NULL;
	}
	
	char* x_string;
	char* y_string;

	if ( !strcmp( get_primitive( field ), "number") ) {
		x_string = jsonNumberToDBString(field, x_node);
		y_string = jsonNumberToDBString(field, y_node);

	} else {
		x_string = jsonObjectToSimpleString(x_node);
		y_string = jsonObjectToSimpleString(y_node);
		if ( !(dbi_conn_quote_string(dbhandle, &x_string) && dbi_conn_quote_string(dbhandle, &y_string)) ) {
			osrfLogError(OSRF_LOG_MARK, "%s: Error quoting key strings [%s] and [%s]",
					MODULENAME, x_string, y_string);
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

static char* searchPredicate ( const char* class, osrfHash* field, 
							   jsonObject* node, osrfMethodContext* ctx ) {

	char* pred = NULL;
	if (node->type == JSON_ARRAY) { // equality IN search
		pred = searchINPredicate( class, field, node, NULL, ctx );
	} else if (node->type == JSON_HASH) { // other search
		jsonIterator* pred_itr = jsonNewIterator( node );
		if( !jsonIteratorHasNext( pred_itr ) ) {
			osrfLogError( OSRF_LOG_MARK, "%s: Empty predicate for field \"%s\"", 
					MODULENAME, osrfHashGet(field, "name") );
		} else {
			jsonObject* pred_node = jsonIteratorNext( pred_itr );

			// Verify that there are no additional predicates
			if( jsonIteratorHasNext( pred_itr ) ) {
				osrfLogError( OSRF_LOG_MARK, "%s: Multiple predicates for field \"%s\"", 
						MODULENAME, osrfHashGet(field, "name") );
			} else if ( !(strcasecmp( pred_itr->key,"between" )) )
				pred = searchBETWEENPredicate( class, field, pred_node );
			else if ( !(strcasecmp( pred_itr->key,"in" )) || !(strcasecmp( pred_itr->key,"not in" )) )
				pred = searchINPredicate( class, field, pred_node, pred_itr->key, ctx );
			else if ( pred_node->type == JSON_ARRAY )
				pred = searchFunctionPredicate( class, field, pred_node, pred_itr->key );
			else if ( pred_node->type == JSON_HASH )
				pred = searchFieldTransformPredicate( class, field, pred_node, pred_itr->key );
			else
				pred = searchSimplePredicate( pred_itr->key, class, field, pred_node );
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
		const char* _tmp = jsonObjectGetString( join_hash );
		freeable_hash = jsonNewObjectType(JSON_HASH);
		jsonObjectSetKey(freeable_hash, _tmp, NULL);
		working_hash = freeable_hash;
	}
	else {
		if( join_hash->type != JSON_HASH ) {
			osrfLogError(
				OSRF_LOG_MARK,
				"%s: JOIN failed; expected JSON object type not found",
				MODULENAME
			);
			return NULL;
		}
		working_hash = join_hash;
	}

	growing_buffer* join_buf = buffer_init(128);
	const char* leftclass = osrfHashGet(leftmeta, "classname");

	jsonObject* snode = NULL;
	jsonIterator* search_itr = jsonNewIterator( working_hash );

	while ( (snode = jsonIteratorNext( search_itr )) ) {
		const char* class = search_itr->key;
		osrfHash* idlClass = osrfHashGet( oilsIDL(), class );
		if( !idlClass ) {
			osrfLogError(
				OSRF_LOG_MARK,
				"%s: JOIN failed.  No class \"%s\" defined in IDL",
				MODULENAME,
				search_itr->key
			);
			jsonIteratorFree( search_itr );
			buffer_free( join_buf );
			if( freeable_hash )
				jsonObjectFree( freeable_hash );
			return NULL;
		}

		const char* fkey = jsonObjectGetString( jsonObjectGetKeyConst( snode, "fkey" ) );
		const char* field = jsonObjectGetString( jsonObjectGetKeyConst( snode, "field" ) );

		if (field && !fkey) {
			// Look up the corresponding join column in the IDL.
			// The link must be defined in the child table,
			// and point to the right parent table.
			osrfHash* idl_link = (osrfHash*) oilsIDLFindPath( "/%s/links/%s", class, field );
			const char* reltype = NULL;
			const char* other_class = NULL;
			reltype = osrfHashGet( idl_link, "reltype" );
			if( reltype && strcmp( reltype, "has_many" ) )
				other_class = osrfHashGet( idl_link, "class" );
			if( other_class && !strcmp( other_class, leftclass ) )
				fkey = osrfHashGet( idl_link, "key" );
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
				if(freeable_hash)
					jsonObjectFree(freeable_hash);
				jsonIteratorFree(search_itr);
				return NULL;
			}

		} else if (!field && fkey) {
			// Look up the corresponding join column in the IDL.
			// The link must be defined in the child table,
			// and point to the right parent table.
			osrfHash* idl_link = (osrfHash*) oilsIDLFindPath( "/%s/links/%s", leftclass, fkey );
			const char* reltype = NULL;
			const char* other_class = NULL;
			reltype = osrfHashGet( idl_link, "reltype" );
			if( reltype && strcmp( reltype, "has_many" ) )
				other_class = osrfHashGet( idl_link, "class" );
			if( other_class && !strcmp( other_class, class ) )
				field = osrfHashGet( idl_link, "key" );
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
				if(freeable_hash)
					jsonObjectFree(freeable_hash);
				jsonIteratorFree(search_itr);
				return NULL;
			}

		} else if (!field && !fkey) {
			osrfHash* _links = oilsIDL_links( leftclass );

			// For each link defined for the left class:
			// see if the link references the joined class
			osrfHashIterator* itr = osrfNewHashIterator( _links );
			osrfHash* curr_link = NULL;
			while( (curr_link = osrfHashIteratorNext( itr ) ) ) {
				const char* other_class = osrfHashGet( curr_link, "class" );
				if( other_class && !strcmp( other_class, class ) ) {

					// In the IDL, the parent class doesn't know then names of the child
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

			if (!field || !fkey) {
				// Do another such search, with the classes reversed
				_links = oilsIDL_links( class );

				// For each link defined for the joined class:
				// see if the link references the left class
				osrfHashIterator* itr = osrfNewHashIterator( _links );
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

			if (!field || !fkey) {
				osrfLogError(
					OSRF_LOG_MARK,
					"%s: JOIN failed.  No link defined between %s and %s",
					MODULENAME,
					leftclass,
					class
				);
				buffer_free(join_buf);
				if(freeable_hash)
					jsonObjectFree(freeable_hash);
				jsonIteratorFree(search_itr);
				return NULL;
			}

		}

		const char* type = jsonObjectGetString( jsonObjectGetKeyConst( snode, "type" ) );
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

		char* table = getSourceDefinition(idlClass);
		if( !table ) {
			jsonIteratorFree( search_itr );
			buffer_free( join_buf );
			if( freeable_hash )
				jsonObjectFree( freeable_hash );
			return NULL;
		}

		buffer_fadd(join_buf, " %s AS \"%s\" ON ( \"%s\".%s = \"%s\".%s",
					table, class, class, field, leftclass, fkey);
		free(table);

		const jsonObject* filter = jsonObjectGetKeyConst( snode, "filter" );
		if (filter) {
			const char* filter_op = jsonObjectGetString( jsonObjectGetKeyConst( snode, "filter_op" ) );
			if ( filter_op && !strcasecmp("or",filter_op) ) {
				buffer_add( join_buf, " OR " );
			} else {
				buffer_add( join_buf, " AND " );
			}

			char* jpred = searchWHERE( filter, idlClass, AND_OP_JOIN, NULL );
			if( jpred ) {
				OSRF_BUFFER_ADD_CHAR( join_buf, ' ' );
				OSRF_BUFFER_ADD( join_buf, jpred );
				free(jpred);
			} else {
				osrfLogError(
					OSRF_LOG_MARK,
					"%s: JOIN failed.  Invalid conditional expression.",
					MODULENAME
				);
				jsonIteratorFree( search_itr );
				buffer_free( join_buf );
				if( freeable_hash )
					jsonObjectFree( freeable_hash );
				return NULL;
			}
		}

		buffer_add(join_buf, " ) ");
		
		const jsonObject* join_filter = jsonObjectGetKeyConst( snode, "join" );
		if (join_filter) {
			char* jpred = searchJOIN( join_filter, idlClass );
			if( jpred ) {
				OSRF_BUFFER_ADD_CHAR( join_buf, ' ' );
				OSRF_BUFFER_ADD( join_buf, jpred );
				free(jpred);
			} else {
				osrfLogError(  OSRF_LOG_MARK, "%s: Invalid nested join.", MODULENAME );
				jsonIteratorFree( search_itr );
				buffer_free( join_buf );
				if( freeable_hash )
					jsonObjectFree( freeable_hash );
				return NULL;
			}
		}
	}

	if(freeable_hash)
		jsonObjectFree(freeable_hash);
	jsonIteratorFree(search_itr);

	return buffer_release(join_buf);
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

static char* searchWHERE ( const jsonObject* search_hash, osrfHash* meta, int opjoin_type, osrfMethodContext* ctx ) {

	osrfLogDebug(
        OSRF_LOG_MARK,
        "%s: Entering searchWHERE; search_hash addr = %p, meta addr = %p, opjoin_type = %d, ctx addr = %p",
        MODULENAME,
        search_hash,
        meta,
        opjoin_type,
        ctx
    );

	growing_buffer* sql_buf = buffer_init(128);

	jsonObject* node = NULL;

	int first = 1;
	if ( search_hash->type == JSON_ARRAY ) {
		osrfLogDebug(OSRF_LOG_MARK, "%s: In WHERE clause, condition type is JSON_ARRAY", MODULENAME);
		jsonIterator* search_itr = jsonNewIterator( search_hash );
		if( !jsonIteratorHasNext( search_itr ) ) {
			osrfLogError(
				OSRF_LOG_MARK,
				"%s: Invalid predicate structure: empty JSON array",
				MODULENAME
			);
			jsonIteratorFree( search_itr );
			buffer_free( sql_buf );
			return NULL;
		}

		while ( (node = jsonIteratorNext( search_itr )) ) {
            if (first) {
                first = 0;
            } else {
                if (opjoin_type == OR_OP_JOIN) buffer_add(sql_buf, " OR ");
                else buffer_add(sql_buf, " AND ");
            }

            char* subpred = searchWHERE( node, meta, opjoin_type, ctx );
			if( subpred ) {
            	buffer_fadd(sql_buf, "( %s )", subpred);
            	free(subpred);
			} else {
				jsonIteratorFree( search_itr );
				buffer_free( sql_buf );
				return NULL;
			}
        }
        jsonIteratorFree(search_itr);

	} else if ( search_hash->type == JSON_HASH ) {
		osrfLogDebug(OSRF_LOG_MARK, "%s: In WHERE clause, condition type is JSON_HASH", MODULENAME);
		jsonIterator* search_itr = jsonNewIterator( search_hash );
		if( !jsonIteratorHasNext( search_itr ) ) {
			osrfLogError(
				OSRF_LOG_MARK,
				"%s: Invalid predicate structure: empty JSON object",
				MODULENAME
			);
			jsonIteratorFree( search_itr );
			buffer_free( sql_buf );
			return NULL;
		}

		while ( (node = jsonIteratorNext( search_itr )) ) {

            if (first) {
                first = 0;
            } else {
                if (opjoin_type == OR_OP_JOIN) buffer_add(sql_buf, " OR ");
                else buffer_add(sql_buf, " AND ");
            }

			if ( '+' == search_itr->key[ 0 ] ) {
				if ( node->type == JSON_STRING ) {
					// Intended purpose; to allow reference to a Boolean column

					// Verify that the class alias is not empty
					if( '\0' == search_itr->key[ 1 ] ) {
						osrfLogError(
							OSRF_LOG_MARK,
							"%s: Table alias is empty",
							MODULENAME
						);
						jsonIteratorFree( search_itr );
						buffer_free( sql_buf );
						return NULL;
					}

					// Verify that the string looks like an identifier.
					const char* subpred = jsonObjectGetString( node );
					if( ! is_identifier( subpred ) ) {
						osrfLogError(
							 OSRF_LOG_MARK,
							"%s: Invalid boolean identifier in WHERE clause: \"%s\"",
							MODULENAME,
							subpred
						);
						jsonIteratorFree( search_itr );
						buffer_free( sql_buf );
						return NULL;
					}

					buffer_fadd(sql_buf, " \"%s\".%s ", search_itr->key + 1, subpred);
				} else {
					char* subpred = searchWHERE( node, osrfHashGet( oilsIDL(), search_itr->key + 1 ), AND_OP_JOIN, ctx );
					if( subpred ) {
						buffer_fadd(sql_buf, "( %s )", subpred);
						free(subpred);
					} else {
						jsonIteratorFree( search_itr );
						buffer_free( sql_buf );
						return NULL;
					}
				}
			} else if ( !strcasecmp("-or",search_itr->key) ) {
				char* subpred = searchWHERE( node, meta, OR_OP_JOIN, ctx );
				if( subpred ) {
					buffer_fadd(sql_buf, "( %s )", subpred);
					free( subpred );
				} else {
					buffer_free( sql_buf );
					return NULL;
				}
			} else if ( !strcasecmp("-and",search_itr->key) ) {
				char* subpred = searchWHERE( node, meta, AND_OP_JOIN, ctx );
				if( subpred ) {
					buffer_fadd(sql_buf, "( %s )", subpred);
					free( subpred );
				} else {
					buffer_free( sql_buf );
					return NULL;
				}
			} else if ( !strcasecmp("-not",search_itr->key) ) {
				char* subpred = searchWHERE( node, meta, AND_OP_JOIN, ctx );
				if( subpred ) {
					buffer_fadd(sql_buf, " NOT ( %s )", subpred);
					free( subpred );
				} else {
					buffer_free( sql_buf );
					return NULL;
				}
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

				if( subpred ) {
					buffer_fadd(sql_buf, "EXISTS ( %s )", subpred);
					free(subpred);
				} else {
					buffer_free( sql_buf );
					return NULL;
				}
            } else if ( !strcasecmp("-not-exists",search_itr->key) ) {
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

				if( subpred ) {
					buffer_fadd(sql_buf, "NOT EXISTS ( %s )", subpred);
					free(subpred);
				} else {
					buffer_free( sql_buf );
					return NULL;
				}

            } else {

                char* class = osrfHashGet(meta, "classname");
                osrfHash* fields = osrfHashGet(meta, "fields");
                osrfHash* field = osrfHashGet( fields, search_itr->key );


                if (!field) {
                    char* table = getSourceDefinition(meta);
					if( !table )
						table = strdup( "(?)" );
                    osrfLogError(
                        OSRF_LOG_MARK,
                        "%s: Attempt to reference non-existent column \"%s\" on %s (%s)",
                        MODULENAME,
                        search_itr->key,
                        table,
                        class ? class : "?"
                    );
                    buffer_free(sql_buf);
                    free(table);
					jsonIteratorFree(search_itr);
					return NULL;
				}

				char* subpred = searchPredicate( class, field, node, ctx );
				if( subpred ) {
					buffer_add( sql_buf, subpred );
					free(subpred);
				} else {
					buffer_free(sql_buf);
					jsonIteratorFree(search_itr);
					return NULL;
				}
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

// Return 1 if the class is in the FROM clause, or 0 if not
static int is_joined( jsonObject* from_clause, const char* class ) {

	if( ! from_clause )
		return 0;
	else if( from_clause->type == JSON_STRING ) {
		if( strcmp( class, jsonObjectGetString( from_clause ) ) )
			return 0;
		else
			return 1;
	} else if( from_clause->type != JSON_HASH ) {
		return 0;
	} else {      // Look at any subjoins
		jsonIterator* class_itr = jsonNewIterator( from_clause );
		jsonObject* curr_class;
		int rc = 0;    // return code
		while ( ( curr_class = jsonIteratorNext( class_itr ) ) ) {
			if( ! strcmp( class_itr->key, class ) ) {
				rc = 1;
				break;
			} else {
				jsonObject* subjoin = jsonObjectGetKey( curr_class, "join" );
				if( subjoin && is_joined( subjoin, class ) ) {
					rc = 1;
					break;
				}
			}
		}
		jsonIteratorFree( class_itr );

		return rc;
	}
}

char* SELECT (
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
	jsonObject* selclass = NULL;
	jsonObject* selfield = NULL;
	jsonObject* snode = NULL;
	jsonObject* onode = NULL;

	char* string = NULL;
	int from_function = 0;
	int first = 1;
	int gfirst = 1;
	//int hfirst = 1;

	// the core search class
	char* core_class = NULL;

	// metadata about the core search class
	osrfHash* core_meta = NULL;

	osrfLogDebug(OSRF_LOG_MARK, "cstore SELECT locale: %s", locale);

	// punt if there's no core class
	if (!join_hash || ( join_hash->type == JSON_HASH && !join_hash->size )) {
		osrfLogError(
			OSRF_LOG_MARK,
			"%s: FROM clause is missing or empty",
			MODULENAME
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

	// get the core class -- the only key of the top level FROM clause, or a string
	if (join_hash->type == JSON_HASH) {
		jsonIterator* tmp_itr = jsonNewIterator( join_hash );
		snode = jsonIteratorNext( tmp_itr );
		
		core_class = strdup( tmp_itr->key );
		join_hash = snode;
		
		jsonObject* extra = jsonIteratorNext( tmp_itr );

		jsonIteratorFree( tmp_itr );
		snode = NULL;

		// There shouldn't be more than one entry in join_hash
		if( extra ) {
			osrfLogError(
				OSRF_LOG_MARK,
				"%s: Malformed FROM clause: extra entry in JSON_HASH",
				MODULENAME
			);
			if( ctx )
				osrfAppSessionStatus(
					ctx->session,
					OSRF_STATUS_INTERNALSERVERERROR,
					"osrfMethodException",
					ctx->request,
					"Malformed FROM clause in JSON query"
				);
			free( core_class );
			return NULL;	// Malformed join_hash; extra entry
		}
	} else if (join_hash->type == JSON_ARRAY) {
		from_function = 1;
		core_class = jsonObjectToSimpleString( jsonObjectGetIndex(join_hash, 0) );
		selhash = NULL;

	} else if (join_hash->type == JSON_STRING) {
		core_class = jsonObjectToSimpleString( join_hash );
		join_hash = NULL;
	}
	else {
		osrfLogError(
			OSRF_LOG_MARK,
			"%s: FROM clause is unexpected JSON type: %s",
			MODULENAME,
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
		free( core_class );
		return NULL;
	}

	if (!from_function) {
		// Get the IDL class definition for the core class
		core_meta = osrfHashGet( oilsIDL(), core_class );
		if( !core_meta ) {    // Didn't find it?
			osrfLogError(
				OSRF_LOG_MARK,
				"%s: SELECT clause references undefined class: \"%s\"",
				MODULENAME,
				core_class
			);
			if( ctx )
				osrfAppSessionStatus(
					ctx->session,
					OSRF_STATUS_INTERNALSERVERERROR,
					"osrfMethodException",
					ctx->request,
					"SELECT clause references undefined class in JSON query"
				);
			free( core_class );
			return NULL;
		}

		// Make sure the class isn't virtual
		if( str_is_true( osrfHashGet( core_meta, "virtual" ) ) ) {
			osrfLogError(
				OSRF_LOG_MARK,
				"%s: Core class is virtual: \"%s\"",
				MODULENAME,
				core_class
			);
			if( ctx )
				osrfAppSessionStatus(
					ctx->session,
					OSRF_STATUS_INTERNALSERVERERROR,
					"osrfMethodException",
					ctx->request,
					"FROM clause references virtual class in JSON query"
				);
			free( core_class );
			return NULL;
		}
	}

	// if the select list is empty, or the core class field list is '*',
	// build the default select list ...
	if (!selhash) {
		selhash = defaultselhash = jsonNewObjectType(JSON_HASH);
		jsonObjectSetKey( selhash, core_class, jsonNewObjectType(JSON_ARRAY) );
	} else if( selhash->type != JSON_HASH ) {
		osrfLogError(
			OSRF_LOG_MARK,
			"%s: Expected JSON_HASH for SELECT clause; found %s",
			MODULENAME,
			json_type( selhash->type )
		);

		if (ctx)
			osrfAppSessionStatus(
				ctx->session,
				OSRF_STATUS_INTERNALSERVERERROR,
				"osrfMethodException",
				ctx->request,
				"Malformed SELECT clause in JSON query"
			);
		free( core_class );
		return NULL;
	} else if ( (tmp_const = jsonObjectGetKeyConst( selhash, core_class )) && tmp_const->type == JSON_STRING ) {
		const char* _x = jsonObjectGetString( tmp_const );
		if (!strncmp( "*", _x, 1 )) {
			jsonObjectRemoveKey( selhash, core_class );
			jsonObjectSetKey( selhash, core_class, jsonNewObjectType(JSON_ARRAY) );
		}
	}

	// the query buffer
	growing_buffer* sql_buf = buffer_init(128);

	// temp buffers for the SELECT list and GROUP BY clause
	growing_buffer* select_buf = buffer_init(128);
	growing_buffer* group_buf = buffer_init(128);

	int aggregate_found = 0;     // boolean

	// Build a select list
	if(from_function)   // From a function we select everything
		OSRF_BUFFER_ADD_CHAR( select_buf, '*' );
	else {

		// If we need to build a default list, prepare to do so
		jsonObject* _tmp = jsonObjectGetKey( selhash, core_class );
		if ( _tmp && !_tmp->size ) {

			osrfHash* core_fields = osrfHashGet( core_meta, "fields" );

			osrfHashIterator* field_itr = osrfNewHashIterator( core_fields );
			osrfHash* field_def;
			while( ( field_def = osrfHashIteratorNext( field_itr ) ) ) {
				if( ! str_is_true( osrfHashGet( field_def, "virtual" ) ) ) {
					// This field is not virtual, so add it to the list
					jsonObjectPush( _tmp, jsonNewObject( osrfHashIteratorKey( field_itr ) ) );
				}
			}
			osrfHashIteratorFree( field_itr );
		}

		// Now build the actual select list
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

			// If the current class isn't the core class
			// and it isn't in the join tree, bail out
			if ( strcmp( core_class, cname ) && ! is_joined( join_hash, cname ) ) {
				osrfLogError(
					OSRF_LOG_MARK,
					"%s: SELECT clause references class not in FROM clause: \"%s\"",
					MODULENAME,
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
				buffer_free( sql_buf );
				buffer_free( select_buf );
				buffer_free( group_buf );
				if( defaultselhash ) jsonObjectFree( defaultselhash );
				free( core_class );
				return NULL;
			}

			// Look up some attributes of the current class, so that we 
			// don't have to look them up again for each field
			osrfHash* idlClass = osrfHashGet( oilsIDL(), cname );
			osrfHash* class_field_set = osrfHashGet( idlClass, "fields" );
			const char* class_pkey = osrfHashGet( idlClass, "primarykey" );
			const char* class_tname = osrfHashGet( idlClass, "tablename" );
			
		    // stitch together the column list ...
		    jsonIterator* select_itr = jsonNewIterator( selclass );
		    while ( (selfield = jsonIteratorNext( select_itr )) ) {   // for each SELECT column

				// If we need a separator comma, add one
				if (first) {
					first = 0;
				} else {
					OSRF_BUFFER_ADD_CHAR( select_buf, ',' );
				}

				// ... if it's a string, just toss it on the pile
				if (selfield->type == JSON_STRING) {

					// Look up the field in the IDL
					const char* col_name = jsonObjectGetString( selfield );
					osrfHash* field_def = osrfHashGet( class_field_set, col_name );
					if ( !field_def ) {
						// No such field in current class
						osrfLogError(
							OSRF_LOG_MARK,
							"%s: Selected column \"%s\" not defined in IDL for class \"%s\"",
							MODULENAME,
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
						jsonIteratorFree( select_itr );
						jsonIteratorFree( selclass_itr );
						buffer_free( sql_buf );
						buffer_free( select_buf );
						buffer_free( group_buf );
						if( defaultselhash ) jsonObjectFree( defaultselhash );
						free( core_class );
						return NULL;
					} else if ( str_is_true( osrfHashGet( field_def, "virtual" ) ) ) {
						// Virtual field not allowed
						osrfLogError(
							OSRF_LOG_MARK,
							"%s: Selected column \"%s\" for class \"%s\" is virtual",
							MODULENAME,
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
						jsonIteratorFree( select_itr );
						jsonIteratorFree( selclass_itr );
						buffer_free( sql_buf );
						buffer_free( select_buf );
						buffer_free( group_buf );
						if( defaultselhash ) jsonObjectFree( defaultselhash );
						free( core_class );
						return NULL;
					}

					if (locale) {
						const char* i18n;
						if (flags & DISABLE_I18N)
							i18n = NULL;
						else
							i18n = osrfHashGet(field_def, "i18n");

						if( str_is_true( i18n ) ) {
                            buffer_fadd( select_buf,
								" oils_i18n_xlate('%s', '%s', '%s', '%s', \"%s\".%s::TEXT, '%s') AS \"%s\"",
								class_tname, cname, col_name, class_pkey, cname, class_pkey, locale, col_name );
                        } else {
				            buffer_fadd(select_buf, " \"%s\".%s AS \"%s\"", cname, col_name, col_name );
                        }
                    } else {
				        buffer_fadd(select_buf, " \"%s\".%s AS \"%s\"", cname, col_name, col_name );
                    }
					
				// ... but it could be an object, in which case we check for a Field Transform
				} else if (selfield->type == JSON_HASH) {

					const char* col_name = jsonObjectGetString( jsonObjectGetKeyConst( selfield, "column" ) );

					// Get the field definition from the IDL
					osrfHash* field_def = osrfHashGet( class_field_set, col_name );
					if ( !field_def ) {
						// No such field in current class
						osrfLogError(
							OSRF_LOG_MARK,
							"%s: Selected column \"%s\" is not defined in IDL for class \"%s\"",
							MODULENAME,
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
						jsonIteratorFree( select_itr );
						jsonIteratorFree( selclass_itr );
						buffer_free( sql_buf );
						buffer_free( select_buf );
						buffer_free( group_buf );
						if( defaultselhash ) jsonObjectFree( defaultselhash );
						free( core_class );
						return NULL;
					} else if ( str_is_true( osrfHashGet( field_def, "virtual" ) ) ) {
						// No such field in current class
						osrfLogError(
							OSRF_LOG_MARK,
							"%s: Selected column \"%s\" is virtual for class \"%s\"",
							MODULENAME,
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
						jsonIteratorFree( select_itr );
						jsonIteratorFree( selclass_itr );
						buffer_free( sql_buf );
						buffer_free( select_buf );
						buffer_free( group_buf );
						if( defaultselhash ) jsonObjectFree( defaultselhash );
						free( core_class );
						return NULL;
					}

					// Decide what to use as a column alias
					const char* _alias;
					if ((tmp_const = jsonObjectGetKeyConst( selfield, "alias" ))) {
						_alias = jsonObjectGetString( tmp_const );
					} else {         // Use field name as the alias
						_alias = col_name;
					}

					if (jsonObjectGetKeyConst( selfield, "transform" )) {
						char* transform_str = searchFieldTransform(cname, field_def, selfield);
						if( transform_str ) {
							buffer_fadd(select_buf, " %s AS \"%s\"", transform_str, _alias);
							free(transform_str);
						} else {
							if( ctx )
								osrfAppSessionStatus(
									ctx->session,
									OSRF_STATUS_INTERNALSERVERERROR,
									"osrfMethodException",
									ctx->request,
									"Unable to generate transform function in JSON query"
								);
							jsonIteratorFree( select_itr );
							jsonIteratorFree( selclass_itr );
							buffer_free( sql_buf );
							buffer_free( select_buf );
							buffer_free( group_buf );
							if( defaultselhash ) jsonObjectFree( defaultselhash );
							free( core_class );
							return NULL;
						}
					} else {

						if (locale) {
							const char* i18n;
							if (flags & DISABLE_I18N)
								i18n = NULL;
							else
								i18n = osrfHashGet(field_def, "i18n");

							if( str_is_true( i18n ) ) {
								buffer_fadd( select_buf,
									" oils_i18n_xlate('%s', '%s', '%s', '%s', \"%s\".%s::TEXT, '%s') AS \"%s\"",
		 							class_tname, cname, col_name, class_pkey, cname, class_pkey, locale, _alias);
							} else {
								buffer_fadd(select_buf, " \"%s\".%s AS \"%s\"", cname, col_name, _alias);
							}
						} else {
							buffer_fadd(select_buf, " \"%s\".%s AS \"%s\"", cname, col_name, _alias);
						}
					}
				}
				else {
					osrfLogError(
						OSRF_LOG_MARK,
						"%s: Selected item is unexpected JSON type: %s",
						MODULENAME,
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
					jsonIteratorFree( select_itr );
					jsonIteratorFree( selclass_itr );
					buffer_free( sql_buf );
					buffer_free( select_buf );
					buffer_free( group_buf );
					if( defaultselhash ) jsonObjectFree( defaultselhash );
					free( core_class );
					return NULL;
				}

				const jsonObject* agg_obj = jsonObjectGetKey( selfield, "aggregate" );
				if( obj_is_true( agg_obj ) )
					aggregate_found = 1;
				else {
					// Append a comma (except for the first one)
					// and add the column to a GROUP BY clause
					if (gfirst)
						gfirst = 0;
					else
						OSRF_BUFFER_ADD_CHAR( group_buf, ',' );

					buffer_fadd(group_buf, " %d", sel_pos);
				}

#if 0
			    if (is_agg->size || (flags & SELECT_DISTINCT)) {

					const jsonObject* aggregate_obj = jsonObjectGetKey( selfield, "aggregate" );
				    if ( ! obj_is_true( aggregate_obj ) ) {
					    if (gfirst) {
						    gfirst = 0;
					    } else {
							OSRF_BUFFER_ADD_CHAR( group_buf, ',' );
					    }

					    buffer_fadd(group_buf, " %d", sel_pos);

					/*
				    } else if (is_agg = jsonObjectGetKey( selfield, "having" )) {
					    if (gfirst) {
						    gfirst = 0;
					    } else {
							OSRF_BUFFER_ADD_CHAR( group_buf, ',' );
					    }

					    _column = searchFieldTransform(cname, field, selfield);
						OSRF_BUFFER_ADD_CHAR(group_buf, ' ');
						OSRF_BUFFER_ADD(group_buf, _column);
					    _column = searchFieldTransform(cname, field, selfield);
					*/
				    }
			    }
#endif

			    sel_pos++;
		    } // end while -- iterating across SELECT columns

            jsonIteratorFree(select_itr);
	    } // end while -- iterating across classes

        jsonIteratorFree(selclass_itr);
    }


	char* col_list = buffer_release(select_buf);
	char* table = NULL;
	if (from_function) table = searchValueTransform(join_hash);
	else table = getSourceDefinition(core_meta);
	
	if( !table ) {
		if (ctx)
			osrfAppSessionStatus(
				ctx->session,
				OSRF_STATUS_INTERNALSERVERERROR,
				"osrfMethodException",
				ctx->request,
				"Unable to identify table for core class"
			);
		free( col_list );
		buffer_free( sql_buf );
		buffer_free( group_buf );
		if( defaultselhash ) jsonObjectFree( defaultselhash );
		free( core_class );
		return NULL;	
	}
	
	// Put it all together
	buffer_fadd(sql_buf, "SELECT %s FROM %s AS \"%s\" ", col_list, table, core_class );
	free(col_list);
	free(table);

	char* order_by_list = NULL;
	char* having_buf = NULL;

	if (!from_function) {

		// Now, walk the join tree and add that clause
		if ( join_hash ) {
			char* join_clause = searchJOIN( join_hash, core_meta );
			if( join_clause ) {
				buffer_add(sql_buf, join_clause);
				free(join_clause);
			} else {
				if (ctx)
					osrfAppSessionStatus(
						ctx->session,
						OSRF_STATUS_INTERNALSERVERERROR,
						"osrfMethodException",
						ctx->request,
  						"Unable to construct JOIN clause(s)"
					);
				buffer_free( sql_buf );
				buffer_free( group_buf );
				if( defaultselhash ) jsonObjectFree( defaultselhash );
				free( core_class );
				return NULL;
			}
	    }

		// Build a WHERE clause, if there is one
	    if ( search_hash ) {
		    buffer_add(sql_buf, " WHERE ");

		    // and it's on the WHERE clause
		    char* pred = searchWHERE( search_hash, core_meta, AND_OP_JOIN, ctx );

		    if (pred) {
				buffer_add(sql_buf, pred);
				free(pred);
			} else {
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
			    buffer_free(group_buf);
			    buffer_free(sql_buf);
			    if (defaultselhash) jsonObjectFree(defaultselhash);
			    return NULL;
			}
		}

		// Build a HAVING clause, if there is one
		if ( having_hash ) {

			// and it's on the the WHERE clause
			having_buf = searchWHERE( having_hash, core_meta, AND_OP_JOIN, ctx );

			if( ! having_buf ) {
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
				buffer_free(group_buf);
				buffer_free(sql_buf);
				if (defaultselhash) jsonObjectFree(defaultselhash);
				return NULL;
			}
		}

		growing_buffer* order_buf = NULL;  // to collect ORDER BY list

		// Build an ORDER BY clause, if there is one
		if( NULL == order_hash )
			;  // No ORDER BY? do nothing
		else if( JSON_ARRAY == order_hash->type ) {
			// Array of field specifications, each specification being a
			// hash to define the class, field, and other details
			int order_idx = 0;
			jsonObject* order_spec;
			while( (order_spec = jsonObjectGetIndex( order_hash, order_idx++ ) ) ) {

				if( JSON_HASH != order_spec->type ) {
					osrfLogError(OSRF_LOG_MARK,
						 "%s: Malformed field specification in ORDER BY clause; expected JSON_HASH, found %s",
						MODULENAME, json_type( order_spec->type ) );
					if( ctx )
						osrfAppSessionStatus(
							 ctx->session,
							OSRF_STATUS_INTERNALSERVERERROR,
							"osrfMethodException",
							ctx->request,
							"Malformed ORDER BY clause -- see error log for more details"
						);
					buffer_free( order_buf );
					free(core_class);
					free(having_buf);
					buffer_free(group_buf);
					buffer_free(sql_buf);
					if (defaultselhash) jsonObjectFree(defaultselhash);
					return NULL;
				}

				const char* class =
						jsonObjectGetString( jsonObjectGetKeyConst( order_spec, "class" ) );
				const char* field =
						jsonObjectGetString( jsonObjectGetKeyConst( order_spec, "field" ) );

				if ( order_buf )
					OSRF_BUFFER_ADD(order_buf, ", ");
				else
					order_buf = buffer_init(128);

				if( !field || !class ) {
					osrfLogError(OSRF_LOG_MARK,
						"%s: Missing class or field name in field specification of ORDER BY clause",
						 MODULENAME );
					if( ctx )
						osrfAppSessionStatus(
							ctx->session,
							OSRF_STATUS_INTERNALSERVERERROR,
							"osrfMethodException",
							ctx->request,
							"Malformed ORDER BY clause -- see error log for more details"
						);
					buffer_free( order_buf );
					free(core_class);
					free(having_buf);
					buffer_free(group_buf);
					buffer_free(sql_buf);
					if (defaultselhash) jsonObjectFree(defaultselhash);
					return NULL;
				}

				if (    ! jsonObjectGetKeyConst( selhash, class )
					 && strcmp( core_class, class )
					 && ! is_joined( join_hash, class ) ) {
					osrfLogError(OSRF_LOG_MARK, "%s: ORDER BY clause references class \"%s\" "
							"not in FROM clause", MODULENAME, class );
					if( ctx )
						osrfAppSessionStatus(
							ctx->session,
							OSRF_STATUS_INTERNALSERVERERROR,
							"osrfMethodException",
							ctx->request,
							"Invalid class referenced in ORDER BY clause -- see error log for more details"
						);
					free(core_class);
					free(having_buf);
					buffer_free(group_buf);
					buffer_free(sql_buf);
					if (defaultselhash) jsonObjectFree(defaultselhash);
					return NULL;
				}

				osrfHash* field_def = oilsIDLFindPath( "/%s/fields/%s", class, field );
				if( !field_def ) {
					osrfLogError(OSRF_LOG_MARK, "%s: Invalid field \"%s\".%s referenced in ORDER BY clause",
						 MODULENAME, class, field );
					if( ctx )
						osrfAppSessionStatus(
							ctx->session,
							OSRF_STATUS_INTERNALSERVERERROR,
							"osrfMethodException",
							ctx->request,
							"Invalid field referenced in ORDER BY clause -- see error log for more details"
						);
					free(core_class);
					free(having_buf);
					buffer_free(group_buf);
					buffer_free(sql_buf);
					if (defaultselhash) jsonObjectFree(defaultselhash);
					return NULL;
				} else if( str_is_true( osrfHashGet( field_def, "virtual" ) ) ) {
					osrfLogError(OSRF_LOG_MARK, "%s: Virtual field \"%s\" in ORDER BY clause",
								 MODULENAME, field );
					if( ctx )
						osrfAppSessionStatus(
							ctx->session,
							OSRF_STATUS_INTERNALSERVERERROR,
							"osrfMethodException",
							ctx->request,
							"Virtual field in ORDER BY clause -- see error log for more details"
						);
					buffer_free( order_buf );
					free(core_class);
					free(having_buf);
					buffer_free(group_buf);
					buffer_free(sql_buf);
					if (defaultselhash) jsonObjectFree(defaultselhash);
					return NULL;
				}

				if( jsonObjectGetKeyConst( order_spec, "transform" ) ) {
					char* transform_str = searchFieldTransform( class, field_def, order_spec );
					if( ! transform_str ) {
						if( ctx )
							osrfAppSessionStatus(
								ctx->session,
								OSRF_STATUS_INTERNALSERVERERROR,
								"osrfMethodException",
								ctx->request,
								"Severe query error in ORDER BY clause -- see error log for more details"
							);
						buffer_free( order_buf );
						free(core_class);
						free(having_buf);
						buffer_free(group_buf);
						buffer_free(sql_buf);
						if (defaultselhash) jsonObjectFree(defaultselhash);
						return NULL;
					}
					
					OSRF_BUFFER_ADD( order_buf, transform_str );
					free( transform_str );
				}
				else
					buffer_fadd( order_buf, "\"%s\".%s", class, field );

				const char* direction =
						jsonObjectGetString( jsonObjectGetKeyConst( order_spec, "direction" ) );
				if( direction ) {
					if( direction[ 0 ] || 'D' == direction[ 0 ] )
						OSRF_BUFFER_ADD( order_buf, " DESC" );
					else
						OSRF_BUFFER_ADD( order_buf, " ASC" );
				}
			}
		} else if( JSON_HASH == order_hash->type ) {
			// This hash is keyed on class name.  Each class has either
			// an array of field names or a hash keyed on field name.
			jsonIterator* class_itr = jsonNewIterator( order_hash );
			while ( (snode = jsonIteratorNext( class_itr )) ) {

				if (   ! jsonObjectGetKeyConst( selhash,class_itr->key )
					&& strcmp( core_class, class_itr->key )
					&& ! is_joined( join_hash, class_itr->key ) ) {
					osrfLogError(OSRF_LOG_MARK, "%s: Invalid class \"%s\" referenced in ORDER BY clause",
								 MODULENAME, class_itr->key );
					if( ctx )
						osrfAppSessionStatus(
							ctx->session,
							OSRF_STATUS_INTERNALSERVERERROR,
							"osrfMethodException",
							ctx->request,
							"Invalid class referenced in ORDER BY clause -- see error log for more details"
						);
					jsonIteratorFree( class_itr );
					buffer_free( order_buf );
					free(core_class);
					free(having_buf);
					buffer_free(group_buf);
					buffer_free(sql_buf);
					if (defaultselhash) jsonObjectFree(defaultselhash);
					return NULL;
				}

				osrfHash* field_list_def = oilsIDLFindPath( "/%s/fields", class_itr->key );

				if ( snode->type == JSON_HASH ) {

					// Hash is keyed on field names from the current class.  For each field
					// there is another layer of hash to define the sorting details, if any,
					// or a string to indicate direction of sorting.
					jsonIterator* order_itr = jsonNewIterator( snode );
					while ( (onode = jsonIteratorNext( order_itr )) ) {

						osrfHash* field_def = osrfHashGet( field_list_def, order_itr->key );
						if( !field_def ) {
							osrfLogError(OSRF_LOG_MARK, "%s: Invalid field \"%s\" in ORDER BY clause",
									MODULENAME, order_itr->key );
							if( ctx )
								osrfAppSessionStatus(
									ctx->session,
									OSRF_STATUS_INTERNALSERVERERROR,
									"osrfMethodException",
									ctx->request,
									"Invalid field in ORDER BY clause -- see error log for more details"
								);
							jsonIteratorFree( order_itr );
							jsonIteratorFree( class_itr );
							buffer_free( order_buf );
							free(core_class);
							free(having_buf);
							buffer_free(group_buf);
							buffer_free(sql_buf);
							if (defaultselhash) jsonObjectFree(defaultselhash);
							return NULL;
						} else if( str_is_true( osrfHashGet( field_def, "virtual" ) ) ) {
							osrfLogError(OSRF_LOG_MARK, "%s: Virtual field \"%s\" in ORDER BY clause",
								 MODULENAME, order_itr->key );
							if( ctx )
								osrfAppSessionStatus(
									ctx->session,
									OSRF_STATUS_INTERNALSERVERERROR,
									"osrfMethodException",
									ctx->request,
									"Virtual field in ORDER BY clause -- see error log for more details"
							);
							jsonIteratorFree( order_itr );
							jsonIteratorFree( class_itr );
							buffer_free( order_buf );
							free(core_class);
							free(having_buf);
							buffer_free(group_buf);
							buffer_free(sql_buf);
							if (defaultselhash) jsonObjectFree(defaultselhash);
							return NULL;
						}

						const char* direction = NULL;
						if ( onode->type == JSON_HASH ) {
							if ( jsonObjectGetKeyConst( onode, "transform" ) ) {
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
										"Severe query error in ORDER BY clause -- see error log for more details"
									);
									jsonIteratorFree( order_itr );
									jsonIteratorFree( class_itr );
									free(core_class);
									free(having_buf);
									buffer_free(group_buf);
									buffer_free(order_buf);
									buffer_free(sql_buf);
									if (defaultselhash) jsonObjectFree(defaultselhash);
									return NULL;
								}
							} else {
								growing_buffer* field_buf = buffer_init(16);
								buffer_fadd(field_buf, "\"%s\".%s", class_itr->key, order_itr->key);
								string = buffer_release(field_buf);
							}

							if ( (tmp_const = jsonObjectGetKeyConst( onode, "direction" )) ) {
								const char* dir = jsonObjectGetString(tmp_const);
								if (!strncasecmp(dir, "d", 1)) {
									direction = " DESC";
								} else {
									direction = " ASC";
								}
							}

						} else if ( JSON_NULL == onode->type || JSON_ARRAY == onode->type ) {
							osrfLogError( OSRF_LOG_MARK,
								"%s: Expected JSON_STRING in ORDER BY clause; found %s",
								MODULENAME, json_type( onode->type ) );
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
							free(core_class);
							free(having_buf);
							buffer_free(group_buf);
							buffer_free(order_buf);
							buffer_free(sql_buf);
							if (defaultselhash) jsonObjectFree(defaultselhash);
							return NULL;

						} else {
							string = strdup(order_itr->key);
							const char* dir = jsonObjectGetString(onode);
							if (!strncasecmp(dir, "d", 1)) {
								direction = " DESC";
							} else {
								direction = " ASC";
							}
						}

						if ( order_buf )
							OSRF_BUFFER_ADD(order_buf, ", ");
						else
							order_buf = buffer_init(128);

						OSRF_BUFFER_ADD(order_buf, string);
						free(string);

						if (direction) {
							 OSRF_BUFFER_ADD(order_buf, direction);
						}

					} // end while
					jsonIteratorFree(order_itr);

				} else if ( snode->type == JSON_ARRAY ) {

					// Array is a list of fields from the current class
					unsigned long order_idx = 0;
					while(( onode = jsonObjectGetIndex( snode, order_idx++ ) )) {

						const char* _f = jsonObjectGetString( onode );

						osrfHash* field_def = osrfHashGet( field_list_def, _f );
						if( !field_def ) {
							osrfLogError(OSRF_LOG_MARK, "%s: Invalid field \"%s\" in ORDER BY clause",
									MODULENAME, _f );
							if( ctx )
								osrfAppSessionStatus(
									ctx->session,
									OSRF_STATUS_INTERNALSERVERERROR,
									"osrfMethodException",
									ctx->request,
									"Invalid field in ORDER BY clause -- see error log for more details"
								);
							jsonIteratorFree( class_itr );
							buffer_free( order_buf );
							free(core_class);
							free(having_buf);
							buffer_free(group_buf);
							buffer_free(sql_buf);
							if (defaultselhash) jsonObjectFree(defaultselhash);
							return NULL;
						} else if( str_is_true( osrfHashGet( field_def, "virtual" ) ) ) {
							osrfLogError(OSRF_LOG_MARK, "%s: Virtual field \"%s\" in ORDER BY clause",
									MODULENAME, _f );
							if( ctx )
								osrfAppSessionStatus(
									ctx->session,
									OSRF_STATUS_INTERNALSERVERERROR,
									"osrfMethodException",
									ctx->request,
									"Virtual field in ORDER BY clause -- see error log for more details"
								);
							jsonIteratorFree( class_itr );
							buffer_free( order_buf );
							free(core_class);
							free(having_buf);
							buffer_free(group_buf);
							buffer_free(sql_buf);
							if (defaultselhash) jsonObjectFree(defaultselhash);
							return NULL;
						}

						if ( order_buf )
							OSRF_BUFFER_ADD(order_buf, ", ");
						else
							order_buf = buffer_init(128);

						buffer_fadd( order_buf, "\"%s\".%s", class_itr->key, _f);

					} // end while

				// IT'S THE OOOOOOOOOOOLD STYLE!
				} else {
					osrfLogError(OSRF_LOG_MARK, 
							"%s: Possible SQL injection attempt; direct order by is not allowed", MODULENAME);
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
					free(having_buf);
					buffer_free(group_buf);
					buffer_free(order_buf);
					buffer_free(sql_buf);
					if (defaultselhash) jsonObjectFree(defaultselhash);
					jsonIteratorFree(class_itr);
					return NULL;
				}
			} // end while
			jsonIteratorFree( class_itr );
		} else {
			osrfLogError(OSRF_LOG_MARK,
				"%s: Malformed ORDER BY clause; expected JSON_HASH or JSON_ARRAY, found %s",
	 			MODULENAME, json_type( order_hash->type ) );
			if( ctx )
				osrfAppSessionStatus(
					ctx->session,
					OSRF_STATUS_INTERNALSERVERERROR,
					"osrfMethodException",
					ctx->request,
					"Malformed ORDER BY clause -- see error log for more details"
				);
			buffer_free( order_buf );
			free(core_class);
			free(having_buf);
			buffer_free(group_buf);
			buffer_free(sql_buf);
			if (defaultselhash) jsonObjectFree(defaultselhash);
			return NULL;
		}

		if( order_buf )
			order_by_list = buffer_release( order_buf );
	}


	string = buffer_release(group_buf);

	if ( *string && ( aggregate_found || (flags & SELECT_DISTINCT) ) ) {
		OSRF_BUFFER_ADD( sql_buf, " GROUP BY " );
		OSRF_BUFFER_ADD( sql_buf, string );
	}

	free(string);

	if( having_buf && *having_buf ) {
		OSRF_BUFFER_ADD( sql_buf, " HAVING " );
		OSRF_BUFFER_ADD( sql_buf, having_buf );
		free( having_buf );
	}

	if( order_by_list ) {

		if ( *order_by_list ) {
			OSRF_BUFFER_ADD( sql_buf, " ORDER BY " );
			OSRF_BUFFER_ADD( sql_buf, order_by_list );
		}

		free( order_by_list );
	}

	if ( limit ){
		const char* str = jsonObjectGetString(limit);
		buffer_fadd( sql_buf, " LIMIT %d", atoi(str) );
	}

	if (offset) {
		const char* str = jsonObjectGetString(offset);
		buffer_fadd( sql_buf, " OFFSET %d", atoi(str) );
	}

	if (!(flags & SUBSELECT)) OSRF_BUFFER_ADD_CHAR(sql_buf, ';');

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
			if( ! str_is_true( osrfHashGet( osrfHashGet( fields, field ), "virtual" ) ) )
				jsonObjectPush( flist, jsonNewObject( field ) );
		}
		osrfStringArrayFree(keys);
	}

	int first = 1;
	jsonIterator* class_itr = jsonNewIterator( selhash );
	while ( (snode = jsonIteratorNext( class_itr )) ) {

		char* cname = class_itr->key;
		osrfHash* idlClass = osrfHashGet( oilsIDL(), cname );
		if (!idlClass) continue;

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
			const char* item_str = jsonObjectGetString( node );
			osrfHash* field = osrfHashGet( osrfHashGet( idlClass, "fields" ), item_str );
			char* fname = osrfHashGet(field, "name");

			if (!field) continue;

			if (first) {
				first = 0;
			} else {
				OSRF_BUFFER_ADD_CHAR(select_buf, ',');
			}

            if (locale) {
        		const char* i18n;
				const jsonObject* no_i18n_obj = jsonObjectGetKey( order_hash, "no_i18n" );
				if ( obj_is_true( no_i18n_obj ) )    // Suppress internationalization?
					i18n = NULL;
				else
					i18n = osrfHashGet(field, "i18n");

				if( str_is_true( i18n ) ) {
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
	if( !table )
		table = strdup( "(null)" );

	buffer_fadd(sql_buf, "SELECT %s FROM %s AS \"%s\"", col_list, table, core_class );
	free(col_list);
	free(table);

	if ( join_hash ) {
		char* join_clause = searchJOIN( join_hash, meta );
		OSRF_BUFFER_ADD_CHAR(sql_buf, ' ');
		OSRF_BUFFER_ADD(sql_buf, join_clause);
		free(join_clause);
	}

	osrfLogDebug(OSRF_LOG_MARK, "%s pre-predicate SQL =  %s",
				 MODULENAME, OSRF_BUFFER_C_STR(sql_buf));

	OSRF_BUFFER_ADD(sql_buf, " WHERE ");

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

						osrfHash* field_def = oilsIDLFindPath( "/%s/fields/%s",
								class_itr->key, order_itr->key );
						if ( !field_def )
							continue;

						char* direction = NULL;
						if ( onode->type == JSON_HASH ) {
							if ( jsonObjectGetKeyConst( onode, "transform" ) ) {
								string = searchFieldTransform( class_itr->key, field_def, onode );
								if( ! string ) {
									osrfAppSessionStatus(
										ctx->session,
										OSRF_STATUS_INTERNALSERVERERROR,
										"osrfMethodException",
										ctx->request,
										"Severe query error in ORDER BY clause -- see error log for more details"
									);
									jsonIteratorFree( order_itr );
									jsonIteratorFree( class_itr );
									buffer_free( order_buf );
									buffer_free( sql_buf );
									if( defaultselhash ) jsonObjectFree( defaultselhash );
									return NULL;
								}
							} else {
								growing_buffer* field_buf = buffer_init(16);
								buffer_fadd(field_buf, "\"%s\".%s", class_itr->key, order_itr->key);
								string = buffer_release(field_buf);
							}

							if ( (_tmp = jsonObjectGetKeyConst( onode, "direction" )) ) {
								const char* dir = jsonObjectGetString(_tmp);
								if (!strncasecmp(dir, "d", 1)) {
									direction = " DESC";
								} else {
									free(direction);
								}
							}

						} else {
							string = strdup(order_itr->key);
							const char* dir = jsonObjectGetString(onode);
							if (!strncasecmp(dir, "d", 1)) {
								direction = " DESC";
							} else {
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
					const char* str = jsonObjectGetString(snode);
					buffer_add(order_buf, str);
					break;
				}

			}

			jsonIteratorFree(class_itr);

			string = buffer_release(order_buf);

			if ( *string ) {
				OSRF_BUFFER_ADD( sql_buf, " ORDER BY " );
				OSRF_BUFFER_ADD( sql_buf, string );
			}

			free(string);
		}

		if ( (_tmp = jsonObjectGetKeyConst( order_hash, "limit" )) ){
			const char* str = jsonObjectGetString(_tmp);
			buffer_fadd(
				sql_buf,
				" LIMIT %d",
				atoi(str)
			);
		}

		_tmp = jsonObjectGetKeyConst( order_hash, "offset" );
		if (_tmp) {
			const char* str = jsonObjectGetString(_tmp);
			buffer_fadd(
				sql_buf,
				" OFFSET %d",
				atoi(str)
			);
		}
	}

	if (defaultselhash) jsonObjectFree(defaultselhash);

	OSRF_BUFFER_ADD_CHAR(sql_buf, ';');
	return buffer_release(sql_buf);
}

int doJSONSearch ( osrfMethodContext* ctx ) {
	if(osrfMethodVerifyContext( ctx )) {
		osrfLogError( OSRF_LOG_MARK,  "Invalid method context" );
		return -1;
	}

	osrfLogDebug(OSRF_LOG_MARK, "Recieved query request");

	int err = 0;

	// XXX for now...
	dbhandle = writehandle;

	jsonObject* hash = jsonObjectGetIndex(ctx->params, 0);

	int flags = 0;

	if ( obj_is_true( jsonObjectGetKey( hash, "distinct" ) ) )
		flags |= SELECT_DISTINCT;

	if ( obj_is_true( jsonObjectGetKey( hash, "no_i18n" ) ) )
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
		jsonObject* where_hash, jsonObject* query_hash, int* err ) {

	// XXX for now...
	dbhandle = writehandle;

	osrfHash* links = osrfHashGet(meta, "links");
	osrfHash* fields = osrfHashGet(meta, "fields");
	char* core_class = osrfHashGet(meta, "classname");
	char* pkey = osrfHashGet(meta, "primarykey");

	const jsonObject* _tmp;
	jsonObject* obj;

	char* sql = buildSELECT( where_hash, query_hash, meta, ctx );
	if (!sql) {
		osrfLogDebug(OSRF_LOG_MARK, "Problem building query, returning NULL");
		*err = -1;
		return NULL;
	}

	osrfLogDebug(OSRF_LOG_MARK, "%s SQL =  %s", MODULENAME, sql);

	dbi_result result = dbi_conn_query(dbhandle, sql);
	if( NULL == result ) {
		osrfLogError(OSRF_LOG_MARK, "%s: Error retrieving %s with query [%s]",
			MODULENAME, osrfHashGet(meta, "fieldmapper"), sql);
		osrfAppSessionStatus(
			ctx->session,
			OSRF_STATUS_INTERNALSERVERERROR,
			"osrfMethodException",
			ctx->request,
			"Severe query error -- see error log for more details"
		);
		*err = -1;
		free(sql);
		return jsonNULL;

	} else {
		osrfLogDebug(OSRF_LOG_MARK, "Query returned with no errors");
	}

	jsonObject* res_list = jsonNewObjectType(JSON_ARRAY);
	osrfHash* dedup = osrfNewHash();

	if (dbi_result_first_row(result)) {
		/* JSONify the result */
		osrfLogDebug(OSRF_LOG_MARK, "Query returned at least one row");
		do {
			obj = oilsMakeFieldmapperFromResult( result, meta );
			char* pkey_val = oilsFMGetString( obj, pkey );
			if ( osrfHashGet( dedup, pkey_val ) ) {
				jsonObjectFree(obj);
				free(pkey_val);
			} else {
				osrfHashSet( dedup, pkey_val, pkey_val );
				jsonObjectPush(res_list, obj);
			}
		} while (dbi_result_next_row(result));
	} else {
		osrfLogDebug(OSRF_LOG_MARK, "%s returned no results for query %s",
			MODULENAME, sql );
	}

	osrfHashFree(dedup);
	/* clean up the query */
	dbi_result_free(result);
	free(sql);

	if (res_list->size && query_hash) {
		_tmp = jsonObjectGetKeyConst( query_hash, "flesh" );
		if (_tmp) {
			int x = (int)jsonObjectGetNumber(_tmp);
			if (x == -1 || x > max_flesh_depth) x = max_flesh_depth;

			const jsonObject* temp_blob;
			if ((temp_blob = jsonObjectGetKeyConst( query_hash, "flesh_fields" )) && x > 0) {

				jsonObject* flesh_blob = jsonObjectClone( temp_blob );
				const jsonObject* flesh_fields = jsonObjectGetKeyConst( flesh_blob, core_class );

				osrfStringArray* link_fields = NULL;

				if (flesh_fields) {
					if (flesh_fields->size == 1) {
						const char* _t = jsonObjectGetString( jsonObjectGetIndex( flesh_fields, 0 ) );
						if (!strcmp(_t,"*")) link_fields = osrfHashKeys( links );
					}

					if (!link_fields) {
						jsonObject* _f;
						link_fields = osrfNewStringArray(1);
						jsonIterator* _i = jsonNewIterator( flesh_fields );
						while ((_f = jsonIteratorNext( _i ))) {
							osrfStringArrayAdd( link_fields, jsonObjectGetString( _f ) );
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

						const char* search_key = jsonObjectGetString(
							jsonObjectGetIndex(
								cur,
								atoi( osrfHashGet(value_field, "array_position") )
							)
						);

						if (!search_key) {
							osrfLogDebug(OSRF_LOG_MARK, "Nothing to search for!");
							continue;
						}

						osrfLogDebug(OSRF_LOG_MARK, "Creating param objects...");

						// construct WHERE clause
						jsonObject* where_clause  = jsonNewObjectType(JSON_HASH);
						jsonObjectSetKey(
							where_clause,
							osrfHashGet(kid_link, "key"),
							jsonNewObject( search_key )
						);

						// construct the rest of the query
						jsonObject* rest_of_query = jsonNewObjectType(JSON_HASH);
						jsonObjectSetKey( rest_of_query, "flesh",
							jsonNewNumberObject( (double)(x - 1 + link_map->size) )
						);

						if (flesh_blob)
							jsonObjectSetKey( rest_of_query, "flesh_fields", jsonObjectClone(flesh_blob) );

						if (jsonObjectGetKeyConst(query_hash, "order_by")) {
							jsonObjectSetKey( rest_of_query, "order_by",
								jsonObjectClone(jsonObjectGetKeyConst(query_hash, "order_by"))
							);
						}

						if (jsonObjectGetKeyConst(query_hash, "select")) {
							jsonObjectSetKey( rest_of_query, "select",
								jsonObjectClone(jsonObjectGetKeyConst(query_hash, "select"))
							);
						}

						jsonObject* kids = doFieldmapperSearch( ctx, kid_idl,
							where_clause, rest_of_query, err);

						jsonObjectFree( where_clause );
						jsonObjectFree( rest_of_query );

						if(*err) {
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
#ifdef PCRUD
	jsonObject* target = jsonObjectGetIndex( ctx->params, 1 );
#else
	jsonObject* target = jsonObjectGetIndex( ctx->params, 0 );
#endif

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
		*err = -1;
		return jsonNULL;
	}

	dbhandle = writehandle;

	char* trans_id = osrfHashGet( (osrfHash*)ctx->session->userData, "xact_id" );

        // Set the last_xact_id
	int index = oilsIDL_ntop( target->classname, "last_xact_id" );
	if (index > -1) {
		osrfLogDebug(OSRF_LOG_MARK, "Setting last_xact_id to %s on %s at position %d", trans_id, target->classname, index);
		jsonObjectSetIndex(target, index, jsonNewObject(trans_id));
	}       

	char* pkey = osrfHashGet(meta, "primarykey");
	osrfHash* fields = osrfHashGet(meta, "fields");

	char* id = oilsFMGetString( target, pkey );

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
		if( str_is_true( osrfHashGet(osrfHashGet(fields,field_name), "virtual") ) )
			continue;

		const jsonObject* field_object = oilsFMGetObject( target, field_name );

		int value_is_numeric = 0;    // boolean
		char* value;
		if (field_object && field_object->classname) {
			value = oilsFMGetString(
				field_object,
				(char*)oilsIDLFindPath("/%s/primarykey", field_object->classname)
            );
		} else {
			value = jsonObjectToSimpleString( field_object );
			if( field_object && JSON_NUMBER == field_object->type )
				value_is_numeric = 1;
		}

		osrfLogDebug( OSRF_LOG_MARK, "Updating %s object with %s = %s", osrfHashGet(meta, "fieldmapper"), field_name, value);

		if (!field_object || field_object->type == JSON_NULL) {
			if ( !(!( strcmp( osrfHashGet(meta, "classname"), "au" ) ) && !( strcmp( field_name, "passwd" ) )) ) { // arg at the special case!
				if (first) first = 0;
				else OSRF_BUFFER_ADD_CHAR(sql, ',');
				buffer_fadd( sql, " %s = NULL", field_name );
			}
			
		} else if ( value_is_numeric || !strcmp( get_primitive( field ), "number") ) {
			if (first) first = 0;
			else OSRF_BUFFER_ADD_CHAR(sql, ',');

			const char* numtype = get_datatype( field );
			if ( !strncmp( numtype, "INT", 3 ) ) {
				buffer_fadd( sql, " %s = %ld", field_name, atol(value) );
			} else if ( !strcmp( numtype, "NUMERIC" ) ) {
				buffer_fadd( sql, " %s = %f", field_name, atof(value) );
			} else {
				// Must really be intended as a string, so quote it
				if ( dbi_conn_quote_string(dbhandle, &value) ) {
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

			osrfLogDebug( OSRF_LOG_MARK, "%s is of type %s", field_name, numtype );

		} else {
			if ( dbi_conn_quote_string(dbhandle, &value) ) {
				if (first) first = 0;
				else OSRF_BUFFER_ADD_CHAR(sql, ',');
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

	jsonObject* obj = jsonNewObject(id);

	if ( strcmp( get_primitive( osrfHashGet( osrfHashGet(meta, "fields"), pkey ) ), "number" ) )
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
		*err = -1;
		return jsonNULL;
	}

	dbhandle = writehandle;

	jsonObject* obj;

	char* pkey = osrfHashGet(meta, "primarykey");

	int _obj_pos = 0;
#ifdef PCRUD
		_obj_pos = 1;
#endif

	char* id;
	if (jsonObjectGetIndex(ctx->params, _obj_pos)->classname) {
		if (!verifyObjectClass(ctx, jsonObjectGetIndex( ctx->params, _obj_pos ))) {
			*err = -1;
			return jsonNULL;
		}

		id = oilsFMGetString( jsonObjectGetIndex(ctx->params, _obj_pos), pkey );
	} else {
#ifdef PCRUD
        if (!verifyObjectPCRUD( ctx, NULL )) {
			*err = -1;
			return jsonNULL;
        }
#endif
		id = jsonObjectToSimpleString(jsonObjectGetIndex(ctx->params, _obj_pos));
	}

	osrfLogDebug(
		OSRF_LOG_MARK,
		"%s deleting %s object with %s = %s",
		MODULENAME,
		osrfHashGet(meta, "fieldmapper"),
		pkey,
		id
	);

	obj = jsonNewObject(id);

	if ( strcmp( get_primitive( osrfHashGet( osrfHashGet(meta, "fields"), pkey ) ), "number" ) )
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
			
			if ( str_is_true( osrfHashGet(_f, "virtual") ) )
				continue;
			
			const char* pos = (char*)osrfHashGet(_f, "array_position");
			if ( !pos ) continue;

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

// Interpret a string as true or false
static int str_is_true( const char* str ) {
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
				MODULENAME,
				osrfHashGet( field, "name" )
			);
		else
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
				MODULENAME,
				osrfHashGet( field, "name" )
			);
		else
			s = "NUMERIC";
	}
	return s;
}

/*
If the input string is potentially a valid SQL identifier, return 1.
Otherwise return 0.

Purpose: to prevent certain kinds of SQL injection.  To that end we
don't necessarily need to follow all the rules exactly, such as requiring
that the first character not be a digit.

We allow leading and trailing white space.  In between, we do not allow
punctuation (except for underscores and dollar signs), control 
characters, or embedded white space.

More pedantically we should allow quoted identifiers containing arbitrary
characters, but for the foreseeable future such quoted identifiers are not
likely to be an issue.
*/
static int is_identifier( const char* s) {
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

/*
Determine whether to accept a character string as a comparison operator.
Return 1 if it's good, or 0 if it's bad.

We don't validate it for real.  We just make sure that it doesn't contain
any semicolons or white space (with a special exception for the
"SIMILAR TO" operator).  The idea is to block certain kinds of SQL
injection.  If it has no semicolons or white space but it's still not a
valid operator, then the database will complain.

Another approach would be to compare the string against a short list of
approved operators.  We don't do that because we want to allow custom
operators like ">100*", which would be difficult or impossible to
express otherwise in a JSON query.
*/
static int is_good_operator( const char* op ) {
	if( !op ) return 0;   // Sanity check

	const char* s = op;
	while( *s ) {
		if( isspace( (unsigned char) *s ) ) {
			// Special exception for SIMILAR TO.  Someday we might make
			// exceptions for IS DISTINCT FROM and IS NOT DISTINCT FROM.
			if( !strcasecmp( op, "similar to" ) )
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
