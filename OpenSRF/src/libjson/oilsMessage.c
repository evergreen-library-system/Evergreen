#include <stdio.h>
#include <string.h>
#include "json.h"


struct oils_method_struct {
	char* method_name;
	struct oils_param_struct* params;
	char (*to_json_string) (struct oils_method_struct*);
};
typedef struct oils_method_struct oils_method;

struct oils_param_struct {
	struct oils_param_struct* next;
	void* param;
	char (*to_json_string) (struct oils_param_struct*);
};
typedef struct oils_param_struct oils_param;


oils_method* oils_method_init( char* name );
int oils_method_add( oils_method*, oils_param* param );
oils_param* oils_param_init( void* param );
char* oils_method_to_json( oils_method* );
char* oils_param_to_json( oils_param* );
int main();



oils_method* oils_method_init( char* name ) {

	if( name == NULL )
		perror( "null method name" );

	oils_method* method = (oils_method*) malloc(sizeof(oils_method));
	memset( method, 0, sizeof(oils_method));

	method->method_name = strdup( name );

	return method;
}

int oils_method_add( oils_method* method, oils_param* param ) {

	if( method->params == NULL ) {
		method->params = param;
		return 1;
	}

	while(1) {
		if( method->params->next == NULL ) {
			method->params->next = param;
			return 1;
		}
		method->params = method->params->next;
	}

	return 0;
}

oils_param* oils_param_init( void* param ) {

	if( param == NULL )
		perror( "Null param" );

	oils_param* par = (oils_param*) malloc(sizeof(oils_param));
	memset( par, 0, sizeof(oils_param));

	par->param = param;
	return par;
}


json_object* oils_method_to_json( oils_method* method ) {
  struct json_object *method_obj;

}


json_object* oils_param_to_json( oils_param* param ) {

}

int main() {
	printf( "Hello world\n" );

}
