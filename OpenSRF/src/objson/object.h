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
	Generic object framework for C.  An object can be either a string, boolean, null, 
	number, array or hash (think Perl hash, dictionary, etc.).   
 * --------------------------------------------------------------------------------------- */

#include <stdio.h>
#include <unistd.h>
#include <stdlib.h>
#include <string.h>

#include <assert.h>
#include "utils.h"

#define MAX_OBJECT_NODES 1000000

#ifndef OBJECT_H
#define OBJECT_H

/* top level generic object structure */
struct object_struct {

	/* how many sub-objects do we contain.  Note that this includes null
	 * array elements in sparse arrays */
	unsigned long size;

	/* optional class hint */
	char* classname;

	/* these determine how we define a given object */
	int is_array;
	int is_hash;
	int is_string;
	int is_null;
	int is_bool;
	int is_number;
	int is_double;

	/* attached accessor/mutator methods for the OO inclined*/
	unsigned long				(*push)				(struct object_struct* src, struct object_struct*);
	unsigned long				(*set_index)		(struct object_struct* src, unsigned long index, struct object_struct*);
	unsigned long				(*add_key)			(struct object_struct* src, char* key, struct object_struct*);
	struct object_struct*	(*get_index)		(struct object_struct*, unsigned long index);
	struct object_struct*	(*get_key)			(struct object_struct*, char* key);
	void							(*set_string)		(struct object_struct*, char*);
	void							(*set_number)		(struct object_struct*, long number);
	void							(*set_double)		(struct object_struct*, double number);
	void							(*set_class)		(struct object_struct*, char* classname);
	unsigned long				(*remove_index)	(struct object_struct*, unsigned long index);
	unsigned long				(*remove_key)		(struct object_struct*, char* key);
	char*							(*get_string)		(struct object_struct*);
	char*							(*to_json)			(struct object_struct*);
	void							(*set_comment)		(struct object_struct*, char* com);

	/* our list of sub-objects */
	struct object_node_struct* data;

	/* if we're a string, here's our data */
	char* string_data;

	/* if we're a boolean value, here's our value */
	int bool_value;

	/* if we're a number, here's our value */
	long num_value;

	/* if we're a double, here's our value */
	double double_value;

	/* client may provide a comment string which will be 
	 * added serialized object when applicable
	 */
	char* comment;

};
typedef struct object_struct object;


/* this contains a single element of the object along with the elements 
 * index (if this object is an array) and key (if this object is a hash)
 */
struct object_node_struct {
	unsigned long index; /* our array position */
	char* key; /* our hash key */
	object* item; /* our object */
	struct object_node_struct* next; /* pointer to the next object node */
};
typedef struct object_node_struct object_node;

/* utility object for iterating over hash objects */
struct object_iterator_struct {
	object* obj; /* the topic object */
	object_node* current; /* the current node within the object */
	object_node* (*next) (struct object_iterator_struct*);
	int (*has_next) (struct object_iterator_struct*);
};
typedef struct object_iterator_struct object_iterator;

/* allocates a new iterator */
object_iterator* new_iterator(object* obj);

/* de-allocates an iterator */
void free_iterator(object_iterator*);

/* returns the object_node currently pointed to by the iterator
 * and increments the pointer to the next node
 */
object_node* object_iterator_next(object_iterator*);

/* returns true if there is another node after the node 
 * currently pointed to
 */
int object_iterator_has_next(object_iterator*);


/* allocates a new object. 'string' is the string data if this object
	is to be a string.  if not, string should be NULL */
object* new_object(char* string);

object* new_int_object(long num);

object* new_double_object(double num);

/* utility method for initing an object */
object* _init_object();

/* returns a pointer to the object at the given index */
object* object_get_index( object* obj, unsigned long index );


/* returns a pointer to the object with the given key */
object* object_get_key( object* obj, char* key );

/* de-allocates a object ( * should only be called on objects that are not
	children of other objects ) */
void free_object(object*);

/* allocates a new object node */
object_node* new_object_node(object* obj);

/* de-allocates a object node */
void free_object_node(object_node*);


/* pushes the given object onto the end of the list, 
 * returns the size on success, -1 on error 
 * If obj is NULL, inserts a new object into the list with is_null set to true
 */
unsigned long object_push(object*, object* obj);

/* removes (and deallocates) the object at the given index (if one exists) and inserts 
 * the new one.  returns the size on success, -1 on error 
 * If obj is NULL, inserts a new object into the list with is_null set to true
 */
unsigned long object_set_index(object*, unsigned long index, object* obj);

/* inserts the new object, overwriting (removing, deallocating) any 
 * previous object with the given key.
 * returns the size on success, -1 on error 
 * if 'obj' is NULL, a new object is inserted at key 'key' with 'is_null' 
 * set to true
 */
unsigned long object_add_key(object*, char* key, object* obj);

/* removes the object at the given index and, if more items exist,
 * re-indexes (shifts down by 1) the rest of the objects in the array
 */
unsigned long object_remove_index(object*, unsigned long index);

/* removes (and deallocates) the object with key 'key' if it exists */
unsigned long object_remove_key(object*, char* key);

/* returns a pointer to the string data held by this object */
char* object_get_string(object*);

/* sets the string data */
void object_set_string(object*, char* string);

/* sets the number value for the object */
void object_set_number(object*, long num);

/* sets the double value for this object */
void object_set_double(object*, double num);

/* sets the class hint for this object */
void object_set_class(object*, char* classname);

/* converts an object to a json string.  client is responsible for freeing the return string */
char* object_to_json(object*);

/* utility function. clears all of the is_* flags */
void object_clear_type(object*);

/* set this object's comment string */
void object_set_comment(object*, char*);

/* utility method.  starting at index 'index', shifts all indices down by one and 
 * decrements the objects size by 1 
 */
void object_shift_index(object*, unsigned long index);

/* formats a JSON string from printing.  User must free returned string */
char* json_string_format(char* json);


#endif
