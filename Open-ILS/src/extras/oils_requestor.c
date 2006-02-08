#include <getopt.h>
#include <stdio.h>
#include <string.h>
#include <readline/readline.h>
#include "opensrf/utils.h"
#include "opensrf/osrf_system.h"
#include "opensrf/osrf_app_session.h"
#include "openils/fieldmapper_lookup.h"
#include "openils/oils_event.h"
#include "openils/oils_utils.h"

char* script		= NULL;
char* authtoken	= NULL;

int do_request( char* request );
char* format_response( jsonObject* o );

int main( int argc, char* argv[] ) {
	
	char c;
	char* username		= NULL;
	char* password		= NULL;
	char* config		= NULL;
	char* context		= NULL;
	char* request;

	while( (c = getopt( argc, argv, "f:u:p:s:c:" )) != -1 ) {
		switch(c) {
			case '?': return -1;
			case 'f': config		= strdup(optarg);
			case 'c': context		= strdup(optarg);
			case 'u': username	= strdup(optarg);
			case 'p': password	= strdup(optarg);
			case 's': script		= strdup(optarg);
		}
	}

	if(!(config && context)) {
		fprintf(stderr, "Config or config context not provided. Exiting...\n");
		return -1;
	}

	if( ! osrf_system_bootstrap_client(config, context) ) {
		fprintf(stderr, "Unable to connect to OpenSRF network...\n");
		return 1;
	}

	if( username && password &&
			( authtoken = oilsUtilsLogin(username, password, "staff", -1 )) ) {
		printf("Login Session: %s\n", authtoken);
	}

	while((request=readline("oils# "))) 
		if(do_request(request)) break;

	free(authtoken);
	return 1;
}


int do_request( char* request ) {

	if(!strcasecmp(request, "exit") || !strcasecmp(request,"quit"))
		return 1;

	if(!strcmp(request,"")) return 0;

	char* service;
	char* method;
	char* tmp;
	char* item;
	growing_buffer* buffer = buffer_init(256);
	
	service = strtok_r(request, " ", &tmp);
	method = strtok_r(NULL, " ", &tmp);
	while( (item = strtok_r(NULL, " ", &tmp)) ) 
		buffer_fadd(buffer, "%s", item);

	if( service && method ) {

		jsonObject* params = NULL;
		if(buffer->n_used > 0) 
			params = jsonParseString("[%s]", buffer->buf);

		osrfAppSession* session = osrf_app_client_session_init(service);
		int req_id = osrf_app_session_make_req( session, params, method, 1, NULL );
		osrfMessage* omsg;

		while( (omsg = osrfAppSessionRequestRecv( session, req_id, 120 )) ) {
			jsonObject* res = osrfMessageGetResult(omsg);
			char* data = format_response(res);
			printf("\n%s\n", data);
			free(data);
			osrfMessageFree(omsg);
		}

		osrfAppSessionFree(session);
		jsonObjectFree(params);

	} else {
		fprintf(stderr, "STATMENT DOES NOT PARSE: %s\n", request);
	}

	buffer_free(buffer);
	return 0;
}


char* format_response( jsonObject* o ) {
	if(!o) return NULL;

	int width = 20;

	if( o->classname && isFieldmapper(o->classname) ) {

		int i = 0;
		char* key;
		growing_buffer* buffer = buffer_init(256);

		buffer_fadd(buffer, " FM Class: %s\n", o->classname);

		while( (key = fm_pton(o->classname, i++)) ) {
			char* val = oilsFMGetString(o, key);
			jsonObject* item;

			int l = strlen(key + 2);
			buffer_fadd(buffer, " %s: ", key);

			if(val) {

				while( l++ < width ) buffer_add(buffer, "-");
				buffer_fadd(buffer, " %s\n", val);
				free(val);

			} else if( (item = oilsFMGetObject(o, key))) {

				if(item->type != JSON_NULL ) {
					char* d = format_response(item);
					buffer_add(buffer, "\n====================================\n");
					buffer_fadd(buffer, "%s\n", d);
					buffer_add(buffer, "====================================\n");
					free(d);
				} else {
					while( l++ < width ) buffer_add(buffer, "-");
					buffer_add(buffer," NULL \n");
				}

			} else {

				while( l++ < width ) buffer_add(buffer, "-");
				buffer_add(buffer," NULL \n");
			}

			free(key);
		}

		char* data = buffer_data(buffer);
		buffer_free(buffer);
		return data;
	}

	char* jjson;
	if( o->type == JSON_ARRAY ) {
		int i = 0;
		growing_buffer* arrb = buffer_init(256);
		for( i = 0; i != o->size; i++ ) {
			char* d = format_response(jsonObjectGetIndex(o, i));
			buffer_fadd(arrb, "%s\n", d);
		}

		jjson = buffer_data(arrb);
		buffer_free(arrb);

	} else {
		char* json = jsonObjectToJSON(o);
		jjson = jsonFormatString(json);
		free(json);
	}

	return jjson;
}
