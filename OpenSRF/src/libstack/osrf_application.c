
#include "osrf_application.h"

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
	*(void **) (&init) = dlsym(app->handle, "initialize");

	if( (error = dlerror()) != NULL ) {
		warning_handler("! Unable to locate method symbol [initialize] for app %s: %s", appName, error );

	} else {

		/* run the method */
		int ret;
		if( (ret = (*init)()) ) {
			warning_handler("Application %s returned non-zero value from "
					"'initialize', not registering...", appName );
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
	if(!appName || ! methodName || ! ses) return -1;
	char* error;

	info_handler("Running method [%s] for app [%s] with request id %d and "
			"thread trace %s", methodName, appName, reqId, ses->session_id );

	osrfApplication* app = _osrfAppFindApplication(appName);
	if(!app) return warning_handler( "Application not found: %s", appName );

	osrfMethod* method = __osrfAppFindMethod( app, methodName );
	if(!method) return warning_handler( "NOT FOUND: app %s / method %s", appName, methodName );

	/* this is the method we're gonna run */
	int (*meth) (osrfMethodDispatcher*);	

	/* open the method */
	*(void **) (&meth) = dlsym(app->handle, method->symbol);

	if( (error = dlerror()) != NULL ) {
		return warning_handler("Unable to locate method symbol [%s] "
				"for method %s and app %s", method->symbol, method->name, app->name );
	}

	osrfMethodDispatcher d;
	d.session = ses;
	d.method = method;
	d.params = params;
	d.request = reqId;

	/* run the method */
	int ret = (*meth) (&d);

	debug_handler("method returned %d", ret );


	if(ret == -1) {
		osrfAppSessionStatus( ses, OSRF_STATUS_INTERNALSERVERERROR, 
					reqId, "An unknown server error occurred" );
		return -1;
	}

	return 0;
}



