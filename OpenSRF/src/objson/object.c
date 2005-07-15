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
#include <fcntl.h>



/* ---------------------------------------------------------------------- */
/* See object.h for function info */
/* ---------------------------------------------------------------------- */

object* new_object(char* string_value) {
	return _init_object(string_value);
}


object* new_int_object(long num) {
	object* o = new_object(NULL);
	o->is_null = 0;
	o->is_number = 1;
	o->num_value = num;
	return o;
}

object* new_double_object(double num) {
	object* o = new_object(NULL);
	o->is_null = 0;
	o->is_double = 1;
	o->double_value = num;
	return o;
}

object* _init_object(char* string_value) {

	object* obj			= (object*) safe_malloc(sizeof(object));
	obj->size			= 0;
	obj->data			= NULL;

	obj->push			= &object_push;
	obj->set_index		= &object_set_index;
	obj->add_key		= &object_add_key;
	obj->get_index		= &object_get_index;
	obj->get_key		= &object_get_key;
	obj->get_string	= &object_get_string;
	obj->set_string	= &object_set_string;
	obj->set_number	= &object_set_number;
	obj->set_class		= &object_set_class;
	obj->set_double	= &object_set_double;
	obj->remove_index = &object_remove_index;
	obj->remove_key	= &object_remove_key;
	obj->to_json		= &object_to_json;
	obj->set_comment	= &object_set_comment;

	if(string_value) {
		obj->is_string = 1;
		obj->string_data = strdup(string_value);
	} else
		obj->is_null = 1;

	return obj;
}

object_node* new_object_node(object* obj) {
	object_node* node = (object_node*) safe_malloc(sizeof(object_node));
	node->item = obj;
	node->next = NULL;
	node->index = -1;
	return node;
}

unsigned long object_push(object* obj, object* new_obj) {
	assert(obj != NULL);
	object_clear_type(obj);
	obj->is_array = 1;

	if(new_obj == NULL) {
		new_obj = new_object(NULL);
		new_obj->is_null = 1;
	}

	object_node* node = new_object_node(new_obj);
	node->index = obj->size++;

	if( obj->size > MAX_OBJECT_NODES )
		return -1;

	if(obj->data == NULL) {
		obj->data = node;

	} else {
		/* append the node onto the end */
		object_node* tmp = obj->data;
		while(tmp) {
			if(tmp->next == NULL) break;
			tmp = tmp->next;
		}
		tmp->next = node;
	}
	return obj->size;
}

unsigned long  object_set_index(object* obj, unsigned long index, object* new_obj) {
	assert(obj != NULL && index <= MAX_OBJECT_NODES);
	object_clear_type(obj);
	obj->is_array = 1;

	if(obj->size <= index)
		obj->size = index + 1;

	if(new_obj == NULL) {
		new_obj = new_object(NULL);
		new_obj->is_null = 1;
	}

	object_node* node = new_object_node(new_obj);
	node->index = index;
	
	if( obj->data == NULL ) {
		obj->data = node;

	} else {

		if(obj->data->index == index) {
			object_node* tmp = obj->data->next;
			free_object_node(obj->data);
			obj->data = node;
			node->next = tmp;

		} else {
		
			object_node* prev = obj->data;
			object_node* cur = prev->next;
			int inserted = 0;

			while(cur != NULL) {

				/* replace an existing node */
				if( cur->index == index ) {
					object_node* tmp = cur->next;
					free_object_node(cur);
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


void object_shift_index(object* obj, unsigned long index) {
	assert(obj && index <= MAX_OBJECT_NODES);
	if(obj->data == NULL) {
		obj->size = 0;
		return;
	}

	object_node* data = obj->data;
	while(data) {
		if(data->index >= index)
			data->index--;
		data = data->next;
	}
	obj->size--;
}

unsigned long object_remove_index(object* obj, unsigned long index) {
	assert(obj != NULL && index <= MAX_OBJECT_NODES);
	if(obj->data == NULL) return 0;

	/* removing the first item in the list */
	if(obj->data->index == index) {
		object_node* tmp = obj->data->next;
		free_object_node(obj->data);
		obj->data = tmp;
		object_shift_index(obj,index);
		return obj->size;
	}


	object_node* prev = obj->data;
	object_node* cur = prev->next;

	while(cur) {
		if(cur->index == index) {
			object_node* tmp = cur->next;
			free_object_node(cur);
			prev->next = tmp;
			object_shift_index(obj,index);
			break;
		}
		prev = cur;
		cur = cur->next;
	}

	return obj->size;	
}


unsigned long object_remove_key(object* obj, char* key) {
	assert(obj && key);
	if(obj->data == NULL) return 0;

	/* removing the first item in the list */
	if(!strcmp(obj->data->key, key)) {
		object_node* tmp = obj->data->next;
		free_object_node(obj->data);
		obj->data = tmp;
		if(!obj->data) 
			obj->size = 0;

		return obj->size;
	}

	object_node* prev = obj->data;
	object_node* cur = prev->next;

	while(cur) {
		if(!strcmp(cur->key,key)) {
			object_node* tmp = cur->next;
			free_object_node(cur);
			prev->next = tmp;
			obj->size--;
			break;
		}
		prev = cur;
		cur = cur->next;
	}

	return obj->size;
}


unsigned long object_add_key(object* obj, char* key, object* new_obj) {

	assert(obj != NULL && key != NULL);
	object_clear_type(obj);
	obj->is_hash = 1;


	if(new_obj == NULL) {
		new_obj = new_object(NULL);
		new_obj->is_null = 1;
	}

	object_node* node = new_object_node(new_obj);
	node->key = strdup(key);
	
	if( obj->data == NULL ) {
		obj->data = node;
		obj->size++;

	} else {

		/* replace the first node */
		if(!strcmp(obj->data->key, key)) {
			object_node* tmp = obj->data->next;
			free_object_node(obj->data);
			obj->data = node;
			node->next = tmp;

		} else {
		
			object_node* prev = obj->data;
			object_node* cur = prev->next;
			int inserted = 0;

			while(cur != NULL) {

				/* replace an existing node */
				if( !strcmp(cur->key, key) ) {
					object_node* tmp = cur->next;
					free_object_node(cur);
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


void free_object(object* obj) {

	if(obj == NULL) return;
	if(obj->classname) free(obj->classname);
	if(obj->comment) free(obj->comment);

	while(obj->data) {
		object_node* tmp = obj->data->next;
		free_object_node(obj->data);
		obj->data = tmp;
	}

	if(obj->string_data) 
		free(obj->string_data);
	free(obj);
}

void free_object_node(object_node* node) {
	if(node == NULL) return;
	if(node->key) free(node->key);
	free_object(node->item);
	free(node);
}

object* object_get_index( object* obj, unsigned long index ) {
	assert(obj != NULL && index <= MAX_OBJECT_NODES);
	object_node* node = obj->data;
	while(node) {
		if(node->index == index)
			return node->item;
		node = node->next;
	}
	return NULL;
}

object* object_get_key( object* obj, char* key ) {
	assert(obj && key);
	object_node* node = obj->data;

	while(node) {
		if(node->key && !strcmp(node->key, key))
			return node->item;
		node = node->next;
	}	

	return NULL;
}

char* object_get_string(object* obj) {
	assert(obj != NULL);
	return obj->string_data;
}

void object_set_string(object* obj, char* string) {
	assert(obj);
	object_clear_type(obj);
	obj->is_string = 1;
	if(string)
		obj->string_data = strdup(string);
}


void object_set_number(object* obj, long num) {
	assert(obj);
	object_clear_type(obj);
	obj->is_number = 1;
	obj->num_value = num;
}

void object_set_double(object* obj, double num) {
	assert(obj);
	object_clear_type(obj);
	obj->is_double = 1;
	obj->double_value = num;
}


void object_set_class(object* obj, char* classname) {
	assert(obj && classname);
	obj->classname = strdup(classname);
}



char* object_to_json(object* obj) {

	if(obj == NULL)
		return strdup("null");

	growing_buffer* buf = buffer_init(64);

	/* add class hints if we have a class name */
	if(obj->classname) {
		buffer_add(buf,"/*--S ");
		buffer_add(buf,obj->classname);
		buffer_add(buf, "--*/");
	}

	if(obj->is_bool && obj->bool_value)
			buffer_add(buf, "true"); 

	else if(obj->is_bool && ! obj->bool_value)
			buffer_add(buf, "false"); 

	else if(obj->is_number) {
		char b[128];
		memset(b, 0, 128);
		sprintf(b, "%ld", obj->num_value);
		buffer_add(buf, b);
	}

	else if(obj->is_double) {
		char b[128];
		memset(b, 0, 128);
		sprintf(b, "%lf", obj->double_value);
		buffer_add(buf, b);
	}

	else if(obj->is_null)
		buffer_add(buf, "null");

	else if (obj->is_string) {

		buffer_add(buf, "\"");
		char* data = obj->string_data;
		int len = strlen(data);
		
		char* output = uescape(data, len, 1);
		buffer_add(buf, output);
		free(output);
		buffer_add(buf, "\"");

	}  else if(obj->is_array) {

		buffer_add(buf, "[");
		int i;
		for( i = 0; i!= obj->size; i++ ) {
			char* data = object_to_json(obj->get_index(obj,i));
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

	} else if(obj->is_hash) {
		buffer_add(buf, "{");
		object_iterator* itr = new_iterator(obj);
		object_node* tmp;
		while( (tmp = itr->next(itr)) ) {
			buffer_add(buf, "\"");
			buffer_add(buf, tmp->key);
			buffer_add(buf, "\":");
			char* data =  object_to_json(tmp->item);

#ifdef STRICT_JSON_WRITE
			buffer_add(buf, data);
#else
			if(strcmp(data,"null")) /* only add the string if it isn't null */
				buffer_add(buf, data);
#endif

			if(itr->has_next(itr))
				buffer_add(buf, ",");
			free(data);
		}
		free_iterator(itr);
		buffer_add(buf, "}");
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


void object_clear_type(object* obj) {
	if(obj == NULL) return;
	obj->is_string = 0;
	obj->is_hash	= 0;
	obj->is_array	= 0;
	obj->is_bool	= 0;
	obj->is_null	= 0;
}


void object_set_comment(object* obj, char* com) {
	assert(obj && com);
	obj->comment = strdup(com);
}



/* ---------------------------------------------------------------------- */
/* Iterator */

object_iterator* new_iterator(object* obj) {
	object_iterator* iter = safe_malloc(sizeof(object_iterator));
	iter->obj = obj;
	iter->current = obj->data;
	iter->next = &object_iterator_next;
	iter->has_next = &object_iterator_has_next;
	return iter;
}

object_node* object_iterator_next(object_iterator* itr) {
	assert( itr != NULL );

	object_node* tmp = itr->current;
	if(tmp == NULL) return NULL;
	itr->current = itr->current->next;

	return tmp;
}

void free_iterator(object_iterator* iter) { 
	if(iter == NULL) return;
	free(iter);
}

int object_iterator_has_next(object_iterator* itr) {
	assert(itr);
	if(itr->current) return 1;
	return 0;
}


