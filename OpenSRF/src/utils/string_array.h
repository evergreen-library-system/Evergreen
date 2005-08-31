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
typedef struct string_array_struct osrfStringArray;

osrfStringArray* init_string_array(int size);
osrfStringArray* osrfNewStringArray(int size);

void string_array_add(osrfStringArray*, char* string);
void osrfStringArrayAdd(osrfStringArray*, char* string);

char* string_array_get_string(osrfStringArray* arr, int index);
char* osrfStringArrayGetString(osrfStringArray* arr, int index);


void string_array_destroy(osrfStringArray*);
void osrfStringArrayFree(osrfStringArray*);

/* total size of all included strings */
int string_array_get_total_size(osrfStringArray* arr);


#endif
