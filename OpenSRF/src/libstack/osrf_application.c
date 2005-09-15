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

	__osrfAppRegisterSysMethods(appName);

	info_handler("Application %s registered successfully", appName );


	return 0;
}

int osrfAppRegisterMethod( char* appName, 
		char* methodName, char* symbolName, char* notes, char* params, int argc ) {

	if( !appName || ! methodName || ! symbolName ) return -1;

	osrfApplication* app = _osrfAppFindApplication(appName);
	if(!app) return warning_handler("Unable to locate application %s", appName );

	debug_handler("Registering method %s for app %s", methodName, appName );

	osrfMethod* method = _osrfAppBuildMethod(
		methodName, symbolName, notes, params, argc, 0 );		

	/* plug the method into the list of methods */
	method->next = app->methods;
	app->methods = method;
	return 0;
}


osrfMethod* _osrfAppBuildMethod( char* methodName, 
	char* symbolName, char* notes, char* params, int argc, int sysmethod ) {

	osrfMethod* method					= safe_malloc(sizeof(osrfMethod));
	if(methodName) method->name		= strdup(methodName);
	if(symbolName) method->symbol		= strdup(symbolName);
	if(notes) method->notes				= strdup(notes);
	if(params) method->paramNotes		= strdup(params);
	method->argc							= argc;
	method->sysmethod						= sysmethod;
	return method;
}


int _osrfAppRegisterSystemMethod( char* appName, char* methodName, 
		char* notes, char* params, int argc ) {
	if(!(appName && methodName)) return -1;
	osrfApplication* app = _osrfAppFindApplication(appName);
	if(!app) return warning_handler("Unable to locate application %s", appName );
	debug_handler("Registering system method %s for app %s", methodName, appName );
	osrfMethod* method = _osrfAppBuildMethod(
		methodName, NULL, notes, params, argc, 1 );		

	/* plug the method into the list of methods */
	method->next = app->methods;
	app->methods = method;
	return 0;

}

int __osrfAppRegisterSysMethods( char* app ) {

	_osrfAppRegisterSystemMethod( 
			app, OSRF_SYSMETHOD_INTROSPECT, 
			"Return a list of methods whose names have the same initial "
			"substring as that of the provided method name",
			"( methodNameSubstring )", 1 );

	_osrfAppRegisterSystemMethod( 
			app, OSRF_SYSMETHOD_INTROSPECT_ALL, 
			"Returns a complete list of methods", "()", 0 ); 

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


int osrfAppRunMethod( char* appName, char* methodName, 
		osrfAppSession* ses, int reqId, jsonObject* params ) {

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
		return osrfAppRequestRespondException( ses, 
				reqId, "Application not found: %s", appName );
	
	if( !(method = __osrfAppFindMethod( app, methodName )) ) 
		return osrfAppRequestRespondException( ses, reqId, 
				"Method [%s] not found for service %s", methodName, appName );

	context.method = method;

	#ifdef OSRF_STRICT_PARAMS
	if( method->argc > 0 ) {
		if(!params || params->type != JSON_ARRAY || params->size < method->argc )
			return osrfAppRequestRespondException( ses, reqId, 
				"Not enough params for method %s / service %s", methodName, appName );
	}
	#endif

	if( method->sysmethod ) {

		int sysres = __osrfAppRunSystemMethod(&context);
		if(sysres == 0) return 0;

		if(sysres > 0) 
			return osrfAppSessionStatus( ses, OSRF_STATUS_COMPLETE,  
					"osrfConnectStatus", reqId, "Request Complete" );

		if(sysres < 0) 
			return osrfAppRequestRespondException( 
				ses, reqId, "An unknown server error occurred" );
	}


	/* open the method */
	*(void **) (&meth) = dlsym(app->handle, method->symbol);

	if( (error = dlerror()) != NULL ) {
		return osrfAppRequestRespondException( ses, reqId, 
				"Unable to execute method [%s]  for service %s", methodName, appName );
	}

	/* run the method */
	int ret;
	if( (ret = (*meth) (&context)) < 0 )
		return osrfAppRequestRespondException( 
				ses, reqId, "An unknown server error occurred" );

	if( ret > 0 ) 
		osrfAppSessionStatus( ses, OSRF_STATUS_COMPLETE,  
				"osrfConnectStatus", reqId, "Request Complete" );

	return 0;
}

int osrfAppRequestRespondException( osrfAppSession* ses, int request, char* msg, ... ) {
	if(!ses) return -1;
	if(!msg) msg = "";
	VA_LIST_TO_STRING(msg);
	osrfLog( OSRF_WARN, "Returning method exception with message: %s", VA_BUF );
	osrfAppSessionStatus( ses, OSRF_STATUS_NOTFOUND, "osrfMethodException", request,  VA_BUF );
	return 0;
}


static void __osrfAppSetIntrospectMethod( osrfMethodContext* ctx, osrfMethod* method, jsonObject* resp ) {
	if(!(ctx && resp)) return;
	jsonObjectSetKey(resp, "api_name", jsonNewObject(method->name));
	jsonObjectSetKey(resp, "method", jsonNewObject(method->symbol));
	jsonObjectSetKey(resp, "service", jsonNewObject(ctx->session->remote_service));
	jsonObjectSetKey(resp, "notes", jsonNewObject(method->notes));
	jsonObjectSetKey(resp, "argc", jsonNewNumberObject(method->argc));
	jsonObjectSetKey(resp, "params", jsonNewObject(method->paramNotes) );
	jsonObjectSetKey(resp, "sysmethod", jsonNewNumberObject(method->sysmethod) );
	jsonObjectSetClass(resp, "method");
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
				__osrfAppSetIntrospectMethod( ctx, method, resp );
				osrfAppRequestRespond(ctx->session, ctx->request, resp);
				jsonObjectFree(resp);
				method = method->next;
			}
			return 1;
		}

		return -1;
	}


	if( !strcmp(ctx->method->name, OSRF_SYSMETHOD_INTROSPECT )) {

		jsonObject* resp = NULL;
		char* methodSubstring = jsonObjectGetString( jsonObjectGetIndex(ctx->params, 0) );
		osrfApplication* app = _osrfAppFindApplication( ctx->session->remote_service );
		int len = 0;

		if(!methodSubstring) return 1; /* respond with no methods */

		if(app) {
			osrfMethod* method = app->methods;
			while(method) {
				if( (len = strlen(methodSubstring)) <= strlen(method->name) ) {
					if( !strncmp( method->name, methodSubstring, len) ) {
						resp = jsonNewObject(NULL);
						__osrfAppSetIntrospectMethod( ctx, method, resp );
						osrfAppRequestRespond(ctx->session, ctx->request, resp);
						jsonObjectFree(resp);
					}
				}
				method = method->next;
			}
			return 1;
		}

		return -1;
	}

	return -1;
}




