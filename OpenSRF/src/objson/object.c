/*
Copyright (C) 2005  Georgia Public Library Service 
Bill Erickson <highfalutin@gmail.com>

This program is free software; you can redistribute it and/or
modify it under the terms of the GNU General Public License
as published by the Free Software Foundation; either version 2
of the License, or (at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.
*/

#include "object.h"
#include "json_parser.h"


/* ---------------------------------------------------------------------- */
/* See object.h for function info */
/* ---------------------------------------------------------------------- */


char* __tabs(int count);

jsonObject* jsonNewObject( const char* stringValue, ... ) { 

	jsonObject* obj	= (jsonObject*) safe_malloc(sizeof(jsonObject));
	obj->size			= 0;
	obj->type = JSON_NULL;

	if(stringValue) {
		VA_LIST_TO_STRING(stringValue);
		obj->type = JSON_STRING;
		obj->value.s = strdup(VA_BUF);
	}

	return obj;
}




jsonObject* jsonNewNumberObject( double num ) {
	jsonObject* o = jsonNewObject(NULL);
	o->type = JSON_NUMBER;
	o->value.n = num;
	return o;

}


jsonObjectNode* jsonNewObjectNode( jsonObject* obj ) {
	jsonObjectNode* node = (jsonObjectNode*) safe_malloc(sizeof(jsonObjectNode));
	node->item = obj;
	node->next = NULL;
	node->index = -1;
	return node;
}

unsigned long jsonObjectPush( jsonObject* obj, jsonObject* new_obj) {
	if(!obj) return -1;

	obj->type = JSON_ARRAY;

	if(new_obj == NULL) {
		new_obj = jsonNewObject(NULL);
		new_obj->type = JSON_NULL;
	}

	jsonObjectNode* node = jsonNewObjectNode(new_obj);
	node->index = obj->size++;

	if(obj->value.c == NULL) {
		obj->value.c = node;

	} else {
		/* append the node onto the end */
		jsonObjectNode* tmp = obj->value.c;
		while(tmp) {
			if(tmp->next == NULL) break;
			tmp = tmp->next;
		}
		tmp->next = node;
	}
	return obj->size;
}

unsigned long  jsonObjectSetIndex( jsonObject* obj, unsigned long index, jsonObject* new_obj) {
	if( obj == NULL ) return -1;
	obj->type = JSON_ARRAY;

	if(obj->size <= index)
		obj->size = index + 1;

	if(new_obj == NULL) {
		new_obj = jsonNewObject(NULL);
		new_obj->type = JSON_NULL;
	}

	jsonObjectNode* node = jsonNewObjectNode(new_obj);
	node->index = index;
	
	if( obj->value.c == NULL ) {
		obj->value.c = node;

	} else {

		if(obj->value.c->index == index) {
			jsonObjectNode* tmp = obj->value.c->next;
			jsonObjectNodeFree(obj->value.c);
			obj->value.c = node;
			node->next = tmp;

		} else {
		
			jsonObjectNode* prev = obj->value.c;
			jsonObjectNode* cur = prev->next;
			int inserted = 0;

			while(cur != NULL) {

				/* replace an existing node */
				if( cur->index == index ) {
					jsonObjectNode* tmp = cur->next;
					jsonObjectNodeFree(cur);
					node->next = tmp;
					prev->next = node;
					inserted = 1;
					break;
					
					/* instert between two nodes */
				} else if( prev->index < index && cur->index > index ) {
					prev->next = node;
					node->next = cur;
					inserted = 1;
					break;
				}
				prev = cur;
				cur = cur->next;
			}

			/* shove on to the end */
			if(!inserted) 
				prev->next = node;
		}
	}

	return obj->size;
}


void _jsonObjectShifIndex( jsonObject* obj, unsigned long index) {
	if( obj == NULL || index < 0 ) return;

	if(obj->value.c == NULL) {
		obj->size = 0;
		return;
	}

	jsonObjectNode* data = obj->value.c;
	while(data) {
		if(data->index >= index)
			data->index--;
		data = data->next;
	}
	obj->size--;
}

unsigned long jsonObjectRemoveIndex( jsonObject* obj, unsigned long index) {
	if( obj == NULL || index < 0 ) return -1;

	if(obj->value.c == NULL) return 0;

	/* removing the first item in the list */
	if(obj->value.c->index == index) {
		jsonObjectNode* tmp = obj->value.c->next;
		jsonObjectNodeFree(obj->value.c);
		obj->value.c = tmp;
		_jsonObjectShiftIndex(obj,index);
		return obj->size;
	}


	jsonObjectNode* prev = obj->value.c;
	jsonObjectNode* cur = prev->next;

	while(cur) {
		if(cur->index == index) {
			jsonObjectNode* tmp = cur->next;
			jsonObjectNodeFree(cur);
			prev->next = tmp;
			_jsonObjectShiftIndex(obj, index);
			break;
		}
		prev = cur;
		cur = cur->next;
	}

	return obj->size;	
}


void _jsonObjectShiftIndex(jsonObject* obj, unsigned long index) {

	if( ! obj ) return;

	if(obj->value.c == NULL) {
		obj->size = 0;
		return;
	}

	jsonObjectNode* data = obj->value.c;
	while(data) {
		if(data->index >= index)
			data->index--;
		data = data->next;
	}
	obj->size--;
}


unsigned long jsonObjectRemoveKey( jsonObject* obj, const char* key) {
	if( obj == NULL || key == NULL ) return -1;

	if(obj->value.c == NULL) return 0;

	/* removing the first item in the list */
	if(!strcmp(obj->value.c->key, key)) {

		jsonObjectNode* tmp = obj->value.c->next;
		jsonObjectNodeFree(obj->value.c);

		obj->value.c = tmp;
		if(!obj->value.c) obj->size = 0;
		return obj->size;
	}

	jsonObjectNode* prev = obj->value.c;
	jsonObjectNode* cur = prev->next;

	while(cur) {
		if(!strcmp(cur->key,key)) {

			jsonObjectNode* tmp = cur->next;
			jsonObjectNodeFree(cur);
			prev->next = tmp;
			obj->size--;
			break;
		}
		prev = cur;
		cur = cur->next;
	}

	return obj->size;
}


unsigned long jsonObjectSetKey( jsonObject* obj, const char* key, jsonObject* new_obj ) {
	if( obj == NULL || key == NULL ) return -1;
	obj->type = JSON_HASH;

	if(new_obj == NULL) {
		new_obj = jsonNewObject(NULL);
		new_obj->type = JSON_NULL;
	}

	jsonObjectNode* node = jsonNewObjectNode(new_obj);
	node->key = strdup(key);
	
	if( obj->value.c == NULL ) {
		obj->value.c = node;
		obj->size++;

	} else {

		/* replace the first node */
		if(!strcmp(obj->value.c->key, key)) {
			jsonObjectNode* tmp = obj->value.c->next;
			jsonObjectNodeFree(obj->value.c);
			obj->value.c = node;
			node->next = tmp;

		} else {
		
			jsonObjectNode* prev = obj->value.c;
			jsonObjectNode* cur = prev->next;
			int inserted = 0;

			while(cur != NULL) {

				/* replace an existing node */
				if( !strcmp(cur->key, key) ) {
					jsonObjectNode* tmp = cur->next;
					jsonObjectNodeFree(cur);
					node->next = tmp;
					prev->next = node;
					inserted = 1;
					break;
				}
					
				prev = cur;
				cur = cur->next;
			}

			/* shove on to the end */
			if(!inserted) {
				prev->next = node;
				obj->size++;
			}
		}
	}

	return obj->size;
}


void jsonObjectFree( jsonObject* obj) {
	if(obj == NULL) return;

	free(obj->classname);
	free(obj->comment);

	if( obj->type == JSON_ARRAY || obj->type == JSON_HASH ) {
		while(obj->value.c) {
			jsonObjectNode* tmp = obj->value.c->next;
			jsonObjectNodeFree(obj->value.c);
			obj->value.c = tmp;
		}
	}

	if(obj->type == JSON_STRING)
		free(obj->value.s);

	free(obj);
}

void jsonObjectNodeFree( jsonObjectNode* node ) {
	if(node == NULL) return;
	free(node->key);
	jsonObjectFree(node->item);
	free(node);
}

jsonObject* jsonObjectGetIndex( const jsonObject* obj, unsigned long index ) {

	if( obj && index >= 0 && 
			index < obj->size && obj->type == JSON_ARRAY ) {

		jsonObjectNode* node = obj->value.c;
		while(node) {
			if(node->index == index)
				return node->item;
			node = node->next;
		}
	}

	return NULL;
}

jsonObject* jsonObjectGetKey( const jsonObject* obj, const char* key ) {

	if( obj && key && obj->type == JSON_HASH ) {

		jsonObjectNode* node = obj->value.c;
	
		while(node) {
			if(node->key && !strcmp(node->key, key))
				return node->item;
			node = node->next;
		}	
	}

	return NULL;
}

char* jsonObjectGetString( const jsonObject* obj ) {
	if( obj && obj->type == JSON_STRING ) return obj->value.s;
	return NULL;
}

double jsonObjectGetNumber( const jsonObject* obj ) {
	if( obj && obj->type == JSON_NUMBER ) return obj->value.n;
	return 0;
}

void jsonObjectSetString( jsonObject* obj, const char* string) {
	if( obj ) {
		obj->type = JSON_STRING;
		if(string) obj->value.s = strdup(string);
		else obj->value.s = NULL; 
	}
}


void jsonObjectSetNumber( jsonObject* obj, double num) {
	if(obj) {
		obj->type = JSON_NUMBER;
		obj->value.n = num;
	}
}


void jsonObjectSetClass( jsonObject* obj, const char* classname) {
	if( obj == NULL || classname == NULL ) return;
	obj->classname = strdup(classname);
}



char* jsonObjectToJSON( const jsonObject* obj ) {

	if(obj == NULL) return strdup("null");

	growing_buffer* buf = buffer_init(64);

	/* add class hints if we have a class name */
	if(obj->classname) {
		buffer_add(buf,"/*--S ");
		buffer_add(buf,obj->classname);
		buffer_add(buf, "--*/");
	}

	switch( obj->type ) {

		case JSON_BOOL: 
			if(obj->value.b) buffer_add(buf, "true"); 
			else buffer_add(buf, "false"); 
			break;

		case JSON_NUMBER: {
			double x = obj->value.n;

			/* if the number does not need to be a double,
				turn it into an int on the way out */
			if( x == (int) x ) {
				INT_TO_STRING((int)x);	
				buffer_add(buf, INTSTR);

			} else {
				DOUBLE_TO_STRING(x);
				buffer_add(buf, DOUBLESTR);
			}
			break;
		}

		case JSON_NULL:
			buffer_add(buf, "null");
			break;

		case JSON_STRING:
			buffer_add(buf, "\"");
			char* data = obj->value.s;
			int len = strlen(data);
			
			char* output = uescape(data, len, 1);
			buffer_add(buf, output);
			free(output);
			buffer_add(buf, "\"");
			break;

		case JSON_ARRAY:
			buffer_add(buf, "[");
			int i;
			for( i = 0; i!= obj->size; i++ ) {
				const jsonObject* x = jsonObjectGetIndex(obj,i);
				char* data = jsonObjectToJSON(x);
	
#ifdef STRICT_JSON_WRITE
				buffer_add(buf, data);
#else
				if(strcmp(data,"null")) /* only add the string if it isn't null */
					buffer_add(buf, data);
#endif
	
				free(data);
				if(i != obj->size - 1)
					buffer_add(buf, ",");
			}
			buffer_add(buf, "]");
			break;	

		case JSON_HASH:
	
			buffer_add(buf, "{");
			jsonObjectIterator* itr = jsonNewObjectIterator(obj);
			jsonObjectNode* tmp;
	
			while( (tmp = jsonObjectIteratorNext(itr)) ) {

				buffer_add(buf, "\"");
				buffer_add(buf, tmp->key);
				buffer_add(buf, "\":");
				char* data =  jsonObjectToJSON(tmp->item);

#ifdef STRICT_JSON_WRITE
				buffer_add(buf, data);
#else
				if(strcmp(data,"null")) /* only add the string if it isn't null */
					buffer_add(buf, data);
#endif

				if(jsonObjectIteratorHasNext(itr))
					buffer_add(buf, ",");
				free(data);
			}

			jsonObjectIteratorFree(itr);
			buffer_add(buf, "}");
			break;
		
			default:
				fprintf(stderr, "Unknown object type %d\n", obj->type);
				break;
				
	}

	/* close out the object hint */
	if(obj->classname) {
		buffer_add(buf, "/*--E ");
		buffer_add(buf, obj->classname);
		buffer_add(buf, "--*/");
	}

	if(obj->comment) {
		buffer_add(buf, " /*");
		buffer_add(buf, obj->comment);
		buffer_add(buf, "*/");
	}

	char* data = buffer_data(buf);
	buffer_free(buf);
	return data;

}


void jsonObjectSetComment( jsonObject* obj, const char* com) {
	if( obj == NULL || com == NULL ) return;
	obj->comment = strdup(com);
}


char* __tabs(int count) {
	growing_buffer* buf = buffer_init(24);
	int i;
	for(i=0;i!=count;i++) buffer_add(buf, "   ");
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

	for(i=0; i!= strlen(string); i++) {

		if( string[i] == '{' || string[i] == '[' ) {

			tab = __tabs(++depth);
			buffer_fadd( buf, "%c\n%s", string[i], tab);
			free(tab);

		} else if( string[i] == '}' || string[i] == ']' ) {

			tab = __tabs(--depth);
			buffer_fadd( buf, "\n%s%c", tab, string[i]);
			free(tab);

			if(string[i+1] != ',') {
				tab = __tabs(depth);
				buffer_fadd( buf, "\n%s", tab );	
				free(tab);
			}

		} else if( string[i] == ',' ) {

			tab = __tabs(depth);
			buffer_fadd(buf, ",\n%s", tab);
			free(tab);

		} else { buffer_add_char(buf, string[i]); }

	}

	char* result = buffer_data(buf);
	buffer_free(buf);
	return result;

}


jsonObject* jsonObjectClone(const jsonObject* o) {
	if(!o) return NULL;
	char* json = jsonObjectToJSON(o);
	jsonObject* newo = jsonParseString(json);
	free(json);
	return newo;
}



/* ---------------------------------------------------------------------- */
/* Iterator */

jsonObjectIterator* jsonNewObjectIterator(const jsonObject* obj) {

	if(!obj) return NULL;
	jsonObjectIterator* iter = safe_malloc(sizeof(jsonObjectIterator));
	iter->obj = obj;

	if( obj->type ==  JSON_HASH || obj->type == JSON_ARRAY ) 
		iter->current = obj->value.c;
	else iter->current = NULL;
	return iter;
}

jsonObjectNode* jsonObjectIteratorNext( jsonObjectIterator* itr ) {
	if( itr == NULL ) return NULL;

	jsonObjectNode* tmp = itr->current;
	if(tmp == NULL) return NULL;
	itr->current = itr->current->next;

	return tmp;
}

void jsonObjectIteratorFree(jsonObjectIterator* iter) { 
	free(iter);
}

int jsonObjectIteratorHasNext(const jsonObjectIterator* itr) {
	return (itr && itr->current);
}


jsonObject* jsonObjectFindPath( const jsonObject* obj, char* format, ...) {
	if(!obj || !format || strlen(format) < 1) return NULL;	

	VA_LIST_TO_STRING(format);
	char* buf = VA_BUF;

	/* tmp storage for strtok_r */
	//char tokbuf[len];		
	//bzero(tokbuf, len);

	char* token = NULL;
	char* t = buf;
	//char* tt = tokbuf;
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
						jsonObjectPush(newarr, jsonObjectGetIndex(thing,i));

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

	jsonObjectNode* tmp = NULL;
	jsonObject* childarr;
	jsonObjectIterator* itr = jsonNewObjectIterator(obj);

	/* recurse through the children and find all potential nodes */
	while( (tmp = jsonObjectIteratorNext(itr)) ) {
		childarr = __jsonObjectFindPathRecurse(tmp->item, root);
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


char* jsonObjectToSimpleString( const jsonObject* o ) {
	char* value = NULL;

	if(o) {
		switch( o->type ) {

			case JSON_NUMBER: {

				if( o->value.n == (int) o->value.n ) {
					INT_TO_STRING((int) o->value.n);	
					value = strdup(INTSTR);
	
				} else {
					DOUBLE_TO_STRING(o->value.n);
					value = strdup(DOUBLESTR);
				}

				break;
			}

			case JSON_STRING:
				value = strdup(o->value.s);
		}
	}	
	return value;
}


