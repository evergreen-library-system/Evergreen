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


/* ---------------------------------------------------------------------------------------
	libjson
 * --------------------------------------------------------------------------------------- */

#ifndef _JSON_OBJECT_H
#define _JSON_OBJECT_H

#include <stdio.h>
#include <unistd.h>
#include <stdlib.h>
#include <string.h>

#include "utils.h"

/* json object types */
#define JSON_HASH 	0
#define JSON_ARRAY	1
#define JSON_STRING 	2
#define JSON_NUMBER 	3
#define JSON_NULL 	4	
#define JSON_BOOL 	5


/* top level generic object structure */
struct _jsonObjectStruct {

	/* how many sub-objects do we contain if we're an array or an object.  
		Note that this includes null array elements in sparse arrays */
	unsigned long size;

	/* optional class hint */
	char* classname;

	/* see JSON types above */
	int type;


	/* our cargo */
	union _jsonObjectValue {
		struct _jsonObjectNodeStruct* c; /* our list of sub-objects if we're an array or a hash */
		char* 		s; /* string */
		int 			b; /* bool */
		double		n; /* number */
	} value;
	

	/* client may provide a comment string which will be 
	 * added to the object when stringified */
	char* comment;

};
typedef struct _jsonObjectStruct jsonObject;


/** 
	String parsing function.  This is assigned by the json_parser code.
	to avoid circular dependency, declare the parse function here,
 	and have the json parse code set the variable to a real function 
*/
//jsonObject* (*jsonParseString) (char* str);


/* this contains a single element of the object along with the elements 
 * index (if this object is an array) and key (if this object is a hash)
 */
struct _jsonObjectNodeStruct {

	unsigned long index; /* our array position */
	char* key; /* our hash key */

	jsonObject* item; /* our object */
	struct _jsonObjectNodeStruct* next; /* pointer to the next object node */
};
typedef struct _jsonObjectNodeStruct jsonObjectNode;



/* utility object for iterating over hash objects */
struct _jsonObjectIteratorStruct {
	const jsonObject* obj; /* the topic object */
	jsonObjectNode* current; /* the current node within the object */
};
typedef struct _jsonObjectIteratorStruct jsonObjectIterator;


/** Allocates a new iterator 
	@param obj The object over which to iterate.
*/
jsonObjectIterator* jsonNewObjectIterator(const jsonObject* obj);

/** 
	De-allocates an iterator 
	@param iter The iterator object to free
*/
void jsonObjectIteratorFree(jsonObjectIterator* iter);

/** 
	Returns the object_node currently pointed to by the iterator
  	and increments the pointer to the next node
	@param iter The iterator in question.
 */
jsonObjectNode* jsonObjectIteratorNext(jsonObjectIterator* iter);

/** 
	@param iter The iterator.
	@return True if there is another node after the current node.
 */
int jsonObjectIteratorHasNext(const jsonObjectIterator* iter);


/** 
	Allocates a new object. 
	@param string The string data if this object is to be a string.  
	if not, string should be NULL 
	@return The newly allocated object or NULL on memory error.
*/
jsonObject* jsonNewObject(const char* string);

/**
	Allocates a new JSON number object.
	@param num The number this object is to hold
	@return The newly allocated object.
*/
jsonObject* jsonNewNumberObject( double num);


/** 
	Returns a pointer to the object at the given index.  This call is
	only valid if the object has a type of JSON_ARRAY.
	@param obj The object
	@param index The position within the object
	@return The object at the given index.
*/
jsonObject* jsonObjectGetIndex( const jsonObject* obj, unsigned long index );


/** 
	Returns a pointer to the object with the given key 
	@param obj The object
	@param key The key
	@return The object with the given key.
*/
jsonObject* jsonObjectGetKey( const jsonObject* obj, const char* key );

/** 
	De-allocates an object.  Note that this function should only be called 
	on objects that are _not_ children of other objects or there will be
	double-free's
	@param obj The object to free.
*/
void jsonObjectFree(jsonObject* obj);


/** 
	Allocates a new object node.
	@param obj The object to which the node will be appended.
	@return The new object node.
*/
jsonObjectNode* jsonNewObjectNode(jsonObject* obj);

/** 
	De-allocates an object node 
	@param obj The object node to de-allocate.
*/
void jsonObjectNodeFree(jsonObjectNode* obj);


/** 
	Pushes the given object onto the end of the list.  This coerces an object
	into becoming an array.  _Only_ use this function on objects that you
	want to become an array.
  	If obj is NULL, inserts a new NULL object into the list.
  	@return array size on success, -1 on error 
 */
unsigned long jsonObjectPush(jsonObject* dest, jsonObject* newObj);

/* removes (and deallocates) the object at the given index (if one exists) and inserts 
 * the new one.  returns the size on success, -1 on error 
 * If obj is NULL, inserts a new object into the list with is_null set to true
 */
unsigned long jsonObjectSetIndex(jsonObject* dest, unsigned long index, jsonObject* newObj);

/* inserts the new object, overwriting (removing, deallocating) any 
 * previous object with the given key.
 * returns the size on success, -1 on error 
 * if 'obj' is NULL, a new object is inserted at key 'key' with 'is_null' 
 * set to true
 */
unsigned long jsonObjectSetKey(jsonObject* dest, const char* key, jsonObject* newObj);

/* removes the object at the given index and, if more items exist,
 * re-indexes (shifts down by 1) the rest of the objects in the array
 */
unsigned long jsonObjectRemoveIndex(jsonObject* dest, unsigned long index);

/* removes (and deallocates) the object with key 'key' if it exists */
unsigned long jsonObjectRemoveKey( jsonObject* dest, const char* key);

/* returns a pointer to the string data held by this object if this object
	is a string.  Otherwise returns NULL*/
char* jsonObjectGetString(const jsonObject*);

double jsonObjectGetNumber( const jsonObject* obj );

/* sets the string data */
void jsonObjectSetString(jsonObject* dest, const char* string);

/* sets the number value for the object */
void jsonObjectSetNumber(jsonObject* dest, double num);

/* sets the class hint for this object */
void jsonObjectSetClass(jsonObject* dest, const char* classname );

/* converts an object to a json string.  client is responsible for freeing the return string */
char* jsonObjectToJSON( const jsonObject* obj );

/* set this object's comment string */
void jsonObjectSetComment(jsonObject* dest, const char* classname);

/* utility method.  starting at index 'index', shifts all indices down by one and 
 * decrements the objects size by 1 
 */
void _jsonObjectShiftIndex(jsonObject* dest, unsigned long index);

/* formats a JSON string from printing.  User must free returned string */
char* jsonFormatString( const char* jsonString );

jsonObject* jsonObjectClone( const jsonObject* o );

/* tries to extract the string data from an object.
	if object -> NULL (the C NULL)
	if array ->	NULL  (the C NULL)
	if null	 -> NULL (the C NULL)
	if true/false -> true/false
	if string/number/double the string version of either of those
	The caller is responsible for freeing the returned string
	*/
char* jsonObjectToSimpleString( const jsonObject* o );


/* ------------------------------------------------------------------------ */
/* XPATH */

/* provides an XPATH style search interface (e.g. /some/node/here) and 
	return the object at that location if one exists.  Naturally,  
	every element in the path must be a proper object ("hash" / {}).
	Returns NULL if the specified node is not found 
	Note also that the object returned is a clone and
	must be freed by the caller
*/
jsonObject* jsonObjectFindPath( const jsonObject* obj, char* path, ... );


/* Utility method. finds any object in the tree that matches the path.  
	Use this for finding paths that start with '//' */
jsonObject* _jsonObjectFindPathRecurse( const jsonObject* o, char* root, char* path );

/* returns a list of object whose key is 'root'.  These are used as
	potential objects when doing a // search */
jsonObject* __jsonObjectFindPathRecurse( const jsonObject* o, char* root );

/* ------------------------------------------------------------------------ */


#endif


