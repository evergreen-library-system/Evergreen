#include "opensrf/string_array.h"

/*
int main() {
	string_array* arr = init_string_array(1);
	string_array_add(arr, "1");
	fprintf(stderr,"adding 3\n");
	string_array_add(arr, "3");
	string_array_destroy(arr);
	return 0;
}
*/



string_array* init_string_array(int size) {
	if(size > STRING_ARRAY_MAX_SIZE)
		fatal_handler("init_string_array size is too large");

	string_array* arr = 
		(string_array*) safe_malloc(sizeof(string_array));
	arr->array = (char**) safe_malloc(size * sizeof(char*));
	arr->size = 0;
	arr->arr_size = size;
	return arr;
}


void string_array_add(string_array* arr, char* str) {
	if(arr == NULL || str == NULL ) {
		warning_handler("Invalid params to string_array_add");
		return;
	}

	if( strlen(str) < 1 ) return;

	arr->size++;
	//fprintf(stderr,"size is %d\n", arr->size);

	if( arr->size > STRING_ARRAY_MAX_SIZE ) 
		fatal_handler("string_array_add size is too large");

	/* if necessary, double capacity */
	if(arr->size >= arr->arr_size) {
		arr->arr_size *= 2;
		debug_handler("string_array: Doubling array size to %d", arr->arr_size);
		char** tmp = (char**) safe_malloc(arr->arr_size * sizeof(char*));
		int i;

		/* copy the string pointers over */
		for( i = 0; i!= arr->size; i++ ) 
			tmp[i] = arr->array[i];

		free(arr->array);
		arr->array = tmp;
	}

	//fprintf(stderr, "String is %s", str);
	//debug_handler("string_array_add: Adding string %s", str);
	//arr->array[arr->size - 1] = (char*) safe_malloc(strlen(str));
	arr->array[arr->size - 1] = strdup(str);
	//fprintf(stderr,"we have %s\n", arr->array[arr->size - 1]);
}

char* string_array_get_string(string_array* arr, int index) {
	if(!arr || index < 0 || index >= arr->size )
		return NULL;
	char* str = arr->array[index]; 

	if(str == NULL)
		warning_handler("Somehow we have a NULL string in the string array");

	//debug_handler("string_array_get_string: getting string %s", str);
	return str;
}


void string_array_destroy(string_array* arr) {
	if(!arr) return;
	int i;
	for( i = 0; i!= arr->size; i++ ) {
		if( arr->array[i] != NULL ) {
			//debug_handler("Freeing string from string array %s", arr->array[i]);
			free(arr->array[i]);
		}
	}
	free(arr->array);
	free(arr);
}
