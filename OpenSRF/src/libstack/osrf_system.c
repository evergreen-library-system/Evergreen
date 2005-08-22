#include "osrf_system.h"

transport_client* global_client;

transport_client* osrf_system_get_transport_client() {
	return global_client;
}

int osrf_system_bootstrap_client( char* config_file, char* contextnode ) {

	if( config_file == NULL )
		fatal_handler("No Config File Specified\n" );

	config_reader_init( "opensrf.bootstrap", config_file );	
	
	osrf_config_context = contextnode;

	char* log_file		= config_value( "opensrf.bootstrap", "//%s/logfile", contextnode );
	char* log_level	= config_value( "opensrf.bootstrap", "//%s/loglevel", contextnode );
	char* domain		= config_value( "opensrf.bootstrap", "//%s/domains/domain1", contextnode ); /* just the first for now */
	char* username		= config_value( "opensrf.bootstrap", "//%s/username", contextnode );
	char* password		= config_value( "opensrf.bootstrap", "//%s/passwd", contextnode );
	char* port			= config_value( "opensrf.bootstrap", "//%s/port", contextnode );
	char* unixpath		= config_value( "opensrf.bootstrap", "//%s/unixpath", contextnode );

	int llevel = 0;
	int iport = 0;
	if(port) iport = atoi(port);
	if(log_level) llevel = atoi(log_level);

	log_init( llevel, log_file );

	info_handler("Bootstrapping system with domain %s, port %d, and unixpath %s", domain, iport, unixpath );

	transport_client* client = client_init( domain, iport, unixpath, 0 );
	char buf[256];
	memset(buf,0,256);
	char* host = getenv("HOSTNAME");
	sprintf(buf, "client_%s_%d", host, getpid() );

	if(client_connect( client, username, password, buf, 10, AUTH_DIGEST )) {
		global_client = client;
	}

	free(log_level);
	free(log_file);
	free(domain);
	free(username);
	free(password);
	free(port);	
	free(unixpath);

	if(global_client)
		return 1;

	return 0;
}

int osrf_system_shutdown() {
	config_reader_free();
	log_free();
	client_disconnect( global_client );
	client_free( global_client );
	global_client = NULL;
	return 1;
}




