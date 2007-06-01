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
#include "osrf_json_utils.h"
#include <ctype.h>


/* if the client sets a global error handler, this will point to it */
static void (*jsonClientErrorCallback) (const char*) = NULL;

/* these are the handlers for our internal parser */
static jsonParserHandler jsonInternalParserHandlerStruct = {
	_jsonHandleStartObject,
	_jsonHandleObjectKey,
	_jsonHandleEndObject,
	_jsonHandleStartArray,
	_jsonHandleEndArray,
	_jsonHandleNull,
	_jsonHandleString,
	_jsonHandleBool,
	_jsonHandleNumber,
	_jsonHandleError
};
static jsonParserHandler* 
	jsonInternalParserHandler = &jsonInternalParserHandlerStruct; 


jsonParserContext* jsonNewParser( jsonParserHandler* handler, void* userData) {
	jsonParserContext* ctx;
	OSRF_MALLOC(ctx, sizeof(jsonParserContext));
	ctx->stateStack			= osrfNewList();
	ctx->buffer					= buffer_init(512);
	ctx->utfbuf					= buffer_init(5);
	ctx->handler				= handler;
	ctx->state					= 0;
	ctx->index					= 0;
	ctx->chunk					= NULL;
	ctx->userData				= userData;
	return ctx;
}

void jsonParserFree( jsonParserContext* ctx ) {
	if(!ctx) return;
	buffer_free(ctx->buffer);
	buffer_free(ctx->utfbuf);
	osrfListFree(ctx->stateStack);
	free(ctx);
}


void jsonSetGlobalErrorHandler(void (*errorHandler) (const char*)) {
	jsonClientErrorCallback = errorHandler;
}


int _jsonParserError( jsonParserContext* ctx, char* err, ... ) {
	if( ctx->handler->handleError ) {
		VA_LIST_TO_STRING(err);
		int pre	= ctx->index - 15;
		int post	= ctx->index + 15;
		while( pre < 0 ) pre++;
		while( post >= ctx->chunksize ) post--;
		int l = post - pre;
		char buf[l];
        memset(buf, 0, l);
		snprintf(buf, l, ctx->chunk + pre);
		ctx->handler->handleError( ctx->userData, 
			"*JSON Parser Error\n - char  = %c\n "
			"- index = %d\n - near  => %s\n - %s", 
			ctx->chunk[ctx->index], ctx->index, buf, VA_BUF );
	}
	JSON_STATE_SET(ctx, JSON_STATE_IS_INVALID);
	return -1;
}


int _jsonParserHandleUnicode( jsonParserContext* ctx ) {

	/* collect as many of the utf characters as we can in this chunk */
	JSON_CACHE_DATA(ctx, ctx->utfbuf, 4);

	/* we ran off the end of the chunk */
	if( ctx->utfbuf->n_used < 4 ) {
		JSON_STATE_SET(ctx, JSON_STATE_IN_UTF);
		return 1;
	}

	ctx->index--; /* push it back to index of the final utf char */

	/* ----------------------------------------------------------------------- */
	/* We have all of the escaped unicode data.  Write it to the buffer */
	/* The following chunk is used with permission from 
	 * json-c http://oss.metaparadigm.com/json-c/ 
	 */
	#define hexdigit(x) ( ((x) <= '9') ? (x) - '0' : ((x) & 7) + 9)
	unsigned char utf_out[4];
	memset(utf_out,0,4);
	char* buf = ctx->utfbuf->buf;

	unsigned int ucs_char =
		(hexdigit(buf[0] ) << 12) +
		(hexdigit(buf[1]) << 8) +
		(hexdigit(buf[2]) << 4) +
		hexdigit(buf[3]);

	if (ucs_char < 0x80) {
		utf_out[0] = ucs_char;
		OSRF_BUFFER_ADD(ctx->buffer, (char*)utf_out);

	} else if (ucs_char < 0x800) {
		utf_out[0] = 0xc0 | (ucs_char >> 6);
		utf_out[1] = 0x80 | (ucs_char & 0x3f);
		OSRF_BUFFER_ADD(ctx->buffer, (char*)utf_out);

	} else {
		utf_out[0] = 0xe0 | (ucs_char >> 12);
		utf_out[1] = 0x80 | ((ucs_char >> 6) & 0x3f);
		utf_out[2] = 0x80 | (ucs_char & 0x3f);
		OSRF_BUFFER_ADD(ctx->buffer, (char*)utf_out);
	}
	/* ----------------------------------------------------------------------- */
	/* ----------------------------------------------------------------------- */

	JSON_STATE_REMOVE(ctx, JSON_STATE_IN_UTF);
	JSON_STATE_REMOVE(ctx, JSON_STATE_IN_ESCAPE);
	buffer_reset(ctx->utfbuf);
	return 0;
}



/* type : 0=null, 1=true, 2=false */
int _jsonParserHandleMatch( jsonParserContext* ctx, int type ) {

	switch(type) {

		case 0: /* JSON null */

			/* first see if we have it all first */
			if( ctx->chunksize > (ctx->index + 3) ) {
				if( strncasecmp(ctx->chunk + ctx->index, "null", 4) ) 
					return _jsonParserError(ctx, "Invalid JSON 'null' sequence");
				if( ctx->handler->handleNull ) 
					ctx->handler->handleNull(ctx->userData);
				ctx->index += 4;
				break;
			}

			JSON_CACHE_DATA(ctx, ctx->buffer, 4);
			if( ctx->buffer->n_used < 4 ) {
				JSON_STATE_SET(ctx, JSON_STATE_IN_NULL);
				return 1;
			} 

			if( strncasecmp(ctx->buffer->buf, "null", 4) ) 
				return _jsonParserError(ctx, "Invalid JSON 'null' sequence");
			if( ctx->handler->handleNull ) 
				ctx->handler->handleNull(ctx->userData);
			break;

		case 1: /* JSON true */

			/* see if we have it all first */
			if( ctx->chunksize > (ctx->index + 3) ) {
				if( strncasecmp(ctx->chunk + ctx->index, "true", 4) ) 
					return _jsonParserError(ctx, "Invalid JSON 'true' sequence");
				if( ctx->handler->handleBool ) 
					ctx->handler->handleBool(ctx->userData, 1);
				ctx->index += 4;
				break;
			}

			JSON_CACHE_DATA(ctx, ctx->buffer, 4);
			if( ctx->buffer->n_used < 4 ) {
				JSON_STATE_SET(ctx, JSON_STATE_IN_TRUE);
				return 1;
			} 
			if( strncasecmp( ctx->buffer->buf, "true", 4 ) ) {
				return _jsonParserError(ctx, "Invalid JSON 'true' sequence");
			}
			if( ctx->handler->handleBool ) 
				ctx->handler->handleBool(ctx->userData, 1);
			break;

		case 2: /* JSON false */

			/* see if we have it all first */
			if( ctx->chunksize > (ctx->index + 4) ) {
				if( strncasecmp(ctx->chunk + ctx->index, "false", 5) ) 
					return _jsonParserError(ctx, "Invalid JSON 'false' sequence");
				if( ctx->handler->handleBool ) 
					ctx->handler->handleBool(ctx->userData, 0);
				ctx->index += 5;
				break;
			}

			JSON_CACHE_DATA(ctx, ctx->buffer, 5);
			if( ctx->buffer->n_used < 5 ) {
				JSON_STATE_SET(ctx, JSON_STATE_IN_FALSE);
				return 1;
			}
			if( strncasecmp( ctx->buffer->buf, "false", 5 ) ) 
				return _jsonParserError(ctx, "Invalid JSON 'false' sequence");
			if( ctx->handler->handleBool ) 
				ctx->handler->handleBool(ctx->userData, 0);
			break;

		default: 
			fprintf(stderr, "Invalid type flag\n");
			return -1;

	}

	ctx->index--; /* set it back to the index of the final sequence character */
	buffer_reset(ctx->buffer);
	JSON_STATE_REMOVE(ctx, JSON_STATE_IN_NULL);
	JSON_STATE_REMOVE(ctx, JSON_STATE_IN_TRUE);
	JSON_STATE_REMOVE(ctx, JSON_STATE_IN_FALSE);

	return 0;
}


int _jsonParserHandleString( jsonParserContext* ctx ) {

	char c = ctx->chunk[ctx->index];

	if( JSON_STATE_CHECK(ctx, JSON_STATE_IN_ESCAPE) ) {

		if( JSON_STATE_CHECK(ctx, JSON_STATE_IN_UTF) ) {

			return _jsonParserHandleUnicode( ctx );
						
		} else {

			switch(c) {

				/* handle all of the escape chars */
				case '\\': OSRF_BUFFER_ADD_CHAR( ctx->buffer, '\\' ); break;
				case '"'	: OSRF_BUFFER_ADD_CHAR( ctx->buffer, '\"' ); break;
				case 't'	: OSRF_BUFFER_ADD_CHAR( ctx->buffer, '\t' ); break;
				case 'b'	: OSRF_BUFFER_ADD_CHAR( ctx->buffer, '\b' ); break;
				case 'f'	: OSRF_BUFFER_ADD_CHAR( ctx->buffer, '\f' ); break;
				case 'r'	: OSRF_BUFFER_ADD_CHAR( ctx->buffer, '\r' ); break;
				case 'n'	: OSRF_BUFFER_ADD_CHAR( ctx->buffer, '\n' ); break;
				case 'u'	: 
					ctx->index++; /* progress to the first utf char */
					return _jsonParserHandleUnicode( ctx );
				default	: OSRF_BUFFER_ADD_CHAR( ctx->buffer, c );
			}
		}

		JSON_STATE_REMOVE(ctx, JSON_STATE_IN_ESCAPE);
		return 0;

	} else {

		switch(c) {

			case '"'	: /* this string is ending */
				if( JSON_STATE_CHECK(ctx, JSON_STATE_IN_KEY) ) {

					/* object key */
					if(ctx->handler->handleObjectKey) {
						ctx->handler->handleObjectKey( 
							ctx->userData, ctx->buffer->buf);
					}

				} else { /* regular json string */

					if(ctx->handler->handleString) {
						ctx->handler->handleString( 
							ctx->userData, ctx->buffer->buf );
					}

				}

				buffer_reset(ctx->buffer); /* flush the buffer and states */
				JSON_STATE_REMOVE(ctx, JSON_STATE_IN_STRING);
				JSON_STATE_REMOVE(ctx, JSON_STATE_IN_KEY);
				break;

			case '\\' : JSON_STATE_SET(ctx, JSON_STATE_IN_ESCAPE); break;
			default	 : OSRF_BUFFER_ADD_CHAR( ctx->buffer, c );
		}
	}
	return 0;
}


int _jsonParserHandleNumber( jsonParserContext* ctx ) {
	char c = ctx->chunk[ctx->index];

	do {
		OSRF_BUFFER_ADD_CHAR(ctx->buffer, c);
		c = ctx->chunk[++(ctx->index)];
	} while( strchr(JSON_NUMBER_CHARS, c) && ctx->index < ctx->chunksize );

	/* if we're run off the end of the chunk and we're not parsing the last chunk,
	 * save the number and the state */
	if( ctx->index >= ctx->chunksize && 
			! JSON_PARSE_FLAG_CHECK(ctx, JSON_PARSE_LAST_CHUNK) ) {
		JSON_STATE_SET(ctx, JSON_STATE_IN_NUMBER);
		return 1;
	}

	/* make me more strict */
	char* err = NULL;
	long double d = strtod(ctx->buffer->buf, &err);
	if(err && err[0] != '\0') 
		return _jsonParserError(ctx, "Invalid number sequence");
	JSON_STATE_REMOVE(ctx, JSON_STATE_IN_NUMBER);
	buffer_reset(ctx->buffer);
	if(ctx->handler->handleNumber)
		ctx->handler->handleNumber( ctx->userData, d );
	ctx->index--; /* scooch back to the first non-digit number */
	return 0;
}




int jsonParseChunk( jsonParserContext* ctx, char* data, int datalen, int flags ) {

	if( !( ctx && ctx->handler && data && datalen > 0 )) return -1;
	ctx->chunksize  = datalen;
	ctx->chunk		= data;
	ctx->flags		= flags;
	char c;

	if( JSON_STATE_CHECK(ctx, JSON_STATE_IS_INVALID) )
		return _jsonParserError( ctx, "JSON Parser cannot continue after an error" );

	if( JSON_STATE_CHECK(ctx, JSON_STATE_IS_DONE) )
		return _jsonParserError( ctx, "Extra content at end of JSON data" );

	for( ctx->index = 0; (ctx->index < ctx->chunksize) && 
				(c = ctx->chunk[ctx->index]); ctx->index++ ) {

		/* middle of parsing a string */
		if( JSON_STATE_CHECK(ctx, JSON_STATE_IN_STRING)) {
			if( _jsonParserHandleString(ctx) == -1 )
				return -1;
			continue;
		}

		/* middle of parsing a number */
		if( JSON_STATE_CHECK(ctx, JSON_STATE_IN_NUMBER) ) {
			if( _jsonParserHandleNumber(ctx) == -1 )
				return -1;
			continue;
		}


#ifdef JSON_IGNORE_COMMENTS
		/* we just saw a bare '/' character */
		if( JSON_STATE_CHECK(ctx, JSON_STATE_START_COMMENT) ) {
			if(c == '*') {
				JSON_STATE_REMOVE(ctx, JSON_STATE_START_COMMENT);
				JSON_STATE_SET(ctx, JSON_STATE_IN_COMMENT);
				continue;
			} else {
				return _jsonParserError( ctx, "Invalid comment initializer" );
			}
		}

		/* we're currently in the middle of a comment block */
		if( JSON_STATE_CHECK(ctx, JSON_STATE_IN_COMMENT) ) {
			if(c == '*') {
				JSON_STATE_REMOVE(ctx, JSON_STATE_IN_COMMENT);
				JSON_STATE_SET(ctx, JSON_STATE_END_COMMENT);
				continue;
			} else {
				continue;
			}
		}

		/* we're in a comment, and we just saw a '*' character */
		if( JSON_STATE_CHECK(ctx, JSON_STATE_END_COMMENT) ) {
			if( c == '/' ) { /* comment is finished */
				JSON_STATE_REMOVE(ctx, JSON_STATE_END_COMMENT);
				continue;
			} else {
				/* looks like this isn't the end of the comment after all */
				JSON_STATE_SET(ctx, JSON_STATE_IN_COMMENT);
				JSON_STATE_REMOVE(ctx, JSON_STATE_END_COMMENT);
			}
		}
#endif

		/* if we're in the middle of parsing a null/true/false sequence */
		if( JSON_STATE_CHECK(ctx, (JSON_STATE_IN_NULL | 
					JSON_STATE_IN_TRUE | JSON_STATE_IN_FALSE)) ) {

			int type = (JSON_STATE_CHECK(ctx, JSON_STATE_IN_NULL)) ? 0 :
				(JSON_STATE_CHECK(ctx, JSON_STATE_IN_TRUE)) ? 1 : 2;

			if( _jsonParserHandleMatch( ctx, type ) == -1 ) 
				return -1;
			continue;
		}

		JSON_EAT_WS(ctx);

		/* handle all of the top level characters */
		switch(c) {

			case '{' : /* starting an object */
				if( ctx->handler->handleStartObject) 
					ctx->handler->handleStartObject( ctx->userData );
				JSON_STATE_PUSH(ctx, JSON_STATE_IN_OBJECT);
				JSON_STATE_SET(ctx, JSON_STATE_IN_KEY);
				break;

			case '}' : /* ending an object */
				if( ctx->handler->handleEndObject) 
					ctx->handler->handleEndObject( ctx->userData ); 
				JSON_STATE_POP(ctx);
				if( JSON_STATE_PEEK(ctx) == NULL )
					JSON_STATE_SET(ctx, JSON_STATE_IS_DONE);
				break;

			case '[' : /* starting an array */
				if( ctx->handler->handleStartArray )
					ctx->handler->handleStartArray( ctx->userData );
				JSON_STATE_PUSH(ctx, JSON_STATE_IN_ARRAY);
				break;

			case ']': /* ending an array */
				if( ctx->handler->handleEndArray )
					ctx->handler->handleEndArray( ctx->userData );
				JSON_STATE_POP(ctx);
				if( JSON_STATE_PEEK(ctx) == NULL )
					JSON_STATE_SET(ctx, JSON_STATE_IS_DONE);
				break;
				
			case ':' : /* done with the object key */
				JSON_STATE_REMOVE(ctx, JSON_STATE_IN_KEY);
				break;

			case ',' : /* after object or array item */
				if( JSON_STATE_CHECK_STACK(ctx, JSON_STATE_IN_OBJECT) )
					JSON_STATE_SET(ctx, JSON_STATE_IN_KEY);
				break;

			case 'n' :
			case 'N' : /* null */
				if( _jsonParserHandleMatch( ctx, 0 ) == -1)
					return -1;
				break;

			case 't' :
			case 'T' :
				if( _jsonParserHandleMatch( ctx, 1 ) == -1 )
					return -1;
				break;

			case 'f' :
			case 'F' :
				if( _jsonParserHandleMatch( ctx, 2 ) == -1)
					return -1;
				break;

			case '"' : 
				JSON_STATE_SET(ctx, JSON_STATE_IN_STRING);
				break;

#ifdef JSON_IGNORE_COMMENTS
			case '/' :
				JSON_STATE_SET(ctx, JSON_STATE_START_COMMENT);
				break;
#endif

			default:
				if( strchr(JSON_NUMBER_CHARS, c) ) {
					if( _jsonParserHandleNumber( ctx ) == -1 )
						return -1;
				} else {
					return _jsonParserError( ctx, "Invalid Token" );
				}
		}
	}

	return 0;
}


jsonInternalParser* _jsonNewInternalParser() {
	jsonInternalParser* p;
	OSRF_MALLOC(p, sizeof(jsonInternalParser));
	p->ctx = jsonNewParser( jsonInternalParserHandler, p );
	p->obj		= NULL;
	p->lastkey	= NULL;
	return p;
}

void _jsonInternalParserFree(jsonInternalParser* p) {
	if(!p) return;
	jsonParserFree(p->ctx);
	free(p->lastkey);
	free(p);
}

static jsonObject* _jsonParseStringImpl(char* str, void (*errorHandler) (const char*) ) {
	jsonInternalParser* parser = _jsonNewInternalParser();
	parser->handleError = errorHandler;
	jsonParseChunk( parser->ctx, str, strlen(str),  JSON_PARSE_LAST_CHUNK );
	jsonObject* obj = parser->obj;
	_jsonInternalParserFree(parser);
	return obj;
}

jsonObject* jsonParseStringHandleError( 
		void (*errorHandler) (const char*), char* str, ... ) {
	if(!str) return NULL;
	VA_LIST_TO_STRING(str);
	return _jsonParseStringImpl(VA_BUF, errorHandler);
}

jsonObject* jsonParseString( char* str ) {
	if(!str) return NULL;
	jsonObject* obj =  _jsonParseStringImpl(str, NULL);
	jsonObject* obj2 = jsonObjectDecodeClass(obj);
	jsonObjectFree(obj);
	return obj2;
}

jsonObject* jsonParseStringRaw( char* str ) {
	if(!str) return NULL;
	return _jsonParseStringImpl(str, NULL);
}

jsonObject* jsonParseStringFmt( char* str, ... ) {
	if(!str) return NULL;
	VA_LIST_TO_STRING(str);
	return _jsonParseStringImpl(VA_BUF, NULL);
}


#define JSON_SHOVE_ITEM(ctx,type)  \
	jsonInternalParser* p = (jsonInternalParser*) ctx;\
	_jsonInsertParserItem(p, jsonNewObjectType(type));

void _jsonHandleStartObject(void* ctx) { JSON_SHOVE_ITEM(ctx, JSON_HASH); }
void _jsonHandleStartArray(void* ctx) { JSON_SHOVE_ITEM(ctx, JSON_ARRAY); }
void _jsonHandleNull(void* ctx) { JSON_SHOVE_ITEM(ctx, JSON_NULL); }

void _jsonHandleObjectKey(void* ctx, char* key) {
	jsonInternalParser* p = (jsonInternalParser*) ctx;
	free(p->lastkey);
	p->lastkey = strdup(key);
}

void _jsonHandleEndObject(void* ctx) {
	jsonInternalParser* p = (jsonInternalParser*) ctx;
	p->current = p->current->parent;
}

void _jsonHandleEndArray(void* ctx) {
	jsonInternalParser* p = (jsonInternalParser*) ctx;
	p->current = p->current->parent;
}

void _jsonHandleString(void* ctx, char* string) {
	jsonInternalParser* p = (jsonInternalParser*) ctx;
	_jsonInsertParserItem(p, jsonNewObject(string));
}

void _jsonHandleBool(void* ctx, int boolval) {
	jsonInternalParser* p = (jsonInternalParser*) ctx;
	jsonObject* obj = jsonNewObjectType(JSON_BOOL);
	obj->value.b = boolval;
	_jsonInsertParserItem(p, obj);
}

void _jsonHandleNumber(void* ctx, long double num) {
	jsonInternalParser* p = (jsonInternalParser*) ctx;
	_jsonInsertParserItem(p, jsonNewNumberObject(num));
}

void _jsonHandleError(void* ctx, char* str, ...) {
	jsonInternalParser* p = (jsonInternalParser*) ctx;
	VA_LIST_TO_STRING(str);

	if( p->handleError ) 
		p->handleError(VA_BUF);
	else 
		if( jsonClientErrorCallback ) 
			jsonClientErrorCallback(VA_BUF);

	else fprintf(stderr, "%s\n", VA_BUF);
	jsonObjectFree(p->obj);
	p->obj = NULL;
}


void _jsonInsertParserItem( jsonInternalParser* p, jsonObject* newo ) {

	if( !p->obj ) {

		/* new parser, set the new object to our object */
		p->obj = p->current = newo;

	} else {

		/* insert the new object into the current container object */
		switch(p->current->type) { 
			case JSON_HASH	: jsonObjectSetKey(p->current, p->lastkey, newo);  break;
			case JSON_ARRAY: jsonObjectPush(p->current, newo); break;
			default: fprintf(stderr, "%s:%d -> how?\n", JSON_LOG_MARK); 
		} 

		/* if the new object is a container object, make it our current container */
		if( newo->type == JSON_ARRAY || newo->type == JSON_HASH )
			p->current = newo;	
	}
}


