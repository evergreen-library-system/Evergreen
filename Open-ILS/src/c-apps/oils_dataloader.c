#include <opensrf/osrf_app_session.h>
#include <opensrf/osrf_system.h>
#include <opensrf/osrfConfig.h>
#include <opensrf/utils.h>
#include <opensrf/osrf_hash.h>

#include <stdio.h>

#include "openils/oils_idl.h"
#include "openils/oils_utils.h"

#define CSTORE "open-ils.cstore"
#define APPNAME "oils_dataloader"

#define E_SUCCESS 0
#define E_COMMITERROR -1
#define E_COMMANDERROR -2
#define E_ROLLBACKERROR -3

static int sendCommand ( const char* );
static int startTransaction ( );
static int commitTransaction ( );
static int rollbackTransaction ( );


static osrfHash* mnames = NULL;
static osrfAppSession* session = NULL;
static char* trans_id = NULL;

int main (int argc, char **argv) {
	if( argc < 4 ) {
		fprintf( stderr, "Usage: %s <path_to_config_file> <config_context> <create|update|delete>\n", argv[0] );
		exit(0);
	}

	mnames = osrfNewHash();

	char* config = strdup( argv[1] );
	char* context = strdup( argv[2] );
	char* method = strdup( argv[3] );

	if (strcmp(method, "create") && strcmp(method, "update") && strcmp(method, "delete")) {
		osrfLogError(OSRF_LOG_MARK, "Bad method name!  Use create, update, or delete.");
		exit(1);
	}

	// connect to the network
	osrfLogInfo(OSRF_LOG_MARK, "Launching data loader with config %s and config context %s", config, context );
	if (!osrfSystemBootstrapClientResc( config, context, APPNAME )) {
		osrfLogError(OSRF_LOG_MARK, "Unable to bootstrap data loader!");
		exit(1);
	}

	// Load the IDL
	osrfHash* idl;
	char* idl_filename = osrfConfigGetValue(NULL, "/IDL");

	if (!(idl = oilsIDLInit( idl_filename ))) {
		osrfLogError(OSRF_LOG_MARK, "Unable to load IDL!");
		exit(1);
	}

	// Generate "create" method name for each 
	osrfStringArray* classes = osrfHashKeys(idl);
	int c_index = 0;
	const char* classname;
	char* st_tmp = NULL;

	while ((classname = osrfStringArrayGetString(classes, c_index++))) {
		osrfHash* idlClass = oilsIDLFindPath("/%s", classname);

		char* _fm = strdup( (char*)osrfHashGet(idlClass, "fieldmapper") );
		char* part = strtok_r(_fm, ":", &st_tmp);

		growing_buffer* _method_name =  buffer_init(64);
		buffer_fadd(_method_name, "%s.direct.%s", CSTORE, part);

		while ((part = strtok_r(NULL, ":", &st_tmp))) {
			buffer_fadd(_method_name, ".%s", part);
		}
		buffer_fadd(_method_name, ".%s", method);

		char* m = buffer_release(_method_name);
		osrfHashSet( mnames, m, classname );

		osrfLogDebug(OSRF_LOG_MARK, "Constructed %s method named %s for %s", method, m, classname);

		free(_fm);
	}

	free(config);
	free(context);
	free(idl_filename);

	// Connect to open-ils.cstore
	session = osrfAppSessionClientInit(CSTORE);
	osrfAppSessionConnect(session);

	// Start a transaction
	if (!startTransaction()) {
		osrfLogError(OSRF_LOG_MARK, "An error occured while attempting to start a transaction");
	}

	growing_buffer* json = buffer_init(128);
	char* json_string;
	int c;
	int counter = 0;
	while ((c = getchar())) {
		switch(c) {
			case '\n':
			case EOF:
				// End of a line
				json_string = buffer_data(json);
				buffer_reset(json);

				if (!sendCommand(json_string)) {
					osrfLogError(
						OSRF_LOG_MARK,
						"An error occured while attempting to %s an object: [%s]",
						method,
						json_string
					);

					if (!rollbackTransaction()) {
						osrfAppSessionFree(session);
						osrfLogError(OSRF_LOG_MARK, "An error occured while attempting to complete a transaction");
						return E_ROLLBACKERROR;
					}

					osrfAppSessionFree(session);
					return E_COMMANDERROR;
				}

				counter++;

				buffer_reset(json);
				free(json_string);
				break;

			default:
				buffer_add_char( json, c );
				break;
		}
	}

	buffer_free(json);

	// clean up, commit, go away
	if (!commitTransaction()) {
		osrfLogError(OSRF_LOG_MARK, "An error occured while attempting to complete a transaction");
		osrfAppSessionFree(session);
		return E_COMMITERROR;
	}

	osrfAppSessionFree(session);
	free(method);

	return E_SUCCESS;
}

static int commitTransaction () {
	int ret = 1;
	const jsonObject* data;
	int req_id = osrfAppSessionMakeRequest( session, NULL, "open-ils.cstore.transaction.commit", 1, NULL );
	osrfMessage* res = osrfAppSessionRequestRecv( session, req_id, 5 );
	if ( (data = osrfMessageGetResult(res)) ) {
		if(!(trans_id = jsonObjectGetString(data))) {
			ret = 0;
		}
	} else {
		ret = 0;
	}
	osrfMessageFree(res);

	return ret;
}

static int rollbackTransaction () {
	int ret = 1;
	const jsonObject* data;
	int req_id = osrfAppSessionMakeRequest( session, NULL, "open-ils.cstore.transaction.rollback", 1, NULL );
	osrfMessage* res = osrfAppSessionRequestRecv( session, req_id, 5 );
	if ( (data = osrfMessageGetResult(res)) ) {
		if(!(trans_id = jsonObjectGetString(data))) {
			ret = 0;
		}
	} else {
		ret = 0;
	}
	osrfMessageFree(res);

	return ret;
}

static int startTransaction () {
	int ret = 1;
	jsonObject* data;
	int req_id = osrfAppSessionMakeRequest( session, NULL, "open-ils.cstore.transaction.begin", 1, NULL );
	osrfMessage* res = osrfAppSessionRequestRecv( session, req_id, 5 );
	if ( (data = osrfMessageGetResult(res)) ) {
		if(!(trans_id = jsonObjectToSimpleString(data))) {
			ret = 0;
		}
	} else {
		ret = 0;
	}
	osrfMessageFree(res);

	return ret;
}

static int sendCommand ( const char* json ) {
	int ret = 1;
	jsonObject* item = jsonParseString(json);

	if (!item->classname) {
		osrfLogError(OSRF_LOG_MARK, "Data loader cannot handle unclassed objects.  Skipping [%s]!", json);
		jsonObjectFree(item);
		return 0;
	}

	// Get the method name...
	char* method_name = osrfHashGet( mnames, item->classname );
	osrfLogDebug(OSRF_LOG_MARK, "Calling %s -> %s for %s", CSTORE, method_name, item->classname);

	// make the param array
	jsonObject* params = jsonParseString("[]");
	jsonObjectSetIndex( params, 0, item );
	jsonObjectSetIndex( params, 1, jsonParseString("{\"quiet\":\"true\"}") );

	jsonObject* data;
	int req_id = osrfAppSessionMakeRequest( session, params, method_name, 1, NULL );
	jsonObjectFree(params);

	osrfMessage* res = osrfAppSessionRequestRecv( session, req_id, 5 );

	if (res) {
		if ( !(data = osrfMessageGetResult(res)) ) {
			ret = 0;
		}
		osrfMessageFree(res);
	} else {
		ret = 0;
	}

	return ret;
}
