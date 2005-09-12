#include "opensrf/osrf_app_session.h"
#include "opensrf/osrf_application.h"
#include "objson/object.h"
#include "opensrf/osrf_log.h"

int osrfAppInitialize();
int osrfAppChildInit();
int osrfMathRun( osrfMethodContext* );


int osrfAppInitialize() {
	osrfLogInit("opensrf.dbmath");
	osrfAppRegisterMethod( "opensrf.dbmath", "add", "osrfMathRun", "send 2 numbers and I'll add them", 2 );
	osrfAppRegisterMethod( "opensrf.dbmath", "sub", "osrfMathRun", "send 2 numbers and I'll divide them", 2 );
	osrfAppRegisterMethod( "opensrf.dbmath", "mult", "osrfMathRun", "send 2 numbers and I'll multiply them", 2 );
	osrfAppRegisterMethod( "opensrf.dbmath", "div", "osrfMathRun", "send 2 numbers and I'll subtract them", 2 );
	return 0;
}

int osrfAppChildInit() {
	return 0;
}

int osrfMathRun( osrfMethodContext* ctx ) {

	OSRF_METHOD_VERIFY_CONTEXT(ctx);	

	jsonObject* x = jsonObjectGetIndex(ctx->params, 0);
	jsonObject* y = jsonObjectGetIndex(ctx->params, 1);

	if( x && y ) {

		char* a = jsonObjectToSimpleString(x);
		char* b = jsonObjectToSimpleString(y);

		if( a && b ) {

			double i = strtod(a, NULL);
			double j = strtod(b, NULL);
			double r = 0;

			if(!strcmp(ctx->method->name, "add"))	r = i + j;
			if(!strcmp(ctx->method->name, "sub"))	r = i - j;
			if(!strcmp(ctx->method->name, "mult"))	r = i * j;
			if(!strcmp(ctx->method->name, "div"))	r = i / j;

			jsonObject* resp = jsonNewNumberObject(r);
			osrfAppRequestRespondComplete( ctx->session, ctx->request, resp );
			jsonObjectFree(resp);

			free(a); free(b);
			return 0;
		}
	}

	return -1;
}



