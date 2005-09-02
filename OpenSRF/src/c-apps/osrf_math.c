#include "opensrf/osrf_app_session.h"
#include "opensrf/osrf_application.h"
#include "objson/object.h"

int initialize();
int childInit();
int osrfMathRun( osrfMethodDispatcher* );


int initialize() {
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

	OSRF_METHOD_VERIFY_DISPATCHER(d);	

	jsonObject* x = jsonObjectGetIndex(params, 0);
	jsonObject* y = jsonObjectGetIndex(params, 1);

	if( x && y ) {

		char* a = jsonObjectToSimpleString(x);
		char* b = jsonObjectToSimpleString(y);

		if( a && b ) {

			jsonObject* new_params = jsonParseString("[]");
			jsonObjectPush(new_params, jsonNewObject(a));
			jsonObjectPush(new_params, jsonNewObject(b));

			free(a); free(b);

			osrfAppSession* ses = osrfAppSessionClientInit("opensrf.dbmath");
			int req_id = osrfAppSessionMakeRequest( ses, new_params, method->name, 1, NULL );
			osrf_message* omsg = osrfAppSessionRequestRecv( ses, req_id, 60 );

			if(omsg) {
				osrfAppRequestRespond( session, request, omsg->_result_content ); 
				osrf_message_free(omsg);
				return 0;
			}
		}
	}

	return -1;
}



