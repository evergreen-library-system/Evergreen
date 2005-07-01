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


#include "json_parser.h"

/* keep a copy of the length of the current json string so we don't 
 * have to calculate it in each function
 */
int current_strlen; /* XXX need to move this into the function params for thread support */

object* json_parse_string(char* string) {

	if(string == NULL) return NULL;

	current_strlen = strlen(string);

	if(current_strlen == 0) 
		return NULL;

	object* obj = new_object(NULL);
	unsigned long index = 0;

	int status = _json_parse_string(string, &index, obj);
	if(!status)
		return obj;

	if(status == -2)
		return NULL;

	return NULL;
}


int _json_parse_string(char* string, unsigned long* index, object* obj) {
	assert(string && index && *index < current_strlen);

	int status = 0; /* return code from parsing routines */
	char* classname = NULL; /* object class hint */
	json_eat_ws(string, index, 1); /* remove leading whitespace */

	char c = string[*index];

	/* remove any leading comments */
	if( c == '/' ) { 

		while(1) {
			(*index)++; /* move to second comment char */
			status = json_eat_comment(string, index, &classname, 1);
			if(status) return status;

			json_eat_ws(string, index, 1);
			c = string[*index];
			if(c != '/')
				break;
		}
	}

	json_eat_ws(string, index, 1); /* remove leading whitespace */

	if(*index >= current_strlen)
		return -2;

	switch(c) {
				
		/* json string */
		case '"': 
			(*index)++;
			status = json_parse_json_string(string, index, obj);
			break;

		/* json array */
		case '[':
			(*index)++;
			status = json_parse_json_array(string, index, obj);			
			break;

		/* json object */
		case '{':
			(*index)++;
			status = json_parse_json_object(string, index, obj);
			break;

		/* NULL */
		case 'n':
		case 'N':
			status = json_parse_json_null(string, index, obj);
			break;
			

		/* true, false */
		case 'f':
		case 'F':
		case 't':
		case 'T':
			status = json_parse_json_bool(string, index, obj);
			break;

		default:
			if(is_number(c) || c == '.' || c == '-') { /* are we a number? */
				status = json_parse_json_number(string, index, obj);	
				if(status) return status;
				break;
			}

			(*index)--;
			/* we should never get here */
			return json_handle_error(string, index, "_json_parse_string() final switch clause");
	}	

	if(status) return status;

	json_eat_ws(string, index, 1);

	if( *index < current_strlen ) {
		/* remove any trailing comments */
		c = string[*index];
		if( c == '/' ) { 
			(*index)++;
			status = json_eat_comment(string, index, NULL, 0);
			if(status) return status;
		}
	}

	if(classname){
		obj->set_class(obj, classname);
		free(classname);
	}

	return 0;
}


int json_parse_json_null(char* string, unsigned long* index, object* obj) {

	if(*index >= (current_strlen - 3)) {
		return json_handle_error(string, index, 
			"_parse_json_string(): invalid null" );
	}

	if(!strncasecmp(string + (*index), "null", 4)) {
		(*index) += 4;
		obj->is_null = 1;
		return 0;
	} else {
		return json_handle_error(string, index,
			"_parse_json_string(): invalid null" );
	}
}

/* should be at the first character of the bool at this point */
int json_parse_json_bool(char* string, unsigned long* index, object* obj) {
	assert(string && obj && *index < current_strlen);

	char* ret = "json_parse_json_bool(): truncated bool";

	if( *index >= (current_strlen - 5))
		return json_handle_error(string, index, ret);
	
	if(!strncasecmp( string + (*index), "false", 5)) {
		(*index) += 5;
		return 0;
	}

	if( *index >= (current_strlen - 4))
		return json_handle_error(string, index, ret);

	if(!strncasecmp( string + (*index), "true", 4)) {
		(*index) += 4;
		return 0;
	}

	return json_handle_error(string, index, ret);
}


/* expecting the first character of the number */
int json_parse_json_number(char* string, unsigned long* index, object* obj) {
	assert(string && obj && *index < current_strlen);

	growing_buffer* buf = buffer_init(64);
	char c = string[*index];

	int done = 0;
	int dot_seen = 0;

	/* negative number? */
	if(c == '-') { buffer_add(buf, "-"); (*index)++; }

	while(*index < current_strlen) {

		if(is_number(c))
			buffer_add_char(buf, c);

		else if( c == '.' ) {
			if(dot_seen) {
				return json_handle_error(string, index, 
					"json_parse_json_number(): malformed json number");
			}
			dot_seen = 1;
		} else {
			done = 1; break;
		}
		(*index)++;
		c = string[*index];
		if(done) break;
	}

	if(dot_seen) {
		obj->is_double = 1;
		obj->double_value = strtod(buf->buf, NULL);
		buffer_free(buf);
		return 0;

	} else {
		obj->is_number = 1;
		obj->num_value = atol(buf->buf);
		buffer_free(buf);
		return 0;
	}
}

/* index should point to the character directly following the '['.  when done
 * index will point to the character directly following the ']' character
 */
int json_parse_json_array(char* string, unsigned long* index, object* obj) {
	assert(string && obj && index && *index < current_strlen);

	int status;
	int in_parse = 0; /* true if this array already contains one item */
	obj->is_array = 1;
	while(*index < current_strlen) {

		json_eat_ws(string, index, 1);

		if(string[*index] == ']') {
			(*index)++;
			break;
		}

		if(in_parse) {
			json_eat_ws(string, index, 1);
			if(string[*index] != ',') {
				return json_handle_error(string, index,
					"json_parse_json_array(): array not followed by a ','");
			}
			(*index)++;
			json_eat_ws(string, index, 1);
		}

		object* item = new_object(NULL);
		status = _json_parse_string(string, index, item);

		if(status) return status;
		obj->push(obj, item);
		in_parse = 1;
	}

	return 0;
}


/* index should point to the character directly following the '{'.  when done
 * index will point to the character directly following the '}'
 */
int json_parse_json_object(char* string, unsigned long* index, object* obj) {
	assert(string && obj && index && *index < current_strlen);

	obj->is_hash = 1;
	int status;
	int in_parse = 0; /* true if we've already added one item to this object */

	while(*index < current_strlen) {

		json_eat_ws(string, index, 1);

		if(string[*index] == '}') {
			(*index)++;
			break;
		}

		if(in_parse) {
			if(string[*index] != ',') {
				return json_handle_error(string, index,
					"json_parse_json_object(): object missing ',' betweenn elements" );
			}
			(*index)++;
			json_eat_ws(string, index, 1);
		}

		/* first we grab the hash key */
		object* key_obj = new_object(NULL);
		status = _json_parse_string(string, index, key_obj);
		if(status) return status;

		if(!key_obj->is_string) {
			return json_handle_error(string, index, 
				"_json_parse_json_object(): hash key not a string");
		}

		char* key = key_obj->string_data;

		json_eat_ws(string, index, 1);

		if(string[*index] != ':') {
			return json_handle_error(string, index, 
				"json_parse_json_object(): hash key not followed by ':' character");
		}

		(*index)++;

		/* now grab the value object */
		json_eat_ws(string, index, 1);
		object* value_obj = new_object(NULL);
		status = _json_parse_string(string, index, value_obj);
		if(status) return status;

		/* put the data into the object and continue */
		obj->add_key(obj, key, value_obj);
		free_object(key_obj);
		in_parse = 1;
	}
	return 0;
}



/* when done, index will point to the character after the closing quote */
int json_parse_json_string(char* string, unsigned long* index, object* obj) {
	assert(string && index && *index < current_strlen);

	int in_escape = 0;	
	int done = 0;
	growing_buffer* buf = buffer_init(64);

	while(*index < current_strlen) {

		char c = string[*index]; 

		switch(c) {

			case '\\':
				if(in_escape) {
					buffer_add(buf, "\\");
					in_escape = 0;
				} else 
					in_escape = 1;
				break;

			case '"':
				if(in_escape) {
					buffer_add(buf, "\"");
					in_escape = 0;
				} else 
					done = 1;
				break;

			case 't':
				if(in_escape) {
					buffer_add(buf,"\t");
					in_escape = 0;
				} else 
					buffer_add_char(buf, c);
				break;

			case 'b':
				if(in_escape) {
					buffer_add(buf,"\b");
					in_escape = 0;
				} else 
					buffer_add_char(buf, c);
				break;

			case 'f':
				if(in_escape) {
					buffer_add(buf,"\f");
					in_escape = 0;
				} else 
					buffer_add_char(buf, c);
				break;

			case 'r':
				if(in_escape) {
					buffer_add(buf,"\r");
					in_escape = 0;
				} else 
					buffer_add_char(buf, c);
				break;

			case 'n':
				if(in_escape) {
					buffer_add(buf,"\n");
					in_escape = 0;
				} else 
					buffer_add_char(buf, c);
				break;

			case 'u':
				if(in_escape) {
					(*index)++;

					if(*index >= (current_strlen - 4)) {
						return json_handle_error(string, index,
							"json_parse_json_string(): truncated escaped unicode"); }

					char buff[5];
					memset(buff,0,5);
					memcpy(buff, string + (*index), 4);


					/* ----------------------------------------------------------------------- */
					/* ----------------------------------------------------------------------- */
					/* The following chunk was borrowed with permission from 
						json-c http://oss.metaparadigm.com/json-c/ */
					unsigned char utf_out[3];
					memset(utf_out,0,3);

					#define hexdigit(x) ( ((x) <= '9') ? (x) - '0' : ((x) & 7) + 9)

					unsigned int ucs_char =
						(hexdigit(string[*index] ) << 12) +
						(hexdigit(string[*index + 1]) << 8) +
						(hexdigit(string[*index + 2]) << 4) +
						hexdigit(string[*index + 3]);
	
					if (ucs_char < 0x80) {
						utf_out[0] = ucs_char;
						buffer_add(buf, utf_out);

					} else if (ucs_char < 0x800) {
						utf_out[0] = 0xc0 | (ucs_char >> 6);
						utf_out[1] = 0x80 | (ucs_char & 0x3f);
						buffer_add(buf, utf_out);

					} else {
						utf_out[0] = 0xe0 | (ucs_char >> 12);
						utf_out[1] = 0x80 | ((ucs_char >> 6) & 0x3f);
						utf_out[2] = 0x80 | (ucs_char & 0x3f);
						buffer_add(buf, utf_out);
					}
					/* ----------------------------------------------------------------------- */
					/* ----------------------------------------------------------------------- */

					(*index) += 3;
					in_escape = 0;

				} else {

					buffer_add_char(buf, c);
				}

				break;

			default:
				buffer_add_char(buf, c);
		}

		(*index)++;
		if(done) break;
	}

	obj->set_string(obj, buf->buf);
	buffer_free(buf);
	return 0;
}


void json_eat_ws(char* string, unsigned long* index, int eat_all) {
	assert(string && index);
	if(*index >= current_strlen)
		return;

	if( eat_all ) { /* removes newlines, etc */
		while(string[*index] == ' ' 	|| 
				string[*index] == '\n' 	||
				string[*index] == '\t') 
			(*index)++;
	}

	else	
		while(string[*index] == ' ') (*index)++;
}


/* index should be at the '*' character at the beginning of the comment.
 * when done, index will point to the first character after the final /
 */
int json_eat_comment(char* string, unsigned long* index, char** buffer, int parse_class) {
	assert(string && index && *index < current_strlen);

	if(string[*index] != '*' && string[*index] != '/' )
		return json_handle_error(string, index, 
			"json_eat_comment(): invalid character after /");

	/* chop out any // style comments */
	if(string[*index] == '/') {
		(*index)++;
		char c = string[*index];
		while(*index < current_strlen) {
			(*index)++;
			if(c == '\n') 
				return 0;
			c = string[*index];
		}
		return 0;
	}

	(*index)++;

	int on_star			= 0; /* true if we just saw a '*' character */

	/* we're just past the '*' */
	if(!parse_class) { /* we're not concerned with class hints */
		while(*index < current_strlen) {
			if(string[*index] == '/') {
				if(on_star) {
					(*index)++;
					return 0;
				}
			}

			if(string[*index] == '*') on_star = 1;
			else on_star = 0;

			(*index)++;
		}
		return 0;
	}



	growing_buffer* buf = buffer_init(64);

	int first_dash		= 0;
	int second_dash	= 0;
	int third_dash		= 0;
	int fourth_dash	= 0;

	int in_hint			= 0;
	int done				= 0;

	/*--S hint--*/   /* <-- Hints  look like this */
	/*--E hint--*/

	while(*index < current_strlen) {
		char c = string[*index];

		switch(c) {

			case '-':
				on_star = 0;
				if(third_dash)			fourth_dash = 1;
				else if(in_hint)		third_dash	= 1;
				else if(first_dash)	second_dash = 1;
				else						first_dash = 1;
				break;

			case 'S':
				on_star = 0;
				if(second_dash && !in_hint) {
					(*index)++;
					json_eat_ws(string, index, 1);
					(*index)--; /* this will get incremented at the bottom of the loop */
					in_hint = 1;
					break;
				}

			case 'E':
				on_star = 0;
				if(second_dash && !in_hint) {
					(*index)++;
					json_eat_ws(string, index, 1);
					(*index)--; /* this will get incremented at the bottom of the loop */
					in_hint = 1;
					break;
				}

			case '*':
				on_star = 1;
				break;

			case '/':
				if(on_star) 
					done = 1;
				else
				on_star = 0;
				break;

			default:
				on_star = 0;
				if(in_hint)
					buffer_add_char(buf, c);
		}

		(*index)++;
		if(done) break;
	}

	if( buf->n_used > 0 && buffer)
		*buffer = buffer_data(buf);

	buffer_free(buf);
	return 0;
}

int is_number(char c) {
	switch(c) {
		case '0':
		case '1':
		case '2':
		case '3':
		case '4':
		case '5':
		case '6':
		case '7':
		case '8':
		case '9':
			return 1;
	}
	return 0;
}

int json_handle_error(char* string, unsigned long* index, char* err_msg) {

	char buf[60];
	memset(buf, 0, 60);

	if(*index > 30)
		strncpy( buf, string + (*index - 30), 59 );
	else
		strncpy( buf, string, 59 );

	fprintf(stderr, 
			"\nError parsing json string at charracter %c "
			"(code %d) and index %ld\nMsg:\t%s\nNear:\t%s\n\n", 
			string[*index], string[*index], *index, err_msg, buf );
	return -1;
}


