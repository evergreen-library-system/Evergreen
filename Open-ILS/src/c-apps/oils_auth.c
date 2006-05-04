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

#define OILS_AUTH_OPAC "opac"
#define OILS_AUTH_STAFF "staff"
#define OILS_AUTH_TEMP "temp"

int osrfAppInitialize();
int osrfAppChildInit();

int __oilsAuthOPACTimeout = 0;
int __oilsAuthStaffTimeout = 0;
int __oilsAuthOverrideTimeout = 0;


int osrfAppInitialize() {

	osrfLogInfo(OSRF_LOG_MARK, "Initializing Auth Server...");

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
		"Completes the authentication process.  Returns an object like so: "
		"{authtoken : <token>, authtime:<time>}, where authtoken is the login "
		"tokena and authtime is the number of seconds the session will be active"
		"PARAMS(username, md5sum( seed + password ), type, org_id ) "
		"type can be one of 'opac','staff', or 'temp' and it defaults to 'staff' "
		"org_id is the location at which the login should be considered "
		"active for login timeout purposes"	, 1, 0 );

	osrfAppRegisterMethod( 
		MODULENAME, 
		"open-ils.auth.session.retrieve", 
		"oilsAuthSessionRetrieve", 
		"Pass in the auth token and this retrieves the user object.  The auth "
		"timeout is reset when this call is made "
		"Returns the user object (password blanked) for the given login session "
		"PARAMS( authToken )", 1, 0 );

	osrfAppRegisterMethod( 
		MODULENAME, 
		"open-ils.auth.session.delete", 
		"oilsAuthSessionDelete", 
		"Destroys the given login session "
		"PARAMS( authToken )",  1, 0 );

	osrfAppRegisterMethod(
		MODULENAME,
		"open-ils.auth.session.reset_timeout",
		"oilsAuthResetTimeout",
		"Resets the login timeout for the given session "
		"Returns an ILS Event with payload = session_timeout of session "
		"is found, otherwise returns the NO_SESSION event"
		"PARAMS( authToken )", 1, 0 );

	return 0;
}

int osrfAppChildInit() {
	return 0;
}

int oilsAuthInit( osrfMethodContext* ctx ) {
	OSRF_METHOD_VERIFY_CONTEXT(ctx); 

	jsonObject* resp;

	char* username = NULL;
	char* seed		= NULL;
	char* md5seed	= NULL;
	char* key		= NULL;

	if( (username = jsonObjectToSimpleString(jsonObjectGetIndex(ctx->params, 0))) ) {

		seed = va_list_to_string( "%d.%d.%s", time(NULL), getpid(), username );
		key = va_list_to_string( "%s%s", OILS_AUTH_CACHE_PRFX, username );

		md5seed = md5sum(seed);
		osrfCachePutString( key, md5seed, 30 );

		osrfLogDebug( OSRF_LOG_MARK, "oilsAuthInit(): has seed %s and key %s", md5seed, key );

		resp = jsonNewObject(md5seed);	
		osrfAppRespondComplete( ctx, resp );

		jsonObjectFree(resp);
		free(seed);
		free(md5seed);
		free(key);
		free(username);
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

	if(!strcasecmp(type, OILS_AUTH_OPAC)) {
		char* permissions[] = { "OPAC_LOGIN" };
		perm = oilsUtilsCheckPerms( oilsFMGetObjectId( userObj ), -1, permissions, 1 );

	} else if(!strcasecmp(type, OILS_AUTH_STAFF)) {
		char* permissions[] = { "STAFF_LOGIN" };
		perm = oilsUtilsCheckPerms( oilsFMGetObjectId( userObj ), -1, permissions, 1 );

	} else if(!strcasecmp(type, OILS_AUTH_TEMP)) {
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

	osrfLogDebug(OSRF_LOG_MARK,  "oilsAuth retrieved seed from cache: %s", seed );
	char* maskedPw = md5sum( "%s%s", seed, realPassword );
	if(!maskedPw) return -1;
	osrfLogDebug(OSRF_LOG_MARK,  "oilsAuth generated masked password %s. "
			"Testing against provided password %s", maskedPw, password );

	if( !strcmp( maskedPw, password ) ) ret = 1;

	free(realPassword);
	free(seed);
	free(maskedPw);

	return ret;
}

/**
 * Calculates the login timeout
 * 1. If orgloc is 1 or greater and has a timeout specified as an 
 * org unit setting, it is used
 * 2. If orgloc is not valid, we check the org unit auth timeout 
 * setting for the home org unit of the user logging in
 * 3. If that setting is not defined, we use the configured defaults
 */
double oilsAuthGetTimeout( jsonObject* userObj, char* type, double orgloc ) {

	if(!__oilsAuthOPACTimeout) { /* Load the default timeouts */

		__oilsAuthOPACTimeout = 
			jsonObjectGetNumber( 
				osrf_settings_host_value_object( 
					"/apps/open-ils.auth/app_settings/default_timeout/opac"));

		__oilsAuthStaffTimeout = 
			jsonObjectGetNumber( 
				osrf_settings_host_value_object( 
					"/apps/open-ils.auth/app_settings/default_timeout/staff" ));

		__oilsAuthOverrideTimeout = 
			jsonObjectGetNumber( 
				osrf_settings_host_value_object( 
					"/apps/open-ils.auth/app_settings/default_timeout/temp" ));


		osrfLogInfo(OSRF_LOG_MARK, "Set default auth timetouts: opac => %d : staff => %d : temp => %d",
				__oilsAuthOPACTimeout, __oilsAuthStaffTimeout, __oilsAuthOverrideTimeout );
	}

	char* setting = NULL;

	double home_ou = jsonObjectGetNumber( oilsFMGetObject( userObj, "home_ou" ) );
	if(orgloc < 1) orgloc = (int) home_ou;

	if(!strcmp(type, OILS_AUTH_OPAC)) 
		setting = OILS_ORG_SETTING_OPAC_TIMEOUT;
	else if(!strcmp(type, OILS_AUTH_STAFF)) 
		setting = OILS_ORG_SETTING_STAFF_TIMEOUT;
	else if(!strcmp(type, OILS_AUTH_TEMP)) 
		setting = OILS_ORG_SETTING_TEMP_TIMEOUT;

	char* timeout = oilsUtilsFetchOrgSetting( orgloc, setting );

	if(!timeout) {
		if( orgloc != home_ou ) {
			osrfLogDebug(OSRF_LOG_MARK, "Auth timeout not defined for org %d, "
								"trying home_ou %d", orgloc, home_ou );
			timeout = oilsUtilsFetchOrgSetting( (int) home_ou, setting );
		}
		if(!timeout) {
			if(!strcmp(type, OILS_AUTH_STAFF)) return __oilsAuthStaffTimeout;
			if(!strcmp(type, OILS_AUTH_TEMP)) return __oilsAuthOverrideTimeout;
			return __oilsAuthOPACTimeout;
		}
	}

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
	osrfLogActivity(OSRF_LOG_MARK,  "User %s successfully logged in", uname );

	double timeout;
	char* wsorg = jsonObjectToSimpleString(oilsFMGetObject(userObj, "ws_ou"));
	if(wsorg) { /* if there is a workstation, use it for the timeout */
		osrfLogDebug( OSRF_LOG_MARK, 
				"Auth session trying workstation id %d for auth timeout", atoi(wsorg));
		timeout = oilsAuthGetTimeout( userObj, type, atoi(wsorg) );
		free(wsorg);
	} else {
		osrfLogDebug( OSRF_LOG_MARK, 
				"Auth session trying org from param [%d] for auth timeout", orgloc );
		timeout = oilsAuthGetTimeout( userObj, type, orgloc );
	}
	osrfLogDebug(OSRF_LOG_MARK, "Auth session timeout for %s: %lf", uname, timeout );

	char* string = va_list_to_string( 
			"%d.%d.%s", getpid(), time(NULL), uname ); 
	char* authToken = md5sum(string); 
	char* authKey = va_list_to_string( 
			"%s%s", OILS_AUTH_CACHE_PRFX, authToken ); 

	oilsFMSetString( userObj, "passwd", "" );
	jsonObject* cacheObj = jsonParseString("{\"authtime\": %lf}", timeout);
	jsonObjectSetKey( cacheObj, "userobj", jsonObjectClone(userObj));

	osrfCachePutObject( authKey, cacheObj, timeout ); 
	jsonObjectFree(cacheObj);
	osrfLogInternal(OSRF_LOG_MARK, "oilsAuthComplete(): Placed user object into cache");
	jsonObject* payload = jsonParseString(
		"{ \"authtoken\": \"%s\", \"authtime\": %lf }", authToken, timeout );

	response = oilsNewEvent2( OSRF_LOG_MARK, OILS_EVENT_SUCCESS, payload );
	free(string); free(authToken); free(authKey);
	jsonObjectFree(payload);

	return response;
}

oilsEvent* oilsAuthVerifyWorkstation( 
		osrfMethodContext* ctx, jsonObject* userObj, char* ws ) {
	osrfLogInfo(OSRF_LOG_MARK, "Attaching workstation to user at login: %s", ws);
	jsonObject* workstation = oilsUtilsFetchWorkstationByName(ws);
	if(!workstation) return oilsNewEvent(OSRF_LOG_MARK, "WORKSTATION_NOT_FOUND");
	long wsid = oilsFMGetObjectId(workstation);
	LONG_TO_STRING(wsid);
	char* orgid = oilsFMGetString(workstation, "owning_lib");
	oilsFMSetString(userObj, "wsid", LONGSTR);
	oilsFMSetString(userObj, "ws_ou", orgid);
	free(orgid);
	return NULL;
}



int oilsAuthComplete( osrfMethodContext* ctx ) {
	OSRF_METHOD_VERIFY_CONTEXT(ctx); 

	jsonObject* args		= jsonObjectGetIndex(ctx->params, 0);

	char* uname				= jsonObjectGetString(jsonObjectGetKey(args, "username"));
	char* password			= jsonObjectGetString(jsonObjectGetKey(args, "password"));
	char* type				= jsonObjectGetString(jsonObjectGetKey(args, "type"));
	double orgloc			= jsonObjectGetNumber(jsonObjectGetKey(args, "org"));
	char* workstation		= jsonObjectGetString(jsonObjectGetKey(args, "workstation"));
	char* barcode			= jsonObjectToSimpleString(jsonObjectGetKey(args, "barcode"));


	if(!type) type = OILS_AUTH_STAFF;

	if( !( (uname || barcode) && password) ) {
		free(barcode);
		return osrfAppRequestRespondException( ctx->session, ctx->request, 
			"username/barocode and password required for method: %s", ctx->method->name );
	}

	oilsEvent* response = NULL;
	jsonObject* userObj = NULL;

	if(uname) userObj = oilsUtilsFetchUserByUsername( uname ); 
	else if(barcode) userObj = oilsUtilsFetchUserByBarcode( barcode );
	
	if(!userObj) { 
		response = oilsNewEvent( OSRF_LOG_MARK, OILS_EVENT_AUTH_FAILED );
		osrfAppRespondComplete( ctx, oilsEventToJSON(response) ); 
		oilsEventFree(response);
		free(barcode);
		return 0;
	}

	/* check to see if the user is allowed to login */
	if( oilsAuthCheckLoginPerm( ctx, userObj, type ) == -1 ) {
		jsonObjectFree(userObj);
		free(barcode);
		return 0;
	}

	
	int passOK = -1;
	if(uname) passOK = oilsAuthVerifyPassword( ctx, userObj, uname, password );
	else if (barcode) 
		passOK = oilsAuthVerifyPassword( ctx, userObj, barcode, password );

	if( passOK < 0 ) {
		free(barcode);
		return passOK;
	}

	/* if a workstation is defined, flesh the user with the workstation info */
	if( workstation != NULL ) {
		osrfLogDebug(OSRF_LOG_MARK, "Workstation is %s", workstation);
		response = oilsAuthVerifyWorkstation( ctx, userObj, workstation );
		if(response) {
			jsonObjectFree(userObj);
			osrfAppRespondComplete( ctx, oilsEventToJSON(response) ); 
			oilsEventFree(response);
			free(barcode);
			return 0;
		}

	} else {
		/* otherwise, use the home org as the workstation org on the user */
		char* orgid = oilsFMGetString(userObj, "home_ou");
		oilsFMSetString(userObj, "ws_ou", orgid);
		free(orgid);
	}

	if( passOK ) {
		response = oilsAuthHandleLoginOK( userObj, uname, type, orgloc );

	} else {
		response = oilsNewEvent( OSRF_LOG_MARK, OILS_EVENT_AUTH_FAILED );
		osrfLogInfo(OSRF_LOG_MARK,  "Login failed for for %s", uname );
	}

	jsonObjectFree(userObj);
	osrfAppRespondComplete( ctx, oilsEventToJSON(response) ); 
	oilsEventFree(response);
	free(barcode);

	return 0;
}



int oilsAuthSessionDelete( osrfMethodContext* ctx ) {
	OSRF_METHOD_VERIFY_CONTEXT(ctx); 

	char* authToken = jsonObjectGetString( jsonObjectGetIndex(ctx->params, 0) );
	jsonObject* resp = NULL;

	if( authToken ) {
		osrfLogDebug(OSRF_LOG_MARK, "Removing auth session: %s", authToken );
		char* key = va_list_to_string("%s%s", OILS_AUTH_CACHE_PRFX, authToken ); /**/
		osrfCacheRemove(key);
		resp = jsonNewObject(authToken); /**/
		free(key);
	}

	osrfAppRespondComplete( ctx, resp );
	jsonObjectFree(resp);
	return 0;
}

/** Resets the auth login timeout
 * @return The event object, OILS_EVENT_SUCCESS, or OILS_EVENT_NO_SESSION
 */
oilsEvent*  _oilsAuthResetTimeout( char* authToken ) {
	if(!authToken) return NULL;

	oilsEvent* evt = NULL;
	double timeout;

	osrfLogDebug(OSRF_LOG_MARK, "Resetting auth timeout for session %s", authToken);
	char* key = va_list_to_string("%s%s", OILS_AUTH_CACHE_PRFX, authToken ); 
	jsonObject* cacheObj = osrfCacheGetObject( key ); 

	if(!cacheObj) {
		osrfLogError(OSRF_LOG_MARK, "No user in the cache exists with key %s", key);
		evt = oilsNewEvent(OSRF_LOG_MARK, OILS_EVENT_NO_SESSION);

	} else {

		timeout = jsonObjectGetNumber( jsonObjectGetKey( cacheObj, "authtime"));
		osrfCacheSetExpire( timeout, key );
		jsonObject* payload = jsonNewNumberObject(timeout);
		evt = oilsNewEvent2(OSRF_LOG_MARK, OILS_EVENT_SUCCESS, payload);
		jsonObjectFree(payload);
		jsonObjectFree(cacheObj);
	}

	free(key);
	return evt;
}

int oilsAuthResetTimeout( osrfMethodContext* ctx ) {
	OSRF_METHOD_VERIFY_CONTEXT(ctx); 
	char* authToken = jsonObjectGetString( jsonObjectGetIndex(ctx->params, 0));
	oilsEvent* evt = _oilsAuthResetTimeout(authToken);
	osrfAppRespondComplete( ctx, oilsEventToJSON(evt) );
	oilsEventFree(evt);
	return 0;
}


int oilsAuthSessionRetrieve( osrfMethodContext* ctx ) {
	OSRF_METHOD_VERIFY_CONTEXT(ctx); 

	char* authToken = jsonObjectGetString( jsonObjectGetIndex(ctx->params, 0));
	jsonObject* cacheObj = NULL;
	oilsEvent* evt = NULL;

	if( authToken ){

		evt = _oilsAuthResetTimeout(authToken);

		if( evt && strcmp(evt->event, OILS_EVENT_SUCCESS) ) {
			osrfAppRespondComplete( ctx, oilsEventToJSON(evt) );
			oilsEventFree(evt);

		} else {

			osrfLogDebug(OSRF_LOG_MARK, "Retrieving auth session: %s", authToken);
			char* key = va_list_to_string("%s%s", OILS_AUTH_CACHE_PRFX, authToken ); 
			cacheObj = osrfCacheGetObject( key ); 
			if(cacheObj) {
				osrfAppRespondComplete( ctx, jsonObjectGetKey( cacheObj, "userobj"));
				jsonObjectFree(cacheObj);
			} else {
				oilsEvent* evt = oilsNewEvent(OSRF_LOG_MARK, OILS_EVENT_NO_SESSION);
				osrfAppRespondComplete( ctx, oilsEventToJSON(evt) ); /* should be event.. */
				oilsEventFree(evt);
			}
			free(key);
		}

	} else {

		evt = oilsNewEvent(OSRF_LOG_MARK, OILS_EVENT_NO_SESSION);
		osrfAppRespondComplete( ctx, oilsEventToJSON(evt) );
		oilsEventFree(evt);
	}

	return 0;
}



