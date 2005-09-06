
#include <stdio.h>
#include <dlfcn.h>
#include "opensrf/utils.h"
#include "opensrf/logging.h"
#include "objson/object.h"
#include "osrf_app_session.h"

/** 
  This macro verifies methods receive the correct parameters 
  It also creates local variables "session", "method",
  "params", and "request" 
  */

#define OSRF_METHOD_VERIFY_CONTEXT(__d) \
	if(!__d) return -1; \
	\
	osrfAppSession* session = __d->session; \
	osrfMethod*	method = __d->method; \
	jsonObject* params = __d->params; \
	int request = __d->request; \
	\
	if( !(session && method && params) ) return -1; \
	if( !params->type == JSON_ARRAY ) return -1; \
	if( !method->name ) return -1; \
	\
	char* __j = jsonObjectToJSON(params);\
	if(__j) { \
		debug_handler("Service: %s | Params: %s", session->remote_service, __j);free(__j);}

	

	

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


