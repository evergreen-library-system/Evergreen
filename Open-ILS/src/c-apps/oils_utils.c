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


oilsEvent* oilsUtilsCheckPerms( int userid, int orgid, char* permissions[], int size ) {
	if (!permissions) return NULL;
	int i;
	oilsEvent* evt = NULL;

	// Find the root org unit, i.e. the one with no parent.
	// Assumption: there is only one org unit with no parent.
	if (orgid == -1) {
		jsonObject* where_clause = jsonParse( "{\"parent_ou\":null}" );
		jsonObject* org = oilsUtilsQuickReq(
			"open-ils.cstore",
			"open-ils.cstore.direct.actor.org_unit.search",
			where_clause
		);
		jsonObjectFree( where_clause );

		orgid = (int)jsonObjectGetNumber( oilsFMGetObject( org, "id" ) );

		jsonObjectFree(org);
	}

	for( i = 0; i < size && permissions[i]; i++ ) {

		char* perm = permissions[i];
		jsonObject* params = jsonParseFmt("[%d, \"%s\", %d]", userid, perm, orgid);
		jsonObject* o = oilsUtilsQuickReq( "open-ils.storage",
			"open-ils.storage.permission.user_has_perm", params );

		char* r = jsonObjectToSimpleString(o);

		if(r && !strcmp(r, "0"))
			evt = oilsNewEvent3( OSRF_LOG_MARK, OILS_EVENT_PERM_FAILURE, perm, orgid );

		jsonObjectFree(params);
		jsonObjectFree(o);
		free(r);

		if(evt)
			break;
	}

	return evt;
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
	@brief Given a username, fetch the corresponding row from the actor.usr table, if any.
	@param name The username for which to search.
	@return A Fieldmapper object for the relevant row in the actor.usr table, if it exists;
	or a JSON_NULL if it doesn't.

	The calling code is responsible for freeing the returned object by calling jsonObjectFree().
*/
jsonObject* oilsUtilsFetchUserByUsername( const char* name ) {
	if(!name) return NULL;
	jsonObject* params = jsonParseFmt("{\"usrname\":\"%s\"}", name);
	jsonObject* user = oilsUtilsQuickReq(
		"open-ils.cstore", "open-ils.cstore.direct.actor.user.search", params );

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
jsonObject* oilsUtilsFetchUserByBarcode(const char* barcode) {
	if(!barcode) return NULL;

	osrfLogInfo(OSRF_LOG_MARK, "Fetching user by barcode %s", barcode);

	jsonObject* params = jsonParseFmt("{\"barcode\":\"%s\"}", barcode);
	jsonObject* card = oilsUtilsQuickReq(
		"open-ils.cstore", "open-ils.cstore.direct.actor.card.search", params );
	jsonObjectFree(params);

	if(!card)
		return NULL;   // No such card

	// Get the user's id as a double
	char* usr = oilsFMGetString(card, "usr");
	jsonObjectFree(card);
	if(!usr)
		return NULL;   // No user id (shouldn't happen)
	double iusr = strtod(usr, NULL);
	free(usr);

	// Look up the user in actor.usr
	params = jsonParseFmt("[%f]", iusr);
	jsonObject* user = oilsUtilsQuickReq(
		"open-ils.cstore", "open-ils.cstore.direct.actor.user.retrieve", params);

	jsonObjectFree(params);
	return user;
}

char* oilsUtilsFetchOrgSetting( int orgid, const char* setting ) {
	if(!setting) return NULL;

	jsonObject* params = jsonParseFmt("[%d, \"%s\"]", orgid, setting );

	jsonObject* set = oilsUtilsQuickReq(
		"open-ils.actor",
		"open-ils.actor.ou_setting.ancestor_default", params);

	char* value = jsonObjectToSimpleString(jsonObjectGetKey(set, "value"));
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
			jsonObjectGetKey(jsonObjectGetKey(o,"payload"), "authtoken"));
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
