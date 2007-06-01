/*
Copyright (C) 2006  Georgia Public Library Service 
Bill Erickson <billserickson@gmail.com>

This program is free software; you can redistribute it and/or
modify it under the terms of the GNU General Public License
as published by the Free Software Foundation; either version 2
of the License, or (at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.
*/

#include "osrf_json.h"

jsonObject* _jsonObjectEncodeClass( jsonObject* obj, int ignoreClass );


jsonObject* jsonObjectFindPath( const jsonObject* obj, char* path, ...);
jsonObject* _jsonObjectFindPathRecurse(const jsonObject* obj, char* root, char* path);
jsonObject* __jsonObjectFindPathRecurse(const jsonObject* obj, char* root);


static char* __tabs(int count) {
	growing_buffer* buf = buffer_init(24);
	int i;
	for(i=0;i<count;i++) OSRF_BUFFER_ADD(buf, "  ");
	char* final = buffer_data( buf );
	buffer_free( buf );
	return final;
}

char* jsonFormatString( const char* string ) {
	if(!string) return strdup("");

	growing_buffer* buf = buffer_init(64);
	int i;
	int depth = 0;
	char* tab = NULL;

	char c;
	for(i=0; i!= strlen(string); i++) {
		c = string[i];

		if( c == '{' || c == '[' ) {

			tab = __tabs(++depth);
			buffer_fadd( buf, "%c\n%s", c, tab);
			free(tab);

		} else if( c == '}' || c == ']' ) {

			tab = __tabs(--depth);
			buffer_fadd( buf, "\n%s%c", tab, c);
			free(tab);

			if(string[i+1] != ',') {
				tab = __tabs(depth);
				buffer_fadd( buf, "%s", tab );	
				free(tab);
			}

		} else if( c == ',' ) {

			tab = __tabs(depth);
			buffer_fadd(buf, ",\n%s", tab);
			free(tab);

		} else { buffer_add_char(buf, c); }

	}

	char* result = buffer_data(buf);
	buffer_free(buf);
	return result;
}



jsonObject* jsonObjectDecodeClass( jsonObject* obj ) {
	if(!obj) return jsonNewObject(NULL);

	jsonObject* newObj		= NULL; 
	jsonObject* classObj		= NULL; 
	jsonObject* payloadObj	= NULL;
	int i;

	if( obj->type == JSON_HASH ) {

		/* are we a special class object? */
		if( (classObj = jsonObjectGetKey( obj, JSON_CLASS_KEY )) ) {

			/* do we have a payload */
			if( (payloadObj = jsonObjectGetKey( obj, JSON_DATA_KEY )) ) {
				newObj = jsonObjectDecodeClass( payloadObj ); 
				jsonObjectSetClass( newObj, jsonObjectGetString(classObj) );

			} else { /* class is defined but there is no payload */
				return NULL;
			}

		} else { /* we're a regular hash */

			jsonObjectIterator* itr = jsonNewObjectIterator(obj);
			jsonObject* tmp;
			newObj = jsonNewObjectType(JSON_HASH);
			while( (tmp = jsonObjectIteratorNext(itr)) ) {
				jsonObject* o = jsonObjectDecodeClass(tmp);
				jsonObjectSetKey( newObj, itr->key, o );
			}
			jsonObjectIteratorFree(itr);
		}

	} else {

		if( obj->type == JSON_ARRAY ) { /* we're an array */
			newObj = jsonNewObjectType(JSON_ARRAY);
			for( i = 0; i != obj->size; i++ ) {
				jsonObject* tmp = jsonObjectDecodeClass(jsonObjectGetIndex( obj, i ) );
				jsonObjectSetIndex( newObj, i, tmp );
			}

		} else { /* not an aggregate type */
			newObj = jsonObjectClone(obj);
		}
	}
		
	return newObj;
}

jsonObject* jsonObjectEncodeClass( jsonObject* obj ) {
	return _jsonObjectEncodeClass( obj, 0 );
}

jsonObject* _jsonObjectEncodeClass( jsonObject* obj, int ignoreClass ) {

	//if(!obj) return NULL;
	if(!obj) return jsonNewObject(NULL);
	jsonObject* newObj = NULL;

	if( obj->classname && ! ignoreClass ) {
		newObj = jsonNewObjectType(JSON_HASH);

		jsonObjectSetKey( newObj, 
			JSON_CLASS_KEY, jsonNewObject(obj->classname) ); 

		jsonObjectSetKey( newObj, 
			JSON_DATA_KEY, _jsonObjectEncodeClass(obj, 1));

	} else if( obj->type == JSON_HASH ) {

		jsonObjectIterator* itr = jsonNewObjectIterator(obj);
		jsonObject* tmp;
		newObj = jsonNewObjectType(JSON_HASH);

		while( (tmp = jsonObjectIteratorNext(itr)) ) {
			jsonObjectSetKey( newObj, itr->key, 
					_jsonObjectEncodeClass(tmp, 0));
		}
		jsonObjectIteratorFree(itr);

	} else if( obj->type == JSON_ARRAY ) {

		newObj = jsonNewObjectType(JSON_ARRAY);
		int i;
		for( i = 0; i != obj->size; i++ ) {
			jsonObjectSetIndex( newObj, i, 
				_jsonObjectEncodeClass(jsonObjectGetIndex( obj, i ), 0 ));
		}

	} else {
		newObj = jsonObjectClone(obj);
	}

	return newObj;
}




static char* _escape_xml (char*);
static int _recurse_jsonObjectToXML(jsonObject*, growing_buffer*);

char* jsonObjectToXML(jsonObject* obj) {

	growing_buffer * res_xml;
	char * output;

	res_xml = buffer_init(1024);

	if (!obj)
		return strdup("<null/>");
	
	_recurse_jsonObjectToXML( obj, res_xml );
	output = buffer_data(res_xml);
	
	buffer_free(res_xml);

	return output;

}

int _recurse_jsonObjectToXML(jsonObject* obj, growing_buffer* res_xml) {

	char * hint = NULL;
	char * bool_val = NULL;
	int i = 0;
	
	if (obj->classname)
		hint = strdup(obj->classname);

	if(obj->type == JSON_NULL) {

		if (hint)
			buffer_fadd(res_xml, "<null class_hint=\"%s\"/>",hint);
		else
			buffer_add(res_xml, "<null/>");

	} else if(obj->type == JSON_BOOL) {

		if (obj->value.b)
			bool_val = strdup("true");
		else
			bool_val = strdup("false");

		if (hint)
			buffer_fadd(res_xml, "<boolean value=\"%s\" class_hint=\"%s\"/>", bool_val, hint);
		else
			buffer_fadd(res_xml, "<boolean value=\"%s\"/>", bool_val);

		free(bool_val);
                
	} else if (obj->type == JSON_STRING) {
		if (hint) {
			char * t = _escape_xml(jsonObjectGetString(obj));
			buffer_fadd(res_xml,"<string class_hint=\"%s\">%s</string>", hint, t);
			free(t);
		} else {
			char * t = _escape_xml(jsonObjectGetString(obj));
			buffer_fadd(res_xml,"<string>%s</string>", t);
			free(t);
		}

	} else if(obj->type == JSON_NUMBER) {
		double x = jsonObjectGetNumber(obj);
		if (hint) {
			if (x == (int)x)
				buffer_fadd(res_xml,"<number class_hint=\"%s\">%d</number>", hint, (int)x);
			else
				buffer_fadd(res_xml,"<number class_hint=\"%s\">%lf</number>", hint, x);
		} else {
			if (x == (int)x)
				buffer_fadd(res_xml,"<number>%d</number>", (int)x);
			else
				buffer_fadd(res_xml,"<number>%lf</number>", x);
		}

	} else if (obj->type == JSON_ARRAY) {

		if (hint) 
        	       	buffer_fadd(res_xml,"<array class_hint=\"%s\">", hint);
		else
               		buffer_add(res_xml,"<array>");

	       	for ( i = 0; i!= obj->size; i++ )
			_recurse_jsonObjectToXML(jsonObjectGetIndex(obj,i), res_xml);

		buffer_add(res_xml,"</array>");

	} else if (obj->type == JSON_HASH) {

		if (hint)
        	       	buffer_fadd(res_xml,"<object class_hint=\"%s\">", hint);
		else
			buffer_add(res_xml,"<object>");

		jsonObjectIterator* itr = jsonNewObjectIterator(obj);
		jsonObject* tmp;
		while( (tmp = jsonObjectIteratorNext(itr)) ) {
			buffer_fadd(res_xml,"<element key=\"%s\">",itr->key);
			_recurse_jsonObjectToXML(tmp, res_xml);
			buffer_add(res_xml,"</element>");
		}
		jsonObjectIteratorFree(itr);

		buffer_add(res_xml,"</object>");
	}

	if (hint)
		free(hint);

	return 1;
}

char* _escape_xml (char* text) {
	char* out;
	growing_buffer* b = buffer_init(256);
	int len = strlen(text);
	int i;
	for (i = 0; i < len; i++) {
		if (text[i] == '&')
			buffer_add(b,"&amp;");
		else if (text[i] == '<')
			buffer_add(b,"&lt;");
		else if (text[i] == '>')
			buffer_add(b,"&gt;");
		else
			buffer_add_char(b,text[i]);
	}
	out = buffer_data(b);
	buffer_free(b);
	return out;
}


jsonObject* jsonParseFile( char* filename ) {
	if(!filename) return NULL;
	char* data = file_to_string(filename);
	jsonObject* o = jsonParseString(data);
	free(data);
	return o;
}



jsonObject* jsonObjectFindPath( const jsonObject* obj, char* format, ...) {
	if(!obj || !format || strlen(format) < 1) return NULL;	

	VA_LIST_TO_STRING(format);
	char* buf = VA_BUF;
	char* token = NULL;
	char* t = buf;
	char* tt; /* strtok storage */

	/* copy the path before strtok_r destroys it */
	char* pathcopy = strdup(buf);

	/* grab the root of the path */
	token = strtok_r(t, "/", &tt);
	if(!token) return NULL;

	/* special case where path starts with //  (start anywhere) */
	if(strlen(pathcopy) > 2 && pathcopy[0] == '/' && pathcopy[1] == '/') {
		jsonObject* it = _jsonObjectFindPathRecurse(obj, token, pathcopy + 1);
		free(pathcopy);
		return it;
	}

	free(pathcopy);

	t = NULL;
	do { 
		obj = jsonObjectGetKey(obj, token);
	} while( (token = strtok_r(NULL, "/", &tt)) && obj);

	return jsonObjectClone(obj);
}

/* --------------------------------------------------------------- */



jsonObject* _jsonObjectFindPathRecurse(const jsonObject* obj, char* root, char* path) {

	if(!obj || ! root || !path) return NULL;

	/* collect all of the potential objects */
	jsonObject* arr = __jsonObjectFindPathRecurse(obj, root);

	/* container for fully matching objects */
	jsonObject* newarr = jsonParseString("[]");
	int i;

	/* path is just /root or /root/ */
	if( strlen(root) + 2 >= strlen(path) ) {
		return arr;

	} else {

		/* gather all of the sub-objects that match the full path */
		for( i = 0; i < arr->size; i++ ) {
			jsonObject* a = jsonObjectGetIndex(arr, i);
			jsonObject* thing = jsonObjectFindPath(a , path + strlen(root) + 1); 

			if(thing) { //jsonObjectPush(newarr, thing);
         	if(thing->type == JSON_ARRAY) {
            	int i;
					for( i = 0; i != thing->size; i++ )
						jsonObjectPush(newarr, jsonObjectClone(jsonObjectGetIndex(thing,i)));
					jsonObjectFree(thing);

				} else {
					jsonObjectPush(newarr, thing);
				}                                         	
			}
		}
	}
	
	jsonObjectFree(arr);
	return newarr;
}

jsonObject* __jsonObjectFindPathRecurse(const jsonObject* obj, char* root) {

	jsonObject* arr = jsonParseString("[]");
	if(!obj) return arr;

	int i;

	/* if the current object has a node that matches, add it */

	jsonObject* o = jsonObjectGetKey(obj, root);
	if(o) jsonObjectPush( arr, jsonObjectClone(o) );

	jsonObject* tmp = NULL;
	jsonObject* childarr;
	jsonObjectIterator* itr = jsonNewObjectIterator(obj);

	/* recurse through the children and find all potential nodes */
	while( (tmp = jsonObjectIteratorNext(itr)) ) {
		childarr = __jsonObjectFindPathRecurse(tmp, root);
		if(childarr && childarr->size > 0) {
			for( i = 0; i!= childarr->size; i++ ) {
				jsonObjectPush( arr, jsonObjectClone(jsonObjectGetIndex(childarr, i)) );
			}
		}
		jsonObjectFree(childarr);
	}

	jsonObjectIteratorFree(itr);

	return arr;
}


