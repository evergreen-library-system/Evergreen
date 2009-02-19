#include "opensrf/osrf_app_session.h"
#include "opensrf/osrf_application.h"
#include "opensrf/osrf_settings.h"
#include "opensrf/osrf_json.h"
#include "opensrf/log.h"
#include "openils/oils_utils.h"
#include "openils/oils_constants.h"
#include "openils/oils_event.h"

#define OILS_AUTH_CACHE_PRFX "oils_auth_"

#define MODULENAME "open-ils.auth"

#define OILS_AUTH_OPAC "opac"
#define OILS_AUTH_STAFF "staff"
#define OILS_AUTH_TEMP "temp"

int osrfAppInitialize();
int osrfAppChildInit();

static int _oilsAuthOPACTimeout = 0;
static int _oilsAuthStaffTimeout = 0;
static int _oilsAuthOverrideTimeout = 0;


int osrfAppInitialize() {

	osrfLogInfo(OSRF_LOG_MARK, "Initializing Auth Server...");

    /* load and parse the IDL */
	if (!oilsInitIDL(NULL)) return 1; /* return non-zero to indicate error */

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
		"token and authtime is the number of seconds the session will be active"
		"PARAMS(username, md5sum( seed + md5sum( password ) ), type, org_id ) "
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
		"if found, otherwise returns the NO_SESSION event"
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

		if( strchr( username, ' ' ) ) {

			/* spaces are not allowed */
			resp = jsonNewObject("x");	 /* 'x' will never be a valid seed */
			osrfAppRespondComplete( ctx, resp );

		} else {

			seed = va_list_to_string( "%d.%ld.%s", time(NULL), (long) getpid(), username );
			key = va_list_to_string( "%s%s", OILS_AUTH_CACHE_PRFX, username );
	
			md5seed = md5sum(seed);
			osrfCachePutString( key, md5seed, 30 );
	
			osrfLogDebug( OSRF_LOG_MARK, "oilsAuthInit(): has seed %s and key %s", md5seed, key );
	
			resp = jsonNewObject(md5seed);	
			osrfAppRespondComplete( ctx, resp );
	
			free(seed);
			free(md5seed);
			free(key);
		}

		jsonObjectFree(resp);
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
static int oilsAuthCheckLoginPerm( 
		osrfMethodContext* ctx, const jsonObject* userObj, const char* type ) {

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
static int oilsAuthVerifyPassword( const osrfMethodContext* ctx,
		const jsonObject* userObj, const char* uname, const char* password ) {

	int ret = 0;
	char* realPassword = oilsFMGetString( userObj, "passwd" ); /**/
	char* seed = osrfCacheGetString( "%s%s", OILS_AUTH_CACHE_PRFX, uname ); /**/

	if(!seed) {
		free(realPassword);
		return osrfAppRequestRespondException( ctx->session,
			ctx->request, "No authentication seed found. "
			"open-ils.auth.authenticate.init must be called first");
	}

	osrfLogInternal(OSRF_LOG_MARK, "oilsAuth retrieved real password: [%s]", realPassword);
	osrfLogDebug(OSRF_LOG_MARK,  "oilsAuth retrieved seed from cache: %s", seed );
	char* maskedPw = md5sum( "%s%s", seed, realPassword );
	if(!maskedPw) {
		free(realPassword);
		free(seed);
		return -1;
	}
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
static double oilsAuthGetTimeout( const jsonObject* userObj, const char* type, double orgloc ) {

	if(!_oilsAuthOPACTimeout) { /* Load the default timeouts */

		jsonObject* value_obj;

		value_obj = osrf_settings_host_value_object(
			"/apps/open-ils.auth/app_settings/default_timeout/opac" );
		_oilsAuthOPACTimeout = jsonObjectGetNumber(value_obj);
		jsonObjectFree(value_obj);

		value_obj = osrf_settings_host_value_object(
			"/apps/open-ils.auth/app_settings/default_timeout/staff" );
		_oilsAuthStaffTimeout = jsonObjectGetNumber(value_obj);
		jsonObjectFree(value_obj);

		value_obj = osrf_settings_host_value_object(
				"/apps/open-ils.auth/app_settings/default_timeout/temp" );
		_oilsAuthOverrideTimeout = jsonObjectGetNumber(value_obj);
		jsonObjectFree(value_obj);


		osrfLogInfo(OSRF_LOG_MARK, "Set default auth timeouts: opac => %d : staff => %d : temp => %d",
				_oilsAuthOPACTimeout, _oilsAuthStaffTimeout, _oilsAuthOverrideTimeout );
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
			if(!strcmp(type, OILS_AUTH_STAFF)) return _oilsAuthStaffTimeout;
			if(!strcmp(type, OILS_AUTH_TEMP)) return _oilsAuthOverrideTimeout;
			return _oilsAuthOPACTimeout;
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
static oilsEvent* oilsAuthHandleLoginOK( jsonObject* userObj, const char* uname,
		const char* type, double orgloc, const char* workstation ) {
		
	oilsEvent* response;

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
	osrfLogDebug(OSRF_LOG_MARK, "Auth session timeout for %s: %f", uname, timeout );

	char* string = va_list_to_string( 
			"%d.%ld.%s", (long) getpid(), time(NULL), uname ); 
	char* authToken = md5sum(string); 
	char* authKey = va_list_to_string( 
			"%s%s", OILS_AUTH_CACHE_PRFX, authToken ); 

	const char* ws = (workstation) ? workstation : "";
	osrfLogActivity(OSRF_LOG_MARK,  
		"successful login: username=%s, authtoken=%s, workstation=%s", uname, authToken, ws );

	oilsFMSetString( userObj, "passwd", "" );
	jsonObject* cacheObj = jsonParseStringFmt("{\"authtime\": %f}", timeout);
	jsonObjectSetKey( cacheObj, "userobj", jsonObjectClone(userObj));

	osrfCachePutObject( authKey, cacheObj, timeout ); 
	jsonObjectFree(cacheObj);
	osrfLogInternal(OSRF_LOG_MARK, "oilsAuthComplete(): Placed user object into cache");
	jsonObject* payload = jsonParseStringFmt(
		"{ \"authtoken\": \"%s\", \"authtime\": %f }", authToken, timeout );

	response = oilsNewEvent2( OSRF_LOG_MARK, OILS_EVENT_SUCCESS, payload );
	free(string); free(authToken); free(authKey);
	jsonObjectFree(payload);

	return response;
}

static oilsEvent* oilsAuthVerifyWorkstation( 
		const osrfMethodContext* ctx, jsonObject* userObj, const char* ws ) {
	osrfLogInfo(OSRF_LOG_MARK, "Attaching workstation to user at login: %s", ws);
	jsonObject* workstation = oilsUtilsFetchWorkstationByName(ws);
	if(!workstation || workstation->type == JSON_NULL) {
        jsonObjectFree(workstation);
        return oilsNewEvent(OSRF_LOG_MARK, "WORKSTATION_NOT_FOUND");
    }
	long wsid = oilsFMGetObjectId(workstation);
	LONG_TO_STRING(wsid);
	char* orgid = oilsFMGetString(workstation, "owning_lib");
	oilsFMSetString(userObj, "wsid", LONGSTR);
	oilsFMSetString(userObj, "ws_ou", orgid);
	free(orgid);
	jsonObjectFree(workstation);
	return NULL;
}



/* see if the card used to login is marked as barred */
static oilsEvent* oilsAuthCheckCard( const char* barcode ) {
	if(!barcode) return NULL;
	osrfLogDebug(OSRF_LOG_MARK, "Checking to see if barcode %s is active", barcode);

	jsonObject* params = jsonParseStringFmt("{\"barcode\":\"%s\"}", barcode);
	jsonObject* card = oilsUtilsQuickReq(
		"open-ils.cstore", "open-ils.cstore.direct.actor.card.search", params );
	jsonObjectFree(params);

	char* active = oilsFMGetString(card, "active");
	jsonObjectFree(card);

	oilsEvent* return_event = NULL;
	if( ! oilsUtilsIsDBTrue(active) ) {
		osrfLogInfo(OSRF_LOG_MARK, "barcode %s is not active, returning event", barcode);
		return_event = oilsNewEvent(OSRF_LOG_MARK, "PATRON_CARD_INACTIVE");
	}

	free(active);
	return return_event;
}



int oilsAuthComplete( osrfMethodContext* ctx ) {
	OSRF_METHOD_VERIFY_CONTEXT(ctx); 

	const jsonObject* args	= jsonObjectGetIndex(ctx->params, 0);

	const char* uname		= jsonObjectGetString(jsonObjectGetKeyConst(args, "username"));
	const char* password	= jsonObjectGetString(jsonObjectGetKeyConst(args, "password"));
	const char* type		= jsonObjectGetString(jsonObjectGetKeyConst(args, "type"));
	double orgloc			= jsonObjectGetNumber(jsonObjectGetKeyConst(args, "org"));
	const char* workstation = jsonObjectGetString(jsonObjectGetKeyConst(args, "workstation"));
	char* barcode			= jsonObjectToSimpleString(jsonObjectGetKeyConst(args, "barcode"));

	const char* ws = (workstation) ? workstation : "";


	if(!type) type = OILS_AUTH_STAFF;

	if( !( (uname || barcode) && password) ) {
		free(barcode);
		return osrfAppRequestRespondException( ctx->session, ctx->request, 
			"username/barcode and password required for method: %s", ctx->method->name );
	}

	oilsEvent* response = NULL;
	jsonObject* userObj = NULL;

	if(uname) userObj = oilsUtilsFetchUserByUsername( uname ); 
	else if(barcode) userObj = oilsUtilsFetchUserByBarcode( barcode );
	
	if(!userObj) { 
		response = oilsNewEvent( OSRF_LOG_MARK, OILS_EVENT_AUTH_FAILED );
		osrfLogInfo(OSRF_LOG_MARK,  "failed login: username=%s, barcode=%s, workstation=%s", uname, barcode, ws );
		osrfAppRespondComplete( ctx, oilsEventToJSON(response) ); 
		oilsEventFree(response);
		free(barcode);
		return 0;
	}

	/* first let's see if they have the right credentials */
	int passOK = -1;
	if(uname) passOK = oilsAuthVerifyPassword( ctx, userObj, uname, password );
	else if (barcode) 
		passOK = oilsAuthVerifyPassword( ctx, userObj, barcode, password );

	if( passOK < 0 ) {
		jsonObjectFree(userObj);
		free(barcode);
		return passOK;
	}

	/* first see if their account is inactive */
	char* active = oilsFMGetString(userObj, "active");
	if( !oilsUtilsIsDBTrue(active) ) {
		response = oilsNewEvent(OSRF_LOG_MARK, "PATRON_INACTIVE");
		osrfAppRespondComplete( ctx, oilsEventToJSON(response) ); 
		oilsEventFree(response);
		jsonObjectFree(userObj);
		free(barcode);
		free(active);
		return 0;
	}
	free(active);

	/* then see if the barcode they used is active */
	if( barcode && ctx && userObj && (response = oilsAuthCheckCard( barcode )) ) {
		osrfAppRespondComplete( ctx, oilsEventToJSON(response) ); 
		oilsEventFree(response);
		jsonObjectFree(userObj);
		free(barcode);
		return 0;
	}


	/* check to see if the user is even allowed to login */
	if( oilsAuthCheckLoginPerm( ctx, userObj, type ) == -1 ) {
		jsonObjectFree(userObj);
		free(barcode);
		return 0;
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

	char* freeable_uname = NULL;
	if(!uname) {
		uname = freeable_uname = oilsFMGetString( userObj, "usrname" );
	}

	if( passOK ) {
		response = oilsAuthHandleLoginOK( userObj, uname, type, orgloc, workstation );

	} else {
		response = oilsNewEvent( OSRF_LOG_MARK, OILS_EVENT_AUTH_FAILED );
		osrfLogInfo(OSRF_LOG_MARK,  "failed login: username=%s, barcode=%s, workstation=%s", uname, barcode, ws );
	}

	jsonObjectFree(userObj);
	osrfAppRespondComplete( ctx, oilsEventToJSON(response) ); 
	oilsEventFree(response);
	free(barcode);

	if(freeable_uname) free(freeable_uname);

	return 0;
}



int oilsAuthSessionDelete( osrfMethodContext* ctx ) {
	OSRF_METHOD_VERIFY_CONTEXT(ctx); 

	const char* authToken = jsonObjectGetString( jsonObjectGetIndex(ctx->params, 0) );
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
static oilsEvent*  _oilsAuthResetTimeout( const char* authToken ) {
	if(!authToken) return NULL;

	oilsEvent* evt = NULL;
	double timeout;

	osrfLogDebug(OSRF_LOG_MARK, "Resetting auth timeout for session %s", authToken);
	char* key = va_list_to_string("%s%s", OILS_AUTH_CACHE_PRFX, authToken ); 
	jsonObject* cacheObj = osrfCacheGetObject( key ); 

	if(!cacheObj) {
		osrfLogInfo(OSRF_LOG_MARK, "No user in the cache exists with key %s", key);
		evt = oilsNewEvent(OSRF_LOG_MARK, OILS_EVENT_NO_SESSION);

	} else {

		timeout = jsonObjectGetNumber( jsonObjectGetKeyConst( cacheObj, "authtime"));
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
	const char* authToken = jsonObjectGetString( jsonObjectGetIndex(ctx->params, 0));
	oilsEvent* evt = _oilsAuthResetTimeout(authToken);
	osrfAppRespondComplete( ctx, oilsEventToJSON(evt) );
	oilsEventFree(evt);
	return 0;
}


int oilsAuthSessionRetrieve( osrfMethodContext* ctx ) {
	OSRF_METHOD_VERIFY_CONTEXT(ctx); 

	const char* authToken = jsonObjectGetString( jsonObjectGetIndex(ctx->params, 0));
	jsonObject* cacheObj = NULL;
	oilsEvent* evt = NULL;

	if( authToken ){

		evt = _oilsAuthResetTimeout(authToken);

		if( evt && strcmp(evt->event, OILS_EVENT_SUCCESS) ) {
			osrfAppRespondComplete( ctx, oilsEventToJSON(evt) );

		} else {

			osrfLogDebug(OSRF_LOG_MARK, "Retrieving auth session: %s", authToken);
			char* key = va_list_to_string("%s%s", OILS_AUTH_CACHE_PRFX, authToken ); 
			cacheObj = osrfCacheGetObject( key ); 
			if(cacheObj) {
				osrfAppRespondComplete( ctx, jsonObjectGetKeyConst( cacheObj, "userobj"));
				jsonObjectFree(cacheObj);
			} else {
				oilsEvent* evt2 = oilsNewEvent(OSRF_LOG_MARK, OILS_EVENT_NO_SESSION);
				osrfAppRespondComplete( ctx, oilsEventToJSON(evt2) ); /* should be event.. */
				oilsEventFree(evt2);
			}
			free(key);
		}

	} else {

		evt = oilsNewEvent(OSRF_LOG_MARK, OILS_EVENT_NO_SESSION);
		osrfAppRespondComplete( ctx, oilsEventToJSON(evt) );
	}

	if(evt)
		oilsEventFree(evt);

	return 0;
}



