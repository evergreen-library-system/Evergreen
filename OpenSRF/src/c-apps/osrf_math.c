#include "opensrf/osrf_app_session.h"
#include "opensrf/osrf_application.h"
#include "objson/object.h"

int initialize();
int childInit();
int osrfMathRun( osrfMethodDispatcher* );


int initialize() {

	/* tell the server about the methods we handle */
	osrfAppRegisterMethod( "opensrf.math", "add", "osrfMathRun", "send 2 numbers and I'll add them", 2 );
	osrfAppRegisterMethod( "opensrf.math", "sub", "osrfMathRun", "send 2 numbers and I'll divide them", 2 );
	osrfAppRegisterMethod( "opensrf.math", "mult", "osrfMathRun", "send 2 numbers and I'll multiply them", 2 );
	osrfAppRegisterMethod( "opensrf.math", "div", "osrfMathRun", "send 2 numbers and I'll subtract them", 2 );
	return 0;
}

int childInit() {
	return 0;
}

int osrfMathRun( osrfMethodDispatcher* d ) {

	OSRF_METHOD_VERIFY_DISPATCHER(d); /* see osrf_application.h */

	/* collect the request params */
	jsonObject* x = jsonObjectGetIndex(params, 0);
	jsonObject* y = jsonObjectGetIndex(params, 1);

	if( x && y ) {

		/* pull out the params as strings since they may be either
			strings or numbers depending on the client */
		char* a = jsonObjectToSimpleString(x);
		char* b = jsonObjectToSimpleString(y);

		if( a && b ) {

			/* construct a new params object to send to dbmath */
			jsonObject* newParams = jsonParseString( "[ %s, %s ]", a, b );
			free(a); free(b);

			/* connect to db math */
			osrfAppSession* ses = osrfAppSessionClientInit("opensrf.dbmath");

			/* dbmath uses the same method names that math does */
			int req_id = osrfAppSessionMakeRequest( ses, newParams, method->name, 1, NULL );
			osrfMessage* omsg = osrfAppSessionRequestRecv( ses, req_id, 60 );

			if(omsg) {

				/* return dbmath's response to the user */
				osrfAppRequestRespond( session, request, osrfMessageGetResult(omsg) ); 
				osrfMessageFree(omsg);
				return 0;
			}
		}
	}

	return -1;
}



