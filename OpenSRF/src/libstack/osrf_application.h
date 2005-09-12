
#include <stdio.h>
#include <dlfcn.h>
#include "opensrf/utils.h"
#include "opensrf/logging.h"
#include "objson/object.h"
#include "osrf_app_session.h"


/** 
  This macro verifies methods receive the correct parameters 
  */

#define _OSRF_METHOD_VERIFY_CONTEXT(d) \
	if(!d) return -1; \
	if(!d->session) { osrfLog( OSRF_ERROR, "Session is NULL in app reqeust" ); return -1; }\
	if(!d->method) { osrfLog( OSRF_ERROR, "Method is NULL in app reqeust" ); return -1; }\
	if(!d->params) { osrfLog( OSRF_ERROR, "Params is NULL in app reqeust %s", d->method->name ); return -1; }\
	if( d->params->type != JSON_ARRAY ) { \
		osrfLog( OSRF_ERROR, "'params' is not a JSON array for method %s", d->method->name);\
		return -1; }\
	if( !d->method->name ) { osrfLog(OSRF_ERROR, "Method name is NULL"); return -1; } 


#ifdef OSRF_LOG_PARAMS 
#define OSRF_METHOD_VERIFY_CONTEXT(d) \
	_OSRF_METHOD_VERIFY_CONTEXT(d); \
	char* __j = jsonObjectToJSON(d->params);\
	if(__j) { \
		osrfLog( OSRF_INFO, "[%s:%s] params: %s", d->session->remote_service, d->method->name, __j);\
		free(__j); \
	} 
#else
#define OSRF_METHOD_VERIFY_CONTEXT(d) _OSRF_METHOD_VERIFY_CONTEXT(d); 
#endif




#define OSRF_SYSMETHOD_INTROSPECT "opensrf.system.method"
#define OSRF_SYSMETHOD_INTROSPECT_ALL "opensrf.system.method.all"


	

	

struct _osrfApplicationStruct {
	char* name; /* the name of our application */
	void* handle; /* the lib handle */
	struct _osrfMethodStruct* methods;	/* list of methods */
	struct _osrfApplicationStruct* next; /* next application */
};
typedef struct _osrfApplicationStruct osrfApplication;


struct _osrfMethodStruct {
	char* name;				/* the method name */
	char* symbol;			/* the symbol name (function) */
	char* notes;			/* public method documentation */
	int argc;				/* how many args this method expects */
	void* methodHandle;	/* cached version of the method handle */
	struct _osrfMethodStruct* next;
}; 
typedef struct _osrfMethodStruct osrfMethod;

struct _osrfMethodContextStruct {
	osrfAppSession* session;
	osrfMethod* method;
	jsonObject* params;
	int request;
};
typedef struct _osrfMethodContextStruct osrfMethodContext;


/** 
  Register an application
  @param appName The name of the application
  @param soFile The library (.so) file that implements this application
  @return 0 on success, -1 on error
  */
int osrfAppRegisterApplication( char* appName, char* soFile );

/**
  Register a method
  @param appName The name of the application that implements the method
  @param methodName The fully qualified name of the method
  @param symbolName The symbol name (function) that implements the method
  @param notes Public documentation for this method.
  @params argc The number of arguments this method expects 
  @return 0 on success, -1 on error
  */
int osrfAppRegisterMethod( char* appName, 
		char* methodName, char* symbolName, char* notes, int argc );

/**
  Finds the given app in the list of apps
  @param name The name of the application
  @return The application pointer or NULL if there is no such application
  */
osrfApplication* _osrfAppFindApplication( char* name );

/**
  Finds the given method for the given app
  @param appName The application
  @param methodName The method to find
  @return A method pointer or NULL if no such method 
  exists for the given application
  */
osrfMethod* _osrfAppFindMethod( char* appName, char* methodName );

/**
  Finds the given method for the given app
  @param app The application object
  @param methodName The method to find
  @return A method pointer or NULL if no such method 
  exists for the given application
  */
osrfMethod* __osrfAppFindMethod( osrfApplication* app, char* methodName );


/**
  Runs the specified method for the specified application.
  @param appName The name of the application who's method to run
  @param methodName The name of the method to run
  @param ses The app session attached to this request
  @params reqId The request id for this request
  @param params The method parameters
  */
int osrfAppRunMethod( char* appName, char* methodName, 
		osrfAppSession* ses, int reqId, jsonObject* params );


/**
  Trys to run the requested method as a system method.
  A system method is a well known method that all
  servers implement.  
  @param context The current method context
  @return 0 if the method is run, -1 otherwise
  */
int __osrfAppRunSystemMethod(osrfMethodContext* context);



