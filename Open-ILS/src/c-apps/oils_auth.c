#include "opensrf/osrf_app_session.h"
#include "opensrf/osrf_application.h"
#include "objson/object.h"
#include "opensrf/osrf_log.h"
#include "oils_utils.h"

#define OILS_AUTH_CACHE_PRFX "oils_auth_"


#define MODULENAME "open-ils.auth"

int osrfAppInitialize();
int osrfAppChildInit();
int osrfMathRun( osrfMethodContext* );


int osrfAppInitialize() {

	osrfLogInit(MODULENAME);

	osrfAppRegisterMethod( 
		MODULENAME, 
		"open-ils.auth.authenticate.init", 
		"oilsAuthInit", 
		"Start the authentication process and returns the intermediate authentication seed",
		" [ username ]", 1 );

	osrfAppRegisterMethod( 
		MODULENAME, 
		"open-ils.auth.authenticate.complete", 
		"oilsAuthComplete", 
		"Completes the authentication process and returns the auth token",
		"[ username, md5sum( seed + password ) ]", 2 );

	osrfAppRegisterMethod( 
		MODULENAME, 
		"open-ils.auth.session.retrieve", 
		"oilsAuthSessionRetrieve", 
		"Returns the user object (password blanked) for the given login session",
		"[ authToken ]", 1 );

	osrfAppRegisterMethod( 
		MODULENAME, 
		"open-ils.auth.session.delete", 
		"oilsAuthSessionDelete", 
		"Destroys the given login session",
		"[ authToken ]",  1 );

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

		osrfLog( OSRF_DEBUG, "oilsAuthInit(): has seed %s and key %s", md5seed, key );

		resp = jsonNewObject(md5seed);	
		osrfAppRequestRespondComplete( ctx->session, ctx->request, resp );

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
	char* storageMethod = "open-ils.storage.direct.actor.user.search.usrname.atomic";

	if( uname && password ) {

		/* grab the user object from storage */
		osrfLog( OSRF_DEBUG, "oilsAuth calling method %s with username %s", storageMethod, uname );

		osrfAppSession* session = osrfAppSessionClientInit( "open-ils.storage" ); /**/
		jsonObject* params = jsonNewObject(uname); /**/
		int reqid = osrfAppSessionMakeRequest( session, params, storageMethod, 1, NULL );
		jsonObjectFree(params);
		osrfMessage* omsg = osrfAppSessionRequestRecv( session, reqid, 60 ); /**/

		if(!omsg) { 
			osrfAppSessionFree(session);
			return osrfAppRequestRespondException( ctx->session, ctx->request,
				"No response from storage server for method %s", storageMethod ); 
		}

		jsonObject* userObj = osrfMessageGetResult(omsg);

		char* _j = jsonObjectToJSON(userObj);
		osrfLog( OSRF_DEBUG, "Auth received user object from storage: %s", _j );
		free(_j);

		/* the method is atomic, grab the first user we receive */
		if( userObj ) userObj = jsonObjectGetIndex(userObj, 0);
		
		if(!userObj) { /* XXX needs to be a 'friendly' exception */
			osrfMessageFree(omsg);
			osrfAppSessionFree(session);
			return osrfAppRequestRespondException( ctx->session, 
					ctx->request, "User %s not found in the database", uname );
		}

		char* realPassword = oilsFMGetString( userObj, "passwd" ); /**/
		char* seed = osrfCacheGetString( "%s%s", OILS_AUTH_CACHE_PRFX, uname ); /**/

		if(!seed) {
			osrfMessageFree(omsg);
			osrfAppSessionFree(session);
			return osrfAppRequestRespondException( ctx->session,
				ctx->request, "No authentication seed found. "
				"open-ils.auth.authenticate.init must be called first");
		}

		osrfLog( OSRF_DEBUG, "oilsAuth retrieved seed from cache: %s", seed );
		char* maskedPw = md5sum( "%s%s", seed, realPassword );
		if(!maskedPw) return -1;
		osrfLog( OSRF_DEBUG, "oilsAuth generated masked password %s. "
				"Testing against provided password %s", maskedPw, password );

		jsonObject* response;

		if( !strcmp( maskedPw, password ) ) {

			osrfLog( OSRF_INFO, "Login successful for %s", uname );
			char* string = va_list_to_string( "%d.%d.%s", getpid(), time(NULL), uname ); /**/
			char* authToken = md5sum(string); /**/
			char* authKey = va_list_to_string( "%s%s", OILS_AUTH_CACHE_PRFX, authToken ); /**/
			oilsFMSetString( userObj, "passwd", "" );
			osrfCachePutObject( authKey, userObj, 28800 ); /* XXX config value */
			response = jsonNewObject( authToken );
			free(string); free(authToken); free(authKey);

		} else {
			osrfLog( OSRF_INFO, "Login failed for for %s", uname );
			response = jsonNewNumberObject(0);
		}

		osrfAppRequestRespondComplete( ctx->session, ctx->request, response ); 
		jsonObjectFree(response);
		osrfMessageFree(omsg);
		osrfAppSessionFree(session);

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

	osrfAppRequestRespondComplete( ctx->session, ctx->request, userObj );
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

	osrfAppRequestRespondComplete( ctx->session, ctx->request, resp );
	jsonObjectFree(resp);
	return 0;
}



