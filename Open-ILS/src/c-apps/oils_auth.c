#include "opensrf/osrf_app_session.h"
#include "opensrf/osrf_application.h"
#include "opensrf/osrf_settings.h"
#include "opensrf/osrf_json.h"
#include "opensrf/log.h"
#include "openils/oils_utils.h"
#include "openils/oils_constants.h"
#include "openils/oils_event.h"

#define PCRE2_CODE_UNIT_WIDTH 8
#include <pcre2.h>

#define OILS_AUTH_CACHE_PRFX "oils_auth_"
#define OILS_AUTH_COUNT_SFFX "_count"

#define MODULENAME "open-ils.auth"

#define OILS_AUTH_OPAC "opac"
#define OILS_AUTH_STAFF "staff"
#define OILS_AUTH_API "api"
#define OILS_AUTH_TEMP "temp"
#define OILS_AUTH_PERSIST "persist"

#define OILS_PASSTYPE_MAIN "main"
#define OILS_PASSTYPE_API "api"

// Default time for extending a persistent session: ten minutes
#define DEFAULT_RESET_INTERVAL 10 * 60

int osrfAppInitialize();
int osrfAppChildInit();

static long _oilsAuthSeedTimeout = 0;
static long _oilsAuthBlockTimeout = 0;
static long _oilsAuthBlockCount = 0;


/* _mfaEnabledCache is used to cache the state of the answer to the question "is MFA enabled?"
 * It starts as a 2 in order to signal that the question hasn't been answered, and once answered
 * it is set to a truthy value of 0 for false, or 1 for true.
 */
static int _mfaEnabledCache = 2;


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
        "open-ils.auth.authenticate.init.barcode",
        "oilsAuthInitBarcode",
        "Start the authentication process using a patron barcode and return "
        "the intermediate authentication seed. PARAMS(barcode)", 1, 0);

    osrfAppRegisterMethod(
        MODULENAME,
        "open-ils.auth.authenticate.init.username",
        "oilsAuthInitUsername",
        "Start the authentication process using a patron username and return "
        "the intermediate authentication seed. PARAMS(username)", 1, 0);

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
		"open-ils.auth.login",
		"oilsAuthLogin",
        "Request an authentication token logging in with username or "
        "barcode.  Parameter is a keyword arguments hash with keys "
        "username, barcode, identifier, password, type, org, workstation, "
        "agent.  The 'identifier' option is used when the caller wants the "
        "API to determine if an identifier string is a username or barcode "
        "using the barcode format configuration.",
        1, 0);

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
		"Pass in the auth token and this retrieves the user object.  By "
		"default, the auth timeout is reset when this call is made.  If "
		"a second non-zero parameter is passed, the auth timeout info is "
		"returned to the caller along with the user object.  If a 3rd "
		"non-zero parameter is passed, the auth timeout will not be reset."
		"Returns the user object (password blanked) for the given login session "
		"PARAMS( authToken[, returnTime[, doNotResetSession]] )", 1, 0 );

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

// free() response
static char* oilsAuthGetSalt(int user_id, char* ptype) {
    char* salt_str = NULL;
    if (!ptype) ptype = OILS_PASSTYPE_MAIN;

    jsonObject* params = jsonParseFmt( // free
        "{\"from\":[\"actor.get_salt\",%d,\"%s\"]}", user_id, ptype);

    jsonObject* salt_obj = // free
        oilsUtilsCStoreReq("open-ils.cstore.json_query", params);

    jsonObjectFree(params);

    if (salt_obj) {

        if (salt_obj->type != JSON_NULL) {

            const char* salt_val = jsonObjectGetString(
                jsonObjectGetKeyConst(salt_obj, "actor.get_salt"));

            // caller expects a free-able string, could be NULL.
            if (salt_val) { salt_str = strdup(salt_val); } 
        }

        jsonObjectFree(salt_obj);
    }

    return salt_str;
}

// ident is either a username or barcode
// Returns the init seed -> requires free();
static char* oilsAuthBuildInitCache(
    int user_id, const char* ident, const char* ident_type, const char* nonce, char* ptype) {

    char* cache_key  = va_list_to_string(
        "%s%s%s", OILS_AUTH_CACHE_PRFX, ident, nonce);

    char* count_key = va_list_to_string(
        "%s%s%s", OILS_AUTH_CACHE_PRFX, ident, OILS_AUTH_COUNT_SFFX);

    char* auth_seed;
    if (user_id == -1) {
        // user does not exist.  Use a dummy seed
        auth_seed = strdup("x");
    } else {
        auth_seed = oilsAuthGetSalt(user_id, ptype);
    }

    jsonObject* seed_object = jsonParseFmt(
        "{\"%s\":\"%s\",\"user_id\":%d,\"seed\":\"%s\"}",
        ident_type, ident, user_id, auth_seed);

    jsonObject* count_object = osrfCacheGetObject(count_key);
    if(!count_object) {
        count_object = jsonNewNumberObject((double) 0);
    }

    osrfCachePutObject(cache_key, seed_object, _oilsAuthSeedTimeout);

    if (user_id != -1) {
        // Only track login counts for existing users, since a 
        // login for a nonexistent user will never succeed anyway.
        osrfCachePutObject(count_key, count_object, _oilsAuthBlockTimeout);
    }

    osrfLogDebug(OSRF_LOG_MARK, 
        "oilsAuthInit(): has seed %s and key %s", auth_seed, cache_key);

    free(cache_key);
    free(count_key);
    jsonObjectFree(count_object);
    jsonObjectFree(seed_object);

    return auth_seed;
}

static int oilsAuthInitUsernameHandler(
    osrfMethodContext* ctx, const char* username, const char* nonce, char* ptype) {

    osrfLogInfo(OSRF_LOG_MARK, 
        "User logging in with username %s", username);

    int user_id = -1;
    jsonObject* resp = NULL; // free
    jsonObject* user_obj = oilsUtilsFetchUserByUsername(ctx, username); // free

    if (user_obj && user_obj->type != JSON_NULL) 
        user_id = oilsFMGetObjectId(user_obj);

    jsonObjectFree(user_obj); // NULL OK

    char* seed = oilsAuthBuildInitCache(user_id, username, "username", nonce, ptype);
    resp = jsonNewObject(seed);
    free(seed);

    osrfAppRespondComplete(ctx, resp);
    jsonObjectFree(resp);
    return 0;
}

// open-ils.auth.authenticate.init.username
int oilsAuthInitUsername(osrfMethodContext* ctx) {
    OSRF_METHOD_VERIFY_CONTEXT(ctx);

    char* username =  // free
        jsonObjectToSimpleString(jsonObjectGetIndex(ctx->params, 0));
    const char* nonce = 
        jsonObjectGetString(jsonObjectGetIndex(ctx->params, 1));
    const char* login_type =
        jsonObjectGetString(jsonObjectGetIndex(ctx->params, 2));

    char* ptype = OILS_PASSTYPE_MAIN;
    if (login_type && !strcmp(login_type, OILS_AUTH_API)) ptype = OILS_PASSTYPE_API;

    if (!nonce) nonce = "";
    if (!username) return -1;

    int resp = oilsAuthInitUsernameHandler(ctx, username, nonce, ptype);

    free(username);
    return resp;
}

static int oilsAuthInitBarcodeHandler(
    osrfMethodContext* ctx, const char* barcode, const char* nonce, char* ptype) {

    osrfLogInfo(OSRF_LOG_MARK, 
        "User logging in with barcode %s", barcode);

    int user_id = -1;
    jsonObject* resp = NULL; // free
    jsonObject* user_obj = oilsUtilsFetchUserByBarcode(ctx, barcode); // free

    if (user_obj && user_obj->type != JSON_NULL) 
        user_id = oilsFMGetObjectId(user_obj);

    jsonObjectFree(user_obj); // NULL OK

    char* seed = oilsAuthBuildInitCache(user_id, barcode, "barcode", nonce, ptype);
    resp = jsonNewObject(seed);
    free(seed);

    osrfAppRespondComplete(ctx, resp);
    jsonObjectFree(resp);
    return 0;
}


// open-ils.auth.authenticate.init.barcode
int oilsAuthInitBarcode(osrfMethodContext* ctx) {
    OSRF_METHOD_VERIFY_CONTEXT(ctx);

    char* barcode = // free
        jsonObjectToSimpleString(jsonObjectGetIndex(ctx->params, 0));
    const char* nonce = 
        jsonObjectGetString(jsonObjectGetIndex(ctx->params, 1));
    const char* login_type =
        jsonObjectGetString(jsonObjectGetIndex(ctx->params, 2));

    char* ptype = OILS_PASSTYPE_MAIN;
    if (login_type && !strcmp(login_type, OILS_AUTH_API)) ptype = OILS_PASSTYPE_API;

    if (!nonce) nonce = "";
    if (!barcode) return -1;

    int resp = oilsAuthInitBarcodeHandler(ctx, barcode, nonce, ptype);

    free(barcode);
    return resp;
}

// returns true if the provided identifier matches the barcode regex.
static int oilsAuthIdentIsBarcode(const char* identifier, int org_id) {

    if (org_id < 1)
        org_id = oilsUtilsGetRootOrgId();

    PCRE2_SPTR bc_regex = (PCRE2_SPTR) oilsUtilsFetchOrgSetting(org_id, "opac.barcode_regex");

    if (!bc_regex) {
        // if no regex is set, assume any identifier starting
        // with a number is a barcode.
        bc_regex = (PCRE2_SPTR) strdup("^\\d"); // dupe for later free'ing
    }

    int err_number;
    PCRE2_SIZE err_offset;

    pcre2_code *compiled = pcre2_compile(bc_regex, PCRE2_ZERO_TERMINATED,
                                         0, &err_number, &err_offset, NULL);

    if (compiled == NULL) {
        PCRE2_UCHAR err_str[256];
        pcre2_get_error_message(err_number, err_str, sizeof(err_str));
        osrfLogError(OSRF_LOG_MARK, "Could not compile '%s': %s",
                     (char *) bc_regex, (char *) err_str);
        free((void *)bc_regex);
        pcre2_code_free(compiled);
        return 0;
    }

    pcre2_match_data *match_data = pcre2_match_data_create_from_pattern(compiled, NULL);

    int match_ret = pcre2_match(compiled, (PCRE2_SPTR) identifier,
                                (PCRE2_SIZE) sizeof(identifier), 0, 0,
                                match_data, NULL);

    free((void *)bc_regex);
    pcre2_code_free(compiled);
    pcre2_match_data_free(match_data);

    if (match_ret >= 0) return 1; // regex matched

    if (match_ret != PCRE2_ERROR_NOMATCH) {
        PCRE2_UCHAR err_str[256];
        pcre2_get_error_message(match_ret, err_str, sizeof(err_str));
        osrfLogError(OSRF_LOG_MARK, "Error processing barcode regex: %s",
                     (char *) err_str);
    }

    return 0; // regex did not match
}


/**
	@brief Implement the "init" method.
	@param ctx The method context.
	@return Zero if successful, or -1 if not.

	Method parameters:
	- username
	- nonce : optional login seed (string) provided by the caller which
		is added to the auth init cache to differentiate between logins
		using the same username and thus avoiding cache collisions for
		near-simultaneous logins.
    - login_type : optional, used to select password type

	Return to client: Intermediate authentication seed.
*/
int oilsAuthInit(osrfMethodContext* ctx) {
    OSRF_METHOD_VERIFY_CONTEXT(ctx);
    int resp = 0;

    char* identifier = // free
        jsonObjectToSimpleString(jsonObjectGetIndex(ctx->params, 0));
    const char* nonce = 
        jsonObjectGetString(jsonObjectGetIndex(ctx->params, 1));
    const char* login_type =
        jsonObjectGetString(jsonObjectGetIndex(ctx->params, 2));

    char* ptype = OILS_PASSTYPE_MAIN;
    if (login_type && !strcmp(login_type, OILS_AUTH_API)) ptype = OILS_PASSTYPE_API;

    if (!nonce) nonce = "";
    if (!identifier) return -1;  // we need an identifier

    if (oilsAuthIdentIsBarcode(identifier, 0)) {
        resp = oilsAuthInitBarcodeHandler(ctx, identifier, nonce, ptype);
    } else {
        resp = oilsAuthInitUsernameHandler(ctx, identifier, nonce, ptype);
    }

    free(identifier);
    return resp;
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
static int oilsAuthVerifyPassword( const osrfMethodContext* ctx, int user_id, 
        const char* identifier, const char* password, const char* nonce, const char* login_type) {

    int verified = 0;

    // We won't be needing the seed again, remove it
	char* key = va_list_to_string("%s%s%s", OILS_AUTH_CACHE_PRFX, identifier, nonce ); /**/
    osrfCacheRemove(key);
    free(key);

    // Ask the DB to verify the user's password.
    // Here, the password is md5(salt + md5(password))

    char* ptype = OILS_PASSTYPE_MAIN;
    if (login_type && !strcmp(login_type, OILS_AUTH_API)) ptype = OILS_PASSTYPE_API;

    jsonObject* params = jsonParseFmt( // free
        "{\"from\":[\"actor.verify_passwd\",%d,\"%s\",\"%s\"]}",
        user_id, ptype, password);

    jsonObject* verify_obj = // free 
        oilsUtilsCStoreReq("open-ils.cstore.json_query", params);

    jsonObjectFree(params);

    if (verify_obj) {
        verified = oilsUtilsIsDBTrue(
            jsonObjectGetString(
                jsonObjectGetKeyConst(
                    verify_obj, "actor.verify_passwd")));

        jsonObjectFree(verify_obj);
    }

    char* countkey = va_list_to_string("%s%s%s", 
        OILS_AUTH_CACHE_PRFX, identifier, OILS_AUTH_COUNT_SFFX );
    jsonObject* countobject = osrfCacheGetObject( countkey );
    if(countobject) {
        long failcount = (long) jsonObjectGetNumber( countobject );
        if(failcount >= _oilsAuthBlockCount) {
            verified = 0;
            osrfLogInfo(OSRF_LOG_MARK, 
                "oilsAuth found too many recent failures for '%s' : %i, "
                "forcing failure state.", identifier, failcount);
        }
        if(verified == 0) {
            failcount += 1;
        }
        jsonObjectSetNumber( countobject, failcount );
        osrfCachePutObject( countkey, countobject, _oilsAuthBlockTimeout );
        jsonObjectFree(countobject);
    }
    free(countkey);

    return verified;
}

/**
 * Returns true if the provided password is correct.
 * Turn the password into the nested md5 hash required of migrated
 * passwords, then check the password in the DB.
 */
static int oilsAuthLoginCheckPassword(int user_id, const char* password, char* ptype) {
    if (!ptype) ptype = OILS_PASSTYPE_MAIN;

    growing_buffer* gb = osrf_buffer_init(33); // free me 1
    char* salt = oilsAuthGetSalt(user_id, ptype); // free me 2
    char* passhash = md5sum(password); // free me 3

    osrf_buffer_add(gb, salt); // gb strdup's internally
    osrf_buffer_add(gb, passhash);

    free(salt); // free 2
    free(passhash); // free 3

    // salt + md5(password)
    passhash = osrf_buffer_release(gb); // free 1 ; free me 4
    char* finalpass = md5sum(passhash); // free me 5

    free(passhash); // free 4

    jsonObject *arr = jsonNewObjectType(JSON_ARRAY);
    jsonObjectPush(arr, jsonNewObject("actor.verify_passwd"));
    jsonObjectPush(arr, jsonNewNumberObject((long) user_id));
    jsonObjectPush(arr, jsonNewObject(ptype));
    jsonObjectPush(arr, jsonNewObject(finalpass));
    jsonObject *params = jsonNewObjectType(JSON_HASH); // free me 6
    jsonObjectSetKey(params, "from", arr);

    free(finalpass); // free 5

    jsonObject* verify_obj = // free 
        oilsUtilsCStoreReq("open-ils.cstore.json_query", params);

    jsonObjectFree(params); // free 6

    if (!verify_obj) return 0; // error

    int verified = oilsUtilsIsDBTrue(
        jsonObjectGetString(
            jsonObjectGetKeyConst(verify_obj, "actor.verify_passwd")
        )
    );

    jsonObjectFree(verify_obj);

    return verified;
}

static int oilsAuthLoginVerifyPassword(const osrfMethodContext* ctx, 
    int user_id, const char* username, const char* password, const char* login_type) {
    char* ptype = OILS_PASSTYPE_MAIN;
    if (login_type && !strcmp(login_type, OILS_AUTH_API)) ptype = OILS_PASSTYPE_API;

    // build the cache key
    growing_buffer* gb = osrf_buffer_init(64); // free me
    osrf_buffer_add(gb, OILS_AUTH_CACHE_PRFX);
    osrf_buffer_add(gb, username);
    osrf_buffer_add(gb, OILS_AUTH_COUNT_SFFX);
    char* countkey = osrf_buffer_release(gb); // free me

    jsonObject* countobject = osrfCacheGetObject(countkey); // free me

    long failcount = 0;
    if (countobject) {
        failcount = (long) jsonObjectGetNumber(countobject);

        if (failcount >= _oilsAuthBlockCount) {
            // User is blocked.  Don't waste any more CPU cycles on them.

            osrfLogInfo(OSRF_LOG_MARK, 
                "oilsAuth found too many recent failures for '%s' : %i, "
                "forcing failure state.", username, failcount);

            jsonObjectFree(countobject);
            free(countkey);   
            return 0;
        }
    }

    int verified = oilsAuthLoginCheckPassword(user_id, password, ptype);

    if (!verified) { // login failed.  increment failure counter.
        failcount++;

        if (countobject) {
            // append to existing counter
            jsonObjectSetNumber(countobject, failcount);

        } else { 
            // first failure, create a new counter
            countobject = jsonNewNumberObject((double) failcount);
        }

        osrfCachePutObject(countkey, countobject, _oilsAuthBlockTimeout);
    }

    jsonObjectFree(countobject); // NULL OK
    free(countkey);

    return verified;
}


/*
	Adds the authentication token to the user cache.  If MFA is enabled for
	this Evergreen instance the token will start out as "provisional" and not
	available for general use until the auth_internal app is told to upgrade
	the session.  If MFA is required for this login, session upgrade happens
	out of band after which the session is usable as normal.  If MFA is enabled
	but NOT required for this session, the session is automatically upgraded.
	The timeout for the auth token is based on the type of login as well as (if
	type=='opac') the org location id.

	Returns the event that should be returned to the user.

	Event must be freed
*/
static oilsEvent* oilsAuthHandleLoginOK( osrfMethodContext* ctx, jsonObject* userObj, const char* uname,
		const char* type, int orgloc, const char* workstation ) {

	oilsEvent* response = NULL;
    if (2 == _mfaEnabledCache) { // requires a service restart, so safe to cache here
        jsonObject* mfaEnabled = oilsUtilsQuickReqCtx(
            ctx,
            "open-ils.auth_mfa",
            "open-ils.auth_mfa.enabled", NULL);
        _mfaEnabledCache = atoi(jsonObjectGetString(mfaEnabled));
        osrfLogInfo(OSRF_LOG_MARK, 
            "Caching MFA-enabled status result: %d", _mfaEnabledCache);
        jsonObjectFree(mfaEnabled);
    }

    jsonObject* params = jsonNewObject(NULL);
    jsonObjectSetKey(params, "user_id", 
        jsonNewNumberObject(oilsFMGetObjectId(userObj)));
    jsonObjectSetKey(params,"org_unit", jsonNewNumberObject(orgloc));
    jsonObjectSetKey(params,"provisional", jsonNewNumberObject(_mfaEnabledCache));
    jsonObjectSetKey(params, "login_type", jsonNewObject(type));
    if (workstation) 
        jsonObjectSetKey(params, "workstation", jsonNewObject(workstation));

    jsonObject* authEvt = oilsUtilsQuickReqCtx(
        ctx,
        "open-ils.auth_internal",
        "open-ils.auth_internal.session.create", params);
    jsonObjectFree(params);

    if (authEvt) {

        const jsonObject* evtPayload = jsonObjectGetKeyConst(authEvt, "payload");
        int is_provisional = (int) jsonObjectGetNumber( jsonObjectGetKeyConst( evtPayload, "provisional" ));
        const char* token = jsonObjectGetString( jsonObjectGetKeyConst( evtPayload, "authtoken" ));

        if (is_provisional) {
            params = jsonNewObject(token);

            jsonObject* mfaRequiredObj = oilsUtilsQuickReqCtx(
                ctx,
                "open-ils.auth_mfa",
                "open-ils.auth_mfa.allowed_for_token.provisional", params);

            int mfaRequired = atoi(jsonObjectGetString(mfaRequiredObj));
            jsonObjectFree(mfaRequiredObj);

            if (!mfaRequired) {
                jsonObject* upgradeEvt = oilsUtilsQuickReqCtx(
                    ctx,
                    "open-ils.auth_internal",
                    "open-ils.auth_internal.session.upgrade_provisional", params);

                const char* upgradeEvtCode =
                    jsonObjectGetString(jsonObjectGetKey(upgradeEvt, "textcode"));

                if (strcmp(upgradeEvtCode, OILS_EVENT_SUCCESS)) { // did NOT get a success message
                    jsonObjectFree(params);
                    jsonObjectFree(authEvt);
                    jsonObjectFree(upgradeEvt);
                    osrfLogError(OSRF_LOG_MARK, 
                        "Error upgrading provisional session in open-ils.auth_internal: %s", token);
                    return response; // it's NULL here
                }

                jsonObjectFree(upgradeEvt);
                jsonObjectRemoveKey(evtPayload, "provisional"); // so the caller knows it's "real"
                osrfLogActivity(OSRF_LOG_MARK, "Upgraded provisional session: %s", token );
            }

            jsonObjectFree(params);
        }

        response = oilsNewEvent2(
            OSRF_LOG_MARK, 
            jsonObjectGetString(jsonObjectGetKey(authEvt, "textcode")),
            evtPayload   // cloned within Event
        );

        osrfLogActivity(OSRF_LOG_MARK,
            "successful login: username=%s, authtoken=%s, workstation=%s",
            uname,
            token,
            workstation ? workstation : ""
        );

        jsonObjectFree(authEvt);

    } else {
        osrfLogError(OSRF_LOG_MARK, 
            "Error caching auth session in open-ils.auth_internal");
    }

    return response;
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
		- "nonce" optional login seed to differentiate logins using the same username.

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
    const char* identifier  = jsonObjectGetString(jsonObjectGetKeyConst(args, "identifier"));
    const char* password    = jsonObjectGetString(jsonObjectGetKeyConst(args, "password"));
    const char* type        = jsonObjectGetString(jsonObjectGetKeyConst(args, "type"));
    int orgloc        = (int) jsonObjectGetNumber(jsonObjectGetKeyConst(args, "org"));
    const char* workstation = jsonObjectGetString(jsonObjectGetKeyConst(args, "workstation"));
    const char* barcode     = jsonObjectGetString(jsonObjectGetKeyConst(args, "barcode"));
    const char* ewho        = jsonObjectGetString(jsonObjectGetKeyConst(args, "agent"));
    const char* nonce       = jsonObjectGetString(jsonObjectGetKeyConst(args, "nonce"));

    const char* ws = (workstation) ? workstation : "";
    if (!nonce) nonce = "";

    // we no longer care how the identifier reaches us, 
    // as long as we have one.
    if (!identifier) {
        if (uname) {
            identifier = uname;
        } else if (barcode) {
            identifier = barcode;
        }
    }

    if (!identifier) {
        return osrfAppRequestRespondException(ctx->session, ctx->request,
            "username/barcode and password required for method: %s", 
            ctx->method->name);
    }

    osrfLogInfo(OSRF_LOG_MARK, 
        "Patron completing authentication with identifer %s", identifier);

    /* Use __FILE__, harmless_line_number for creating
     * OILS_EVENT_AUTH_FAILED events (instead of OSRF_LOG_MARK) to avoid
     * giving away information about why an authentication attempt failed.
     */
    int harmless_line_number = __LINE__;

    if( !type )
         type = OILS_AUTH_STAFF;

    oilsEvent* response = NULL; // free
    jsonObject* userObj = NULL; // free

    char* cache_key = va_list_to_string(
        "%s%s%s", OILS_AUTH_CACHE_PRFX, identifier, nonce);
    jsonObject* cacheObj = osrfCacheGetObject(cache_key); // free

    if (!cacheObj) {
        return osrfAppRequestRespondException(ctx->session,
            ctx->request, "No authentication seed found. "
            "open-ils.auth.authenticate.init must be called first "
            " (check that memcached is running and can be connected to) "
        );
    }

    int user_id = jsonObjectGetNumber(
        jsonObjectGetKeyConst(cacheObj, "user_id"));

    if (user_id == -1) {
        // User was not found during init.  Clean up and exit early.
        response = oilsNewEvent(
            __FILE__, harmless_line_number, OILS_EVENT_AUTH_FAILED);
        osrfAppRespondComplete(ctx, oilsEventToJSON(response));
        oilsEventFree(response); // frees event JSON
        osrfCacheRemove(cache_key);
        jsonObjectFree(cacheObj);
        return 0;
    }

    jsonObject* param = jsonNewNumberObject(user_id); // free
    userObj = oilsUtilsCStoreReqCtx(
        ctx, "open-ils.cstore.direct.actor.user.retrieve", param);
    jsonObjectFree(param);

    // determine if authenticate.init had found the user by barcode,
    // regardless of whether authenticate.complete is being passed
    // a username or identifier key.
    bool initFoundUserByBarcode = false;
    jsonObject* value = NULL;
    jsonIterator* cacheIter = jsonNewIterator(cacheObj);
    while (value = jsonIteratorNext(cacheIter)) {
        const char *key_name = cacheIter->key;
        if (!strcmp(key_name, "barcode")) {
            initFoundUserByBarcode = true;
            break;
        }
    }
    jsonIteratorFree(cacheIter);

    char* freeable_uname = NULL;
    if (!uname) {
        uname = freeable_uname = oilsFMGetString(userObj, "usrname");
    }

    // See if the user is allowed to login.

    jsonObject* params = jsonNewObject(NULL);
    jsonObjectSetKey(params, "user_id", 
        jsonNewNumberObject(oilsFMGetObjectId(userObj)));
    jsonObjectSetKey(params,"org_unit", jsonNewNumberObject(orgloc));
    jsonObjectSetKey(params, "login_type", jsonNewObject(type));
    if (initFoundUserByBarcode) {
         jsonObjectSetKey(params, "barcode", jsonNewObject(identifier));
    } else if (barcode) {
         jsonObjectSetKey(params, "barcode", jsonNewObject(barcode));
    }

    jsonObject* authEvt = oilsUtilsQuickReqCtx( // freed after password test
        ctx,
        "open-ils.auth_internal",
        "open-ils.auth_internal.user.validate", params);
    jsonObjectFree(params);

    if (!authEvt) {
        // Something went seriously wrong.  Get outta here before 
        // we start segfaulting.
        jsonObjectFree(userObj);
        if(freeable_uname) free(freeable_uname);
        return -1;
    }

    const char* authEvtCode = 
        jsonObjectGetString(jsonObjectGetKey(authEvt, "textcode"));

    if (!strcmp(authEvtCode, OILS_EVENT_AUTH_FAILED)) {
        // Received the generic login failure event.

        osrfLogInfo(OSRF_LOG_MARK,  
            "failed login: username=%s, barcode=%s, workstation=%s",
            uname, (barcode ? barcode : "(none)"), ws);

        response = oilsNewEvent(
            __FILE__, harmless_line_number, OILS_EVENT_AUTH_FAILED);
    }

    int passOK = 0;
    
    if (!response) {
        // User exists and is not barred, etc.  Test the password.

        passOK = oilsAuthVerifyPassword(
            ctx, user_id, identifier, password, nonce, type);

        if (!passOK) {
            // Password check failed. Return generic login failure.

            response = oilsNewEvent(
                __FILE__, harmless_line_number, OILS_EVENT_AUTH_FAILED);

            osrfLogInfo(OSRF_LOG_MARK,  
                "failed login: username=%s, barcode=%s, workstation=%s",
                    uname, (barcode ? barcode : "(none)"), ws );
        }
    }


    // Below here, we know the password check succeeded if no response
    // object is present.

    if (!response && (
        !strcmp(authEvtCode, "PATRON_INACTIVE") ||
        !strcmp(authEvtCode, "PATRON_CARD_INACTIVE"))) {
        // Patron and/or card is inactive but the correct password 
        // was provided.  Alert the caller to the inactive-ness.
        response = oilsNewEvent2(
            OSRF_LOG_MARK, authEvtCode,
            jsonObjectGetKey(authEvt, "payload")   // cloned within Event
        );
    }

    if (!response && strcmp(authEvtCode, OILS_EVENT_SUCCESS)) {
        // Validate API returned an unexpected non-success event.
        // To be safe, treat this as a generic login failure.

        response = oilsNewEvent(
            __FILE__, harmless_line_number, OILS_EVENT_AUTH_FAILED);
    }

    if (!response) {
        // password OK and no other events have prevented login completion.

        char* ewhat = "login";

        if (0 == strcmp(ctx->method->name, "open-ils.auth.authenticate.verify")) {
            response = oilsNewEvent( OSRF_LOG_MARK, OILS_EVENT_SUCCESS );
            ewhat = "verify";

        } else {
            response = oilsAuthHandleLoginOK(
                ctx, userObj, uname, type, orgloc, workstation);
        }

        oilsUtilsTrackUserActivity(
            ctx,
            oilsFMGetObjectId(userObj), 
            ewho, ewhat, 
            osrfAppSessionGetIngress()
        );
    }

    // reply
    osrfAppRespondComplete(ctx, oilsEventToJSON(response));

    // clean up
    oilsEventFree(response);
    jsonObjectFree(userObj);
    jsonObjectFree(authEvt);
    jsonObjectFree(cacheObj);
    if(freeable_uname)
        free(freeable_uname);

    return 0;
}


int oilsAuthLogin(osrfMethodContext* ctx) {
    OSRF_METHOD_VERIFY_CONTEXT(ctx);

    const jsonObject* args  = jsonObjectGetIndex(ctx->params, 0);

    const char* username    = jsonObjectGetString(jsonObjectGetKeyConst(args, "username"));
    const char* identifier  = jsonObjectGetString(jsonObjectGetKeyConst(args, "identifier"));
    const char* password    = jsonObjectGetString(jsonObjectGetKeyConst(args, "password"));
    const char* type        = jsonObjectGetString(jsonObjectGetKeyConst(args, "type"));
    int orgloc        = (int) jsonObjectGetNumber(jsonObjectGetKeyConst(args, "org"));
    const char* workstation = jsonObjectGetString(jsonObjectGetKeyConst(args, "workstation"));
    const char* barcode     = jsonObjectGetString(jsonObjectGetKeyConst(args, "barcode"));
    const char* ewho        = jsonObjectGetString(jsonObjectGetKeyConst(args, "agent"));

    const char* ws = (workstation) ? workstation : "";
    if (!type) type = OILS_AUTH_STAFF;

    jsonObject* userObj = NULL; // free me
    oilsEvent* response = NULL; // free me

    /* Use __FILE__, harmless_line_number for creating
     * OILS_EVENT_AUTH_FAILED events (instead of OSRF_LOG_MARK) to avoid
     * giving away information about why an authentication attempt failed.
     */
    int harmless_line_number = __LINE__;

    // translate a generic identifier into a username or barcode if necessary.
    if (identifier && !username && !barcode) {
        if (oilsAuthIdentIsBarcode(identifier, orgloc)) {
            barcode = identifier;
        } else {
            username = identifier;
        }
    }

    if (username) {
        barcode = NULL; // avoid superfluous identifiers
        userObj = oilsUtilsFetchUserByUsername(ctx, username);

    } else if (barcode) {
        userObj = oilsUtilsFetchUserByBarcode(ctx, barcode);

    } else {
        // not enough params
        return osrfAppRequestRespondException(ctx->session, ctx->request,
            "username/barcode and password required for method: %s", 
            ctx->method->name);
    }

    if (!userObj) { // user not found.  
        response = oilsNewEvent(
            __FILE__, harmless_line_number, OILS_EVENT_AUTH_FAILED);
        osrfAppRespondComplete(ctx, oilsEventToJSON(response));
        oilsEventFree(response); // frees event JSON
        return 0;
    }

    long user_id = oilsFMGetObjectId(userObj);

    // username is freed when userObj is freed.
    // From here we can use the username as the generic identifier
    // since it's guaranteed to have a value.
    if (!username) username = oilsFMGetStringConst(userObj, "usrname");

    // See if the user is allowed to login.
    jsonObject* params = jsonNewObject(NULL);
    jsonObjectSetKey(params, "user_id", jsonNewNumberObject(user_id));
    jsonObjectSetKey(params,"org_unit", jsonNewNumberObject(orgloc));
    jsonObjectSetKey(params, "login_type", jsonNewObject(type));
    if (barcode) jsonObjectSetKey(params, "barcode", jsonNewObject(barcode));

    jsonObject* authEvt = oilsUtilsQuickReqCtx( // freed after password test
        ctx,
        "open-ils.auth_internal",
        "open-ils.auth_internal.user.validate", params);
    jsonObjectFree(params);

    if (!authEvt) { // unknown error
        jsonObjectFree(userObj);
        return -1;
    }

    const char* authEvtCode = 
        jsonObjectGetString(jsonObjectGetKey(authEvt, "textcode"));

    if (!strcmp(authEvtCode, OILS_EVENT_AUTH_FAILED)) {
        // Received the generic login failure event.

        osrfLogInfo(OSRF_LOG_MARK,  
            "failed login: username=%s, barcode=%s, workstation=%s",
            username, (barcode ? barcode : "(none)"), ws);

        response = oilsNewEvent(
            __FILE__, harmless_line_number, OILS_EVENT_AUTH_FAILED);
    }

    if (!response && // user exists and is not barred, etc.
        !oilsAuthLoginVerifyPassword(ctx, user_id, username, password, type)) {
        // User provided the wrong password or is blocked from too 
        // many previous login failures.

        response = oilsNewEvent(
            __FILE__, harmless_line_number, OILS_EVENT_AUTH_FAILED);

        osrfLogInfo(OSRF_LOG_MARK,  
            "failed login: username=%s, barcode=%s, workstation=%s",
                username, (barcode ? barcode : "(none)"), ws );
    }

    // Below here, we know the password check succeeded if no response
    // object is present.

    if (!response && (
        !strcmp(authEvtCode, "PATRON_INACTIVE") ||
        !strcmp(authEvtCode, "PATRON_CARD_INACTIVE"))) {
        // Patron and/or card is inactive but the correct password 
        // was provided.  Alert the caller to the inactive-ness.
        response = oilsNewEvent2(
            OSRF_LOG_MARK, authEvtCode,
            jsonObjectGetKey(authEvt, "payload")   // cloned within Event
        );
    }

    if (!response && strcmp(authEvtCode, OILS_EVENT_SUCCESS)) {
        // Validate API returned an unexpected non-success event.
        // To be safe, treat this as a generic login failure.

        response = oilsNewEvent(
            __FILE__, harmless_line_number, OILS_EVENT_AUTH_FAILED);
    }

    if (!response) {
        // password OK and no other events have prevented login completion.

        char* ewhat = "login";

        if (0 == strcmp(ctx->method->name, "open-ils.auth.authenticate.verify")) {
            response = oilsNewEvent( OSRF_LOG_MARK, OILS_EVENT_SUCCESS );
            ewhat = "verify";

        } else {
            response = oilsAuthHandleLoginOK(
                ctx, userObj, username, type, orgloc, workstation);
        }

        oilsUtilsTrackUserActivity(
            ctx,
            oilsFMGetObjectId(userObj), 
            ewho, ewhat, 
            osrfAppSessionGetIngress()
        );
    }

    // reply
    osrfAppRespondComplete(ctx, oilsEventToJSON(response));

    // clean up
    oilsEventFree(response);
    jsonObjectFree(userObj);
    jsonObjectFree(authEvt);

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
    jsonObject *param, *userObj, *newUserObj = NULL;

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
    bool noTimeoutReset = false;

	const char* authToken = jsonObjectGetString( jsonObjectGetIndex(ctx->params, 0));

    if(ctx->params->size > 1) {
        // caller wants full cached object, with authtime, etc.
        const char* rt = jsonObjectGetString(jsonObjectGetIndex(ctx->params, 1));
        if(rt && strcmp(rt, "0") != 0) 
            returnFull = true;

        if (ctx->params->size > 2) {
            // Avoid resetting the auth session timeout.
            const char* noReset = 
                jsonObjectGetString(jsonObjectGetIndex(ctx->params, 2));
            if (noReset && strcmp(noReset, "0") != 0) 
                noTimeoutReset = true;
        }
    }

	jsonObject* cacheObj = NULL;
	oilsEvent* evt = NULL;

	if( authToken ){

		// Reset the timeout to keep the session alive
        if (!noTimeoutReset) 
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
