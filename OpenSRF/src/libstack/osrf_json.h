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


#include "utils.h"
#include "osrf_list.h"
#include "osrf_hash.h"

#ifndef _JSON_H
#define _JSON_H


/* parser states */
#define JSON_STATE_IN_OBJECT	0x1
#define JSON_STATE_IN_ARRAY		0x2
#define JSON_STATE_IN_STRING	0x4
#define JSON_STATE_IN_UTF		0x8
#define JSON_STATE_IN_ESCAPE	0x10
#define JSON_STATE_IN_KEY		0x20
#define JSON_STATE_IN_NULL		0x40
#define JSON_STATE_IN_TRUE		0x80
#define JSON_STATE_IN_FALSE		0x100
#define JSON_STATE_IN_NUMBER	0x200
#define JSON_STATE_IS_INVALID	0x400
#define JSON_STATE_IS_DONE		0x800
#define JSON_STATE_START_COMMEN	0x1000
#define JSON_STATE_IN_COMMENT	0x2000
#define JSON_STATE_END_COMMENT	0x4000


/* object and array (container) states are pushed onto a stack so we
 * can keep track of the object nest.  All other states are
 * simply stored in the state field of the parser */
#define JSON_STATE_SET(ctx,s) ctx->state |= s; /* set a state */
#define JSON_STATE_REMOVE(ctx,s) ctx->state &= ~s; /* unset a state */
#define JSON_STATE_CHECK(ctx,s) (ctx->state & s) ? 1 : 0 /* check if a state is set */
#define JSON_STATE_POP(ctx) osrfListPop( ctx->stateStack ); /* remove a state from the stack */
#define JSON_STATE_PUSH(ctx, state) osrfListPush( ctx->stateStack,(void*) state );/* push a state on the stack */
#define JSON_STATE_PEEK(ctx) osrfListGetIndex(ctx->stateStack, ctx->stateStack->size -1) /* check which container type we're currently in */
#define JSON_STATE_CHECK_STACK(ctx, s) (JSON_STATE_PEEK(ctx) == (void*) s ) ? 1 : 0  /* compare stack values */

/* JSON types */
#define JSON_HASH 	0
#define JSON_ARRAY	1
#define JSON_STRING	2
#define JSON_NUMBER	3
#define JSON_NULL 	4	
#define JSON_BOOL 	5

#define JSON_PARSE_LAST_CHUNK 0x1 /* this is the last part of the string we're parsing */

#define JSON_PARSE_FLAG_CHECK(ctx, f) (ctx->flags & f) ? 1 : 0 /* check if a parser state is set */

#ifndef JSON_CLASS_KEY
#define JSON_CLASS_KEY "__c"
#endif
#ifndef JSON_DATA_KEY
#define JSON_DATA_KEY "__p"
#endif


struct jsonParserContextStruct {
	int state;						/* what are we currently parsing */
	char* chunk;					/* the chunk we're currently parsing */
	int index;						/* where we are in parsing the current chunk */
	int chunksize;					/* the size of the current chunk */
	int flags;						/* parser flags */
	osrfList* stateStack;		/* represents the nest of object/array states */
	growing_buffer* buffer;		/* used to hold JSON strings, number, true, false, and null sequences */
	growing_buffer* utfbuf;		/* holds the current unicode characters */
	void* userData;				/* opaque user pointer.  we ignore this */
	struct jsonParserHandlerStruct* handler; /* the event handler struct */
};
typedef struct jsonParserContextStruct jsonParserContext;

struct jsonParserHandlerStruct {
	void (*handleStartObject)	(void* userData);
	void (*handleObjectKey)		(void* userData, char* key);
	void (*handleEndObject)		(void* userData);
	void (*handleStartArray)	(void* userData);
	void (*handleEndArray)		(void* userData);
	void (*handleNull)			(void* userData);
	void (*handleString)			(void* userData, char* string);
	void (*handleBool)			(void* userData, int boolval);
	void (*handleNumber)			(void* userData, long double num);
	void (*handleError)			(void* userData, char* err, ...);
};
typedef struct jsonParserHandlerStruct jsonParserHandler;

struct _jsonObjectStruct {
	unsigned long size;	/* number of sub-items */
	char* classname;		/* optional class hint (not part of the JSON spec) */
	int type;				/* JSON type */
	struct _jsonObjectStruct* parent;	/* who we're attached to */
	union __jsonValue {	/* cargo */
		osrfHash*	h;		/* object container */
		osrfList*	l;		/* array container */
		char* 		s;		/* string */
		int 			b;		/* bool */
		long double	n;		/* number */
	} value;
};
typedef struct _jsonObjectStruct jsonObject;

struct _jsonObjectIteratorStruct {
	jsonObject* obj; /* the object we're traversing */
	osrfHashIterator* hashItr; /* the iterator for this hash */
	char* key; /* if this object is an object, the current key */
	unsigned long index; /* if this object is an array, the index */
};
typedef struct _jsonObjectIteratorStruct jsonObjectIterator;



/** 
 * Allocates a new parser context object
 * @param handler The event handler struct
 * @param userData Opaque user pointer which is available in callbacks
 * and ignored by the parser
 * @return An allocated parser context, NULL on error
 */
jsonParserContext* jsonNewParser( jsonParserHandler* handler, void* userData);

/**
 * Deallocates a parser context
 * @param ctx The context object
 */
void jsonParserFree( jsonParserContext* ctx );

/**
 * Parse a chunk of data.
 * @param ctx The parser context
 * @param data The data to parse
 * @param datalen The size of the chunk to parser
 * @param flags Reserved
 */
int jsonParseChunk( jsonParserContext* ctx, char* data, int datalen, int flags );


/**
 * Parses a JSON string;
 * @param str The string to parser
 * @return The resulting JSON object or NULL on error
 */
jsonObject* jsonParseString( char* str );
jsonObject* jsonParseStringRaw( char* str );

jsonObject* jsonParseStringFmt( char* str, ... );

/**
 * Parses a JSON string;
 * @param str The string to parser
 * @return The resulting JSON object or NULL on error
 */
jsonObject* jsonParseStringHandleError( void (*errorHandler) (const char*), char* str, ... );



/**
 * Creates a new json object
 * @param data The string data this object will hold if 
 * this object happens to be a JSON_STRING, NULL otherwise
 * @return The allocated json object.  Must be freed with 
 * jsonObjectFree()
 */
jsonObject* jsonNewObject(char* data, ...);

/**
 * Creates a new object of the given type
 */
jsonObject* jsonNewObjectType(int type);

/**
 * Creates a new number object
 */
jsonObject* jsonNewNumberObject( long double num );

/**
 * Deallocates an object
 */
void jsonObjectFree( jsonObject* o );

/**
 * Forces the given object to become an array (if it isn't already one) 
 * and pushes the new object into the array
 */
unsigned long jsonObjectPush(jsonObject* o, jsonObject* newo);

/**
 * Forces the given object to become a hash (if it isn't already one)
 * and assigns the new object to the key of the hash
 */
unsigned long jsonObjectSetKey(
		jsonObject* o, const char* key, jsonObject* newo);


/**
 * Turns the object into a JSON string.  The string must be freed by the caller */
char* jsonObjectToJSON( const jsonObject* obj );
char* jsonObjectToJSONRaw( const jsonObject* obj );


/**
 * Retrieves the object at the given key
 */
jsonObject* jsonObjectGetKey( const jsonObject* obj, const char* key );






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
jsonObject* jsonObjectIteratorNext(jsonObjectIterator* iter);


/** 
	@param iter The iterator.
	@return True if there is another node after the current node.
 */
int jsonObjectIteratorHasNext(const jsonObjectIterator* iter);


/** 
	Returns a pointer to the object at the given index.  This call is
	only valid if the object has a type of JSON_ARRAY.
	@param obj The object
	@param index The position within the object
	@return The object at the given index.
*/
jsonObject* jsonObjectGetIndex( const jsonObject* obj, unsigned long index );


/* removes (and deallocates) the object at the given index (if one exists) and inserts 
 * the new one.  returns the size on success, -1 on error 
 * If obj is NULL, inserts a new object into the list with is_null set to true
 */
unsigned long jsonObjectSetIndex(jsonObject* dest, unsigned long index, jsonObject* newObj);

/* removes the object at the given index and, if more items exist,
 * re-indexes (shifts down by 1) the rest of the objects in the array
 */
unsigned long jsonObjectRemoveIndex(jsonObject* dest, unsigned long index);

/* removes (and deallocates) the object with key 'key' if it exists */
unsigned long jsonObjectRemoveKey( jsonObject* dest, const char* key);

/* returns a pointer to the string data held by this object if this object
	is a string.  Otherwise returns NULL*/
char* jsonObjectGetString(const jsonObject*);

long double jsonObjectGetNumber( const jsonObject* obj );

/* sets the string data */
void jsonObjectSetString(jsonObject* dest, const char* string);

/* sets the number value for the object */
void jsonObjectSetNumber(jsonObject* dest, double num);

/* sets the class hint for this object */
void jsonObjectSetClass(jsonObject* dest, const char* classname );

int jsonBoolIsTrue( jsonObject* boolObj );


jsonObject* jsonObjectClone( const jsonObject* o );


/* tries to extract the string data from an object.
	if object	-> NULL (the C NULL)
	if array		->	NULL  
	if null		-> NULL 
	if bool		-> NULL
	if string/number the string version of either of those
	The caller is responsible for freeing the returned string
	*/
char* jsonObjectToSimpleString( const jsonObject* o );



/* provides an XPATH style search interface (e.g. /some/node/here) and 
	return the object at that location if one exists.  Naturally,  
	every element in the path must be a proper object ("hash" / {}).
	Returns NULL if the specified node is not found 
	Note also that the object returned is a clone and
	must be freed by the caller
*/
jsonObject* jsonObjectFindPath( const jsonObject* obj, char* path, ... );


/* formats a JSON string from printing.  User must free returned string */
char* jsonFormatString( const char* jsonString );

/* sets the error handler for all parsers */
void jsonSetGlobalErrorHandler(void (*errorHandler) (const char*));

jsonObject* jsonParseFile( char* filename );

/* ------------------------------------------------------------------------- */
/**
 * The following methods provide a ficility for serializing and
 * deserializing "classed" JSON objects.  To give a JSON object a 
 * class, simply call jsonObjectSetClass().  
 * Then, calling jsonObjectEncodeClass() will convert the JSON
 * object (and any sub-objects) to a JSON object with class 
 * wrapper objects like so:
 * { _c : "classname", _d : <json_thing> }
 * In this example _c is the class key and _d is the data (object)
 * key.  The keys are defined by the constants 
 * OSRF_JSON_CLASS_KEY and OSRF_JSON_DATA_KEY
 * To revive a serialized object, simply call
 * jsonObjectDecodeClass()
 */


/** Converts a class-wrapped object into an object with the
 * classname set
 * Caller must free the returned object 
 */ 
jsonObject* jsonObjectDecodeClass( jsonObject* obj );


/** Converts an object with a classname into a
 * class-wrapped (serialized) object
 * Caller must free the returned object 
 */ 
jsonObject* jsonObjectEncodeClass( jsonObject* obj );

/* ------------------------------------------------------------------------- */


/**
 *	Generates an XML representation of a JSON object */
char* jsonObjectToXML(jsonObject*);

#endif
