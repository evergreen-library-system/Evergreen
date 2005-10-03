#include "osrf_system.h"
#include "osrf_hash.h"
#include "osrf_list.h"

//static void _free(void* i) { free(i); }
//static void _hfree(char* c, void* i) { free(i); }

int main( int argc, char* argv[] ) {

	/*
	osrfHash* list = osrfNewHash();
	list->freeItem = _hfree;

	char* x = strdup("X");
	char* y = strdup("Y");
	char* z = strdup("Z");
	osrfHashSet( list, x, "test1" );
	osrfHashSet( list, y, "test2" );
	osrfHashSet( list, z, "test3" );

	char* q = (char*) osrfHashGet( list, "test1" );
	printf( "%s\n", q );

	q = (char*) osrfHashGet( list, "test2" );
	printf( "%s\n", q );

	q = (char*) osrfHashGet( list, "test3" );
	printf( "%s\n", q );

	osrfHashIterator* itr = osrfNewHashIterator(list);
	char* val;

	while( (val = osrfHashIteratorNext(itr)) )
		printf("Iterated item: %s\n", val );

	osrfHashIteratorReset(itr);
	while( (val = osrfHashIteratorNext(itr)) )
		printf("Iterated item: %s\n", val );

	printf( "Count: %lu\n", osrfHashGetCount(list));

	osrfHashIteratorFree(itr);

	osrfHashFree(list);

	exit(1);

	osrfList* list = osrfNewList();
	list->freeItem = _free;

	char* x = strdup("X");
	char* y = strdup("Y");
	char* z = strdup("Z");
	osrfListSet( list, x, 0 );
	osrfListSet( list, y, 2 );
	osrfListSet( list, z, 4 );

	char* q = (char*) osrfListGetIndex( list, 4 );
	printf( "%s\n", q );

	osrfListIterator* itr = osrfNewListIterator( list );
	char* val;

	while( (val = osrfListIteratorNext(itr)) ) 
		printf("Found val: %s\n", val );

	osrfListIteratorReset(itr);
	printf("\n");
	while( (val = osrfListIteratorNext(itr)) ) 
		printf("Found val: %s\n", val );

	osrfListIteratorFree(itr);

	printf( "Count: %lu\n", osrfListGetCount(list));

	osrfListFree(list);

	exit(1);
	*/



	if( argc < 4 ) {
		fprintf(stderr, "Usage: %s <host> <bootstrap_config> <config_context>\n", argv[0]);
		return 1;
	}

	fprintf(stderr, "Loading OpenSRF host %s with bootstrap config %s "
			"and config context %s\n", argv[1], argv[2], argv[3] );

	char* host = strdup( argv[1] );
	char* config = strdup( argv[2] );
	char* context = strdup( argv[3] );

	init_proc_title( argc, argv );
	set_proc_title( "OpenSRF System" );

	osrfSystemBootstrap( host, config, context );

	free(host);
	free(config);
	free(context);

	return 0;
}


