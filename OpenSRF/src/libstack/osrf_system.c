#include "osrf_system.h"

transport_client* global_client;

transport_client* osrf_system_get_transport_client() {
	return global_client;
}

int osrf_system_bootstrap_client( char* config_file ) {

	if( config_file == NULL )
		fatal_handler("No Config File Specified\n" );

	config_reader_init( "opensrf.bootstrap", config_file );	

	char* log_file		= config_value( "opensrf.bootstrap", "//logs/client" );
	char* log_level	= config_value( "opensrf.bootstrap", "//bootstrap/debug" );
	char* domain		= config_value( "opensrf.bootstrap", "//bootstrap/domains/domain1" ); /* just the first for now */
	char* username		= config_value( "opensrf.bootstrap", "//bootstrap/username" );
	char* password		= config_value( "opensrf.bootstrap", "//bootstrap/passwd" );
	char* port			= config_value( "opensrf.bootstrap", "//bootstrap/port" );

	int llevel = 0;
	int iport = atoi(port);

	if			(!strcmp(log_level, "ERROR"))	llevel = LOG_ERROR;
	else if	(!strcmp(log_level, "WARN"))	llevel = LOG_WARNING;
	else if	(!strcmp(log_level, "INFO"))	llevel = LOG_INFO;
	else if	(!strcmp(log_level, "DEBUG"))	llevel = LOG_DEBUG;

	log_init( llevel, log_file );

	// XXX config values 
	transport_client* client = client_init( domain, iport, 0 );
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




