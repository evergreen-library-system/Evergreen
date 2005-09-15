#include "opensrf/osrf_app_session.h"
#include "opensrf/osrf_application.h"
#include "objson/object.h"
#include "opensrf/osrf_log.h"

#define MODULENAME "opensrf.dbmath"

int osrfAppInitialize();
int osrfAppChildInit();
int osrfMathRun( osrfMethodContext* );


int osrfAppInitialize() {

	osrfLogInit(MODULENAME);

	osrfAppRegisterMethod( 
			MODULENAME, 
			"add", 
			"osrfMathRun", 
			"Addss two numbers",
			"[ num1, num2 ]", 2 );

	osrfAppRegisterMethod( 
			MODULENAME, 
			"sub", 
			"osrfMathRun", 
			"Subtracts two numbers",
			"[ num1, num2 ]", 2 );

	osrfAppRegisterMethod( 
			MODULENAME, 
			"mult", 
			"osrfMathRun", 
			"Multiplies two numbers",
			"[ num1, num2 ]", 2 );

	osrfAppRegisterMethod( 
			MODULENAME, 
			"div", 
			"osrfMathRun", 
			"Divides two numbers",
			"[ num1, num2 ]", 2 );

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



