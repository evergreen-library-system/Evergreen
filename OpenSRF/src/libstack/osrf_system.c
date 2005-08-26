#include "osrf_system.h"

transport_client* global_client;
char* system_config = NULL;
char* config_context = NULL;
char* bootstrap_config = NULL;

transport_client* osrf_system_get_transport_client() {
	return global_client;
}


char* osrf_get_config_context() {
	return config_context;
}

char* osrf_get_bootstrap_config() {
	return bootstrap_config;
}

int osrf_system_bootstrap_client( char* config_file, char* contextnode ) {
	return osrf_system_bootstrap_client_resc(config_file, contextnode, NULL);
}

int osrf_system_bootstrap_client_resc( char* config_file, char* contextnode, char* resource ) {

	if( !config_file || !contextnode )
		fatal_handler("No Config File Specified\n" );

	config_context = strdup(contextnode);
	bootstrap_config = strdup(config_file);

	debug_handler("Bootstrapping client with config %s and context node %s", config_file, contextnode);

	config_reader_init( "opensrf.bootstrap", config_file );	

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

	char* host = getenv("HOSTNAME");

	if(!resource) resource = "";
	int len = strlen(resource) + 256;
	char buf[len];
	memset(buf,0,len);
	snprintf(buf, len - 1, "opensrf_%s_%s_%d", resource, host, getpid() );
	
	if(client_connect( client, username, password, buf, 10, AUTH_DIGEST )) {
		/* child nodes will leak the parents client... but we can't free
			it without disconnecting the parents client :( */
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

int osrf_system_disconnect_client() {
	client_disconnect( global_client );
	client_free( global_client );
	global_client = NULL;
	return 0;
}

int osrf_system_shutdown() {
	config_reader_free();
	osrf_system_disconnect_client();
	//free(system_config);
	//free(config_context);
	osrf_settings_free_host_config(NULL);
	log_free();
	return 1;
}




