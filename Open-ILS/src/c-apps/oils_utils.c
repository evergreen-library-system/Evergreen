#include "oils_utils.h"

char* oilsFMGetString( jsonObject* object, char* field ) {
	return jsonObjectToSimpleString(oilsFMGetObject( object, field ));
}


jsonObject* oilsFMGetObject( jsonObject* object, char* field ) {
	if(!(object && field)) return NULL;
	if( object->type != JSON_ARRAY || !object->classname ) return NULL;
	int pos = fm_ntop(object->classname, field);
	if( pos > -1 ) return jsonObjectGetIndex( object, pos );
	return NULL;
}


int oilsFMSetString( jsonObject* object, char* field, char* string ) {
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


long oilsFMGetObjectId( jsonObject* obj ) {
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
		jsonObject* params = jsonParseString("[%d, \"%s\", %d]", userid, perm, orgid);
		jsonObject* o = oilsUtilsQuickReq( "open-ils.storage", 
			"open-ils.storage.permission.user_has_perm", params );

		char* r = jsonObjectToSimpleString(o);

		if(r && !strcmp(r, "0")) 
			evt = oilsNewEvent3( OILS_EVENT_PERM_FAILURE, perm, orgid );

		jsonObjectFree(params);
		jsonObjectFree(o);
		free(r);

		if(evt) break;
	}

	return evt;
}

jsonObject* oilsUtilsQuickReq( char* service, char* method, jsonObject* params ) {
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



jsonObject* oilsUtilsFetchUserByUsername( char* name ) {
	if(!name) return NULL;
	jsonObject* params = jsonParseString("[\"%s\"]", name);
	jsonObject* r = oilsUtilsQuickReq( "open-ils.storage",
			"open-ils.storage.direct.actor.user.search.usrname.atomic", params );
	jsonObject* user = jsonObjectClone(jsonObjectGetIndex( r, 0 ));
	jsonObjectFree(r);
	return user;
}

char* oilsUtilsFetchOrgSetting( int orgid, char* setting ) {
	if(!setting) return NULL;

	jsonObject* params = jsonParseString(
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



char* oilsUtilsLogin( char* uname, char* passwd, char* type, int orgId ) {
	if(!(uname && passwd)) return NULL;

	osrfLogDebug(OSRF_LOG_MARK, "Logging in with username %s", uname );
	char* token = NULL;

	jsonObject* params = jsonParseString("[\"%s\"]", uname);

	jsonObject* o = oilsUtilsQuickReq( "open-ils.auth",
		"open-ils.auth.authenticate.init", params );

	char* seed = jsonObjectGetString(o);
	char* passhash = md5sum(passwd);
	char buf[256];
	bzero(buf, 256);
	snprintf(buf, 255, "%s%s", seed, passhash);
	char* fullhash = md5sum(buf);

	jsonObjectFree(o);
	jsonObjectFree(params);
	free(passhash);

	params = jsonParseString( "[\"%s\", \"%s\", \"%s\", \"%d\"]", uname, fullhash, type, orgId );
	o = oilsUtilsQuickReq( "open-ils.auth",
		"open-ils.auth.authenticate.complete", params );

	if(o) {
		char* tok = jsonObjectGetString(
			jsonObjectGetKey(jsonObjectGetKey(o,"payload"), "authtoken"));
		if(tok) token = strdup(tok);
	}

	free(fullhash);
	jsonObjectFree(params);
	jsonObjectFree(o);

	return token;
}


jsonObject* oilsUtilsFetchWorkstation( long id ) {
	jsonObject* p = jsonParseString("[%ld]", id);
	jsonObject* r = oilsUtilsQuickReq(
		"open-ils.storage", 
		"open-ils.storage.direct.actor.workstation.retrieve", p );
	jsonObjectFree(p);
	return r;
}


