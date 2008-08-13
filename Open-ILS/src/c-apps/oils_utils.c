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
		if(freeable_filename) free(freeable_filename);
		return NULL;
	}

	if(freeable_filename) free(freeable_filename);
	return oilsIDL();
}

char* oilsFMGetString( const jsonObject* object, const char* field ) {
	return jsonObjectToSimpleString(oilsFMGetObject( object, field ));
}


const jsonObject* oilsFMGetObject( const jsonObject* object, const char* field ) {
	if(!(object && field)) return NULL;
	if( object->type != JSON_ARRAY || !object->classname ) return NULL;
	int pos = fm_ntop(object->classname, field);
	if( pos > -1 ) return jsonObjectGetIndex( object, pos );
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
	if(ids) { id = atol(ids); free(ids); }
	return id;
}


oilsEvent* oilsUtilsCheckPerms( int userid, int orgid, char* permissions[], int size ) {
	if(!permissions) return NULL;
	int i;
	oilsEvent* evt = NULL;
	if(orgid == -1) orgid = 1; /* XXX  */

	for( i = 0; i != size && permissions[i]; i++ ) {

		char* perm = permissions[i];
		jsonObject* params = jsonParseStringFmt("[%d, \"%s\", %d]", userid, perm, orgid);
		jsonObject* o = oilsUtilsQuickReq( "open-ils.storage", 
			"open-ils.storage.permission.user_has_perm", params );

		char* r = jsonObjectToSimpleString(o);

		if(r && !strcmp(r, "0")) 
			evt = oilsNewEvent3( OSRF_LOG_MARK, OILS_EVENT_PERM_FAILURE, perm, orgid );

		jsonObjectFree(params);
		jsonObjectFree(o);
		free(r);

		if(evt) break;
	}

	return evt;
}

jsonObject* oilsUtilsQuickReq( const char* service, const char* method,
		const jsonObject* params ) {
	if(!(service && method)) return NULL;
	osrfLogDebug(OSRF_LOG_MARK, "oilsUtilsQuickReq(): %s - %s", service, method );
	osrfAppSession* session = osrfAppSessionClientInit( service ); 
	int reqid = osrfAppSessionMakeRequest( session, params, method, 1, NULL );
	osrfMessage* omsg = osrfAppSessionRequestRecv( session, reqid, 60 ); 
	jsonObject* result = jsonObjectClone(osrfMessageGetResult(omsg));
	osrfMessageFree(omsg);
	osrfAppSessionFree(session);
	return result;
}

jsonObject* oilsUtilsStorageReq( const char* method, const jsonObject* params ) {
	return oilsUtilsQuickReq( "open-ils.storage", method, params );
}

jsonObject* oilsUtilsCStoreReq( const char* method, const jsonObject* params ) {
	return oilsUtilsQuickReq("open-ils.cstore", method, params);
}



jsonObject* oilsUtilsFetchUserByUsername( const char* name ) {
	if(!name) return NULL;
	jsonObject* params = jsonParseStringFmt("{\"usrname\":\"%s\"}", name);
	jsonObject* user = oilsUtilsQuickReq( 
		"open-ils.cstore", "open-ils.cstore.direct.actor.user.search", params );

	jsonObjectFree(params);
	long id = oilsFMGetObjectId(user);
	osrfLogDebug(OSRF_LOG_MARK, "Fetched user %s:%ld", name, id);
	return user;
}

jsonObject* oilsUtilsFetchUserByBarcode(const char* barcode) {
	if(!barcode) return NULL;

	osrfLogInfo(OSRF_LOG_MARK, "Fetching user by barcode %s", barcode);

	jsonObject* params = jsonParseStringFmt("{\"barcode\":\"%s\"}", barcode);
	jsonObject* card = oilsUtilsQuickReq(
		"open-ils.cstore", "open-ils.cstore.direct.actor.card.search", params );

	if(!card) { jsonObjectFree(params); return NULL; }

	char* usr = oilsFMGetString(card, "usr");
	jsonObjectFree(card);
	if(!usr) return NULL;
	double iusr = strtod(usr, NULL);
	free(usr);

	jsonObjectFree(params);
	params = jsonParseStringFmt("[%f]", iusr);
	jsonObject* user = oilsUtilsQuickReq(
		"open-ils.cstore", "open-ils.cstore.direct.actor.user.retrieve", params);

	jsonObjectFree(params);
	return user;
}

char* oilsUtilsFetchOrgSetting( int orgid, const char* setting ) {
	if(!setting) return NULL;

	jsonObject* params = jsonParseStringFmt(
			"[{ \"org_unit\": %d, \"name\":\"%s\" }]", orgid, setting );

	jsonObject* set = oilsUtilsQuickReq(
		"open-ils.storage",
		"open-ils.storage.direct.actor.org_unit_setting.search_where", params );

	jsonObjectFree(params);
	char* value = oilsFMGetString( set, "value" );
	jsonObjectFree(set);
	osrfLogDebug(OSRF_LOG_MARK, "Fetched org [%d] setting: %s => %s", orgid, setting, value);
	return value;

}



char* oilsUtilsLogin( const char* uname, const char* passwd, const char* type, int orgId ) {
	if(!(uname && passwd)) return NULL;

	osrfLogDebug(OSRF_LOG_MARK, "Logging in with username %s", uname );
	char* token = NULL;

	jsonObject* params = jsonParseStringFmt("[\"%s\"]", uname);

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

	params = jsonParseStringFmt( "[\"%s\", \"%s\", \"%s\", \"%d\"]", uname, fullhash, type, orgId );
	o = oilsUtilsQuickReq( "open-ils.auth",
		"open-ils.auth.authenticate.complete", params );

	if(o) {
		const char* tok = jsonObjectGetString(
			jsonObjectGetKey(jsonObjectGetKey(o,"payload"), "authtoken"));
		if(tok) token = strdup(tok);
	}

	free(fullhash);
	jsonObjectFree(params);
	jsonObjectFree(o);

	return token;
}


jsonObject* oilsUtilsFetchWorkstation( long id ) {
	jsonObject* p = jsonParseStringFmt("[%ld]", id);
	jsonObject* r = oilsUtilsQuickReq(
		"open-ils.storage", 
		"open-ils.storage.direct.actor.workstation.retrieve", p );
	jsonObjectFree(p);
	return r;
}

jsonObject* oilsUtilsFetchWorkstationByName( const char* name ) {
	jsonObject* p = jsonParseStringFmt("{\"name\":\"%s\"}", name);
    jsonObject* r = oilsUtilsCStoreReq(
        "open-ils.cstore.direct.actor.workstation.search", p);
	jsonObjectFree(p);
    return r;
}



