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
	int pos = fm_ntop(object->classname, field);
	if( pos > -1 ) {
		jsonObjectSetIndex( object, pos, jsonNewObject(string) );
		return 0;
	}
	return -1;
}
