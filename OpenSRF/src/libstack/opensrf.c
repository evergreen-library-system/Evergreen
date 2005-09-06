#include "osrf_system.h"
#include "opensrf/utils.h"

int main( int argc, char* argv[] ) {

	if( argc < 4 ) {
		fprintf(stderr, "Host, Bootstrap, and context required\n");
		return 1;
	}

	fprintf(stderr, "Loading OpenSRF host %s with bootstrap config %s "
			"and config context %s\n", argv[1], argv[2], argv[3] );

	char* host = strdup( argv[1] );
	char* config = strdup( argv[2] );
	char* context = strdup( argv[3] );

	init_proc_title( argc, argv );
	set_proc_title( "opensrf system" );

	osrfSystemBootstrap( host, config, context );

	free(host);
	free(config);
	free(context);

	return 0;
}


