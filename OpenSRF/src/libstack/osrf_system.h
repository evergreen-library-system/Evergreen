#ifndef OSRF_SYSTEM_H
#define OSRF_SYSTEM_H

#include "opensrf/transport_client.h"
#include "opensrf/utils.h"
#include "opensrf/logging.h"
#include "osrf_settings.h"
#include "osrfConfig.h"


/** Connects to jabber.  Returns 1 on success, 0 on failure 
	contextnode is the location in the config file where we collect config info
*/


int osrf_system_bootstrap_client( char* config_file, char* contextnode );

/* bootstraps a client adding the given resource string to the host/pid, etc. resource string */
/**
  Sets up the global connection.
  @param configFile The OpenSRF bootstrap config file
  @param contextNode The location in the config file where we'll find the necessary info
  @param resource The login resource.  If NULL a default will be created
  @return 1 on successs, 0 on failure.
  */
int osrfSystemBootstrapClientResc( char* configFile, char* contextNode, char* resource );
int osrf_system_bootstrap_client_resc( char* config_file, char* contextnode, char* resource );

/**
  Bootstrap the server.
  @param hostname The name of this host.  This is the name that will be used to 
	load the settings.
  @param configfile The OpenSRF bootstrap config file
  @param contextnode The config context
  @return 0 on success, -1 on error
  */
int osrfSystemBootstrap( char* hostName, char* configfile, char* contextNode );

transport_client* osrfSystemGetTransportClient();
transport_client* osrf_system_get_transport_client();

/* disconnects and destroys the current client connection */
int osrf_system_disconnect_client();
int osrf_system_shutdown(); 

#endif
