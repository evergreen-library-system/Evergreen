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
	osrfLogInternal("oilsFMSetString(): Collecing position for field %s", field);
	int pos = fm_ntop(object->classname, field);
	if( pos > -1 ) {
		osrfLogInternal("oilsFMSetString(): Setting string "
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
	osrfLogDebug("oilsUtilsQuickReq(): %s - %s", service, method );
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

