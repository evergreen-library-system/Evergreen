#include <ctype.h>
#include <limits.h>
#include "openils/oils_utils.h"
#include "openils/oils_idl.h"

osrfHash* oilsInitIDL(const char* idl_filename) {

	char* freeable_filename = NULL;
	const char* filename;

	if(idl_filename)
		filename = idl_filename;
	else {
		freeable_filename = osrf_settings_host_value("/IDL");
		filename = freeable_filename;
	}

	if (!filename) {
		osrfLogError(OSRF_LOG_MARK, "No settings config for '/IDL'");
		return NULL;
	}

	osrfLogInfo(OSRF_LOG_MARK, "Parsing IDL %s", filename);

	if (!oilsIDLInit( filename )) {
		osrfLogError(OSRF_LOG_MARK, "Problem loading IDL file [%s]!", filename);
		if(freeable_filename)
			free(freeable_filename);
		return NULL;
	}

	if(freeable_filename)
		free(freeable_filename);
	return oilsIDL();
}

/**
	@brief Return a const string with the value of a specified column in a row object.
	@param object Pointer to the row object.
	@param field Name of the column.
	@return Pointer to a const string representing the value of the specified column,
		or NULL in case of error.

	The row object must be a JSON_ARRAY with a classname.  The column value must be a
	JSON_STRING or a JSON_NUMBER.  Any other object type results in a return of NULL.

	The return value points into the internal contents of the row object, which
	retains ownership.
*/
const char* oilsFMGetStringConst( const jsonObject* object, const char* field ) {
	return jsonObjectGetString(oilsFMGetObject( object, field ));
}

/**
	@brief Return a string with the value of a specified column in a row object.
	@param object Pointer to the row object.
	@param field Name of the column.
	@return Pointer to a newly allocated string representing the value of the specified column,
		or NULL in case of error.

	The row object must be a JSON_ARRAY with a classname.  The column value must be a
	JSON_STRING or a JSON_NUMBER.  Any other object type results in a return of NULL.

	The calling code is responsible for freeing the returned string by calling free().
 */
char* oilsFMGetString( const jsonObject* object, const char* field ) {
	return jsonObjectToSimpleString(oilsFMGetObject( object, field ));
}

/**
	@brief Return a pointer to the value of a specified column in a row object.
	@param object Pointer to the row object.
	@param field Name of the column.
	@return Pointer to the jsonObject representing the value of the specified column, or NULL
		in case of error.

	The row object must be a JSON_ARRAY with a classname.

	The return value may point to a JSON_NULL, JSON_STRING, JSON_NUMBER, or JSON_ARRAY.  It
	points into the internal contents of the row object, which retains ownership.
*/
const jsonObject* oilsFMGetObject( const jsonObject* object, const char* field ) {
	if(!(object && field)) return NULL;
	if( object->type != JSON_ARRAY || !object->classname ) return NULL;
	int pos = fm_ntop(object->classname, field);
	if( pos > -1 )
		return jsonObjectGetIndex( object, pos );
	return NULL;
}


int oilsFMSetString( jsonObject* object, const char* field, const char* string ) {
	if(!(object && field && string)) return -1;
	osrfLogInternal(OSRF_LOG_MARK, "oilsFMSetString(): Collecing position for field %s", field);
	int pos = fm_ntop(object->classname, field);
	if( pos > -1 ) {
		osrfLogInternal(OSRF_LOG_MARK, "oilsFMSetString(): Setting string "
				"%s at field %s [position %d]", string, field, pos );
		jsonObjectSetIndex( object, pos, jsonNewObject(string) );
		return 0;
	}
	return -1;
}


int oilsUtilsIsDBTrue( const char* val ) {
	if( val && strcasecmp(val, "f") && strcmp(val, "0") ) return 1;
	return 0;
}


long oilsFMGetObjectId( const jsonObject* obj ) {
	long id = -1;
	if(!obj) return id;
	char* ids = oilsFMGetString( obj, "id" );
	if(ids) {
		id = atol(ids);
		free(ids);
	}
	return id;
}

int oilsUtilsTrackUserActivity(osrfMethodContext* ctx, long usr, const char* ewho, const char* ewhat, const char* ehow) {
    if (!usr && !(ewho || ewhat || ehow)) return 0;
    int rowcount = 0;

    jsonObject* params = jsonParseFmt(
        "{\"from\":[\"actor.insert_usr_activity\", %ld, \"%s\", \"%s\", \"%s\"]}",
        usr, 
        (NULL == ewho)  ? "" : ewho, 
        (NULL == ewhat) ? "" : ewhat, 
        (NULL == ehow)  ? "" : ehow
    );

	osrfAppSession* session = osrfAppSessionClientInit("open-ils.cstore");
    osrfAppSessionConnect(session);
    int reqid = osrfAppSessionSendRequest(session, NULL, "open-ils.cstore.transaction.begin", 1);
	osrfMessage* omsg = osrfAppSessionRequestRecv(session, reqid, 60);

    if(omsg) {
        osrfMessageFree(omsg);
        reqid = osrfAppSessionSendRequest(session, params, "open-ils.cstore.json_query", 1);
	    omsg = osrfAppSessionRequestRecv(session, reqid, 60);

        if(omsg) {
            const jsonObject* rows = osrfMessageGetResult(omsg);
            if (rows) rowcount = rows->size;
            osrfMessageFree(omsg); // frees rows
            if (rowcount) {
                reqid = osrfAppSessionSendRequest(session, NULL, "open-ils.cstore.transaction.commit", 1);
	            omsg = osrfAppSessionRequestRecv(session, reqid, 60);
                osrfMessageFree(omsg);
            } else {
                reqid = osrfAppSessionSendRequest(session, NULL, "open-ils.cstore.transaction.rollback", 1);
	            omsg = osrfAppSessionRequestRecv(session, reqid, 60);
                osrfMessageFree(omsg);
            }
        }
    }

    osrfAppSessionFree(session); // calls disconnect internally
    jsonObjectFree(params);
    return rowcount;
}


static int rootOrgId = 0; // cache the ID of the root org unit.
int oilsUtilsGetRootOrgId() {

    // return the cached value if we have it.
    if (rootOrgId > 0) return rootOrgId;

    jsonObject* where_clause = jsonParse("{\"parent_ou\":null}");
    jsonObject* org = oilsUtilsQuickReq(
        "open-ils.cstore",
        "open-ils.cstore.direct.actor.org_unit.search",
        where_clause
    );

    rootOrgId = (int) 
        jsonObjectGetNumber(oilsFMGetObject(org, "id"));

    jsonObjectFree(where_clause);
    jsonObjectFree(org);

    return rootOrgId;
}

oilsEvent* oilsUtilsCheckPerms( int userid, int orgid, char* permissions[], int size ) {
    if (!permissions) return NULL;
    int i;

    // Check perms against the root org unit if no org unit is provided.
    if (orgid == -1)
        orgid = oilsUtilsGetRootOrgId();

    for( i = 0; i < size && permissions[i]; i++ ) {
        oilsEvent* evt = NULL;
        char* perm = permissions[i];

        jsonObject* params = jsonParseFmt(
            "{\"from\":[\"permission.usr_has_perm\",\"%d\",\"%s\",\"%d\"]}",
            userid, perm, orgid
        );

        // Execute the query
        jsonObject* result = oilsUtilsCStoreReq(
            "open-ils.cstore.json_query", params);

        const jsonObject* hasPermStr = 
            jsonObjectGetKeyConst(result, "permission.usr_has_perm");

        if (!oilsUtilsIsDBTrue(jsonObjectGetString(hasPermStr))) {
            evt = oilsNewEvent3(
                OSRF_LOG_MARK, OILS_EVENT_PERM_FAILURE, perm, orgid);
        }

        jsonObjectFree(params);
        jsonObjectFree(result);

        // return first failed permission check.
        if (evt) return evt;
    }

    return NULL; // all perm checks succeeded
}

/**
	@brief Perform a remote procedure call.
	@param service The name of the service to invoke.
	@param method The name of the method to call.
	@param params The parameters to be passed to the method, if any.
	@return A copy of whatever the method returns as a result, or a JSON_NULL if the method
	doesn't return anything.

	If the @a params parameter points to a JSON_ARRAY, pass each element of the array
	as a separate parameter.  If it points to any other kind of jsonObject, pass it as a
	single parameter.  If it is NULL, pass no parameters.

	The calling code is responsible for freeing the returned object by calling jsonObjectFree().
*/
jsonObject* oilsUtilsQuickReq( const char* service, const char* method,
		const jsonObject* params ) {
	if(!(service && method)) return NULL;

	osrfLogDebug(OSRF_LOG_MARK, "oilsUtilsQuickReq(): %s - %s", service, method );

	// Open an application session with the service, and send the request
	osrfAppSession* session = osrfAppSessionClientInit( service );
	int reqid = osrfAppSessionSendRequest( session, params, method, 1 );

	// Get the response
	osrfMessage* omsg = osrfAppSessionRequestRecv( session, reqid, 60 );
	jsonObject* result = jsonObjectClone( osrfMessageGetResult(omsg) );

	// Clean up
	osrfMessageFree(omsg);
	osrfAppSessionFree(session);
	return result;
}

/**
	@brief Perform a remote procedure call, propagating session
        locale and timezone
	@param service The name of the service to invoke.
	@param method The name of the method to call.
	@param params The parameters to be passed to the method, if any.
	@return A copy of whatever the method returns as a result, or a JSON_NULL if the method
	doesn't return anything.

	If the @a params parameter points to a JSON_ARRAY, pass each element of the array
	as a separate parameter.  If it points to any other kind of jsonObject, pass it as a
	single parameter.  If it is NULL, pass no parameters.

	The calling code is responsible for freeing the returned object by calling jsonObjectFree().
*/
jsonObject* oilsUtilsQuickReqCtx( osrfMethodContext* ctx, const char* service,
                const char* method, const jsonObject* params ) {
	if(!(service && method && ctx)) return NULL;

	osrfLogDebug(OSRF_LOG_MARK, "oilsUtilsQuickReqCtx(): %s - %s (%s)", service, method, ctx->session->session_tz );

	// Open an application session with the service, and send the request
	osrfAppSession* session = osrfAppSessionClientInit( service );
	osrf_app_session_set_tz(session, ctx->session->session_tz);
	int reqid = osrfAppSessionSendRequest( session, params, method, 1 );

	// Get the response
	osrfMessage* omsg = osrfAppSessionRequestRecv( session, reqid, 60 );
	jsonObject* result = jsonObjectClone( osrfMessageGetResult(omsg) );

	// Clean up
	osrfMessageFree(omsg);
	osrfAppSessionFree(session);
	return result;
}

/**
	@brief Call a method of the open-ils.storage service.
	@param method Name of the method.
	@param params Parameters to be passed to the method, if any.
	@return A copy of whatever the method returns as a result, or a JSON_NULL if the method
	doesn't return anything.

	If the @a params parameter points to a JSON_ARRAY, pass each element of the array
	as a separate parameter.  If it points to any other kind of jsonObject, pass it as a
	single parameter.  If it is NULL, pass no parameters.

	The calling code is responsible for freeing the returned object by calling jsonObjectFree().
*/
jsonObject* oilsUtilsStorageReq( const char* method, const jsonObject* params ) {
	return oilsUtilsQuickReq( "open-ils.storage", method, params );
}

/**
	@brief Call a method of the open-ils.cstore service.
	@param method Name of the method.
	@param params Parameters to be passed to the method, if any.
	@return A copy of whatever the method returns as a result, or a JSON_NULL if the method
	doesn't return anything.

	If the @a params parameter points to a JSON_ARRAY, pass each element of the array
	as a separate parameter.  If it points to any other kind of jsonObject, pass it as a
	single parameter.  If it is NULL, pass no parameters.

	The calling code is responsible for freeing the returned object by calling jsonObjectFree().
*/
jsonObject* oilsUtilsCStoreReq( const char* method, const jsonObject* params ) {
	return oilsUtilsQuickReq("open-ils.cstore", method, params);
}

/**
	@brief Call a method of the open-ils.cstore service, context aware.
	@param ctx Method context object.
	@param method Name of the method.
	@param params Parameters to be passed to the method, if any.
	@return A copy of whatever the method returns as a result, or a JSON_NULL if the method
	doesn't return anything.

	If the @a params parameter points to a JSON_ARRAY, pass each element of the array
	as a separate parameter.  If it points to any other kind of jsonObject, pass it as a
	single parameter.  If it is NULL, pass no parameters.

	The calling code is responsible for freeing the returned object by calling jsonObjectFree().
*/
jsonObject* oilsUtilsCStoreReqCtx( osrfMethodContext* ctx, const char* method, const jsonObject* params ) {
	return oilsUtilsQuickReqCtx(ctx, "open-ils.cstore", method, params);
}



/**
	@brief Given a username, fetch the corresponding row from the actor.usr table, if any.
	@param name The username for which to search.
	@return A Fieldmapper object for the relevant row in the actor.usr table, if it exists;
	or a JSON_NULL if it doesn't.

	The calling code is responsible for freeing the returned object by calling jsonObjectFree().
*/
jsonObject* oilsUtilsFetchUserByUsername( osrfMethodContext* ctx, const char* name ) {
	if(!name) return NULL;
	jsonObject* params = jsonParseFmt("{\"usrname\":\"%s\"}", name);
	jsonObject* user = oilsUtilsQuickReqCtx(
		ctx, "open-ils.cstore", "open-ils.cstore.direct.actor.user.search", params );

	jsonObjectFree(params);
	long id = oilsFMGetObjectId(user);
	osrfLogDebug(OSRF_LOG_MARK, "Fetched user %s:%ld", name, id);
	return user;
}

/**
	@brief Given a barcode, fetch the corresponding row from the actor.usr table, if any.
	@param name The barcode for which to search.
	@return A Fieldmapper object for the relevant row in the actor.usr table, if it exists;
	or a JSON_NULL if it doesn't.

	Look up the barcode in actor.card.  Follow a foreign key from there to get a row in
	actor.usr.

	The calling code is responsible for freeing the returned object by calling jsonObjectFree().
*/
jsonObject* oilsUtilsFetchUserByBarcode(osrfMethodContext* ctx, const char* barcode) {
	if(!barcode) return NULL;

	osrfLogInfo(OSRF_LOG_MARK, "Fetching user by barcode %s", barcode);

	jsonObject* params = jsonParseFmt("{\"barcode\":\"%s\"}", barcode);
	jsonObject* card = oilsUtilsQuickReqCtx(
		ctx, "open-ils.cstore", "open-ils.cstore.direct.actor.card.search", params );
	jsonObjectFree(params);

	if(!card)
		return NULL;   // No such card

	// Get the user's id as a long
	char* usr = oilsFMGetString(card, "usr");
	jsonObjectFree(card);
	if(!usr)
		return NULL;   // No user id (shouldn't happen)
	long iusr = strtol(usr, NULL, 10);
	free(usr);

	// Look up the user in actor.usr
	params = jsonParseFmt("[%d]", iusr);
	jsonObject* user = oilsUtilsQuickReqCtx(
		ctx, "open-ils.cstore", "open-ils.cstore.direct.actor.user.retrieve", params);

	jsonObjectFree(params);
	return user;
}

char* oilsUtilsFetchOrgSetting( int orgid, const char* setting ) {
	if(!setting) return NULL;

	jsonObject* params = jsonParseFmt("[%d, \"%s\"]", orgid, setting );

	jsonObject* set = oilsUtilsQuickReq(
		"open-ils.actor",
		"open-ils.actor.ou_setting.ancestor_default", params);

	char* value = jsonObjectToSimpleString( jsonObjectGetKeyConst( set, "value" ));
	jsonObjectFree(params);
	jsonObjectFree(set);
	osrfLogDebug(OSRF_LOG_MARK, "Fetched org [%d] setting: %s => %s", orgid, setting, value);
	return value;
}



char* oilsUtilsLogin( const char* uname, const char* passwd, const char* type, int orgId ) {
	if(!(uname && passwd)) return NULL;

	osrfLogDebug(OSRF_LOG_MARK, "Logging in with username %s", uname );
	char* token = NULL;

	jsonObject* params = jsonParseFmt("[\"%s\"]", uname);

	jsonObject* o = oilsUtilsQuickReq(
		"open-ils.auth", "open-ils.auth.authenticate.init", params );

	const char* seed = jsonObjectGetString(o);
	char* passhash = md5sum(passwd);
	char buf[256];
	snprintf(buf, sizeof(buf), "%s%s", seed, passhash);
	char* fullhash = md5sum(buf);

	jsonObjectFree(o);
	jsonObjectFree(params);
	free(passhash);

	params = jsonParseFmt( "[\"%s\", \"%s\", \"%s\", \"%d\"]", uname, fullhash, type, orgId );
	o = oilsUtilsQuickReq( "open-ils.auth",
		"open-ils.auth.authenticate.complete", params );

	if(o) {
		const char* tok = jsonObjectGetString(
			jsonObjectGetKeyConst( jsonObjectGetKey( o,"payload" ), "authtoken" ));
		if( tok )
			token = strdup( tok );
	}

	free(fullhash);
	jsonObjectFree(params);
	jsonObjectFree(o);

	return token;
}


jsonObject* oilsUtilsFetchWorkstation( long id ) {
	jsonObject* p = jsonParseFmt("[%ld]", id);
	jsonObject* r = oilsUtilsQuickReq(
		"open-ils.storage",
		"open-ils.storage.direct.actor.workstation.retrieve", p );
	jsonObjectFree(p);
	return r;
}

jsonObject* oilsUtilsFetchWorkstationByName( const char* name ) {
	jsonObject* p = jsonParseFmt("{\"name\":\"%s\"}", name);
	jsonObject* r = oilsUtilsCStoreReq(
		"open-ils.cstore.direct.actor.workstation.search", p);
	jsonObjectFree(p);
	return r;
}

/**
	@brief Convert a string to a number representing a time interval in seconds.
	@param interval Pointer to string, e.g. "420" or "2 weeks".
	@return If successful, the number of seconds that the string represents; otherwise -1.

	If the string is all digits (apart from any leading or trailing white space), convert
	it directly.  Otherwise pass it to PostgreSQL for translation.

	The result is the same as if we were to pass every string to PostgreSQL, except that,
	depending on the value of LONG_MAX, we return values for some strings that represent
	intervals too long for PostgreSQL to represent (i.e. more than 2147483647 seconds).

	WARNING: a valid interval of -1 second will be indistinguishable from an error.  If
	such an interval is a plausible possibility, don't use this function.
*/
long oilsUtilsIntervalToSeconds( const char* s ) {

	if( !s ) {
		osrfLogWarning( OSRF_LOG_MARK, "String to be converted is NULL" );
		return -1;
	}

	// Skip leading white space
	while( isspace( (unsigned char) *s ))
		++s;

	if( '\0' == *s ) {
		osrfLogWarning( OSRF_LOG_MARK, "String to be converted is empty or all white space" );
		return -1;
	}

	// See if the string is a raw number, i.e. all digits
	// (apart from any leading or trailing white space)

	const char* p = s;   // For traversing and examining the remaining string
	if( isdigit( (unsigned char) *p )) {
		// Looks like a number so far...skip over the digits
		do {
			++p;
		} while( isdigit( (unsigned char) *p ));
		// Skip over any following white space
		while( isspace( (unsigned char) *p ))
			++p;
		if( '\0' == *p ) {
			// This string is a raw number.  Convert it directly.
			long n = strtol( s, NULL, 10 );
			if( LONG_MAX == n ) {
				// numeric overflow
				osrfLogWarning( OSRF_LOG_MARK,
					"String \"%s\"represents a number too big for a long", s );
				return -1;
			} else
				return n;
		}
	}

	// If we get to this point, the string is not all digits.  Pass it to PostgreSQL.

	// Build the query
	jsonObject* query_obj = jsonParseFmt(
		"{\"from\":[\"config.interval_to_seconds\",\"%s\"]}", s );

	// Execute the query
	jsonObject* result = oilsUtilsCStoreReq(
		"open-ils.cstore.json_query", query_obj );
	jsonObjectFree( query_obj );

	// Get the results
	const jsonObject* seconds_obj = jsonObjectGetKeyConst( result, "config.interval_to_seconds" );
	long seconds = -1;
	if( seconds_obj && JSON_NUMBER == seconds_obj->type )
		seconds = (long) jsonObjectGetNumber( seconds_obj );
	else
		osrfLogError( OSRF_LOG_MARK,
			"Error calling json_query to convert \"%s\" to seconds", s );

	jsonObjectFree( result );
	return seconds;
}
