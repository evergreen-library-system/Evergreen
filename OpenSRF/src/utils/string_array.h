#include <stdio.h>

#include "utils.h"
#include "logging.h"

#define STRING_ARRAY_MAX_SIZE 1024

#ifndef STRING_ARRAY_H
#define STRING_ARRAY_H

struct string_array_struct {
		char** array;	
		int size;
		int arr_size;
		int total_string_size;
};
typedef struct string_array_struct string_array;

string_array* init_string_array(int size);
void string_array_add(string_array*, char* string);

char* string_array_get_string(string_array* arr, int index);
void string_array_destroy(string_array*);

/* total size of all included strings */
int string_array_get_total_size(string_array* arr);


#endif
