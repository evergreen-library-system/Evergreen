#include "osrf_system.h"
#include <signal.h>
#include "osrf_application.h"
#include "osrf_prefork.h"

static int _osrfSystemInitCache( void );

static transport_client* osrfGlobalTransportClient = NULL;

transport_client* osrfSystemGetTransportClient( void ) {
	return osrfGlobalTransportClient;
}

void osrfSystemIgnoreTransportClient() {
	osrfGlobalTransportClient = NULL;
}

transport_client* osrf_system_get_transport_client( void ) {
	return osrfGlobalTransportClient;
}

int osrf_system_bootstrap_client( char* config_file, char* contextnode ) {
	return osrf_system_bootstrap_client_resc(config_file, contextnode, NULL);
}

int osrfSystemBootstrapClientResc( char* config_file, char* contextnode, char* resource ) {
	return osrf_system_bootstrap_client_resc( config_file, contextnode, resource );
}


static int _osrfSystemInitCache( void ) {

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
	
					osrfLogDebug( OSRF_LOG_MARK, "Server exiting for app %s and library %s\n", appname, libfile );
					exit(0);
				}
			} // language == c
		} 
	}

	/** daemonize me **/

	/* background and let our children do their thing */
	daemonize();
    while(1) {
        errno = 0;
        pid_t pid = wait(NULL);
        if(-1 == pid) {
            if(errno == ECHILD)
                osrfLogError(OSRF_LOG_MARK, "We have no more live services... exiting");
            else
                osrfLogError(OSRF_LOG_MARK, "Exiting top-level system loop with error: %s", strerror(errno));
            break;
        } else {
            osrfLogError(OSRF_LOG_MARK, "We lost a top-level service process with PID %d", pid);
        }
    }


	return 0;
}

int osrf_system_bootstrap_client_resc( char* config_file, char* contextnode, char* resource ) {

	int failure = 0;

	if(osrfSystemGetTransportClient()) {
		osrfLogInfo(OSRF_LOG_MARK, "Client is already bootstrapped");
		return 1; /* we already have a client connection */
	}

	if( !( config_file && contextnode ) && ! osrfConfigHasDefaultConfig() ) {
		osrfLogError( OSRF_LOG_MARK, "No Config File Specified\n" );
		return -1;
	}

	if( config_file ) {
		osrfConfig* cfg = osrfConfigInit( config_file, contextnode );
		if(cfg)
			osrfConfigSetDefaultConfig(cfg);
		else
			return 0;   /* Can't load configuration?  Bail out */
	}


	char* log_file		= osrfConfigGetValue( NULL, "/logfile");
	char* log_level		= osrfConfigGetValue( NULL, "/loglevel" );
	osrfStringArray* arr	= osrfNewStringArray(8);
	osrfConfigGetValueList(NULL, arr, "/domains/domain");

	char* username		= osrfConfigGetValue( NULL, "/username" );
	char* password		= osrfConfigGetValue( NULL, "/passwd" );
	char* port		= osrfConfigGetValue( NULL, "/port" );
	char* unixpath		= osrfConfigGetValue( NULL, "/unixpath" );
	char* facility		= osrfConfigGetValue( NULL, "/syslog" );
	char* actlog		= osrfConfigGetValue( NULL, "/actlog" );

	if(!log_file) {
		fprintf(stderr, "No log file specified in configuration file %s\n",
			   config_file);
		free(log_level);
		free(username);
		free(password);
		free(port);
		free(unixpath);
		free(facility);
		free(actlog);
		return -1;
	}

	/* if we're a source-client, tell the logger */
	char* isclient = osrfConfigGetValue(NULL, "/client");
	if( isclient && !strcasecmp(isclient,"true") )
		osrfLogSetIsClient(1);
	free(isclient);

	int llevel = 0;
	int iport = 0;
	if(port) iport = atoi(port);
	if(log_level) llevel = atoi(log_level);

	if(!strcmp(log_file, "syslog")) {
		osrfLogInit( OSRF_LOG_TYPE_SYSLOG, contextnode, llevel );
		osrfLogSetSyslogFacility(osrfLogFacilityToInt(facility));
		if(actlog) osrfLogSetSyslogActFacility(osrfLogFacilityToInt(actlog));

	} else {
		osrfLogInit( OSRF_LOG_TYPE_FILE, contextnode, llevel );
		osrfLogSetFile( log_file );
	}


	/* Get a domain, if one is specified */
	const char* domain = osrfStringArrayGetString( arr, 0 ); /* just the first for now */
	if(!domain) {
		fprintf(stderr, "No domain specified in configuration file %s\n", config_file);
		osrfLogError( OSRF_LOG_MARK, "No domain specified in configuration file %s\n", config_file);
		failure = 1;
	}

	if(!username) {
		fprintf(stderr, "No username specified in configuration file %s\n", config_file);
		osrfLogError( OSRF_LOG_MARK, "No username specified in configuration file %s\n", config_file);
		failure = 1;
	}

	if(!password) {
		fprintf(stderr, "No password specified in configuration file %s\n", config_file);
		osrfLogError( OSRF_LOG_MARK, "No password specified in configuration file %s\n", config_file);
		failure = 1;
	}

	if((iport <= 0) && !unixpath) {
		fprintf(stderr, "No unixpath or valid port in configuration file %s\n", config_file);
		osrfLogError( OSRF_LOG_MARK, "No unixpath or valid port in configuration file %s\n",
			config_file);
		failure = 1;
	}

	if (failure) {
		osrfStringArrayFree(arr);
		free(log_level);
		free(username);
		free(password);
		free(port);
		free(unixpath);
		free(facility);
		free(actlog);
		return 0;
	}

	osrfLogInfo( OSRF_LOG_MARK, "Bootstrapping system with domain %s, port %d, and unixpath %s",
		domain, iport, unixpath ? unixpath : "(none)" );
	transport_client* client = client_init( domain, iport, unixpath, 0 );

	const char* host;
	host = getenv("HOSTNAME");

	char tbuf[32];
	tbuf[0] = '\0';
	snprintf(tbuf, 32, "%f", get_timestamp_millis());

	if(!host) host = "";
	if(!resource) resource = "";

	int len = strlen(resource) + 256;
	char buf[len];
	buf[0] = '\0';
	snprintf(buf, len - 1, "%s_%s_%s_%ld", resource, host, tbuf, (long) getpid() );

	if(client_connect( client, username, password, buf, 10, AUTH_DIGEST )) {
		/* child nodes will leak the parents client... but we can't free
			it without disconnecting the parents client :( */
		osrfGlobalTransportClient = client;
	}

	osrfStringArrayFree(arr);
	free(actlog);
	free(facility);
	free(log_level);
	free(log_file);
	free(username);
	free(password);
	free(port);	
	free(unixpath);

	if(osrfGlobalTransportClient)
		return 1;

	return 0;
}

int osrf_system_disconnect_client( void ) {
	client_disconnect( osrfGlobalTransportClient );
	client_free( osrfGlobalTransportClient );
	osrfGlobalTransportClient = NULL;
	return 0;
}

int osrf_system_shutdown( void ) {
	osrfConfigCleanup();
	osrf_system_disconnect_client();
	osrf_settings_free_host_config(NULL);
	osrfAppSessionCleanup();
	osrfLogCleanup();
	return 1;
}




