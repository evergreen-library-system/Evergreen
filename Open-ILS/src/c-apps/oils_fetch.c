#include "opensrf/osrf_app_session.h"
#include "opensrf/osrf_application.h"
#include "opensrf/osrf_settings.h"
#include "objson/object.h"
#include "opensrf/log.h"
#include "oils_utils.h"
#include "oils_constants.h"
#include "oils_event.h"
#include <dbi/dbi.h>
#include <openils/fieldmapper_lookup.h>

#define OILS_AUTH_CACHE_PRFX "oils_fetch_"

#define MODULENAME "open-ils.fetch"
dbi_conn dbhandle; /* our db connection */

/* handy NULL json object to have around */
static jsonObject* oilsFetchNULL = NULL;

int osrfAppChildInit();

/* turns a singal db result row into a jsonObject */
jsonObject* oilsFetchMakeJSON( dbi_result result, char* hint );

osrfHash* fmClassMap = NULL;


int osrfAppInitialize() {
	osrfLogInfo(OSRF_LOG_MARK, "Initializing Fetch Server...");

	oilsFetchNULL = jsonNewObject(NULL);
	fmClassMap = osrfNewHash();

	int i;
	char* hint;
	char* apiname;

	osrfList* keys = fm_classes();
	if(!keys) return 0;

	/* cycle through all of the classes and register a 
	 * retrieve method for each */
	for( i = 0; i < keys->size; i++ ) {

		hint = OSRF_LIST_GET_INDEX(keys, i);	
		i++;
		apiname = OSRF_LIST_GET_INDEX(keys, i);	
		if(!(hint && apiname)) break;

		osrfHashSet( fmClassMap, hint, apiname );

		char method[256];
		bzero(method, 256);
		snprintf(method, 256, "open-ils.fetch.%s.retrieve", apiname);

		osrfAppRegisterMethod( MODULENAME, 
				method, "oilsFetchDoRetrieve", "", 1, 0 );
	}

	return 0;
}


/**
 * Connects to the database 
 */
int osrfAppChildInit() {

	dbi_initialize(NULL);

	char* driver = osrf_settings_host_value("/apps/%s/app_settings/databases/driver", MODULENAME);
	char* user	 = osrf_settings_host_value("/apps/%s/app_settings/databases/database/user", MODULENAME);
	char* host	 = osrf_settings_host_value("/apps/%s/app_settings/databases/database/host", MODULENAME);
	char* port	 = osrf_settings_host_value("/apps/%s/app_settings/databases/database/port", MODULENAME);
	char* db		 = osrf_settings_host_value("/apps/%s/app_settings/databases/database/db", MODULENAME);
	char* pw		 = osrf_settings_host_value("/apps/%s/app_settings/databases/database/pw", MODULENAME);

	dbhandle = dbi_conn_new(driver);

	if(!dbhandle) {
		osrfLogError(OSRF_LOG_MARK, "Error creating database driver %s", driver);
		return -1;
	}

	osrfLogInfo(OSRF_LOG_MARK, "oils_fetch connecting to database.  host=%s, "
		"port=%s, user=%s, pw=%s, db=%s", host, port, user, pw, db );

	if(host) dbi_conn_set_option(dbhandle, "host", host );
	if(port) dbi_conn_set_option_numeric( dbhandle, "port", atoi(port) );
	if(user) dbi_conn_set_option(dbhandle, "username", user);
	if(pw) dbi_conn_set_option(dbhandle, "password", pw );
	if(db) dbi_conn_set_option(dbhandle, "dbname", db );

	free(user);
	free(host);
	free(port);
	free(db);
	free(pw);

	if (dbi_conn_connect(dbhandle) < 0) {
		const char* err;
		dbi_conn_error(dbhandle, &err);
		osrfLogError( OSRF_LOG_MARK, "Error connecting to database: %s", err);
		return -1;
	}

	osrfLogInfo(OSRF_LOG_MARK, "%s successfully connected to the database", MODULENAME);

	return 0;
}



int oilsFetchDoRetrieve( osrfMethodContext* ctx ) {

	OSRF_METHOD_VERIFY_CONTEXT(ctx); 

	char* id		= jsonObjectToSimpleString(jsonObjectGetIndex(ctx->params, 0));
	char* meth	= strdup(ctx->method->name);
	char* strtk;

	strtok_r(meth, ".", &strtk); /* open-ils */
	strtok_r(NULL, ".", &strtk); /* fetch */
	char* schema	= strtok_r(NULL, ".", &strtk); 
	char* object	= strtok_r(NULL, ".", &strtk);

	osrfLogDebug(OSRF_LOG_MARK, "%s retrieving %s.%s "
			"object with id %s", MODULENAME, schema, object, id );

	/* construct the SQL */
	char sql[256];
	bzero(sql, 256);
	snprintf( sql, 255, "select * from %s.%s where id = %s;", schema, object, id );

	/* find the object hint from the api name */
	char hintbuf[256];
	bzero(hintbuf,256);
	snprintf(hintbuf, 255, "%s.%s", schema, object );
	char* hint = osrfHashGet( fmClassMap, hintbuf );

	osrfLogDebug(OSRF_LOG_MARK, "%s SQL =  %s", MODULENAME, sql);

	dbi_result result = dbi_conn_queryf(dbhandle, sql);

	if(result) {

		/* there should be one row at the most  */
		dbi_result_next_row(result); 

		/* JSONify the result */
		jsonObject* obj = oilsFetchMakeJSON( result, hint );

		/* clean up the query */
		dbi_result_free(result); 

		osrfAppRespondComplete( ctx, obj ); 
		jsonObjectFree(obj);

	} else {

		osrfLogDebug(OSRF_LOG_MARK, "%s returned no results for query %s", MODULENAME, sql);
		osrfAppRespondComplete( ctx, oilsFetchNULL );
	}

	free(id);
	free(meth);
	return 0;
}


jsonObject* oilsFetchMakeJSON( dbi_result result, char* hint ) {
	if(!(result && hint)) return NULL;

	jsonObject* object = jsonParseString("[]");
	jsonObjectSetClass(object, hint);

	int attr;  
	int fmIndex; 
	int columnIndex = 1; 
	unsigned short type;
	const char* columnName; 

	/* cycle through the column list */
	while( (columnName = dbi_result_get_field_name(result, columnIndex++)) ) {

		/* determine the field type and storage attributes */
		type = dbi_result_get_field_type(result, columnName);
		attr = dbi_result_get_field_attribs(result, columnName);

		/* fetch the fieldmapper index */
		if( (fmIndex = fm_ntop(hint, (char*) columnName)) < 0 ) continue;

		switch( type ) {

			case DBI_TYPE_INTEGER :

				if( attr & DBI_INTEGER_SIZE8 ) 
					jsonObjectSetIndex( object, fmIndex, 
						jsonNewNumberObject(dbi_result_get_longlong(result, columnName)));
				else 
					jsonObjectSetIndex( object, fmIndex, 
						jsonNewNumberObject(dbi_result_get_long(result, columnName)));

				break;

			case DBI_TYPE_DECIMAL :
				jsonObjectSetIndex( object, fmIndex, 
						jsonNewNumberObject(dbi_result_get_double(result, columnName)));
				break;

			case DBI_TYPE_STRING :
				jsonObjectSetIndex( object, fmIndex, 
					jsonNewObject(dbi_result_get_string(result, columnName)));
				break;

			case DBI_TYPE_DATETIME :
				jsonObjectSetIndex( object, fmIndex, 
					jsonNewNumberObject(dbi_result_get_datetime(result, columnName)));
				break;

			case DBI_TYPE_BINARY :
				osrfLogError( OSRF_LOG_MARK, 
					"Can't do binary at column %s : index %d", columnName, columnIndex - 1);
		}
	}

	return object;
}



