#include "opensrf/osrf_app_session.h"
#include "opensrf/osrf_application.h"
#include "objson/object.h"
#include "opensrf/log.h"
#include "oils_utils.h"
#include "oils_constants.h"
#include "oils_event.h"

#define OILS_AUTH_CACHE_PRFX "oils_auth_"

#define MODULENAME "open-ils.auth"

int osrfAppInitialize();
int osrfAppChildInit();
int osrfMathRun( osrfMethodContext* );


int osrfAppInitialize() {

	osrfAppRegisterMethod( 
		MODULENAME, 
		"open-ils.auth.authenticate.init", 
		"oilsAuthInit", 
		"Start the authentication process and returns the intermediate authentication seed"
		" PARAMS( username )", 1, 0 );

	osrfAppRegisterMethod( 
		MODULENAME, 
		"open-ils.auth.authenticate.complete", 
		"oilsAuthComplete", 
		"Completes the authentication process and returns the auth token "
		"PARAMS(username, md5sum( seed + password ), type )", 2, 0 );

	osrfAppRegisterMethod( 
		MODULENAME, 
		"open-ils.auth.session.retrieve", 
		"oilsAuthSessionRetrieve", 
		"Returns the user object (password blanked) for the given login session "
		"PARAMS( authToken )", 1, 0 );

	osrfAppRegisterMethod( 
		MODULENAME, 
		"open-ils.auth.session.delete", 
		"oilsAuthSessionDelete", 
		"Destroys the given login session "
		"PARAMS( authToken )",  1, 0 );

	return 0;
}

int osrfAppChildInit() {
	return 0;
}

int oilsAuthInit( osrfMethodContext* ctx ) {
	OSRF_METHOD_VERIFY_CONTEXT(ctx); 

	jsonObject* resp;
	char* username = NULL;
	char* seed = NULL;
	char* md5seed = NULL;
	char* key = NULL;

	if( (username = jsonObjectGetString(jsonObjectGetIndex(ctx->params, 0))) ) {

		seed = va_list_to_string( "%d.%d.%s", time(NULL), getpid(), username );
		key = va_list_to_string( "%s%s", OILS_AUTH_CACHE_PRFX, username );

		md5seed = md5sum(seed);
		osrfCachePutString( key, md5seed, 30 );

		osrfLogDebug( "oilsAuthInit(): has seed %s and key %s", md5seed, key );

		resp = jsonNewObject(md5seed);	
		osrfAppRespondComplete( ctx, resp );

		jsonObjectFree(resp);
		free(seed);
		free(md5seed);
		free(key);
		return 0;
	}

	return -1;
}


int oilsAuthComplete( osrfMethodContext* ctx ) {
	OSRF_METHOD_VERIFY_CONTEXT(ctx); 

	char* uname = jsonObjectGetString(jsonObjectGetIndex(ctx->params, 0));
	char* password = jsonObjectGetString(jsonObjectGetIndex(ctx->params, 1));
	char* type		= jsonObjectGetString(jsonObjectGetIndex(ctx->params, 2));
	if(!type) type = "staff";

	if( uname && password ) {

		oilsEvent* response = NULL;
		jsonObject* userObj = oilsUtilsFetchUserByUsername( uname ); /* XXX */
		
		if(!userObj) { 
			response = oilsNewEvent( OILS_EVENT_AUTH_FAILED );
			osrfAppRespondComplete( ctx, oilsEventToJSON(response) ); 
			oilsEventFree(response);
			return 0;
		}

		/* check to see if the user is allowed to login */
		oilsEvent* perm = NULL;

		if(!strcmp(type, "opac")) {
			char* permissions[] = { "OPAC_LOGIN" };
			perm = oilsUtilsCheckPerms( oilsFMGetObjectId( userObj ), -1, permissions, 1 );

		} else if(!strcmp(type, "staff")) {
			char* permissions[] = { "STAFF_LOGIN" };
			perm = oilsUtilsCheckPerms( oilsFMGetObjectId( userObj ), -1, permissions, 1 );
		}

		if(perm) {
			jsonObjectFree(userObj);
			osrfAppRespondComplete( ctx, oilsEventToJSON(perm) ); 
			oilsEventFree(perm);
			return 0;
		}



		char* realPassword = oilsFMGetString( userObj, "passwd" ); /**/
		char* seed = osrfCacheGetString( "%s%s", OILS_AUTH_CACHE_PRFX, uname ); /**/

		if(!seed) {
			return osrfAppRequestRespondException( ctx->session,
				ctx->request, "No authentication seed found. "
				"open-ils.auth.authenticate.init must be called first");
		}

		osrfLogDebug( "oilsAuth retrieved seed from cache: %s", seed );
		char* maskedPw = md5sum( "%s%s", seed, realPassword );
		if(!maskedPw) return -1;
		osrfLogDebug( "oilsAuth generated masked password %s. "
				"Testing against provided password %s", maskedPw, password );


		if( !strcmp( maskedPw, password ) ) {

			osrfLogActivity( "User %s successfully logged in", uname );

			char* string = va_list_to_string( "%d.%d.%s", getpid(), time(NULL), uname ); /**/
			char* authToken = md5sum(string); /**/
			char* authKey = va_list_to_string( "%s%s", OILS_AUTH_CACHE_PRFX, authToken ); /**/

			osrfLogInternal("oilsAuthComplete(): Setting fieldmapper string on the user object");
			oilsFMSetString( userObj, "passwd", "" );
			osrfCachePutObject( authKey, userObj, 28800 ); /* XXX config value */
			osrfLogInternal("oilsAuthComplete(): Placed user object into cache");
			response = oilsNewEvent2( OILS_EVENT_SUCCESS, jsonNewObject(authToken) );
			free(string); free(authToken); free(authKey);
			jsonObjectFree(userObj);

		} else {

			response = oilsNewEvent( OILS_EVENT_AUTH_FAILED );
			osrfLogInfo( "Login failed for for %s", uname );
		}

		osrfLogInternal("oilsAuthComplete responding to client");
		osrfAppRespondComplete( ctx, oilsEventToJSON(response) ); 
		oilsEventFree(response);

	} else {
		return osrfAppRequestRespondException( ctx->session, ctx->request, 
			"username and password required for method: %s", ctx->method->name );
	}

	return 0;

}

int oilsAuthSessionRetrieve( osrfMethodContext* ctx ) {
	OSRF_METHOD_VERIFY_CONTEXT(ctx); 

	char* authToken = jsonObjectGetString( jsonObjectGetIndex(ctx->params, 0));
	jsonObject* userObj = NULL;

	if( authToken ){
		char* key = va_list_to_string("%s%s", OILS_AUTH_CACHE_PRFX, authToken ); /**/
		userObj = osrfCacheGetObject( key ); /**/
		free(key);
	}

	osrfAppRespondComplete( ctx, userObj );
	jsonObjectFree(userObj);
	return 0;
}

int oilsAuthSessionDelete( osrfMethodContext* ctx ) {
	OSRF_METHOD_VERIFY_CONTEXT(ctx); 

	char* authToken = jsonObjectGetString( jsonObjectGetIndex(ctx->params, 0) );
	jsonObject* resp = NULL;

	if( authToken ) {
		char* key = va_list_to_string("%s%s", OILS_AUTH_CACHE_PRFX, authToken ); /**/
		osrfCacheRemove(key);
		resp = jsonNewObject(authToken); /**/
		free(key);
	}

	osrfAppRespondComplete( ctx, resp );
	jsonObjectFree(resp);
	return 0;
}



