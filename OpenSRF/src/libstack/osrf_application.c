#include "osrf_application.h"
#include "osrf_log.h"
#include "objson/object.h"

//osrfApplication* __osrfAppList = NULL; 

osrfHash* __osrfAppHash = NULL;


int osrfAppRegisterApplication( char* appName, char* soFile ) {
	if(!appName || ! soFile) return -1;
	char* error;

	if(!__osrfAppHash) __osrfAppHash = osrfNewHash();

	info_handler("Registering application %s with file %s", appName, soFile );

	osrfApplication* app = safe_malloc(sizeof(osrfApplication));
	app->handle = dlopen (soFile, RTLD_NOW);

	if(!app->handle) {
		warning_handler("Failed to dlopen library file %s: %s", soFile, dlerror() );
		dlerror(); /* clear the error */
		free(app);
		return -1;
	}

	app->methods = osrfNewHash();
	osrfHashSet( __osrfAppHash, app, appName );

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

	osrfLogInit(appName);

	return 0;
}


int osrfAppRegisterMethod( char* appName, char* methodName, 
		char* symbolName, char* notes, char* params, int argc, int streaming ) {

	return _osrfAppRegisterMethod(appName, methodName, 
			symbolName, notes, params, argc, streaming, 0 );
}

int _osrfAppRegisterMethod( char* appName, char* methodName, 
		char* symbolName, char* notes, char* params, int argc, int streaming, int system ) {

	if( !appName || ! methodName  ) return -1;

	osrfApplication* app = _osrfAppFindApplication(appName);
	if(!app) return warning_handler("Unable to locate application %s", appName );

	debug_handler("Registering method %s for app %s", methodName, appName );

	osrfMethod* method = _osrfAppBuildMethod(
		methodName, symbolName, notes, params, argc, system, 0 );		
	method->streaming = streaming;

	/* plug the method into the list of methods */
	osrfHashSet( app->methods, method, method->name );

	if( streaming ) { /* build the atomic counterpart */
		osrfMethod* atomicMethod = _osrfAppBuildMethod(
			methodName, symbolName, notes, params, argc, system, 1 );		
		osrfHashSet( app->methods, atomicMethod, atomicMethod->name );
	}

	return 0;
}



osrfMethod* _osrfAppBuildMethod( char* methodName, 
	char* symbolName, char* notes, char* params, int argc, int sysmethod, int atomic ) {

	osrfMethod* method					= safe_malloc(sizeof(osrfMethod));

	if(methodName) method->name		= strdup(methodName);
	if(symbolName) method->symbol		= strdup(symbolName);
	if(notes) method->notes				= strdup(notes);
	if(params) method->paramNotes		= strdup(params);

	method->argc							= argc;
	method->sysmethod						= sysmethod;
	method->atomic							= atomic;
	method->cachable						= 0;

	if(atomic) { /* add ".atomic" to the end of the name */
		char mb[strlen(method->name) + 8];
		sprintf(mb, "%s.atomic", method->name);
		free(method->name);
		method->name = strdup(mb);
		method->streaming = 1;
	}

	debug_handler("Built method %s", method->name );

	return method;
}


int __osrfAppRegisterSysMethods( char* app ) {

	_osrfAppRegisterMethod( 
			app, OSRF_SYSMETHOD_INTROSPECT, NULL, 
			"Return a list of methods whose names have the same initial "
			"substring as that of the provided method name",
			"( methodNameSubstring )", 1, 1 , 1);

	_osrfAppRegisterMethod( 
			app, OSRF_SYSMETHOD_INTROSPECT_ALL, NULL, 
			"Returns a complete list of methods", "()", 0, 1, 1 ); 

	_osrfAppRegisterMethod( 
			app, OSRF_SYSMETHOD_ECHO, NULL, 
			"Echos all data sent to the server back to the client", 
			"([a, b, ...])", 0, 1, 1);

	return 0;
}

osrfApplication* _osrfAppFindApplication( char* name ) {
	if(!name) return NULL;
	return (osrfApplication*) osrfHashGet(__osrfAppHash, name);
}

osrfMethod* __osrfAppFindMethod( osrfApplication* app, char* methodName ) {
	if(!app || ! methodName) return NULL;
	return (osrfMethod*) osrfHashGet( app->methods, methodName );
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
	context.responses = NULL;

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

	int retcode = 0;

	if( method->sysmethod ) {
		retcode = __osrfAppRunSystemMethod(&context);

	} else {

		/* open and now run the method */
		*(void **) (&meth) = dlsym(app->handle, method->symbol);

		if( (error = dlerror()) != NULL ) {
			return osrfAppRequestRespondException( ses, reqId, 
				"Unable to execute method [%s]  for service %s", methodName, appName );
		}

		retcode = (*meth) (&context);
	}

	if(retcode < 0) 
		return osrfAppRequestRespondException( 
				ses, reqId, "An unknown server error occurred" );

	return __osrfAppPostProcess( &context, retcode );

}


int osrfAppRespond( osrfMethodContext* ctx, jsonObject* data ) {
	return _osrfAppRespond( ctx, data, 0 );
}

int osrfAppRespondComplete( osrfMethodContext* context, jsonObject* data ) {
	return _osrfAppRespond( context, data, 1 );
}

int _osrfAppRespond( osrfMethodContext* ctx, jsonObject* data, int complete ) {
	if(!(ctx && ctx->method)) return -1;

	if( ctx->method->atomic ) {
		osrfLog( OSRF_DEBUG, 
			"Adding responses to stash for atomic method %s", ctx->method );

		if( ctx->responses == NULL )												
			ctx->responses = jsonParseString("[]");							
		jsonObjectPush( ctx->responses, jsonObjectClone(data) );	
	}


	if( !ctx->method->atomic && ! ctx->method->cachable ) {
		if(complete) 
			osrfAppRequestRespondComplete( ctx->session, ctx->request, data );
		else
			osrfAppRequestRespond( ctx->session, ctx->request, data );
		return 0;
	}

	return 0;
}




int __osrfAppPostProcess( osrfMethodContext* ctx, int retcode ) {
	if(!(ctx && ctx->method)) return -1;

	osrfLog( OSRF_DEBUG, "Postprocessing method %s with retcode %d",
			ctx->method->name, retcode );

	if(ctx->responses) { /* we have cached responses to return */

		osrfAppRequestRespondComplete( ctx->session, ctx->request, ctx->responses );
		jsonObjectFree(ctx->responses);
		ctx->responses = NULL;

	} else {

		if( retcode > 0 ) 
			osrfAppSessionStatus( ctx->session, OSRF_STATUS_COMPLETE,  
					"osrfConnectStatus", ctx->request, "Request Complete" );
	}

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
	jsonObjectSetKey(resp, "api_name",	jsonNewObject(method->name));
	jsonObjectSetKey(resp, "method",		jsonNewObject(method->symbol));
	jsonObjectSetKey(resp, "service",	jsonNewObject(ctx->session->remote_service));
	jsonObjectSetKey(resp, "notes",		jsonNewObject(method->notes));
	jsonObjectSetKey(resp, "argc",		jsonNewNumberObject(method->argc));
	jsonObjectSetKey(resp, "params",		jsonNewObject(method->paramNotes) );
	jsonObjectSetKey(resp, "sysmethod", jsonNewNumberObject(method->sysmethod) );
	jsonObjectSetKey(resp, "atomic",		jsonNewNumberObject(method->atomic) );
	jsonObjectSetKey(resp, "cachable",	jsonNewNumberObject(method->cachable) );
	jsonObjectSetClass(resp, "method");
}



int __osrfAppRunSystemMethod(osrfMethodContext* ctx) {
	OSRF_METHOD_VERIFY_CONTEXT(ctx);

	if(	!strcmp(ctx->method->name, OSRF_SYSMETHOD_INTROSPECT_ALL ) || 
			!strcmp(ctx->method->name, OSRF_SYSMETHOD_INTROSPECT_ALL_ATOMIC )) {

		return osrfAppIntrospectAll(ctx);
	}


	if(	!strcmp(ctx->method->name, OSRF_SYSMETHOD_INTROSPECT ) ||
			!strcmp(ctx->method->name, OSRF_SYSMETHOD_INTROSPECT_ATOMIC )) {

		return osrfAppIntrospect(ctx);
	}

	osrfAppRequestRespondException( ctx->session, 
			ctx->request, "System method implementation not found");

	return 0;
}


int osrfAppIntrospect( osrfMethodContext* ctx ) {

	jsonObject* resp = NULL;
	char* methodSubstring = jsonObjectGetString( jsonObjectGetIndex(ctx->params, 0) );
	osrfApplication* app = _osrfAppFindApplication( ctx->session->remote_service );
	int len = 0;

	if(!methodSubstring) return 1; /* respond with no methods */

	if(app) {

		osrfHashIterator* itr = osrfNewHashIterator(app->methods);
		osrfMethod* method;

		while( (method = osrfHashIteratorNext(itr)) ) {
			if( (len = strlen(methodSubstring)) <= strlen(method->name) ) {
				if( !strncmp( method->name, methodSubstring, len) ) {
					resp = jsonNewObject(NULL);
					__osrfAppSetIntrospectMethod( ctx, method, resp );
					osrfAppRespond(ctx, resp);
					jsonObjectFree(resp);
				}
			}
		}
		osrfHashIteratorFree(itr);
		return 1;
	}

	return -1;

}


int osrfAppIntrospectAll( osrfMethodContext* ctx ) {
	jsonObject* resp = NULL;
	osrfApplication* app = _osrfAppFindApplication( ctx->session->remote_service );

	if(app) {
		osrfHashIterator* itr = osrfNewHashIterator(app->methods);
		osrfMethod* method;
		while( (method = osrfHashIteratorNext(itr)) ) {
			resp = jsonNewObject(NULL);
			__osrfAppSetIntrospectMethod( ctx, method, resp );
			osrfAppRespond(ctx, resp);
			jsonObjectFree(resp);
		}
		osrfHashIteratorFree(itr);
		return 1;
	}

	return -1;
}


