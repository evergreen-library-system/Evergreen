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

#define MODULENAME "open-ils.auth_internal"

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
        "oilsAutInternalCreateSession",
        "Adds a user to the authentication cache to indicate "
        "the user is authenticated", 1, 0 
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

*/
int oilsAutInternalCreateSession(osrfMethodContext* ctx) {
    OSRF_METHOD_VERIFY_CONTEXT(ctx);

    const jsonObject* args  = jsonObjectGetIndex(ctx->params, 0);

    const char* user_id     = jsonObjectGetString(jsonObjectGetKeyConst(args, "user_id"));
    const char* org_unit    = jsonObjectGetString(jsonObjectGetKeyConst(args, "org_unit"));
    const char* login_type  = jsonObjectGetString(jsonObjectGetKeyConst(args, "login_type"));
    const char* workstation = jsonObjectGetString(jsonObjectGetKeyConst(args, "workstation"));

    if ( !(user_id && login_type && org_unit) ) {
        return osrfAppRequestRespondException( ctx->session, ctx->request,
            "Missing parameters for method: %s", ctx->method->name );
    }

	oilsEvent* response = NULL;

    // fetch the user object
    jsonObject* idParam = jsonNewNumberStringObject(user_id);
    jsonObject* userObj = oilsUtilsCStoreReq(
        "open-ils.cstore.direct.actor.user.retrieve", idParam);
    jsonObjectFree(idParam);

    if (!userObj) {
        return osrfAppRequestRespondException(ctx->session, 
            ctx->request, "No user found with ID %s", user_id);
    }

    // If a workstation is defined, add the workstation info
    if (workstation) {
        response = oilsAuthVerifyWorkstation(ctx, userObj, workstation);
        if (response) {
            jsonObjectFree(userObj);
            osrfAppRespondComplete(ctx, oilsEventToJSON(response));
            oilsEventFree(response);
            return 0;
        }

    } else {
        // Otherwise, use the home org as the workstation org on the user
        char* orgid = oilsFMGetString(userObj, "home_ou");
        oilsFMSetString(userObj, "ws_ou", orgid);
        free(orgid);
    }

    // determine the auth/cache timeout
    long timeout = oilsAuthGetTimeout(userObj, login_type, atoi(org_unit));

    char* string = va_list_to_string("%d.%ld.%ld", 
        (long) getpid(), time(NULL), oilsFMGetObjectId(userObj));
    char* authToken = md5sum(string);
    char* authKey = va_list_to_string(
        "%s%s", OILS_AUTH_CACHE_PRFX, authToken);

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
        "{\"authtoken\": \"%s\", \"authtime\": %ld}", authToken, timeout);

    response = oilsNewEvent2(OSRF_LOG_MARK, OILS_EVENT_SUCCESS, payload);
    free(string); free(authToken); free(authKey);
    jsonObjectFree(payload);

    jsonObjectFree(userObj);
    osrfAppRespondComplete(ctx, oilsEventToJSON(response));
    oilsEventFree(response);

    return 0;
}

