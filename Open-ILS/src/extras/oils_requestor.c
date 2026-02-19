#include <getopt.h>
#include <stdio.h>
#include <string.h>
#include <readline/readline.h>
#include "opensrf/utils.h"
#include "opensrf/osrf_system.h"
#include "opensrf/osrf_app_session.h"
#include "openils/oils_event.h"
#include "openils/oils_utils.h"

char* script    = NULL;
char* authtoken = NULL;
static char* tz = NULL;

static int do_request( char* request );
static char* format_response( const jsonObject* o );

int main( int argc, char* argv[] ) {

	int c;
	char* username      = NULL;
	char* password      = NULL;
	char* config        = NULL;
	char* context       = NULL;
	char* idl_filename  = NULL;
	char* hostname      = NULL;
	char* request;

	while( (c = getopt( argc, argv, "f:u:p:s:c:i:h:" )) != -1 ) {
		switch(c) {
			case '?': return -1;
			case 'f': config        = strdup(optarg); break;
			case 'c': context       = strdup(optarg); break;
			case 'u': username      = strdup(optarg); break;
			case 'p': password      = strdup(optarg); break;
			case 's': script        = strdup(optarg); break;
			case 'i': idl_filename  = strdup(optarg); break;
			case 'h': hostname      = strdup(optarg); break;
		}
	}

	if(!(config && context)) {
		fprintf(stderr, "Config or config context not provided. Exiting...\n");
		return -1;
	}

	if( ! osrf_system_bootstrap_client(config, context) ) {
		fprintf(stderr, "Unable to connect to OpenSRF network... [config:%s : context:%s]\n",
			config, context);
		return 1;
	}

	if(!idl_filename) {
		if(!hostname) {
			fprintf( stderr, "We need an IDL file name or a settings server hostname...\n");
		    return 1;
		}
		osrf_settings_retrieve(hostname);
	}

	if (!oilsInitIDL( idl_filename )) {
		fprintf(stderr, "IDL file could not be loaded. Exiting...\n");
		return -1;
	}

	printf("Connected to OpenSRF network...\n");

    tz = getenv("TZ");

	if( username && password &&
			( authtoken = oilsUtilsLogin(username, password, "staff", -1 )) ) {
		printf("Login Session: %s\n", authtoken);
	}

	while( (request=readline("oils# ")) ) {
		int retcode = do_request(request);
		free(request);
		if( retcode )
			break;
	}

	free(config);
	free(context);
	free(username);
	free(password);
	free(script);
	free(authtoken);
	free(idl_filename);
	osrf_settings_free_host_config(NULL);
	return 1;
}


static int do_request( char* request ) {

	if(!strcasecmp(request, "exit") || !strcasecmp(request,"quit"))
		return 1;

	if(!strcmp(request,""))
		return 0;

	const char* service;
	const char* method;
	char* tmp = NULL;

	service = strtok_r(request, " ", &tmp);
	method = strtok_r(NULL, " ", &tmp);

	if( service && method ) {

		jsonObject* params = NULL;

		if( *tmp ) {
			growing_buffer* buffer = osrf_buffer_init(256);
			osrf_buffer_fadd( buffer, "[%s]", tmp );
			params = jsonParse( buffer->buf );
			osrf_buffer_free(buffer);
		}

		osrfAppSession* session = osrfAppSessionClientInit(service);
		if (tz) osrf_app_session_set_tz(session,tz);

		int req_id = osrfAppSessionSendRequest( session, params, method, 1 );
		osrfMessage* omsg;

		while( (omsg = osrfAppSessionRequestRecv( session, req_id, 120 )) ) {
			const jsonObject* res = osrfMessageGetResult(omsg);
			char* data = format_response(res);
			printf("%s\n", data);
			free(data);
			osrfMessageFree(omsg);
		}

		osrfAppSessionFree(session);
		jsonObjectFree(params);

	} else {
		fprintf(stderr, "STATEMENT DOES NOT PARSE: %s\n", request);
	}

	return 0;
}


static char* format_response( const jsonObject* o ) {
	if(!o) return NULL;

	int width = 20;

	if( o->classname && isFieldmapper(o->classname) ) {

		int i = 0;
		char* key;
		growing_buffer* buffer = osrf_buffer_init(256);

		osrf_buffer_fadd(buffer, " FM Class: %s\n", o->classname);

		while( (key = fm_pton(o->classname, i++)) ) {
			char* val = oilsFMGetString(o, key);
			const jsonObject* item;

			int l = strlen(key + 2);
			osrf_buffer_fadd(buffer, " %s: ", key);

			if(val) {

				while( l++ < width ) osrf_buffer_add(buffer, "-");
				osrf_buffer_fadd(buffer, " %s\n", val);
				free(val);

			} else if( (item = oilsFMGetObject(o, key))) {

				if(item->type != JSON_NULL ) {
					char* d = format_response(item);
					osrf_buffer_add(buffer, "\n====================================\n");
					osrf_buffer_fadd(buffer, "%s\n", d);
					osrf_buffer_add(buffer, "====================================\n");
					free(d);
				} else {
					while( l++ < width ) osrf_buffer_add(buffer, "-");
					osrf_buffer_add(buffer," NULL \n");
				}

			} else {

				while( l++ < width ) osrf_buffer_add(buffer, "-");
				osrf_buffer_add(buffer," NULL \n");
			}

			free(key);
		}

		return osrf_buffer_release(buffer);
	}

	char* jjson;
	if( o->type == JSON_ARRAY ) {
		int i = 0;
		growing_buffer* arrb = osrf_buffer_init(256);
		for( i = 0; i != o->size; i++ ) {
			char* d = format_response(jsonObjectGetIndex(o, i));
			osrf_buffer_fadd(arrb, "%s\n", d);
			free(d);
		}

		jjson = osrf_buffer_release(arrb);

	} else {
		char* json = jsonObjectToJSON(o);
		jjson = jsonFormatString(json);
		free(json);
	}

	return jjson;
}
