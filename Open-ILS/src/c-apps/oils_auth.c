#include "opensrf/osrf_app_session.h"
#include "opensrf/osrf_application.h"
#include "opensrf/osrf_settings.h"
#include "objson/object.h"
#include "opensrf/log.h"
#include "oils_utils.h"
#include "oils_constants.h"
#include "oils_event.h"

#define OILS_AUTH_CACHE_PRFX "oils_auth_"

#define MODULENAME "open-ils.auth"

int osrfAppInitialize();
int osrfAppChildInit();

int __oilsAuthOPACTimeout = 0;
int __oilsAuthStaffTimeout = 0;


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

/** Verifies that the user has permission to login with the 
 * given type.  If the permission fails, an oilsEvent is returned
 * to the caller.
 * @return -1 if the permission check failed, 0 if ther permission
 * is granted
 */
int oilsAuthCheckLoginPerm( 
		osrfMethodContext* ctx, jsonObject* userObj, char* type ) {

	if(!(userObj && type)) return -1;
	oilsEvent* perm = NULL;

	if(!strcmp(type, "opac")) {
		char* permissions[] = { "OPAC_LOGIN" };
		perm = oilsUtilsCheckPerms( oilsFMGetObjectId( userObj ), -1, permissions, 1 );

	} else if(!strcmp(type, "staff")) {
		char* permissions[] = { "STAFF_LOGIN" };
		perm = oilsUtilsCheckPerms( oilsFMGetObjectId( userObj ), -1, permissions, 1 );
	}

	if(perm) {
		osrfAppRespondComplete( ctx, oilsEventToJSON(perm) ); 
		oilsEventFree(perm);
		return -1;
	}

	return 0;
}

/**
 * Returns 1 if the password provided matches the user's real password
 * Returns 0 otherwise
 * Returns -1 on error
 */
int oilsAuthVerifyPassword( 
		osrfMethodContext* ctx, jsonObject* userObj, char* uname, char* password ) {

	int ret = 0;
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

	if( !strcmp( maskedPw, password ) ) ret = 1;

	free(realPassword);
	free(seed);
	free(maskedPw);

	return ret;
}

double oilsAuthGetTimeout( char* type, double orgloc ) {
	if(!__oilsAuthOPACTimeout) {

		__oilsAuthOPACTimeout = 
			jsonObjectGetNumber( 
				osrf_settings_host_value_object( 
					"/apps/open-ils.auth/app_settings/default_timeout/opac"));

		__oilsAuthStaffTimeout = 
			jsonObjectGetNumber( 
				osrf_settings_host_value_object( 
					"/apps/open-ils.auth/app_settings/default_timeout/staff" ));

		osrfLogInfo("Set default auth timetouts: opac => %d : staff => %d",
				__oilsAuthOPACTimeout, __oilsAuthStaffTimeout );
	}

	char* setting = NULL;

	if(!strcmp(type, "opac")) {
		if(orgloc < 1) return __oilsAuthOPACTimeout;
		setting = OILS_ORG_SETTING_OPAC_TIMEOUT;

	} else if(!strcmp(type, "staff")) {
		if(orgloc < 1) return __oilsAuthStaffTimeout;
		setting = OILS_ORG_SETTING_STAFF_TIMEOUT;
	}

	char* timeout = oilsUtilsFetchOrgSetting( orgloc, setting );
	double t = atof(timeout);
	free(timeout);
	return t ;
}

/* Adds the authentication token to the user cache.  The timeout for the 
 * auth token is based on the type of login as well as (if type=='opac') 
 * the org location id.
 * Returns the event that should be returned to the user.  
 * Event must be freed
 */
oilsEvent* oilsAuthHandleLoginOK( 
		jsonObject* userObj, char* uname, char* type, double orgloc ) { 
		
	oilsEvent* response;
	osrfLogActivity( "User %s successfully logged in", uname );

	double timeout = oilsAuthGetTimeout( type, orgloc );
	osrfLogDebug("Auth session timeout for %s: %lf", uname, timeout );

	char* string = va_list_to_string( 
			"%d.%d.%s", getpid(), time(NULL), uname ); 
	char* authToken = md5sum(string); 
	char* authKey = va_list_to_string( 
			"%s%s", OILS_AUTH_CACHE_PRFX, authToken ); 

	oilsFMSetString( userObj, "passwd", "" );
	osrfCachePutObject( authKey, userObj, timeout ); 
	osrfLogInternal("oilsAuthComplete(): Placed user object into cache");
	response = oilsNewEvent2( OILS_EVENT_SUCCESS, jsonNewObject(authToken) );

	free(string); free(authToken); free(authKey);
	return response;
}



int oilsAuthComplete( osrfMethodContext* ctx ) {
	OSRF_METHOD_VERIFY_CONTEXT(ctx); 

	char* uname		= jsonObjectGetString(jsonObjectGetIndex(ctx->params, 0));
	char* password = jsonObjectGetString(jsonObjectGetIndex(ctx->params, 1));
	char* type		= jsonObjectGetString(jsonObjectGetIndex(ctx->params, 2));
	double orgloc	= jsonObjectGetNumber(jsonObjectGetIndex(ctx->params, 3));

	if(!type) type = "staff";

	if( !(uname && password) ) {
		return osrfAppRequestRespondException( ctx->session, ctx->request, 
			"username and password required for method: %s", ctx->method->name );
	}

	oilsEvent* response = NULL;
	jsonObject* userObj = oilsUtilsFetchUserByUsername( uname ); 
	
	if(!userObj) { 
		response = oilsNewEvent( OILS_EVENT_AUTH_FAILED );
		osrfAppRespondComplete( ctx, oilsEventToJSON(response) ); 
		oilsEventFree(response);
		return 0;
	}

	/* check to see if the user is allowed to login */
	if( oilsAuthCheckLoginPerm( ctx, userObj, type ) == -1 ) {
		jsonObjectFree(userObj);
		return 0;
	}

	int passOK = oilsAuthVerifyPassword( ctx, userObj, uname, password );
	if( passOK < 0 ) return passOK;

	if( passOK ) {
		response = oilsAuthHandleLoginOK( userObj, uname, type, orgloc );

	} else {
		response = oilsNewEvent( OILS_EVENT_AUTH_FAILED );
		osrfLogInfo( "Login failed for for %s", uname );
	}

	jsonObjectFree(userObj);
	osrfAppRespondComplete( ctx, oilsEventToJSON(response) ); 
	oilsEventFree(response);

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



