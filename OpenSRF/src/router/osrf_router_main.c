#include "osrf_router.h"
#include "opensrf/osrfConfig.h"
#include "opensrf/utils.h"
#include "opensrf/logging.h"
#include <signal.h>

osrfRouter* __osrfRouter = NULL;

void routerSignalHandler( int signal ) {
	warning_handler("Received signal [%d], cleaning up...", signal );
	osrfConfigCleanup();
	osrfRouterFree(__osrfRouter);
	log_free();
}

static int __setupRouter( char* config, char* context );


int main( int argc, char* argv[] ) {

	if( argc < 3 ) {
		fatal_handler( "Usage: %s <path_to_config_file> <config_context>", argv[0] );
		exit(0);
	}

	char* config = strdup( argv[1] );
	char* context = strdup( argv[2] );
	init_proc_title( argc, argv );
	set_proc_title( "OpenSRF Router" );

	return __setupRouter( config, context );
	free(config);
	free(context);

}

int __setupRouter( char* config, char* context ) {

	fprintf(stderr, "Launching router with config %s and config context %s", config, context );
	osrfConfig* cfg = osrfConfigInit( config, context );
	osrfConfigSetDefaultConfig(cfg);


	char* server			= osrfConfigGetValue(NULL, "/transport/server");
	char* port				= osrfConfigGetValue(NULL, "/transport/port");
	char* username			= osrfConfigGetValue(NULL, "/transport/username");
	char* password			= osrfConfigGetValue(NULL, "/transport/password");
	char* resource			= osrfConfigGetValue(NULL, "/transport/resource");

	/* set up the logger */
	char* level = osrfConfigGetValue(NULL, "/loglevel");
	char* log_file = osrfConfigGetValue(NULL, "/logfile");

	int llevel = 1;
	if(level) llevel = atoi(level);

	if(!log_init( llevel, log_file )) 
		fprintf(stderr, "Unable to init logging, going to stderr...\n" );

	free(level);
	free(log_file);

	info_handler( "Router connecting as: server: %s port: %s "
			"user: %s resource: %s", server, port, username, resource );

	int iport = 0;
	if(port)	iport = atoi( port );

	osrfStringArray* tclients = osrfNewStringArray(4);
	osrfStringArray* tservers = osrfNewStringArray(4);
	osrfConfigGetValueList(NULL, tservers, "/trusted_domains/server" );
	osrfConfigGetValueList(NULL, tclients, "/trusted_domains/client" );

	int i;
	for( i = 0; i != tservers->size; i++ ) 
		info_handler( "Router adding trusted server: %s", osrfStringArrayGetString( tservers, i ) );

	for( i = 0; i != tclients->size; i++ ) 
		info_handler( "Router adding trusted client: %s", osrfStringArrayGetString( tclients, i ) );

	if( tclients->size == 0 || tservers->size == 0 )
		fatal_handler("We need trusted servers and trusted client to run the router...");

	osrfRouter* router = osrfNewRouter( server, 
			username, resource, password, iport, tclients, tservers );
	
	signal(SIGHUP,routerSignalHandler);
	signal(SIGINT,routerSignalHandler);
	signal(SIGTERM,routerSignalHandler);

	if( (osrfRouterConnect(router)) != 0 ) {
		fprintf(stderr, "!!!! Unable to connect router to jabber server %s... exiting", server );
		return -1;
	}

	free(server); free(port); 
	free(username); free(password); 

	__osrfRouter = router;
	daemonize();
	osrfRouterRun( router );

	return -1;
}


