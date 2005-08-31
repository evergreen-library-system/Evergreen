#include "osrf_system.h"

transport_client* __osrfGlobalTransportClient;

transport_client* osrf_system_get_transport_client() {
	return __osrfGlobalTransportClient;
}

int osrf_system_bootstrap_client( char* config_file, char* contextnode ) {
	return osrf_system_bootstrap_client_resc(config_file, contextnode, NULL);
}

int osrf_system_bootstrap_client_resc( char* config_file, char* contextnode, char* resource ) {

	if( !( config_file && contextnode ) && ! osrfConfigHasDefaultConfig() )
		fatal_handler("No Config File Specified\n" );

	if( config_file ) {
		osrfConfigCleanup();
		osrfConfig* cfg = osrfConfigInit( config_file, contextnode );
		osrfConfigSetDefaultConfig(cfg);
	}


	char* log_file		= osrfConfigGetValue( NULL, "/logfile");
	char* log_level	= osrfConfigGetValue( NULL, "/loglevel" );
	osrfStringArray* arr = osrfNewStringArray(8);
	osrfConfigGetValueList(NULL, arr, "/domains/domain");
	char* username		= osrfConfigGetValue( NULL, "/username" );
	char* password		= osrfConfigGetValue( NULL, "/passwd" );
	char* port			= osrfConfigGetValue( NULL, "/port" );
	char* unixpath		= osrfConfigGetValue( NULL, "/unixpath" );

	char* domain = osrfStringArrayGetString( arr, 0 ); /* just the first for now */
	osrfStringArrayFree(arr);


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
		__osrfGlobalTransportClient = client;
	}

	free(log_level);
	free(log_file);
	free(username);
	free(password);
	free(port);	
	free(unixpath);

	if(__osrfGlobalTransportClient)
		return 1;

	return 0;
}

int osrf_system_disconnect_client() {
	client_disconnect( __osrfGlobalTransportClient );
	client_free( __osrfGlobalTransportClient );
	__osrfGlobalTransportClient = NULL;
	return 0;
}

int osrf_system_shutdown() {
	osrfConfigCleanup();
	osrf_system_disconnect_client();
	osrf_settings_free_host_config(NULL);
	log_free();
	return 1;
}




