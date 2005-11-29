#include "string_array.h"

osrfStringArray* osrfNewStringArray(int size) {
	return init_string_array(size);
}

string_array* init_string_array(int size) {
	if(size > STRING_ARRAY_MAX_SIZE)
		osrfLogError("init_string_array size is too large");

	string_array* arr = 
		(string_array*) safe_malloc(sizeof(string_array));
	arr->array = (char**) safe_malloc(size * sizeof(char*));
	arr->size = 0;
	arr->arr_size = size;
	return arr;
}


void osrfStringArrayAdd(osrfStringArray* arr, char* string) {
	string_array_add(arr, string);
}

void string_array_add(string_array* arr, char* str) {
	if(arr == NULL || str == NULL ) return;
	if( strlen(str) < 1 ) return;

	arr->size++;

	if( arr->size > STRING_ARRAY_MAX_SIZE ) 
		osrfLogError("string_array_add size is too large");

	/* if necessary, double capacity */
	if(arr->size >= arr->arr_size) {
		arr->arr_size *= 2;
		char** tmp = (char**) safe_malloc(arr->arr_size * sizeof(char*));
		int i;

		/* copy the string pointers over */
		for( i = 0; i!= arr->size; i++ ) 
			tmp[i] = arr->array[i];

		free(arr->array);
		arr->array = tmp;
	}

	arr->array[arr->size - 1] = strdup(str);
}

char* osrfStringArrayGetString(osrfStringArray* arr, int index) {
	return string_array_get_string(arr, index);
}

char* string_array_get_string(string_array* arr, int index) {
	if(!arr || index < 0 || index >= arr->size ) return NULL;
	return arr->array[index]; 
}


void osrfStringArrayFree(osrfStringArray* arr) {
	string_array_destroy(arr);
}

void string_array_destroy(string_array* arr) {
	if(arr) {
		int i = 0;
		while( i < arr->size ) free(arr->array[i++]);
		free(arr->array);
		free(arr);
	}
}


int osrfStringArrayContains( osrfStringArray* arr, char* string ) {
	if(!(arr && string)) return 0;
	
	int i;
	for( i = 0; i != arr->size; i++ ) {
		char* str = osrfStringArrayGetString(arr, i);
		if(str) {
			if(!strcmp(str, string)) return 1;
		}
	}

	return 0;
}

