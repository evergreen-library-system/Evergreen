#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "libjson/json.h"


int main(int argc, char **argv)
{


	json *oils_method, *oils_param;

	/* build the param array */
	oils_param = json_object_new_array();
	json_object_array_add(oils_param, json_object_new_int(1));
	json_object_array_add(oils_param, 
			json_object_new_string("<?xml version='1.0'?><oils:root>hi</oils:root>"));

	/* build the method and add the params */
	oils_method = json_object_new_object();
	json_object_object_add( oils_method, "name", json_object_new_string("add"));
	json_object_object_add( oils_method, "params", oils_param );

	/* print the whole method */
	printf( "oils_method: %s\n", json_object_to_json_string( oils_method ) );

	/* retrieve and print the params */
	json* params = json_object_object_get(oils_method, "params" );
	printf( "Params:\n" );
	printf( "%d\n", json_object_get_int( json_object_array_get_idx( params, 0 )));
	printf( "%s\n", json_object_get_string( json_object_array_get_idx( params, 1 )));


	return 0;
}
