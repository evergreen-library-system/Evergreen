#include "osrf_system.h"

int main( int argc, char* argv[] ) {

	if( argc < 4 ) {
		fprintf(stderr, "Host, Bootstrap, and context required\n");
		return 1;
	}

	fprintf(stderr, "Loading OpenSRF host %s with bootstrap config %s "
			"and config context %s\n", argv[1], argv[2], argv[3] );

	osrfSystemBootstrap( argv[1], argv[2], argv[3] );

	return 0;
}


