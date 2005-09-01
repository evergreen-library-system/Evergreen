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
	JSON parser.
 * --------------------------------------------------------------------------------------- */
#ifndef JSON_PARSER_H
#define JSON_PARSER_H

#include <stdio.h>
#include "object.h"
#include "utils.h"



/* Parses the given JSON string and returns the built object. 
 *	returns NULL (and prints parser error to stderr) on error.  
 */

jsonObject* json_parse_string(char* string);

jsonObject* jsonParseString( char* string );

jsonObject* json_parse_file( const char* filename );

jsonObject* jsonParseFile( const char* string );



/* does the actual parsing work.  returns 0 on success.  -1 on error and
 * -2 if there was no object to build (string was all comments) 
 */
int _json_parse_string(char* string, unsigned long* index, jsonObject* obj);

/* returns 0 on success and turns obj into a string object */
int json_parse_json_string(char* string, unsigned long* index, jsonObject* obj);

/* returns 0 on success and turns obj into a number or double object */
int json_parse_json_number(char* string, unsigned long* index, jsonObject* obj);

/* returns 0 on success and turns obj into an 'object' object */
int json_parse_json_object(char* string, unsigned long* index, jsonObject* obj);

/* returns 0 on success and turns object into an array object */
int json_parse_json_array(char* string, unsigned long* index, jsonObject* obj);

/* churns through whitespace and increments index as it goes.
 * eat_all == true means we should eat newlines, tabs
 */
void json_eat_ws(char* string, unsigned long* index, int eat_all);

int json_parse_json_bool(char* string, unsigned long* index, jsonObject* obj);

/* removes comments from a json string.  if the comment contains a class hint
 * and class_hint isn't NULL, an allocated char* with the class name will be
 * shoved into *class_hint.  returns 0 on success, -1 on parse error.
 * 'index' is assumed to be at the second character (*) of the comment
 */
int json_eat_comment(char* string, unsigned long* index, char** class_hint, int parse_class);

/* prints a useful error message to stderr. always returns -1 */
int json_handle_error(char* string, unsigned long* index, char* err_msg);

/* returns true if c is 0-9 */
int is_number(char c);

int json_parse_json_null(char* string, unsigned long* index, jsonObject* obj);


#endif
