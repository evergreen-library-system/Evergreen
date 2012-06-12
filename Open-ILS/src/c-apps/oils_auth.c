#include "opensrf/osrf_app_session.h"
#include "opensrf/osrf_application.h"
#include "opensrf/osrf_settings.h"
#include "opensrf/osrf_json.h"
#include "opensrf/log.h"
#include "openils/oils_utils.h"
#include "openils/oils_constants.h"
#include "openils/oils_event.h"

#define OILS_AUTH_CACHE_PRFX "oils_auth_"
#define OILS_AUTH_COUNT_SFFX "_count"

#define MODULENAME "open-ils.auth"

#define OILS_AUTH_OPAC "opac"
#define OILS_AUTH_STAFF "staff"
#define OILS_AUTH_TEMP "temp"
#define OILS_AUTH_PERSIST "persist"

// Default time for extending a persistent session: ten minutes
#define DEFAULT_RESET_INTERVAL 10 * 60

int osrfAppInitialize();
int osrfAppChildInit();

static long _oilsAuthOPACTimeout = 0;
static long _oilsAuthStaffTimeout = 0;
static long _oilsAuthOverrideTimeout = 0;
static long _oilsAuthPersistTimeout = 0;
static long _oilsAuthSeedTimeout = 0;
static long _oilsAuthBlockTimeout = 0;
static long _oilsAuthBlockCount = 0;


/**
	@brief Initialize the application by registering functions for method calls.
	@return Zero in all cases.
*/
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
		"active for login timeout purposes", 1, 0 );

	osrfAppRegisterMethod(
		MODULENAME,
		"open-ils.auth.authenticate.verify",
		"oilsAuthComplete",
		"Verifies the user provided a valid username and password."
		"Params and are the same as open-ils.auth.authenticate.complete."
		"Returns SUCCESS event on success, failure event on failure", 1, 0);


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

	if(!_oilsAuthSeedTimeout) { /* Load the default timeouts */

		jsonObject* value_obj;

		value_obj = osrf_settings_host_value_object(
			"/apps/open-ils.auth/app_settings/auth_limits/seed" );
		_oilsAuthSeedTimeout = oilsUtilsIntervalToSeconds( jsonObjectGetString( value_obj ));
		jsonObjectFree(value_obj);
		if( -1 == _oilsAuthSeedTimeout ) {
			osrfLogWarning( OSRF_LOG_MARK, "Invalid timeout for Auth Seeds - Using 30 seconds" );
			_oilsAuthSeedTimeout = 30;
		}

		value_obj = osrf_settings_host_value_object(
			"/apps/open-ils.auth/app_settings/auth_limits/block_time" );
		_oilsAuthBlockTimeout = oilsUtilsIntervalToSeconds( jsonObjectGetString( value_obj ));
		jsonObjectFree(value_obj);
		if( -1 == _oilsAuthBlockTimeout ) {
			osrfLogWarning( OSRF_LOG_MARK, "Invalid timeout for Blocking Timeout - Using 3x Seed" );
			_oilsAuthBlockTimeout = _oilsAuthSeedTimeout * 3;
		}

		value_obj = osrf_settings_host_value_object(
			"/apps/open-ils.auth/app_settings/auth_limits/block_count" );
		_oilsAuthBlockCount = oilsUtilsIntervalToSeconds( jsonObjectGetString( value_obj ));
		jsonObjectFree(value_obj);
		if( -1 == _oilsAuthBlockCount ) {
			osrfLogWarning( OSRF_LOG_MARK, "Invalid count for Blocking - Using 10" );
			_oilsAuthBlockCount = 10;
		}

		osrfLogInfo(OSRF_LOG_MARK, "Set auth limits: "
			"seed => %ld : block_timeout => %ld : block_count => %ld",
			_oilsAuthSeedTimeout, _oilsAuthBlockTimeout, _oilsAuthBlockCount );
	}

	return 0;
}

/**
	@brief Dummy placeholder for initializing a server drone.

	There is nothing to do, so do nothing.
*/
int osrfAppChildInit() {
	return 0;
}

/**
	@brief Implement the "init" method.
	@param ctx The method context.
	@return Zero if successful, or -1 if not.

	Method parameters:
	- username

	Return to client: Intermediate authentication seed.

	Combine the username with a timestamp and process ID, and take an md5 hash of the result.
	Store the hash in memcache, with a key based on the username.  Then return the hash to
	the client.

	However: if the username includes one or more embedded blank spaces, return a dummy
	hash without storing anything in memcache.  The dummy will never match a stored hash, so
	any attempt to authenticate with it will fail.
*/
int oilsAuthInit( osrfMethodContext* ctx ) {
	OSRF_METHOD_VERIFY_CONTEXT(ctx);

	char* username  = jsonObjectToSimpleString( jsonObjectGetIndex(ctx->params, 0) );
	if( username ) {

		jsonObject* resp;

		if( strchr( username, ' ' ) ) {

			// Embedded spaces are not allowed in a username.  Use "x" as a dummy
			// seed.  It will never be a valid seed because 'x' is not a hex digit.
			resp = jsonNewObject( "x" );

		} else {

			// Build a key and a seed; store them in memcache.
			char* key  = va_list_to_string( "%s%s", OILS_AUTH_CACHE_PRFX, username );
			char* countkey = va_list_to_string( "%s%s%s", OILS_AUTH_CACHE_PRFX, username, OILS_AUTH_COUNT_SFFX );
			char* seed = md5sum( "%d.%ld.%s", (int) time(NULL), (long) getpid(), username );
			jsonObject* countobject = osrfCacheGetObject( countkey );
			if(!countobject) {
				countobject = jsonNewNumberObject( (double) 0 );
			}
			osrfCachePutString( key, seed, _oilsAuthSeedTimeout );
			osrfCachePutObject( countkey, countobject, _oilsAuthBlockTimeout );

			osrfLogDebug( OSRF_LOG_MARK, "oilsAuthInit(): has seed %s and key %s", seed, key );

			// Build a returnable object containing the seed.
			resp = jsonNewObject( seed );

			free( seed );
			free( key );
			free( countkey );
			jsonObjectFree( countobject );
		}

		// Return the seed to the client.
		osrfAppRespondComplete( ctx, resp );

		jsonObjectFree(resp);
		free(username);
		return 0;
	}

	return -1;  // Error: no username parameter
}

/**
	Verifies that the user has permission to login with the
	given type.  If the permission fails, an oilsEvent is returned
	to the caller.
	@return -1 if the permission check failed, 0 if the permission
	is granted
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
	} else if(!strcasecmp(type, OILS_AUTH_PERSIST)) {
		char* permissions[] = { "PERSISTENT_LOGIN" };
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
	Returns 1 if the password provided matches the user's real password
	Returns 0 otherwise
	Returns -1 on error
*/
/**
	@brief Verify the password received from the client.
	@param ctx The method context.
	@param userObj An object from the database, representing the user.
	@param password An obfuscated password received from the client.
	@return 1 if the password is valid; 0 if it isn't; or -1 upon error.

	(None of the so-called "passwords" used here are in plaintext.  All have been passed
	through at least one layer of hashing to obfuscate them.)

	Take the password from the user object.  Append it to the username seed from memcache,
	as stored previously by a call to the init method.  Take an md5 hash of the result.
	Then compare this hash to the password received from the client.

	In order for the two to match, other than by dumb luck, the client had to construct
	the password it passed in the same way.  That means it neded to know not only the
	original password (either hashed or plaintext), but also the seed.  The latter requirement
	means that the client process needs either to be the same process that called the init
	method or to receive the seed from the process that did so.
*/
static int oilsAuthVerifyPassword( const osrfMethodContext* ctx,
		const jsonObject* userObj, const char* uname, const char* password ) {

	// Get the username seed, as stored previously in memcache by the init method
	char* seed = osrfCacheGetString( "%s%s", OILS_AUTH_CACHE_PRFX, uname );
	if(!seed) {
		return osrfAppRequestRespondException( ctx->session,
			ctx->request, "No authentication seed found. "
			"open-ils.auth.authenticate.init must be called first "
			" (check that memcached is running and can be connected to) "
		);
	}
    
	// We won't be needing the seed again, remove it
	osrfCacheRemove( "%s%s", OILS_AUTH_CACHE_PRFX, uname );

	// Get the hashed password from the user object
	char* realPassword = oilsFMGetString( userObj, "passwd" );

	osrfLogInternal(OSRF_LOG_MARK, "oilsAuth retrieved real password: [%s]", realPassword);
	osrfLogDebug(OSRF_LOG_MARK, "oilsAuth retrieved seed from cache: %s", seed );

	// Concatenate them and take an MD5 hash of the result
	char* maskedPw = md5sum( "%s%s", seed, realPassword );

	free(realPassword);
	free(seed);

	if( !maskedPw ) {
		// This happens only if md5sum() runs out of memory
		free( maskedPw );
		return -1;  // md5sum() ran out of memory
	}

	osrfLogDebug(OSRF_LOG_MARK,  "oilsAuth generated masked password %s. "
			"Testing against provided password %s", maskedPw, password );

	int ret = 0;
	if( !strcmp( maskedPw, password ) )
		ret = 1;

	free(maskedPw);

	char* countkey = va_list_to_string( "%s%s%s", OILS_AUTH_CACHE_PRFX, uname, OILS_AUTH_COUNT_SFFX );
	jsonObject* countobject = osrfCacheGetObject( countkey );
	if(countobject) {
		long failcount = (long) jsonObjectGetNumber( countobject );
		if(failcount >= _oilsAuthBlockCount) {
			ret = 0;
		    osrfLogInfo(OSRF_LOG_MARK, "oilsAuth found too many recent failures for '%s' : %i, forcing failure state.", uname, failcount);
		}
		if(ret == 0) {
			failcount += 1;
		}
		jsonObjectSetNumber( countobject, failcount );
		osrfCachePutObject( countkey, countobject, _oilsAuthBlockTimeout );
		jsonObjectFree(countobject);
	}
	free(countkey);

	return ret;
}

/**
	@brief Determine the login timeout.
	@param userObj Pointer to an object describing the user.
	@param type Pointer to one of four possible character strings identifying the login type.
	@param orgloc Org unit to use for settings lookups (negative or zero means unspecified)
	@return The length of the timeout, in seconds.

	The default timeout value comes from the configuration file, and depends on the
	login type.

	The default may be overridden by a corresponding org unit setting.  The @a orgloc
	parameter says what org unit to use for the lookup.  If @a orgloc <= 0, or if the
	lookup for @a orgloc yields no result, we look up the setting for the user's home org unit
	instead (except that if it's the same as @a orgloc we don't bother repeating the lookup).

	Whether defined in the config file or in an org unit setting, a timeout value may be
	expressed as a raw number (i.e. all digits, possibly with leading and/or trailing white
	space) or as an interval string to be translated into seconds by PostgreSQL.
*/
static long oilsAuthGetTimeout( const jsonObject* userObj, const char* type, int orgloc ) {

	if(!_oilsAuthOPACTimeout) { /* Load the default timeouts */

		jsonObject* value_obj;

		value_obj = osrf_settings_host_value_object(
			"/apps/open-ils.auth/app_settings/default_timeout/opac" );
		_oilsAuthOPACTimeout = oilsUtilsIntervalToSeconds( jsonObjectGetString( value_obj ));
		jsonObjectFree(value_obj);
		if( -1 == _oilsAuthOPACTimeout ) {
			osrfLogWarning( OSRF_LOG_MARK, "Invalid default timeout for OPAC logins" );
			_oilsAuthOPACTimeout = 0;
		}

		value_obj = osrf_settings_host_value_object(
			"/apps/open-ils.auth/app_settings/default_timeout/staff" );
		_oilsAuthStaffTimeout = oilsUtilsIntervalToSeconds( jsonObjectGetString( value_obj ));
		jsonObjectFree(value_obj);
		if( -1 == _oilsAuthStaffTimeout ) {
			osrfLogWarning( OSRF_LOG_MARK, "Invalid default timeout for staff logins" );
			_oilsAuthStaffTimeout = 0;
		}

		value_obj = osrf_settings_host_value_object(
			"/apps/open-ils.auth/app_settings/default_timeout/temp" );
		_oilsAuthOverrideTimeout = oilsUtilsIntervalToSeconds( jsonObjectGetString( value_obj ));
		jsonObjectFree(value_obj);
		if( -1 == _oilsAuthOverrideTimeout ) {
			osrfLogWarning( OSRF_LOG_MARK, "Invalid default timeout for temp logins" );
			_oilsAuthOverrideTimeout = 0;
		}

		value_obj = osrf_settings_host_value_object(
			"/apps/open-ils.auth/app_settings/default_timeout/persist" );
		_oilsAuthPersistTimeout = oilsUtilsIntervalToSeconds( jsonObjectGetString( value_obj ));
		jsonObjectFree(value_obj);
		if( -1 == _oilsAuthPersistTimeout ) {
			osrfLogWarning( OSRF_LOG_MARK, "Invalid default timeout for persist logins" );
			_oilsAuthPersistTimeout = 0;
		}

		osrfLogInfo(OSRF_LOG_MARK, "Set default auth timeouts: "
			"opac => %ld : staff => %ld : temp => %ld : persist => %ld",
			_oilsAuthOPACTimeout, _oilsAuthStaffTimeout,
			_oilsAuthOverrideTimeout, _oilsAuthPersistTimeout );
	}

	int home_ou = (int) jsonObjectGetNumber( oilsFMGetObject( userObj, "home_ou" ));
	if(orgloc < 1)
		orgloc = home_ou;

	char* setting = NULL;
	long default_timeout = 0;

	if( !strcmp( type, OILS_AUTH_OPAC )) {
		setting = OILS_ORG_SETTING_OPAC_TIMEOUT;
		default_timeout = _oilsAuthOPACTimeout;
	} else if( !strcmp( type, OILS_AUTH_STAFF )) {
		setting = OILS_ORG_SETTING_STAFF_TIMEOUT;
		default_timeout = _oilsAuthStaffTimeout;
	} else if( !strcmp( type, OILS_AUTH_TEMP )) {
		setting = OILS_ORG_SETTING_TEMP_TIMEOUT;
		default_timeout = _oilsAuthOverrideTimeout;
	} else if( !strcmp( type, OILS_AUTH_PERSIST )) {
		setting = OILS_ORG_SETTING_PERSIST_TIMEOUT;
		default_timeout = _oilsAuthPersistTimeout;
	}

	// Get the org unit setting, if there is one.
	char* timeout = oilsUtilsFetchOrgSetting( orgloc, setting );
	if(!timeout) {
		if( orgloc != home_ou ) {
			osrfLogDebug(OSRF_LOG_MARK, "Auth timeout not defined for org %d, "
				"trying home_ou %d", orgloc, home_ou );
			timeout = oilsUtilsFetchOrgSetting( home_ou, setting );
		}
	}

	if(!timeout)
		return default_timeout;   // No override from org unit setting

	// Translate the org unit setting to a number
	long t;
	if( !*timeout ) {
		osrfLogWarning( OSRF_LOG_MARK,
			"Timeout org unit setting is an empty string for %s login; using default",
			timeout, type );
		t = default_timeout;
	} else {
		// Treat timeout string as an interval, and convert it to seconds
		t = oilsUtilsIntervalToSeconds( timeout );
		if( -1 == t ) {
			// Unable to convert; possibly an invalid interval string
			osrfLogError( OSRF_LOG_MARK,
				"Unable to convert timeout interval \"%s\" for %s login; using default",
				timeout, type );
			t = default_timeout;
		}
	}

	free(timeout);
	return t;
}

/*
	Adds the authentication token to the user cache.  The timeout for the
	auth token is based on the type of login as well as (if type=='opac')
	the org location id.
	Returns the event that should be returned to the user.
	Event must be freed
*/
static oilsEvent* oilsAuthHandleLoginOK( jsonObject* userObj, const char* uname,
		const char* type, int orgloc, const char* workstation ) {

	oilsEvent* response;

	long timeout;
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
	osrfLogDebug(OSRF_LOG_MARK, "Auth session timeout for %s: %ld", uname, timeout );

	char* string = va_list_to_string(
			"%d.%ld.%s", (long) getpid(), time(NULL), uname );
	char* authToken = md5sum(string);
	char* authKey = va_list_to_string(
			"%s%s", OILS_AUTH_CACHE_PRFX, authToken );

	const char* ws = (workstation) ? workstation : "";
	osrfLogActivity(OSRF_LOG_MARK,
		"successful login: username=%s, authtoken=%s, workstation=%s", uname, authToken, ws );

	oilsFMSetString( userObj, "passwd", "" );
	jsonObject* cacheObj = jsonParseFmt( "{\"authtime\": %ld}", timeout );
	jsonObjectSetKey( cacheObj, "userobj", jsonObjectClone(userObj));

	if( !strcmp( type, OILS_AUTH_PERSIST )) {
		// Add entries for endtime and reset_interval, so that we can gracefully
		// extend the session a bit if the user is active toward the end of the 
		// timeout originally specified.
		time_t endtime = time( NULL ) + timeout;
		jsonObjectSetKey( cacheObj, "endtime", jsonNewNumberObject( (double) endtime ) );

		// Reset interval is hard-coded for now, but if we ever want to make it
		// configurable, this is the place to do it:
		jsonObjectSetKey( cacheObj, "reset_interval",
			jsonNewNumberObject( (double) DEFAULT_RESET_INTERVAL ));
	}

	osrfCachePutObject( authKey, cacheObj, (time_t) timeout );
	jsonObjectFree(cacheObj);
	osrfLogInternal(OSRF_LOG_MARK, "oilsAuthHandleLoginOK(): Placed user object into cache");
	jsonObject* payload = jsonParseFmt(
		"{ \"authtoken\": \"%s\", \"authtime\": %ld }", authToken, timeout );

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



/**
	@brief Implement the "complete" method.
	@param ctx The method context.
	@return -1 upon error; zero if successful, and if a STATUS message has been sent to the
	client to indicate completion; a positive integer if successful but no such STATUS
	message has been sent.

	Method parameters:
	- a hash with some combination of the following elements:
		- "username"
		- "barcode"
		- "password" (hashed with the cached seed; not plaintext)
		- "type"
		- "org"
		- "workstation"
		- "agent" (what software/interface/3rd-party is making the request)

	The password is required.  Either a username or a barcode must also be present.

	Return to client: Intermediate authentication seed.

	Validate the password, using the username if available, or the barcode if not.  The
	user must be active, and not barred from logging on.  The barcode, if used for
	authentication, must be active as well.  The workstation, if specified, must be valid.

	Upon deciding whether to allow the logon, return a corresponding event to the client.
*/
int oilsAuthComplete( osrfMethodContext* ctx ) {
	OSRF_METHOD_VERIFY_CONTEXT(ctx);

	const jsonObject* args  = jsonObjectGetIndex(ctx->params, 0);

	const char* uname       = jsonObjectGetString(jsonObjectGetKeyConst(args, "username"));
	const char* password    = jsonObjectGetString(jsonObjectGetKeyConst(args, "password"));
	const char* type        = jsonObjectGetString(jsonObjectGetKeyConst(args, "type"));
	int orgloc        = (int) jsonObjectGetNumber(jsonObjectGetKeyConst(args, "org"));
	const char* workstation = jsonObjectGetString(jsonObjectGetKeyConst(args, "workstation"));
	const char* barcode     = jsonObjectGetString(jsonObjectGetKeyConst(args, "barcode"));
	const char* ewho        = jsonObjectGetString(jsonObjectGetKeyConst(args, "agent"));

	const char* ws = (workstation) ? workstation : "";

	/* Use __FILE__, harmless_line_number for creating
	 * OILS_EVENT_AUTH_FAILED events (instead of OSRF_LOG_MARK) to avoid
	 * giving away information about why an authentication attempt failed.
	 */
	int harmless_line_number = __LINE__;

	if( !type )
		 type = OILS_AUTH_STAFF;

	if( !( (uname || barcode) && password) ) {
		return osrfAppRequestRespondException( ctx->session, ctx->request,
			"username/barcode and password required for method: %s", ctx->method->name );
	}

	oilsEvent* response = NULL;
	jsonObject* userObj = NULL;
	int card_active     = 1;      // boolean; assume active until proven otherwise

	// Fetch a row from the actor.usr table, by username if available,
	// or by barcode if not.
	if(uname) {
		userObj = oilsUtilsFetchUserByUsername( uname );
		if( userObj && JSON_NULL == userObj->type ) {
			jsonObjectFree( userObj );
			userObj = NULL;         // username not found
		}
	}
	else if(barcode) {
		// Read from actor.card by barcode

		osrfLogInfo( OSRF_LOG_MARK, "Fetching user by barcode %s", barcode );

		jsonObject* params = jsonParseFmt("{\"barcode\":\"%s\"}", barcode);
		jsonObject* card = oilsUtilsQuickReq(
			"open-ils.cstore", "open-ils.cstore.direct.actor.card.search", params );
		jsonObjectFree( params );

		if( card && card->type != JSON_NULL ) {
			// Determine whether the card is active
			char* card_active_str = oilsFMGetString( card, "active" );
			card_active = oilsUtilsIsDBTrue( card_active_str );
			free( card_active_str );

			// Look up the user who owns the card
			char* userid = oilsFMGetString( card, "usr" );
			jsonObjectFree( card );
			params = jsonParseFmt( "[%s]", userid );
			free( userid );
			userObj = oilsUtilsQuickReq(
					"open-ils.cstore", "open-ils.cstore.direct.actor.user.retrieve", params );
			jsonObjectFree( params );
			if( userObj && JSON_NULL == userObj->type ) {
				// user not found (shouldn't happen, due to foreign key)
				jsonObjectFree( userObj );
				userObj = NULL;
			}
		}
	}

	int     barred = 0, deleted = 0;
	char   *barred_str, *deleted_str;

	if(userObj) {
		barred_str = oilsFMGetString( userObj, "barred" );
		barred = oilsUtilsIsDBTrue( barred_str );
		free( barred_str );

		deleted_str = oilsFMGetString( userObj, "deleted" );
		deleted = oilsUtilsIsDBTrue( deleted_str );
		free( deleted_str );
	}

	if(!userObj || barred || deleted) {
		response = oilsNewEvent( __FILE__, harmless_line_number, OILS_EVENT_AUTH_FAILED );
		osrfLogInfo(OSRF_LOG_MARK,  "failed login: username=%s, barcode=%s, workstation=%s",
				uname, (barcode ? barcode : "(none)"), ws );
		osrfAppRespondComplete( ctx, oilsEventToJSON(response) );
		oilsEventFree(response);
		return 0;           // No such user
	}

	// Such a user exists and isn't barred or deleted.
	// Now see if he or she has the right credentials.
	int passOK = -1;
	if(uname)
		passOK = oilsAuthVerifyPassword( ctx, userObj, uname, password );
	else if (barcode)
		passOK = oilsAuthVerifyPassword( ctx, userObj, barcode, password );

	if( passOK < 0 ) {
		jsonObjectFree(userObj);
		return passOK;
	}

	// See if the account is active
	char* active = oilsFMGetString(userObj, "active");
	if( !oilsUtilsIsDBTrue(active) ) {
		if( passOK )
			response = oilsNewEvent( OSRF_LOG_MARK, "PATRON_INACTIVE" );
		else
			response = oilsNewEvent( __FILE__, harmless_line_number, OILS_EVENT_AUTH_FAILED );

		osrfAppRespondComplete( ctx, oilsEventToJSON(response) );
		oilsEventFree(response);
		jsonObjectFree(userObj);
		free(active);
		return 0;
	}
	free(active);

	osrfLogInfo( OSRF_LOG_MARK, "Fetching card by barcode %s", barcode );

	if( !card_active ) {
		osrfLogInfo( OSRF_LOG_MARK, "barcode %s is not active, returning event", barcode );
		response = oilsNewEvent( OSRF_LOG_MARK, "PATRON_CARD_INACTIVE" );
		osrfAppRespondComplete( ctx, oilsEventToJSON( response ) );
		oilsEventFree( response );
		jsonObjectFree( userObj );
		return 0;
	}


	// See if the user is even allowed to log in
	if( oilsAuthCheckLoginPerm( ctx, userObj, type ) == -1 ) {
		jsonObjectFree(userObj);
		return 0;
	}

	// If a workstation is defined, add the workstation info
	if( workstation != NULL ) {
		osrfLogDebug(OSRF_LOG_MARK, "Workstation is %s", workstation);
		response = oilsAuthVerifyWorkstation( ctx, userObj, workstation );
		if(response) {
			jsonObjectFree(userObj);
			osrfAppRespondComplete( ctx, oilsEventToJSON(response) );
			oilsEventFree(response);
			return 0;
		}

	} else {
		// Otherwise, use the home org as the workstation org on the user
		char* orgid = oilsFMGetString(userObj, "home_ou");
		oilsFMSetString(userObj, "ws_ou", orgid);
		free(orgid);
	}

	char* freeable_uname = NULL;
	if(!uname) {
		uname = freeable_uname = oilsFMGetString( userObj, "usrname" );
	}

	if( passOK ) { // login successful  
        
		char* ewhat = "login";

		if (0 == strcmp(ctx->method->name, "open-ils.auth.authenticate.verify")) {
			response = oilsNewEvent( OSRF_LOG_MARK, OILS_EVENT_SUCCESS );
			ewhat = "verify";

		} else {
			response = oilsAuthHandleLoginOK( userObj, uname, type, orgloc, workstation );
		}

		oilsUtilsTrackUserActivity(
			oilsFMGetObjectId(userObj), 
			ewho, ewhat, 
			osrfAppSessionGetIngress()
		);

	} else {
		response = oilsNewEvent( __FILE__, harmless_line_number, OILS_EVENT_AUTH_FAILED );
		osrfLogInfo(OSRF_LOG_MARK,  "failed login: username=%s, barcode=%s, workstation=%s",
				uname, (barcode ? barcode : "(none)"), ws );
	}

	jsonObjectFree(userObj);
	osrfAppRespondComplete( ctx, oilsEventToJSON(response) );
	oilsEventFree(response);

	if(freeable_uname)
		free(freeable_uname);

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

/**
 * Fetches the user object from the database and updates the user object in 
 * the cache object, which then has to be re-inserted into the cache.
 * User object is retrieved inside a transaction to avoid replication issues.
 */
static int _oilsAuthReloadUser(jsonObject* cacheObj) {
    int reqid, userId;
    osrfAppSession* session;
	osrfMessage* omsg;
    jsonObject *param, *userObj, *newUserObj;

    userObj = jsonObjectGetKey( cacheObj, "userobj" );
    userId = oilsFMGetObjectId( userObj );

    session = osrfAppSessionClientInit( "open-ils.cstore" );
    osrfAppSessionConnect(session);

    reqid = osrfAppSessionSendRequest(session, NULL, "open-ils.cstore.transaction.begin", 1);
	omsg = osrfAppSessionRequestRecv(session, reqid, 60);

    if(omsg) {

        osrfMessageFree(omsg);
        param = jsonNewNumberObject(userId);
        reqid = osrfAppSessionSendRequest(session, param, "open-ils.cstore.direct.actor.user.retrieve", 1);
	    omsg = osrfAppSessionRequestRecv(session, reqid, 60);
        jsonObjectFree(param);

        if(omsg) {
            newUserObj = jsonObjectClone( osrfMessageGetResult(omsg) );
            osrfMessageFree(omsg);
            reqid = osrfAppSessionSendRequest(session, NULL, "open-ils.cstore.transaction.rollback", 1);
	        omsg = osrfAppSessionRequestRecv(session, reqid, 60);
            osrfMessageFree(omsg);
        }
    }

    osrfAppSessionFree(session); // calls disconnect internally

    if(newUserObj) {

        // ws_ou and wsid are ephemeral and need to be manually propagated
        // oilsFMSetString dupe()'s internally, no need to clone the string
        oilsFMSetString(newUserObj, "wsid", oilsFMGetStringConst(userObj, "wsid"));
        oilsFMSetString(newUserObj, "ws_ou", oilsFMGetStringConst(userObj, "ws_ou"));

        jsonObjectRemoveKey(cacheObj, "userobj"); // this also frees the old user object
        jsonObjectSetKey(cacheObj, "userobj", newUserObj);
        return 1;
    } 

    osrfLogError(OSRF_LOG_MARK, "Error retrieving user %d from database", userId);
    return 0;
}

/**
	Resets the auth login timeout
	@return The event object, OILS_EVENT_SUCCESS, or OILS_EVENT_NO_SESSION
*/
static oilsEvent*  _oilsAuthResetTimeout( const char* authToken, int reloadUser ) {
	if(!authToken) return NULL;

	oilsEvent* evt = NULL;
	time_t timeout;

	osrfLogDebug(OSRF_LOG_MARK, "Resetting auth timeout for session %s", authToken);
	char* key = va_list_to_string("%s%s", OILS_AUTH_CACHE_PRFX, authToken );
	jsonObject* cacheObj = osrfCacheGetObject( key );

	if(!cacheObj) {
		osrfLogInfo(OSRF_LOG_MARK, "No user in the cache exists with key %s", key);
		evt = oilsNewEvent(OSRF_LOG_MARK, OILS_EVENT_NO_SESSION);

	} else {

        if(reloadUser) {
            _oilsAuthReloadUser(cacheObj);
        }

		// Determine a new timeout value
		jsonObject* endtime_obj = jsonObjectGetKey( cacheObj, "endtime" );
		if( endtime_obj ) {
			// Extend the current endtime by a fixed amount
			time_t endtime = (time_t) jsonObjectGetNumber( endtime_obj );
			int reset_interval = DEFAULT_RESET_INTERVAL;
			const jsonObject* reset_interval_obj = jsonObjectGetKeyConst(
				cacheObj, "reset_interval" );
			if( reset_interval_obj ) {
				reset_interval = (int) jsonObjectGetNumber( reset_interval_obj );
				if( reset_interval <= 0 )
					reset_interval = DEFAULT_RESET_INTERVAL;
			}

			time_t now = time( NULL );
			time_t new_endtime = now + reset_interval;
			if( new_endtime > endtime ) {
				// Keep the session alive a little longer
				jsonObjectSetNumber( endtime_obj, (double) new_endtime );
				timeout = reset_interval;
				osrfCachePutObject( key, cacheObj, timeout );
			} else {
				// The session isn't close to expiring, so don't reset anything.
				// Just report the time remaining.
				timeout = endtime - now;
			}
		} else {
			// Reapply the existing timeout from the current time
			timeout = (time_t) jsonObjectGetNumber( jsonObjectGetKeyConst( cacheObj, "authtime"));
			osrfCachePutObject( key, cacheObj, timeout );
		}

		jsonObject* payload = jsonNewNumberObject( (double) timeout );
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
    double reloadUser = jsonObjectGetNumber( jsonObjectGetIndex(ctx->params, 1));
	oilsEvent* evt = _oilsAuthResetTimeout(authToken, (int) reloadUser);
	osrfAppRespondComplete( ctx, oilsEventToJSON(evt) );
	oilsEventFree(evt);
	return 0;
}


int oilsAuthSessionRetrieve( osrfMethodContext* ctx ) {
	OSRF_METHOD_VERIFY_CONTEXT(ctx);
    bool returnFull = false;

	const char* authToken = jsonObjectGetString( jsonObjectGetIndex(ctx->params, 0));

    if(ctx->params->size > 1) {
        // caller wants full cached object, with authtime, etc.
        const char* rt = jsonObjectGetString(jsonObjectGetIndex(ctx->params, 1));
        if(rt && strcmp(rt, "0") != 0) 
            returnFull = true;
    }

	jsonObject* cacheObj = NULL;
	oilsEvent* evt = NULL;

	if( authToken ){

		// Reset the timeout to keep the session alive
		evt = _oilsAuthResetTimeout(authToken, 0);

		if( evt && strcmp(evt->event, OILS_EVENT_SUCCESS) ) {
			osrfAppRespondComplete( ctx, oilsEventToJSON( evt ));    // can't reset timeout

		} else {

			// Retrieve the cached session object
			osrfLogDebug(OSRF_LOG_MARK, "Retrieving auth session: %s", authToken);
			char* key = va_list_to_string("%s%s", OILS_AUTH_CACHE_PRFX, authToken );
			cacheObj = osrfCacheGetObject( key );
			if(cacheObj) {
				// Return a copy of the cached user object
                if(returnFull)
				    osrfAppRespondComplete( ctx, cacheObj);
                else
				    osrfAppRespondComplete( ctx, jsonObjectGetKeyConst( cacheObj, "userobj"));
				jsonObjectFree(cacheObj);
			} else {
				// Auth token is invalid or expired
				oilsEvent* evt2 = oilsNewEvent(OSRF_LOG_MARK, OILS_EVENT_NO_SESSION);
				osrfAppRespondComplete( ctx, oilsEventToJSON(evt2) ); /* should be event.. */
				oilsEventFree(evt2);
			}
			free(key);
		}

	} else {

		// No session
		evt = oilsNewEvent(OSRF_LOG_MARK, OILS_EVENT_NO_SESSION);
		osrfAppRespondComplete( ctx, oilsEventToJSON(evt) );
	}

	if(evt)
		oilsEventFree(evt);

	return 0;
}
