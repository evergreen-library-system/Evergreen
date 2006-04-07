#include "osrf_system.h"
#include <signal.h>
#include "osrf_application.h"
#include "osrf_prefork.h"

void __osrfSystemSignalHandler( int sig );

transport_client* __osrfGlobalTransportClient = NULL;

transport_client* osrfSystemGetTransportClient() {
	return __osrfGlobalTransportClient;
}

transport_client* osrf_system_get_transport_client() {
	return __osrfGlobalTransportClient;
}

int osrf_system_bootstrap_client( char* config_file, char* contextnode ) {
	return osrf_system_bootstrap_client_resc(config_file, contextnode, NULL);
}

int osrfSystemBootstrapClientResc( char* config_file, char* contextnode, char* resource ) {
	return osrf_system_bootstrap_client_resc( config_file, contextnode, resource );
}


int _osrfSystemInitCache() {

	jsonObject* cacheServers = osrf_settings_host_value_object("/cache/global/servers/server");
	char* maxCache = osrf_settings_host_value("/cache/global/max_cache_time");

	if( cacheServers && maxCache) {

		if( cacheServers->type == JSON_ARRAY ) {
			int i;
			char* servers[cacheServers->size];
			for( i = 0; i != cacheServers->size; i++ ) {
				servers[i] = jsonObjectGetString( jsonObjectGetIndex(cacheServers, i) );
				osrfLogInfo( OSRF_LOG_MARK, "Adding cache server %s", servers[i]);
			}
			osrfCacheInit( servers, cacheServers->size, atoi(maxCache) );

		} else {
			char* servers[] = { jsonObjectGetString(cacheServers) };		
			osrfLogInfo( OSRF_LOG_MARK, "Adding cache server %s", servers[0]);
			osrfCacheInit( servers, 1, atoi(maxCache) );
		}

	} else {
		osrfLogError( OSRF_LOG_MARK,  "Missing config value for /cache/global/servers/server _or_ "
			"/cache/global/max_cache_time");
	}

	return 0;
}


int osrfSystemBootstrap( char* hostname, char* configfile, char* contextNode ) {
	if( !(hostname && configfile && contextNode) ) return -1;

	/* first we grab the settings */
	if(!osrfSystemBootstrapClientResc(configfile, contextNode, "settings_grabber" )) {
		osrfLogError( OSRF_LOG_MARK, "Unable to bootstrap");
		return -1;
	}

	osrf_settings_retrieve(hostname);
	osrf_system_disconnect_client();

	jsonObject* apps = osrf_settings_host_value_object("/activeapps/appname");
	osrfStringArray* arr = osrfNewStringArray(8);
	
	_osrfSystemInitCache();

	if(apps) {
		int i = 0;

		if(apps->type == JSON_STRING) {
			osrfStringArrayAdd(arr, jsonObjectGetString(apps));

		} else {
			jsonObject* app;
			while( (app = jsonObjectGetIndex(apps, i++)) ) 
				osrfStringArrayAdd(arr, jsonObjectGetString(app));
		}

		char* appname = NULL;
		i = 0;
		while( (appname = osrfStringArrayGetString(arr, i++)) ) {

			char* lang = osrf_settings_host_value("/apps/%s/language", appname);

			if(lang && !strcasecmp(lang,"c"))  {

				char* libfile = osrf_settings_host_value("/apps/%s/implementation", appname);
		
				if(! (appname && libfile) ) {
					osrfLogWarning( OSRF_LOG_MARK, "Missing appname / libfile in settings config");
					continue;
				}

				osrfLogInfo( OSRF_LOG_MARK, "Launching application %s with implementation %s", appname, libfile);
		
				int pid;
		
				if( (pid = fork()) ) { 
					// storage pid in local table for re-launching dead children...
					osrfLogInfo( OSRF_LOG_MARK, "Launched application child %d", pid);
	
				} else {
		
					fprintf(stderr, " * Running application %s\n", appname);
					if( osrfAppRegisterApplication( appname, libfile ) == 0 ) 
						osrf_prefork_run(appname);
	
					osrfLogDebug( OSRF_LOG_MARK, "Server exiting for app %s and library %s", appname, libfile );
					exit(0);
				}
			} // language == c
		} 
	}

	/** daemonize me **/

	/* background and let our children do their thing */
	daemonize();
	while(1) {
		signal(SIGCHLD, __osrfSystemSignalHandler);
		sleep(10000);
	}
	
	return 0;
}

int osrf_system_bootstrap_client_resc( char* config_file, char* contextnode, char* resource ) {

	if( !( config_file && contextnode ) && ! osrfConfigHasDefaultConfig() ) {
		osrfLogError( OSRF_LOG_MARK, "No Config File Specified\n" );
		return -1;
	}

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
	char* facility		= osrfConfigGetValue( NULL, "/syslog" );
	char* actlog		= osrfConfigGetValue( NULL, "/actlog" );

	char* domain = strdup(osrfStringArrayGetString( arr, 0 )); /* just the first for now */
	osrfStringArrayFree(arr);


	int llevel = 0;
	int iport = 0;
	if(port) iport = atoi(port);
	if(log_level) llevel = atoi(log_level);

	if(!log_file) { fprintf(stderr, "Log file needed\n"); return -1; }

	if(!strcmp(log_file, "syslog")) {
		osrfLogInit( OSRF_LOG_TYPE_SYSLOG, contextnode, llevel );
		osrfLogSetSyslogFacility(osrfLogFacilityToInt(facility));
		if(actlog) osrfLogSetSyslogActFacility(osrfLogFacilityToInt(actlog));

	} else {
		osrfLogInit( OSRF_LOG_TYPE_FILE, contextnode, llevel );
		osrfLogSetFile( log_file );
	}

	osrfLogInfo( OSRF_LOG_MARK, "Bootstrapping system with domain %s, port %d, and unixpath %s", domain, iport, unixpath );

	transport_client* client = client_init( domain, iport, unixpath, 0 );

	char* host;
	host = getenv("HOSTNAME");

	if(!host) host = "";
	if(!resource) resource = "";

	int len = strlen(resource) + 256;
	char buf[len];
	memset(buf,0,len);
	snprintf(buf, len - 1, "%s_%s_%d", resource, host, getpid() );
	
	if(client_connect( client, username, password, buf, 10, AUTH_DIGEST )) {
		/* child nodes will leak the parents client... but we can't free
			it without disconnecting the parents client :( */
		__osrfGlobalTransportClient = client;
	}

	free(actlog);
	free(facility);
	free(log_level);
	free(log_file);
	free(username);
	free(password);
	free(port);	
	free(unixpath);
	free(domain);

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
	osrfAppSessionCleanup();
	osrfLogCleanup();
	return 1;
}




void __osrfSystemSignalHandler( int sig ) {

	pid_t pid;
	int status;

	while( (pid = waitpid(-1, &status, WNOHANG)) > 0) {
		osrfLogWarning( OSRF_LOG_MARK, "We lost child %d", pid);
	}

	/** relaunch the server **/
}


