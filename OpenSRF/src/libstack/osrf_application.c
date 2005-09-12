#include "osrf_application.h"
#include "osrf_log.h"
#include "objson/object.h"

osrfApplication* __osrfAppList = NULL; 


int osrfAppRegisterApplication( char* appName, char* soFile ) {
	if(!appName || ! soFile) return -1;
	char* error;

	info_handler("Registering application %s with file %s", appName, soFile );

	osrfApplication* app = safe_malloc(sizeof(osrfApplication));
	app->handle = dlopen (soFile, RTLD_NOW);

	if(!app->handle) {
		warning_handler("Failed to dlopen library file %s: %s", soFile, dlerror() );
		dlerror(); /* clear the error */
		free(app);
		return -1;
	}

	app->name = strdup(appName);

	/* this has to be done before initting the application */
	app->next = __osrfAppList;
	__osrfAppList = app;


	/* see if we can run the initialize method */
	int (*init) (void);
	*(void **) (&init) = dlsym(app->handle, "osrfAppInitialize");

	if( (error = dlerror()) != NULL ) {
		warning_handler("! Unable to locate method symbol [osrfAppInitialize] for app %s: %s", appName, error );

	} else {

		/* run the method */
		int ret;
		if( (ret = (*init)()) ) {
			warning_handler("Application %s returned non-zero value from "
					"'osrfAppInitialize', not registering...", appName );
			//free(app->name); /* need a method to remove an application from the list */
			//free(app);
			return ret;
		}
	}


	info_handler("Application %s registered successfully", appName );


	return 0;
}


int osrfAppRegisterMethod( char* appName, 
		char* methodName, char* symbolName, char* notes, int argc ) {
	if( !appName || ! methodName || ! symbolName ) return -1;

	osrfApplication* app = _osrfAppFindApplication(appName);
	if(!app) return warning_handler("Unable to locate application %s", appName );

	debug_handler("Registering method %s for app %s", appName, methodName );

	osrfMethod* method = safe_malloc(sizeof(osrfMethod));
	method->name = strdup(methodName);
	method->symbol = strdup(symbolName);
	if(notes) method->notes = strdup(notes);
	method->argc = argc;

	/* plug the method into the list of methods */
	method->next = app->methods;
	app->methods = method;
	return 0;
}

osrfApplication* _osrfAppFindApplication( char* name ) {
	if(!name) return NULL;
	osrfApplication* app = __osrfAppList;
	while(app) {
		if(!strcmp(app->name, name))
			return app;
		app = app->next;
	}
	return NULL;
}

osrfMethod* __osrfAppFindMethod( osrfApplication* app, char* methodName ) {
	if(!app || ! methodName) return NULL;
	osrfMethod* method = app->methods;
	while(method) {
		if(!strcmp(method->name, methodName))
			return method;
		method = method->next;
	}
	return NULL;
}

osrfMethod* _osrfAppFindMethod( char* appName, char* methodName ) {
	if(!appName || ! methodName) return NULL;
	return __osrfAppFindMethod( _osrfAppFindApplication(appName), methodName );
}




int osrfAppRunMethod( char* appName, char* methodName, osrfAppSession* ses, int reqId, jsonObject* params ) {
	if( !(appName && methodName && ses) ) return -1;

	char* error;
	osrfApplication* app;
	osrfMethod* method;
	osrfMethodContext context;

	context.session = ses;
	context.params = params;
	context.request = reqId;

	/* this is the method we're gonna run */
	int (*meth) (osrfMethodContext*);	

	info_handler("Running method [%s] for app [%s] with request id %d and "
			"thread trace %s", methodName, appName, reqId, ses->session_id );

	if( !(app = _osrfAppFindApplication(appName)) )
		return warning_handler( "Application not found: %s", appName );

	
	if( !(method = __osrfAppFindMethod( app, methodName )) ) {
		/* see if the unfound method is a system method */
		info_handler("Method %s not found, checking to see if it's a system method...", methodName );
		osrfMethod meth;
		meth.name = methodName;
		context.method = &meth;
		int sysres = __osrfAppRunSystemMethod(&context);
		if(sysres == 0) return 0;
		if(sysres > 0) {
			osrfAppSessionStatus( ses, OSRF_STATUS_COMPLETE,  "osrfConnectStatus", reqId, "Request Complete" );
			return 0;
		}
		return warning_handler( "NOT FOUND: app %s / method %s", appName, methodName );
	}


	context.method = method;
	
	/* open the method */
	*(void **) (&meth) = dlsym(app->handle, method->symbol);

	if( (error = dlerror()) != NULL ) {
		return warning_handler("Unable to locate method symbol [%s] "
				"for method %s and app %s", method->symbol, method->name, app->name );
	}

	/* run the method */
	int ret = (*meth) (&context);

	debug_handler("method returned %d", ret );

	if(ret == -1) {
		osrfAppSessionStatus( ses, OSRF_STATUS_INTERNALSERVERERROR,  
			"Server Error", reqId, "An unknown server error occurred" );
		return -1;
	}

	if( ret > 0 ) 
		osrfAppSessionStatus( ses, OSRF_STATUS_COMPLETE,  "osrfConnectStatus", reqId, "Request Complete" );

	return 0;
}



int __osrfAppRunSystemMethod(osrfMethodContext* ctx) {
	OSRF_METHOD_VERIFY_CONTEXT(ctx);

	if( !strcmp(ctx->method->name, OSRF_SYSMETHOD_INTROSPECT_ALL )) {

		jsonObject* resp = NULL;
		osrfApplication* app = _osrfAppFindApplication( ctx->session->remote_service );
		if(app) {
			osrfMethod* method = app->methods;
			while(method) {
				resp = jsonNewObject(NULL);
				jsonObjectSetKey(resp, "api_name", jsonNewObject(method->name));
				jsonObjectSetKey(resp, "method", jsonNewObject(method->symbol));
				jsonObjectSetKey(resp, "service", jsonNewObject(ctx->session->remote_service));
				jsonObjectSetKey(resp, "notes", jsonNewObject(method->notes));
				jsonObjectSetKey(resp, "argc", jsonNewNumberObject(method->argc));
				osrfAppRequestRespond(ctx->session, ctx->request, resp);
				method = method->next;
				jsonObjectSetClass(resp, "method");
				jsonObjectFree(resp);
			}
			return 1;
		}

		return -1;
	}

	return -1;
}




