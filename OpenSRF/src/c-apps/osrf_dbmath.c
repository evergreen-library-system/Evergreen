#include "opensrf/osrf_app_session.h"
#include "opensrf/osrf_application.h"
#include "objson/object.h"

int initialize();
int childInit();
int osrfMathRun( osrfMethodContext* );


int initialize() {
	osrfAppRegisterMethod( "opensrf.dbmath", "add", "osrfMathRun", "send 2 numbers and I'll add them", 2 );
	osrfAppRegisterMethod( "opensrf.dbmath", "sub", "osrfMathRun", "send 2 numbers and I'll divide them", 2 );
	osrfAppRegisterMethod( "opensrf.dbmath", "mult", "osrfMathRun", "send 2 numbers and I'll multiply them", 2 );
	osrfAppRegisterMethod( "opensrf.dbmath", "div", "osrfMathRun", "send 2 numbers and I'll subtract them", 2 );
	return 0;
}

int childInit() {
	return 0;
}

int osrfMathRun( osrfMethodContext* d ) {

	OSRF_METHOD_VERIFY_CONTEXT(d);	

	jsonObject* x = jsonObjectGetIndex(params, 0);
	jsonObject* y = jsonObjectGetIndex(params, 1);

	if( x && y ) {

		char* a = jsonObjectToSimpleString(x);
		char* b = jsonObjectToSimpleString(y);

		if( a && b ) {

			double i = strtod(a, NULL);
			double j = strtod(b, NULL);
			double r = 0;

			if(!strcmp(method->name, "add"))		r = i + j;
			if(!strcmp(method->name, "sub"))		r = i - j;
			if(!strcmp(method->name, "mult"))	r = i * j;
			if(!strcmp(method->name, "div"))		r = i / j;

			jsonObject* resp = jsonNewNumberObject(r);
			osrfAppRequestRespondComplete( session, request, resp );
			jsonObjectFree(resp);

			free(a); free(b);
			return 0;
		}
	}

	return -1;
}



