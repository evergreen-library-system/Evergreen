#define _XOPEN_SOURCE 500
#include <time.h>
#include <string.h>
#include <strings.h>
#include "opensrf/osrf_app_session.h"
#include "opensrf/osrf_application.h"
#include "opensrf/osrf_settings.h"
#include "opensrf/osrf_json.h"
#include "opensrf/log.h"
#include "openils/oils_utils.h"
#include "openils/oils_constants.h"
#include "openils/oils_event.h"

#define OILS_PROVISIONAL_AUTH_CACHE_PRFX "oils_provisional_auth_"
#define OILS_AUTH_CACHE_PRFX "oils_auth_"
#define OILS_AUTH_COUNT_SFFX "_count"

#define MODULENAME "open-ils.auth_internal"

#define OILS_AUTH_OPAC "opac"
#define OILS_AUTH_STAFF "staff"
#define OILS_AUTH_TEMP "temp"
#define OILS_AUTH_PERSIST "persist"
#define OILS_AUTH_API "api"

#define BLOCK_EXPIRED_STAFF_LOGIN_FLAG "auth.block_expired_staff_login"

// Default time for extending a persistent session: ten minutes
#define DEFAULT_RESET_INTERVAL 10 * 60

int safe_line = __LINE__;
#define OILS_LOG_MARK_SAFE __FILE__,safe_line

int osrfAppInitialize();
int osrfAppChildInit();

static long _oilsAuthOPACTimeout = 0;
static long _oilsAuthStaffTimeout = 0;
static long _oilsAuthOverrideTimeout = 0;
static long _oilsAuthPersistTimeout = 0;
static long _oilsAuthAPITimeout = 0;

/**
    @brief Initialize the application by registering functions for method calls.
    @return Zero on success, 1 on error.
*/
int osrfAppInitialize() {

    osrfLogInfo(OSRF_LOG_MARK, "Initializing Auth Internal Server...");

    /* load and parse the IDL */
    /* return non-zero to indicate error */
    if (!oilsInitIDL(NULL)) return 1; 

    osrfAppRegisterMethod(
        MODULENAME,
        "open-ils.auth_internal.session.create",
        "oilsAuthInternalCreateSession",
        "Adds a user to the authentication cache to indicate "
        "the user is authenticated", 1, 0 
    );

    osrfAppRegisterMethod(
        MODULENAME,
        "open-ils.auth_internal.session.upgrade_provisional",
        "oilsAuthInternalUpgradeProvisionalSession",
        "Upgrades a provisional session object to a full session.  "
        "Returns SUCCESS oilsEvent when the provisional session "
        "was found, otherwise returns OILS_EVENT_NO_SESSION.  "
        "PARAMS( authToken )", 1, 0
    );

    osrfAppRegisterMethod(
        MODULENAME,
        "open-ils.auth_internal.session.retrieve_provisional",
        "oilsAuthInternalProvisionalSessionRetrieve",
        "Pass in the provisional auth token and this retrieves the "
        "session object.  Unlike the similar public service method, "
        "the auth timeout is never reset and the full session"
        "object is always returned.  "
        "PARAMS( authToken )", 1, 0 );

    osrfAppRegisterMethod(
        MODULENAME,
        "open-ils.auth_internal.session.delete_provisional",
        "oilsAuthInternalProvisionalSessionDelete",
        "Destroys the given login session.  "
        "PARAMS( authToken )",  1, 0 );

    osrfAppRegisterMethod(
        MODULENAME,
        "open-ils.auth_internal.user.validate",
        "oilsAuthInternalValidate",
        "Determines whether a user should be allowed to login.  " 
        "Returns SUCCESS oilsEvent when the user is valid, otherwise "
        "returns a non-SUCCESS oilsEvent object", 1, 0
    );

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
    @brief Determine the login timeout.
    @param userObj Pointer to an object describing the user.
    @param type Pointer to one of four possible character strings identifying the login type.
    @param orgloc Org unit to use for settings lookups (negative or zero means unspecified)
    @return The length of the timeout, in seconds.

    The default timeout value comes from the configuration file, and
    depends on the login type.

    The default may be overridden by a corresponding org unit setting.
    The @a orgloc parameter says what org unit to use for the lookup.
    If @a orgloc <= 0, or if the lookup for @a orgloc yields no result,
    we look up the setting for the user's home org unit instead (except
    that if it's the same as @a orgloc we don't bother repeating the
    lookup).

    Whether defined in the config file or in an org unit setting, a
    timeout value may be expressed as a raw number (i.e. all digits,
    possibly with leading and/or trailing white space) or as an interval
    string to be translated into seconds by PostgreSQL.
*/
static long oilsAuthGetTimeout(
    const jsonObject* userObj, const char* type, int orgloc) {

    if(!_oilsAuthOPACTimeout) { /* Load the default timeouts */

        jsonObject* value_obj;

        value_obj = osrf_settings_host_value_object(
            "/apps/open-ils.auth_internal/app_settings/default_timeout/opac" );
        _oilsAuthOPACTimeout = oilsUtilsIntervalToSeconds( jsonObjectGetString( value_obj ));
        jsonObjectFree(value_obj);
        if( -1 == _oilsAuthOPACTimeout ) {
            osrfLogWarning( OSRF_LOG_MARK, "Invalid default timeout for OPAC logins" );
            _oilsAuthOPACTimeout = 0;
        }

        value_obj = osrf_settings_host_value_object(
            "/apps/open-ils.auth_internal/app_settings/default_timeout/api" );
        _oilsAuthAPITimeout = oilsUtilsIntervalToSeconds( jsonObjectGetString( value_obj ));
        jsonObjectFree(value_obj);
        if( -1 == _oilsAuthAPITimeout ) {
            osrfLogWarning( OSRF_LOG_MARK, "Invalid default timeout for API logins" );
            _oilsAuthAPITimeout = 0;
        }

        value_obj = osrf_settings_host_value_object(
            "/apps/open-ils.auth_internal/app_settings/default_timeout/staff" );
        _oilsAuthStaffTimeout = oilsUtilsIntervalToSeconds( jsonObjectGetString( value_obj ));
        jsonObjectFree(value_obj);
        if( -1 == _oilsAuthStaffTimeout ) {
            osrfLogWarning( OSRF_LOG_MARK, "Invalid default timeout for staff logins" );
            _oilsAuthStaffTimeout = 0;
        }

        value_obj = osrf_settings_host_value_object(
            "/apps/open-ils.auth_internal/app_settings/default_timeout/temp" );
        _oilsAuthOverrideTimeout = oilsUtilsIntervalToSeconds( jsonObjectGetString( value_obj ));
        jsonObjectFree(value_obj);
        if( -1 == _oilsAuthOverrideTimeout ) {
            osrfLogWarning( OSRF_LOG_MARK, "Invalid default timeout for temp logins" );
            _oilsAuthOverrideTimeout = 0;
        }

        value_obj = osrf_settings_host_value_object(
            "/apps/open-ils.auth_internal/app_settings/default_timeout/persist" );
        _oilsAuthPersistTimeout = oilsUtilsIntervalToSeconds( jsonObjectGetString( value_obj ));
        jsonObjectFree(value_obj);
        if( -1 == _oilsAuthPersistTimeout ) {
            osrfLogWarning( OSRF_LOG_MARK, "Invalid default timeout for persist logins" );
            _oilsAuthPersistTimeout = 0;
        }

        osrfLogInfo(OSRF_LOG_MARK, "Set default auth timeouts: "
            "opac => %ld : staff => %ld : temp => %ld : persist => %ld : api => %ld",
            _oilsAuthOPACTimeout, _oilsAuthStaffTimeout,
            _oilsAuthOverrideTimeout, _oilsAuthPersistTimeout, _oilsAuthAPITimeout );
    }

    int home_ou = (int) jsonObjectGetNumber( oilsFMGetObject( userObj, "home_ou" ));
    if(orgloc < 1)
        orgloc = home_ou;

    char* setting = NULL;
    long default_timeout = 0;

    if( !strcmp( type, OILS_AUTH_OPAC )) {
        setting = OILS_ORG_SETTING_OPAC_TIMEOUT;
        default_timeout = _oilsAuthOPACTimeout;
    } else if( !strcmp( type, OILS_AUTH_API )) {
        setting = OILS_ORG_SETTING_API_TIMEOUT;
        default_timeout = _oilsAuthAPITimeout;
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

/**
 * Verify workstation exists and stuff it into the user object to be cached
 */
static oilsEvent* oilsAuthVerifyWorkstation(
        const osrfMethodContext* ctx, jsonObject* userObj, const char* ws ) {

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
    Verifies that the user has permission to login with the given type.  
    Caller is responsible for freeing returned oilsEvent.
    @return oilsEvent* if the permission check failed, NULL otherwise.
*/
static oilsEvent* oilsAuthCheckLoginPerm(osrfMethodContext* ctx, 
    int user_id, int org_id, const char* type ) {

    // For backwards compatibility, check all login permissions 
    // using the root org unit as the context org unit.
    org_id = -1;

    char* perms[1];

    if (!strcasecmp(type, OILS_AUTH_OPAC)) {
        perms[0] = "OPAC_LOGIN";

    } else if (!strcasecmp(type, OILS_AUTH_API)) {
        perms[0] = "API_LOGIN";

    } else if (!strcasecmp(type, OILS_AUTH_STAFF)) {
        perms[0] = "STAFF_LOGIN";

    } else if (!strcasecmp(type, OILS_AUTH_TEMP)) {
        perms[0] = "STAFF_LOGIN";

    } else if (!strcasecmp(type, OILS_AUTH_PERSIST)) {
        perms[0] = "PERSISTENT_LOGIN";
    }

    return oilsUtilsCheckPerms(user_id, org_id, perms, 1);
}



/**
    @brief Implement the session create method
    @param ctx The method context.
    @return -1 upon error; zero if successful, and if a STATUS message has 
    been sent to the client to indicate completion; a positive integer if 
    successful but no such STATUS message has been sent.

    Method parameters:
    - a hash with some combination of the following elements:
        - "user_id"     -- actor.usr (au) ID for the user to cache.
        - "org_unit"    -- actor.org_unit (aou) ID representing the physical 
                           location / context used for timeout, etc. settings.
        - "login_type"  -- login type (opac, staff, temp, persist)
        - "workstation" -- workstation name
        - "provisional" -- request the creation of a provisional session
                           which can later be upgraded to a full session

*/
int oilsAuthInternalCreateSession(osrfMethodContext* ctx) {
    OSRF_METHOD_VERIFY_CONTEXT(ctx);

    const jsonObject* args  = jsonObjectGetIndex(ctx->params, 0);

    const char* user_id     = jsonObjectGetString(jsonObjectGetKeyConst(args, "user_id"));
    const char* login_type  = jsonObjectGetString(jsonObjectGetKeyConst(args, "login_type"));
    const char* workstation = jsonObjectGetString(jsonObjectGetKeyConst(args, "workstation"));
    int org_unit            = jsonObjectGetNumber(jsonObjectGetKeyConst(args, "org_unit"));
    int provisional         = jsonObjectGetNumber(jsonObjectGetKeyConst(args, "provisional")); // numeric bool, 0/1, 0 by default

    if ( !(user_id && login_type) ) {
        return osrfAppRequestRespondException( ctx->session, ctx->request,
            "Missing parameters for method: %s", ctx->method->name );
    }

    // XXX For now, ONLY staff logins can be provisional, which allows MFA
    if (strcmp(login_type, OILS_AUTH_STAFF)) {
        provisional = 0;
    }

    oilsEvent* response = NULL;

    // fetch the user object
    jsonObject* idParam = jsonNewNumberStringObject(user_id);
    jsonObject* userObj = oilsUtilsCStoreReqCtx(
        ctx, "open-ils.cstore.direct.actor.user.retrieve", idParam);
    jsonObjectFree(idParam);

    if (!userObj) {
        return osrfAppRequestRespondException(ctx->session, 
            ctx->request, "No user found with ID %s", user_id);
    }

    // If a workstation is defined, add the workstation info
    if (workstation) {
        response = oilsAuthVerifyWorkstation(ctx, userObj, workstation);

        if (response) { // invalid workstation.
            jsonObjectFree(userObj);
            osrfAppRespondComplete(ctx, oilsEventToJSON(response));
            oilsEventFree(response);
            return 0;

        } else { // workstation OK.  

            // The worksation org unit supersedes any org unit value 
            // provided via the API.  oilsAuthVerifyWorkstation() sets the 
            // ws_ou value to the WS owning lib.  A value is guaranteed.
            org_unit = atoi(oilsFMGetStringConst(userObj, "ws_ou"));
        }

    } else { // no workstation

        // For backwards compatibility, when no workstation is provided, use 
        // the users's home org as its workstation org unit, regardless of 
        // any API-level org unit value provided.
        const char* orgid = oilsFMGetStringConst(userObj, "home_ou");
        oilsFMSetString(userObj, "ws_ou", orgid);

        // The context org unit defaults to the user's home library when
        // no workstation is used and no API-level value is provided.
        if (org_unit < 1) org_unit = atoi(orgid);
    }

    // determine the auth/cache timeout
    long timeout = oilsAuthGetTimeout(userObj, login_type, org_unit);

    char* string = va_list_to_string("%ld.%d.%ld.%ld", 
        random(), (long) getpid(), time(NULL), oilsFMGetObjectId(userObj));

    char* authToken = md5sum(string);
    char* authKeyPrefix = (provisional != 0) ? OILS_PROVISIONAL_AUTH_CACHE_PRFX : OILS_AUTH_CACHE_PRFX;
    char* authKey = va_list_to_string(
        "%s%s", authKeyPrefix, authToken);

    oilsFMSetString(userObj, "passwd", "");
    jsonObject* cacheObj = jsonParseFmt("{\"authtime\": %ld}", timeout);
    jsonObjectSetKey(cacheObj, "userobj", jsonObjectClone(userObj));

    if( !strcmp(login_type, OILS_AUTH_PERSIST)) {
        // Add entries for endtime and reset_interval, so that we can gracefully
        // extend the session a bit if the user is active toward the end of the 
        // timeout originally specified.
        time_t endtime = time( NULL ) + timeout;
        jsonObjectSetKey(cacheObj, "endtime", 
            jsonNewNumberObject( (double) endtime ));

        // Reset interval is hard-coded for now, but if we ever want to make it
        // configurable, this is the place to do it:
        jsonObjectSetKey(cacheObj, "reset_interval",
            jsonNewNumberObject( (double) DEFAULT_RESET_INTERVAL));
    }

    osrfCachePutObject(authKey, cacheObj, (time_t) timeout);
    jsonObjectFree(cacheObj);
    jsonObject* payload = jsonParseFmt(
        "{\"authtoken\": \"%s\", \"authtime\": %ld, \"provisional\": %ld}", authToken, timeout, provisional);

    response = oilsNewEvent2(OSRF_LOG_MARK, OILS_EVENT_SUCCESS, payload);
    free(string); free(authToken); free(authKey);
    jsonObjectFree(payload);

    jsonObjectFree(userObj);
    osrfAppRespondComplete(ctx, oilsEventToJSON(response));
    oilsEventFree(response);

    return 0;
}

int oilsAuthInternalUpgradeProvisionalSession(osrfMethodContext* ctx) {
    OSRF_METHOD_VERIFY_CONTEXT(ctx);

    oilsEvent* response = NULL;
    const char* authToken = jsonObjectGetString( jsonObjectGetIndex(ctx->params, 0) );

    if (authToken) {
        char* authKey = va_list_to_string("%s%s", OILS_PROVISIONAL_AUTH_CACHE_PRFX, authToken);
        jsonObject* provisionalSessionObject = osrfCacheGetObject(authKey);

        if (provisionalSessionObject) { // Found the provisional session
            // ... remove it from the provisional cache
            osrfCacheRemove(authKey);
            free(authKey);

            // ... generate the "real" cache key and get the original timeout
            authKey = va_list_to_string("%s%s", OILS_AUTH_CACHE_PRFX, authToken);
            long timeout = jsonObjectGetNumber(jsonObjectGetKeyConst(provisionalSessionObject, "authtime"));

            // ... add it to the "real" cache with that original timeout
            osrfCachePutObject(authKey, provisionalSessionObject, (time_t) timeout);
            jsonObjectFree(provisionalSessionObject);

            // ... and prepare a success message
            response = oilsNewEvent(OSRF_LOG_MARK, OILS_EVENT_SUCCESS);

        } else {
            // Provisional session not found
            response = oilsNewEvent(OSRF_LOG_MARK, OILS_EVENT_NO_SESSION);
        }

        free(authKey);
        free(authToken);

    } else {
        // No provisional session auth token passed to us
        response = oilsNewEvent(OSRF_LOG_MARK, OILS_EVENT_NO_SESSION);
    }

    osrfAppRespondComplete(ctx, oilsEventToJSON(response));
    oilsEventFree(response);

    return 0;
}


int _checkIfExpiryDatePassed(const char *expire_date) {

    struct tm expire_tm;
    memset(&expire_tm, 0, sizeof(expire_tm));
    strptime(expire_date, "%FT%T%z", &expire_tm);
    time_t now = time(NULL);
    time_t expire_time_t = mktime(&expire_tm);
    if (now > expire_time_t) {
        return 1;
    } else {
        return 0;
    }
}

int _blockExpiredStaffLogin(osrfMethodContext* ctx, int user_id) {
    // check global flag whether we're supposed to block or not
    jsonObject *cgfObj = NULL, *params = NULL;
    params = jsonNewObject(BLOCK_EXPIRED_STAFF_LOGIN_FLAG);
    cgfObj = oilsUtilsCStoreReqCtx(
        ctx, "open-ils.cstore.direct.config.global_flag.retrieve", params);
    jsonObjectFree(params);

    int may_block_login = 0;
    char* tmp_str = NULL;
    if (cgfObj && cgfObj->type != JSON_NULL) {
        tmp_str = oilsFMGetString(cgfObj, "enabled");
        if (oilsUtilsIsDBTrue(tmp_str)) {
            may_block_login = 1;
        }
        free(tmp_str);
    }
    jsonObjectFree(cgfObj);

    if (!may_block_login) {
        return 0;
    }

    // OK, we're supposed to block logins by expired staff accounts,
    // so let's see if the account is one. We'll do so by seeing
    // if the account has the STAFF_LOGIN permission anywhere. We
    // are _not_ checking the login_type, as blocking 'staff' and
    // 'temp' logins still leaves open the possibility of constructing
    // an 'opac'-type login that _also_ sets a workstation, which
    // in turn could be used to set an authtoken cookie that works
    // in the staff interface. This means, that unlike ordinary patrons,
    // a staff account that expires will not be able to log into
    // the public catalog... but then, staff members really ought
    // to be using a separate account when acting as a library patron
    // anyway.

    int block_login = 0;

    // using the root org unit as the context org unit.
    int org_id = -1;
    char* perms[1];
    perms[0] = "STAFF_LOGIN";
    oilsEvent* response = oilsUtilsCheckPerms(user_id, org_id, perms, 1);

    if (!response) {
        // user has STAFF_LOGIN, so should be blocked
        block_login = 1;
    } else {
        oilsEventFree(response);
    }

    return block_login;
}

int oilsAuthInternalValidate(osrfMethodContext* ctx) {
    OSRF_METHOD_VERIFY_CONTEXT(ctx);

    const jsonObject* args  = jsonObjectGetIndex(ctx->params, 0);

    const char* user_id     = jsonObjectGetString(jsonObjectGetKeyConst(args, "user_id"));
    const char* barcode     = jsonObjectGetString(jsonObjectGetKeyConst(args, "barcode"));
    const char* login_type  = jsonObjectGetString(jsonObjectGetKeyConst(args, "login_type"));
    int org_unit            = jsonObjectGetNumber(jsonObjectGetKeyConst(args, "org_unit"));

    if ( !(user_id && login_type) ) {
        return osrfAppRequestRespondException( ctx->session, ctx->request,
            "Missing parameters for method: %s", ctx->method->name );
    }

    oilsEvent* response = NULL;
    jsonObject *userObj = NULL, *params = NULL;
    char* tmp_str = NULL;
    int user_exists = 0, user_active = 0, 
        user_barred = 0, user_deleted = 0,
        expired = 0;

    // Confirm user exists, active=true, barred=false, deleted=false
    params = jsonNewNumberStringObject(user_id);
    userObj = oilsUtilsCStoreReqCtx(
        ctx, "open-ils.cstore.direct.actor.user.retrieve", params);
    jsonObjectFree(params);

    if (userObj && userObj->type != JSON_NULL) {
        user_exists = 1;

        tmp_str = oilsFMGetString(userObj, "active");
        user_active = oilsUtilsIsDBTrue(tmp_str);
        free(tmp_str);

        tmp_str = oilsFMGetString(userObj, "barred");
        user_barred = oilsUtilsIsDBTrue(tmp_str);
        free(tmp_str);

        tmp_str = oilsFMGetString(userObj, "deleted");
        user_deleted = oilsUtilsIsDBTrue(tmp_str);
        free(tmp_str);

        tmp_str = oilsFMGetString(userObj, "expire_date");
        expired = _checkIfExpiryDatePassed(tmp_str);
        free(tmp_str);
    }

    if (!user_exists || user_barred || user_deleted) {
        response = oilsNewEvent(OILS_LOG_MARK_SAFE, OILS_EVENT_AUTH_FAILED);
    }

    if (!response && expired) {
        if (_blockExpiredStaffLogin(ctx, atoi(user_id))) {
            tmp_str = oilsFMGetString(userObj, "usrname");
            osrfLogWarning( OSRF_LOG_MARK, "Blocked login for expired staff user %s", tmp_str );
            free(tmp_str);
            response = oilsNewEvent(OILS_LOG_MARK_SAFE, OILS_EVENT_AUTH_FAILED);
        }
    }

    if (!response && !user_active) {
        // In some cases, it's useful for the caller to know if the
        // patron was unable to login becuase the account is inactive.
        // Return a specific event for this.
        response = oilsNewEvent(OILS_LOG_MARK_SAFE, "PATRON_INACTIVE");
    }

    if (!response && barcode) {
        // Caller provided a barcode.  Ensure it exists and is active.

        int card_ok = 0;
        params = jsonParseFmt("{\"barcode\":\"%s\"}", barcode);
        jsonObject* card = oilsUtilsCStoreReqCtx(
            ctx, "open-ils.cstore.direct.actor.card.search", params);
        jsonObjectFree(params);

        if (card && card->type != JSON_NULL) {
            tmp_str = oilsFMGetString(card, "active");
            card_ok = oilsUtilsIsDBTrue(tmp_str);
            free(tmp_str);
        }

        jsonObjectFree(card); // card=NULL OK here.

        if (!card_ok) {
            response = oilsNewEvent(
                OILS_LOG_MARK_SAFE, "PATRON_CARD_INACTIVE");
        }
    }

    // XXX: login permission checks are always global (see 
    // oilsAuthCheckLoginPerm()).  No need to extract the 
    // workstation org unit here.

    if (!response) { // Still OK
        // Confirm user has permission to login w/ the requested type.
        response = oilsAuthCheckLoginPerm(
            ctx, atoi(user_id), org_unit, login_type);
    }


    if (!response) {
        // No tests failed.  Return SUCCESS.
        response = oilsNewEvent(OSRF_LOG_MARK, OILS_EVENT_SUCCESS);
    }


    jsonObjectFree(userObj); // userObj=NULL OK here.
    osrfAppRespondComplete(ctx, oilsEventToJSON(response));
    oilsEventFree(response);

    return 0;
}

int oilsAuthInternalProvisionalSessionRetrieve( osrfMethodContext* ctx ) {
    OSRF_METHOD_VERIFY_CONTEXT(ctx);

    oilsEvent* evt = NULL;
    const char* authToken = jsonObjectGetString( jsonObjectGetIndex(ctx->params, 0));

    if (authToken) {
        // Retrieve the cached session object
        osrfLogDebug(OSRF_LOG_MARK, "Retrieving provisional auth session: %s", authToken);
        char* key = va_list_to_string("%s%s", OILS_PROVISIONAL_AUTH_CACHE_PRFX, authToken );
        jsonObject* cacheObj = osrfCacheGetObject( key );
        free(key);

        if(cacheObj) {
            // Return a copy of the cached user object
            osrfAppRespondComplete( ctx, cacheObj);
            jsonObjectFree(cacheObj);
        } else {
            // Provisional session is invalid or expired
            evt = oilsNewEvent(OSRF_LOG_MARK, OILS_EVENT_NO_SESSION);
            osrfAppRespondComplete( ctx, oilsEventToJSON(evt) );
            oilsEventFree(evt);
        }

    } else {

        // No provisional session auth token passed to us
        evt = oilsNewEvent(OSRF_LOG_MARK, OILS_EVENT_NO_SESSION);
        osrfAppRespondComplete( ctx, oilsEventToJSON(evt) );
        oilsEventFree(evt);
    }

    return 0;
}

int oilsAuthInternalProvisionalSessionDelete( osrfMethodContext* ctx ) {
    OSRF_METHOD_VERIFY_CONTEXT(ctx);

    const char* authToken = jsonObjectGetString( jsonObjectGetIndex(ctx->params, 0) );
    jsonObject* resp = NULL;

    if( authToken ) {
        osrfLogDebug(OSRF_LOG_MARK, "Removing provisional auth session: %s", authToken );
        char* key = va_list_to_string("%s%s", OILS_PROVISIONAL_AUTH_CACHE_PRFX, authToken ); /**/
        osrfCacheRemove(key);
        resp = jsonNewObject(authToken);
        free(key);
    }

    osrfAppRespondComplete( ctx, resp );
    jsonObjectFree(resp);
    return 0;
}

