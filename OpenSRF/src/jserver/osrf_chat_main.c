#include "osrf_chat.h"
#include "opensrf/osrfConfig.h"
#include <stdio.h>
#include "opensrf/log.h"
#include <syslog.h>


int main( int argc, char* argv[] ) {

	if( argc < 3 ) {
		fprintf( stderr, "Usage: %s <config_file> <config_context>\n", argv[0] );
		exit(0);
	}

	osrfConfig* cfg = osrfConfigInit( argv[1], argv[2] );
	if( !cfg ) {
		fprintf( stderr, "Unable to load configuration file %s\n", argv[1] );
		return -1;
	}

	init_proc_title( argc, argv );
	set_proc_title( "ChopChop" );

	char* domain		= osrfConfigGetValue(cfg, "/domain");
	char* secret		= osrfConfigGetValue(cfg, "/secret");
	char* sport			= osrfConfigGetValue(cfg, "/port");
	char* s2sport		= osrfConfigGetValue(cfg, "/s2sport");
	char* listenaddr	= osrfConfigGetValue(cfg, "/listen_address");
	char* llevel		= osrfConfigGetValue(cfg, "/loglevel");
	char* lfile			= osrfConfigGetValue(cfg, "/logfile");
	char* facility		= osrfConfigGetValue(cfg, "/syslog");

	if(!domain)
		fputs( "No domain specified in configuration file\n", stderr );
	
	if(!secret)
		fputs( "No secret specified in configuration file\n", stderr );
	
	if(!sport)
		fputs( "No port specified in configuration file\n", stderr );
	
	if(!listenaddr)
		fputs( "No listen_address specified in configuration file\n", stderr );
	
	if(!llevel)
		fputs( "No loglevel specified in configuration file\n", stderr );
	
	if(!lfile)
		fputs( "No logfile specified in configuration file\n", stderr );
	
	if(!s2sport)
		fputs( "No s2sport specified in configuration file\n", stderr );
	
	if(!(domain && secret && sport && listenaddr && llevel && lfile && s2sport)) {
		fprintf(stderr, "Configuration error for ChopChop - missing key ingredient\n");
		return -1;
	}

	int port = atoi(sport);
	int s2port = atoi(s2sport);
	int level = atoi(llevel);

	if(!strcmp(lfile, "syslog")) {
		osrfLogInit( OSRF_LOG_TYPE_SYSLOG, "chopchop", level );
		osrfLogSetSyslogFacility(osrfLogFacilityToInt(facility));

	} else {
		osrfLogInit( OSRF_LOG_TYPE_FILE, "chopchop", level );
		osrfLogSetFile( lfile );
	}

	fprintf(stderr, "Attempting to launch ChopChop with:\n"
			"domain: %s\nport: %s\nlisten address: %s\nlog level: %s\nlog file: %s\n",
			domain, sport, listenaddr, llevel, lfile );

	osrfChatServer* server = osrfNewChatServer(domain, secret, s2port);

	if( osrfChatServerConnect( server, port, s2port, listenaddr ) != 0 ) {
		osrfLogError( OSRF_LOG_MARK, "ChopChop unable to bind to port %d on %s", port, listenaddr);
		return -1;
	}

	daemonize();
	osrfChatServerWait( server );

	osrfChatServerFree( server );
	osrfConfigFree(cfg);

	return 0;

}

